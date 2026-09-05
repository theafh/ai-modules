---
description: Gate archive size and repeated-link lint warns behind an opt-in flag for task_fix sweeps so create, update, and close-out lint stay free of permanent archive style noise.
scope: plugins/ai_dev/skills/task
created: 2026-09-05T22:39:53
updated: 2026-09-05T22:39:53
status: open
reported-by: Andreas Hoffmann
---

# Gate archive style lint warns behind an opt-in flag

## Goal

Ordinary task-family lint (create, update, one-task / connected-file checks, and archive close-out verify) reports structural findings only for archived files when archive iteration is needed, and never floods the report with permanent archive `size` or `repeated-link` style debt. Full-tree maintenance (`task_fix` and its escalated `auto_shaper_task` path) can still opt into those archive style warns deliberately.

## Context

`plugins/ai_dev/skills/task/scripts/lint.py` already ships `--include-archive`. Default iteration is live `tasks/*.md` only; the flag extends per-file checks over `tasks/archive/*.md`. Filename collisions always scan both roots. Soft-pointer (`check_no_position_claims`) already returns immediately on archived pages, with the explicit rationale that archived pages are closed records and checking them creates permanent noise.

`check_size` and `check_repeated_links` do not skip archived pages. Once `--include-archive` is on, every archived body is scored for those warns.

Measured on this repo (2026-09-05): default `--quiet` ≈ 39 warns (live only); `--include-archive --quiet` ≈ 122 warns, of which ~95 are archive `repeated-link` and 2 are archive `size`. The delta is historical style debt, not actionable close-out work.

Skill wiring today:

- Create / update / `task_create`: `lint.py --quiet` (no archive iteration) — correct for live work.
- `task_fix` / `auto_shaper_task`: `lint.py --include-archive` — intended full sweep.
- `<archive>` close-out / `task_finish` step 6: also passes `--include-archive` so the just-moved file is checked in its new home. The base `<lint>` text already says other archived findings are pre-existing context for `task_fix`, yet the script still emits the full archive warn set, and agents routinely surface dozens of those lines in ordinary finish reports.

There is no separate flag for archive *style* warns, and no file-scoped lint path that would let close-out verify one archived file without iterating the whole archive.

## Approach

1. **Add an opt-in for archive style warns.** In `lint.py`, keep `--include-archive` as the iterator that includes archived files in per-file checks (blocking frontmatter, location, migration, broken links, naming). Gate `size` and `repeated-link` on archived pages behind a new flag (suggested name: `--archive-style-warns`) that is off by default. When the page is archived and that flag is unset, those two checks return empty the same way soft-pointer already does. Live pages keep today's behaviour under every flag combination.

2. **Wire skills to the split.** `task_fix` and `auto_shaper_task` pass both `--include-archive` and `--archive-style-warns` on assess and verify. Create, update, and the `<archive>` close-out keep `--include-archive` only where structural verify of a moved file still needs archive iteration, and never pass `--archive-style-warns`. Rewrite the base skill `<lint>` / `<archive>` prose so the two flags and their owners are unambiguous: ordinary ops stay quiet on archive style debt; full-tree maintenance opts in.

3. **Prove the gate in the task script harness.** Extend `tests/task/script_tests/` with fixtures that place an oversized and a repeated-link archived page: default and `--include-archive` alone emit neither archive style warn; `--include-archive --archive-style-warns` emits both; live-page style warns remain unchanged without the new flag.

**Out of scope:** Raising or lowering `REPEATED_LINK_FLOOR` or the 300-line ceiling. Rewriting existing archived bodies to clear historical style debt. Adding a general `--path` / connected-file lint mode (useful later for one-task scoping of *live* noise, but not required once archive style debt is gated). Changing soft-pointer's always-skip-on-archive behaviour.

## Acceptance

- `lint.py --help` documents `--archive-style-warns` (or the shipped name) as the opt-in that enables `size` and `repeated-link` on archived pages, and states that `--include-archive` alone does not enable those style warns on archive.
- On a fixture tree with an archived page over 300 lines and an archived page that links one local target twice: `python3 lint.py --quiet` and `python3 lint.py --include-archive --quiet` report zero archive `size` / `repeated-link` findings; `python3 lint.py --include-archive --archive-style-warns --quiet` reports both.
- Soft-pointer continues to skip archived pages under every flag combination (no regression of the existing archive skip).
- Base `task` skill `<lint>` and `<archive>` step 6, plus `task_fix` and `auto_shaper_task`, name which flag set each workflow passes; close-out verify does not opt into archive style warns.
- `tests/task/script_tests/run.sh` covers the three invocation cases above and stays green under the skill's script-test runner.
