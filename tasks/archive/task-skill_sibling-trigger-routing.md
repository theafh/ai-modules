---
description: Improve task* family trigger routing — baseline precise 14/25; description-sharpening was tried and regressed, so the working levers are naming and right-sizing the eval, not more description text.
scope: plugins/ai_dev
created: 2026-05-29T23:41:45
updated: 2026-05-31T00:43:06
status: implemented
---

# Improve task* family trigger routing

## Goal

`tests/trigger_evals/task.json` measures which `task*` skill a realistic
phrasing routes to. The baseline is **precise 14/25, family 20/25** — the
family is recognised well, but the wrong member often wins. Improve the
routing on the misses that are *actually* fixable, using the levers a
first attempt proved effective (naming) rather than the one it proved
regressive (description-sharpening), and honestly document or scope out
the misses that are trigger-eval instrument artefacts. Success is a
no-regression rise on the addressable cases — not a perfect 25/25.

The naming lever has **already landed and deployed**: `task_health` was
renamed to `task_fix` in both the source and the deployed skill tree, and
`task.json` already expects `task_fix`. The trigger-eval runner reads the
deployed descriptions, so this precondition is satisfied — the immediate
work is to **re-measure and interpret**, not to land any rename.

## Context

Baseline run: `tests/trigger_evals/results/task/2026-05-29_233532/` (model
`claude-sonnet-4-6`, 3 runs/query). The misses sort into three buckets.

**Bucket A — base `task` swallows sibling action verbs** (family-pass,
precise-fail; base `task` fired where a sibling should):

- `build the thing described in this task now` → expected `task_implement`
- `is this task actually done? verify it against the code` → expected `task_audit`
- `mark this task done and archive it` → expected `task_finish`

**Bucket B — sibling-on-sibling bleed** (the fired-skill names below are
baseline-era: the run predates the rename, so `task_health` there is
today's `task_fix`):

- `audit the entire tasks tree and fix whatever is mechanical` →
  `task_audit` (expected `task_fix`, recorded as `task_health` at baseline).
- `what's left to do in this project?` → `task_fix` (recorded as
  `task_health`; expected base `task`).

**Bucket C — no skill fired / acted inline**: `implement … <path>`,
`re-check this archived task …`, `break this doc into several tasks`,
`go do task … end to end`, `defer this task …`, `update the description on
the … task`. An action verb plus a concrete file path makes the model
read the file or just act, which the runner records as no-trigger.

### Settled finding — description-sharpening alone does not work

A first attempt (2026-05-29) edited the base `task`, `task_audit`, and
`task_health` `description:` fields to cede verbs and bind siblings
tighter, bumped versions, and re-ran against the live (symlinked)
descriptions. It **regressed**: precise 14/25 → 12/25, family 20/25 →
14/25 (run `…/2026-05-29_234838/`). It was reverted. Three lessons:

- **Action verbs route to action, not a skill.** Hedging base `task` with
  "for a single task the siblings own the verb" made the model fire *no*
  task skill for "implement / do / mark / defer / verify" phrasings — it
  just acts inline. Wording cannot force a skill load when the model's
  first move is to do the work. (This is also why Bucket C resists fixes.)
- **Skill-name tokens dominate description wording.** "audit the entire
  tasks tree" stayed on `task_audit` regardless of any ceding clause — the
  `audit` token in the *name* outweighs the prose. The lever is the name,
  not the description.
- **Hedged descriptions cost precise wins.** Two clean baseline passers
  regressed once descriptions grew conditional. Sharper is not freer.

## Approach

Work *with* those limits. Do **not** reintroduce description-sharpening as
the fix — it is a rejected approach.

1. **Measure the landed naming lever.** The
   [rename of `task_health` → `task_fix`](task-skill_rename-health-to-fix.md)
   gave the repair intent a `fix` name token, and it has already deployed
   (source and `~/.claude/skills` both carry `task_fix`; `task.json` already
   expects it). Per the name-dominance finding this is the right tool for
   Bucket B's "audit the entire tasks tree and **fix** whatever is
   mechanical" — that query now has a `fix` token to grab. Re-run
   `task.json` against the current deployed descriptions and record whether
   the `fix` token moved that query onto `task_fix`. No rename is pending
   here; this step is measurement.
2. **Triage what remains with a mechanical test, don't churn descriptions.**
   For Bucket A and the Bucket C inline-action cases, classify each miss
   into one of three dispositions by a concrete rule rather than taste,
   across the 3 runs:
   - **instrument-limited** — the model loaded **no** family skill and
     instead read or acted on the named file path. The runner cannot
     observe a skill load when the model's first move is to do the work
     (the Bucket C inline-action cases). Document and scope out.
   - **addressable real bleed** — a family skill loaded but the wrong
     member won, **and** the cause is a name token a structural lever could
     fix (another rename, a sharper sibling name). Pursue that lever.
   - **known accepted limitation** — a family skill loaded but the wrong
     member won, and **no** non-regressive lever exists: description-
     sharpening is the rejected approach, and no name token distinguishes
     the cases (Bucket A — base `task` firing for a bare action verb like
     "build / do / mark", which is acceptable real-world behaviour). Document
     as accepted; do not chase.

   Record the classifying disposition and reason inline next to each
   re-annotated `task.json` entry (e.g. "instrument-limited: no skill
   loadable" / "accepted: base task fires for bare action verb, no lever").
   Only the addressable-real-bleed bucket gets a structural lever.
3. **Right-size the eval without gaming the metric.** Update `task.json`
   (and the precise/family reading in `tests/CLAUDE.md` if needed) so the
   bar reflects what routing can actually achieve, separating "genuinely
   mis-routed" from "model acted inline". Guard against inflating the
   headline by re-labelling: the precise-rate floor in Acceptance is
   computed on the **un-re-annotated** 25-entry denominator, so marking a
   case instrument-limited documents it but never raises the measured rate.
   Keep every entry that *is* diagnostic of real bleed.
4. **Re-measure and record.** Re-running needs the current descriptions
   live, so confirm the deployed tree is in sync first — it already is for
   the rename; a fresh `make deploy` is required only if this task makes a
   *new* description edit, and per repo policy that deploy is run only on
   the operator's go-ahead. Re-run the set with the baseline protocol
   (`--runs-per-query 3`, 50% per-query threshold), take the verdict from
   the written `results.json` summary compared against the
   `2026-05-29_233532` baseline — not a single invocation. Record the
   comparison as a short Findings note in this task body, citing the new
   `results/task/<timestamp>/` run directory (its `results.json` / `run.log`
   are the raw machine record). Any skill/plugin edit follows the
   one-bump-per-commit + `ai_dev` plugin-lockstep rules.

## Acceptance

- All rates below are read from the written `results.json` summary of a
  re-run with the baseline protocol (`--runs-per-query 3`, 50% per-query
  threshold), compared against the `2026-05-29_233532` baseline — never
  from a single invocation — and the comparison is recorded as a Findings
  note in this task body, citing the new `results/task/<timestamp>/` run
  directory.
- The `task_fix` rename is already deployed; the re-run **records whether**
  the `fix` token resolved the single Bucket B name-lever query ("audit the
  entire tasks tree and fix whatever is mechanical"). A move onto `task_fix`
  is the predicted result, but a null result is an acceptable outcome too —
  document it and route that query through the Bucket A/C triage rule. The
  recorded measurement is the deliverable, not its direction.
- No description-only sharpening is reintroduced; the reverted approach
  stays rejected and the descriptions keep firing (no new `-/-/-`).
- The overall precise rate is **at least the 14/25 baseline** (no
  regression). The only case expected to move from the rename alone is the
  one Bucket B name-lever query above; no other case is expected to shift
  without a further justified lever. The floor is computed on the
  **un-re-annotated 25-entry denominator**, so marking misses
  instrument-limited cannot lift the measured rate.
- Every residual miss (Bucket A and the inline-action Bucket C cases)
  carries one of the three dispositions — instrument-limited, addressable
  real bleed (fixed by a justified structural lever), or known accepted
  limitation — recorded inline in `task.json` next to the entry with its
  reason. None is chased with regressive description edits.
- Any skill or plugin edit made here bumps `version:` and the `ai_dev`
  plugin metadata lockstep; `make lint` and the deploy dry-run pass, and
  the re-measure deploy is run only on the operator's go-ahead.

## Findings

Re-run `tests/trigger_evals/results/task/2026-05-31_003514/` (model
`claude-sonnet-4-6`, 3 runs/query, same protocol as the baseline). Raw
record: that dir's `results.json` / `run.log`.

- **Result: precise 15/25, family 20/25** — vs. baseline 14/25 precise,
  20/25 family. A +1 precise gain, no regression, family unchanged.
- **The naming lever worked exactly as predicted.** The entire +1 is the
  Bucket B query "audit the entire tasks tree and fix whatever is
  mechanical": baseline routed it to `task_audit`; this run routed it
  `task_audit / task_fix / task_fix` → precise pass (2/3). The deployed
  `fix` name token grabbed it, confirming the name-dominance finding. No
  other query moved from the rename alone, as expected.
- **The 10 residual precise-fails carry dispositions in `task.json`** (each
  as a `note` field — see the deviation below). None is addressable real
  bleed; no further non-regressive lever exists:
  - **5 known-accepted** — base `task` swallows a bare action verb
    (`build`, `go do … end to end`, `verify`, `mark … archive`, `defer`).
    Family-passes; acceptable real-world behaviour; description-sharpening
    is the rejected lever and no name token distinguishes these.
  - **5 instrument-limited** — the model acts inline / reads the named file
    rather than loading a skill (`…ready…` + path, `implement … <path>`,
    `re-check this archived task`, `what's left to do`, `break this doc`).
    The runner cannot observe a skill load when the model's first move is
    to do the work.
- **Deviation from the brief:** the task said to record dispositions
  "inline next to each `task.json` entry". `task.json` is strict JSON
  (`json.load`), so a comment would break the parse; instead each
  disposition is a JSON-legal `note` field on the entry. Verified
  `run.py`'s `normalize_eval_entry` reads only `query` / `expected_skill`
  and ignores the `note`, so the runner is unaffected.
- **No description, skill, or plugin edits were made** — the lever had
  already landed, so there was no version bump, no plugin-lockstep change,
  and no `make deploy`. The descriptions kept firing; no new `-/-/-`
  resulted from any edit of mine.

## Related

- Landed name-token lever (archived):
  [task-skill_rename-health-to-fix](task-skill_rename-health-to-fix.md).
- Where `task.json` and the behavioral evals were authored:
  [task-skill_testing-new-features](task-skill_testing-new-features.md).
