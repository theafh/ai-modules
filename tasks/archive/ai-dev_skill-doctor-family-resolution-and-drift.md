---
description: Parse the real family block instead of the first tag mention, group the family set by owning plugin, and warn when a prefix family spans plugins or disagrees with the hub's block.
scope: plugins/ai_dev/skills/skill_doctor
created: 2026-08-13T18:02:27
updated: 2026-08-14T19:04:43
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Correct skill_doctor's family resolution and report its drift

## Goal

A `--family <token>` run resolves the set the hub actually declares, and it
reports every way that set could be wrong rather than presenting a guess as
fact. Three behaviours change for the user: a hub that documents `<family>` in
prose or shows it in a fenced example no longer contaminates the family set, the
resolved set is grouped by the plugin that owns each member so a cross-plugin
split is visible at a glance, and the run warns when a prefix family spans
plugins or when the hub's declared block disagrees with the skills on disk.
Concretely against this repository, `--family task` returns exactly the skills
whose frontmatter `name:` is `task` or begins `task_`, and `wiki` is gone.

## Context

Family resolution has two mechanisms, and both are unreliable in ways a run
cannot currently see. `resolve_family` in
`plugins/ai_dev/skills/skill_doctor/scripts/resolve_scope.py` builds a prefix set
first, then unions in the names its hub's `<family>` block declares. The prefix
pass is primary, so a block that omits a sibling loses nothing; what the two
mechanisms lack is any report of their own uncertainty.

**The block is read from the wrong region.** `FAMILY_BLOCK_RE` is
`<family>(.*?)</family>` under `re.DOTALL | re.IGNORECASE`. The non-greedy
quantifier governs the captured *content*, not the opening tag, so the match
begins at the first literal `<family>` anywhere in the body and runs to the
nearest closing tag.
`plugins/ai_dev/skills/task/SKILL.md` is the one file here that trips it: its
`<not_in_scope>` section discusses the tag by name — the sentence beginning
`A focused sibling serves some of that backlog work better than the hub does`
writes `` `<family>` `` three times — hundreds of lines above the real block. The
captured span runs about 397 lines and 65,500 characters against a real block of
roughly 1,700, and `BACKTICK_NAME_RE` harvests 31 distinct names where the block
lists 9. `resolve_family` keeps only names matching a discovered skill, which
discards noise such as `open`, `ready`, and `mv`; one spurious name survives that
filter, `wiki`, backticked in the `<not_a_wiki>` pitfall. Running `--family task` against
this repository today returns 11 names, the ten real siblings plus `wiki`.

The cost lands in discovery safety, which compares descriptions *within* the
selected set. A skill outside the family enters the sibling-distinctness,
routing-overlap, and length-outlier computations, so the run can raise a finding
describing no real family problem and can shift the length mean enough to hide
one that is real. Nothing is written, since the doctor is check-only.

**The prefix rule can cross a plugin boundary silently.** `shares_family_name`
matches a token across the whole walk, so two unrelated plugins that each use the
same leading token resolve into one family. This repository has no such
collision — every prefix family here sits wholly inside one plugin — and that is
no argument for leaving it unguarded, because a repository this skill is pointed
at is often a plugin marketplace carrying independently authored plugins, where
two vendors reaching for the same obvious token is likely rather than exotic. A
genuine cross-plugin family does exist as a case, which is what the `<family>`
block's union is for, so the run states the split rather than assuming either
reading.

**The block harvest reads prose as membership.** `BACKTICK_NAME_RE` takes every
backticked lowercase word inside the block, not the entry names. The task hub's
own line reads ``- `task_finish` — close out: set status, bump `updated`,
archive``, so `updated` is harvested as a member today. It is harmless while the
only consumer is a set filtered against discovered skills, and it becomes a false
positive the moment a check reports block entries that name no skill.

Three body shapes decide any block-parsing fix, and each is met here or is
plausible authoring: a hub documenting the tag in backticks before or after its
real block, which the `task` hub does; a hub showing a `<family>` example inside
a fenced code block; and a file mentioning `<family>` with no closing tag at all,
which the `skill_doctor` hub itself is, and which must resolve to no names rather
than to everything from the mention to end of file.

**Co-edit coordination.** `scripts/resolve_scope.py` is also the edit surface of
[ai-dev_skill-doctor-agent-scope.md](ai-dev_skill-doctor-agent-scope.md), which
owns the agent-handling passage and any `--agent` resolver mode its
**Open decision:** settles, and of
[ai-dev_skill-doctor-repo-convention-portability.md](ai-dev_skill-doctor-repo-convention-portability.md),
which rewrote the walk and the path branch there and is the state the 11-name
measurement above was taken against. Neither blocks this task; whichever lands
second reconciles the shared file.

## Approach

Work `resolve_family` and `parse_family_block_names` as one change: the drift
warnings read the same two sets the parse fix corrects, so they share the edit
surface and one acceptance story about whether a family set can be trusted.

**Locate the block by masking, not by first occurrence.** Build a probe copy of
the body with fenced code blocks and inline code spans blanked to same-length
runs, so a `<family>` written as documentation is not read as markup, and search
that probe for the tag positions, keeping the search case-insensitive so it
matches the current `IGNORECASE` flag. Preserving length keeps the probe's
offsets usable against the original. Require the opening tag to own its line, tolerating
leading indentation and a trailing HTML comment, then take the first closing tag
after it; this covers an unbackticked mid-sentence mention, which masking alone
does not. Keep both tags required, so a body with an opening tag and no closing
tag yields no names and resolves by prefix alone. Record the choice in one
comment stating the block is located structurally rather than by first
occurrence, so a later reader does not simplify it back to a positional match.

**Harvest entry names, not every backticked word.** Read each member from the
leading backticked token of a block list item, from a copy with fenced blocks
blanked and inline code intact — the member names are themselves backticked and
would vanish under the probe mask, while a fenced example inside a genuine block
would otherwise contribute its sample names. This is what makes a dangling-entry
warning trustworthy instead of firing on prose.

**Group the resolved set by owning plugin.** Keep the flat `skills` array and
add a top-level `by_plugin` grouped view beside `layouts` that maps each
owning plugin to its members, keyed on `plugin_host["directory"]` when
`plugin_host` is present, so the orientation lead names the split instead of
presenting a flat list that hides it. A skill whose `plugin_host` is `None`
stays in `skills` and is omitted from `by_plugin`. The resolver already
records a skill's `plugin_host`, so the owning plugin is available without a
second walk.

**Warn where the set cannot be vouched for.** Add a warnings channel to the
resolver payload and surface it in the skill's report under **Warnings**, each
finding naming the skills and paths involved:

- The prefix set spans more than one plugin (the prefix set's hosted
  `plugin_host["directory"]` values have more than one distinct key, omitting
  `None`), naming each plugin and its members.
- A prefix sibling is absent from the hub's parsed `<family>` block, which reads
  as hub documentation that has fallen behind the tree.
- A block entry names no discovered skill, which reads as a member that was
  renamed or removed.

Omit-sibling and dangling-entry warnings fire only when a `<family>` block was
parsed. A prefix sibling is a skill whose frontmatter `name:` shares the family
token other than the hub itself; the hub name is not a prefix sibling whose
absence warns. A hub with no parsed block resolves by prefix alone and produces
neither finding.

Keep all three at `warning`: the harness loads every one of these skills, and a
hub may deliberately omit a deprecated sibling, so none of them is a mechanical
load failure.

**Open decision:** whether a same-prefix skill in another plugin stays in the
resolved set.

- **Keep it and warn (the default an implementer takes without further input).**
  The set stays a superset, the warning and the plugin grouping make the split
  visible, and a genuine cross-plugin family keeps working with no extra
  declaration. The cost is that a coincidental match still enters the sibling
  comparisons, which is the same contamination this task removes elsewhere.
- **Drop it and warn.** Scope the prefix pass to the hub's own plugin and report
  each excluded same-prefix skill with the note that a `<family>` block entry
  includes it deliberately. This treats the prefix as the cheap heuristic it is
  and the block as the explicit declaration, and it keeps a coincidental match
  out of the comparisons. The cost is a hubless family, such as a `format_*` set
  with no `format` skill, having no hub plugin to scope to, so that case needs
  its own rule.

**Out of scope:**

- Changing `plugins/ai_dev/skills/task/SKILL.md`. Its prose naming `<family>` is
  correct authoring; the parser is what tolerates it, and asking every future
  skill author to avoid naming their own tags would move the defect's cost rather
  than remove it.
- The `<family>` block that
  [wiki_family-inheritance-blocks.md](../wiki_family-inheritance-blocks.md) adds to
  the wiki hub, which that task owns. This work is independent of whether that
  block exists.
- A general markdown parser for skill bodies. The masking here serves this one
  lookup, and no other check in the skill parses body markup.

## Acceptance

1. Run `scripts/resolve_scope.py --root <this repo> --family task`: the resolved
   set equals the set of skills whose frontmatter `name:` is `task` or begins
   `task_`, and searching that output for `wiki` returns no match. The same
   command returns that set plus `wiki` before the work.
2. Against this repository's family hubs — `task`, `guardrail`, and prefix-only
   `wiki` — each `--family` run resolves to the prefix set unioned with the
   entry names of the block **Locate the block by masking, not by first
   occurrence.** identifies: the first line-owned opening after masking, then
   the first closing tag after it. `--family task` is the only current
   membership that changes.
3. A staged hub whose prose mentions `` `<family>` `` in backticks before its real
   block resolves to the block's members alone, and the skill named only in that
   prose is absent. Repeat with the mention after the block.
4. A staged hub showing a `<family>` example inside a fenced code block ahead of
   its real block resolves to the real block's members, and the name inside the
   fenced example is absent. Repeat with the fenced example inside the genuine
   block.
5. A staged file mentioning `<family>` in prose with no closing tag resolves to
   no block members, and a `--family` request against a token whose hub has that
   shape still returns the prefix-derived set.
6. A staged hub whose block is indented, one whose opening tag carries a trailing
   HTML comment, one whose prose names `<family>` unbackticked mid-sentence
   before the block, and one whose tags are mixed-case (`<Family>` / `</FAMILY>`)
   each resolve to their members.
7. A staged block entry reading ``- `sib_one` — does a thing, bumps `updated` ``
   yields `sib_one` as the only member of that entry, and
   `parse_family_block_names` on this repository's `task` hub returns harvested
   members that exclude `updated`.
8. The family-mode payload keeps the `skills` array and adds a `by_plugin`
   grouped view keyed on `plugin_host["directory"]` when `plugin_host` is
   present. Today's payload keys are `mode`, `selector`, `count`, `root`,
   `layouts`, `vendor_substitution`, and `skills`, so `by_plugin` is absent.
   A staged family whose skills have `plugin_host` `None` keeps those skills
   in `skills` and omits them from `by_plugin`. The orientation lead groups
   hosted members under each owning plugin.
9. A staged repo with `plugins/one/skills/db_query` and
   `plugins/two/skills/db_migrate` produces a warning naming both plugins and
   their members, and the resolved set matches whichever branch the **Open
   decision:** settles. A staged repo whose same-prefix skills all sit in one
   plugin produces no such warning. A staged repo whose hosted same-prefix
   skills sit in one plugin and that also includes a same-prefix skill with
   `plugin_host` `None` produces no such warning.
10. A staged hub whose parsed block omits a prefix sibling produces a warning
    naming that skill, and that omitted sibling remains in the resolved
    `skills` array. A staged hub whose parsed block names a skill absent from
    the tree produces a warning naming that entry. A staged hub whose parsed
    block lists every prefix sibling, including when it omits the hub name,
    produces neither, and a hub with no parsed block produces neither.
11. Running the resolver against this repository, the family-mode payload's
    warnings collection is present and contains no omit-sibling or
    dangling-entry finding. `parse_family_block_names` on this repository's
    `task` hub harvests exactly the skills whose frontmatter `name:` begins
    `task_` and excludes the hub name `task`.
12. `plugins/ai_dev/skills/skill_doctor/SKILL.md` `<scope_resolution>` states that
    the family block is identified structurally — an opening tag owning its line,
    outside code spans — so an author may document the tag freely, and its
    `<output_contract>` names the plugin grouping in the orientation lead and the
    family warnings under **Warnings**.
13. `tests/skill_doctor/script_tests/run.sh` gains a scenario for each staged
    shape: prose `<family>` before the block, prose `<family>` after the block, a
    fenced example ahead of the block, a fenced example inside the block, no
    closing tag, an indented block, an opening tag with a trailing HTML comment,
    an unbackticked mid-sentence mention, a list item that bumps `updated`,
    mixed-case tags (`<Family>` / `</FAMILY>`), cross-plugin `db_query` /
    `db_migrate`, same-prefix skills all in one plugin, a no-manifest family
    (`plugin_host` `None`), a one-plugin family that also includes a null-host
    same-prefix skill, a parsed block that omits a prefix sibling, a parsed block that names a skill absent from the tree, a
    parsed block that lists every prefix sibling including when it omits the hub
    name, and a hub with no parsed block; the suite passes in full with every
    scenario reported.
14. The family-mode payload carries a warnings collection, and each warning in it
    names the skills and paths involved.
15. Searching `parse_family_block_names` in `scripts/resolve_scope.py` for a
    comment stating the block is located structurally rather than by first
    occurrence returns a match.
