---
description: "State in task_audit that a missing design-extended on an implement-stamped task is a recording note, and only a signal that mismatches the built change is a gap blocking audited."
scope: plugins/ai_dev/skills/task_audit
created: 2026-11-15T06:30:39Z
updated: 2026-11-24T07:01:30Z
status: finished
reported-by: "Andreas Hoffmann"
implemented-by: "Andreas Hoffmann"
design-extended: false
---

# State the severity of a missing design-extended signal in task_audit

## Goal

`task_audit` gives one reading of a missing `design-extended` field on an
implement-stamped task. The absent field reads as `false`, the report names it
as a recording note, and the `audited` stamp stays available whenever that
`false` reading matches the built change. Only a mismatch is a gap that
withholds the stamp: a `false` or absent signal on a change that extended the
design, or a `true` with no extension. Audits of the same task then reach the
same stamp on every vendor.

## Context

- `plugins/ai_dev/skills/task_audit/SKILL.md` **Verify each item against the
  code.** says today: "Treat a missing field on a task implement stamped as a
  recording gap worth naming, while an absent field on a task predating the
  field is legitimate and draws no finding." **Stamp the verdict.** stamps
  `audited` only when "the `design-extended` signal check is confirmed", and
  `<output_contract>` leads every result short of full compliance with
  `Gaps:`. Because "gap" is also the word that withholds the stamp, the skill
  leaves open whether this recording gap blocks `audited`, and it gives no test
  for recognising a task that predates the field.
- The `audit_clean` eval in `tests/task/evals/` shows the split. Its fixture
  task is `implemented` with complete code and tests and no `design-extended`
  field. A Claude run confirmed every Acceptance item, then withheld `audited`
  and listed the missing field under `Gaps:`; a Cursor run read the same
  sentence as a recording gap only and stamped.
- The hub settles the direction. The base `task` skill's `<frontmatter>` entry
  for `design-extended` says the field is "**optional, and absence reads as
  `false`**", and `<lifecycle_responsibility>` says `task_audit` "verifies the
  `design-extended` signal, recorded or absent, against the built change".
  Absence is therefore a value the audit verifies against the change, and only
  a verified mismatch fails the check.

## Approach

1. In **Verify each item against the code.**, rewrite the sentence that begins
   "Treat a missing field on a task implement stamped" so it states the
   severity rule once. An absent field reads as `false` and is checked like a
   recorded `false`; when that reading matches the change, the report names
   the missing field as a recording note among the supporting evidence that
   precedes the verdict line, outside any `Gaps:` list. A gap is only a
   mismatch: a `false` or absent signal on a change that extended the design,
   or a `true` with no extension. The rewrite drops the "predating the field"
   distinction, since the rule no longer depends on a task's age and the audit
   has no reliable test for it.
2. In **Stamp the verdict.**, rewrite the clause "the `design-extended` signal
   check is confirmed" so it points at the verify step's rule instead of
   restating it: the check is confirmed when that rule holds, and a recording
   note leaves it confirmed.
3. In `<output_contract>`, rewrite the full-compliance bullet's "Supporting
   evidence may precede it" clause so it names a recording note from the
   verify step as part of that evidence, which leaves the verdict a full pass.
4. Make `audit_clean` the pin for the absent case in `tests/task/evals/`. Add
   a check to its arm in `grade.sh` that the task file still carries no
   `design-extended` line after the run, since the audit's only permitted task
   edits are its status stamp and the `updated` bump. Add two response checks
   to the same arm: one that a line of the response is exactly `Success: full
   task compliance confirmed.`, and one that no line of the response opens a
   `Gaps:` list, so a response that lists the missing field as a gap fails the
   eval. Rewrite the fixture header in `fixtures/audit_clean/setup.sh` and the
   eval's `expected_output` in `evals.json` to say that the seeded task
   carries no `design-extended` field and the audit still stamps `audited`.
   The `evals.json` `expectations` stay documentation no grader reads, so the
   Gaps-versus-note behaviour is pinned by the `grade.sh` checks rather than
   by a new expectation there. Update every `audit_clean` site in `tests/task/evals/README.md`, found at
   implementation time by `rg -n "audit_clean" tests/task/evals/README.md`: the
   eval-set row gains that same absent-field wording, and the recorded-results
   sentence and the verdict-of-record row naming this task are rewritten in
   place. Rewrite the recorded-results sentence as a whole sentence rather than
   by substituting a fragment of it: it reads "On current inputs every eval but
   two passes on both vendors: `implement_boundary_cross` fails on Cursor and
   has an open task named below, and `audit_clean`'s Claude result is unrecorded
   — its wording is fixed, but its Claude re-run is still owed and is the
   operator's to schedule." The "each of those has an open task" clause goes
   with the old sentence. The verdict cell of the verdict-of-record row reads
   "wording fixed; Claude re-run owed (operator to schedule)", dropping its
   `fails;` label and its link naming this task, so no site still reports the
   old failure or names this task as its open owner. Keep the fixture task
   without the field.

5. Record the proof boundary the vendor rule sets. The wording change is
   vendor-neutral, and `TESTING.md` forbids an unsolicited `--vendor claude`
   run, so this task proves the reading on the default vendor only and claims
   no Claude pass. The Claude failure recorded for `audit_clean` in
   `tests/task/evals/README.md` is retired as step 4 describes, with the
   re-run named as the operator's to schedule.

**Out of scope:**

- An eval for the gap side of the rule, a `false` signal on a change that
  extended the design: owned by
  [tests_task-family-lifecycle-evals](../tests_task-family-lifecycle-evals.md),
  whose planned `audit_design_signal_mismatch` eval pins it.
- How `task_implement` records the field; this task governs only how
  `task_audit` grades it.

## Acceptance

- `rg -n "predating the field|recording gap" plugins/ai_dev/skills/task_audit/SKILL.md`
  returns no match, so the superseded sentence is gone.
- **Verify each item against the code.** in
  `plugins/ai_dev/skills/task_audit/SKILL.md` states the severity rule: an
  absent field reads as `false` and draws a recording note outside any
  `Gaps:` list, and a gap is a `false` or absent signal on a change that
  extended the design or a `true` with no extension.
- `rg -n "recording note" plugins/ai_dev/skills/task_audit/SKILL.md` finds
  the verify step, the **Stamp the verdict.** step, and the `<output_contract>`
  full-compliance bullet, and the last two point at the verify step's rule
  rather than restating it.
- The `audit_clean` arm of `tests/task/evals/grade.sh` fails a staged copy of
  the fixture whose task carries a `design-extended` line.
- The `audit_clean` entry in `tests/task/evals/evals.json`, the fixture header
  in `tests/task/evals/fixtures/audit_clean/setup.sh`, and the `audit_clean`
  eval-set row in `tests/task/evals/README.md` each name the absent-field case
  the eval pins. `rg -n "audit_clean" tests/task/evals/README.md` shows no site
  still reporting a Claude failure or naming this task as the fix's open
  owner: the recorded-results sentence and the verdict-of-record row read
  "wording fixed; Claude re-run owed", naming the re-run as the operator's to
  schedule. The recorded-results sentence is the settled whole-sentence
  rewrite rather than a fragment substitution, so
  `rg -n "each of those has an open task" tests/task/evals/README.md` returns
  no match.
  `rg -n "every eval passes on both vendors except" tests/task/evals/README.md`
  returns no match, so no sentence claims a both-vendors pass and then names
  only `implement_boundary_cross` as its exception, leaving `audit_clean`
  inside that claim.
  `rg -n "Claude result is unrecorded" tests/task/evals/README.md` finds the
  recorded-results sentence, which names `audit_clean`'s Claude result as
  unrecorded pending the operator's re-run.
- `python3 tests/task/evals/run.py audit_clean`, run on the default vendor
  with no `--vendor` flag, grades PASS, with status `audited`. The
  `audit_clean` arm of `tests/task/evals/grade.sh` checks the response for a
  line that is exactly `Success: full task compliance confirmed.` and for no
  line that opens a `Gaps:` list, so a response that lists the missing field
  under `Gaps:` fails the eval. A FAIL on either response check means the
  rewritten wording still reads the missing field as a gap: revise the wording
  and re-run, leaving the grader's checks as they are.
