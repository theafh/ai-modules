---
description: "State in task_audit that a missing design-extended on an implement-stamped task is a recording note, and only a signal that mismatches the built change is a gap blocking audited."
scope: plugins/ai_dev/skills/task_audit
created: 2026-11-15T06:30:39Z
updated: 2026-11-15T06:30:39Z
status: open
reported-by: "Andreas Hoffmann"
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
   check is confirmed" so it points at that rule: the check is confirmed when
   the recorded or absent signal matches the change, and a recording note
   leaves it confirmed.
3. In `<output_contract>`, rewrite the full-compliance bullet's "Supporting
   evidence may precede it" clause so it names a recording note from the
   verify step as part of that evidence, which leaves the verdict a full pass.
4. Make `audit_clean` the pin for the absent case in `tests/task/evals/`. Add
   a check to its arm in `grade.sh` that the task file still carries no
   `design-extended` line after the run, since the audit's only permitted task
   edit is its status stamp. Rewrite the fixture header in
   `fixtures/audit_clean/setup.sh`, the `audit_clean` row in `README.md`, and
   the eval's `expected_output` in `evals.json` to say that the seeded task
   carries no `design-extended` field and the audit still stamps `audited`,
   and add an expectation that the response names the missing field at most as
   a recording note, never as a `Gaps:` item. Keep the fixture task without
   the field.

**Out of scope:**

- An eval for the gap side of the rule, a `false` signal on a change that
  extended the design: owned by
  [tests_task-family-lifecycle-evals](tests_task-family-lifecycle-evals.md),
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
  row in `tests/task/evals/README.md` each name the absent-field case the eval
  pins.
- `python3 tests/task/evals/run.py audit_clean`, run on the default vendor
  with no `--vendor` flag, grades PASS, with status `audited` and the verdict
  line exactly `Success: full task compliance confirmed.` on its own line. A
  FAIL on the stamp check means the rewritten wording still reads the missing
  field as a gap: revise the wording and re-run, leaving the grader's stamp
  check as it is.
