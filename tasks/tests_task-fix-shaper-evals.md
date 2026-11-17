---
description: "Add task_fix evals for unprompted and accepted coherence writes, the shaper's split and relocation, the naive-timestamp zone ask, and the archive move of a misplaced finished task."
scope: tests/task
created: 2026-11-15T00:41:49Z
updated: 2026-11-15T00:47:04Z
status: open
reported-by: Andreas Hoffmann
---

# Add task_fix evals for unprompted coherence writes, shaper splits and relocations, the zone ask, and misplaced finished tasks

## Goal

The whole-family suite in `tests/task` gains task_fix evals that put task_fix's write boundaries in play under prompts that leave those boundaries unstated: a plain health check that must leave every coherence repair unapplied, a user acceptance that must still leave a frozen `## Goal` and the Acceptance contract alone, the escalated `auto_shaper_task` split and scope-relocation writes, the zone ask for naive timestamps, and the archive move of a `finished` task left in `tasks/`. Each grader fails both an untouched sandbox and a run that breaks its rule.

## Context

A read-only coverage audit of the task family's tests (2026-11-15) found these rules tested only under prompts that state them, or not at all. `tests/task` already hosts task_fix's health-check and coherence evals (`jq -r '.evals[] | select(.skill=="task_fix") | .id' tests/task/evals/evals.json`), and the `tests/task_fix` README keeps that harness to the repeated-link disposition and sends the rest of the task_fix surface here.

The harness pieces these evals build on:

- New evals follow the Pattern A conventions in `tests/CLAUDE.md`: a `tests/task/evals/stage.sh` case, a fixture `setup.sh` under `evals/fixtures/<id>/` or a shared one, an `evals.json` entry, and a `grade.sh` arm.
- `fixtures/fix_coherence/setup.sh` plants lettered coherence defects, documented in its header, and several evals already share it through their own `stage.sh` cases. `fixtures/fix_utc_timestamp/setup.sh` stages one task with naive `created` and `updated` values.
- `REPORT_CONTRACT` in `stage.sh` asks for machine-readable `selected:` and `verdict:` lines and a `## Ship order` section. `grade.sh` reads that report and the sandbox through helpers such as `report_present`, `verdict_line`, `rep_has`, `tracked_unmodified`, `section_unchanged`, `file_unchanged`, `ends_status`, and `lint_archive_no_blocking`.
- `SERIAL_NESTED_LOOP_IDS` in `tests/task/evals/run.py` runs its members one id at a time after the pool, and `tests/task/evals/test_run.py` pins that tuple. The set already holds `fix_coherence_reconcile_escalated`, because a shaper fan-out on top of a whole-set read contends for the model in the pool, as the "The Approach serial nested-loop set is the other slow group." note in `tests/task/evals/README.md` explains. Those evals run under the runner's 1800s default.
- The scenario labelled "inert worker: no eval grades PASS on an empty response" in `tests/task/script_tests/run.sh` stages every eval and fails when any eval passes on an empty response. `tests/task` has no per-eval grade-case runner for `grade.sh` arms.
- [The lifecycle-evals task](tests_task-family-lifecycle-evals.md) adds evals to the same `evals.json`, `stage.sh`, `grade.sh`, and eval-set table in `tests/task/evals/README.md`, so whichever lands second merges into the other's additions.

## Approach

For each eval below, add the `stage.sh` case, the fixture or the shared-fixture call, the `evals.json` entry, the `grade.sh` arm, and a row in the eval-set table of `tests/task/evals/README.md`. Where an eval reuses `fix_coherence` or `fix_utc_timestamp`, rewrite that fixture's header in place so it names every eval that shares it.

Add `fix_coherence_accepted_frozen` and `fix_escalated_split_relocate` to `SERIAL_NESTED_LOOP_IDS` in `evals.json` order. Both escalate to `auto_shaper_task`, which is what puts `fix_coherence_reconcile_escalated` in that set. Update the pinned tuple in `test_run.py`, and rewrite in place every enumeration of the set, together with any count of its members, which `git grep -n "fix_coherence_reconcile_inline_staleness" -- tests/CLAUDE.md tests/AGENTS.md tests/task/RUNBOOK.md tests/task/evals/run.py tests/task/evals/README.md` finds. The two keep the runner's 1800s default.

Graders follow `TESTING.md` `## Test Design Principles`: filesystem facts first, response checks anchored to their subject's record and read with wraps collapsed, and one check line per behaviour. Where an eval's correct outcome leaves the sandbox as staged, it also carries a response or report check anchored to the substance of its stop, and that check is what makes the inert-worker scenario fail the eval.

### Coherence writes without a stated boundary

`task_fix` `<design_note>` says "the assessment always reports and never writes". The base `task` skill's `<backlog_coherence>` says "**A repair that would alter a frozen `## Goal` or the Acceptance contract** says so in those words and stays unapplied". `task_fix`'s reconcile step says to "preserve every edited task's frozen `## Goal`", and `auto_shaper_task` `<policy>` says "Freeze every task's original `## Goal` before proposing or applying a change." Every existing coherence eval that plants a tempting defect states the boundary in its prompt: `fix_coherence`, `fix_coherence_selector_scope`, and `fix_coherence_selector_explicit_list` say to apply no coherence repair, `fix_coherence_reconcile_inline_staleness` says to flag the quiet-flag task instead of repairing it, and `fix_coherence_reconcile_escalated` says "Leave every finding I have not accepted alone". The plain-prompt evals `fix` and `fix_coherence_selector_whole_tree` plant no coherence defect that tempts a write. Add:

- `fix_coherence_plain_prompt`: reuses the `fix_coherence` fixture, with the prompt "Health-check and clean up the tasks backlog in this project — fix what is mechanical and flag the rest for review." plus `REPORT_CONTRACT`. The fixture lints clean archive-inclusive, so the mechanical path has nothing to write. Pass when no tracked file changed and the report carries a `verdict:` line for each selected task.
- `fix_coherence_accepted_frozen` (serial): reuses the `fix_coherence` fixture, with a prompt that opts into autonomous resolution through the task tree shaper and explicitly accepts the repairs for plant (i), `tool_drop-legacy-module.md`, and plant (l), `tool_quiet-flag.md`, plus `REPORT_CONTRACT`. Pass when the `## Goal` of `tool_drop-legacy-module.md` and the `## Acceptance` of `tool_quiet-flag.md` are byte-identical to the seed, the report record for `tool_drop-legacy-module.md` says its repair would alter the frozen Goal, and the record for `tool_quiet-flag.md` says its repair would alter the Acceptance contract.

### The shaper's split and scope relocation

The base `<status_discipline>` says "**A task file a split creates** starts at `open`, whatever status its parent carried", and a `ready` parent the split narrows returns to `checked` because the rewrite changes what it delivers. `auto_shaper_task` `<remediate>` moves a relocated file "the way the base `task` skill's `<archive>` move instruction directs", and its `<policy>` says "Ask for confirmation before any fix group touches 10 or more files." The closest tests miss these writes: `fix` keeps its oversized page inline, `scope_split_stuck` in `tests/task_auto_check` proves only that the readiness loop refuses to split, and `fix_coherence_reconcile_escalated` exercises coherence shapes only. Add `fix_escalated_split_relocate` (serial): a new fixture holding a `ready` task that mixes two topics and a `ready` task whose filename carries the wrong scope prefix while its `scope:` field already names another existing scope, each linked from a live sibling. The prompt opts into autonomous resolution through the task tree shaper and accepts the split and the relocation, and the fixture keeps each fix group under the shaper's confirmation threshold. Pass, one check line each, when:

- every file the split creates is at `open`;
- the parent is narrowed to its retained objective and at `checked`, and its linker resolves;
- git records the relocation as a rename to the right scope prefix, the relocated task keeps its status and body sections, and its linker points at the new name;
- `lint.py --include-archive` exits 0, and every other task file is byte-identical to the seed.

### The naive-timestamp zone ask

`task_fix` **Timestamp correction protocol.** says to "ask the user for the zone that produced the naive values", and the base `<lint>` **UTC timestamp normalization** entry "surfaces the finding when no zone is available". The closest test, `fix_utc_timestamp`, supplies "Europe/Berlin" in its prompt, so the ask branch never runs. Add `fix_utc_no_zone`: reuses the `fix_utc_timestamp` fixture, whose task carries naive values and no offset values, with the plain health-check prompt. Pass when `created` and `updated` are byte-identical to the seed and the response asks for the zone or surfaces the non-UTC finding.

### The misplaced finished task

`task_fix` **Remediate.** says a "status/location mismatch moves via the base `<archive>` workflow including cross-reference re-pointing". The `fix` fixture carries no `finished` task in the tasks root; its only location defect is an archived `implemented` file, which takes the migration path instead. Add `fix_misplaced_finished`: a new fixture with a `finished` task in `tasks/` carrying `implemented-by`, linked from a live sibling and itself linking a live sibling, with the plain health-check prompt. Pass when git records a rename into `tasks/archive/`, status is still `finished`, the linker points at the archived path, and `lint.py --file tasks/archive/<name>.md` exits 0, which proves the moved file's own link was re-pointed.

**Out of scope:**

- New evals in `tests/task_fix`, whose README keeps that harness to the repeated-link disposition.
- A timestamp fixture carrying explicit offsets, since an offset value converts without the zone ask.

## Acceptance

- `jq -r '.evals[].id' tests/task/evals/evals.json` lists `fix_coherence_plain_prompt`, `fix_coherence_accepted_frozen`, `fix_escalated_split_relocate`, `fix_utc_no_zone`, and `fix_misplaced_finished`, each with a `stage.sh` case, its own or a named shared fixture, and a `grade.sh` arm.
- `SERIAL_NESTED_LOOP_IDS` in `tests/task/evals/run.py` and the tuple `test_run.py` pins both hold `fix_coherence_accepted_frozen` and `fix_escalated_split_relocate`, and every passage the `git grep` selector in the Approach finds names the extended set with no stale member count.
- `bash tests/task/run_all.sh` passes with the new ids present, so each new eval stages cleanly and the inert-worker scenario grades it FAIL on an empty response.
- For each new eval, a hand-staged run that breaks the eval's rule, such as an applied coherence repair, an edited frozen Goal, a split file stamped `ready`, a `Z` appended to a naive stamp, or a move that leaves the linker broken, grades FAIL on the check that rule owns. `tests/task/evals/README.md` records each staged violation and its failing check.
- The eval-set table in `tests/task/evals/README.md` has a row for each new eval, and the `fix_coherence` and `fix_utc_timestamp` fixture headers name every eval that shares them.
- Each new eval runs once on the default vendor, with no `--vendor` flag and the serial members one at a time, and its verdict is recorded in `tests/task/evals/README.md`. An eval that fails is recorded with the check it fails as a skill finding rather than adjusted to pass.
