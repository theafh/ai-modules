---
description: Replace the diff-jargon term hunk with plain English across the auto_shaper_wiki agent, rename its two hunk tags, and update the Layer 1 contract test and live tasks that pin the old wording.
scope: plugins/knowledge_management
created: 2026-08-25T01:08:56
updated: 2026-08-25T11:59:29
status: open
reported-by: Andreas Hoffmann
---

# Replace the diff-jargon term hunk with plain English across the auto_shaper_wiki agent

## Goal

The shipped `auto_shaper_wiki` agent carries no occurrence of the word `hunk`. Every prose use becomes plain English, and the two pseudo-XML tags named with it are renamed to match.

`hunk` is unified-diff jargon. It means a contiguous block of lines that differs between two files. The agent uses it as load-bearing vocabulary in the instructions that tell the agent how to classify each difference against the canonical template. A reader who does not already know the jargon has to decode the term before they can follow the rule, and the agent's instructions are read by a model that benefits from the plain term just as a person does.

After this task, `grep -rniE "\bhunk" plugins/` returns nothing. The replacement term is defined once where it first appears, so the rest of the file can use it bare. The Layer 1 contract test that pins the old wording matches the new wording instead, and every live task quoting the old tag names resolves against the renamed tags.

This is a vocabulary replacement across one artefact, not a point-fix at one site.

## Context

`plugins/knowledge_management/agents/auto_shaper_wiki.md` is the only shipped artefact that carries the word. Take the occurrence set at implementation time from `grep -rniE "\bhunk" plugins/`, rather than from a count frozen here, because the surrounding tasks listed below edit the same file and can add or remove sites before this one lands.

The sites fall into three kinds, which the sweep handles differently:

- **Two pseudo-XML tag names.** `<hunk_classification>` wraps the rule that walks each difference and sorts it into drift, customization, preserved wording, or reorder. `<common_hunk_kinds>` wraps the open list of example difference kinds. Each needs its opening and closing tag renamed together.
- **Prose instructions.** Passages such as `Walk every hunk and classify:`, `to classify each hunk.`, `Classify each hunk`, `Common kinds of hunk the diff surfaces`, and the phrase `diff hunk needs interpretation` in the template-read rule.
- **Internal cross-references to the tags.** The agent cites its own tag elsewhere, for example in the passage `for the user per` followed by the tag name. These follow the rename.

The surrounding word `diff` stays. It already appears throughout the file, it is standard tooling vocabulary rather than jargon peculiar to this artefact, and the task's aim is the one term that needs decoding.

Two dependencies bound the sweep.

The Layer 1 contract test `tests/wiki/layer1/agent_contract.py` pins the template-read rule by regular expression, inside its `main()` function, in the `require(...)` call whose failure message reads `template reads are not hunk-scoped`. The pinned pattern spans the wording `read the relevant template section only when a` and `diff hunk needs interpretation`. Rewriting the agent without updating that call fails the default `tests/wiki/run_all.sh` Layer 1 run, so the two changes land together. The standing repo rule that a change ships with the tests it needs governs here.

Two live tasks quote the old tag names and are co-edited by this one. Take their set at implementation time from `grep -rlniE "\bhunk" tasks/*.md`, and refresh each hit rather than a list fixed at authoring time.

- [wiki_sanctioned-template-deviations.md](wiki_sanctioned-template-deviations.md) instructs rewriting `<hunk_classification>` and quotes it at several sites across its Approach and Acceptance. It is the heavier collision, and it edits the same agent file.
- [wiki_page-type-growth-and-anatomy.md](wiki_page-type-growth-and-anatomy.md) names the tag once, in the passage explaining that a declared growth pattern would otherwise survive on the tag's generic extends-the-canon fallback.

Neither sibling imposes a build order on this task, and this task imposes none on them. Whichever lands second refreshes the names the first left behind, which is why the enumeration above is a search rather than a fixed list.

## Approach

1. **Define the frozen term once.** The replacement term is **diff block**, applied uniformly. Rewrite the first passage in the agent that uses the old word so it states the term's meaning inline, as a contiguous block of lines that differs between the wiki's file and the canonical template. Every later use then stands bare. Rewrite each later passage in place so one canonical statement of the term remains and no second definition accumulates.

2. **Rename the two tags and their references together.** Rewrite `<hunk_classification>` to `<diff_block_classification>` and `<common_hunk_kinds>` to `<common_diff_block_kinds>`, opening and closing tags in the same pass, and rewrite each in-file citation of those tags to match. A renamed tag whose closing partner or whose citation still carries the old name leaves the agent's structure broken, so treat the tag, its partner, and its citations as one edit.

3. **Rewrite the prose sites.** Work the occurrence set from the `grep` in `## Context` and rewrite each remaining prose use to the frozen term. Keep each rule's meaning, scope, and strength unchanged: this task changes what the instructions are called, never what they require. Keep the full compound `diff block` and do not abbreviate to a bare `block`, because `block` already names other things in this file (a shell block, a yaml or frontmatter block, a semantic reading block, a code block). Two sites read badly under a one-for-one swap and need rewording instead: `whole-section deletion hunks` in the template-read rule, which a literal swap turns into the clunky `deletion diff blocks`, and the `Common kinds of hunk the diff surfaces` opener, where a literal swap echoes `diff ... diff`. Reword each to read cleanly while preserving the meaning, for example `a diff block that deletes a whole section` and `the kinds of diff block the comparison surfaces`.

4. **Repoint the Layer 1 contract test.** Rewrite the `require(...)` call in `agent_contract.py` whose failure message reads `template reads are not hunk-scoped`, so its pattern matches the rewritten agent wording and its message names the new vocabulary. Run the default `tests/wiki/run_all.sh` to confirm the Layer 1 contract passes against the rewritten agent.

5. **Refresh the live task cross-references.** For each live task the `grep` in `## Context` returns, rewrite its quotations of the old tag names to the new ones in place, leaving each task's Goal, Approach, and Acceptance semantics untouched. Bump `updated` on each file edited, per the standing task-family rule.

**Out of scope:** Sweeping the archived tasks under `tasks/archive/` and `CHANGELOG.md`, which keep the old word because the standing repo rules make them append-only historical records of what was written at the time. The separate word `chunk` and its plural, which appear in the wiki and `git_commit` skills and in both READMEs to describe reading a large file in pieces; that is a different word with a different meaning, and `hunk` is the only term this task replaces.

## Acceptance

- `grep -rniE "\bhunk" plugins/` returns no match, so no prose passage and no tag name in any shipped artefact carries the word.
- The agent states the replacement term's meaning exactly once, at its first use, as a contiguous block of lines that differs between the wiki's file and the canonical template; the prior undefined-jargon wording at that site is superseded and no second definition appears elsewhere in the file.
- Each renamed tag appears as a matched pair, so every opening tag has a closing tag under the same new name, and every in-file citation of those two tags uses the new name.
- The classification rule and the example-kinds list keep the behaviour they had before the rename: the four classification outcomes and the open-list framing of the example kinds read the same, with only the vocabulary changed. No rewritten passage reads `diff diff` or `deletion diff blocks`, and `diff block` stays the full compound rather than a bare `block` at every rewritten site.
- The `require(...)` call in `tests/wiki/layer1/agent_contract.py` whose failure message read `template reads are not hunk-scoped` is superseded in place, so its pattern matches the rewritten agent wording and its failure message names the new vocabulary rather than the old.
- The default `tests/wiki/run_all.sh` Layer 1 run passes against the rewritten agent, with the template-read contract among the checks that pass rather than skipped.
- `grep -rniE "\bhunk" tests/wiki/` returns no match, so the Layer 1 harness carries neither the old pinned regex wording nor the old `hunk-scoped` failure message.
- `grep -rlniE "\bhunk" tasks/*.md` returns no live task, so every live task that quoted the old tag names now quotes the new ones, and each file edited in that sweep carries a bumped `updated`.
- Every live task refreshed in that sweep keeps its `status` and its Goal, Approach, and Acceptance semantics unchanged, so the sweep reads as a rename and never as a re-scope.
- The sweep stays bounded: the change's file set contains no path under `tasks/archive/` and does not contain `CHANGELOG.md`.
