#!/usr/bin/env python3
"""Vendor-aware worker runner for agent_spinner behavioral evals.

Stages a sandbox, micro-deploys agent_spinner (plus the harness_portability
skill it routes per-harness questions to, and any governing skill the eval
names in `extra_reads`) through the deploy script into a scratch home,
runs one vendor-resolved print-mode worker that loads agent_spinner, records
`artefacts_read_from_micro_deployment`, then grades the filesystem, the roster, the briefs, and the response markers with
grade.sh. The worker runs on Cursor by default (`agent -p`, model `auto`);
`--vendor claude` (model `sonnet`) runs where Claude is needed or asked for, and `--model ''` inherits the vendor CLI default.

Two things here are specific to this harness. A fixture that stages "no
delegation surface" denies the spawn tool on the worker's command line, so
the absence is a real harness state rather than a claim in a note. And every
run is bracketed by a `git status --porcelain` of the host checkout, so an
escape from the sandbox fails the eval that caused it.

Cursor has no `--disallowedTools` flag, so on that vendor the harness appends
an explicit environment note to the prompt instead of trying to pass a native
restriction flag the CLI does not implement.

Usage:
    python3 tests/agent_spinner/evals/run.py [eval_id ...]
      [--vendor claude|cursor] [--model sonnet|auto|'']
      [--timeout 420] [--worker-bin <bin>]
      [--force] [--no-cache]
"""

from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import subprocess
import sys
import time

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
EVALS = THIS / "evals.json"
WORKSPACE = THIS / "workspace"
REPO_ROOT = THIS.parents[2]

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402
import micro_deploy  # noqa: E402
import vendor  # noqa: E402

# Skills agent_spinner itself routes work to by name, so a worker may load them
# in any eval: every per-harness question goes to harness_portability.
ROUTED_SKILLS = ["harness_portability"]

# Skills a governing skill reads through its own <authority> step.
GOVERNING_COMPANIONS = {"task_auto_check": ["task"]}

WORKER_PROMPT = """\
You are running an automated skill regression eval. Do exactly this:

1. Read the skill definition file in full: {skill_path}
2. Read its references/ directory as the run needs them.
{extra_reads}3. Keep the run's own state where this harness can read it, under
   `.agent_spinner/` in the working directory. Write the run's opening
   announcement, verbatim, to `.agent_spinner/announcement.txt` before the
   first pass. Write the dispatch roster the skill's <run_state> block requires
   to `.agent_spinner/roster.tsv`. Append each helper brief, in full, to
   `.agent_spinner/briefs/<label>.txt` before that helper is dispatched or that
   pass is performed. Write the closing report, verbatim, to
   `.agent_spinner/report.md` once it is written. This harness reads only the
   last thing you say, so these four paths are its window on the rest of the run.
4. Carry out the user request below, operating only inside the current working
   directory ({workdir}):

{prompt}
"""

EXTRA_READ_LINE = ("2b. A named skill governs this request. Read it too and apply its own\n"
                   "   contract where it states one: {path}\n")


def load_evals() -> dict:
    data = json.loads(EVALS.read_text())
    return {e["id"]: e for e in data["evals"]}


def governing_names(harness: dict) -> list[str]:
    """Artefact names for the governing skills an eval reads."""
    names: list[str] = []
    for rel in harness.get("extra_reads", []):
        name = (REPO_ROOT / rel).parent.name
        names.append(name)
        names.extend(GOVERNING_COMPANIONS.get(name, []))
    return names


def artefacts_for(harness: dict) -> list[str]:
    """agent_spinner, the skills it routes work to, and any governing skill
    this eval reads."""
    return list(dict.fromkeys(
        ["agent_spinner", *ROUTED_SKILLS, *governing_names(harness)]
    ))


def source_roots_for(harness: dict):
    """The skill under test, the skills it routes work to, plus any governing
    skill this eval reads.

    An eval whose ask falls under a governing skill depends on that skill's
    contract, and a per-harness answer depends on harness_portability, so a
    change to either has to move the cache key too.
    """
    return micro_deploy.source_roots_for(artefacts_for(harness))


def host_status() -> str:
    """Porcelain status of the host checkout, for the sandbox-escape guard."""
    return subprocess.run(
        ["git", "-C", str(REPO_ROOT), "status", "--porcelain"],
        capture_output=True, text=True,
    ).stdout


def stage(eval_id: str, target: pathlib.Path) -> dict:
    out = subprocess.check_output(
        ["bash", str(STAGE), eval_id, str(target)],
        text=True,
    )
    env: dict[str, str] = {}
    for line in out.splitlines():
        if "=" not in line:
            continue
        key, raw = line.split("=", 1)
        env[key] = subprocess.check_output(
            ["bash", "-c", f"printf %s {raw}"], text=True
        ).rstrip("\n")
    return env


def worker_completed(rc: int, stdout: str) -> bool:
    return rc == 0 and bool(stdout.strip())


def run_one(eval_id: str, spec: dict, run_dir: pathlib.Path,
            resolved: vendor.Resolved, timeout: int, cache, force: bool):
    eval_dir = run_dir / eval_id
    target = eval_dir / "sandbox"
    target.mkdir(parents=True, exist_ok=True)

    staged = stage(eval_id, target)
    workdir = staged["sandbox_proj"]
    harness = spec.get("harness", {})
    model_label = resolved.worker_model or "<inherit>"

    key = None
    if cache is not None:
        key = eval_cache.content_key(
            source_roots=source_roots_for(harness),
            harness_dir=THIS,
            model=resolved.worker_model,
            eval_id=eval_id,
            prompt=staged["prompt"],
        )
        if not force:
            hit = cache.lookup(eval_id, key)
            if hit is not None:
                eval_cache.write_replay_artifacts(eval_dir, hit)
                verdict = "PASS" if hit["passed"] else "FAIL"
                print(f"  [{eval_id}] CACHED {verdict} "
                      f"(graded {hit.get('graded_at', '?')}, "
                      f"model={hit.get('model', '?')}) — skipped {resolved.config.label}; "
                      "--force to re-run\n", flush=True)
                return hit["passed"], True

    denied = harness.get("disallowed_tools") or []
    extra_args: list[str] = []
    if denied and resolved.vendor == "claude":
        extra_args = ["--disallowedTools", *denied]

    host_before = host_status()
    print(f"  [{eval_id}] running {resolved.config.label} "
          f"(model={model_label}"
          f"{', denied=' + ','.join(denied) if denied else ''}) ...", flush=True)
    start = time.time()
    with micro_deploy.micro_deploy(
        resolved.vendor, artefacts_for(harness), pathlib.Path(workdir),
        preflight=False,
    ) as md:
        extra = "".join(
            EXTRA_READ_LINE.format(
                path=str(md.path_map[(REPO_ROOT / rel).parent.name])
            )
            for rel in harness.get("extra_reads", [])
        )
        prompt = WORKER_PROMPT.format(
            skill_path=md.path_map["agent_spinner"],
            extra_reads=extra,
            workdir=workdir,
            prompt=staged["prompt"],
        )
        if denied and resolved.vendor != "claude":
            prompt += (
                "\n\nEnvironment note: the following tools are unavailable in this "
                f"harness run and must not be used: {', '.join(denied)}."
            )
        worker = micro_deploy.run_worker(
            vendor_name=resolved.vendor, bin_name=resolved.bin,
            model=resolved.worker_model, prompt=prompt, deploy=md,
            timeout=timeout, cwd=pathlib.Path(workdir), extra_args=extra_args,
            prompt_before_flags=bool(extra_args),
        )
        rc, stdout, stderr = worker.returncode, worker.stdout, worker.stderr
        integrity = micro_deploy.integrity_record(
            worker.read_paths, worker.out_of_set_paths
        )
    duration_s = time.time() - start
    host_after = host_status()

    (eval_dir / "response.txt").write_text(stdout)
    (eval_dir / "stderr.txt").write_text(stderr)
    (eval_dir / "timing.json").write_text(json.dumps({
        "eval_id": eval_id,
        "duration_s": duration_s,
        "worker_rc": rc,
        "claude_rc": rc,
        "model": model_label,
        "disallowed_tools": denied,
        "artefacts_read_from_micro_deployment": integrity,
    }, indent=2))

    grade = subprocess.run(
        ["bash", str(GRADE), eval_id, workdir, str(eval_dir / "response.txt")],
        capture_output=True, text=True
    )
    (eval_dir / "grading.txt").write_text(grade.stdout + grade.stderr)
    print(grade.stdout, end="", flush=True)
    grade_passed = grade.returncode == 0

    host_clean = host_before == host_after
    if not host_clean:
        print(f"  [{eval_id}] FAIL — the host checkout changed during this eval; "
              "the run escaped its sandbox\n", flush=True)

    completed = worker_completed(rc, stdout)
    passed = grade_passed and completed and host_clean and integrity["passed"]

    if not completed:
        why = ("timeout" if "[TIMEOUT" in stderr
               else "empty response" if not stdout.strip()
               else f"worker rc={rc}")
        print(f"  [{eval_id}] FAIL — worker did not complete ({why})\n",
              flush=True)
    elif not integrity["passed"]:
        print(f"  [{eval_id}] FAIL — worker read artefacts outside the "
              f"micro-deployment: {integrity['out_of_set']}\n", flush=True)
    elif host_clean:
        print(f"  [{eval_id}] {'PASS' if passed else 'FAIL'} (worker rc={rc})\n",
              flush=True)

    if cache is not None and completed and key is not None:
        cache.record(
            eval_id,
            key,
            passed=passed,
            model=model_label,
            duration_s=duration_s,
            worker_rc=rc,
            grading_output=grade.stdout + grade.stderr,
            response_excerpt=stdout[:eval_cache.RESPONSE_EXCERPT_CHARS],
        )
    return passed, False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="*", default=None)
    vendor.add_vendor_arguments(parser)
    parser.add_argument("--timeout", type=int, default=420)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--no-cache", action="store_true")
    args = parser.parse_args()

    specs = load_evals()
    ids = args.ids if args.ids else list(specs)
    unknown = [i for i in ids if i not in specs]
    if unknown:
        print("unknown eval id(s):", ", ".join(unknown))
        return 2

    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")
    resolved = vendor.resolve(args)
    model_label = resolved.worker_model or "<inherit>"
    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"model: {model_label}"
    )

    failures = []
    for eval_id in ids:
        ok, _cached = run_one(
            eval_id, specs[eval_id], run_dir, resolved, args.timeout, cache, args.force,
        )
        if not ok:
            failures.append(eval_id)

    if failures:
        print("FAILED:", ", ".join(failures))
        return 1
    print("All evals passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
