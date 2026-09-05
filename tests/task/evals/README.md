# tests/task/evals: task-family behavioral evals

Pattern A (skill-creator-aligned), operator-driven, with the same three-phase
shape as `tests/git_commit/evals/`: **stage → agent runs → grade**. These
exercise the *skill prose* that drives the agent, covering the base
`task` skill's own hub behaviours, at least one eval per sibling
(task_implement and task_select each add dependency evals; the Out of scope
boundary convention adds task_check / task_implement / task_create /
task_auto_check boundary evals), standing-rule baseline regressions, and
source-fidelity evals on the create path (the lossless-conversion contract).
The bundled-script surface is covered separately by
`../script_tests/` and is the only part `../run_all.sh` auto-runs.

## The eval set (every `id` in `evals.json`)

| id | skill | what it proves |
| --- | --- | --- |
| `create` | task_create | one lint-clean task, `created`/`updated` stamped from the real wall clock (trustworthy timestamps), description in the ~180-char budget, acceptance carries task-specific checks only (no generic gates), no second task |
| `check` | task_check | readiness verdict plus a status-only `checked` stamp: `# General assessment` + a non-empty `## Issues` on an under-specified task, entries located by label per the soft-pointer rule, issues grounded against the repo |
| `standing_rules_create` | task_create | root CLAUDE.md / AGENTS.md only, no family guardrail docs: a copied repo automation rule in a source draft becomes a citation to standing repo rules, not copied task text |
| `standing_rules_check` | task_check | root CLAUDE.md / AGENTS.md only: an otherwise-ready task that copies a standing rule is stamped `checked` with a Restated standing rules finding |
| `standing_rules_check_control` | task_check | the cited-rule control stays clean: a task that cites standing repo rules is stamped `ready` and no restated-rule finding is raised |
| `explain` | task_explain | read-only orientation on one archived task: bottom-line frame plus What / Why / How synthesis, status and scope included, task file unchanged |
| `select` | task_select | read-only next-task recommendation; filters eligible live tasks before ranking, excludes archived and already-implemented work, applies scope narrowing, and explains impact / complexity / friction / bug-fix tradeoffs |
| `select_inbound_dep` | task_select | honours an INBOUND ordering note authored in a task outside the scope filter: blocks the filtered dependent, names the outside-scope prerequisite, recommends the unblocked candidate |
| `select_dep_regression` | task_select | the archived dependency-aware behaviours still hold after the base-taxonomy repoint: creator ranked ahead of consumer (forward-reference hard dep), disjoint companions surface soft with no forced order |
| `implement` | task_implement | writes the code AND a test, leaves the suite green, stamps `implemented` + `implemented-by`, keeps the task live |
| `implement_dep_gate` | task_implement | pre-flight dependency gate: a forward-reference to a block a live task creates is surfaced as a hard prerequisite; the gate lists it, asks, and stops with no code edit |
| `audit_gaps` | task_audit | emits `Gaps:` for an acceptance-mandated test that is missing; leaves status `implemented` |
| `audit_clean` | task_audit | emits `Success: full task compliance confirmed.` when code + test are present; stamps `audited` |
| `finish` | task_finish | status → `finished`, `git mv` to archive/, inbound links re-pointed from open AND archived tasks (both-directories scan), re-lints clean |
| `finish_arch_extended` | task_finish | close-out consumes `design-extended: true` and refreshes the project's `ARCHITECTURE.md` in the same pass, superseding the stale design decision; reports the refreshed disposition with what changed; preserves the signal through the move |
| `finish_arch_declined` | task_finish | `design-extended: false` declines the refresh: `ARCHITECTURE.md` byte-identical to the seed, the decline stated with its reason rather than silently skipped, sibling task untouched |
| `finish_arch_absent` | task_finish | the presence gate on a **true** signal: no `ARCHITECTURE.md` in the project, so none is created and the close-out completes normally, reporting the absent state (staged `true` so the doc's absence is the only thing that can decline the refresh) |
| `fix` | task_fix | whole-tree archive-inclusive run: blocking → zero, legacy archive status migrated, non-ISO datetime normalised, bare line-number reference re-anchored, oversized page left + flagged |
| `query` | task (base) | read-only listing of open tasks grouped by scope; archived task not surfaced; tree unchanged |
| `update` | task (base) | edits a task and bumps `updated` from the wall clock while preserving `created`; stays open, re-lints clean |
| `update_contract` | task (base) | the hub `<output_contract>`: one `<update>` run closes in the four-part shape, with the file touched by relative path (one of two open tasks; the sibling stays byte-identical), no lifecycle move (open, still in `tasks/`), the linter outcome (backlog lints clean), and the assumptions / judgement calls left for the user (two `TBD` placeholders settled in place) |
| `triage` | task (base) | the numbered apply-findings flow: accepted finding applied with its minimum fix, rejected passage byte-identical, user modification winning over the report's suggestion, one bump + one re-lint per round |
| `lossless_split` | task (base) | derives several tasks from a multi-section source, carries the shared preamble into EVERY task, covers every section, leaves the source untouched, and fires unprompted |
| `lossless_single` | task_create | collapses a one-unit source into a single task that still carries every relevant detail; does not skip the coverage check just because one task results; leaves the source untouched |
| `check_boundary_contradiction` | task_check | the extended Contradictions lens surfaces a body-versus-boundary contradiction (an Acceptance item proves work the `**Out of scope:**` block excludes) as a numbered issue, routes disposition through Decide or label, withholds `ready` |
| `check_boundary_clean` | task_check | the optional convention stays invisible: a task carrying NO `**Out of scope:**` block draws no boundary finding |
| `implement_boundary_cross` | task_implement | the crossing backstop: delivering the Goal requires editing a file the `**Out of scope:**` block rejects, so it quotes the conflicting passages, applies reconcile-or-surface, and holds with no edit |
| `implement_boundary_agree` | task_implement | the boundary agrees with the body: an `**Out of scope:**` deferral to a live owner draws no interruption; builds the in-scope work, skips the deferred work, leaves the owner task open |
| `create_scope_trim` | task_create | scope trimmed while authoring lands in the new file's `**Out of scope:**` block as a deferral/rejection, never a silent drop, with no prompt added beyond the create flow |
| `check_exclusion_requirement` | task_check | the not-for side of the block: a guardrail the task builds AND a meta not-an-exclusion note, both filed in `**Out of scope:**`, surface as contradiction-rank findings (relocate / drop) and `ready` is withheld |
| `check_exclusion_requirement_control` | task_check | the precision control: a block holding only genuine work-not-done rejections draws no miscategorization finding and reaches `ready` |
| `check_exclusion_waiver` | task_check | an `**Out of scope:**` entry exempting the task's own change from the root `make lint` gate fires the Rule-waiving exclusions finding on the ordinary Decide-or-label path (no CHARTER.md), withholding `ready` |
| `check_exclusion_waiver_control` | task_check | the carve-out control: an entry tracking a carve-out its governing rule already provides narrows work, not a rule, so no waiver finding fires and the task reaches `ready` |
| `check_count_stable` | task_check | both quantity classes in one body: a frozen mutable-set count (`all 3 plugin manifests under plugins/*/plugin.json`, accurate today) is flagged against the count-stable rule with the selector rewrite as its fix, while the measurement-protocol count (5 runs over a fixed denominator of 6 seeded fixtures against a `make lint` baseline) stays unflagged; the count-stable issue is the fixture's only blocking finding, so the withheld `ready` is attributable to that rule alone; body byte-identical |
| `auto_check_boundary` | task_auto_check | the loop surfaces the gate's boundary contradiction with disposition options through the human-routed stuck channel and never crosses or drops it silently, stopping at `checked`, reached via the fast invalidated-premise stop (the full Boundary-advocate repair loop can't complete headlessly; that stance is covered statically + by `tests/task_auto_check/`) |
| `fix_coherence` | task_fix | the default-on `<backlog_coherence>` assessment over a 17-task jointly incoherent live set: the double-owned `severity_label` edit, the stale `unreachable_clean_bar` anchor, the license finding that re-blocks a sibling's loop exception, the short check-module sweep, and the opposed path/glob postures all come back as alter findings with evidence; the clean task is ship-as-is, the task `tool/report_json.py` invalidates is a defer candidate, the Goal-altering and Acceptance-altering candidates are surfaced not applied, the TOML/JSON fork is a labeled decision with a suggested path, and the ship order places the severity registry ahead of its consumer, with nothing written |
| `fix_coherence_reconcile_escalated` | task_fix | reuses the `fix_coherence` fixture: the accepted five-finding set reconciles through the existing `auto_shaper_task` escalation as the single writer (so the staleness item rides that same write), with the named repair shapes applied, every unaccepted finding untouched, every edited Goal byte-identical, and the archive-inclusive lint clean |
| `fix_coherence_reconcile_inline_staleness` | task_fix | reuses the `fix_coherence` fixture with a staleness-only accept: the anchor refresh and the additive `**Out of scope:**` note land inline with no escalation, the `ready` task stays `ready` (the change-significance rule), the Acceptance-altering candidate is flagged for re-check and not applied, and every withheld judgement call is byte-identical |
| `fix_coherence_selector_scope` | task_fix | the scope-filter selector form: the report assesses exactly the three tool-scope tasks and leaves the two docs-scope tasks out of the selected live set |
| `fix_coherence_selector_explicit_list` | task_fix | the explicit-list selector form: the report assesses exactly the two named tasks and leaves the two unnamed siblings out, though all four share one scope and one target file |
| `fix_coherence_selector_whole_tree` | task_fix | the no-selector default: an ordinary health-check prompt with no coherence phrasing assesses the whole live tree across both scopes and leaves the archived sibling out |

## One-shot run (the default)

`run.py` drives all three phases and pins the skill under test to
**sonnet**, the worker model the repo's test policy standardizes on
(see `tests/CLAUDE.md`). It spawns the worker with `$sandbox_proj` as
the working directory, so `discover_tasks.sh` resolves the sandbox and
never the real repo. The deterministic `grade.sh` it calls uses no
model; the output-verdict expectations stay for you to confirm from the
captured `response.txt` on the inherited session model.

```bash
python3 tests/task/evals/run.py                 # all evals
python3 tests/task/evals/run.py check fix       # just those two
python3 tests/task/evals/run.py lossless_split  # just the split-source fidelity eval
python3 tests/task/evals/run.py --model ''      # inherit the CLI default instead
```

Per eval it writes `workspace/run-<ts>/<id>/{response.txt, stderr.txt,
timing.json, grading.txt}` and exits 0 only if every eval's worker
completed cleanly (CLI rc 0 with a real response) and its grade passed.
A timed-out or crashed worker fails the eval regardless of `grade.sh`,
since `grade.sh` then sees only partial sandbox state. The manual
three-phase workflow below is what `run.py` automates. Reach for it when
debugging a single eval by hand.

> **`auto_check_boundary` is slow and time-variable.** It runs the full
> task_auto_check nested-agent loop (drift → gate → reviewer → verifier)
> and has measured at 405 to 676s. It carries its own `"timeout": 3000` in
> `evals.json`, so it needs no flag. See the fixture header for why no
> `report` codebase is seeded (a valid premise pushes the loop past the
> gate, and the loop then never finishes headlessly).

<!-- -->

> **The `fix_coherence*` evals are the other slow group.** All six read a
> whole live task set plus the artifacts it targets in one context. The
> assess-only and selector ones finish quickly; the two reconcile ones
> want far longer, and `fix_coherence_reconcile_escalated` spawns the
> `auto_shaper_task` → reviewer/verifier fan-out on top of that. The
> `--timeout` default is 1800s so those run without a flag, and a
> timeout is a ceiling rather than a wait, so the fast evals pay nothing
> for it. Run the deep ones sequentially: two nested loops in parallel
> contend for the model and both slow down.

## Manual three-phase workflow

```bash
# 1. Stage one fixture; exports shell-safe name=value lines.
eval "$(bash tests/task/evals/stage.sh <eval_id>)"
#    -> sandbox_proj, skill_name, skill_path, prompt

# 2. Run the skill against the sandbox. run.py does this with a sonnet
#    `claude -p` worker (the policy default). By hand: spawn `claude -p
#    --model claude-sonnet-4-6 --permission-mode bypassPermissions` with
#    $sandbox_proj as the working directory and a prompt that loads
#    $skill_path. An in-session run is fine for a quick look but uses the
#    inherited model, not the pinned worker — debugging, not measurement.
#    RUN THE WORKER WITH $sandbox_proj AS ITS WORKING DIRECTORY so the
#    skill's discover_tasks.sh resolves the sandbox, never the real repo.

# 3. Grade the post-run sandbox programmatically.
bash tests/task/evals/grade.sh <eval_id> "$sandbox_proj"
```

`stage.sh` stages under a fresh `mktemp` dir (the project lives at
`$target/proj`) and drops a `.eval_started_at` marker holding the
run-start epoch. `grade.sh` uses it for the created-timestamp tolerance
and the isolation fail-safe.

## What grade.sh checks vs. agent-attest

`grade.sh` covers everything verifiable from filesystem + git + suite
state: files created/moved, status transitions, `git mv` tracking, link
re-pointing, a clean re-lint, a green test suite, and the
created-timestamp tolerance. It also asserts the **isolation fail-safe**
on every eval: *no writes to the real repo's `tasks/` tree*. It is the same
load-bearing guard the `wiki/` Layer 2 harness uses to justify running on
the operator's real filesystem.

The six `fix_coherence*` evals extend that with one more graded surface:
their prompts ask the agent to write its report to
`coherence-report.md` in the sandbox project root, with a
`selected: <task filenames>` line and one
`verdict: <task> - <ship-as-is|alter|defer-candidate> - <evidence>` line
per task. `grade.sh` never sees the agent's *response* text, so a report
on disk in a structured shape is what makes the selected-set boundary and
the per-task verdicts deterministically gradeable rather than
attest-only. The content asked for is exactly what `task_fix`'s
`<output_contract>` already mandates, and the assess-only evals pair it
with `tracked_unmodified` so a run that writes a repair fails whatever
its report claims.

The output-verdict expectations live in `evals.json`'s `expectations[]`
(LLM-graded by skill-creator's `run_eval`, or confirmed by the operator
from the transcript): the literal `# General assessment`,
`No issues found.`, `Gaps:`, `Success: full task compliance confirmed.`,
and `audit complete — …` strings each skill is instructed to emit. `grade.sh`
lists them as `agent-attest` notes rather than asserting them, because it
never sees the agent's response text.

## Success

For each eval: `grade.sh <id> "$sandbox_proj"` exits 0 with PASS on every
programmatic check, and the operator (or `run_eval`) confirms the
`agent-attest` / `evals.json` output expectations.

## Scope discipline

These evals consume LLM tokens and are NOT auto-run from `run_all.sh`.
Per `tests/CLAUDE.md`, lean on filesystem-state and structured-field
checks first; the prose verdict strings are the one place free-form
response text is load-bearing, and there the exact literal is the signal.
