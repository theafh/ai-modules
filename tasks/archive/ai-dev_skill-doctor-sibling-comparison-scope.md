---
description: Scope skill_doctor's sibling description comparisons to one family group, so a skill from another family or plugin neither raises a sibling finding nor hides one.
scope: plugins/ai_dev/skills/skill_doctor
created: 2026-08-14T19:11:13
updated: 2026-08-14T20:25:27
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Scope skill_doctor's sibling comparisons to one family group

## Goal

Every sibling finding names skills that are genuinely siblings. A description
is compared only against the skills a deliberate declaration binds it to, so a
skill from another family or another plugin neither raises a sibling finding
nor hides a real one. Two behaviours change for the user. A whole-repo run
stops measuring one skill's description against every unrelated skill in the
tree, and a name-prefix family that spans plugins compares within each declared
group rather than across the coincidence.

## Context

`sibling_findings` in
`plugins/ai_dev/skills/skill_doctor/scripts/discovery_safety.py` compares
whatever paths the run passed it, with no notion of which of them are siblings.
It computes one `mean_len` over every description for `sibling_length_outlier`,
runs `is_outlier_trait` over the same flat set for
`sibling_typographic_punctuation_outlier` and
`sibling_risky_punctuation_outlier`, and runs one pairwise loop over every pair
for `sibling_routing_overlap` and `sibling_purpose_not_distinct`. The set is
whatever the skill selected: `<discovery_safety>` in
`plugins/ai_dev/skills/skill_doctor/SKILL.md` instructs the run to pass every
selected `SKILL.md`, and for a family request every sibling.

**A whole-repo run already compares unrelated skills.** Resolving `--all`
against this repository and passing that set to `scripts/discovery_safety.py`
emits sibling findings computed across every skill the walk found, families and
standalone skills alike. Measured on the current tree, that run produces six
`sibling_typographic_punctuation_outlier` findings and two
`sibling_length_outlier` findings, among them `guardrail` reported as a length
outlier against a mean drawn from the whole tree and `ai_instruction_writing`
reported as a punctuation carrier against skills it shares no family with. Each
finding's own message says the description is out of step with its *siblings*,
which is a claim the computation never established.

**A cross-plugin prefix family carries the same defect in a narrower mode.**
`resolve_family` in `scripts/resolve_scope.py` keeps a same-prefix skill that
lives in another plugin and reports the split as a `family_spans_plugins`
warning, which
[ai-dev_skill-doctor-family-resolution-and-drift.md](ai-dev_skill-doctor-family-resolution-and-drift.md)
settled deliberately so a genuine cross-plugin family keeps working. That
membership decision stands. What follows it does not: the coincidental member
then enters these comparisons, and the warning makes the situation diagnosable
without stopping the computation. This repository cannot reach that state
today, because every family here sits wholly inside one plugin, and the case is
the marketplace repository of independently authored plugins that the same task
named as likely rather than exotic.

The contamination runs in three directions, and only the first is obvious. An
unrelated description shifts `mean_len`, so a length outlier appears or
disappears. `is_outlier_trait` fires only when the carriers are a proper
non-empty subset of the set, so adding an unrelated skill can turn a trait the
real family all shares into a subset and invent a finding, or complete the set
and suppress a real one. The pairwise loop compares every pair, and
`sibling_purpose_not_distinct` is the one sibling finding at **blocking**
severity, so two unrelated skills whose purpose clauses happen to match would
block a healthy repository. That case does not fire on this tree today, so it
is latent where the warning-tier contamination is live.

The two scripts share only a list of paths. `resolve_scope.py` knows the family
token, the hub's parsed `<family>` block, and the `by_plugin` grouping that
`group_by_plugin` builds; `discovery_safety.py` receives positional paths and a
`--root`. Nothing carries provenance across that seam today.

**Co-edit coordination.** `scripts/resolve_scope.py` is also the edit surface of
[ai-dev_skill-doctor-agent-scope.md](../ai-dev_skill-doctor-agent-scope.md), which
owns the agent-handling passage and any `--agent` resolver mode its
**Open decision:** settles. Neither blocks the other; whichever lands second
reconciles the shared file.

## Approach

Give the comparison a group and compute every sibling finding within one group
at a time, leaving membership and the finding set alone.

**Define the group by declaration, not by selection.** A comparison group is
computed from the given paths: take each family-name token those names imply
under `shares_family_name` (a name equals the token or equals `token_*`) and
apply `resolve_family` to that token against the walk at `--root`. A hub is not
required. When no hub and no `<family>` block exist, that prefix set is the
group. Then split a same-prefix member in another plugin into its own group
unless a hub exists and that hub's parsed `<family>` block names it. A given
path the walk under `--root` does not list still receives that classification
from the path's own frontmatter name and plugin host. This reads the
family-resolution task's settled reasoning forward: the resolver keeps the
member because a genuine cross-plugin family exists as a case, and the block is
what distinguishes the declared case from the accident.

A skill that belongs to no family is a group of one and draws no sibling
finding, which the short-circuit that already skips a set of fewer than two
descriptions delivers for free. Every sibling finding then means what its
message says. A repo-wide house-style comparison across unaffiliated skills is
a different question that no finding currently claims to answer, so this work
stops answering it by accident rather than rewording a finding to keep it.

**Derive the grouping from a shared module rather than passing it between the
scripts.** Move the discovery half of `resolve_scope.py` into one module
beside the two scripts and have both load it: the walk, the frontmatter name
read, the plugin-host lookup, the `<family>` block parse, and the constants
they already both carry. `discovery_safety.py` then derives its own grouping
from the group rule above, using `--root` as the existing walk-and-citation
flag rather than a grouping payload, so a run is correct with no grouping
argument from its caller. The alternative, an argument the agent copies out of
the resolver payload, puts the correctness of every family run behind a prose
step and degrades silently into today's behaviour whenever that step is
missed. The second walk costs roughly a quarter second on this repository
against the check's own runtime, one implementation cannot drift from itself,
and the two scripts already carry their own copies of `split_frontmatter` and
`SKILL_FILE_RE`, which have diverged in text while staying equivalent only
because `Path.read_text` normalises line endings before either copy runs.

The module has to import cleanly under both load paths in use. A plain sibling
import resolves when a script runs by absolute path, since Python puts the
script's own directory first on the import path, and fails under the
`importlib.util.spec_from_file_location` form the script tests use, which sets
no such entry. Inserting the script's own directory ahead of the import
satisfies both. Re-export every discovery symbol those importlib loads import
from `resolve_scope.py`, including `parse_family_block_names`, so the runtime
loads keep passing. The AST docstring check that currently parses
`resolve_scope.py` for a `FunctionDef` named `parse_family_block_names` moves
to the shared module, because a re-export is not a function definition in that
file.

**Restage the existing sibling-assertion fixtures onto one declared group.**
`tests/skill_doctor/script_tests/run.sh` currently compares a selected set:
`good_a` / `good_b` / `risky` (the `1 of 3` typographic outlier) and `typo_em`
/ `typo_ell` plus `good_a` / `good_b` (the `2 of 4` multi-carrier message).
Restage each mix as one declared group — a shared prefix in one plugin, or a
hub `<family>` block that names them. The four-path mix keeps two carriers and
two clean descriptions inside that one group: two `typo_` carriers alone fill
their prefix set and `is_outlier_trait` stays quiet.

**Rewrite the statements that describe the old behaviour in place.** The
`<discovery_safety>` bullet reading `Compare sibling descriptions inside the
same selected set for formatting outliers, risky punctuation, typographic
punctuation, routing overlap, and user-readable high-level distinctness.`
becomes a statement of the group rule, and the `sibling_findings` docstring
follows it. Three leftover selected-set phrases are rewritten to agree with
that same statement rather than restating it: the length paragraph that
currently reads the sibling finding against `the selected set`, the
listing-budget comment that currently contrasts the per-skill finding with
`the siblings in the selected set`, and the `typographic_message` that
currently reports `N of M descriptions in the selected set`. One canonical
description of what a sibling finding measures remains.

**Out of scope:**

- Changing which skills a family run resolves. Membership stays where
  [ai-dev_skill-doctor-family-resolution-and-drift.md](ai-dev_skill-doctor-family-resolution-and-drift.md)
  settled it, keeping the cross-plugin member and warning; this task changes
  only what gets compared against what.
- Adding sibling finding codes or changing their thresholds. The five existing
  codes keep their detection rules and their severities, including
  `sibling_purpose_not_distinct` at blocking.
- The per-skill listing-budget length finding, which
  [ai-dev_skill-doctor-listing-budget-length.md](ai-dev_skill-doctor-listing-budget-length.md)
  deliberately made independent of how many siblings a run selected. It reads
  one description against the harness budget and no grouping touches it.

## Acceptance

Every staged `scripts/discovery_safety.py` invocation below passes `--root` at
that staged tree unless the item itself names a different `--root`.

1. Resolving `--all` against this repository and passing that set to
   `scripts/discovery_safety.py` produces sibling findings whose named skills
   all sit in one family group. The same run today produces cross-family
   findings, measured on the current tree as six
   `sibling_typographic_punctuation_outlier` and two `sibling_length_outlier`
   findings, with `guardrail` and `harness_portability` reported as length
   outliers against a whole-tree mean; record the post-change counts beside
   those, and when the run still reports a cross-family finding, record which
   and stop rather than adjusting a threshold to hide it.
2. A staged repository with `plugins/one/skills/db_query` and
   `plugins/two/skills/db_migrate`, whose descriptions are written to trip a
   pairwise finding against each other, produces no sibling finding pairing the
   two after the work and does produce one before it. Resolving `--all`
   against that staged `--root` lists both skills, so walk membership is the
   coincidence split rather than an omitted path. Resolving `--family db`
   against that same staged `--root` still lists both members and still
   reports `family_spans_plugins`.
3. A staged cross-plugin family whose hub `<family>` block names the member in
   the other plugin compares across that split and produces the pairwise
   finding its descriptions earn, so a declared cross-plugin family keeps its
   sibling coverage.
4. A staged family wholly inside one plugin produces the same sibling findings
   before and after the work, so the common case is unchanged. That staged
   family is a hubless prefix set: no skill is named the token, the shape
   `--family format` already resolves on this tree.
5. `scripts/discovery_safety.py` invoked directly on paths from two different
   families, with no caller supplying a grouping argument, groups them and
   produces no cross-family finding, so correctness needs no grouping payload
   from whoever calls it. `--root` is the existing walk-and-citation flag, not
   that payload. The same item also proves given paths classify when the walk
   omits them: invoking with `--root` at this repository, whose walk omits
   gitignored staged files, still groups those given paths and produces no
   cross-family finding. A single-skill run reports no sibling finding, as it
   does today.
6. Both scripts load the shared discovery module when run by absolute path and
   when loaded through `importlib.util.spec_from_file_location`.
   `split_frontmatter` and `SKILL_FILE_RE` are defined once in that module and
   no longer in either script. `resolve_scope.py` re-exports the moved symbols
   those importlib loads import from it, including `parse_family_block_names`.
   The AST docstring check that currently parses `resolve_scope.py` for a
   `FunctionDef` named `parse_family_block_names` moves to the shared module.
7. A staged pair of unrelated same-prefix skills in different plugins whose
   purpose clauses are identical produces no `sibling_purpose_not_distinct`
   finding and exits zero, while a staged pair of declared siblings with
   identical purpose clauses still produces that blocking finding and exits
   nonzero.
8. A staged whole-repo set containing skills that belong to no family produces
   no sibling finding naming any of them, while each of those skills keeps its
   per-skill findings unchanged.
9. `rg "selected set" plugins/ai_dev/skills/skill_doctor/SKILL.md
   plugins/ai_dev/skills/skill_doctor/scripts/discovery_safety.py` returns no
   match, and `<discovery_safety>` carries one statement of the group rule
   naming what a sibling finding compares. The `sibling_findings` docstring
   agrees with it. A staged `sibling_typographic_punctuation_outlier` finding
   emits a message that names that comparison group rather than a selected set.
10. `tests/skill_doctor/script_tests/run.sh` gains a scenario for each staged
    shape above: the cross-plugin coincidence, the declared cross-plugin
    family, the one-plugin hubless prefix family, the no-grouping-argument
    default, the identical-purpose pair in both readings, and the unaffiliated
    whole-repo set. The existing sibling-assertion fixtures are restaged onto
    one declared group and keep their `1 of 3` (`good_a` / `good_b` /
    `risky`) and `2 of 4` (`typo_em` / `typo_ell` plus two clean descriptions)
    message contracts. The suite passes in full with every scenario reported.
11. The skill-behavior evals under `tests/skill_doctor/evals/` pass on the
    changed skill, since `<discovery_safety>` prose changes invalidate their
    recorded verdicts.
