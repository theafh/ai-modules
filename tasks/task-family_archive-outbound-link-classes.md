---
description: Rewrite the task skill's archive close-out to re-point all three outbound link classes in the moved file and verify the move with an archive-inclusive lint of that file.
scope: plugins/ai_dev/skills/task
created: 2026-07-02T19:03:00
updated: 2026-07-02T19:03:00
status: open
reported-by: Andreas Hoffmann
---

# Archive close-out re-points all outbound link classes and verifies the moved file

## Goal

Closing a task — `finished` or `deferred` alike — leaves every relative link inside the moved file resolving from its new home under `tasks/archive/`, and the close-out itself verifies that outcome mechanically instead of trusting the agent's judgment. Two passages in the base `task` skill's `<archive>` workflow are rewritten in place: the cross-reference instruction generalizes from its live-sibling-only wording to all three outbound link classes, and the closing lint instruction gains an archive-inclusive check of the just-moved file. User-visible outcome: an archived task never carries a link its own close-out silently broke, and a miss surfaces at close time rather than lying dormant until the next `task_fix --include-archive` run.

## Context

The `<archive>` workflow's cross-reference item (lead-in **"Update cross-references."** in the base `task` skill's `SKILL.md`) instructs outbound re-pointing only for a link that "still names a sibling" at the tasks root, then prescribes the inbound scan. Two further outbound classes break on the same move and are not named: a link into the archive (`archive/foo.md`, which from the new location resolves to `archive/archive/foo.md`) and a link out of the tasks tree, whose `../` depth is now one level short (`../plugins/…` must become `../../plugins/…`).

The verification backstop cannot catch the miss: the workflow's closing lint item ("Run `python3 scripts/lint.py --quiet` and resolve every blocking finding before declaring the archive complete") runs the linter's default mode, whose per-file checks cover live files only — the just-archived file is exactly what it no longer inspects. Only `--include-archive` sees it, and the `<lint>` section currently assigns that flag to `task_fix` alone ("task_fix is the archive owner").

The into-archive class is manufactured by the system itself: when task B archives, B's close-out inbound scan correctly rewrites live task A's link from `B.md` to `archive/B.md`; when A later archives, that link is the one the outbound instruction does not cover. Motivating incident (2026-07-02): deferring a task carrying exactly one such link followed the close-out choreography — status, `updated`, deferral note, `git mv`, inbound re-points in a sibling — yet left that link broken, and the default-mode lint reported clean. A git-history scan of every committed archive move found no earlier occurrence of the class at move time, while the live tree at the time of writing holds 16 into-archive links across 7 tasks — each a future occurrence of the same precondition. The out-of-tree depth class has occurred and was handled by agents generalizing beyond the written rule, which is judgment variance, not a guarantee.

The inbound half of archive-time link repair shipped in [archive-aware inbound link scan](archive/task-family_archive-inbound-link-scan.md); this task completes the outbound half. `task_finish` needs no edit: its workflow already says "outbound links inside the moved file" broadly and defers to the base `<archive>` rules through its `<authority>` section, so fixing the base fixes the family.

## Approach

All edits land in the base `task` skill's `SKILL.md`; sibling skills inherit them.

- **Rewrite the outbound sentence of the "Update cross-references." item in place** to the general rule: re-point every relative link inside the moved file so it resolves from the file's new location under `archive/`, naming the three classes — a live sibling (`foo.md` becomes `../foo.md`), an already-archived sibling (`archive/foo.md` becomes `foo.md`), and a target outside the tasks tree (one `../` deeper, e.g. `../plugins/…` becomes `../../plugins/…`). The existing inbound-scan sentences stay as they are.
- **Extend the closing lint item in place**: after the move, run the linter with `--include-archive` and resolve every finding for the moved file; findings in other archived files are reported as pre-existing context for `task_fix` rather than treated as blockers of this close-out.
- **Rewrite the `<lint>` section's ownership sentence** ("task_fix is the archive owner") so one canonical statement covers both uses of `--include-archive`: task_fix's whole-archive maintenance and the archive close-out's verification of the one just-moved file.
- **Correct the `<archive>` intro's stale step count** ("run all five steps") to match the item count while editing the same block.
- **Prove the rule on a staged fixture**: in a scratch tasks tree, author a task carrying one link of each outbound class plus one inbound link from a sibling, archive it by following the rewritten workflow, and confirm every link resolves on disk with the moved file clean under `--include-archive`.

Non-goals: no `task_finish` edit; no `lint.py` code change (default mode's live-only scope is by design — the workflow, not the linter, gains the archive-inclusive call); the into-archive links currently in live tasks are correct while live and stay untouched; regression-harness expansion beyond the staged fixture stays out per the standing repo rules on separating skill changes from test growth.

## Acceptance

- The `<archive>` item with lead-in **"Update cross-references."** names all three outbound link classes with the resolve-from-new-location rule, and its narrower "still names a sibling" phrasing is superseded — one canonical outbound statement remains.
- The `<archive>` closing lint item instructs the archive-inclusive lint whose findings for the moved file must be resolved, with findings in other archived files surfaced as pre-existing context; the `<lint>` section states both `--include-archive` uses in one canonical passage, superseding the task_fix-only ownership wording.
- The `<archive>` intro's step count matches its actual item count.
- Staged fixture run: a task file carrying an `archive/<sibling>.md` link, a live-sibling link, and an out-of-tree `../` link, archived per the rewritten workflow, ends with all three links resolving on disk, the sibling's inbound link re-pointed, and `lint.py --include-archive --quiet` reporting the moved file clean.
