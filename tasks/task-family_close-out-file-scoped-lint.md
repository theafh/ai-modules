---
description: Give the task linter a file-scoped mode so archive close-out verifies only the file it just moved, instead of sweeping the whole archive and discarding most of the output by hand.
scope: plugins/ai_dev/skills/task
created: 2026-09-05T22:39:53
updated: 2026-09-06T09:21:49
status: open
reported-by: Andreas Hoffmann
---

# Scope archive close-out lint to the file it moved

## Goal

Archive close-out verifies exactly the one task file it just moved into `archive/`, reporting that file's own findings including its `size` and `repeated-link` warns, and reporting nothing about the rest of the archive. Full-tree maintenance keeps the archive-wide sweep it owns, unchanged in both the flag it passes and the findings it sees. The linter gains the file-scoped mode the close-out instruction already assumes but cannot currently express.

## Context

`plugins/ai_dev/skills/task/scripts/lint.py` controls scope through one mechanism: `iter_task_files(tasks, include_archive)` yields live `tasks/*.md` by default and adds `tasks/archive/*.md` under `--include-archive`. There is no way to name a single file. `check_name_collisions` deliberately runs over both roots regardless of the flag, because a collision is a whole-tree property.

The base `task` skill's `<archive>` step 6 runs `python3 scripts/lint.py --include-archive --quiet`, then tells the agent to resolve every blocking finding **for that file** and treats findings in other archived files as pre-existing context for `task_fix`. The instruction already asks for file scope. Because the tool cannot express it, close-out runs the whole archive and discards most of the output by hand, which is work an agent does unreliably and at length.

Measured on this repo (2026-09-06): `lint.py --quiet` reports 39 warns over the live tree. `lint.py --include-archive --quiet` reports 122. The 83-warn delta is 81 `repeated-link` and 2 `size` findings scored on archived pages, and close-out is instructed to ignore all of it.

Two facts bound what a fix may assume. `check_no_position_claims` already returns immediately on an archived page, with an in-code rationale that archived pages are closed records so checking them is permanent noise; no other check distinguishes live from archived. And the linter's `info` severity has no construction site at all, so `--quiet` currently changes no output for any caller.

The callers today: `task_create` step 8 and the hub's `<create>` and `<update>` run `lint.py --quiet`; `<archive>` step 6 and `task_finish` run `lint.py --include-archive --quiet`; `task_fix` and the `auto_shaper_task` agent run `lint.py --include-archive` on assess and on verify.

## Approach

1. **Add a file-scoped mode to the linter.** Give `lint.py` a `--file <path>` option that restricts the per-file checks to that one task file, resolved under the tasks root and accepted whether the file is live or archived. Keep `check_name_collisions` running over both roots so a collision involving the named file still blocks. Leave every check's severity and every exit-code rule as it is: the option changes which pages are inspected, never what a check reports about a page. Update the module-docstring `Usage:` CLI list and the argparse help in the same edit so both name the new option beside `[TASKS_PATH] [--quiet] [--include-archive]`.

2. **Rewrite `<archive>` step 6 in place** so close-out runs the linter at the moved file's archived path under `--file` rather than passing `--include-archive`. Supersede the sentence that declares findings in other archived files pre-existing context for `task_fix`, because under file scope the run produces none; state instead that close-out resolves the moved file's findings, which now include that file's own style warns.

3. **Rewrite the `<lint>` paragraph in place** so `--include-archive` reads as the full-tree maintenance flag with `task_fix` as its sole owner. Supersede the dual-use sentence naming close-out as a second owner, and add the file-scoped invocation to the command block beside the existing three.

4. **Extend `tests/task/script_tests/run.sh`** with scenarios covering the file-scoped mode over the cases the acceptance names, following the harness's existing per-scenario staged-tree pattern.

**Out of scope:** Changing which severity any check reports, since this task changes which pages a run inspects rather than what a check says about a page. Adding an opt-in flag that gates the `size` or `repeated-link` checks on archived pages. Reducing the 83-finding archive style debt that full-tree maintenance reports, which this task leaves at its current count. Rewriting archived bodies to clear that debt. Raising or lowering `REPEATED_LINK_FLOOR` or the 300-line ceiling.

## Acceptance

- `lint.py --help` and the module-docstring `Usage:` CLI list both document the file-scoped option, naming it as the mode that restricts per-file checks to one named task file.
- On a staged tree holding an oversized archived page, an archived page linking one local target twice, and a third archived page carrying a blocking frontmatter defect: running the linter scoped to the oversized archived page reports that page's `size` warn and reports no finding naming either of the other two pages.
- Running the linter scoped to a live page reports that page's own findings and no finding naming any other page, live or archived.
- Running the linter scoped to a path that does not exist, or that resolves outside the tasks root, exits non-zero with a message naming the offending path.
- On a staged tree where the named file's basename exists in both `tasks/` and `tasks/archive/`, the scoped run still reports the duplicate-filename finding and exits 1.
- The `<archive>` step 6 instruction runs the linter under the file-scoped option at the moved file's archived path; the superseded `--include-archive` invocation and the superseded sentence declaring other archived findings pre-existing context are both absent from that step, leaving one canonical statement of what close-out verifies.
- The `<lint>` section names `--include-archive` as the full-tree maintenance flag owned by `task_fix`, and the superseded sentence naming the close-out as a co-owner of that flag is absent, leaving one canonical statement of who passes it.
- `task_fix` and `auto_shaper_task` still pass `--include-archive` with no added option, and `lint.py --include-archive --quiet` over this repo's own backlog still reports its full archive-inclusive finding set (122 warns at the 2026-09-06 baseline, or the then-current count if the backlog has changed).
- `tests/task/script_tests/run.sh` covers each behaviour above and stays green under the skill's script-test runner.
