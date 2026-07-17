---
description: Drop the `created`-vs-birth-time drift check from task lint.py — birthtime is not durable under edits or clones, so the check false-flags legitimate changes. Move to trust-on-write.
scope: plugins/ai_dev/skills/task
created: 2026-05-29T00:28:10
updated: 2026-05-31T01:18:38
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Drop the birth-time drift check from task `lint.py`

## Goal

Remove the `created`-vs-filesystem-birth-time drift warning from the task
linter and move the `created` field to **trust-on-write**: it is stamped once
from `date` at creation and is never mechanically re-validated. The task tree
lints clean after any legitimate edit, and on a fresh clone, without emitting
drift warnings that aren't real drift.

## Context

The drift check (`check_birthtime` in
`plugins/ai_dev/skills/task/scripts/lint.py`) compares the `created`
frontmatter value against the file's filesystem birth time (`st_birthtime`).
Its premise — birthtime ≈ true creation time — does not hold:

- **Atomic-save editors reset birthtime.** Most editors, plus `sed -i ''`,
  formatters, etc., write a temp file and rename it into place — new inode,
  birthtime = now. So *any* legitimate edit to a task can manufacture a
  "drift" that isn't one.
- **git stores no birthtime.** A fresh `git clone` / checkout sets every
  file's birthtime to checkout time, so the check flags the entire tree on a
  clone. The skill already concedes this ("a fresh clone/checkout… resets
  birth time"), which is really an admission the signal is mostly noise — and
  accepted noise trains warn-blindness, defeating the check's purpose.
- **Only `git mv` preserves birthtime** (same inode) — the one case the
  current design leaned on.

Demonstrated live during a `task_health` run on 2026-05-29: editing task files
to fix unrelated warnings reset their birthtime and re-introduced drift
warnings, and hand-restoring birthtime with `touch` only papered over the
symptom — the next legitimate edit re-breaks it.

**Decision (user, 2026-05-29): trust-on-write — drop the check.** The
alternative considered and rejected was re-basing the oracle on git's
first-commit date (`git log --diff-filter=A --follow --format=%aI`), which is
durable but adds git-dependence and complexity the field doesn't warrant.

This is the successor to
[task-family_trustworthy-timestamps](task-family_trustworthy-timestamps.md)
(implemented), which introduced the check. Scope here is the **task** linter
only — the `wiki` skill's separate birthtime logic in
`plugins/knowledge_management/skills/wiki/scripts/lint.py` is out of scope.

## Approach

1. **`plugins/ai_dev/skills/task/scripts/lint.py`** — remove `check_birthtime`,
   `birth_epoch`, the `BIRTHTIME_TOLERANCE_SECONDS` constant and its comment,
   the call site (`issues.extend(check_birthtime(...))`), and the module
   docstring line that mentions birth-time agreement. Drop any imports left
   dead by the removal (e.g. an unused `datetime`/`os.stat` path — verify
   before deleting).
2. **`plugins/ai_dev/skills/task/SKILL.md`** — in `<lint>`, remove the
   drift clause from the **warn** bucket description. In `<frontmatter>`,
   keep the "stamp from `date`" guidance (still how `created` is set) but
   drop any wording implying the value is checked against birthtime.
3. **`plugins/ai_dev/skills/task_fix/SKILL.md`** — rework the **verify**
   phase and `<surface_for_review>`: the current triage is framed around
   "leaving birth-time drift … surfaced-and-accepted." With the check gone,
   the clean bar becomes simply 0 blocking + mechanical warns resolved +
   remaining judgement-call warns reported; drop birth-time drift from the
   judgement-call examples. Keep the topic-mixing / single-shot-readiness
   advisory checks.
4. **Sweep the rest of the family.** Grep the shipped tree for residual
   references and update prose to match:
   `grep -rln "birth.time\|birthtime\|drift" plugins/ai_dev/`. Known hits:
   `task_audit/SKILL.md`, `plugins/ai_dev/README.md`. Leave **archived**
   tasks (`tasks/archive/`) untouched — they are historical record.
5. **Tests (gitignored, not committed).** Update
   `tests/tasks/script_tests/run.sh` and its fixtures — remove the drift
   cases (`test_drift`, `test_near`, `test_sameday`, `test_match`,
   `test_nobirth`) and any assertions on drift output, so the script suite
   stays green against the new behaviour. Land this in the same change per
   the "tight scenario with the skill change" rule.
6. **Versioning.** Bump the `task` skill `version` 1.1.2 → 1.1.3 and the
   `ai_dev` plugin meta (`.claude-plugin/plugin.json`,
   `.codex-plugin/plugin.json`, `.claude-plugin/marketplace.json`) 1.2.6 →
   1.2.7 lockstep.

## Acceptance

- `lint.py` no longer emits any birth-time / drift warning; editing a task
  file (which resets birthtime) and re-linting produces no new warning from
  the change alone.
- No dead code or unused imports remain in `lint.py` after the removal.
- The base `task` `<lint>` prose, `task_fix`'s verify/surface sections,
  and any other live `task_*` references no longer describe a drift check;
  archived tasks are left as-is.
- `tests/tasks/script_tests/run.sh` passes with the drift cases removed.
- `make lint` and `./deployment/deployment.sh --global --dry-run` pass.
- `task` skill at 1.1.3, `ai_dev` plugin meta at 1.2.7 in all three metas.

## Related

- Ancestor (introduced the check):
  [task-family_trustworthy-timestamps](task-family_trustworthy-timestamps.md).
- Out of scope: the `wiki` skill's own birthtime logic.
