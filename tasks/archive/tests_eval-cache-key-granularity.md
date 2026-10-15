---
description: Narrow the shared behavioral-eval verdict cache key with fail-closed per-eval dependency declarations and always-on grade.sh arm-split, so an edit re-runs only the evals that can reach it.
scope: "local test harnesses"
created: 2026-09-04T17:54:29
updated: 2026-10-15T16:00:19
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Narrow the behavioral-eval verdict cache key to what each eval reaches

## Goal

A behavioral eval re-runs when something it can actually reach has changed, and
keeps its recorded verdict otherwise. The user-visible outcome: editing one rule
in a skill, or one `case` arm in a grader, spends worker time only on the evals
that exercise that rule or arm, so a targeted fix costs a targeted run instead
of the whole suite.

The narrowing holds the cache's existing safety property unchanged: it can never
serve a stale pass, given a grader that keeps the good-faith contract stated
under **Split the grader by its arms.** Skill-tree precision is declaration-opt-in and fail-closed:
every skill-tree file that no declaration covers keeps invalidating every eval,
so the invariant holds by construction rather than by an author remembering to
declare a dependency. `grade.sh` narrowing is always on per **Split the grader
by its arms.**, independent of whether a declaration is present.

## Context

The shared helper is `tests/lib/eval_cache.py`. Its `content_key()` builds each
eval's key from the `source_roots` it is handed, the `harness_dir`, the shared
`VERDICT_HELPERS` under `tests/lib`, the worker model, the eval id, and the
prompt. Both directory inputs are hashed as whole trees by `_tree_hash()`, which
is where the coarseness lives:

- **The skill tree.** Each runner's `source_roots_for()` names the skill
  directories a worker's behavior depends on, and the whole of each one is
  hashed. A rule that only some runs reach still moves every eval's key.
- **The harness tree.** `harness_dir` is the entire `evals/` directory,
  `grade.sh` included, even though a grader is a `case` statement whose arms are
  already per-eval.

Every Pattern A `evals/run.py` under `tests/` that already imports
`tests/lib/eval_cache` and calls `content_key()` shares this helper. A change to
the helper governs all of them, so the work lands once rather than per harness.
Derive that runner set at implementation time from the tree rather than from a
frozen list. The worker-model field already separates Cursor (`auto`) and Claude
(`sonnet`) cache entries, so this task leaves vendor selection alone.

`tests/CLAUDE.md` documents what the cache key hashes in the verdict-cache
section that names the key's inputs. `tests/AGENTS.md` under `### Verdict cache, timeouts, isolation` points at that `tests/CLAUDE.md` policy rather than restating it. This task rewrites the `tests/CLAUDE.md` whole-tree key passage in place; the `tests/AGENTS.md` pointer stays accurate by deferring to the rewritten `tests/CLAUDE.md` text.

The measured motivation, as one illustration of the general cost: in a single
session on the `git_review` skill, an edit confined to publishing rules
invalidated all of that harness's evals, of which most are plain review runs
that never enter the publishing or reviewer-edit stages at all; and a change to
one grader `case` arm invalidated every eval that arm does not grade. Full suite
runs went to verifying edits that only a minority of evals could reach.

[The grader-authoring discipline task](tests_grader-authoring-discipline.md)
governs how grader checks assert and shares the `grade.sh` edit surface. The two
touch the same file for different reasons and impose no order on each other.
[The git eval-runner parity task](../tests_git-eval-runner-parity.md) adds runners
that will consume the same helper once they exist; this task's fail-closed
default keeps an undeclared eval correct for any runner that lands later.

## Approach

Extend `tests/lib/eval_cache.py` so `content_key()` accepts an optional
per-eval dependency declaration and folds it into the key in place of the
whole-tree hashes it covers. Teach every Pattern A runner that already
calls `content_key()` to forward that optional field when the harness
definition supplies one; only `tests/git_review` authors `dependencies`
maps in this task.

**Declare dependencies per eval, and fail closed.** An eval declares the parts of the skill tree its verdict depends on. `VERDICT_HELPERS` keep joining every key unchanged; only the whole-tree hashes for covered skill paths give way to the declaration. When a skill root carries a declaration, the key hashes each listed stage body from that root's `SKILL.md` and omits every undeclared top-level stage body under that root; every other file under the root, and every non-stage `SKILL.md` byte (material outside those top-level stage elements), keeps contributing fail-closed and still invalidates every eval. An absent or malformed declaration produces the same key as Acceptance **No-declaration baseline and grade.sh arm-split.** Harness contribution always follows **Split the grader by its arms.**, independent of whether `dependencies` is present. This is what makes the narrower key a provable superset of what determines the verdict: stage narrowing applies only where a declaration lists stages, while undeclared files and non-stage material stay fail-closed by construction.

**Name a skill section, not a line range.** A declaration points at the
pseudo-XML stages a run exercises, so it survives edits inside those stages and
moves the key when one of them changes. Resolve a named stage by reading its
element out of the `SKILL.md`, and fall back to the whole-file hash when the
element is absent, so a renamed or removed stage invalidates rather than
silently matching nothing.

**Split the grader by its arms.** Arm-splitting replaces only `grade.sh`'s contribution to the key. For each `eval_id`, the splitter includes every arm that matches that id across every top-level `case "$eval_id"` block in `grade.sh`, plus every shared region outside those selected arms (predicates, helpers, and prose that sit between or around the blocks). A nested `case` that appears inside a selected arm is part of that arm and joins that eval's key with it. Every other path under `harness_dir` (`evals.json`, `stage.sh`, `run.py`, fixtures, README, and any sibling file the tree already hashes today) keeps participating in every eval's key exactly as `_tree_hash(harness_dir)` does now. A grader whose top-level `case "$eval_id"` structure the splitter cannot determine contributes its whole `grade.sh` content to every eval's key, per the fail-closed rule; multiple discernible `case "$eval_id"` blocks are not themselves a fail-closed trigger. The split is used only when bash's own parse confirms it, and it assumes a grader written in good faith: no program the grader executes re-enters `grade.sh`, and neither the grader nor a file it sources rebinds `eval_id`, changes positional parameters before the binding, or changes how bash parses or matches arms through indirection static inspection cannot read. The checks fail closed on every such construct they recognise, and this precondition covers the rest.

**Keep the declaration beside the eval.** The declaration lives with the eval it
describes in `evals.json`, so an author adding an eval writes it in one place
and a reader sees the coverage claim next to the scenario.

**Declaration schema.** Each eval object in `evals.json` may carry an optional `dependencies` object whose only skill-side shape is a map from skill-root basename (the same basename `content_key()` already labels each `source_roots` entry with) to a list of `SKILL.md` stage element names that eval exercises under that root — for example of object shape only (not which stages any eval must list): `"dependencies": { "git_review": ["primary_workflow", "output_contract"], "guardrail": ["hierarchy"] }`. A listed stage binds only to its mapped root. When a sibling root's basename also appears in `dependencies`, an undeclared stage under that sibling does not move that eval's key; when that sibling basename is absent from `dependencies`, the sibling keeps today's whole-tree contribution. Harness narrowing is not a field in this object; it is only the automatic `grade.sh` `case`-arm split already stated under **Split the grader by its arms.** Omitting the field, passing a null value, or failing to parse it leaves every uncovered skill-root input on today's whole-tree contribution; harness contribution always follows **Split the grader by its arms**, independent of whether `dependencies` is present.

**Stage selection.** For each eval the git_review sample authors, under each `source_roots` basename the worker can reach when that eval runs, list every top-level child element of that skill's root wrapper that run can actually reach; when whether a stage is reached is uncertain, include that stage; omit a basename the run does not reach stage-specifically so that root keeps today's whole-tree contribution. Take element names from the live `SKILL.md` at authoring time.

**Prove the invariant with tests.** Cover the helper under the existing
script-test surface: a declared-narrow eval whose declared stage changes misses,
the same eval whose undeclared sibling stage changes hits, an undeclared file
under a skill tree invalidates every eval, an absent or malformed declaration
falls back to the **No-declaration baseline and grade.sh arm-split.** key, a
renamed stage invalidates, and a grader arm change reaches only its own eval.

**Rewrite the verdict-cache docs with the shared policy.** Under **Verdict-cache docs rewrite.**, when that Acceptance item’s sample harness receives declarations, its operator RUNBOOK passage that enumerates verdict-cache key inputs is rewritten in place to the narrowed, fail-closed key alongside `tests/CLAUDE.md` and the module docstring Inputs enumeration plus the `content_key()` docstring in `tests/lib/eval_cache.py`. The RUNBOOK rewrite target is `tests/git_review/RUNBOOK.md` (`## The verdict cache`). Harnesses that stay undeclared keep skill-side whole-tree key prose until they receive declarations; residual RUNBOOK drift from **No-declaration baseline and grade.sh arm-split.**’s universal `grade.sh` arm-split is accepted, with `tests/CLAUDE.md` authoritative. `tests/AGENTS.md` under `### Verdict cache, timeouts, isolation` continues to point at that `tests/CLAUDE.md` policy without restating it.

**Out of scope:**

- Changing what any eval covers or how any check asserts; this task changes when
  an eval re-runs.
- The worker-spawning and grading flow inside each runner, which stays as it is,
  including the `--vendor` switch in `tests/lib/vendor.py`.
- The legacy two-layer `wiki` harness, which runs no Pattern-A verdict cache.
- Backfilling declarations across every existing eval. The fail-closed default
  keeps an undeclared eval correct, so declarations land where the run cost
  justifies them.
- Rewriting other Pattern A harness `RUNBOOK.md` passages that still describe whole-tree keying. Under the fail-closed default those harnesses keep skill-side whole-tree invalidation until they carry declarations; **No-declaration baseline and grade.sh arm-split.**’s automatic `grade.sh` arm-split still applies to every Pattern A caller, so those RUNBOOK passages may drift from that part of the key. `tests/CLAUDE.md` under **Verdict-cache docs rewrite.** is authoritative for the narrowed key; only the sample harness named under **Verdict-cache docs rewrite.** (`tests/git_review`) gets its RUNBOOK rewritten here.

## Acceptance

1. **No-declaration baseline and grade.sh arm-split.** `content_key()` in `tests/lib/eval_cache.py` accepts a per-eval dependency
   declaration and folds it into the key. A call that passes none keeps today's
   whole-tree contribution for every skill root and every harness path other
   than `grade.sh`, while `grade.sh` contributes via the automatic `case`-arm
   split Approach names (or the whole file when unparseable). Proven by a
   script test that, after the change, recomputes and pins one no-declaration
   key on a fixture whose `grade.sh` makes that arm split explicit, asserting
   that every skill root and every harness path other than `grade.sh` keep
   today's whole-tree contribution while `grade.sh` follows Approach's
   arm-split (or the whole file when unparseable), and that each
   `VERDICT_HELPERS` member still moves every eval's key with the same
   contribution as today.
2. A call that passes a malformed dependency declaration produces the same key
   as **No-declaration baseline and grade.sh arm-split.** for that eval, proven by a script test that
   feeds a deliberately malformed declaration and pins the key against that
   baseline.
3. An eval declaring a skill stage it exercises keeps its cached verdict when a
   different, undeclared stage in the same `SKILL.md` changes, and loses it when
   the declared stage changes. When `source_roots` lists several skills and a
   sibling root's basename also appears in `dependencies`, a stage listed under
   one root's basename keeps the verdict when an undeclared stage under that
   sibling changes; when that sibling basename is absent from `dependencies`,
   that sibling keeps today's whole-tree contribution. Both the same-file and
   multi-root directions are covered by script tests over staged fixture skills.
4. A file under a declared skill tree that no declaration names invalidates
   every eval of that harness, proven by a test that adds such a file and
   observes a miss on an eval whose declarations are otherwise untouched.
   On that same declared-narrow fixture, a change that touches only
   non-stage `SKILL.md` material under the declared root (bytes outside
   every top-level stage element) also produces a miss on that eval,
   proven by a script test that performs that edit alone and asserts the
   miss.
5. A declaration naming a `SKILL.md` element that does not exist falls back to
   the whole-file hash rather than matching nothing, proven by a test that
   renames a declared stage and observes a miss.
6. A change to one matching `case` arm of a harness `grade.sh` invalidates that arm's
   eval alone, while a change to a shared region outside the selected arms
   invalidates every eval of that harness. On a fixture grader with more than
   one top-level `case "$eval_id"` block, every arm that matches the eval id
   (including nested `case` content inside a selected arm) joins that eval's
   key. A change to any other path under that harness's `harness_dir` (for
   example `evals.json` or a fixture) also invalidates every eval of that
   harness. All four directions are covered by script tests.
7. A `grade.sh` whose `case` shape the splitter cannot parse contributes its
   whole content to every eval's key, proven by a test over a deliberately
   unparseable grader.
8. Every Pattern A `evals/run.py` under `tests/` that already calls
   `content_key()` passes its declaration through to that helper, proven by a
   call-site tree check that each such runner forwards the optional
   declaration when the harness definition supplies one. Before
   changing the key formula, capture each such runner's suite once on the
   default vendor per `TESTING.md` and record every eval id's graded
   pass/fail verdict under a `baseline` heading in
   `tests/lib/results/eval-cache-key-granularity-comparison.md`. After the
   change, re-run each suite once on that vendor against an otherwise
   unchanged tree and record the verdicts under an `after` heading in the
   same file. A suite whose every eval's content key is byte-identical
   under the old and the new formula on the same tree is instead satisfied
   by that key-identity proof, recorded under its `after` heading in place
   of a fresh after run, because such a run could only replay or resample
   the baseline's inputs, and `TESTING.md` `## Re-run Economy` calls a
   criterion that mandates a re-run buying no new information a defect.
   When every eval id matches its baseline verdict, that suite's
   comparison passes. When any id diverges, re-run only the diverging evals
   once more on the same vendor; if they then match the baseline, record the
   transient miss and treat the suite as matching. If a divergence remains
   after that second run, record each remaining
   `(eval_id, baseline_verdict, after_verdict)` triple with a one-line
   disposition that attributes the flip to LLM nondeterminism on an
   unchanged prompt/grader (and states that the cache-key formula change
   does not explain it); that recorded residual is a satisfied suite
   outcome, not a failure of this item. The item is satisfied when the
   call-site tree check passes and the file carries the baseline, the
   after run or a suite's key-identity proof, and for every suite either a
   key-identity proof, a clean match (including after
   at most one bounded re-run of diverging evals) or such recorded
   residual triples with nondeterminism dispositions.
9. **Verdict-cache docs rewrite.** The verdict-cache section of
   `tests/CLAUDE.md`, `## The verdict cache` in
   `tests/git_review/RUNBOOK.md`, and the module docstring Inputs enumeration
   plus the `content_key()` docstring in `tests/lib/eval_cache.py`, state the
   narrowed key and the fail-closed rule, including that `VERDICT_HELPERS`
   still join every key, that skill-tree whole-tree hashes narrow only where a
   declaration covers them, and that harness contribution always follows
   **Split the grader by its arms.** (whole `grade.sh` when unparseable), and the passages describing the whole-tree key are gone rather than
   left beside the new statement. `tests/AGENTS.md` under `### Verdict cache, timeouts, isolation` continues to point at that `tests/CLAUDE.md` policy without restating the key.
10. `tests/git_review/evals/evals.json` carries `dependencies` maps on its
    evals in the schema Approach names (skill-root basename → stage element
    names; no harness paths), and each map follows Approach's **Stage
    selection.** rule, and `tests/git_review/evals/README.md` records
    that schema, that rule, and how an author writes one, with any prior
    schema note that omits it superseded rather than left beside the new one,
    and a script test proves that a non-publishing eval whose map omits the
    `publishing` stage keeps its key when that stage changes.
