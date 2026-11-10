---
description: Rewrite agent_spinner's description so the router reaches it, measured against the recorded 1-of-8 recall baseline while holding its clean 8-of-8 boundary.
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-09-16T12:58:00Z
updated: 2026-10-04T17:52:01Z
status: deferred
reported-by: Andreas Hoffmann
---

# Make agent_spinner's description reach the router

## Goal

A user asking how to run helper agents gets `agent_spinner` loaded. Today the
skill is deployed and correct but largely unreachable: a router reading its
`description:` picks it for one of the eight orchestration asks written to
exercise it. After this task the description leads with what the skill is for
in terms a router matches, and the recorded measurement says whether that
worked.

The boundary half already holds and stays held. No query belonging to a
sibling family may start loading `agent_spinner` as a side effect of the
rewrite.

## Context

**Deferred on 2026-10-04.** Trigger runs that day tested this task's hypothesis directly. They used `claude` 2.1.226, a `claude-sonnet-4-6` worker, and three runs per query, each in a scratch config directory holding a copy of the deployed skills. Two runs of the current description passed 4 and 3 of the eight `should_trigger: true` queries and all eight `should_trigger: false` queries, so the 1-of-8 baseline below no longer describes the router. A rewrite that led with the purpose passed 3 of 8, and one that anchored the triggers to the moment of spawning passed 2 of 8. The ordering hypothesis is therefore not supported, and no tested rewrite beat the current text. The queries that still miss load no skill at all, or the bundled code-review skill. The routing sentence this task owned moved to [the routing task](ai-dev_agent-spinner-routing.md), which measured its conditional form at 4 of 8 with every negative and both queries naming the skill held.

`plugins/ai_dev/skills/agent_spinner/SKILL.md` ships the description under
review. The skill body itself is out of scope here; only the frontmatter
`description:` value changes.

The measured baseline is recorded at
`tests/trigger_evals/results/agent_spinner/2026-09-16_145529/`, produced in
deployed mode with three runs per query against a sonnet-pinned worker. It
reports 9 of 16 precise, split unevenly: 1 of 8 on the `should_trigger: true`
queries and 8 of 8 on the `should_trigger: false` ones. Run output under
`tests/trigger_evals/results/` is gitignored, so treat that directory as
present on the machine that measured it and re-measure rather than assume it
when it is absent.

Two properties of the failures narrow the diagnosis and rule out the obvious
first guesses. Six of the seven failing queries returned no loaded skill at
all rather than a sibling winning the match, so the problem is that nothing
fires rather than that something else fires first. And the trigger keywords are
already present: the query "split this review into a few lenses and give each
sub-agent one angle" scored zero across three runs while the description
contains the phrase "splitting a review into lenses" verbatim. Adding more
keyword surface is therefore the one approach already known not to be the fix.

The standing repo rules own the dual-audience description contract, which asks
for a precise compact summary for a browsing user followed by keyword-rich
`Use when` trigger contexts. The current value satisfies that contract's
letter while running roughly 450 characters of internal mechanism, naming the
capability tier, the phase plan, the roster and the report shape, before the
`Use when` clause begins. Whether that ordering is what starves the match is
the hypothesis this task tests rather than a settled cause.

`tests/trigger_evals/run.py` is the measurement instrument, and it reads the
*deployed* copy under the harness skills directory rather than the repo
source, so a description edit needs a deploy before it can be measured. That
deploy is gated on the user by the standing repo rules.
[task-family_audit-select-description-repair](task-family_audit-select-description-repair.md)
is the archived precedent for repairing a description against a recorded
pre-edit baseline, and its measurement shape is the one to follow.

`TESTING.md`'s re-run economy rule governs what gets re-run here: the
description is the only input under test, so the behavioural eval suite under
`tests/agent_spinner/evals/` stays out of the loop entirely.

## Approach

Rewrite the `description:` value in
`plugins/ai_dev/skills/agent_spinner/SKILL.md`, replacing the current value
rather than extending it, and keep it inside the 1500-character budget the
skill's own test suite asserts. Lead with the question the skill answers, in
the words a user asking it would use, and move the internal mechanism behind
the trigger contexts so a router meets the match surface first. Treat the
mechanism summary as compressible: a browsing user needs to know what the
skill decides, not every block it decides with.

Deploy, then re-measure with the same protocol that produced the baseline, and
diff against it:

```bash
python3 tests/trigger_evals/run.py \
  --eval-set tests/trigger_evals/agent_spinner.json \
  --skill agent_spinner \
  --skill-path plugins/ai_dev/skills/agent_spinner \
  --model claude-sonnet-4-6 --runs-per-query 3 --timeout 45 --workers 10 \
  --baseline tests/trigger_evals/results/agent_spinner/2026-09-16_145529
```

Record the outcome and its disposition in
`tests/agent_spinner/RUNBOOK.md`, beside the deploy-time obligation already
written there, so the next author reads the measured history rather than
re-deriving it.

**Out of scope:**

- Editing the skill body, its `references/`, or any block inside them, since
  the router reads the frontmatter alone and a body change cannot move this
  measurement.
- Re-running `tests/agent_spinner/evals/`, whose fixtures exercise the skill
  once loaded and are unreachable from a frontmatter edit under `TESTING.md`'s
  re-run economy rule.
- The cross-set trigger sweep over the other eval sets, which
  `tests/agent_spinner/trigger_overlap.py` gates and which this task's edit
  re-opens only if it introduces vocabulary that overlaps another set.
- Adding trigger keywords as the repair, since the baseline already shows a
  verbatim-present phrase scoring zero.
- Widening `tests/trigger_evals/agent_spinner.json` to easier queries, which
  would move the number without moving the skill's reachability.

## Acceptance

- `plugins/ai_dev/skills/agent_spinner/SKILL.md` carries one `description:`
  value, differing from the baseline value recorded in the git history of the
  commit that shipped it, and `wc -c` on the extracted value returns under
  1500.
- The rewritten value names the skill's purpose before its first mechanism
  term, verifiable by the purpose clause preceding the first occurrence of
  "capability tier", "phase plan", "roster", or "dispatched".
- `bash tests/agent_spinner/script_tests/run.sh` passes, including its four
  description trigger-word assertions and its two routing-boundary assertions,
  so the rewrite keeps the contract those checks pin.
- A fresh trigger run over `tests/trigger_evals/agent_spinner.json` exists
  under `tests/trigger_evals/results/agent_spinner/`, produced with three runs
  per query in deployed mode against a sonnet-pinned worker, and its
  `results.json` carries a `baseline_comparison` against the
  `2026-09-16_145529` run.
- That run reports no query regressing on the `should_trigger: false` half:
  its eight negative queries stay at eight precise passes, so the boundary is
  held rather than traded away for recall.
- The `should_trigger: true` half's precise count is recorded in
  `tests/agent_spinner/RUNBOOK.md` against the baseline's 1 of 8, whichever
  direction it moved. When it improves, the entry states the new count and the
  change that produced it. When it fails to improve after one rewrite, the
  entry states that, names the ordering hypothesis as unsupported, and leaves
  the remaining options for a human to weigh rather than the task iterating
  further on its own.
