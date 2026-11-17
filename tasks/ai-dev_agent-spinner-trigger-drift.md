---
description: "Win back the two agent_spinner trigger queries that regressed on Cursor against the 18/18 baseline: the helper-report merge ask, and the harness tool-name ask that belongs to harness_portability."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-17T10:06:07Z
status: open
reported-by: Andreas Hoffmann
---

# Win back agent_spinner's two drifted trigger queries

## Goal

The agent_spinner trigger set holds its 18/18 precise baseline on the default vendor again, or each query that keeps failing carries a recorded disposition. Two queries regressed on the same `description:` text:

- "merge what the helper agents reported into one answer without just counting how many of them agreed" should load agent_spinner, and loaded no skill.
- "which tool names do I need for a read-only subagent on each harness we target?" should load no family skill (it belongs to harness_portability), and loaded agent_spinner.

## Context

- **The measurement.** The baseline is the 2026-11-10 Cursor `auto` run of the set (3 runs per query, 18/18), recorded in `tests/agent_spinner/RUNBOOK.md` and taken on the trimmed description that commit `1174815` shipped. On 2026-11-14, three runs of the same set against that baseline each failed one or both queries at 0/3: 17/18, 17/18, and 16/18. Each query failed in two of the three runs, as the RUNBOOK's "Recorded measurements" table records. The deployed copy under the Cursor skills root matched the source description throughout, so the description did not change; the router behind Cursor's `auto` did. Trigger-run output stays local, so re-measure rather than assume a prior result on another machine.
- **The text in play.** agent_spinner's description in `plugins/ai_dev/skills/agent_spinner/SKILL.md` already lists "aggregating helper reports" and ends with "Per-harness facts stay with harness_portability". harness_portability's description claims "agent definitions, agent frontmatter, tool allowlists, read-only agent enforcement".
- **Prior art.** [The deferred description-recall task](archive/ai-dev_agent-spinner-description-recall.md) found that adding keyword surface does not raise agent_spinner's recall, and it was parked when no tested rewrite beat the description of its day. That finding constrains this task: a fix that only adds trigger phrases is the approach already known not to work. `tests/CLAUDE.md`'s trigger-eval section ("Acting on family-only passes") says a sibling stealing a query is usually fixed in the sibling's description.

## Approach

1. Re-run the set three times against the 2026-11-10 baseline, with the run-pattern command in `tests/CLAUDE.md`'s trigger-eval section, to confirm both regressions still hold before changing anything.
2. For the negative query, sharpen the boundary where the bleed is. Make agent_spinner's closing routing sentence name per-harness tool and agent-definition questions as harness_portability's, and adjust harness_portability's description only if the agent_spinner change does not hold the query. Measure harness_portability's own trigger behaviour with its set when its description changes; if it has none, note that in the record.
3. For the positive query, try one rewrite of the aggregation clause that says what the skill does with helper reports (merges cited findings by substance rather than by vote) instead of adding keywords, and measure it the same way.
4. When a query still fails three runs after a tried rewrite, give its eval-set entry in `tests/trigger_evals/agent_spinner.json` a `note` that records the disposition, as `tests/CLAUDE.md` describes for persistent, understood failures, and keep the shipped description.

## Acceptance

- `tests/agent_spinner/RUNBOOK.md`'s "Recorded measurements" table carries the confirming runs made at implementation time and the post-change runs, each with date, vendor, model, and per-category counts, with the per-query result for the two drifted queries in the prose beneath it.
- Each of the two queries either passes in at least two of three post-change runs against the 2026-11-10 baseline, with no other query regressing, or carries a `note` disposition in `tests/trigger_evals/agent_spinner.json`.
- A description change ships under the standing versioning rules, and `skill_doctor`'s `discovery_safety.py` reports the new description under the listing budget.
