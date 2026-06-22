---
description: After the changelog skill fixes ship, delete CHANGELOG.md and cold-regenerate it from git history with the fixed skill, then verify a re-run is a no-op.
scope: "CHANGELOG.md regeneration"
created: 2026-06-02T19:37:57
updated: 2026-06-22T23:40:52
status: open
reported-by: Andreas Hoffmann
---

# Delete and cold-regenerate CHANGELOG.md with the fixed skill

## Goal

Bring the existing `CHANGELOG.md` into the new immutable-entries format the cheap
way: delete it and let the fixed `update_changelog` skill regenerate the whole
history from git in a cold build (no `CHANGELOG.md` present → the skill enumerates
the full commit history oldest-first and writes every day in the new format). A
cold regenerate reaches the same end state as a hand-repair would, drops the old
`[active]`/`[changed later]`/`[superseded]` markers and the retroactive
back-annotations automatically (each day is rebuilt from its own commits, so a
later rename shows up as its own entry on its own day), and doubles as the
end-to-end proof that the changelog skill fixes work together.

## Context

- Target: `CHANGELOG.md` at the repo root. It currently carries old-format
  artefacts — status markers and at least one retroactive annotation
  (the `2026-05-29` entry notes the `task_health` → `task_fix` rename that
  actually happened `2026-05-31`). Regenerating discards all of that.
- `CHANGELOG.md` is git-history-derived by design (per the repo rules), so nothing in it
  needs preserving beyond what the skill re-derives from commits — which is why
  deleting and regenerating is safe rather than lossy.
- Do this **only after all the changelog skill-fix tasks have shipped**, the
  format keystone being
  [changelog_immutable-entries-redesign.md](archive/changelog_immutable-entries-redesign.md):
  a cold build against the unfixed skill would just reproduce the old marker
  format.

## Approach

1. Confirm the changelog skill-fix tasks are shipped, so the skill produces the
   new format.
2. Delete `CHANGELOG.md` (`git rm CHANGELOG.md`).
3. Run `update_changelog` with no `CHANGELOG.md` present; its cold-build path
   regenerates every day section from git history in the new format.
4. Committing the regenerated file is fine, per the repo rules' changelog rule
   (skill output, not a hand-edit).

## Acceptance

- `CHANGELOG.md` is regenerated from git history in the new format: no
  `[active]`/`[changed later]`/`[superseded]` markers, no marker-legend line,
  supersession carried as forward entries, newest-first.
- No past day section's text references a later change (each day is rebuilt from
  its own commits).
- A spot re-run of `update_changelog` makes **no** changes — confirming the file
  is in the skill's steady state and the fix suite works end-to-end.
