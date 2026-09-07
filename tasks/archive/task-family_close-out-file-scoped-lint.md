---
description: Give the task linter a file-scoped mode so archive close-out verifies only the file it just moved, instead of sweeping the whole archive and discarding most of the output by hand.
scope: plugins/ai_dev/skills/task
created: 2026-09-05T22:39:53
updated: 2026-09-06T17:47:29
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Scope archive close-out lint to the file it moved

## Goal

Archive close-out verifies exactly the one task file it just moved into `archive/`, reporting only Issues whose path is that moved file, including its `size` and `repeated-link` warns, and emitting no Issue whose path is any other archive file. Full-tree maintenance keeps the archive-wide sweep it owns, unchanged in both the flag it passes and the findings it sees. The linter gains the file-scoped mode the close-out instruction already assumes but cannot currently express.

## Context

`plugins/ai_dev/skills/task/scripts/lint.py` controls scope through one mechanism: `iter_task_files(tasks, include_archive)` yields live `tasks/*.md` by default and adds `tasks/archive/*.md` under `--include-archive`. There is no way to name a single file. `check_name_collisions` deliberately runs over both roots regardless of the flag, because a collision is a whole-tree property.

The base `task` skill's `<archive>` instruction that runs `python3 scripts/lint.py --include-archive --quiet`, then tells the agent to resolve every blocking finding **for that file** and treats findings in other archived files as pre-existing context for `task_fix`. The instruction already asks for file scope. Because the tool cannot express it, close-out runs the whole archive and discards most of the output by hand, which is work an agent does unreliably and at length.

Measured on this repo (2026-09-06): `lint.py --quiet` reports 39 warns over the live tree. `lint.py --include-archive --quiet` reports 122. The 83-warn delta is 81 `repeated-link` and 2 `size` findings scored on archived pages, and close-out is instructed to ignore all of it.

Two facts bound what a fix may assume. `check_no_position_claims` already returns immediately on an archived page, with an in-code rationale that archived pages are closed records so checking them is permanent noise; `check_location` and `check_archive_migration` also call `is_archived` to enforce status-versus-path rules, and those three are the checks that distinguish live from archived today. And the linter's `info` severity has no construction site at all, so `--quiet` currently changes no output for any caller.

The callers today: `task_create`'s `**Lint.**` step and the hub's `<create>` and `<update>` run `lint.py --quiet`; `<archive>` and `task_finish` run `lint.py --include-archive --quiet`; `task_fix` and the `auto_shaper_task` agent run `lint.py --include-archive` on assess and on verify.

## Approach

1. **Add a file-scoped mode to the linter.** Give `lint.py` a `--file <path>` option that restricts the per-file checks to that one task file, resolved under the tasks root and accepted whether the file is live or archived. Reject combining `--file` with `--include-archive` at argparse (mutually exclusive); under `--file`, the named path alone determines the per-file page set, and `--include-archive` remains the full-tree maintenance flag for callers that do not pass `--file`. Keep `check_name_collisions` running over both roots so a collision involving the named file still blocks; under `--file`, include in the report only collision issues whose path is the named file, leaving exit 1 unchanged when that file collides. Leave every check's severity and every exit-code rule as it is: the option changes which pages' findings appear in the report (dual-root collision detection still runs; only the named file's collision finding is emitted), never what a check concludes about a page it does report. Update the module-docstring dual-use prose, the module-docstring `Usage:` CLI list, and the argparse help in the same edit so the prose attributes close-out verification to `--file` and whole-archive maintenance to `--include-archive` under `task_fix` only, and so both the Usage list and argparse help name the new option beside `[TASKS_PATH] [--quiet] [--include-archive]`.

2. **Rewrite the `<archive>` instruction that runs `python3 scripts/lint.py --include-archive --quiet` in place** so close-out runs the linter at the moved file's archived path under `--file` rather than passing `--include-archive`. Supersede the sentence that declares findings in other archived files pre-existing context for `task_fix`, because under file scope the report emits no finding whose path is any other file (dual-root collision detection may still find a basename twin, but the mirror collision issue for that other path is not emitted; the named file's collision message may still mention the twin); state instead that close-out still resolves only blocking findings for the moved file, and that the file-scoped run also surfaces that file's own style warns (`size`, `repeated-link`) without newly requiring those warns to be cleared before close-out completes.

3. **Rewrite the `<lint>` paragraph in place** so `--include-archive` reads as the full-tree maintenance flag with `task_fix` as its sole owner. Supersede the dual-use sentence naming close-out as a second owner, and add the file-scoped invocation to the command block beside the existing three.

4. **Rewrite the `<output_contract>` linter-outcome bullet in place** so a close-out report names the file-scoped invocation that produced the outcome, and names `--include-archive` only when a full-tree maintenance run used that form. Supersede the clause that names `--include-archive` when a close-out used that form, leaving one canonical statement of which invocation a close-out report names.

5. **Extend `tests/task/script_tests/run.sh`** with scenarios covering the file-scoped mode over the cases the acceptance names, following the harness's existing per-scenario staged-tree pattern.

**Out of scope:** Changing which severity any check reports, since this task changes which pages a run inspects rather than what a check says about a page. Adding an opt-in flag that gates the `size` or `repeated-link` checks on archived pages. Reducing the 83-finding archive style debt that full-tree maintenance reports, which this task leaves at its current count. Rewriting archived bodies to clear that debt. Raising or lowering `REPEATED_LINK_FLOOR` or the 300-line ceiling.

## Acceptance

- `lint.py --help` and the module-docstring `Usage:` CLI list both document the file-scoped option, naming it as the mode that restricts per-file checks to one named task file; the module-docstring prose attributes close-out verification to `--file` and whole-archive maintenance to `--include-archive` under `task_fix` only, and the superseded dual-use attribution of close-out to `--include-archive` is absent.
- On a staged tree holding an oversized archived page, an archived page linking one local target twice, and a third archived page carrying a blocking frontmatter defect: running the linter scoped to the oversized archived page reports that page's `size` warn and reports no finding naming either of the other two pages; running the linter scoped to the archived page that links one local target twice reports that page's `repeated-link` warn and reports no finding naming either of the other two pages.
- Running the linter scoped to a live page reports that page's own findings and no finding naming any other page, live or archived.
- Running the linter scoped to a path that does not exist, or that resolves outside the tasks root, exits non-zero with a message naming the offending path.
- Combining `--file` with `--include-archive` exits non-zero with a message that names the conflicting flags; a `--file`-only run still restricts per-file checks to the named path without requiring `--include-archive`.
- On a staged tree where the named file's basename exists in both `tasks/` and `tasks/archive/`, the scoped run still reports the duplicate-filename finding for the named file only (no collision finding whose path is the other colliding file) and exits 1.
- The `<archive>` instruction rewritten from `python3 scripts/lint.py --include-archive --quiet` runs the linter under the file-scoped option at the moved file's archived path; the rewritten instruction states that close-out resolves only blocking findings for the moved file and that the file-scoped run surfaces that file's own `size` and `repeated-link` warns without requiring those warns to be cleared before close-out completes; the superseded `--include-archive` invocation and the superseded sentence declaring other archived findings pre-existing context are both absent from that instruction, leaving one canonical statement of what close-out verifies.
- The `<lint>` section names `--include-archive` as the full-tree maintenance flag owned by `task_fix`, adds the file-scoped invocation to the command block beside the existing three, and the superseded sentence naming the close-out as a co-owner of that flag is absent, leaving one canonical statement of who passes it.
- The `<output_contract>` linter-outcome bullet names the file-scoped invocation for a close-out report; the superseded clause naming `--include-archive` when a close-out used that form is absent, leaving one canonical statement of which invocation a close-out report names.
- `task_fix` and `auto_shaper_task` still pass `--include-archive` with no added option, and `lint.py --include-archive --quiet` over this repo's own backlog still reports its full archive-inclusive finding set (122 warns at the 2026-09-06 baseline, or the then-current count if the backlog has changed).
- `tests/task/script_tests/run.sh` covers the file-scoped CLI behaviours above (`lint.py --help` / module-docstring `Usage:` documentation, scoped archived-page findings, scoped live-page findings, invalid-path exit, conflicting `--file`/`--include-archive` flags, and duplicate-basename collision) and stays green under the skill's script-test runner.
