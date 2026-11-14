"""Shared vendor abstraction for the test harness worker helpers."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field

VENDORS = ("claude", "cursor")

# The deploy script's target ids, uppercased for the agent-frontmatter rewrite.
_DEPLOY_TARGETS = ("vscode", "claude", "cursor", "codex", "antigravity", "opencode")
_KNOWN_AGENT_PREFIXES = tuple(target.upper() for target in _DEPLOY_TARGETS)

# Isolated-sandbox evals that use tests/lib/eval_runner.py default to this many
# concurrent jobs (each with its own TMPDIR). Pass --workers 1 to serialize.
# Harnesses that share a resource the helper cannot isolate stay sequential;
# see tests/CLAUDE.md and tests/AGENTS.md.
DEFAULT_PARALLEL_WORKERS = 4

CLAUDE_ONLY = {
    "deployment_styles": (
        "this harness exercises Claude output-style behavior that Cursor does "
        "not expose"
    ),
    "natural_language": (
        "this harness exercises Claude output-style selection"
    ),
}

_VENDOR_ROOTS = {
    "claude": ".claude",
    "cursor": ".cursor",
}

# Compatibility skill roots each vendor also reads, after its native root.
_COMPAT_SKILL_ROOTS = {
    "claude": (),
    "cursor": (".agents", ".claude", ".codex", ".grok"),
}


def skill_roots(vendor: str) -> list[pathlib.Path]:
    """Return a vendor's user-level skill roots, native root first.

    The native root is the one ``make deploy`` writes for that vendor. Cursor
    also reads the compatibility roots its skills documentation lists, so a
    skill copy under one of those is a real load too.
    """

    chosen = config(vendor)
    native = pathlib.Path.home() / _VENDOR_ROOTS[chosen.name] / "skills"
    compat = [
        pathlib.Path.home() / root / "skills"
        for root in _COMPAT_SKILL_ROOTS[chosen.name]
    ]
    return [native, *compat]


@dataclass(frozen=True)
class VendorConfig:
    """Static defaults for one worker vendor.

    An effort is the level the CLI's ``--effort`` flag takes. An empty effort
    omits the flag, so the CLI applies its own default; Cursor has no effort
    control, so both of its efforts stay empty.
    """

    name: str
    bin: str
    worker_model: str
    worker_effort: str
    judge_model: str
    judge_effort: str
    label: str


@dataclass(frozen=True)
class Resolved:
    """Effective worker settings after CLI overrides are applied.

    ``judge_model`` and ``judge_effort`` are ``None`` when the harness has no
    judge (``resolve`` called without ``with_judge``).
    """

    vendor: str
    bin: str
    worker_model: str
    worker_effort: str
    judge_model: str | None
    judge_effort: str | None
    config: VendorConfig


# Claude runs the latest Opus alias at high effort for the worker, the level the
# operator's own sessions run at, and at xhigh for the judge. The measurements
# behind the worker default are recorded under the 2026-11-13 worker model and
# effort probe in tests/agent_spinner/evals/README.md. Those runs measured only
# the worker, so no run there backs the judge default.
_CONFIGS = {
    "claude": VendorConfig(
        name="claude",
        bin="claude",
        worker_model="opus",
        worker_effort="high",
        judge_model="opus",
        judge_effort="xhigh",
        label="claude -p",
    ),
    "cursor": VendorConfig(
        name="cursor",
        bin="agent",
        worker_model="auto",
        worker_effort="",
        judge_model="auto",
        judge_effort="",
        label="agent -p",
    ),
}

# The levels `claude --effort` accepts, named in the help text. Claude is the
# one vendor with an effort control.
EFFORT_LEVELS = ("low", "medium", "high", "xhigh", "max")
EFFORT_VENDORS = ("claude",)


# --- Withheld tool classes ---------------------------------------------------
#
# One row per class of tools the runner can withhold from a worker. A class is
# a group of tools the runner withholds together. `claude` names the tools
# Claude Code calls the class, and `cursor_kind` is the tool-kind key Cursor's
# stream records. The route fields name how each vendor withholds the class:
# `cli-flag` is a command-line flag, `cli-config` is a deny entry in the CLI's
# project config, and `declared-absence` is a prompt note on both vendors.
# `spawn` is declared on both vendors because neither CLI offers a flag or deny
# entry that removes its spawn tool.
WITHHELD_TOOL_CLASSES: dict[str, dict[str, object]] = {
    "spawn": {
        "claude": ("Agent", "Task", "Workflow"),
        "cursor_kind": "taskToolCall",
        "claude_route": "declared-absence",
        "cursor_route": "declared-absence",
    },
    "shell": {
        "claude": ("Bash",),
        "cursor_kind": "shellToolCall",
        "claude_route": "cli-flag",
        "cursor_route": "cli-config",
        "cursor_deny": "Shell(*)",
    },
    "write": {
        "claude": ("Edit", "Write", "NotebookEdit"),
        "cursor_kind": "editToolCall",
        "claude_route": "cli-flag",
        "cursor_route": "cli-config",
        "cursor_deny": "Write(**)",
    },
}

WITHHELD_TOOL_CLASS_NAMES = tuple(WITHHELD_TOOL_CLASSES)


@dataclass(frozen=True)
class WithheldPlan:
    """What one vendor and class list need, and the mechanism that applied."""

    classes: tuple[str, ...] = ()
    extra_args: tuple[str, ...] = ()
    deny_entries: tuple[str, ...] = ()
    declared: tuple[str, ...] = ()
    withheld_by: dict[str, str] = field(default_factory=dict)


def withheld_tool_plan(vendor: str, classes: list[str] | None) -> WithheldPlan:
    """Resolve withheld classes into CLI arguments, deny entries, and notes.

    A value outside the class set raises ``ValueError`` so the caller can stop
    the run before staging, naming the eval. The classes come back in the
    table's canonical order, so a key built from the plan stays stable however
    the eval spells its list.
    """

    chosen = config(vendor)
    requested = list(classes or [])
    unknown = [name for name in requested if name not in WITHHELD_TOOL_CLASSES]
    if unknown:
        raise ValueError(
            "unknown withheld tool class(es) "
            f"{', '.join(sorted(set(unknown)))}; choose from "
            f"{', '.join(WITHHELD_TOOL_CLASS_NAMES)}"
        )

    ordered = [name for name in WITHHELD_TOOL_CLASS_NAMES if name in requested]
    claude_names: list[str] = []
    deny_entries: list[str] = []
    declared: list[str] = []
    withheld_by: dict[str, str] = {}
    for name in ordered:
        row = WITHHELD_TOOL_CLASSES[name]
        if chosen.name == "claude":
            route = str(row["claude_route"])
            if route == "cli-flag":
                claude_names.extend(str(tool) for tool in row["claude"])
                withheld_by[name] = "cli-flag"
            else:
                declared.append(name)
                withheld_by[name] = "declared-absence"
        else:
            route = str(row["cursor_route"])
            if route == "cli-config":
                deny_entries.append(str(row["cursor_deny"]))
                withheld_by[name] = "cli-config"
            else:
                declared.append(name)
                withheld_by[name] = "declared-absence"

    extra_args = ["--disallowedTools", *claude_names] if claude_names else []
    return WithheldPlan(
        classes=tuple(ordered),
        extra_args=tuple(extra_args),
        deny_entries=tuple(deny_entries),
        declared=tuple(declared),
        withheld_by=withheld_by,
    )


def withheld_detail(plan: WithheldPlan) -> dict[str, str]:
    """Each withheld class's mechanism plus its flag or deny entry."""

    detail: dict[str, str] = {}
    for name in plan.classes:
        mechanism = plan.withheld_by[name]
        if mechanism == "cli-flag":
            detail[name] = "cli-flag:" + ",".join(
                str(tool) for tool in WITHHELD_TOOL_CLASSES[name]["claude"]
            )
        elif mechanism == "cli-config":
            detail[name] = "cli-config:" + str(
                WITHHELD_TOOL_CLASSES[name]["cursor_deny"]
            )
        else:
            detail[name] = "declared-absence:prompt-note"
    return detail


def write_cursor_deny_entries(
    workdir: pathlib.Path | str, deny_entries: list[str] | tuple[str, ...]
) -> pathlib.Path | None:
    """Write deny entries into a workdir's Cursor project config.

    The file is ``<workdir>/.cursor/cli.json`` with the shape
    ``{"permissions": {"allow": [], "deny": [...]}}``. An existing file keeps
    its allow list and gains only the entries it lacks.
    """

    entries = [entry for entry in deny_entries if entry]
    if not entries:
        return None
    config_dir = pathlib.Path(workdir) / ".cursor"
    config_dir.mkdir(parents=True, exist_ok=True)
    path = config_dir / "cli.json"
    data: dict[str, object] = {}
    if path.is_file():
        try:
            loaded = json.loads(path.read_text())
            if isinstance(loaded, dict):
                data = loaded
        except json.JSONDecodeError:
            data = {}
    permissions = data.get("permissions")
    if not isinstance(permissions, dict):
        permissions = {}
        data["permissions"] = permissions
    allow = permissions.get("allow")
    if not isinstance(allow, list):
        permissions["allow"] = []
    deny = permissions.get("deny")
    if not isinstance(deny, list):
        deny = []
        permissions["deny"] = deny
    for entry in entries:
        if entry not in deny:
            deny.append(entry)
    path.write_text(json.dumps(data, indent=2) + "\n")
    return path


def classify_tool(vendor: str, name: str) -> str:
    """Return the withheld class a tool name belongs to, or ``other``."""

    chosen = config(vendor)
    for tool_class in WITHHELD_TOOL_CLASS_NAMES:
        row = WITHHELD_TOOL_CLASSES[tool_class]
        if chosen.name == "claude":
            if name in row["claude"]:
                return tool_class
        elif name == row["cursor_kind"]:
            return tool_class
    return "other"


def classify_tool_list(vendor: str, names: list[str]) -> list[str]:
    """Map a stream's tool list to classes, deduplicated in stream order."""

    classes: list[str] = []
    for name in names:
        tool_class = classify_tool(vendor, name)
        if tool_class not in classes:
            classes.append(tool_class)
    return classes


def config(vendor: str) -> VendorConfig:
    """Return the static config for a supported vendor."""

    key = vendor.strip().lower()
    try:
        return _CONFIGS[key]
    except KeyError as err:
        msg = f"unsupported vendor {vendor!r}; choose one of: {', '.join(VENDORS)}"
        raise ValueError(msg) from err


def require_vendor_allowed(vendor: str, harness_id: str) -> None:
    """Exit with a clear message when a harness does not support the vendor."""

    chosen = config(vendor)
    reason = CLAUDE_ONLY.get(harness_id)
    if chosen.name == "cursor" and reason:
        sys.exit(
            f"error: `{harness_id}` is Claude-only and does not support "
            f"`--vendor cursor`: {reason}. Run it with `--vendor claude`, "
            "which is also its default."
        )


def default_vendor(harness_id: str | None = None) -> str:
    """The vendor a harness runs on when `--vendor` is not given.

    Cursor is the project's measurement vendor because its runs are cheaper
    and faster. A Claude-only harness defaults to Claude, the one vendor it
    supports, and stops with an error on an explicit `--vendor cursor`.
    """

    return "claude" if harness_id in CLAUDE_ONLY else "cursor"


def add_vendor_arguments(
    parser: argparse.ArgumentParser,
    *,
    with_judge: bool = False,
    harness_id: str | None = None,
) -> None:
    """Add shared vendor-selection flags to a harness parser.

    Pass ``harness_id`` for a Claude-only harness so its default is Claude.
    """

    default = default_vendor(harness_id)
    parser.add_argument(
        "--vendor",
        choices=VENDORS,
        default=default,
        help=(
            f"Worker vendor. Default: {default}. Pass claude where an eval needs "
            "a Claude-specific feature or the operator asks for a Claude run."
        ),
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Worker model override. Default: vendor worker model. Use '' to inherit.",
    )
    parser.add_argument(
        "--effort",
        default=None,
        choices=("", *EFFORT_LEVELS),
        help=(
            "Worker effort override on Claude ("
            + "|".join(EFFORT_LEVELS)
            + "). Default: vendor worker effort (high on Claude, none on "
            "Cursor). Use '' to omit --effort from the command."
        ),
    )
    parser.add_argument(
        "--worker-bin",
        dest="worker_bin",
        default=None,
        help="Worker binary override. Default: vendor binary.",
    )
    parser.add_argument(
        "--claude-bin",
        dest="claude_bin",
        default=None,
        help="Deprecated alias for --worker-bin.",
    )
    if with_judge:
        parser.add_argument(
            "--judge-model",
            default=None,
            help=(
                "Judge model override. Default: vendor judge model. "
                "Use '' to inherit."
            ),
        )
        parser.add_argument(
            "--judge-effort",
            default=None,
            choices=("", *EFFORT_LEVELS),
            help=(
                "Judge effort override on Claude ("
                + "|".join(EFFORT_LEVELS)
                + "). Default: vendor judge effort (xhigh on Claude, none on "
                "Cursor). Use '' to omit --effort from the judge command."
            ),
        )


def _require_effort_control(chosen: VendorConfig, flag: str, effort: str) -> None:
    """Stop when a non-empty effort is asked of a vendor with no effort control."""

    if effort and chosen.name not in EFFORT_VENDORS:
        sys.exit(
            f"error: `{flag} {effort}` sets an effort level, and only Claude has "
            f"an effort control; `--vendor {chosen.name}` has none. Run with "
            f"`--vendor claude`, or drop `{flag}`."
        )


def resolve(args, *, with_judge: bool = False) -> Resolved:
    """Resolve vendor defaults plus CLI overrides into one object.

    An effort override replaces the vendor default the way ``--model`` does,
    and ``''`` omits the flag. A non-empty effort on a vendor without an effort
    control (Cursor) stops the run with an error naming Claude.
    """

    chosen = config(args.vendor)
    worker_bin = getattr(args, "worker_bin", None)
    legacy_claude_bin = getattr(args, "claude_bin", None)
    if (
        worker_bin
        and legacy_claude_bin
        and worker_bin != legacy_claude_bin
    ):
        sys.exit(
            "conflicting worker binary overrides: pass only one of "
            "`--worker-bin` or `--claude-bin`, or give both the same value"
        )

    effort_override = getattr(args, "effort", None)
    worker_effort = (
        chosen.worker_effort if effort_override is None else effort_override
    )
    if effort_override is not None:
        _require_effort_control(chosen, "--effort", effort_override)

    judge_model = None
    judge_effort = None
    if with_judge:
        judge_override = getattr(args, "judge_model", None)
        judge_model = chosen.judge_model if judge_override is None else judge_override
        judge_effort_override = getattr(args, "judge_effort", None)
        judge_effort = (
            chosen.judge_effort
            if judge_effort_override is None
            else judge_effort_override
        )
        if judge_effort_override is not None:
            _require_effort_control(chosen, "--judge-effort", judge_effort_override)

    return Resolved(
        vendor=chosen.name,
        bin=worker_bin or legacy_claude_bin or chosen.bin,
        worker_model=chosen.worker_model if args.model is None else args.model,
        worker_effort=worker_effort,
        judge_model=judge_model,
        judge_effort=judge_effort,
        config=chosen,
    )


def _check_effort_vendor(chosen: VendorConfig, effort: str) -> None:
    """Refuse a non-empty effort for a vendor with no effort control."""

    if effort and chosen.name not in EFFORT_VENDORS:
        raise ValueError(
            f"effort {effort!r} needs an effort control, which only Claude "
            f"has; vendor {chosen.name!r} takes none"
        )


def worker_env(vendor: str) -> dict[str, str]:
    """Return the environment a worker process should inherit."""

    chosen = config(vendor)
    if chosen.name == "cursor":
        return os.environ.copy()
    return _claude_worker_env()


def build_print_cmd(
    *,
    vendor: str,
    bin: str,
    model: str,
    prompt: str,
    workspace: str | None = None,
    extra_args: list[str] | None = None,
    prompt_before_flags: bool = False,
    output_format: str | None = None,
    session_id: str | None = None,
    resume: str | None = None,
    effort: str = "",
) -> list[str]:
    """Build the non-interactive worker command for one vendor.

    ``output_format`` defaults to plain text on Cursor and to the CLI default
    on Claude. Pass ``stream-json`` to replace Cursor's ``--output-format text``
    and to add ``--output-format stream-json --verbose`` on Claude.

    A non-empty ``effort`` adds ``--effort <level>`` after ``--model`` on
    Claude; the empty default omits it, which the preflight probes rely on.
    Cursor has no effort control, so a non-empty effort there is an error.

    A Claude first turn passes ``--session-id <id>`` and a later turn passes
    ``--resume <id>``. A Cursor first turn passes no session flag and a later
    turn passes ``--resume <id>`` with the session id its first stream carried.
    Passing both ``session_id`` and ``resume`` is an error.
    """

    chosen = config(vendor)
    if session_id and resume:
        raise ValueError("pass either session_id or resume, not both")
    _check_effort_vendor(chosen, effort)
    extras = list(extra_args or [])
    fmt = (output_format or "").strip() or None
    if chosen.name == "claude":
        if prompt_before_flags:
            cmd = [bin, "-p", prompt, "--permission-mode", "bypassPermissions"]
        else:
            cmd = [bin, "-p", "--permission-mode", "bypassPermissions"]
        if model:
            cmd += ["--model", model]
        if effort:
            cmd += ["--effort", effort]
        if resume:
            cmd += ["--resume", resume]
        elif session_id:
            cmd += ["--session-id", session_id]
        if fmt == "stream-json":
            cmd += ["--output-format", "stream-json", "--verbose"]
        elif fmt is not None:
            cmd += ["--output-format", fmt]
        cmd += extras
        if not prompt_before_flags:
            cmd.append(prompt)
        return cmd

    cmd = [bin, "-p", "--force", "--sandbox", "disabled"]
    if workspace is not None:
        cmd += ["--workspace", workspace]
    if model:
        cmd += ["--model", model]
    if resume:
        cmd += ["--resume", resume]
    cmd += ["--output-format", fmt or "text"]
    cmd += extras
    cmd.append(prompt)
    return cmd


def build_stream_cmd(
    *,
    vendor: str,
    bin: str,
    model: str,
    query: str,
    workspace: str | None = None,
    effort: str = "",
) -> list[str]:
    """Build the stream-json worker command for one vendor.

    Claude keeps its print-mode shape and reads the query right after ``-p``.
    Cursor takes ``--trust`` and ``--workspace`` and reads the query last. Both
    commands keep the CLI's default permission mode: neither carries
    ``--permission-mode``, ``--force``, or ``--yolo``. The runner stops each
    worker at its first tool call, so a default-mode read is enough. A
    non-empty ``effort`` adds ``--effort <level>`` after ``--model`` on Claude,
    as in ``build_print_cmd``.
    """

    chosen = config(vendor)
    _check_effort_vendor(chosen, effort)
    if chosen.name == "claude":
        cmd = [
            bin,
            "-p",
            query,
            "--output-format",
            "stream-json",
            "--verbose",
            "--include-partial-messages",
        ]
        if model:
            cmd += ["--model", model]
        if effort:
            cmd += ["--effort", effort]
        return cmd

    cmd = [bin, "-p", "--output-format", "stream-json", "--trust"]
    if workspace is not None:
        cmd += ["--workspace", workspace]
    if model:
        cmd += ["--model", model]
    cmd.append(query)
    return cmd


def preflight_auth(vendor: str, bin: str, model: str = "") -> None:
    """Probe a live worker call so harnesses fail fast on dead auth."""

    prompt = "Reply with exactly: PROBE_OK"
    probe = build_print_cmd(
        vendor=vendor,
        bin=bin,
        model=model,
        prompt=prompt,
    )
    try:
        result = subprocess.run(
            probe,
            cwd="/tmp",
            env=worker_env(vendor),
            capture_output=True,
            text=True,
            timeout=90,
        )
    except (OSError, subprocess.SubprocessError) as err:
        sys.exit(f"auth pre-flight could not launch `{bin} -p`: {err}")

    if result.returncode == 0 and "PROBE_OK" in result.stdout:
        return

    blob = (result.stdout + result.stderr).strip()
    if config(vendor).name == "claude":
        sys.exit(
            "auth pre-flight failed — nested `claude -p` workers cannot "
            "authenticate. Fix either path, then re-run:\n"
            "  * re-auth the interactive login:  claude auth login\n"
            "  * or set a headless token:        claude setup-token, then\n"
            "      security add-generic-password -a \"$USER\" "
            "-s claude-headless-token -w '<token>' -U\n"
            f"  (probe rc={result.returncode}; output: {blob[:200]!r})"
        )

    sys.exit(
        "auth pre-flight failed — live `agent -p` could not authenticate. "
        "Fix either path, then re-run:\n"
        "  * sign in to Cursor/agent again\n"
        "  * or export CURSOR_API_KEY for the worker environment\n"
        f"  (probe rc={result.returncode}; output: {blob[:200]!r})"
    )


def stage_skill_tree(
    sandbox: pathlib.Path,
    skill_dir: pathlib.Path,
    vendor: str,
    agent_files: list[pathlib.Path] | None = None,
) -> pathlib.Path:
    """Stage one skill tree plus optional agents into a vendor sandbox."""

    chosen = config(vendor)
    sandbox = pathlib.Path(sandbox)
    skill_dir = pathlib.Path(skill_dir)
    skill_file = skill_dir / "SKILL.md"
    if not skill_file.is_file():
        raise FileNotFoundError(f"SKILL.md not found under {skill_dir}")

    vendor_root = sandbox / _VENDOR_ROOTS[chosen.name]
    staged_skill_dir = vendor_root / "skills" / skill_dir.name
    staged_skill = staged_skill_dir / "SKILL.md"
    agents_root = vendor_root / "agents"

    # Create the vendor root first so a missing intermediate never races the
    # skills/ and agents/ mkdir calls, and so sandbox runners that block
    # creating a bare `.cursor` / `.claude` leaf fail with a clear path.
    vendor_root.mkdir(parents=True, exist_ok=True)
    (vendor_root / "skills").mkdir(parents=True, exist_ok=True)
    agents_root.mkdir(parents=True, exist_ok=True)

    if staged_skill_dir.exists():
        shutil.rmtree(staged_skill_dir)
    shutil.copytree(skill_dir, staged_skill_dir)

    stage_agents(sandbox, chosen.name, agent_files or [])

    return staged_skill


_AGENT_PREFIX_LINE_RE = re.compile(r"^([A-Z]+)_([A-Za-z0-9_-]+:.*)$")


def render_agent_frontmatter(text: str, vendor: str) -> str:
    """Render an agent file's frontmatter for one vendor, body unchanged.

    The rule mirrors ``rewrite_agent_frontmatter`` in
    ``deployment/deployment.sh``: an unprefixed line stays, the worker
    vendor's own uppercase prefix is stripped, and a line prefixed with any
    other deploy target is dropped together with its indented continuation
    block.
    """

    chosen = config(vendor)
    own = chosen.name.upper()
    in_frontmatter = False
    frontmatter_done = False
    skip_prefixed_block = False
    output: list[str] = []

    for line in text.splitlines():
        if not frontmatter_done and line == "---":
            output.append("---")
            if in_frontmatter:
                in_frontmatter = False
                frontmatter_done = True
            else:
                in_frontmatter = True
            continue

        if in_frontmatter:
            if skip_prefixed_block:
                if not line.strip() or line[:1].isspace():
                    continue
                skip_prefixed_block = False

            match = _AGENT_PREFIX_LINE_RE.match(line)
            if match:
                prefix, rest = match.group(1), match.group(2)
                if prefix == own:
                    output.append(rest)
                    continue
                if prefix in _KNOWN_AGENT_PREFIXES:
                    skip_prefixed_block = True
                    continue

        output.append(line)

    return "\n".join(output) + "\n"


def stage_agents(
    workdir: pathlib.Path,
    vendor: str,
    agent_files: list[pathlib.Path] | None = None,
) -> list[pathlib.Path]:
    """Stage fixture agent files into the sandbox vendor agents directory.

    Each file's frontmatter is rendered for the worker's vendor by
    ``render_agent_frontmatter`` and its body is copied unchanged. Discoverable
    agents that ``discover_artifacts`` names go through the deploy script's
    rendering instead. This helper is the minimal post micro-deploy path for
    fixture agents that are not among those names.
    """

    chosen = config(vendor)
    workdir = pathlib.Path(workdir)
    vendor_root = workdir / _VENDOR_ROOTS[chosen.name]
    agents_root = vendor_root / "agents"
    vendor_root.mkdir(parents=True, exist_ok=True)
    agents_root.mkdir(parents=True, exist_ok=True)
    staged: list[pathlib.Path] = []
    for agent_file in agent_files or []:
        agent_path = pathlib.Path(agent_file)
        if not agent_path.is_file():
            raise FileNotFoundError(f"agent file not found: {agent_path}")
        dest = agents_root / agent_path.name
        dest.write_text(render_agent_frontmatter(agent_path.read_text(), chosen.name))
        shutil.copystat(agent_path, dest)
        staged.append(dest)
    return staged


def _claude_worker_env() -> dict[str, str]:
    """Return an env dict for a nested `claude -p` worker.

    A host `CLAUDE_CODE_EFFORT_LEVEL` would override the `--effort` flag the
    runner passes, while the cache key and run records name the flag's level,
    so the worker never inherits it.
    """

    env = os.environ.copy()
    env.pop("CLAUDECODE", None)
    env.pop("CLAUDE_CODE_EFFORT_LEVEL", None)
    env.pop("CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH", None)
    env.pop("CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH", None)
    if not env.get("CLAUDE_CODE_OAUTH_TOKEN"):
        try:
            token = subprocess.run(
                [
                    "security",
                    "find-generic-password",
                    "-s",
                    "claude-headless-token",
                    "-w",
                ],
                capture_output=True,
                text=True,
                timeout=10,
            ).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            token = ""
        if token:
            env["CLAUDE_CODE_OAUTH_TOKEN"] = token
    return env
