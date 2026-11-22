---
description: "Make routing a write to a stamped artifact hand the write to its owning family: no agent_spinner writer runs on an owned target, and the ledger refuses a writer before the routing record."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T23:20:22Z
updated: 2026-11-22T01:01:06Z
status: finished
implemented-by: Andreas Hoffmann
design-extended: true
reported-by: Andreas Hoffmann
---

# Make routing a stamped write hand it to the owning family

## Goal

When an agent_spinner run meets a write to an artifact another family has stamped, such as a task file at `status: ready`, it hands that write to the owning family's gate or to the user and dispatches no writer of its own on that path. Routing means the hand-off, not a record made after the run wrote the file. The ledger enforces the order: it refuses a writer brief or dispatch on an owned target unless the user answered a fork for it first, and `close` checks that the routing record precedes any writer on that path.

## Context

All paths are under `plugins/ai_dev/skills/agent_spinner/`.

- **The rule says when, not what.** SKILL.md `<judgement>` says "Route a write to a stamped artifact to that gate or to the user before dispatch, whatever the write changes", and `references/checks.md` C9 says the same. Neither says whether routing hands the write off or is a record after which the run writes it anyway. `<judgement>` also says "An answer the request states is the user's answer", and `<invocation_boundary>` says "Write no family-owned artifact yourself" without saying whether running the family's own workflow inline counts.
- **The ledger allows write-then-route.** `references/run-protocol.md` calls `dispose --routed` "a changed-path disposition". `cmd_close`'s condition 10 checks that a routed disposition exists, not when it was made, and nothing refuses a writer on an owned target.
- **What happened.** In the 2026-11-14 evening Claude run of `stamped_target_routed_to_owner`, the worker deployed and read the `task` skill, recorded the file as an owned target of `task_check`, read the request's edit ask as the answer to the stamped-write gate, dispatched a writer that rewrote `tasks/demo_cache.md`, and only then ran `dispose --routed task_check`; `close` exited 0. The morning Claude run and the Cursor runs held the write and routed it.

**Settled here:** `<judgement>`'s own "whatever the write changes" makes the stamped-write rule override a general edit ask, so routing to the gate hands the write to the family, and the request answers the fork only where it names the stamped artifact and authorizes the run itself to write it. An orchestrator following the family's skill inline is not the family's writer.

This task lands after the terminal-states, brief-contract, report-and-packet, and unanswered-fork tasks, which edit `scripts/run_ledger.py` and `references/run-protocol.md` too, and before the coverage-gates and record-completeness tasks.

## Approach

1. Rewrite SKILL.md `<judgement>`'s stamped-write sentence and `references/checks.md` C9 in place: routing to the owning gate hands the write to that family and dispatches no writer on the path; routing to the user is a fork, answered only by an explicit gate answer or a request that names the artifact and authorizes the run's own write.
2. In SKILL.md `<invocation_boundary>`, state that an orchestrator running a family's workflow inline is not that family's writer.
3. In `scripts/run_ledger.py`, refuse `brief` and `dispatch` for a writer row whose target is an owned target unless an answered fork naming that path predates it — a `fork` record whose `path` field names the target together with the `gate_answered` record whose `gate_id` names either that fork's `id` or the `packet` id the fork's `surfaced` disposition carries, where an `own_authority` record never counts as an answer and an answer the request supplies is recorded as that `gate_answered`. Make `close` condition 10 compare the path's first writer `dispatch` record against its `dispose --routed` disposition: a changed owned-target path whose routed disposition postdates that dispatch fails condition 10 naming the path, and a path whose only route is an answered fork, carrying no routed disposition, is cleared by the guard's prior ordering check rather than re-tested. Rewrite the same two rules into the passages that state the old clearing rather than adding a second sentence beside it: `references/run-protocol.md` `### brief` and `### dispatch` name the owned-target refusal, `### close` condition 10 and the `forks` bullet's `path` sentence carry the ordering test and the refusals in place of the superseded clearing, and `references/checks.md` C9's **Checks** paragraph is replaced to match. Condition 10's clause keeps its `10. A changed path` opening and keeps a `path` field phrase as the answered-fork branch, so `scenario_docs`'s pinned regex still matches, and `scenario_docs` is updated wherever its pinned text changes.
4. Keep `tests/agent_spinner/evals/` as it is unless a check reads the old order; both stamped evals already grade the hand-off. Rebuild `scenario_markers` in `tests/agent_spinner/script_tests/ledger_run.sh` around an answered fork: its base case and its `fork` and `fork-dot` sub-cases each brief `produce:a` on the owned target `a.txt:task:task_finish` before any fork exists, so the new refusal stops the brief, `token_of` reads no token, `accept` rejects the return, no fork record lands, and both fork-clears-condition-10 assertions report FAIL; record each case's answered fork before its brief, and restate every condition-10 assertion the new ordering rule makes unreachable — including the base case's no-routing failure and its status listing — so the scenario proves the ordering and the fork route under the new refusal.

## Acceptance

- A `ledger_run.sh` scenario: a writer brief and a `dispatch` of a writer row on an owned target with no answered fork are each refused; with an answered fork naming the path each is accepted.
- A `ledger_run.sh` scenario: a writer accepted on an owned target under an answered fork naming the path, with its `dispose --routed` record written after the writer, leaves `close` refusing on condition 10 and naming the path; the same run with the routed disposition written before the writer, and a run whose only route is the answered fork with no routed disposition, both close clean.
- SKILL.md `<judgement>`, `<invocation_boundary>`, and `references/checks.md` C9 carry the hand-off rule, and the old sentence no longer stands without it.
- `references/run-protocol.md` `### brief`, `### dispatch`, and `### close` condition 10, its `forks` bullet, and `references/checks.md` C9's **Checks** paragraph state the owned-target refusals and the ordering test in place, with no superseded clearing left standing beside them, and `tests/agent_spinner/script_tests/ledger_run.sh`'s `scenario_docs` passes against the rewritten text.
- `stamped_target_routed_to_owner` and `stamp_routed_on_any_rewrite` run on the default vendor, and their verdicts are recorded in `tests/agent_spinner/evals/README.md`. If either still writes the stamped file, the record names the step and the task stays open.
- `bash tests/agent_spinner/script_tests/ledger_run.sh` passes, with `scenario_markers` rebuilt around an answered fork and its condition-10 assertions restated to the ordering rule.
