"""Shared nested-worker auth for the local `claude -p` eval runners.

A `claude -p` worker spawned from inside a Claude Code session must not look
nested, or it expects the parent session's SDK-held auth (which does not reach
grandchild processes) and 401s. Stripping CLAUDECODE makes the child a plain
CLI invocation that reads the CLI's own stored OAuth login (on macOS the
`Claude Code-credentials` keychain item) directly — so no separate token is
needed while that login is present and unexpired. Never pass `--bare`: it
forces ANTHROPIC_API_KEY/apiKeyHelper auth and 401s a subscription login.

A `claude setup-token` headless token stays supported as an optional override
for a machine with no interactive login (e.g. cron): export
CLAUDE_CODE_OAUTH_TOKEN, or store it in the `claude-headless-token` keychain
item, and it wins over the stored OAuth login.

Derived from a sibling skill-eval runner's procedure notes. This module is
the single source of truth the runners import so the wiring does not drift.
Operator doc: tests/CLAUDE.md "Worker auth" section.
"""

from __future__ import annotations

import os
import subprocess
import sys


def worker_env() -> dict:
    """Return an env dict for a nested `claude -p` worker.

    Pops CLAUDECODE (so the child is not treated as nested and reads the
    stored OAuth login) and the host-managed refresh flags. Falls back to the
    `claude-headless-token` keychain item when CLAUDE_CODE_OAUTH_TOKEN is not
    already exported; an exported token wins over both.
    """
    env = os.environ.copy()
    env.pop("CLAUDECODE", None)
    env.pop("CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH", None)
    env.pop("CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH", None)
    if not env.get("CLAUDE_CODE_OAUTH_TOKEN"):
        try:
            tok = subprocess.run(
                ["security", "find-generic-password",
                 "-s", "claude-headless-token", "-w"],
                capture_output=True, text=True, timeout=10,
            ).stdout.strip()
            if tok:
                env["CLAUDE_CODE_OAUTH_TOKEN"] = tok
        except (OSError, subprocess.SubprocessError):
            pass
    return env


def preflight_auth(claude_bin: str = "claude", model: str = "") -> None:
    """Fail fast on a dead login before spawning any eval worker.

    `claude auth status` reports loggedIn even past expiry, so probe live with
    a throwaway `claude -p` from a neutral cwd. On failure, exit with the two
    remediations (re-auth the interactive login, or set a headless token).
    """
    probe = [claude_bin, "-p", "Reply with exactly: PROBE_OK"]
    if model:
        probe += ["--model", model]
    try:
        r = subprocess.run(probe, cwd="/tmp", env=worker_env(),
                           capture_output=True, text=True, timeout=90)
    except (OSError, subprocess.SubprocessError) as e:
        sys.exit(f"auth pre-flight could not launch `{claude_bin} -p`: {e}")
    if r.returncode != 0 or "PROBE_OK" not in r.stdout:
        blob = (r.stdout + r.stderr).strip()
        sys.exit(
            "auth pre-flight failed — nested `claude -p` workers cannot "
            "authenticate. Fix either path, then re-run:\n"
            "  * re-auth the interactive login:  claude auth login\n"
            "  * or set a headless token:        claude setup-token, then\n"
            "      security add-generic-password -a \"$USER\" "
            "-s claude-headless-token -w '<token>' -U\n"
            f"  (probe rc={r.returncode}; output: {blob[:200]!r})"
        )
