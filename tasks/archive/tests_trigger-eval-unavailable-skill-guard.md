---
description: "Make the trigger-eval runner fail loudly when a skill is unavailable, and document how to read a zero-recall outcome in the `## tests/trigger_evals/` section of `tests/CLAUDE.md`."
scope: "local test harnesses"
created: 2026-08-30T16:57:07
updated: 2026-10-17T13:43:37
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Fail loudly on an unavailable skill in the trigger-eval runner and document zero-recall reading

## Goal

A trigger-eval run whose skill under test cannot be reached in deployed mode
exits with a distinct, named unavailability and writes no score, instead of
silently scoring a clean-looking zero through the UUID proxy. The deliberate
proxy path stays reachable behind `--force-uuid`. The `## tests/trigger_evals/`
section in `tests/CLAUDE.md` states how to read a zero-recall outcome, so a
reader separates a real description non-match from an availability failure. An
operator who runs the harness against a skill that is not deployed then sees a
loud failure they can act on, and a genuine zero in deployed mode reads as
evidence about the description.

## Context

This harness is Claude-only for a product reason: it grades Claude `Skill(...)` /
stream-json load evidence, and `tests/lib/vendor.py` rejects `--vendor cursor`
for `trigger_evals` until a Cursor equivalent exists. That is a Claude feature
surface, not leftover harness shape from before the vendor switch.

`tests/trigger_evals/run.py` resolves the skill under test from the deployed tree
(`~/.claude/skills/<name>/`) and falls back to skill-creator's UUID-proxy runner
when that lookup misses. Deployed mode measures triggering correctly. Recent
deployed runs scored `wiki` 19/20 (2026-05-25) and the `task` fixture 18/31
(2026-08-11). The UUID fallback is the path that once reported `precision=100%
recall=0% accuracy=50%`, a clean-looking zero that reads as "the description
matches nothing" when the real cause is that the skill was unavailable to the
worker.

The runner already carries `--force-uuid`, which forces the proxy path, and it
chooses deployed-versus-fallback where it sets `deployed_root`. The gap is the
branch that runs when the skill is not deployed: with a `--skill-path` present it
calls `run_uuid_fallback` and scores, and only the narrower "not deployed and no
skill path" case exits with an error. So an ordinary run against a not-yet-deployed
skill still produces a silent zero rather than a loud failure.

Deploy copies every skill into the deployed tree via `copy_path_with_replacements`,
so the fallback is rarely taken after a normal deploy. The guard matters for the
next skill authored but not yet deployed, whose run would otherwise repeat the
silent-zero misread that produced the now-deferred
[tests_trigger-eval-harness-repair.md](tests_trigger-eval-harness-repair.md).
This task carries the genuinely-open remainder of that deferred task, its
loud-failure and zero-recall-documentation acceptance, while that task's
reproduce-and-fix-the-resolution framing is moot, since deployed mode already
measures.

The `## tests/trigger_evals/` section in `tests/CLAUDE.md` describes the
deployed-versus-fallback mode selection but says nothing about how to read a
zero-recall result. The `## Trigger evals` section in
`tests/agent_spinner/RUNBOOK.md` still says that without a deployment the runner
falls back to the UUID proxy.

## Approach

Change the unavailable-skill branch in `run.py` so a run whose skill under test is
absent from the deployed tree, taken without `--force-uuid`, exits non-zero with a
distinct message naming the unavailability and writes no results score, folding
today's narrower no-skill-path error into that one named failure. Keep
`--force-uuid` as the deliberate opt-in that still reaches the UUID proxy, so
exercising the proxy on purpose stays possible. Rewrite in place the module
docstring opening that today says when the skill is not deployed the runner
"falls back to the skill-creator runner's UUID-proxy approach," so unavailable
without `--force-uuid` is the named loud failure and `--force-uuid` is the only
UUID-proxy entry.

Extend `tests/trigger_evals/script_tests/run.sh` with three hermetic assertions
that stage an isolated `HOME`, pass `--skill-path` to a temporary skill tree, and
pass `--results-dir` under that staging so host deploy state and host results are
never consulted. For mode-selection checks (2) and (3), drive `main` (or the
equivalent entry the script already invokes) under that staging with
`run_uuid_fallback` and `run_deployed_mode` stubbed so each stub records that it
was called and leaves no scored `results.json` (no accuracy, recall, precise, or
family score fields): (1) without `--force-uuid`, a skill absent from the staged
deployed tree exits non-zero, prints the named unavailability, and creates no
results directory; (2) with `--force-uuid`, the uuid stub returns a score-free
payload, the stubbed run records a `run_uuid_fallback` call, and leaves no scored
`results.json`; (3) with the skill present under the staged `HOME` deployed tree,
the deployed stub records the call then raises a sentinel so `main` exits through
its exception handler before writing `results.json`, proving `run_deployed_mode`
was selected without inventing precise or family score fields for the print path.
Preserve `run_uuid_fallback`'s existing scoring behaviour for deliberate
`--force-uuid` runs; the stubbed reachability assertion already proves that proxy
path is selected, and the hermetic suite stops at those three assertions. The
runner exits 0 when those assertions pass.

Rewrite in place the mode-selection bullets under `## tests/trigger_evals/` in
`tests/CLAUDE.md` so an unavailable skill exits with the named loud failure and
writes no score, `--force-uuid` remains the deliberate UUID-proxy opt-in, and the
section states how to read a zero-recall outcome in deployed mode as evidence
about the description rather than an availability failure. Rewrite the inventory
Pattern cell for `trigger_evals/` in the same file so it no longer describes auto
UUID fallback. Rewrite in place the fallback sentence under `## Trigger evals` in
`tests/agent_spinner/RUNBOOK.md` so an unavailable skill exits with the named
loud failure and writes no score, and `--force-uuid` remains the deliberate
UUID-proxy opt-in, superseding the prior "falls back to the UUID proxy" wording.
Leave the section's run command and deploy-time obligation as they stand; the
dual-vendor command and baseline rewrite stay with
[tests_trigger-evals-cursor-vendor.md](../tests_trigger-evals-cursor-vendor.md).

**Out of scope:**

- Rewriting any skill `description:` to move a routing result, owned by
  [wiki_activation-surface-and-descriptions.md](wiki_activation-surface-and-descriptions.md).
- Re-baselining recorded runs or deleting the stale 2026-05-17 run logs; that
  output is gitignored and a fresh run supersedes it.
- Adding trigger-eval cases for any skill and editing the task-family
  harness-inventory rows, owned by
  [task-family_test-harness-consolidation.md](task-family_test-harness-consolidation.md);
  cross-link that task for registering any new trigger harness row rather than
  editing the inventory here.

## Acceptance

- A run invoked against a skill that is not present in the deployed tree, without
  `--force-uuid`, exits non-zero and prints a distinct message naming the
  unavailability, and writes no `results.json` carrying an accuracy, recall, or
  precise/family score.
- The module docstring of `tests/trigger_evals/run.py` no longer states that an
  undeployed skill falls back to the UUID-proxy approach; it states the named
  loud failure for unavailable-without-`--force-uuid` and names `--force-uuid`
  as the only UUID-proxy entry.
- `tests/trigger_evals/script_tests/run.sh` asserts, under hermetic `HOME` /
  `--skill-path` / `--results-dir` staging with `run_uuid_fallback` and
  `run_deployed_mode` stubbed as Approach states, that `--force-uuid` records a
  `run_uuid_fallback` call and leaves no scored `results.json`.
- `tests/trigger_evals/script_tests/run.sh` asserts, under the same hermetic
  staging and stubs, that a skill present in the staged deployed tree records a
  `run_deployed_mode` call, exits via the deployed stub's sentinel before scoring,
  and leaves no scored `results.json`.
- `tests/trigger_evals/script_tests/run.sh` asserts that an unavailable-skill run
  without `--force-uuid` exits non-zero, prints the named unavailability, and
  creates no results directory under that hermetic staging; the runner exits 0
  when its assertions pass.
- The `## tests/trigger_evals/` section in `tests/CLAUDE.md` states deployed-mode
  selection, `--force-uuid` as the deliberate proxy path, and what a zero-recall
  outcome means in deployed mode, with the prior auto UUID-fallback mode-selection
  wording superseded; the inventory Pattern cell for `trigger_evals/` matches that
  contract and no longer says auto UUID fallback.
- The `## Trigger evals` section in `tests/agent_spinner/RUNBOOK.md` states that
  an unavailable skill fails loudly with the named unavailability and writes no
  score, with `--force-uuid` as the deliberate proxy path; the prior "falls back
  to the UUID proxy" wording is superseded (`rg -F 'falls back to the UUID proxy'
  tests/agent_spinner/RUNBOOK.md` finds no matches).
