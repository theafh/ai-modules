---
description: "Route the serial implement-then-audit delegation ask to agent_spinner and stop task_* routing from swallowing a task-path prompt that also asks for helpers."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-27T09:00:44Z
updated: 2026-11-27T12:29:05Z
status: open
reported-by: Andreas Hoffmann
---

# Route serial implement/audit delegation to agent_spinner

## Goal

A prompt that asks for a serial two-agent loop — implement, then have a second agent audit, repeat until the task is stamped audited — loads `agent_spinner`. A prompt that names a task file and also asks for helper agents does not route away to `task_*` before the skill is considered. The description and `<selector>` carry a phrase for the serial loop, not only for fan-out, lenses, judges, and verifiers.

## Context

- The skill's `description:` enumerates fan-out over files, parallel helpers, lens panels, judge panels, verifier passes, and cross-checks. It has no phrase for the serial implement/audit loop, even though its own selector table names "Implement one task, a tracked item with its own acceptance list, spanning many files" and the `multi-file-task.md` recipe. It measures 950 characters against `discovery_safety.py`'s 1,000-character risk threshold (`LISTING_BUDGET_RISK_CHARS = 8000 // 8`), so a new clause replaces an existing phrase rather than appending.
- `<invocation_boundary>` routes "a request naming the task backlog or the wiki without naming this skill" to that family. `task_implement` and `task_audit` own no agent loop, so a prompt whose first token is a `tasks/….md` path reads as a backlog request and the delegation discipline falls through the gap.
- Observed: eleven sessions carrying the verbatim ask "implement and audit run in sub-agents until one audit stamps the task as audited" never loaded the skill; several loaded `git_auto_review` later, for the review phase only. Separately, 13 of 16 sessions using an identical pasted multi-agent sweep prompt bypassed the skill, because the prompt itself supplied the discipline.
- The [trigger-drift task](archive/ai-dev_agent-spinner-trigger-drift.md) measured two specific Cursor queries and closed with no description edit, because the confirming runs passed. This task owns the serial-loop phrase and the routing boundary, and the description edit and its budget headroom are its alone.

## Approach

1. Add one clause to the `description:` for the serial loop, in place of a weaker phrase so the description stays within the listing budget that `discovery_safety.py` enforces. The clause names "implement then audit in sub-agents" or an equivalent verbatim trigger, not a generic "agents".
2. Add one `<selector>` row for the serial two-agent loop, pointing at `references/recipes/multi-file-task.md`, so the body and the description agree on the shape.
3. Rewrite `<invocation_boundary>` in place so a task-path prompt that also asks for helper agents stays with `agent_spinner`, while a pure backlog query still goes to `task_*`. State the test the router can apply: does the ask request helper agents, or only backlog work?
4. Add at least two `should_trigger: true` queries to `tests/trigger_evals/agent_spinner.json` in the serial-loop wording, and one `should_trigger: false` query for a pure backlog query.
5. Run the trigger set on the default vendor with three runs per query, record the baseline and the post-change result in `tests/agent_spinner/RUNBOOK.md`, and run `python3 tests/agent_spinner/trigger_overlap.py` after the description edit.

**Out of scope:** changing `task_implement` or `task_audit` to own an agent loop; the routing fix belongs to `agent_spinner`'s own boundary.

## Acceptance

- Both new serial-loop queries load `agent_spinner` in at least two of three runs, and the pure backlog query loads no `agent_spinner`.
- No pre-existing query in `tests/trigger_evals/agent_spinner.json` regresses against the recorded baseline.
- The `description:` stays within the listing budget reported by `discovery_safety.py`, and `tests/agent_spinner/RUNBOOK.md` records the post-change run with date, vendor, model, and per-query counts.
- `rg -n "implement.*audit|serial" plugins/ai_dev/skills/agent_spinner/SKILL.md` finds the description clause and the selector row, and `<invocation_boundary>` states the helper-agent test.
- `bash tests/agent_spinner/script_tests/run.sh` passes.
