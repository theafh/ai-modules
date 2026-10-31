---
description: "Make the deterministic test gate hermetic and green: fix skill_doctor's mixed-family grouping failure, and remove git_review's dependence on ambient git core.quotePath."
scope: "local test harnesses"
created: 2026-10-30T23:33:51
updated: 2026-10-31T10:36:25
status: checked
reported-by: Andreas Hoffmann
---

# Make the deterministic test gate hermetic and green

## Goal

Every committed `script_tests/` suite passes on a clean checkout regardless of
the operator's ambient git configuration, so the repo's deterministic gate
either proves the tree good or names a real defect. Two failures break that
today: one genuine product-adjacent defect in `skill_doctor`'s comparison
grouping, and one harness that reads the operator's `core.quotePath` setting
instead of pinning its own.

The user-visible outcome: `bash tests/skill_doctor/script_tests/run.sh` and
`bash tests/git_review/script_tests/run.sh` both exit zero on a clean checkout
with a stock git configuration, and both fail when the behaviour they pin
actually breaks.

## Context

`AGENTS.md` requires `make lint` clean before every commit and names a red
lint run as the repo's gate rather than a report about one session's files.
The script-test suites carry the same role for behaviour, and
`TESTING.md` `## Coverage Expectations` makes them the default post-change
check. A suite that fails on a healthy tree spends that authority: the next
agent cannot tell its own regression from the pre-existing red.

Measured on 2026-10-30 at commit `54680e4` with a clean working tree.

**`skill_doctor`: one failing check.** `bash
tests/skill_doctor/script_tests/run.sh` reports `364 passed, 1 failed`, the
failure being `self_whole_repo_groups_each_hold_one_family`. That check asserts
every `comparison_groups` entry holds one family, and the whole-repo run
produces the mixed group `'git_auto_review family' -> ['git_auto_review',
'git_review']`. The cause is in
`plugins/ai_dev/skills/skill_doctor/scripts/skill_discovery.py`:
`declaring_hubs()` resolves a declared name to a hub whose own name shares a
family prefix with it, and `git_auto_review`'s `<family>` block declares
`git_review`, whose leading token `git` also prefixes `git_auto_review`,
`git_checkout`, `git_commit`, `git_refresh`, and `git_status`-style neighbours.
The grouping then binds two names that share no family token. Either the
grouping needs a same-token test before it binds, or the `<family>` block needs
to stop declaring a name outside its own token — the implementer settles which
against the check's own stated intent, since the check exists to guarantee that
a sibling finding's message is true.

**`git_review`: five failing checks under a non-default git setting.** With
`core.quotePath=false` in the environment — set through
`GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0`, which is how the
Cursor sandbox and some operator profiles export it — the suite reports
`34 pass, 5 fail` on scenarios s22, s25, s30, s31, and s32. Every failure is a
check that expects git to print a non-ASCII path in its C-quoted form
(`"\303\244.txt"`); with `quotePath=false` git prints the raw path. The same
tree reports `39 pass, 0 fail` once those variables are unset. `git_review`'s
bundled scripts already handle both forms, so the product is correct and the
harness is the surface at fault: the scenarios inherit the ambient setting
instead of pinning the one they assert.

`TESTING.md` `## Running Tests` already records that a sandbox-only failure is
an environment result to re-run unsandboxed before reporting. That guidance
covers a sandbox that blocks writes; it does not cover a suite that reads an
ambient git config, which is the defect here.

## Approach

Fix the product-adjacent grouping first, then make the harness hermetic.

1. **`skill_doctor` grouping.** Remove `git_review` from `git_auto_review`'s
   `<family>` block. `declaring_hubs()` stays as written: its docstring states
   that a block binds a member whose own name shares no prefix with the family,
   so the declaration is what carries that member's family, and the
   `sibling_group_binds_every_declared_member` and
   `declared_span_compares_across_the_plugin_split` fixtures assert that
   cross-token authority on the repo's own tree. Record the resolution rule
   beside the declaration it governs. The existing
   `self_whole_repo_groups_each_hold_one_family` check must pass on the repo's
   own tree, and the fixture cases that already pass must keep passing.
2. **`git_review` hermeticity.** Give the affected scenarios their own git
   configuration rather than the ambient one. Git resolves `core.quotePath`
   from the inherited `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_*` /
   `GIT_CONFIG_VALUE_*` environment ahead of any repository config, and a
   command-line `-c` ahead of both, so clearing that environment is the
   operative half of the pin: clear those variables once at suite entry,
   beside the suite's own prologue, so the pin covers every git invocation the
   suite makes — the collectors that produce the quoted-path evidence and the
   scenarios' own expectation computations alike, including the
   `git diff --name-only` fixture-shape guards and the `git diff --name-only` /
   `--numstat` / `--name-status` calls that build `expected_paths` and the
   line-count baselines. The repository setting (`git config core.quotepath
   true`) that the scenarios already carry is the fallback for a clean
   environment, so it stays as written. Keep the assertions as they are: the
   scenarios assert a real property of the bundled scripts, and the fix belongs
   in the fixture, not in the check. Add one scenario that re-exports the
   inverted value for its own git invocations and runs the quoted-path
   assertions under it, so the pin is proved rather than assumed.
3. **Record the ambient-config class.** Note in `tests/AGENTS.md` and
   `tests/CLAUDE.md`, in lockstep, that a script test pinning git output shape
   clears or overrides the inherited `GIT_CONFIG_*` environment for every git
   invocation it makes, with a `git config` setting in its own scratch repo as
   the clean-environment fallback. Cite the `git_review` scenario as the
   reference.

**Out of scope:** The `make lint` surface, which already passes. Changing the
assertions the existing scenarios make about product behaviour. Parallelizing
these suites, which the sibling parallel-eval tasks own.

## Acceptance

- `bash tests/skill_doctor/script_tests/run.sh` exits zero on a clean checkout,
  and its summary reports no failed check. The mixed group
  `'git_auto_review family' -> ['git_auto_review', 'git_review']` no longer
  appears in the whole-repo `comparison_groups` output; the check
  `self_whole_repo_groups_each_hold_one_family` is still present and still
  asserts that every group holds one family.
- The `skill_doctor` change is accompanied by a fixture or scenario that fails
  when the grouping binds two names sharing no family token, so the fix is
  pinned rather than only observed.
- `bash tests/git_review/script_tests/run.sh` exits zero with
  `GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=core.quotePath`, and
  `GIT_CONFIG_VALUE_0=false` exported, and also exits zero without them. Both
  runs are recorded for commit in `tests/git_review/results/` as a note naming
  the two commands and their tallies.
- Every suite that the selector `tests/*/script_tests/run.sh` finds exits zero
  with `GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=core.quotePath`, and
  `GIT_CONFIG_VALUE_0=false` exported, so the suite set the Goal names is
  proven by running it rather than inferred from the two suites above.
- A `git_review` scenario stages a scratch repo with the ambient
  `core.quotePath` deliberately inverted and still passes its quoted-path
  assertions, proving the suite no longer reads the operator's setting.
- `tests/AGENTS.md` and `tests/CLAUDE.md` both carry the statement `## Approach`
  step 3 defines, and the two files remain in lockstep on it.
- `make lint` passes.
