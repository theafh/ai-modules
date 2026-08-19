---
description: Harden the base task skill's archive move into a real git rename: a per-file tracked test, git mv as default, named plain-mv fallback, and the copy-then-delete pattern it replaces.
scope: plugins/ai_dev
created: 2026-08-18T14:35:37
updated: 2026-08-19T20:12:57
status: ready
reported-by: Andreas Hoffmann
---

# Archive a task file as a git rename, not a copy-then-delete

## Goal

The base `task` skill's `<archive>` move instruction states the procedure in a form
that a weaker model and a non-Claude harness both execute correctly: it names the
per-file tracked test to run, makes `git mv` the default for a tracked file, names
the condition under which plain `mv` is the right move instead, and names the
copy-then-delete pattern the instruction replaces. `auto_shaper_task`'s relocation
move stops hedging and cites the same rule.

The user-visible outcome is that closing a task leaves the archived file recorded as
a rename: `git status` shows `R  tasks/<name>.md -> tasks/archive/<name>.md`, and
`git log --follow` on the archived path still reaches the task's origin commit.

## Context

The rule already exists and is already correct in intent. The base `task` skill's
`SKILL.md` carries it inside the `<archive>` block, verbatim today:

```text
Move the file from `<tasks>/` to `<tasks>/archive/` with `git mv` (or plain `mv` if
the project is not a git repo). The filename does not change.
```

What that sentence lacks is anything a model can *run*. It states a preference and a
repo-level exception, gives no test for either branch, and says nothing about the
pattern that keeps getting used instead. In practice, across several agent harnesses
and with smaller models, close-out recreated the task file under `tasks/archive/`
with an internal file-writing tool and then deleted the original. Git records that as
a delete plus an unrelated add, so rename detection and history continuity are lost.

The move must be a real rename because the `auto_drift_task` agent reconstructs a
task's committed intent by following renames through history, which its
`<objective>` describes as following the file across its committed origin; a
delete-plus-add breaks that walk.

The propagation surfaces, and how each one gets the fix:

- **`task_finish`** delegates whole. Its `<workflow>` item whose bold lead-in
  reads **Run the base skill's `<archive>` close-out.** explicitly declines to
  restate the close-out rules, so a fix in the base rule reaches task_finish with no edit to
  its own file. This is the delegation working as designed, and this task keeps it
  that way rather than pushing a copy of the rule down into the sibling.
- **`task_fix`** carries a one-line inventory of the same move inside its
  `<authority>` block, in the parenthetical that lists the status/location move as
  "set `status`, bump `updated` from `date`, `git mv`, re-point cross-references,
  re-lint". That is a pointer, not a competing statement of the rule, so it stays as
  written unless the base rewrite changes the words it names.
- **`auto_shaper_task`** is the one sibling that genuinely hedges. Its `<remediate>`
  section says a scope relocation moves "with `git mv` when available", which reads
  as a soft preference an agent may drop. It needs realigning onto the base rule.

The standing repo rule that a skill-family rule is authored once in the family's base
skill and inherited through each sibling's `<authority>` reference is what makes the
base `<archive>` block the single edit site for the rule itself.

The shape to model the rewrite on already ships in the wiki family: the
`auto_shaper_wiki` agent carries a standalone `<use_git_mv>` fix constraint stating
the history-preserving rule as its own named block rather than as a parenthetical
inside a numbered step. That constraint is why the wiki family needs no equivalent
work here.

One command covers both branches of the test. `git ls-files --error-unmatch` exits
non-zero both when the path is untracked and when there is no git repository at all,
so a single per-file probe replaces the current repo-level phrasing without adding a
second check.

## Approach

Rewrite the base `task` skill's `<archive>` move instruction in place so one
canonical statement of the move remains. The rewritten instruction covers four
things: the per-file probe that decides the branch, `git mv` as the move for a
tracked file, plain `mv` as the move when the probe fails (untracked file, or no git
repository), and the copy-then-delete pattern the instruction supersedes. Name that
last one concretely — recreating the file at the archive path with a file-writing
tool and deleting the original — because a model that has not been told which wrong
move to avoid reaches for it whenever `git mv` is not the obvious reflex. This
negative carries content the positive framing cannot: it identifies the specific
failing behaviour rather than restating the correct one. Keep the existing sentence
that the filename does not change.

Realign `auto_shaper_task`'s `<remediate>` relocation sentence onto that rule. Replace
the "when available" hedge with a citation of the base `<archive>` move instruction,
in the same style the agent already uses when it cites the base skill's
`<backlog_coherence>` block, so the agent inherits the hardened rule rather than
carrying a second, weaker copy of it.

Leave `task_finish` unedited, and leave `task_fix`'s `<authority>` parenthetical
unedited unless the base rewrite changes a phrase that parenthetical quotes.

**Out of scope:**

- The wiki family's relocation rules. `auto_shaper_wiki` already carries the
  `<use_git_mv>` fix constraint and the wiki skill already carries the
  re-Read-after-`git mv` discipline, so there is nothing to harden there.
- A linter check that detects a non-rename archive move. The bundled `lint.py`
  inspects file content and location, and adding git-history inspection to it is a
  separate capability with its own design questions.
- Repairing the git history of task files already archived by a copy-then-delete
  move. Those histories are committed and rewriting them is not worth the cost.
- A skill-behavior eval measuring whether a model follows the hardened archive
  instruction.

## Acceptance

- The base `task` skill's `<archive>` block names the tracked probe: `rg -n
  'ls-files --error-unmatch' plugins/ai_dev/skills/task/SKILL.md` returns the move
  instruction.
- The superseded phrasing is gone and one canonical statement remains: `rg -n 'if the
  project is not a git repo' plugins/ai_dev/skills/task/SKILL.md` returns nothing,
  and the `<archive>` block contains exactly one sentence describing how the file
  moves.
- The base instruction names the copy-then-delete pattern it replaces, in terms of
  recreating the file with a file-writing tool and deleting the original.
- `auto_shaper_task`'s `<remediate>` relocation sentence no longer hedges: `rg -n 'git mv
  when available' plugins/ai_dev/agents/auto_shaper_task.md` returns nothing, and the
  relocation sentence cites the base `<archive>` move instruction.
- The filename constraint survives the rewrite: `rg -n 'The filename does not change'
  plugins/ai_dev/skills/task/SKILL.md` returns the `<archive>` move instruction.
- A tracked close-out produces a rename. In a throwaway git repository holding a
  committed task file, execute the rewritten instruction exactly as worded; `git
  status --porcelain` reports the move as `R` from the live path to the archive path,
  and `git log --follow` on the archived path reaches the original commit.
- An untracked close-out takes the fallback without erroring. In the same throwaway
  repository, a task file that was created but never committed archives through the
  fallback branch, the file lands at the archive path, and the run reports which
  branch it took.
