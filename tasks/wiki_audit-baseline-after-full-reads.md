---
description: Make the wiki audit move its baseline, and a page's checked date, forward only after it has read the pages in full, so the next audit never skips a page nobody read.
scope: plugins/knowledge_management
created: 2026-10-03T15:54:08
updated: 2026-10-04T17:06:16
status: open
reported-by: Andreas Hoffmann
---

# Move the wiki audit baseline and checked dates forward only after full reads

## Goal

The wiki audit agent, `auto_shaper_wiki`, saves work by re-reading only the pages that changed since its last audit. It knows where the last audit stopped from the `Audit baseline:` line in that audit's `log.md` entry, which records a git commit. The agent treats every page unchanged since that commit as already checked and skips it.

Today the audit writes the current commit as the new baseline at the end of every run, even when it read only a few pages. The next audit then skips every page that changed before that commit, including the pages nobody read. A page's `checked:` date in its frontmatter has the same problem. It gets a new date even when the page was only partly read, or when only some of its claims were checked.

After this task, both records claim only what actually happened:

- The audit moves the baseline to the current commit only when it read every page that changed since the previous baseline, each one in full. Otherwise it keeps the previous baseline, so the next audit reads the pages this run skipped.
- A page's `checked:` date changes only after the whole page was read and every claim on it was checked against its source. A partial read leaves the date as it was.

The rule is written once in the wiki skill, and the audit agent follows it where it writes these two records.

## Context

- **How the audit picks pages today.** In `plugins/knowledge_management/agents/auto_shaper_wiki.md`, the block `<derive_page_audit_working_set>` reads in full only the pages that are new or changed since the newest usable `Audit baseline:`. Its text says that a page "unchanged since it last passed a cold walk stays out" of the pages to read, where a cold walk means a fresh full read of the file. The block `<append_audit_log_entry>` writes a new baseline after every completed audit, with the instruction ``Prefer `git rev-parse HEAD` for the baseline when the wiki lives in a git worktree.``. Nothing ties the new baseline to what the run actually read. The entry's `Cold page reads:` line lists the pages the run read, but nothing defines what counts as a full read.
- **How the checked date is set today.** In `plugins/knowledge_management/skills/wiki/SKILL.md`, the **Freshness** bullet in `<write_or_update_pages>` says to set `checked` "when you verify the claims". It requires neither reading the whole page nor checking every claim. The agent keeps `checked` unchanged when it rewrites frontmatter in `<fix_frontmatter_missing_or_malformed>`, and nothing tells it when it may set a new date. The agent's `<read_canonical_references>` reads only named blocks of the wiki skill, and those leave out both the **Freshness** bullet and `<operational_discipline>`. A rule placed only in the wiki skill might therefore never reach the agent.
- **What went wrong in practice.** One audit, given a broad review request, fully read only a small share of a wiki in which every page had changed since the previous baseline. Half of the pages it listed under `Cold page reads:` it had only seen as search excerpts. It still recorded the current commit as the new baseline, so the next audit would have skipped every page this run never read. A helper script in the same run set a new `checked` date on every page it touched, including one it had read only in part.
- **Why keeping the previous baseline is the right fix.** The audit promises that every page gets one fresh full read after each change. Keeping the previous baseline after a partial run keeps that promise. The cost is that the next audit re-reads some pages the partial run already read.
- **Tests that pin today's wording.** `tests/wiki/layer1/agent_contract.py` checks that several phrases stay in the two agent blocks, among them `unchanged since it last passed a cold walk stays out`, `Audit baseline:`, `Cold page reads:`, `on every completed audit`, and `zero-change outcome entry`. Its `derive_cold_reads` function re-implements the page-selection rule over a small example, so the test can compare the agent's text with the expected behaviour.
- **Two other tasks change nearby text.** [The log rotation task](archive/wiki_log-rotation-and-retrieval.md) will say that the first audit after a log rotation records a fresh baseline. Under this task's rule that is true only when that audit reads every page in full, so the task that lands second rewrites its sentence to carry that condition. [The log consolidation task](wiki_log-session-entry-consolidation.md) keeps `<append_audit_log_entry>` and its baseline, but changes how the agent writes log entries inside that same block.

## Approach

1. **Write the rule once in the wiki skill.** Add one block to `<operational_discipline>` in the wiki skill, for example `<record_only_full_reads>`. It says that the audit baseline and a page's `checked` date move forward only over pages read in full during the same pass. A page counts as read in full only when the pass read every line of it, in one read or in several reads that together cover the whole file, as `<too_large_to_read_in_one_shot>` allows. Search hits, context excerpts, and partial line ranges do not count as reading the page.
2. **Rewrite the Freshness bullet.** Change the **Freshness** bullet so a writer sets `checked` only after reading the whole page and checking every claim on it against its source. A partial read, or a check of only some claims, leaves the date unchanged. The bullet points at the new block.
3. **Change how the audit writes its baseline.** Rewrite the baseline paragraph of `<append_audit_log_entry>` in place:
   - The baseline moves to the current commit only when the run read in full every page that changed since the previous baseline and still exists. On a first audit, which has no previous baseline, that means every page in the wiki.
   - Otherwise the new entry repeats the previous usable baseline unchanged, or writes `unavailable` when there is none.
   - `Cold page reads:` lists only pages read in full.

   Point at the wiki-skill block by its tag instead of repeating the rule. Keep the phrases the layer-1 test checks, or update a pinned phrase where the rewrite changes it, following TESTING.md's Test Integrity rules.
4. **Make the agent keep checked dates.** Add one clause to the agent's `<policy>`: the agent sets a new `checked` date only as the wiki-skill block allows, and otherwise keeps the date the page already has.
5. **Extend the layer-1 test.** In `tests/wiki/layer1/agent_contract.py`, pin the clause that keeps the previous baseline and the definition of a full read in `<append_audit_log_entry>`. Extend `derive_cold_reads` with the new baseline rule over a small example: the baseline moves forward after a complete read, stays after a partial read, and becomes `unavailable` when there was no previous baseline.
6. **Add three layer-2 scenarios.** Give them the next ids after the highest `AS-` id in `tests/wiki/layer2/evals.json`. Stage each with a `stage_<id>` function in `tests/wiki/layer2/setup_scenarios.sh`, and add each id to its `ALL_SCENARIOS` list. In each sandbox, the wiki sits in a git repository whose `log.md` holds one earlier `audit` entry, which records the first staging commit as its baseline. A second commit then changes one `concepts/` page and one `procedures/` page.
   - `auto-shaper-holds-baseline-on-scoped-audit`: the request limits the audit to the `procedures/` directory. The changed `concepts/` page stays unread, so the baseline must stay where it was.
   - `auto-shaper-advances-baseline-on-full-read`: the request asks for a full audit, so the baseline must move to the new commit.
   - `auto-shaper-holds-checked-on-partial-claim-check`: an entity page carries `checked: 2026-01-01`, several claims whose sources lie outside the sandbox, and one figure that contradicts a staged raw note. The request asks the audit to check that figure against the note and fix it. The figure must be fixed while the `checked` date stays the same, because the page's other claims were not checked.

   Write the graders under TESTING.md's `## Test Design Principles`, and run the scenarios under TESTING.md's vendor rule. One `glob_file_contains` assertion can use a regex backreference to compare the new entry's baseline with the staged one without hard-coding a commit hash.

**Out of scope:**

- Editing the `checked` paragraph of `references/template_schema.md`. That paragraph defines the field rather than when to set it, and changing the template would make every wiki's scaffold differ from it on the next audit.

## Acceptance

1. The wiki skill states the rule once, in the new `<operational_discipline>` block, naming both records and defining a full read. A search of the skill for that definition finds one statement.
2. The **Freshness** bullet requires reading the whole page and checking every claim before setting `checked`, and it points at the block. A search of the skill for `when you verify the claims` finds nothing.
3. `<append_audit_log_entry>` moves the baseline only under the full-read condition, and otherwise repeats the previous baseline or writes `unavailable`. The sentence ``Prefer `git rev-parse HEAD` for the baseline when the wiki lives in a git worktree.`` is replaced, so the block states one rule for when the baseline moves.
4. `Cold page reads:` is defined as pages read in full, and the agent's `<policy>` ties `checked` dates to the wiki-skill block.
5. `bash tests/wiki/run_all.sh` passes with the new layer-1 pins and the extended `derive_cold_reads` example. Each new pin fails when the clause that keeps the previous baseline is removed from the agent. This is shown once, and the clause is then restored.
6. `auto-shaper-holds-baseline-on-scoped-audit` passes: the run's new `audit` entry records the same `Audit baseline:` value as the staged earlier entry, and its `Cold page reads:` line names no `concepts/` page.
7. `auto-shaper-advances-baseline-on-full-read` passes: the run's new `audit` entry records a baseline different from the staged one.
8. `auto-shaper-holds-checked-on-partial-claim-check` passes: the figure on the entity page matches the raw note, and the page still carries `checked: 2026-01-01`.
9. Before the commit, a manual read of every changed shipped file and of this task's own diff finds no session, company, or project name, and no denylist is committed.
