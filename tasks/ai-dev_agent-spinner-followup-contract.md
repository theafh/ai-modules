---
description: "Record the subagent follow-up contract in agent_spinner's role prompts so a resumed helper still passes agent and description and stops losing calls to the missing-key error."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-27T09:00:44Z
updated: 2026-11-27T09:00:44Z
status: open
reported-by: Andreas Hoffmann
---

# Record the subagent follow-up contract in agent_spinner

## Goal

An orchestrator that resumes a running helper passes the fields the host still requires, so a follow-up does not fail on a missing `agent` or `description`. The contract lives in `agent_spinner`'s role prompts and run protocol, where the orchestrator reads it before it sends the follow-up.

## Context

- The host's `subagent` tool requires `agent`, `description`, and `prompt` on every call, including a call that passes an existing `sessionID`; only `sessionID`, `model`, and `background` are optional. Its description advertises `sessionID`-only continuation, so an orchestrator reasonably omits `agent` and `description` and is rejected.
- Observed: 70 rejected follow-ups across 47 parent sessions. 69 carried `sessionID`, 64 carried `description`, 69 carried `prompt`, and 0 carried `agent`. Every one recovered on the next call, but the median retry cost 8.9 seconds and the total cost was about 26 minutes, with one retry taking over six minutes.
- The skill's `<helper_failure>` already covers a spawn glitch, a spawn failure, and a contract violation. It does not state the host's follow-up field contract, so the orchestrator learns it only by failing.
- This is a workaround in the skill, not a fix to the host. The host fix belongs upstream and is tracked separately.

## Approach

1. Add one paragraph to `references/role-prompts.md`'s orchestration template: a follow-up call that passes `sessionID` also passes `agent` and `description`, and the prompt restates the item so the child can act without the parent's context.
2. Add the same rule to `references/run-protocol.md`'s follow-up or `attach` entry, so the ledger path and the generic path agree.
3. Add one static check to `tests/agent_spinner/script_tests/run.sh` that both files name the required follow-up fields.
4. Record the upstream defect in the task's Context or in a comment at the rule, so a later reader can delete the workaround once the host accepts a `sessionID`-only follow-up.

**Out of scope:** changing the host tool's schema; that is an upstream change outside this repository.

## Acceptance

- `rg -n "sessionID" plugins/ai_dev/skills/agent_spinner/references/role-prompts.md plugins/ai_dev/skills/agent_spinner/references/run-protocol.md` finds a passage in each that names `agent` and `description` as required on a follow-up.
- `tests/agent_spinner/script_tests/run.sh` carries a check that fails when either passage is removed.
- `bash tests/agent_spinner/script_tests/run.sh` passes.
