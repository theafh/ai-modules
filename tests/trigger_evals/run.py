#!/usr/bin/env python3
"""Trigger-eval runner for the skills shipped in this repo.

Measures whether a skill's `description:` makes the agent load that skill for a
realistic message, on Claude and on Cursor. Both vendors run the same eval sets
and are graded the same way into one result schema.

Deployed mode measures the copy of the skill that `make deploy` installed under
the run vendor's native root: `~/.claude/skills/<name>/` on Claude and
`~/.cursor/skills/<name>/` on Cursor. Claude records a load as a
`Skill(skill="<name>", ...)` call or a `Read` of a `/<name>/SKILL.md`; Cursor
records it as a `tool_call` whose `readToolCall.args.path` ends in
`/<name>/SKILL.md`, under its native root or a compatibility root. Each worker
starts in its own fresh directory outside the checkout and any git repository,
so the repository's instruction files never load. A skill missing from the run
vendor's deployed tree exits with a named unavailability and writes no score.
`--force-uuid` is the only entry to skill-creator's UUID-proxy path, which is
Claude-only because that runner drives `claude -p`.

Usage:

    python3 tests/trigger_evals/run.py \\
      --eval-set tests/trigger_evals/wiki.json \\
      --skill wiki \\
      [--vendor {claude,cursor}] \\
      [--family wiki,wiki_import,wiki_fix,wiki_wrapup] \\
      [--model opus|auto|''] [--effort high|<level>|''] \\
      [--runs-per-query 3] [--timeout 45] [--workers 4]

`--vendor` defaults to `cursor`. `--workers` defaults to
`vendor.DEFAULT_PARALLEL_WORKERS`. A deployed-mode Claude worker runs on the
vendor's worker model and effort (`opus` at `high`); `--force-uuid` hands its
run to skill-creator's own runner, which applies no effort, so that run records
the empty effort.

Outputs `results.json` and `run.log` under
`tests/trigger_evals/results/<skill>/<timestamp>/`.

Eval-set schema (one of):

    {"query": "...", "expected_skill": "wiki" | "wiki_import" | ... | null}

Or backward-compatible:

    {"query": "...", "should_trigger": true | false}

A `should_trigger: true` infers `expected_skill = <--skill>`. A
`should_trigger: false` infers `expected_skill = null`. The
backward-compat path can't express "trigger a sibling instead" — to
exercise that, switch to the explicit `expected_skill` form.

Grading reports two metrics per run:

- **Precise**: did the FIRST tool the model invoked load the exact
  expected skill? (`Skill(skill="<expected>")` or `Read(.../<expected>/SKILL.md)`).
- **Family**: did the first tool load ANY skill in the family list?
  (Useful when the eval set says "expected_skill: wiki_import" but a
  query is genuinely ambiguous between wiki and wiki_import — a
  family hit captures that the model correctly recognized
  wiki-territory even if it picked the sibling.)

When `expected_skill: null`, both metrics flip: precise = "no skill
was loaded"; family = "no skill from the family was loaded".

Per-query pass uses a 50% threshold over `runs-per-query` runs.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import vendor  # noqa: E402  (shared vendor helper; tests/ is gitignored)

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SKC_RUN_EVAL = (Path.home() / ".claude" / "plugins" / "marketplaces"
                / "claude-plugins-official" / "plugins" / "skill-creator"
                / "skills" / "skill-creator")

# Pre-compiled patterns for extracting the triggered-skill name from the
# accumulated stream-event JSON of a Skill / Read tool_use.
SKILL_INPUT_NAME_RE = re.compile(r'"skill"\s*:\s*"([^"]+)"')
READ_PATH_RE = re.compile(r'"file_path"\s*:\s*"([^"]+)"')
READ_PATH_SKILL_RE = re.compile(r'/([^/]+)/SKILL\.md$')

# Sentinel returned by run_one_deployed when the worker did NOT complete — it
# timed out or crashed before its first-tool decision — as distinct from a clean
# run that deliberately loaded no family skill (None). A worker failure must
# never count as a deliberate "no trigger", or an `expected_skill: null` query
# would false-pass on a dead worker.
WORKER_FAILED = "__worker_failed__"


def deployed_skill_root(skill_name: str, vendor_name: str) -> Path | None:
    """Return the skill under the vendor's native root, where deploy writes it."""

    p = vendor.skill_roots(vendor_name)[0] / skill_name
    if (p / "SKILL.md").is_file():
        return p
    return None


def auto_derive_family(source_skill_path: Path) -> list[str]:
    """Derive the family from sibling skill directories that share a name
    root with the given skill. The root is the part before the first
    underscore (e.g. `wiki` for `wiki_import`, `format` for `format_python`).
    Family = {root} ∪ {root_*} restricted to skills that actually exist on
    disk under the same plugin's `skills/` parent.

    Examples:
      wiki         → [wiki, wiki_fix, wiki_import, wiki_wrapup]
      wiki_import  → [wiki, wiki_fix, wiki_import, wiki_wrapup]
      format_python → [format_markdown, format_python, format_rust]
      git_commit   → [git_commit]   (no `git_*` siblings)
      spr          → [spr]          (no `spr_*` siblings)
    """
    parent = source_skill_path.parent
    if not parent.is_dir():
        return [source_skill_path.name]
    own = source_skill_path.name
    siblings = {d.name for d in parent.iterdir()
                if d.is_dir() and (d / "SKILL.md").is_file()}
    root = own.split("_", 1)[0]
    family = sorted(
        s for s in siblings
        if s == root or s.startswith(root + "_")
    )
    return family or [own]


def parse_description_from_skill_md(skill_md: Path) -> str:
    text = skill_md.read_text()
    in_fm = False
    capturing_block = False
    parts: list[str] = []
    for line in text.splitlines():
        if line.strip() == "---":
            if not in_fm:
                in_fm = True
                continue
            break
        if not in_fm:
            continue
        if capturing_block:
            if line.startswith("  "):
                parts.append(line[2:])
                continue
            break
        if line.startswith("description:"):
            after = line[len("description:"):].strip()
            if after in ("|", ">"):
                capturing_block = True
                continue
            parts.append(after)
            break
    return " ".join(s.strip() for s in parts).strip()


def detect_drift(deployed_md: Path, source_md: Path | None) -> str | None:
    if source_md is None or not source_md.is_file():
        return None
    if parse_description_from_skill_md(deployed_md) != parse_description_from_skill_md(source_md):
        return (f"WARNING: deployed description differs from source.\n"
                f"  deployed: {deployed_md}\n"
                f"  source:   {source_md}\n"
                f"  Run `make deploy` to bring them back in sync, or "
                f"the eval will measure stale deployed text.")
    return None


def normalize_eval_entry(entry: dict, target_skill: str) -> dict:
    """Map both schemas onto a uniform internal entry with `expected_skill`."""
    if "expected_skill" in entry:
        return {"query": entry["query"], "expected_skill": entry["expected_skill"]}
    if "should_trigger" in entry:
        if entry["should_trigger"]:
            return {"query": entry["query"], "expected_skill": target_skill}
        return {"query": entry["query"], "expected_skill": None}
    raise ValueError(f"eval entry missing expected_skill / should_trigger: {entry}")


def _fresh_worker_dir() -> Path:
    """Create a worker directory outside the checkout and any git repository."""

    base = Path(tempfile.gettempdir()).resolve()
    repo = REPO_ROOT.resolve()
    if base == repo or repo in base.parents:
        base = Path("/tmp")
    try:
        inside = (
            subprocess.run(
                ["git", "-C", str(base), "rev-parse", "--is-inside-work-tree"],
                capture_output=True,
                text=True,
            ).stdout.strip()
            == "true"
        )
    except OSError:
        inside = False
    if inside:
        base = Path("/tmp")
    return Path(tempfile.mkdtemp(prefix="trigger_evals_worker_", dir=str(base)))


def _read_worker(
    proc: subprocess.Popen, timeout: int, vendor_name: str
) -> str | None:
    """Read one worker's stream and return its first-tool decision.

    Claude reads `stream_event` records. Cursor reads the `started` `tool_call`
    record's tool kind and `args`, which the model chooses before the call
    executes. A `result` record with `is_error` true is a failed worker on both
    vendors. A clean exit before any tool is a no-trigger; every other ending is
    a failed worker.
    """

    decision_made = False
    triggered_skill: str | None = None
    start = time.time()
    buffer = ""
    pending_tool: str | None = None
    accumulated = ""
    saw_eof = False

    try:
        while not decision_made and time.time() - start < timeout:
            if proc.poll() is not None:
                rest = proc.stdout.read()
                if rest:
                    buffer += rest.decode("utf-8", errors="replace")
                break
            ready, _, _ = select.select([proc.stdout], [], [], 1.0)
            if not ready:
                continue
            chunk = os.read(proc.stdout.fileno(), 8192)
            if not chunk:
                saw_eof = True
                break
            buffer += chunk.decode("utf-8", errors="replace")
            while "\n" in buffer and not decision_made:
                line, buffer = buffer.split("\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(event, dict):
                    continue

                if event.get("type") == "result" and event.get("is_error"):
                    # A dead worker must never pass a negative query, whatever
                    # the exit status says.
                    triggered_skill = WORKER_FAILED
                    decision_made = True
                    break

                if vendor_name == "cursor":
                    if event.get("type") != "tool_call":
                        continue
                    tool_call = event.get("tool_call")
                    if not isinstance(tool_call, dict) or not tool_call:
                        continue
                    kind, payload = next(iter(tool_call.items()))
                    if not isinstance(payload, dict):
                        payload = {}
                    if kind == "readToolCall":
                        args = payload.get("args")
                        if not isinstance(args, dict):
                            args = {}
                        path = str(args.get("path") or "")
                        match = READ_PATH_SKILL_RE.search(path)
                        triggered_skill = match.group(1) if match else None
                    else:
                        triggered_skill = None
                    decision_made = True
                    continue

                if event.get("type") != "stream_event":
                    continue
                se = event.get("event", {})
                se_type = se.get("type", "")
                if se_type == "content_block_start":
                    cb = se.get("content_block", {})
                    if cb.get("type") == "tool_use":
                        tn = cb.get("name", "")
                        if tn in ("Skill", "Read"):
                            pending_tool = tn
                            accumulated = ""
                        else:
                            decision_made = True
                elif se_type == "content_block_delta" and pending_tool:
                    delta = se.get("delta", {})
                    if delta.get("type") == "input_json_delta":
                        accumulated += delta.get("partial_json", "")
                        if pending_tool == "Skill":
                            m = SKILL_INPUT_NAME_RE.search(accumulated)
                            if m:
                                triggered_skill = m.group(1)
                                decision_made = True
                        elif pending_tool == "Read":
                            m = READ_PATH_RE.search(accumulated)
                            if m:
                                path = m.group(1)
                                m2 = READ_PATH_SKILL_RE.search(path)
                                if m2:
                                    triggered_skill = m2.group(1)
                                # Read of a non-SKILL.md path is not a skill trigger
                                decision_made = True
                elif se_type in ("content_block_stop", "message_stop"):
                    pending_tool = None
                    accumulated = ""
    finally:
        # Capture the worker's own exit status BEFORE we terminate it: an int rc
        # if it already exited on its own, None if it is still running (we ran
        # out of time). Needed to tell a clean no-trigger from a timeout/crash.
        self_exit_rc = proc.poll()
        if saw_eof and self_exit_rc is None:
            # stdout closed just before the process was reaped. Give it a short
            # grace so a clean exit is not misread as a timeout.
            try:
                self_exit_rc = proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                self_exit_rc = proc.poll()
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                proc.kill()
            except Exception:
                pass
        except Exception:
            pass

    if decision_made:
        # We observed the worker's first-tool choice — a valid measurement
        # (a trigger, or a deliberate non-family / no-skill choice).
        return triggered_skill
    if self_exit_rc == 0:
        # The worker exited cleanly before invoking any tool: a legitimate
        # "no trigger" (the model answered without loading a skill).
        return None
    # Still running when we gave up (timeout: self_exit_rc is None) or exited
    # nonzero (crash): a worker failure, not a deliberate no-trigger.
    return WORKER_FAILED


def run_one_deployed(
    query: str,
    timeout: int,
    resolved: vendor.Resolved,
) -> str | None:
    """Run one worker in a fresh directory and return its first-tool decision."""

    worker_dir = _fresh_worker_dir()
    try:
        cmd = vendor.build_stream_cmd(
            vendor=resolved.vendor,
            bin=resolved.bin,
            model=resolved.worker_model,
            effort=resolved.worker_effort,
            query=query,
            workspace=str(worker_dir) if resolved.vendor == "cursor" else None,
        )
        env = vendor.worker_env(resolved.vendor)
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=env,
            cwd=str(worker_dir),
        )
        return _read_worker(proc, timeout, resolved.vendor)
    finally:
        shutil.rmtree(worker_dir, ignore_errors=True)


def _worker(task: tuple) -> tuple:
    qi, ri, query, timeout, resolved = task
    return qi, ri, run_one_deployed(query, timeout, resolved)


def grade_query(triggered_runs: list[str | None], expected_skill: str | None,
                family: list[str]) -> dict:
    """Grade per query.

    For non-null `expected_skill`:
      - precise: triggered_skill == expected_skill
      - family:  triggered_skill ∈ family
    For null `expected_skill` (the query is outside the family's territory):
      - precise: triggered_skill ∉ family    (same as family)
      - family:  triggered_skill ∉ family
    For null we deliberately do NOT require `triggered_skill is None` —
    a query like "review this PR" correctly fires a non-family skill
    (e.g. `code-review`); from the family's perspective that's the right
    behavior, not a failure. Tracking "did some non-family skill fire"
    would belong in a cross-family eval, not this one.

    A run recorded as WORKER_FAILED (the worker timed out or crashed before
    deciding) never counts toward a pass in either metric, but stays in the
    denominator `n` so a systematically dead worker fails rather than
    false-passing a null-expected query on a no-op.
    """
    n = len(triggered_runs)
    if expected_skill is None:
        # A worker failure must not count as a deliberate no-trigger; it stays
        # in `n` so it lowers the pass rate instead of inflating it.
        precise_n = sum(1 for t in triggered_runs if t != WORKER_FAILED and t not in family)
        family_n = precise_n
    else:
        precise_n = sum(1 for t in triggered_runs if t == expected_skill)
        family_n = sum(1 for t in triggered_runs if t in family)
    return {
        "precise_n": precise_n,
        "family_n": family_n,
        "n": n,
        "precise_pass": (precise_n / n >= 0.5) if n else False,
        "family_pass": (family_n / n >= 0.5) if n else False,
    }


class EscapeDetected(RuntimeError):
    """A worker wrote into the host checkout during the run."""

    def __init__(self, paths: list[str]):
        self.paths = paths
        super().__init__(
            "worker wrote into the host checkout: " + ", ".join(paths)
        )


def _git_status(repo: Path) -> str | None:
    """Return ``git status --porcelain`` for a repo, or None outside one."""

    try:
        result = subprocess.run(
            ["git", "-C", str(repo), "status", "--porcelain"],
            capture_output=True,
            text=True,
        )
    except OSError:
        return None
    return result.stdout if result.returncode == 0 else None


def _changed_paths(before: str, after: str) -> list[str]:
    """Paths present after the run that were not present before it."""

    paths = []
    for line in sorted(set(after.splitlines()) - set(before.splitlines())):
        path = line[3:].strip()
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path)
    return paths


def run_deployed_mode(entries: list[dict], target_skill: str, family: list[str],
                      runs_per_query: int, timeout: int, workers: int,
                      resolved: vendor.Resolved, log) -> dict:
    native_root = vendor.skill_roots(resolved.vendor)[0] / target_skill
    print(f"Mode: deployed ({native_root}/)", file=log, flush=True)
    print(f"Family: {family}", file=log, flush=True)
    runs_by_query: list[list[str | None]] = [[None] * runs_per_query for _ in entries]
    tasks = [
        (qi, ri, e["query"], timeout, resolved)
        for qi, e in enumerate(entries)
        for ri in range(runs_per_query)
    ]
    completed = 0
    total = len(tasks)
    before = _git_status(REPO_ROOT)
    with ProcessPoolExecutor(max_workers=workers) as pool:
        for qi, ri, name in pool.map(_worker, tasks):
            runs_by_query[qi][ri] = name
            completed += 1
            if completed % 5 == 0 or completed == total:
                print(f"  progress: {completed}/{total}", file=log, flush=True)
    after = _git_status(REPO_ROOT)
    if before is not None and after is not None and before != after:
        raise EscapeDetected(_changed_paths(before, after))

    results = []
    precise_passed = 0
    family_passed = 0
    for entry, runs in zip(entries, runs_by_query):
        g = grade_query(runs, entry["expected_skill"], family)
        if g["precise_pass"]:
            precise_passed += 1
        if g["family_pass"]:
            family_passed += 1
        results.append({
            "query": entry["query"],
            "expected_skill": entry["expected_skill"],
            "triggered_skill_per_run": runs,
            "precise_triggers": g["precise_n"],
            "family_triggers": g["family_n"],
            "runs": g["n"],
            "precise_trigger_rate": g["precise_n"] / g["n"] if g["n"] else 0.0,
            "family_trigger_rate": g["family_n"] / g["n"] if g["n"] else 0.0,
            "precise_pass": g["precise_pass"],
            "family_pass": g["family_pass"],
        })

    return {
        "skill_name": target_skill,
        "mode": "deployed",
        "family": family,
        "results": results,
        "summary": {
            "total": len(entries),
            "precise_passed": precise_passed,
            "family_passed": family_passed,
            "precise_failed": len(entries) - precise_passed,
            "family_failed": len(entries) - family_passed,
        },
    }


def run_uuid_fallback(eval_set_path: Path, source_skill_path: Path,
                      model: str | None, runs_per_query: int, timeout: int,
                      workers: int, log) -> dict:
    print("Mode: uuid_fallback (--force-uuid)", file=log, flush=True)
    print("Note: uuid fallback uses skill-creator's run_eval.py, which only "
          "supports single-skill grading. Family / precise metrics are not "
          "available in this mode.\n", file=log, flush=True)
    if not (SKC_RUN_EVAL / "scripts" / "run_eval.py").is_file():
        raise RuntimeError(
            f"skill-creator runner not found at {SKC_RUN_EVAL}/scripts/run_eval.py — "
            "install the skill-creator plugin, or omit --force-uuid and deploy the skill "
            "to measure in deployed mode."
        )
    cmd = [
        sys.executable, "-m", "scripts.run_eval",
        "--eval-set", str(eval_set_path),
        "--skill-path", str(source_skill_path),
        "--runs-per-query", str(runs_per_query),
        "--timeout", str(timeout),
        "--num-workers", str(workers),
        "--verbose",
    ]
    if model:
        cmd.extend(["--model", model])
    result = subprocess.run(cmd, cwd=SKC_RUN_EVAL, capture_output=True, text=True)
    log.write(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"uuid fallback failed (rc={result.returncode}): {result.stderr[:400]}")
    parsed = json.loads(result.stdout)
    parsed["mode"] = "uuid_fallback"
    return parsed


def baseline_worker_mismatch(base: dict, current: dict) -> str | None:
    """Name a worker model or effort difference between baseline and run.

    A baseline that omits `worker_effort` reads as the empty effort, and one
    that omits `worker_model` reads as `unknown`, which differs from every
    resolved model. Both sides normalize the same way, so a Cursor baseline
    that carries `worker_model` `auto` and no effort still compares against a
    Cursor run. Returns None when both normalized values match.
    """
    base_model = base.get("worker_model")
    base_model = "unknown" if base_model is None else str(base_model)
    base_effort = str(base.get("worker_effort") or "")
    cur_model = str(current.get("worker_model") or "")
    cur_effort = str(current.get("worker_effort") or "")
    if base_model == cur_model and base_effort == cur_effort:
        return None
    return (
        f"recorded with worker_model {base_model!r} and worker_effort "
        f"{base_effort!r}, this run uses worker_model {cur_model!r} and "
        f"worker_effort {cur_effort!r}"
    )


def _load_results(path: Path) -> dict:
    """Load a results.json given either that file or its run directory."""
    p = path if path.is_file() else path / "results.json"
    return json.loads(p.read_text())


def compare_to_baseline(current: dict, baseline_path: Path) -> dict:
    """Diff this run's per-query precise verdicts against a prior run.

    Matches queries by text on the intersection of the two sets, so an
    eval set that grew or shrank still compares on its shared queries. A
    single-query flip can be sampling noise at the 50%-over-3-runs
    threshold, so the report carries both the verdict change and the
    per-run trigger counts; treat a lone regression as a prompt to re-run,
    not proof of a real routing change.
    """
    base = _load_results(baseline_path)
    cur_q = {r["query"]: r for r in current.get("results", [])}
    base_q = {r["query"]: r for r in base.get("results", [])}
    shared = [q for q in cur_q if q in base_q]
    regressions, improvements = [], []
    for q in shared:
        b, c = base_q[q], cur_q[q]
        move = {"query": q, "expected_skill": c["expected_skill"],
                "baseline_precise": b["precise_triggers"],
                "current_precise": c["precise_triggers"], "runs": c["runs"]}
        if b["precise_pass"] and not c["precise_pass"]:
            regressions.append(move)
        elif c["precise_pass"] and not b["precise_pass"]:
            improvements.append(move)
    return {
        "baseline_path": str(baseline_path),
        "shared_queries": len(shared),
        "only_in_current": sorted(set(cur_q) - set(base_q)),
        "only_in_baseline": sorted(set(base_q) - set(cur_q)),
        "regressions": regressions,
        "improvements": improvements,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--eval-set", required=True)
    parser.add_argument("--skill", required=True,
                        help="The skill name being targeted. Used for "
                             "deployed-mode detection, as the inferred "
                             "expected_skill for legacy `should_trigger: true` "
                             "entries, and as the default family member.")
    parser.add_argument("--family", default=None,
                        help="Comma-separated list of sibling skill names. "
                             "Default: auto-derive from the parent of "
                             "--skill-path. Falls back to just --skill if "
                             "auto-derivation finds nothing.")
    parser.add_argument("--skill-path", default=None,
                        help="Source SKILL.md dir under plugins/...; used for "
                             "deployed-vs-source drift warning, family "
                             "auto-derivation, and required by --force-uuid. "
                             "Defaults to "
                             "plugins/knowledge_management/skills/<skill>.")
    vendor.add_vendor_arguments(parser, harness_id="trigger_evals")
    parser.add_argument("--runs-per-query", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=45,
                        help="Per-query timeout in seconds.")
    parser.add_argument(
        "--workers", type=int, default=vendor.DEFAULT_PARALLEL_WORKERS
    )
    parser.add_argument("--results-dir", default=None)
    parser.add_argument("--baseline", default=None,
                        help="Prior results.json (or its run dir) to diff this run "
                             "against per query. Reports precise regressions and "
                             "improvements; a regression makes the exit code non-zero.")
    parser.add_argument("--force-uuid", action="store_true",
                        help="Deliberate opt-in to the UUID-proxy path. "
                             "Skip deployed detection and use skill-creator's "
                             "uuid fallback. The only way to reach that path.")
    args = parser.parse_args()
    vendor.require_vendor_allowed(args.vendor, "trigger_evals")
    resolved = vendor.resolve(args)

    if args.vendor == "cursor" and args.force_uuid:
        print(
            "ERROR: --force-uuid is the UUID-proxy path and is Claude-only: "
            "skill-creator's runner behind it drives `claude -p`. Run it with "
            "`--vendor claude`, or omit --force-uuid and deploy the skill to "
            "measure on Cursor.",
            file=sys.stderr,
        )
        return 2

    eval_set_path = Path(args.eval_set).resolve()
    if not eval_set_path.is_file():
        print(f"ERROR: eval set not found: {eval_set_path}", file=sys.stderr)
        return 2
    raw_entries = json.loads(eval_set_path.read_text())
    entries = [normalize_eval_entry(e, args.skill) for e in raw_entries]

    if args.skill_path:
        source_skill_path: Path | None = Path(args.skill_path).resolve()
    else:
        candidate = REPO_ROOT / "plugins" / "knowledge_management" / "skills" / args.skill
        source_skill_path = candidate if candidate.is_dir() else None

    if args.family:
        family = [s.strip() for s in args.family.split(",") if s.strip()]
    elif source_skill_path:
        family = auto_derive_family(source_skill_path)
    else:
        family = [args.skill]
    if args.skill not in family:
        family = [args.skill] + family

    native_root = vendor.skill_roots(resolved.vendor)[0] / args.skill
    deployed_root = (
        None if args.force_uuid else deployed_skill_root(args.skill, args.vendor)
    )
    if deployed_root is None and not args.force_uuid:
        print(
            f"ERROR: skill '{args.skill}' is unavailable: not found under "
            f"{native_root}/. Deploy the skill (make deploy) or pass "
            f"--vendor claude --force-uuid to use the UUID-proxy path "
            f"deliberately.",
            file=sys.stderr,
        )
        return 2

    # --force-uuid preflight before any results directory exists
    if args.force_uuid:
        if source_skill_path is None:
            print(
                "ERROR: --force-uuid requires a skill source path "
                "(--skill-path or the default under "
                "plugins/knowledge_management/skills/<skill>).",
                file=sys.stderr,
            )
            return 2
        if shutil.which(resolved.bin) is None:
            print(f"ERROR: '{resolved.bin}' CLI not found on PATH.", file=sys.stderr)
            return 2

    if args.results_dir:
        out_dir = Path(args.results_dir).resolve()
    else:
        ts = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
        out_dir = REPO_ROOT / "tests" / "trigger_evals" / "results" / args.skill / ts
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Results dir: {out_dir}")

    drift_notes: list[str] = []
    if deployed_root and source_skill_path:
        for root in vendor.skill_roots(resolved.vendor):
            copy = root / args.skill / "SKILL.md"
            if not copy.is_file():
                continue
            note = detect_drift(copy, source_skill_path / "SKILL.md")
            if note:
                drift_notes.append(note)

    log_path = out_dir / "run.log"
    results_path = out_dir / "results.json"
    baseline_mismatch: str | None = None
    # The uuid-fallback runner applies no effort, so both records of that run,
    # run.log and results.json, name the empty effort rather than an effort
    # that run never applied.
    applied_effort = resolved.worker_effort if deployed_root else ""

    with log_path.open("w") as log:
        log.write(f"eval_set:       {eval_set_path}\n")
        log.write(f"skill:          {args.skill}\n")
        log.write(f"family:         {family}\n")
        log.write(f"source_path:    {source_skill_path}\n")
        log.write(f"deployed_root:  {deployed_root}\n")
        log.write(f"vendor:         {resolved.vendor}\n")
        log.write(f"command:        {resolved.config.label}\n")
        log.write(f"model:          {resolved.worker_model or '<inherit>'}\n")
        log.write(f"effort:         {applied_effort or '<inherit>'}\n")
        log.write(f"runs_per_query: {args.runs_per_query}\n")
        log.write(f"timeout:        {args.timeout}\n")
        log.write(f"workers:        {args.workers}\n")
        log.write(f"force_uuid:     {args.force_uuid}\n\n")
        for drift_note in drift_notes:
            log.write(drift_note + "\n\n")
            print(drift_note)

        try:
            if deployed_root:
                output = run_deployed_mode(
                    entries, args.skill, family, args.runs_per_query,
                    args.timeout, args.workers, resolved, log,
                )
            else:
                output = run_uuid_fallback(
                    eval_set_path, source_skill_path, resolved.worker_model,
                    args.runs_per_query, args.timeout, args.workers, log,
                )
        except Exception as e:
            log.write(f"\nERROR: {e}\n")
            print(f"ERROR: {e}", file=sys.stderr)
            return 1

        output["vendor"] = resolved.vendor
        output["worker_model"] = resolved.worker_model
        output["worker_effort"] = applied_effort

        baseline_cmp = None
        if args.baseline and output["mode"] == "deployed":
            try:
                base_path = Path(args.baseline).resolve()
                base = _load_results(base_path)
                base_vendor = base.get("vendor", "claude")
                worker_mismatch = baseline_worker_mismatch(base, output)
                if base_vendor != output["vendor"]:
                    baseline_mismatch = (
                        f"baseline vendor mismatch: baseline {base_path} was "
                        f"recorded on {base_vendor}, this run is on "
                        f"{output['vendor']}. Comparison skipped."
                    )
                elif worker_mismatch is not None:
                    baseline_mismatch = (
                        f"baseline worker mismatch: baseline {base_path} was "
                        f"{worker_mismatch}. Comparison skipped."
                    )
                if baseline_mismatch is not None:
                    log.write("\nWARNING: " + baseline_mismatch + "\n")
                    print(f"WARNING: {baseline_mismatch}", file=sys.stderr)
                else:
                    baseline_cmp = compare_to_baseline(output, base_path)
                    output["baseline_comparison"] = baseline_cmp
            except Exception as e:
                log.write(f"\nWARNING: could not compare to baseline: {e}\n")
                print(f"WARNING: could not compare to baseline: {e}", file=sys.stderr)

        results_path.write_text(json.dumps(output, indent=2))

        if output["mode"] == "deployed":
            s = output["summary"]
            log.write(f"\nResults: precise={s['precise_passed']}/{s['total']}  "
                      f"family={s['family_passed']}/{s['total']}\n")
            for r in output["results"]:
                pp = "P" if r["precise_pass"] else "."
                fp = "F" if r["family_pass"] else "."
                triggered = "/".join(t or "-" for t in r["triggered_skill_per_run"])
                log.write(f"  [{pp}{fp}] expected={r['expected_skill'] or '<none>':<14} "
                          f"triggered={triggered:<24} : {r['query'][:80]}\n")
            print(f"Mode: deployed (family: {family})")
            print(f"Precise: {s['precise_passed']}/{s['total']} "
                  f"({s['precise_passed']/s['total']*100:.0f}%) — the exact expected skill loaded")
            print(f"Family:  {s['family_passed']}/{s['total']} "
                  f"({s['family_passed']/s['total']*100:.0f}%) — any family member loaded "
                  f"when expected (or none, when expected_skill=null)")
            if baseline_cmp is not None:
                regs, imps = baseline_cmp["regressions"], baseline_cmp["improvements"]
                header = (f"Baseline: {baseline_cmp['shared_queries']} shared queries vs "
                          f"{baseline_cmp['baseline_path']}")
                print(header); log.write("\n" + header + "\n")
                if not regs and not imps:
                    line = "  no per-query precise change vs baseline"
                    print(line); log.write(line + "\n")
                for r in regs:
                    line = (f"  REGRESSION {r['baseline_precise']}/{r['runs']} -> "
                            f"{r['current_precise']}/{r['runs']} "
                            f"expected={r['expected_skill'] or '<none>'} : {r['query'][:70]}")
                    print(line); log.write(line + "\n")
                for r in imps:
                    line = (f"  improved   {r['baseline_precise']}/{r['runs']} -> "
                            f"{r['current_precise']}/{r['runs']} "
                            f"expected={r['expected_skill'] or '<none>'} : {r['query'][:70]}")
                    print(line); log.write(line + "\n")
                if regs:
                    tip = ("  note: a lone per-query flip can be sampling noise at the "
                           "50%-over-3-runs threshold; re-run to confirm before acting.")
                    print(tip); log.write(tip + "\n")
        else:
            # uuid fallback uses upstream schema
            s = output.get("summary", {})
            log.write(f"\nResults: {s.get('passed','?')}/{s.get('total','?')} passed (uuid fallback)\n")
            print(f"Mode: uuid_fallback")
            print(f"Passed: {s.get('passed','?')}/{s.get('total','?')}")

    print(f"results.json: {results_path}")
    print(f"run.log:      {log_path}")
    if output["mode"] == "deployed":
        if baseline_mismatch is not None:
            return 1
        cmp = output.get("baseline_comparison")
        if cmp is not None:
            # With a baseline the meaningful signal is regression, not the
            # absolute pass rate (which never reaches 100% on this eval set).
            return 1 if cmp["regressions"] else 0
        return 0 if output["summary"]["precise_passed"] == output["summary"]["total"] else 1
    return 0 if output.get("summary", {}).get("passed", 0) == output.get("summary", {}).get("total", 0) else 1


if __name__ == "__main__":
    sys.exit(main())
