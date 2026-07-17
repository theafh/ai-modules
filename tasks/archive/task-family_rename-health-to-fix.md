---
description: Rename task_health to task_fix — mirror wiki_fix and give repair a name token (a lever for the sibling-trigger-routing task); update all refs and bump versions lockstep.
scope: plugins/ai_dev
created: 2026-05-30T00:07:29
updated: 2026-05-30T23:13:04
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Rename task_health to task_fix

## Goal

Rename the `task_health` skill to `task_fix` across every artefact that
names it — directory, frontmatter `name:`, H1, root pseudo-XML tag, the
`<family>` map in all siblings, both READMEs, and the gitignored test
harness — then bump versions lockstep. The base `task` skill stays the
source of truth; this is a **pure rename, no behaviour change**. Done =
the rename is mechanically complete and the suite/lint stay green. A
final `make deploy` (the user's to run) refreshes the deployed symlink so
the trigger runner sees the new name; that and measuring the effect on
trigger routing are out of this task's completion bar (see below).

## Context

`task_health` already describes itself as "the task-backlog analogue of
`wiki_fix`." Renaming it `task_fix` makes the two families parallel
(`wiki` ↔ `task`, `wiki_fix` ↔ `task_fix`), which aids recall and routing.

It is also a routing lever for
[task-family_sibling-trigger-routing](task-family_sibling-trigger-routing.md):
that investigation found **skill-name tokens dominate trigger routing**,
and one bleed was "audit the entire tasks tree and **fix** whatever is
mechanical" landing on `task_audit`. A `fix` name token gives that query
something to grab. Note the query carries *both* an `audit` and a `fix`
token, so the rename may not cleanly win it — that is exactly why the
**re-measurement and the verdict on whether it helped belong to the
sibling-trigger-routing task, not to this one**. This task's job is the
clean mechanical rename; that task owns re-running `task.json` afterward.

Caveat considered: "health" connotes assess-and-surface as well as repair,
while "fix" leans mutation — but `wiki_fix` carries the same audit + fix +
surface-contested scope under the `fix` name, so the precedent holds.

The deployed skills are **symlinks to source** (`~/.claude/skills/<name>`
→ `plugins/ai_dev/skills/<name>`). After the directory rename the old
`task_health` symlink dangles and a `task_fix` symlink must be created —
`make deploy` (with an `uninstall` first, or relying on its prune) handles
this and is **user-gated** per `CLAUDE.md`.

Versioning precedent: the `tasks` → `task` rename (commit `c5d0fd8`)
bumped the renamed skill a minor (`1.0.1` → `1.1.0`) and the `ai_dev`
plugin a minor lockstep (`1.1.1` → `1.2.0`). Follow that shape here.

## Approach

1. **Move the directory.** `git mv plugins/ai_dev/skills/task_health
   plugins/ai_dev/skills/task_fix` (preserves history).
2. **Rename the skill internals** in the moved `SKILL.md`: frontmatter
   `name: task_fix`, the H1 `# task_fix`, the root tag `<task_fix_skill>`
   … `</task_fix_skill>`, the `<family>` `**(this skill)**` line, and any
   prose self-reference.
3. **Update every sibling's `<family>` map and cross-references.** Each of
   `task`, `task_create`, `task_check`, `task_implement`, `task_audit`,
   `task_finish` lists `task_health` in its `<family>` map; `task_check`'s
   `description:` and `task_audit`'s `<when_to_activate>` body prose also
   point at `task_health` for whole-tree health. Repoint all to `task_fix`.
   Keep the one-line role gloss ("audit and repair the whole tasks tree")
   — only the name changes.
4. **Update both READMEs.** `plugins/ai_dev/README.md` (the `task_health`
   bullet) and root `README.md` (the layout-tree entry at the
   `task_health/` line and the skill bullet). Rename only — both bullets
   are already free of the old birth-time wording.
5. **Update the gitignored test harness.** `tests/trigger_evals/task.json`
   (`expected_skill: "task_health"` → `"task_fix"`),
   `tests/tasks/evals/stage.sh` (`skill_name="task_fix"` for the health
   case), `tests/tasks/evals/evals.json` (the `skill` field), and the
   prose in `tests/tasks/README.md` and `tests/tasks/evals/README.md`. The
   eval id / fixture dir `health` may stay as-is (internal) or be renamed
   to `fix` for tidiness — implementer's call. The trigger runner derives
   the family from directory names, so it picks up `task_fix` for free.
6. **Sweep for residue.** `grep -rn "task_health" .` (exclude
   `tasks/archive/` and `tests/**/results/`) must come back empty for live
   artefacts; archived tasks are historical record and stay.
7. **Version + deploy.** Bump the renamed skill `1.0.1` → `1.1.0` (minor,
   matching the rename precedent). Bump every other `SKILL.md` you
   actually edit per the repo's one-bump-per-commit rule — a patch suffices
   for a family-map cross-ref repoint. Bump `ai_dev` plugin meta `1.2.7` →
   `1.3.0` lockstep in `.claude-plugin/plugin.json`,
   `.codex-plugin/plugin.json`, and the `.claude-plugin/marketplace.json`
   entry. Run `make lint` and `./deployment/deployment.sh --global
   --dry-run`. The final `make deploy` to refresh the symlink is
   **user-gated** — leave it for the user; it is not part of this task's
   completion bar.

## Acceptance

- The skill lives at `plugins/ai_dev/skills/task_fix/` with `name:`, H1,
  and root tag all `task_fix`; no `task_health` directory remains.
- `grep -rn "task_health"` over live artefacts (excluding `tasks/archive/`
  and test `results/`) returns nothing; every sibling `<family>` map, both
  READMEs, and the test harness name `task_fix`.
- `tests/tasks/script_tests/run.sh` stays green; the behavioral-eval
  harness (`stage.sh`/`grade.sh`/`evals.json`) references `task_fix` and
  still self-checks; `tests/trigger_evals/task.json` expects `task_fix`.
- `make lint` and the deploy dry-run pass (modulo the known pre-existing
  `deployment.sh` shellcheck finding, which is out of scope).
- Versions bumped: `task_fix` at `1.1.0`, every other edited `SKILL.md`
  bumped per the one-bump rule, and `ai_dev` plugin meta at `1.3.0` in all
  three metadata files.
- Routing effect is **out of scope here** — after the user runs
  `make deploy`, the re-run of `tests/trigger_evals/task.json` and the
  verdict on whether the `fix` token resolved the Bucket B query are owned
  by [task-family_sibling-trigger-routing](task-family_sibling-trigger-routing.md).

## Related

- Motivating routing analysis (owns the post-rename re-measurement):
  [task-family_sibling-trigger-routing](task-family_sibling-trigger-routing.md).
- Sibling family precedent: the `wiki_fix` skill in the
  `knowledge_management` plugin.
