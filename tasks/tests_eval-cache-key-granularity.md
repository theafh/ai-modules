---
description: Narrow the shared behavioral-eval verdict cache key with fail-closed per-eval dependency declarations, so an edit re-runs only the evals that can reach it.
scope: "local test harnesses"
created: 2026-09-04T17:54:29
updated: 2026-09-04T17:54:29
status: open
reported-by: Andreas Hoffmann
---

# Narrow the behavioral-eval verdict cache key to what each eval reaches

## Goal

A behavioral eval re-runs when something it can actually reach has changed, and
keeps its recorded verdict otherwise. The user-visible outcome: editing one rule
in a skill, or one `case` arm in a grader, spends worker time only on the evals
that exercise that rule or arm, so a targeted fix costs a targeted run instead
of the whole suite.

The narrowing holds the cache's existing safety property unchanged: it can never
serve a stale pass. Every file that no declaration covers keeps invalidating
every eval, so precision is opt-in per file and the invariant holds by
construction rather than by an author remembering to declare a dependency.

## Context

The shared helper is `tests/lib/eval_cache.py`. Its `content_key()` builds each
eval's key from five inputs: the `source_roots` it is handed, the `harness_dir`,
the worker model, the eval id, and the prompt. Both directory inputs are hashed
as whole trees by `_tree_hash()`, which is where the coarseness lives:

- **The skill tree.** Each runner's `source_roots_for()` names the skill
  directories a worker's behavior depends on, and the whole of each one is
  hashed. A rule that only some runs reach still moves every eval's key.
- **The harness tree.** `harness_dir` is the entire `evals/` directory,
  `grade.sh` included, even though a grader is a `case` statement whose arms are
  already per-eval.

Five Pattern-A behavioral runners share the helper: `git_commit`, `task`,
`task_create`, `task_auto_check`, and `git_review`. A change to the helper
governs all of them, so the work lands once rather than per harness.

`tests/CLAUDE.md` documents what the cache key hashes, in the verdict-cache
section that names the key's inputs. That passage describes the current
whole-tree behavior and is rewritten by this task rather than left beside the
new one.

The measured motivation, as one illustration of the general cost: in a single
session on the `git_review` skill, an edit confined to publishing rules
invalidated all 48 of that harness's evals, of which 35 are plain review runs
that never enter the publishing or reviewer-edit stages at all; and a change to
one grader `case` arm invalidated the 47 evals that arm does not grade. Two full
suite runs of roughly two and a half hours each went to verifying edits that at
most 13 evals could reach.

[The grader-authoring discipline task](tests_grader-authoring-discipline.md)
governs how grader checks assert and shares the `grade.sh` edit surface. The two
touch the same file for different reasons and impose no order on each other.

## Approach

Extend `tests/lib/eval_cache.py` so `content_key()` accepts an optional
per-eval dependency declaration and folds it into the key in place of the
whole-tree hashes it covers, then teach the five runners and the harness
definitions to supply one.

**Declare dependencies per eval, and fail closed.** An eval declares the parts
of the skill tree and the harness tree its verdict depends on. Whatever a
declaration does not name keeps its whole-tree contribution to the key, so an
undeclared file, a newly added file, and a malformed declaration each fall back
to today's behavior. This is what makes the narrower key a provable superset of
what determines the verdict: narrowing happens only where a declaration
positively claims coverage, and every other byte still invalidates everything.

**Name a skill section, not a line range.** A declaration points at the
pseudo-XML stages a run exercises, so it survives edits inside those stages and
moves the key when one of them changes. Resolve a named stage by reading its
element out of the `SKILL.md`, and fall back to the whole-file hash when the
element is absent, so a renamed or removed stage invalidates rather than
silently matching nothing.

**Split the grader by its arms.** A grader's per-eval `case` arm contributes to
that eval's key alone, while the shared predicate and helper region above the
`case` statement contributes to every eval's key. A grader whose shape the
splitter cannot parse contributes whole, per the fail-closed rule.

**Keep the declaration beside the eval.** The declaration lives with the eval it
describes in `evals.json`, so an author adding an eval writes it in one place
and a reader sees the coverage claim next to the scenario.

**Prove the invariant with tests.** Cover the helper under the existing
script-test surface: a declared-narrow eval whose declared stage changes misses,
the same eval whose undeclared sibling stage changes hits, an undeclared file
anywhere invalidates every eval, an absent or malformed declaration falls back
to whole-tree, a renamed stage invalidates, and a grader arm change reaches only
its own eval.

**Out of scope:**

- Changing what any eval covers or how any check asserts; this task changes when
  an eval re-runs.
- The worker-spawning and grading flow inside each runner, which stays as it is.
- The legacy two-layer `wiki` harness, which runs no Pattern-A verdict cache.
- Backfilling declarations across every existing eval. The fail-closed default
  keeps an undeclared eval correct, so declarations land where the run cost
  justifies them.

## Acceptance

1. `content_key()` in `tests/lib/eval_cache.py` accepts a per-eval dependency
   declaration and folds it into the key, while a call that passes none still
   produces the key it produces today, proven by a test that pins one such key
   across the change.
2. An eval declaring a skill stage it exercises keeps its cached verdict when a
   different, undeclared stage in the same `SKILL.md` changes, and loses it when
   the declared stage changes. Both directions are covered by script tests over
   a staged fixture skill.
3. A file under a declared skill tree that no declaration names invalidates
   every eval of that harness, proven by a test that adds such a file and
   observes a miss on an eval whose declarations are otherwise untouched.
4. A declaration naming a `SKILL.md` element that does not exist falls back to
   the whole-file hash rather than matching nothing, proven by a test that
   renames a declared stage and observes a miss.
5. A change to one `case` arm of a harness `grade.sh` invalidates that arm's
   eval alone, while a change to the shared predicate region above the `case`
   statement invalidates every eval of that harness. Both are covered by script
   tests.
6. A `grade.sh` whose `case` shape the splitter cannot parse contributes its
   whole content to every eval's key, proven by a test over a deliberately
   unparseable grader.
7. Each of the five Pattern-A runners (`git_commit`, `task`, `task_create`,
   `task_auto_check`, `git_review`) passes its declaration through to
   `content_key()`, and each runner's suite reaches the same verdicts it reached
   before the change on an unchanged tree, recorded as the before-and-after
   comparison.
8. The verdict-cache section of `tests/CLAUDE.md` states the narrowed key and
   the fail-closed rule, and the passage describing the whole-tree key is gone
   rather than left beside the new statement.
9. `evals.json` for at least one harness carries declarations for its evals, and
   `tests/<skill>/evals/README.md` for that harness records what a declaration
   means and how an author writes one.
