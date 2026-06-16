---
description: Require an explicit --global or --project-dir before deployment.sh deploys, while keeping no-scope uninstall and backup cleanup as maintenance modes.
scope: deployment
created: 2026-06-02T23:06:06
updated: 2026-06-16T22:09:29
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Require an explicit deployment scope so global stops being a silent fallback

## Goal

Make a deployment scope — `--global` or `--project-dir DIR` — a required,
explicit choice before `deployment/deployment.sh` deploys into target
directories. Today the script treats global config dirs as an implicit fallback:
running it with a secondary flag but no scope (the reported case is
`--clear-backups` on its own) silently performs a full **global** deployment into
`~/.claude`, `~/.codex`, `~/.cursor`, `~/.gemini`, and the rest. Deployment
should run only when a concrete scope flag selects one, and otherwise stop with a
clear message. Outcome: `deployment.sh --clear-backups` becomes a standalone
maintenance operation that clears managed backups and exits before deploy;
non-scope deploy/filter flags alone no longer deploy; a global deploy happens
only when `--global` is passed explicitly. `deployment.sh --uninstall` remains
log-driven and continues to uninstall without a deployment scope.

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
- **Docs and usage should mirror the script**: script usage and
  `deployment/README.md` currently include no-scope examples such as
  `./deployment/deployment.sh --uninstall` and
  `./deployment/deployment.sh --clear-backups --target cursor,claude`. Keep
  uninstall and standalone backup-cleanup examples no-scope when the script keeps
  those behaviors, and add an explicit scope to examples that deploy.
- **Repro:** `./deployment/deployment.sh --clear-backups` clears backups and then
  deploys into the global dirs. Expected: clear managed backups and exit before
  deployment, because no deploy scope was selected.
- **Mixed-mode combinations need explicit semantics** so the guard does not turn
  into a broad `CLEAR_BACKUPS` bypass: no-scope backup cleanup supports
  `--target` and `--dry-run`; no-scope uninstall keeps its existing `--target`
  and `--type` filters; `--type` without `--uninstall` or a deploy scope remains
  a deploy/artifact filter and requires `--global` or `--project-dir DIR`.

## Approach

- After arg parsing and the existing `--global` / `--project-dir` conflict check,
  add a **scope-required guard**: when `GLOBAL_MODE` is false, `PROJECT_DIR` is
  empty, `UNINSTALL` is false, and `CLEAR_BACKUPS` is false, print a clear error
  to stderr naming the missing choice (pass `--global` or `--project-dir DIR`),
  follow it with the usage, and exit non-zero. This replaces global-as-fallback
  with an explicit, required scope for deploy operations while keeping
  log-driven uninstall and standalone backup cleanup as existing no-scope
  maintenance operations.
- Keep the zero-arg path as the friendly help: no arguments still prints usage and
  exits 0. The new guard covers the "arguments present but no scope" case
  (`--dry-run`, `--type …`, `--target …`), which currently slips through.
- Keep `--clear-backups` without a scope working as backup cleanup only: clear
  managed backups for the selected target filter, then exit before the backup
  creation and deploy phases. Document that call inline near the guard or
  clear-backups branch so the maintenance mode is intentional and stable.
- Keep `--clear-backups --dry-run` without a scope as a cleanup preview: report
  the managed backups that would be removed, exit 0, and perform no backup
  creation or deployment.
- Treat `--clear-backups --type …` without `--uninstall` and without a scope as a
  missing deploy-scope error, because `--type` filters artifacts, not backup
  roots. `--clear-backups --uninstall --type …` remains valid because uninstall
  already uses the type filter.
- Keep `--global --clear-backups` as the explicit global deploy variant: clear
  old managed backups for activated global targets, create fresh backups, then
  deploy globally.
- Keep `--uninstall` without a scope working: it reads the deployment log and
  uninstalls matching entries as it does today. Document that call inline near the
  guard so the exception is intentional and stable rather than an accidental
  bypass.
- Keep `--uninstall --target …` and `--uninstall --type …` without a scope
  working as filtered uninstall operations. If `--clear-backups` is combined with
  no-scope uninstall, clear the selected managed backups first, then uninstall
  matching log entries, and exit without creating fresh backups or deploying.
- Keep `--project-dir DIR --clear-backups` as today's project-dir no-op note for
  backup cleanup, then continue the project deploy; project-dir mode still
  disables backups.
- Leave the global `else`-branch dir assignments unchanged; they now run only once
  `--global` is confirmed present. Keep the toolchain to shell only.
- Update the script usage text and `deployment/README.md` in the same change so
  no-scope examples reflect the final behavior: keep `--uninstall` and
  standalone `--clear-backups` as no-scope maintenance examples, and add
  `--global` or `--project-dir DIR` to examples that deploy, preview, or filter
  deployment.

Non-goals: no change to what a global or project deploy does once a scope is
chosen; no new flags; no change to the `--global` + `--project-dir` conflict rule.

Coordinate with [deployment_relocate-state-to-home.md](../deployment_relocate-state-to-home.md):
it also edits `deployment/deployment.sh` (the state-path resolution and banner, a
different region), so whichever lands second rebases the other's line references.
This is a co-edited-file coordination link, not a relatedness note.

## Acceptance

- `./deployment/deployment.sh --clear-backups` clears managed global backups and
  exits 0 before backup creation or deployment; it performs no deployment and
  creates no new backups.
- `./deployment/deployment.sh --clear-backups --target cursor,claude` clears only
  managed backups for the selected targets and exits before backup creation or
  deployment.
- `./deployment/deployment.sh --clear-backups --dry-run` previews the managed
  backups that would be removed and exits 0 without writing changes, creating
  backups, or deploying.
- `./deployment/deployment.sh --clear-backups --type skill` fails with the
  missing deploy-scope error because `--type` has no backup-cleanup meaning
  outside uninstall.
- The same guard fires for any other non-scope deploy/filter flag alone —
  `--dry-run`, `--type …`, and `--target …`.
- `./deployment/deployment.sh --uninstall` still uninstalls from the deployment
  log without requiring `--global` or `--project-dir`.
- `./deployment/deployment.sh --uninstall --target claude` and
  `./deployment/deployment.sh --uninstall --type skill` still apply the existing
  uninstall filters without requiring `--global` or `--project-dir`.
- `./deployment/deployment.sh --clear-backups --uninstall --target claude` clears
  selected managed backups, uninstalls matching logged entries, creates no fresh
  backups, performs no deploy, and exits 0.
- `./deployment/deployment.sh` with no arguments still prints usage and exits 0.
- `./deployment/deployment.sh --global --dry-run` still previews a global deploy
  and exits 0; `--global --clear-backups` clears old managed backups, creates
  fresh backups, then deploys globally.
- `./deployment/deployment.sh --project-dir DIR …` still deploys into the project
  unchanged.
- `./deployment/deployment.sh --project-dir DIR --clear-backups` still prints the
  existing project-dir backup-disabled note and continues the project deploy
  without backup cleanup or backup creation.
- Script usage text and `deployment/README.md` reflect the final behavior: no
  stale no-scope deploy, preview, or filter examples remain, and the no-scope
  uninstall and clear-backups examples remain because the script still supports
  them as maintenance modes.
