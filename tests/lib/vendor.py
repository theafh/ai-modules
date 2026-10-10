"""Shared vendor abstraction for the test harness worker helpers."""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
from dataclasses import dataclass

VENDORS = ("claude", "cursor")

# Isolated-sandbox evals that use tests/lib/eval_runner.py default to this many
# concurrent jobs (each with its own TMPDIR). Pass --workers 1 to serialize.
# Harnesses that share a resource the helper cannot isolate stay sequential;
# see tests/CLAUDE.md and tests/AGENTS.md.
DEFAULT_PARALLEL_WORKERS = 4

CLAUDE_ONLY = {
    "trigger_evals": (
        "this harness inspects Claude-specific skill-load evidence from "
        "`claude -p` runs"
    ),
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


@dataclass(frozen=True)
class VendorConfig:
    """Static defaults for one worker vendor."""

    name: str
    bin: str
    worker_model: str
    judge_model: str
    label: str


@dataclass(frozen=True)
class Resolved:
    """Effective worker settings after CLI overrides are applied."""

    vendor: str
    bin: str
    worker_model: str
    judge_model: str | None
    config: VendorConfig


_CONFIGS = {
    "claude": VendorConfig(
        name="claude",
        bin="claude",
        worker_model="sonnet",
        judge_model="",
        label="claude -p",
    ),
    "cursor": VendorConfig(
        name="cursor",
        bin="agent",
        worker_model="auto",
        judge_model="auto",
        label="agent -p",
    ),
}


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


def resolve(args, *, with_judge: bool = False) -> Resolved:
    """Resolve vendor defaults plus CLI overrides into one object."""

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

    judge_model = None
    if with_judge:
        judge_override = getattr(args, "judge_model", None)
        judge_model = chosen.judge_model if judge_override is None else judge_override

    return Resolved(
        vendor=chosen.name,
        bin=worker_bin or legacy_claude_bin or chosen.bin,
        worker_model=chosen.worker_model if args.model is None else args.model,
        judge_model=judge_model,
        config=chosen,
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
) -> list[str]:
    """Build the non-interactive worker command for one vendor.

    ``output_format`` defaults to plain text on Cursor and to the CLI default
    on Claude. Pass ``stream-json`` to replace Cursor's ``--output-format text``
    and to add ``--output-format stream-json --verbose`` on Claude.
    """

    chosen = config(vendor)
    extras = list(extra_args or [])
    fmt = (output_format or "").strip() or None
    if chosen.name == "claude":
        if prompt_before_flags:
            cmd = [bin, "-p", prompt, "--permission-mode", "bypassPermissions"]
        else:
            cmd = [bin, "-p", "--permission-mode", "bypassPermissions"]
        if model:
            cmd += ["--model", model]
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
    cmd += ["--output-format", fmt or "text"]
    cmd += extras
    cmd.append(prompt)
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


def stage_agents(
    workdir: pathlib.Path,
    vendor: str,
    agent_files: list[pathlib.Path] | None = None,
) -> list[pathlib.Path]:
    """Copy fixture agent files into the sandbox vendor agents directory.

    Discoverable agents that ``discover_artifacts`` names go through the
    deploy script's rendering instead. This helper is the minimal post
    micro-deploy path for fixture agents that are not among those names.
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
        shutil.copy2(agent_path, dest)
        staged.append(dest)
    return staged


def _claude_worker_env() -> dict[str, str]:
    """Return an env dict for a nested `claude -p` worker."""

    env = os.environ.copy()
    env.pop("CLAUDECODE", None)
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
