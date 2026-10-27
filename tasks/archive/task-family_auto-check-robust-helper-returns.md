---
description: "Make task_auto_check robust on weaker models: final-message helper returns, an output-budget failure class, a context-compaction stop, read-only isolation counting, and high helper effort."
scope: plugins/ai_dev
created: 2026-10-27T11:38:26
updated: 2026-10-27T11:40:00
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Make task_auto_check helper returns and stops robust on weaker models

## Goal

`task_auto_check` and its `auto_*_task` helpers keep working when a smaller model runs them: every helper delivers its whole contract in the one message its caller receives, an empty or truncated helper return is classified and retried as what it is, a recursive search that merely crossed the relay directory no longer forces a gate re-run, the loop stops for the operator at a context compaction instead of continuing on a summary, and the loop helpers run at `high` reasoning effort instead of the deepest level.

## Context

Runs of the loop on 26 October 2026 with a smaller open-weight model failed for harness reasons rather than for unclear contracts. The repo wiki records the evidence in [the run observations note](../../wiki/raw/notes/auto-check-open-weight-run-observations-2026-10-27.md), and its pages [Cursor](../../wiki/entities/cursor.md), [SST OpenCode](../../wiki/entities/sst-opencode.md), and [Agent definition portability](../../wiki/concepts/agent-definition-portability.md) carry the harness facts:

- Cursor hands the parent only a helper's final assistant message, and eleven helper returns put the full contract in an earlier message, then ended with a closing note such as "Decision delivered above."
- Five OpenCode helper calls at the deepest variant ended with finish reason `length` after 32,000 reasoning tokens and no output, and the orchestrator misfiled the empty returns as the spawn-echo glitch to earn a second retry.
- Several gate re-runs fired because a recursive `grep` crossed `.task_auto_check/` and returned nothing from it, which the isolation rule counted as an out-of-bounds read.
- One Cursor run compacted its context several times, and right after a compaction the orchestrator wrote helper returns itself.

The affected files are `plugins/ai_dev/skills/task_auto_check/SKILL.md`, the six `plugins/ai_dev/agents/auto_*_task.md` agents, and `tests/task_auto_check/script_tests/run.sh`.

## Approach

1. **Final-message rule.** Open every `auto_*_task` agent's `<output_contract>` with the rule that the caller receives only the final message, so the helper writes the complete contract as that message, starting with its first heading, and writes nothing after it. In `task_auto_check`'s `<relay>`, name a return that points at an earlier message instead of carrying the contract as contract-violating output.
2. **Output-budget failure.** In `<agent_failure_policy>`, class an empty return, or one the harness reports cut off at its output limit, as an output-budget failure, separate from the spawn-echo glitch, with one identical-prompt retry. A persistent one stops the run with a report that names it and offers lowering the helpers' effort or raising the model's output limit.
3. **Context-compaction stop.** Add `<context_compaction_stop>` to the loop policy: stop at the next round boundary when the harness announces an imminent compaction, and otherwise detect a compaction from its traces (a summary standing in for earlier turns, the original request delivered again, a saved helper return the conversation no longer holds). On detection the loop starts no helper and writes nothing, reads the step reached from the relay directory, and reports to the operator with the options of a fresh-session re-run, continuing under the operator's direction, or abandoning the run, plus restoring `r<N>-pre-apply.txt` when the last applied edits are unaudited. The stop skips `<finalize_mechanical_lint>`, and `<loop_bounds>`, `<iterate>`, and the output contract list it.
4. **Isolation counts reads.** In `auto_gate_task` and `auto_dryrun_task`, exclude `.task_auto_check/` from every recursive search (for example `grep -r --exclude-dir=.task_auto_check`) and define an out-of-bounds read as content opened from, or returned by a search out of, an excluded store. State the same definition in `task_auto_check`'s `<gate>`, so a search that crossed the relay and returned nothing triggers no isolation replacement.
5. **High helper effort.** Pin `effort: high` and `model_reasoning_effort: high` on the five loop helpers (`auto_drift_task`, `auto_dryrun_task`, `auto_gate_task`, `auto_reviewer_task`, `auto_verifier_task`) in place of `max` and `xhigh`. The pin reaches Claude and Codex; on the other harnesses the operator's session or user setting decides, as the wiki pages above record.

**Out of scope:** a behavioral nested-loop eval for these rules, which this change does not author or run; and `auto_shaper_task`'s effort pin, since it is no `task_auto_check` helper.

## Acceptance

- `bash tests/task_auto_check/script_tests/run.sh` passes scenario `s15`, whose final-message, output-budget, pointer-return, compaction-stop, isolation, and effort assertions fail on the files as they stood before this change.
- `grep -c "Your caller receives only your final message." plugins/ai_dev/agents/auto_*_task.md` reports 1 for each of the six agents.
- `grep -E "^(effort|model_reasoning_effort): (max|xhigh)$"` over the five loop helpers finds nothing, and each carries `effort: high` and `model_reasoning_effort: high`.
- `task_auto_check`'s `<agent_failure_policy>` names the output-budget failure and states it is never the spawn-echo glitch, and its `<context_compaction_stop>` block exists and is listed among the stops in `<loop_bounds>`.
