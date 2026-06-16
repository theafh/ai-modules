---
description: Require an explicit --global or --project-dir scope before deployment.sh touches any target dir, so secondary flags like --clear-backups stop silently triggering a global deploy.
scope: deployment
created: 2026-06-02T23:06:06
updated: 2026-06-16T21:45:29
status: checked
reported-by: Andreas Hoffmann
---

# Require an explicit deployment scope so global stops being a silent fallback

## Goal

Make a deployment scope — `--global` or `--project-dir DIR` — a required, explicit
choice before `deployment/deployment.sh` touches any target directory. Today the
script treats global config dirs as an implicit fallback: running it with a
secondary flag but no scope (the reported case is `--clear-backups` on its own)
silently performs a full **global** deployment into `~/.claude`, `~/.codex`,
`~/.cursor`, `~/.gemini`, and the rest. Deployment should run only when a concrete
scope flag selects one, and otherwise stop with a clear message. Outcome:
`deployment.sh --clear-backups` (and any other non-scope flag alone) no longer
deploys; a global deploy happens only when `--global` is passed explicitly.

## Context

- File: `deployment/deployment.sh`.
- **Arg parsing**: `--global` sets `GLOBAL_MODE=true` and
  `--project-dir` sets `PROJECT_DIR`; the other flags — `--clear-backups`,
  `--dry-run`, `--uninstall`, `--type`, `--target` — set their own state and never
  select a scope.
- **The only current guard** against an unintended run is the zero-arg check:
  `if [[ "$ORIGINAL_ARGC" -eq 0 ]]; then print_usage; exit 0; fi`.
  Any non-empty argv passes it.
- **The conflict guard** rejects `--global` together with
  `--project-dir`, but nothing requires that *one* of them be present.
- **Target-dir selection**: when `PROJECT_DIR` is empty, the
  `else` branch assigns the **global** `$HOME/.*` config dirs.
  This is the silent fallback — with neither scope flag set, deployment proceeds
  against global dirs. There is no `GLOBAL_MODE` gate on the actual deploy.
- **The usage text already promises the intended behavior**: "To
  deploy to global config directories, pass --global explicitly," and it calls
  `--global` "the previous default behavior of running the script with no
  arguments." The code stops enforcing that promise the moment any argument is
  present.
- **Repro:** `./deployment/deployment.sh --clear-backups` clears backups and then
  deploys into the global dirs. Expected: refuse, because no scope was selected.

## Approach

- After arg parsing and the existing `--global` / `--project-dir` conflict check,
  add a **scope-required guard**: when `GLOBAL_MODE` is false and `PROJECT_DIR` is
  empty, print a clear error to stderr naming the missing choice (pass `--global`
  or `--project-dir DIR`), follow it with the usage, and exit non-zero. This
  replaces global-as-fallback with an explicit, required scope.
- Keep the zero-arg path as the friendly help: no arguments still prints usage and
  exits 0. The new guard covers the "arguments present but no scope" case
  (`--clear-backups`, `--dry-run`, `--type …`, `--target …`, `--uninstall` alone),
  which currently slips through.
- Decide `--uninstall`'s scope requirement deliberately and record the call in a
  comment: uninstall works from the deployment log against the global dirs, so
  prefer requiring an explicit scope for every operation that reads or writes
  target dirs — one rule, not an exception list — unless there is a concrete reason
  to exempt it, in which case document that reason inline.
- Leave the global `else`-branch dir assignments unchanged; they now run only once
  `--global` is confirmed present. Keep the toolchain to shell only.

Non-goals: no change to what a global or project deploy does once a scope is
chosen; no new flags; no change to the `--global` + `--project-dir` conflict rule.

Coordinate with [deployment_relocate-state-to-home.md](deployment_relocate-state-to-home.md):
it also edits `deployment/deployment.sh` (the state-path resolution and banner, a
different region), so whichever lands second rebases the other's line references.
This is a co-edited-file coordination link, not a relatedness note.

## Acceptance

- `./deployment/deployment.sh --clear-backups` exits non-zero with a message that
  no deployment scope was selected and that `--global` or `--project-dir` is
  required; it performs no deployment and clears/creates no global artifacts.
- The same guard fires for any other non-scope flag alone — `--dry-run`,
  `--type …`, `--target …`, and (per the deliberate call above) `--uninstall`
  unless explicitly exempted with a documented reason.
- `./deployment/deployment.sh` with no arguments still prints usage and exits 0.
- `./deployment/deployment.sh --global --dry-run` still previews a global deploy
  and exits 0; `--global --clear-backups` still clears then deploys globally.
- `./deployment/deployment.sh --project-dir DIR …` still deploys into the project
  unchanged.
