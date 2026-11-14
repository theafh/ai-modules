---
description: "Give Claude eval workers the micro-deployment's scratch home as HOME, flag bare listings of a real-home agent or skill directory, and keep the tool calls of a pass whose read checks fail."
scope: tests/lib
created: 2026-11-14T16:08:26Z
updated: 2026-11-14T23:20:22Z
status: open
reported-by: Andreas Hoffmann
---

# Give Claude eval workers the scratch home as HOME

## Goal

A Claude eval worker sees the same home as its micro-deployment, so `~/.claude` in its shell resolves to the scratch configuration directory and the operator's deployed skills and agents stay out of reach, as they already do on Cursor. A worker that only lists a real-home agent or skill directory fails its read check the way a worker that reads a file there does. A pass whose read checks fail keeps its tool calls on disk, so the next diagnosis reads the commands instead of reconstructing them.

## Context

- **Claude keeps the real `HOME`.** `_build_env` in `tests/lib/micro_deploy.py` points `HOME` at the scratch home only for Cursor. For Claude it sets `CLAUDE_CONFIG_DIR` to the scratch config directory and `CLAUDE_SECURESTORAGE_CONFIG_DIR` to the empty string, and keeps the real `HOME`. `tests/CLAUDE.md` and `tests/AGENTS.md` document that ("`~` is the scratch home on Cursor but the real home on Claude"), and `tests/lib/test_micro_deploy.py` pins it with the case "claude ~ expands to the real home and fails". The spawn registry is therefore isolated on Claude while the filesystem is not. In the 2026-11-14 Claude suite run, the `depth_one_level` worker listed the operator's agent directory and read two role definitions there, and the `stamp_routed_on_any_rewrite` worker read a deployed skill there. Both failed `artefacts_read_from_micro_deployment` even though their graders passed. The archived role-definitions task promised that "no agent_spinner eval sees a deployed role", which holds on Claude only for the spawn registry. The evening run of the repaired suite then failed `checker_spawned_without_role` the way that task warned: its worker read the operator's `~/.claude/agents/auto_checker_spinner.md` and recorded a role-route probe row, so the eval failed both its read check and "no probe row uses a role route" for a reason that is purely environmental.
- **Bare listings go unflagged.** `_ARTEFACT_PATH_RE` in `tests/lib/micro_deploy.py` needs a name after `agents/` or `skills/`, so `ls ~/.claude/agents` never counts as an artefact read, although its output names the operator's deployed roles. Opus runs of `probe_definitions_no_spawn` and `stamped_target_routed_to_owner` listed real-home artefact directories this way and passed.
- **Failed read checks leave no command record.** The per-pass record in `timing.json` keeps the read paths and `out_of_set`, but no tool-call log unless the eval sets `tool_record`, and the scratch home that holds the worker's transcript is removed when the handle closes. Diagnosing the 2026-11-14 integrity failures meant inferring each command from the order of the recorded paths.
- **Claude behaviour under a scratch `HOME` is unverified.** Keychain OAuth with `CLAUDE_SECURESTORAGE_CONFIG_DIR=""` was probed only with the real `HOME`. The Bash tool's shell snapshot and `PATH`, git's global identity and excludes, and the `~/.claude.json` lookup are all untested under a scratch home. Cursor's branch already handles the same problems: `_link_keychains` and the scratch login profiles, which put back the launch `PATH`.

## Approach

1. Probe a Claude worker under a scratch `HOME` that reuses `_link_keychains` and the login profiles. Check authentication, the Bash tool's `PATH` and shell, git identity, and that `~/.claude` resolves to the scratch config directory. Record the probe as a dated note under `wiki/raw/notes/` and its facts on the Claude Code entity page through the wiki skill family. This probe exercises a Claude-specific feature, the Claude CLI's home and keychain handling, so it runs with `--vendor claude` in the foreground.
2. Set `HOME` to the scratch home in `_build_env`'s Claude branch, which makes `CLAUDE_CONFIG_DIR` and `~/.claude` the same directory. Keep `preflight_auth`'s probe as the run-start check that catches an authentication regression.
3. Widen `_ARTEFACT_PATH_RE`, or add a sibling check, so a listing or glob of a vendor `agents/` or `skills/` directory outside the scratch home and sandbox project counts as an out-of-set read.
4. When `artefacts_read_from_micro_deployment` or `checkout_unread` fails, write the pass's tool calls to `tool_calls.jsonl` in the eval directory before the scratch home is removed.
5. Rewrite in place the passages that state the old Claude behaviour: the "`~` is the scratch home on Cursor but the real home on Claude" sentences in `tests/CLAUDE.md` and `tests/AGENTS.md`, the matching comment in `micro_deploy.py`, and the micro-deployment passage in `wiki/concepts/verification-surfaces.md`, the last through the wiki skill family.

## Acceptance

- `tests/lib/test_micro_deploy.py` asserts that the Claude worker environment sets `HOME` to the scratch home and links the keychains, and that `cat ~/.claude/agents/x.md` classifies as in set. The old "claude ~ expands to the real home and fails" case is replaced, and a grep for it finds nothing.
- A `test_micro_deploy.py` case classifies `ls <real home>/.claude/agents` as out of set, and the same listing under the scratch home as in set.
- A `test_micro_deploy.py` case shows a pass with a failing read check leaving `tool_calls.jsonl` in its eval directory.
- The probe note records the outcome of each check in Approach step 1. If the scratch `HOME` breaks authentication or the shell, the note records how, Approach step 2 stays unapplied, and the task stays open with the failing check named.
- A grep of `tests/CLAUDE.md`, `tests/AGENTS.md`, and `wiki/concepts/verification-surfaces.md` finds no remaining statement that `~` is the real home on Claude.
