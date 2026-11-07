#!/usr/bin/env python3
"""Vendor-aware worker runner for agent_spinner behavioral evals.

Stages a sandbox, micro-deploys agent_spinner (plus the harness_portability
skill it routes per-harness questions to, any governing skill the eval names
in `extra_reads`, and any plugin role the eval stages) through the deploy
script into a scratch home, runs one or more vendor-resolved print-mode turns
that load agent_spinner, records `artefacts_read_from_micro_deployment`, then
grades the filesystem, the roster, the briefs, and the response markers with
grade.sh. The worker runs on Cursor by default (`agent -p`, model `auto`);
`--vendor claude` (model `sonnet`) runs where Claude is needed or asked for,
and `--model ''` inherits the vendor CLI default.

Three runner modes sit beside the ordinary single-turn eval. An eval with
`inline_body` gets the deployed skill body in its prompt, the way a host's
manual attachment delivers it. An eval with `second_turn` resumes the first
turn's session through the vendor CLI's own resume path, with an optional
fixture step between the turns. An eval with `agents` stages named agent
definitions where the worker's host discovers them.

Withheld tools follow one rule on both vendors, held as a table in
`tests/lib/vendor.py`. Shell and write are withheld by CLI flag on Claude and
by CLI project config on Cursor; spawn is a declared absence on both, because
no Cursor deny entry withholds it. `withheld_by` records which mechanism
applied, and an eval marked `needs_real_absence` reports when its expected
behaviour rests on that declaration. The runner records each turn's stream
tool calls to `tool_calls.jsonl` when the eval sets `tool_record`.

Every eval is one job in the shared pool from `tests/lib/eval_runner.py`
(`--workers`, default `vendor.DEFAULT_PARALLEL_WORKERS`, each job with its own
TMPDIR). The default ids are every id in `evals.json`, in file order.

A host-status guard brackets each job through the helper's before/after hooks.
The before hook stores the full `git status --porcelain` of the host checkout;
the after hook reads the eval's preserved sandbox copy and blames only the new
host paths whose basename that copy owns. Overlapping evals therefore stay
attributable: an escape fails the eval whose sandbox names it, and a sibling's
own work never does.

Usage:
    python3 tests/agent_spinner/evals/run.py [eval_id ...]
      # default: every `id` in evals.json, derived at startup
      [--vendor claude|cursor] [--model sonnet|auto|'']
      [--workers 4] [--timeout 420] [--worker-bin <bin>]
      [--force] [--no-cache]
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime
import json
import pathlib
import shlex
import subprocess
import sys
import time
import uuid
from collections.abc import Mapping

THIS = pathlib.Path(__file__).resolve().parent
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.sh"
EVALS = THIS / "evals.json"
FIXTURES = THIS / "fixtures"
REPO_ROOT = THIS.parents[2]

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import eval_cache  # noqa: E402
import eval_runner  # noqa: E402  (shared Pattern A job pool)
import micro_deploy  # noqa: E402
import vendor  # noqa: E402
import worker_isolation  # noqa: E402  (shared sandbox-root helper)

# The sole run root: tests/agent_spinner/workspace, beside evals/.
WORKSPACE = eval_runner.resolve_workspace(THIS)

# Every id in evals.json, in file order — the default run set. Derived rather
# than frozen, so a newly added eval is covered the moment it is staged.
DEFAULT_IDS = eval_runner.load_eval_ids(EVALS)

ISOLATION_PREFIX = "agent_spinner_"

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

# The inline-body mode reproduces a host's manual attachment: the note, the
# attached file's path, then the body with no frontmatter and no references.
ATTACHMENT_NOTE = (
    "The user attached the file below to this conversation. Treat its contents "
    "as the skill definition. Other files need reading only if the task needs "
    "them."
)
INLINE_GOVERNING_LINE = (
    "{n}. A named skill governs this request. Read it too and apply its own\n"
    "   contract where it states one: {path}\n"
)
INLINE_STATE_STEP = (
    "{n}. Keep the run's own state where this harness can read it, under\n"
    "   `.agent_spinner/` in the working directory. Write the run's opening\n"
    "   announcement, verbatim, to `.agent_spinner/announcement.txt` before the\n"
    "   first pass. Write the dispatch roster the skill's <run_state> block requires\n"
    "   to `.agent_spinner/roster.tsv`. Append each helper brief, in full, to\n"
    "   `.agent_spinner/briefs/<label>.txt` before that helper is dispatched or that\n"
    "   pass is performed. Write the closing report, verbatim, to\n"
    "   `.agent_spinner/report.md` once it is written. This harness reads only the\n"
    "   last thing you say, so these four paths are its window on the rest of the run.\n"
)
INLINE_REQUEST_STEP = (
    "{n}. Carry out the user request below, operating only inside the current working\n"
    "   directory ({workdir}):\n\n"
    "{prompt}\n"
)

# The one declared-absence note the spawn class carries on both vendors. No
# Cursor deny entry withholds the spawn tool, so every eval that withholds it
# says the same thing on either vendor.
DECLARED_ABSENCE_NOTE = (
    "Environment note: the spawn tool is unavailable in this harness run and "
    "must not be used. The delegation surface is absent: Agent, Task, and "
    "Workflow cannot be called."
)
ABSENCE_SUFFIX = "the absence rests on the prompt declaration"


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


def resolve_agent_path(rel: str) -> pathlib.Path:
    """Resolve an agent path from the repo root or the evals directory."""
    path = pathlib.Path(rel)
    if path.is_absolute():
        if path.is_file():
            return path
        raise FileNotFoundError(f"agent file not found: {path}")
    for base in (REPO_ROOT, THIS):
        candidate = base / path
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(
        f"agent file not found under {REPO_ROOT} or {THIS}: {rel}"
    )


def split_agent_files(harness: dict) -> tuple[list[pathlib.Path], list[pathlib.Path]]:
    """Split staged agents into plugin roles and fixture agents.

    A plugin role is one ``discover_artifacts`` names, so the micro-deployment
    renders it per vendor. A fixture agent is any other listed file, which the
    runner stages into the sandbox project after the micro-deployment returns.
    """
    index = micro_deploy.discover_artefact_index()
    plugin: list[pathlib.Path] = []
    fixtures: list[pathlib.Path] = []
    for rel in harness.get("agents") or []:
        path = resolve_agent_path(rel)
        entry = index.get(path.stem)
        if entry is not None and entry[0] == "agent" and entry[1].resolve() == path.resolve():
            plugin.append(path)
        else:
            fixtures.append(path)
    return plugin, fixtures


def artefacts_for(harness: dict) -> list[str]:
    """agent_spinner, the skills it routes work to, any governing skill this
    eval reads, and any plugin role it stages."""
    names = ["agent_spinner", *ROUTED_SKILLS, *governing_names(harness)]
    names.extend(path.stem for path in split_agent_files(harness)[0])
    return list(dict.fromkeys(names))


def source_roots_for(harness: dict):
    """The skill under test, the skills it routes work to, any governing skill
    this eval reads, and each fixture agent's parent directory.

    A fixture agent lives outside the deploy script's discovery, so its parent
    directory joins the cache key here rather than in the declaration.
    """
    roots = list(micro_deploy.source_roots_for(artefacts_for(harness)))
    for path in split_agent_files(harness)[1]:
        if path.parent not in roots:
            roots.append(path.parent)
    return roots


def validate_harness(eval_id: str, spec: dict) -> str | None:
    """Return an error naming the eval when a withheld class is unknown."""
    harness = spec.get("harness", {})
    try:
        vendor.withheld_tool_plan("claude", harness.get("disallowed_tools") or [])
    except ValueError as err:
        return f"{eval_id}: {err}"
    return None


def strip_frontmatter(text: str) -> str:
    """Drop a leading YAML frontmatter block, keeping the body's own bytes."""
    if not text.startswith("---"):
        return text
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return text
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return "".join(lines[index + 1:])
    return text


def governing_paths(harness: dict, deploy: micro_deploy.MicroDeployHandle) -> list[str]:
    return [
        str(deploy.path_map[(REPO_ROOT / rel).parent.name])
        for rel in harness.get("extra_reads", [])
    ]


def build_inline_prompt(
    *,
    skill_path: pathlib.Path,
    body: str,
    extra_paths: list[str],
    workdir: str,
    prompt: str,
) -> str:
    """Build the attachment block plus the steps that remain without a path read."""
    parts = [
        ATTACHMENT_NOTE,
        f"Attached file: {skill_path}",
        "",
        body,
        "",
    ]
    number = 1
    for path in extra_paths:
        parts.append(INLINE_GOVERNING_LINE.format(n=number, path=path))
        number += 1
    parts.append(INLINE_STATE_STEP.format(n=number))
    number += 1
    parts.append(
        INLINE_REQUEST_STEP.format(n=number, workdir=workdir, prompt=prompt)
    )
    return "\n".join(parts)


def build_prompt(
    harness: dict,
    deploy: micro_deploy.MicroDeployHandle,
    staged: dict,
    workdir: str,
) -> str:
    """Build the first turn's prompt for the eval's mode."""
    if harness.get("inline_body"):
        skill_path = deploy.path_map["agent_spinner"]
        return build_inline_prompt(
            skill_path=skill_path,
            body=strip_frontmatter(skill_path.read_text()),
            extra_paths=governing_paths(harness, deploy),
            workdir=workdir,
            prompt=staged["prompt"],
        )
    extra = "".join(
        EXTRA_READ_LINE.format(path=path)
        for path in governing_paths(harness, deploy)
    )
    return WORKER_PROMPT.format(
        skill_path=deploy.path_map["agent_spinner"],
        extra_reads=extra,
        workdir=workdir,
        prompt=staged["prompt"],
    )


def with_declared_absence(prompt: str, plan: vendor.WithheldPlan) -> str:
    if "spawn" not in plan.declared:
        return prompt
    return prompt.rstrip() + "\n\n" + DECLARED_ABSENCE_NOTE + "\n"


def host_status() -> str:
    """Porcelain status of the host checkout, for the sandbox-escape guard."""
    return subprocess.run(
        ["git", "-C", str(REPO_ROOT), "status", "--porcelain"],
        capture_output=True, text=True,
    ).stdout


def status_paths(status: str) -> set[str]:
    """The paths one `git status --porcelain` record names.

    A rename line carries both sides; the target side is the path the run
    now owns. Quoted paths are unquoted for the basename comparison.
    """
    paths: set[str] = set()
    for line in status.splitlines():
        if len(line) < 4:
            continue
        rest = line[3:]
        if " -> " in rest:
            rest = rest.split(" -> ", 1)[1]
        rest = rest.strip().strip('"')
        if rest:
            paths.add(rest)
    return paths


def sandbox_names(path: pathlib.Path) -> set[str]:
    """Every basename an eval's preserved sandbox copy holds."""
    names: set[str] = set()
    if not path.is_dir():
        return names
    for entry in path.rglob("*"):
        names.add(entry.name)
    return names


class HostEscapeGuard:
    """Blame only the host paths an eval's own sandbox names own.

    The shared helper runs ``before`` and ``after`` one call at a time around
    each job. The lock orders the snapshots but cannot attribute a change, so
    ``after`` compares its own snapshot with the current status and keeps only
    the new paths whose basename appears in that eval's preserved sandbox
    copy, the copy ``worker_isolation.preserve_sandbox_copy`` leaves behind in
    the job's ``finally``. An eval with no sandbox copy owns no names and
    stays green, and a still-running sibling's own work never fails it.
    """

    def __init__(self, run_dir: pathlib.Path, eval_ids: list[str]):
        self.run_dir = pathlib.Path(run_dir)
        self.eval_ids = list(eval_ids)
        self.snapshots: dict[int, str] = {}
        self.blamed: dict[int, list[str]] = {}

    def before(self, index: int) -> str:
        snapshot = host_status()
        self.snapshots[index] = snapshot
        return snapshot

    def after(self, index: int, before_state: str | None) -> list[str]:
        before = before_state if before_state is not None else ""
        new_paths = status_paths(host_status()) - status_paths(before)
        owned = sandbox_names(self.run_dir / self.eval_ids[index] / "sandbox")
        blamed = sorted(
            path for path in new_paths if pathlib.Path(path).name in owned
        )
        self.blamed[index] = blamed
        return blamed


@dataclasses.dataclass
class EvalOutcome:
    """One eval's verdict, carried from its job to the post-guard summary.

    The host-escape verdict is decided by the after hook, after the job has
    returned, so the job carries everything the summary, the escape blame,
    and the cache record need instead of printing and caching inside itself.
    """

    eval_id: str
    passed: bool
    cached: bool
    cached_detail: str = ""
    completed: bool = False
    suffix: str = ""
    verdict_note: str = ""
    escape: list[str] = dataclasses.field(default_factory=list)
    cache_key: str | None = None
    model: str = ""
    duration_s: float = 0.0
    worker_rc: int = 0
    grading_output: str = ""
    response_excerpt: str = ""


def _apply_job_temp(deploy_env: dict[str, str], job_env: Mapping[str, str]) -> None:
    """Point the worker at this job's TMPDIR, TEMP, and TMP."""
    for key in ("TMPDIR", "TEMP", "TMP"):
        value = job_env.get(key)
        if value:
            deploy_env[key] = value


def stage(
    eval_id: str,
    target: pathlib.Path,
    env: Mapping[str, str] | None = None,
) -> dict:
    """Run stage.sh and read back the staged values.

    stage.sh prints printf-%q-quoted `name=value` lines meant to be `eval`'d in
    bash, so bash evaluates them and re-emits the raw values NUL-separated. The
    script captures stage.sh's output before evaluating it and exits with
    stage.sh's status when it fails, so a failed stage raises here. An empty or
    missing sandbox_proj raises too, because pathlib.Path("") is the current
    directory and the worker would otherwise start in the checkout. A caller
    that supplies `env` stages under that job's own TMPDIR.
    """
    emit = (
        f'out="$(bash {shlex.quote(str(STAGE))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})" || exit $?; eval "$out"; '
        'printf "%s\\0%s\\0%s\\0%s\\0" '
        '"$sandbox_proj" "$sandbox_target" "$skill_path" "$prompt"'
    )
    result = subprocess.run(
        ["bash", "-c", emit],
        capture_output=True,
        text=True,
        env=dict(env) if env is not None else None,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"stage.sh failed for eval {eval_id} (rc={result.returncode}): "
            f"{result.stderr.strip()}"
        )
    sandbox_proj, sandbox_target, skill_path, prompt, _rest = (
        result.stdout.split("\0")
    )
    if not sandbox_proj or not pathlib.Path(sandbox_proj).is_dir():
        raise RuntimeError(
            f"stage.sh staged no sandbox project for eval {eval_id}: "
            f"{sandbox_proj!r}"
        )
    return {
        "sandbox_proj": sandbox_proj,
        "sandbox_target": sandbox_target,
        "skill_path": skill_path,
        "prompt": prompt,
    }


def reseal(target: str, proj: str) -> None:
    """Commit files the runner staged after stage.sh and record both inventories."""
    command = f'. {shlex.quote(str(FIXTURES / "_common.sh"))}; seal "$1" "$2"'
    result = subprocess.run(
        ["bash", "-c", command, "reseal", target, proj],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"re-seal failed (rc={result.returncode}): "
            f"{(result.stdout + result.stderr).strip()}"
        )


def worker_completed(rc: int, stdout: str) -> bool:
    return rc == 0 and bool(stdout.strip())


def read_worker_version(bin_name: str) -> str:
    """Read the worker CLI version once per run, for the smoke-eval cache key."""
    try:
        result = subprocess.run(
            [bin_name, "--version"], capture_output=True, text=True, timeout=30
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return (result.stdout or result.stderr).strip()


def cache_prompt_value(
    prompt: str,
    plan: vendor.WithheldPlan,
    worker_version: str,
    eval_id: str,
) -> str:
    """The prompt value a cache key folds, including withholding and version.

    Each withheld class joins with its mechanism and its flag or deny entry.
    A smoke eval also folds the worker CLI's version, so a new build re-runs
    every smoke eval.
    """
    parts = [prompt]
    detail = vendor.withheld_detail(plan)
    for tool_class in plan.classes:
        parts.append(f"withheld {tool_class} {detail[tool_class]}")
    if eval_id.startswith("smoke_"):
        parts.append(f"worker-version {worker_version}")
    return "\n".join(parts)


def withheld_suffix(plan: vendor.WithheldPlan, harness: dict) -> str:
    """The class:mechanism list and the declared-absence note for a status line."""
    suffix = ""
    if plan.classes:
        suffix = "; withheld " + ", ".join(
            f"{tool_class}:{plan.withheld_by[tool_class]}"
            for tool_class in plan.classes
        )
    if harness.get("needs_real_absence") and "spawn" in plan.declared:
        suffix += f"; {ABSENCE_SUFFIX}"
    return suffix


def tool_call_lines(turn: int, worker: micro_deploy.WorkerRunResult) -> list[dict]:
    """The stream-only records for one turn, plus its offered classes."""
    lines: list[dict] = []
    if worker.offered_classes is not None:
        lines.append({
            "turn": turn,
            "type": "offered_tools",
            "classes": list(worker.offered_classes),
        })
    for record in worker.stream_tools:
        lines.append({
            "turn": turn,
            "type": "tool_call",
            "class": record.tool_class,
            "name": record.name,
            "helper": record.helper,
            "input": record.input,
            "result": record.result_text,
            "failed": record.failed,
            "parent_tool_use_id": record.parent_tool_use_id,
        })
    return lines


def write_tool_calls(eval_dir: pathlib.Path, turns: list[tuple[int, micro_deploy.WorkerRunResult]]) -> None:
    lines: list[dict] = []
    for turn, worker in turns:
        lines.extend(tool_call_lines(turn, worker))
    text = "".join(json.dumps(line, sort_keys=True) + "\n" for line in lines)
    (eval_dir / "tool_calls.jsonl").write_text(text)


def combined_provenance(
    workers: list[micro_deploy.WorkerRunResult],
) -> tuple[dict, dict]:
    """Both read-check records across every turn of the eval."""
    read_paths: list[str] = []
    out_of_set: list[str] = []
    inside: list[str] = []

    def add(target: list[str], values: list[str]) -> None:
        for value in values:
            if value not in target:
                target.append(value)

    for worker in workers:
        add(read_paths, worker.read_paths)
        add(out_of_set, worker.out_of_set_paths)
        add(inside, worker.inside_checkout_paths)
    return (
        micro_deploy.integrity_record(read_paths, out_of_set),
        micro_deploy.checkout_unread_record(inside),
    )


def preflight_resume(
    resolved: vendor.Resolved,
    run_dir: pathlib.Path,
    timeout: int,
) -> tuple[bool, str]:
    """Prove the vendor's resume path once, inside one micro-deployment.

    The first turn hands the worker a random token, and the resumed turn asks
    for it back. The check passes when the second reply carries the token.
    """
    token = "RESUME_" + uuid.uuid4().hex
    project = run_dir / ".preflight_resume"
    project.mkdir(parents=True, exist_ok=True)
    session_id = str(uuid.uuid4()) if resolved.vendor == "claude" else None
    try:
        with micro_deploy.micro_deploy(
            resolved.vendor, [], project, preflight=False
        ) as deploy:
            first = micro_deploy.run_worker(
                vendor_name=resolved.vendor,
                bin_name=resolved.bin,
                model=resolved.worker_model,
                prompt=(
                    "Remember this token for the next turn: "
                    f"{token}. Reply with exactly: TOKEN_STORED"
                ),
                deploy=deploy,
                timeout=timeout,
                cwd=project,
                session_id=session_id,
            )
            if first.returncode != 0 or not first.stdout.strip():
                return False, f"first turn failed (rc={first.returncode})"
            resume_id = session_id if resolved.vendor == "claude" else first.session_id
            if not resume_id:
                return False, "the first turn's stream carried no session id"
            second = micro_deploy.run_worker(
                vendor_name=resolved.vendor,
                bin_name=resolved.bin,
                model=resolved.worker_model,
                prompt=(
                    "What token did I give you in the previous turn? "
                    "Reply with the token alone."
                ),
                deploy=deploy,
                timeout=timeout,
                cwd=project,
                resume=resume_id,
            )
            if second.returncode != 0:
                return False, f"resumed turn failed (rc={second.returncode})"
            if token not in second.stdout:
                return False, "the resumed turn did not carry the token"
    except (OSError, RuntimeError, subprocess.SubprocessError) as err:
        return False, str(err)
    return True, ""


def run_one(
    index: int,
    eval_id: str,
    spec: dict,
    run_dir: pathlib.Path,
    resolved: vendor.Resolved,
    timeout: int,
    cache,
    force: bool,
    resume_preflight: tuple[bool, str] | None,
    worker_version: str,
    env: Mapping[str, str],
) -> EvalOutcome:
    """Run one eval inside the caller's job, under that job's TMPDIR."""
    eval_dir = run_dir / eval_id
    eval_dir.mkdir(parents=True, exist_ok=True)

    harness = spec.get("harness", {})
    plan = vendor.withheld_tool_plan(
        resolved.vendor, harness.get("disallowed_tools") or []
    )
    second_turn = harness.get("second_turn")
    suffix = withheld_suffix(plan, harness)
    modes = {
        "inline_body": bool(harness.get("inline_body")),
        "second_turn": bool(second_turn),
        "tool_record": bool(harness.get("tool_record")),
        "agents": list(harness.get("agents") or []),
    }
    outcome = EvalOutcome(eval_id=eval_id, passed=False, cached=False,
                          suffix=suffix)

    root = worker_isolation.create_sandbox_root(ISOLATION_PREFIX)
    try:
        try:
            staged = stage(eval_id, root, env)
            plugin_agents, fixture_agents = split_agent_files(harness)
        except (RuntimeError, FileNotFoundError) as exc:
            message = str(exc)
            (eval_dir / "stderr.txt").write_text(f"{message}\n")
            outcome.verdict_note = message
            return outcome
        workdir = staged["sandbox_proj"]
        model_label = resolved.worker_model or "<inherit>"
        staged_agent_names = [
            resolve_agent_path(rel).stem for rel in harness.get("agents") or []
        ]

        key = None
        if cache is not None:
            key = eval_cache.content_key(
                source_roots=source_roots_for(harness),
                harness_dir=THIS,
                model=resolved.worker_model,
                eval_id=eval_id,
                prompt=cache_prompt_value(
                    staged["prompt"], plan, worker_version, eval_id
                ),
                dependencies=spec.get("dependencies"),
            )
            if not force:
                hit = cache.lookup(eval_id, key)
                if hit is not None:
                    eval_cache.write_replay_artifacts(eval_dir, hit)
                    timing_path = eval_dir / "timing.json"
                    try:
                        timing = json.loads(timing_path.read_text())
                    except (OSError, json.JSONDecodeError):
                        timing = {"eval_id": eval_id, "cached": True}
                    timing["withheld_by"] = dict(plan.withheld_by)
                    timing["withheld_classes"] = list(plan.classes)
                    timing_path.write_text(json.dumps(timing, indent=2))
                    outcome.passed = bool(hit["passed"])
                    outcome.cached = True
                    outcome.cached_detail = (
                        f"(graded {hit.get('graded_at', '?')}, "
                        f"model={hit.get('model', '?')}) — skipped "
                        f"{resolved.config.label}; --force to re-run"
                    )
                    return outcome
        outcome.cache_key = key

        if second_turn and resume_preflight is not None and not resume_preflight[0]:
            message = (
                f"resume pre-flight failed for {resolved.vendor}: "
                f"{resume_preflight[1]}"
            )
            (eval_dir / "stderr.txt").write_text(f"{message}\n")
            outcome.verdict_note = message
            return outcome

        print(
            f"  [{eval_id}] running {resolved.config.label} "
            f"(model={model_label}{suffix}) ...",
            flush=True,
        )
        started_at = time.time()
        turns: list[micro_deploy.WorkerRunResult] = []
        turn_timings: list[dict] = []
        try:
            with micro_deploy.micro_deploy(
                resolved.vendor, artefacts_for(harness), pathlib.Path(workdir),
                preflight=False,
            ) as md:
                _apply_job_temp(md.env, env)
                if resolved.vendor == "cursor":
                    vendor.write_cursor_deny_entries(workdir, plan.deny_entries)
                if fixture_agents:
                    vendor.stage_agents(workdir, resolved.vendor, fixture_agents)
                needs_reseal = bool(fixture_agents) or (
                    resolved.vendor == "cursor"
                    and bool(plugin_agents or plan.deny_entries)
                )
                if needs_reseal:
                    reseal(staged["sandbox_target"], workdir)

                first_prompt = with_declared_absence(
                    build_prompt(harness, md, staged, workdir), plan
                )
                claude_session = (
                    str(uuid.uuid4())
                    if second_turn and resolved.vendor == "claude"
                    else None
                )
                turn_start = time.time()
                first = micro_deploy.run_worker(
                    vendor_name=resolved.vendor,
                    bin_name=resolved.bin,
                    model=resolved.worker_model,
                    prompt=first_prompt,
                    deploy=md,
                    timeout=timeout,
                    cwd=pathlib.Path(workdir),
                    extra_args=list(plan.extra_args),
                    prompt_before_flags=bool(plan.extra_args),
                    session_id=claude_session,
                )
                turns.append(first)
                turn_timings.append({
                    "turn": 1,
                    "rc": first.returncode,
                    "duration_s": round(time.time() - turn_start, 3),
                })

                if second_turn:
                    if not worker_completed(first.returncode, first.stdout):
                        pass
                    else:
                        (eval_dir / "response_turn1.txt").write_text(first.stdout)
                        between = second_turn.get("between")
                        if between:
                            script = THIS / between
                            if not script.is_file():
                                raise RuntimeError(
                                    f"between script not found: {script}"
                                )
                            step = subprocess.run(
                                [
                                    "bash", str(script),
                                    staged["sandbox_target"], workdir,
                                ],
                                capture_output=True, text=True,
                            )
                            if step.returncode != 0:
                                raise RuntimeError(
                                    "between script failed "
                                    f"(rc={step.returncode}): "
                                    f"{(step.stdout + step.stderr).strip()}"
                                )
                        resume_id = (
                            claude_session
                            if resolved.vendor == "claude"
                            else first.session_id
                        )
                        if not resume_id:
                            raise RuntimeError(
                                "the first turn's stream carried no session id"
                            )
                        second_prompt = with_declared_absence(
                            str(second_turn.get("prompt", "")), plan
                        )
                        turn_start = time.time()
                        resumed = micro_deploy.run_worker(
                            vendor_name=resolved.vendor,
                            bin_name=resolved.bin,
                            model=resolved.worker_model,
                            prompt=second_prompt,
                            deploy=md,
                            timeout=timeout,
                            cwd=pathlib.Path(workdir),
                            extra_args=list(plan.extra_args),
                            prompt_before_flags=bool(plan.extra_args),
                            resume=resume_id,
                        )
                        turns.append(resumed)
                        turn_timings.append({
                            "turn": 2,
                            "rc": resumed.returncode,
                            "duration_s": round(time.time() - turn_start, 3),
                        })

                integrity, checkout_unread = combined_provenance(turns)
        except RuntimeError as exc:
            message = str(exc)
            (eval_dir / "stderr.txt").write_text(f"{message}\n")
            outcome.verdict_note = message
            return outcome
        ended_at = time.time()
        duration_s = ended_at - started_at

        last = turns[-1]
        rc, stdout = last.returncode, last.stdout
        stderr_parts = [
            f"--- turn {index} ---\n{worker.stderr}"
            for index, worker in enumerate(turns, 1)
            if worker.stderr
        ]
        stderr = "\n".join(stderr_parts)

        (eval_dir / "response.txt").write_text(stdout)
        (eval_dir / "stderr.txt").write_text(stderr)
        (eval_dir / "timing.json").write_text(json.dumps({
            "eval_id": eval_id,
            "started_at": started_at,
            "ended_at": ended_at,
            "duration_s": duration_s,
            "worker_rc": rc,
            "claude_rc": rc,
            "model": model_label,
            "disallowed_tools": list(plan.classes),
            "withheld_by": dict(plan.withheld_by),
            "withheld_classes": list(plan.classes),
            "modes": modes,
            "staged_agents": staged_agent_names,
            "turns": turn_timings,
            "artefacts_read_from_micro_deployment": integrity,
            "checkout_unread": checkout_unread,
        }, indent=2))
        if harness.get("tool_record"):
            write_tool_calls(
                eval_dir,
                [(entry["turn"], worker) for entry, worker in zip(turn_timings, turns)],
            )

        grade_env = dict(env)
        grade_env["EVAL_VENDOR"] = resolved.vendor
        grade = subprocess.run(
            ["bash", str(GRADE), eval_id, workdir, str(eval_dir / "response.txt")],
            capture_output=True, text=True, env=grade_env,
        )
        (eval_dir / "grading.txt").write_text(grade.stdout + grade.stderr)
        print(grade.stdout, end="", flush=True)
        grade_passed = grade.returncode == 0

        completed = worker_completed(rc, stdout)
        passed = (
            grade_passed and completed
            and micro_deploy.read_checks_passed(integrity, checkout_unread)
        )

        outcome.completed = completed
        outcome.passed = passed
        outcome.model = model_label
        outcome.duration_s = duration_s
        outcome.worker_rc = rc
        outcome.grading_output = grade.stdout + grade.stderr
        outcome.response_excerpt = stdout[:eval_cache.RESPONSE_EXCERPT_CHARS]

        if not completed:
            why = ("timeout" if "[TIMEOUT" in stderr
                   else "empty response" if not stdout.strip()
                   else f"worker rc={rc}")
            outcome.verdict_note = f"worker did not complete ({why})"
        else:
            fail = micro_deploy.read_checks_fail_message(
                integrity, checkout_unread, vendor=resolved.vendor
            )
            if fail:
                outcome.verdict_note = fail
        return outcome
    finally:
        worker_isolation.preserve_sandbox_copy(root, eval_dir / "sandbox")


def _print_outcome(outcome: EvalOutcome) -> None:
    """Print one eval's verdict line once the escape guard has reported."""
    suffix = outcome.suffix
    cached = (
        f"; cache hit {outcome.cached_detail}" if outcome.cached else ""
    )
    if outcome.escape:
        paths = ", ".join(outcome.escape)
        print(
            f"  [{outcome.eval_id}] FAIL — the host checkout gained {paths}, "
            f"which this eval's sandbox owns (a sandbox escape){cached}{suffix}\n",
            flush=True,
        )
    elif outcome.verdict_note:
        print(
            f"  [{outcome.eval_id}] FAIL — {outcome.verdict_note}{suffix}\n",
            flush=True,
        )
    elif outcome.cached:
        print(
            f"  [{outcome.eval_id}] CACHED "
            f"{'PASS' if outcome.passed else 'FAIL'} "
            f"{outcome.cached_detail}{suffix}\n",
            flush=True,
        )
    else:
        print(
            f"  [{outcome.eval_id}] "
            f"{'PASS' if outcome.passed else 'FAIL'} "
            f"(worker rc={outcome.worker_rc}{suffix})",
            flush=True,
        )


def _execute(
    specs: dict,
    eval_ids: list[str],
    *,
    run_dir: pathlib.Path,
    resolved: vendor.Resolved,
    timeout: int,
    cache: eval_cache.EvalCache | None,
    force: bool,
    resume_preflight: tuple[bool, str] | None,
    worker_version: str,
    workers: int,
) -> list[tuple[str, bool, bool]]:
    """Run eval_ids through the shared pool. Results follow eval_ids.

    The escape guard brackets every job, so an eval whose sandbox names reach
    the host checkout is blamed after its job returns and before its verdict
    is printed or cached.
    """

    if not eval_ids:
        return []

    guard = HostEscapeGuard(run_dir, eval_ids)

    def make_job(index: int, eval_id: str) -> eval_runner.JobFn:
        def job(env: Mapping[str, str]) -> EvalOutcome:
            return run_one(
                index, eval_id, specs[eval_id], run_dir, resolved, timeout,
                cache, force, resume_preflight, worker_version, env,
            )

        return job

    jobs = [make_job(index, eval_id) for index, eval_id in enumerate(eval_ids)]

    def on_error(index: int, exc: Exception) -> EvalOutcome:
        eval_id = eval_ids[index]
        eval_dir = run_dir / eval_id
        eval_dir.mkdir(parents=True, exist_ok=True)
        (eval_dir / "stderr.txt").write_text(f"{exc}\n")
        return EvalOutcome(
            eval_id=eval_id, passed=False, cached=False,
            verdict_note=str(exc),
        )

    raw = eval_runner.run_jobs(
        jobs,
        workers=workers,
        on_error=on_error,
        before=guard.before,
        after=guard.after,
    )

    rows: list[tuple[str, bool, bool]] = []
    for index, eval_id in enumerate(eval_ids):
        outcome = raw[index]
        blamed = guard.blamed.get(index) or []
        if blamed:
            outcome.escape = list(blamed)
            outcome.passed = False
        _print_outcome(outcome)
        if outcome.completed and outcome.cache_key is not None:
            eval_runner.cache_record(
                cache,
                eval_id,
                outcome.cache_key,
                passed=outcome.passed,
                model=outcome.model,
                duration_s=outcome.duration_s,
                worker_rc=outcome.worker_rc,
                grading_output=outcome.grading_output,
                response_excerpt=outcome.response_excerpt,
            )
        rows.append((eval_id, outcome.passed, outcome.cached))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="*", default=None)
    vendor.add_vendor_arguments(parser)
    eval_runner.add_workers_argument(parser)
    parser.add_argument("--timeout", type=int, default=420)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--no-cache", action="store_true")
    args = parser.parse_args()

    specs = load_evals()
    ids = list(args.ids) if args.ids else list(DEFAULT_IDS)
    unknown = [i for i in ids if i not in specs]
    if unknown:
        print("unknown eval id(s):", ", ".join(unknown))
        return 2

    errors = [error for error in (
        validate_harness(eval_id, specs[eval_id]) for eval_id in ids
    ) if error]
    if errors:
        for error in errors:
            print(f"error: {error}")
        return 2

    cache = None if args.no_cache else eval_cache.EvalCache(THIS / ".eval_cache")
    resolved = vendor.resolve(args)
    model_label = resolved.worker_model or "<inherit>"
    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)
    worker_version = read_worker_version(resolved.bin)

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{ts}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(
        f"Worker vendor: {resolved.vendor}; command: {resolved.config.label}; "
        f"model: {model_label}; workers: {args.workers}; evals: {ids}"
    )

    resume_preflight: tuple[bool, str] | None = None
    if any(specs[eval_id].get("harness", {}).get("second_turn") for eval_id in ids):
        resume_preflight = preflight_resume(resolved, run_dir, args.timeout)
        if resume_preflight[0]:
            print(
                f"Resume pre-flight: PASS ({resolved.vendor}, "
                f"{resolved.config.label})"
            )
        else:
            print(
                f"Resume pre-flight: FAIL ({resolved.vendor}, "
                f"{resolved.config.label}) — {resume_preflight[1]}"
            )

    rows = _execute(
        specs,
        ids,
        run_dir=run_dir,
        resolved=resolved,
        timeout=args.timeout,
        cache=cache,
        force=args.force,
        resume_preflight=resume_preflight,
        worker_version=worker_version,
        workers=args.workers,
    )
    eval_runner.print_summary(rows)

    # The helper prints the graded summary to stdout and writes no file, so
    # this runner keeps its own summary.json as the run's verdict of record.
    summary = {
        "run_dir": str(run_dir),
        "model": model_label,
        "workers": args.workers,
        "passed": sum(1 for _id, passed, _cached in rows if passed),
        "total": len(rows),
        "results": {
            eval_id: {"passed": passed, "cached": was_cached}
            for eval_id, passed, was_cached in rows
        },
    }
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2))

    declared = [
        eval_id for eval_id in ids
        if specs[eval_id].get("harness", {}).get("needs_real_absence")
    ]
    if declared:
        print(
            "Declared-absence evals (the absence rests on the prompt "
            f"declaration): {', '.join(declared)}"
        )

    failures = [eval_id for eval_id, passed, _cached in rows if not passed]
    if failures:
        print("FAILED:", ", ".join(failures))
        return 1
    print("All evals passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
