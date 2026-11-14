---
description: "Make routing a write to a stamped artifact hand the write to its owning family: no agent_spinner writer runs on an owned target, and the ledger refuses a writer before the routing record."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T23:20:22Z
updated: 2026-11-14T23:54:21Z
status: open
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
3. In `scripts/run_ledger.py`, refuse `brief` and `dispatch` for a writer row whose target is an owned target unless an answered fork naming that path predates it, and make `close` condition 10 fail when a writer on an owned target precedes the path's routing record. Document both in `references/run-protocol.md`.
4. Keep `tests/agent_spinner/evals/` as it is unless a check reads the old order; both stamped evals already grade the hand-off.

## Acceptance

- A `ledger_run.sh` scenario: a writer brief on an owned target with no answered fork is refused; with an answered fork naming the path it is accepted.
- A `ledger_run.sh` scenario: a writer accepted on an owned target before its `dispose --routed` record leaves `close` refusing on condition 10.
- SKILL.md `<judgement>`, `<invocation_boundary>`, and `references/checks.md` C9 carry the hand-off rule, and the old sentence no longer stands without it.
- `stamped_target_routed_to_owner` and `stamp_routed_on_any_rewrite` run on the default vendor, and their verdicts are recorded in `tests/agent_spinner/evals/README.md`. If either still writes the stamped file, the record names the step and the task stays open.
