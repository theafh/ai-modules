---
description: Make the trigger-eval runner fail loudly on an unavailable skill instead of silently scoring a zero, and document how to read a zero-recall outcome in the tests-tree README.
scope: "local test harnesses"
created: 2026-08-30T16:57:07
updated: 2026-08-30T16:57:07
status: open
reported-by: Andreas Hoffmann
---

# Fail loudly on an unavailable skill in the trigger-eval runner

## Goal

A trigger-eval run whose skill under test cannot be reached in deployed mode
exits with a distinct, named unavailability and writes no score, instead of
silently scoring a clean-looking zero through the UUID proxy. The deliberate
proxy path stays reachable behind `--force-uuid`. The tests-tree README states
how to read a zero-recall outcome, so a reader separates a real description
non-match from an availability failure. An operator who runs the harness against
a skill that is not deployed then sees a loud failure they can act on, and a
genuine zero in deployed mode reads as evidence about the description.

## Context

`tests/trigger_evals/run.py` resolves the skill under test from the deployed tree
(`~/.claude/skills/<name>/`) and falls back to skill-creator's UUID-proxy runner
when that lookup misses. Deployed mode measures triggering correctly — recent
deployed runs scored `wiki` 19/20 (2026-05-25) and the `task` fixture 18/31
(2026-08-11). The UUID fallback is the path that once reported `precision=100%
recall=0% accuracy=50%` — a clean-looking zero that reads as "the description
matches nothing" when the real cause is that the skill was unavailable to the
worker.

The runner already carries `--force-uuid`, which forces the proxy path, and it
chooses deployed-versus-fallback where it sets `deployed_root`. The gap is the
branch that runs when the skill is not deployed: with a `--skill-path` present it
calls `run_uuid_fallback` and scores, and only the narrower "not deployed and no
skill path" case exits with an error. So an ordinary run against a not-yet-deployed
skill still produces a silent zero rather than a loud failure.

Direct-deploy now symlinks every skill into the deployed tree, so the fallback is
rarely taken today. The guard matters for the next skill authored but not yet
deployed, whose run would otherwise repeat the silent-zero misread that produced
the now-deferred [archive/tests_trigger-eval-harness-repair.md](archive/tests_trigger-eval-harness-repair.md).
This task carries the genuinely-open remainder of that deferred task — its
loud-failure and zero-recall-documentation acceptance — while that task's
reproduce-and-fix-the-resolution framing is moot, since deployed mode already
measures.

The tests-tree README documents the trigger harness under its own
`## tests/trigger_evals/` section in `tests/CLAUDE.md`, which describes the
deployed-versus-fallback mode selection but says nothing about how to read a
zero-recall result.

## Approach

Change the unavailable-skill branch in `run.py` so a run whose skill under test is
absent from the deployed tree, taken without `--force-uuid`, exits non-zero with a
distinct message naming the unavailability and writes no results score — folding
today's narrower no-skill-path error into that one named failure. Keep
`--force-uuid` as the deliberate opt-in that still reaches the UUID proxy, so
exercising the proxy on purpose stays possible.

Add a bundled assertion that proves the loud failure: a run invoked against a
skill that is not deployed, without `--force-uuid`, exits non-zero, prints the
named unavailability, and leaves no scored `results.json`. Place it in the trigger
harness's script-test surface under Pattern A (`tests/trigger_evals/script_tests/run.sh`),
creating that runner when none exists.

State in the trigger harness's own README section (`## tests/trigger_evals/` in
`tests/CLAUDE.md`) how to read a zero-recall outcome: in deployed mode a zero is a
real description non-match and evidence about the description, distinguished from
an availability failure, which now exits loudly rather than scoring zero.

**Out of scope:**

- Rewriting any skill `description:` to move a routing result, owned by
  [wiki_activation-surface-and-descriptions.md](wiki_activation-surface-and-descriptions.md).
- Re-baselining recorded runs or deleting the stale 2026-05-17 run logs; that
  output is gitignored and a fresh run supersedes it.
- Adding trigger-eval cases for any skill and editing the task-family
  harness-inventory rows, owned by
  [task-family_test-harness-consolidation.md](archive/task-family_test-harness-consolidation.md);
  cross-link that task for registering any new trigger harness row rather than
  editing the inventory here.

## Acceptance

- A run invoked against a skill that is not present in the deployed tree, without
  `--force-uuid`, exits non-zero and prints a distinct message naming the
  unavailability, and writes no `results.json` carrying an accuracy, recall, or
  precise/family score.
- A run invoked with `--force-uuid` still reaches the UUID-proxy path, so the
  deliberate proxy run stays available.
- A deployed-mode run against an available skill still scores as it does today, so
  the guard changes only the unavailable case.
- `tests/trigger_evals/script_tests/run.sh` holds an assertion that the
  unavailable-skill run exits non-zero, prints the named unavailability, and
  leaves no scored `results.json`; the runner exits 0 when its assertions pass.
- The `## tests/trigger_evals/` section in `tests/CLAUDE.md` states what a
  zero-recall outcome means in deployed mode and which failure it is distinguished
  from, added alongside its current mode-selection description.
