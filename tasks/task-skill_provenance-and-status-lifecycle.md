---
description: Add reported-by/implemented-by provenance fields and a seven-state status lifecycle to the task_* family — linter-enforced, with a per-stage status stamp and git-history retrofit of existing tasks.
scope: plugins/ai_dev/skills
created: 2026-06-12T22:21:32
updated: 2026-06-12T22:33:49
status: open
---

# Task provenance and lifecycle status across the task_* family

## Goal

Give every task file two provenance fields and a richer lifecycle status, all enforced by the linter and backfillable onto existing tasks from git history:

- **`reported-by`** — the git user (`git config user.name`) who created the task, written by the create path at creation time.
- **`implemented-by`** — the git user who built the work, written by `task_implement` when the implementation lands.
- **A seven-state `status` lifecycle** — `open → checked → ready → implemented → audited → finished`, with `deferred` as an alternate terminal — replacing today's three-value `open`/`implemented`/`deferred` set. Each stage of the `task_*` chain stamps its own status as it acts, so the frontmatter records how far a task has travelled.

The linter makes all three mandatory, validates `status` against the enum, and — for tasks already tracked that predate these fields — reads git history to derive the missing value and reports a one-time retrofit hint. Backfilling this metadata onto an existing task leaves `updated` untouched.

## Context

**Why.** A task file today records *what* and *when* but not *who*, and its status collapses the whole create→check→implement→audit→finish journey into a single open/closed bit. Recording the reporter and the implementer, plus the stage reached, makes the backlog auditable across people and across time without reading git by hand — and lets a glance at the frontmatter tell open-but-unchecked from checked-and-ready from built-but-unaudited.

**The lifecycle and who stamps each state** — one node per stage owns its outbound transition:

- `open` — created, not yet checked. Written by the create path (`task_create` / base `<create>`).
- `checked` — `task_check` has run at least once and surfaced issues that remain; neither a clean verdict nor a user declaration has yet marked the task ready.
- `ready` — the task is declared implementation-ready by **either** path: `task_check` ran and reported no blocking issue, **or** the user declares it ready (accepting or overriding the check's findings). The clean-verdict path is stamped by `task_check`; the user-declared path is stamped through the base skill's apply-findings update flow.
- `implemented` — the work is built. Written by `task_implement`, together with `implemented-by`.
- `audited` — `task_audit` checked the implementation against the codebase and confirmed **every** body item, acceptance check, and test as genuinely implemented. Running the audit does not by itself advance the status; only a clean, complete verdict flips `implemented`→`audited`. An audit that finds any gap leaves the status at `implemented`.
- `finished` — closed out and archived. Written by `task_finish`.
- `deferred` — parked or dropped without implementation; archived. Written by `task_finish`.

**Status ↔ location.** `open`, `checked`, `ready`, `implemented`, and `audited` live in `tasks/`; only `finished` and `deferred` live in `tasks/archive/`. This moves the archive boundary: `implemented` and `audited` become *working* states that stay in `tasks/`, and the archive move happens only at `task_finish`. The base skill today equates "done" with `implemented`-in-archive (`<when_to_activate>` and `<archive>`); both shift to `finished`.

**Read-only refinement for the gates.** `task_check` and `task_audit` are read-only today ("it judges, it does not edit" / "it makes no state change"). Each gains exactly one allowed mutation: stamping the `status` it just established (`checked`/`ready` for check, `audited` for audit) and bumping `updated`. They still change no task body, no other frontmatter, no code, and move no file — the status stamp is the recorded outcome of their assessment.

**Rule sites** (re-grep `status`, `read-only`, `implemented` across `plugins/ai_dev/skills/task*` before finishing):

- `task/SKILL.md` — the hub. `<frontmatter>` documents the `status` values and the field list: extend the enum to the seven states with the definitions above and add `reported-by`/`implemented-by`. `<when_to_activate>` ("move to archive with status `implemented`") and `<archive>` step 1 ("Set `status` … to `implemented` … or `deferred`") shift `implemented`→`finished`. `<bump_updated>` gains the retrofit exception (below). `<create>`'s `<write>` step writes `reported-by`, and `<update>`'s apply-findings flow stamps `status: ready` when the user declares the task ready over remaining findings. `<lint>` notes the new checks.
- `task_create/SKILL.md` — its `<workflow>` Write step writes `status: open` plus `reported-by` from `git config user.name`.
- `task_check/SKILL.md` — gains the `checked`/`ready` status stamp under the read-only refinement.
- `task_implement/SKILL.md` — sets `status: implemented` and writes `implemented-by` from `git config user.name` when the work lands.
- `task_audit/SKILL.md` — gains the `audited` status stamp on a clean verdict under the read-only refinement.
- `task_finish/SKILL.md` — sets `status: finished` (done) or `deferred` (parked); its "verify before an `implemented` close" step renames to the `finished` close.
- `task_fix/SKILL.md` — applies the retrofits mechanically across the tree (below).
- `task/scripts/lint.py` — `VALID_STATUS`, `ARCHIVE_STATUS`, `REQUIRED_FRONTMATTER`, `check_frontmatter`, `check_location`, plus the new git-history retrofit reporting.

**Git-history retrofit (mechanics verified against this repo on 2026-06-12).** When a tracked task is missing a provenance field, the linter derives the value and reports a fix hint; it reports only and never auto-edits.

- `reported-by` for any tracked task missing it — the author of the commit that first added the file:
  `git log --diff-filter=A --follow --format='%an' -- <file> | tail -1`
- `implemented-by` for an archived task missing it — the author of the commit that moved the file into `archive/`:
  `git log --diff-filter=R --follow --format='%an' -- <archive-file> | head -1`

(Confirmed e.g. against `tasks/archive/task-skill_acceptance-contract.md`, whose archive-move author resolves from the family-overhaul commit.)

**Retrofit does not bump `updated`.** Backfilling `reported-by`, `implemented-by`, or migrating a legacy status onto a pre-existing task is one-time bookkeeping, not work: it leaves `updated` as it was, because `updated` records when the task's content last changed. This is the single exception to `<bump_updated>`; every other status transition on a live task bumps `updated` as usual. The linter's retrofit hints state the no-bump rule inline.

**Existing-data migration.** The repo's archived tasks all carry the legacy `status: implemented` or `deferred`. Under the new `ARCHIVE_STATUS = {finished, deferred}`, an archived task whose status is anything else is a finding whose one-time fix is to set `status: finished` (legacy `implemented`); `deferred` is unchanged. Open tasks keep `status: open` (still valid) and need only the `reported-by` backfill.

**Severity and the deferred case.** `reported-by` (every task) and `implemented-by` (status `implemented`/`audited`/`finished`) are mandatory: absent → blocking, like the existing required fields, but the finding is enriched with the git-derived value and the exact frontmatter line so the fix is mechanical. A `deferred` task was never implemented, so the linter does not require `implemented-by` for it.

**Non-goals.** No strict transition-order enforcement (a task may skip `checked` or `audited`); the linter validates enum membership and status↔location only. No field beyond the two named. The git-history reads are the only git use added — they live in `lint.py` and `task_fix`; no other skill shells out to git for provenance.

## Approach

1. **Base skill (`task/SKILL.md`).** Rewrite `<frontmatter>`'s `status` line into the seven-state enum with the per-state definitions and the status↔location mapping, and add `reported-by`/`implemented-by` field docs (value source `git config user.name`; when each is written). Shift `<when_to_activate>` and `<archive>` from `implemented`→`finished`. Add the retrofit no-bump exception to `<bump_updated>` and reference it (not restate it) from the field docs. Note the new checks in `<lint>`. Give the lifecycle a per-stage status responsibility so each sibling's role names the status it stamps.
2. **Create path.** In `task_create/SKILL.md` and the base `<write>` step, write `reported-by: <git config user.name>` alongside `status: open` at creation.
3. **Check gate.** In `task_check/SKILL.md`, add the read-only refinement: after a run, stamp `status: ready` on a clean, implementation-ready verdict, else `status: checked`, and bump `updated`; change nothing else. The other path to `ready` — the user declaring the task ready over remaining findings — is stamped by the base skill's apply-findings update flow (step 1), not by the check.
4. **Implement.** In `task_implement/SKILL.md`, set `status: implemented` and write `implemented-by: <git config user.name>` when the work lands.
5. **Audit gate.** In `task_audit/SKILL.md`, add the read-only refinement: stamp `status: audited` only on a clean, complete verdict (every item confirmed implemented) and bump `updated`; an audit that finds any gap leaves `status: implemented` and routes the gaps to `task_implement` (the skill's existing hand-off). Change nothing else.
6. **Finish.** In `task_finish/SKILL.md`, set `status: finished` (done) or `deferred` (parked); rename the "verify before an `implemented` close" step to the `finished` close.
7. **Linter (`lint.py`).** Extend `VALID_STATUS` to the seven states and `ARCHIVE_STATUS` to `{finished, deferred}`; add `reported-by` to `REQUIRED_FRONTMATTER` and require `implemented-by` when status ∈ {implemented, audited, finished}. On a missing provenance field for a git-tracked file, shell out to git (queries above) to derive the value and emit a blocking finding carrying the value, the exact frontmatter line to add, and the no-`updated`-bump note. For an archived task whose status is not `finished`/`deferred`, emit the migrate-to-`finished` hint. Guard the git calls so an untracked file (no history) reports "set at creation" rather than erroring.
8. **task_fix.** In `task_fix/SKILL.md`, add the provenance/status retrofit to the mechanical-fix set: read git, write the derived `reported-by`/`implemented-by`, and migrate legacy archived `implemented`→`finished`, all without bumping `updated`.
9. **Prove on fixtures.** Add the minimal scenarios to `tests/tasks/script_tests/` (per the repo's land-with-a-tight-scenario rule; broader harness growth stays in its own session) and run `tests/tasks/run_all.sh`.

## Acceptance

- `VALID_STATUS` in `lint.py` is exactly `{open, checked, ready, implemented, audited, finished, deferred}` and `ARCHIVE_STATUS` is `{finished, deferred}` (false today: three-value set, archive = implemented/deferred).
- A staged fixture with `status: ready` under `tasks/` lints clean, and one with `status: implemented` under `tasks/archive/` raises a blocking finding whose hint names the `finished` migration and the no-`updated`-bump note (false today: `ready` is invalid and archived `implemented` is accepted).
- A staged tracked fixture missing `reported-by` produces a blocking finding carrying the first-commit author (derived via the `--diff-filter=A` first-commit query in Context) and the exact `reported-by:` line to add; an archived fixture missing `implemented-by` carries the archive-move author from the rename-commit query (false today: neither field exists).
- `reported-by` is in `REQUIRED_FRONTMATTER`; a fixture with status `implemented` but no `implemented-by` is blocking, while a `deferred` fixture without `implemented-by` lints clean (false today: no such fields or rules).
- The base `task/SKILL.md` `<frontmatter>` documents all seven states with definitions and the status↔location mapping, and documents `reported-by`/`implemented-by` with `git config user.name` as the value source (false today: status doc lists three values, no provenance fields).
- Each of `task_create`, `task_check`, `task_implement`, `task_audit`, `task_finish` names the status it stamps at its stage, and `task_check`/`task_audit` state the status-only read-only refinement (false today: only `task_finish` sets status; check/audit are unconditionally read-only).
- `task/SKILL.md` `<bump_updated>` states the retrofit-does-not-bump-`updated` exception exactly once, referenced where the fields are documented (false today: no exception exists).
- `task_fix/SKILL.md` lists the git-history provenance/status retrofit among its mechanical auto-fixes, applied without bumping `updated` (false today: not mentioned).
- The new `tests/tasks/script_tests/` scenarios pass and `tests/tasks/run_all.sh` exits 0 (false today: scenarios absent).
