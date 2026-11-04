---
description: Let wiki_fix hand its agent a user-approved list of confirmed findings as its scope, so auto_shaper_wiki checks each one again, fixes only those, and reports the outcome of each.
scope: plugins/knowledge_management/skills/wiki_fix
created: 2026-10-03T15:54:08
updated: 2026-11-04T11:49:57
status: open
reported-by: Andreas Hoffmann
---

# Let wiki_fix take a user-approved list of confirmed findings as its scope

## Goal

`wiki_fix` repairs a wiki by handing the work to the `auto_shaper_wiki` agent, the wiki family's own writer. The agent audits the wiki and fixes what it finds. Today `wiki_fix` lets the user narrow that work with a scope qualifier, such as one directory, but no rule names a list of findings. A user who already holds confirmed findings from another review has no way to hand that list to the writer.

After this task, a user who holds a list of confirmed wiki findings can hand it to `wiki_fix`, approve it, and get exactly those findings repaired by the writer:

- `wiki_fix` passes the list to `auto_shaper_wiki` as its scope.
- The agent reads each listed page in full and re-derives each finding before it edits. Re-deriving means checking the finding again against the page.
- Each finding ends fixed, refuted with the span of text that refutes it, or surfaced as a judgement call for the user.
- Every page the list does not name stays as it was. The report gives each listed finding its disposition, meaning which of those three outcomes it got.

The list may come from any review the user ran, including a review of an earlier scoped run's changes. The rule lives once, in the family's own files.

## Context

- **Current state.** `plugins/knowledge_management/skills/wiki_fix/SKILL.md` accepts a narrower scope only from the user. Its `<delegate>` rule hands the work to the agent. That rule forbids duplicating the agent's scope, re-listing its checks, or narrowing it "unless the user supplied an explicit narrower scope". Its `<pass_through_user_scope>` rule forwards a scope qualifier the user supplied, with examples such as "only the procedures directory". Neither rule names a list of findings. The agent's `<inputs>` in `plugins/knowledge_management/agents/auto_shaper_wiki.md` define no such input either.
- **What the agent does today.** `<derive_page_audit_working_set>` picks the cold-read set, the pages the agent reads in full this run, from evidence of which pages changed since the last audit. The page-first walk then takes those pages one at a time and runs every applicable check on each. `<remediation_contract>` applies every safe fix. It routes judgement calls to the contested-page protocol, which flags a page for the user to decide instead of guessing. `<relint_until_clean>` re-runs the linter and the fixes until the `<lint_clean>` criterion holds for the whole wiki. `<minimal_changes_per_fix>` already reports unrelated improvements as new findings instead of folding them into a fix.
- **The gap, observed.** A review pass outside the wiki family confirmed findings on a wiki's pages, and the user wanted the family writer to repair them. The family's rules offered no way to take that list. The run instead wrote a multi-lens review panel into the agent's brief. Such a panel is a set of review perspectives that each look for something different. That brief conflicts with the agent's `<page_first_iteration>` rule, which requires reading page by page and running every applicable check on each page. The agent read only a small part of the pages it was asked to review. A plan that sends confirmed findings to the writer as a narrower scope needs this change, because today's pass-through rule admits only a qualifier the user supplied.
- **Order.** Land after [the audit-baseline task](wiki_audit-baseline-after-full-reads.md). The audit baseline is the git commit that the agent's last audit recorded in `log.md`, and the next audit re-reads only the pages changed since that commit. That task's rule keeps an audit that reads only some of the changed pages from moving the baseline forward. A run scoped to a findings list reads only the listed pages. This task therefore adds no baseline clause of its own and relies on that rule.
- **Shared harness file.** [The wiki front-end evals task](tests_wiki-front-end-behavior-evals.md) also edits `tests/wiki/layer2/evals.json` and what the layer-2 runner captures from each run. Add this task's scenario as a new entry, so the two edits stay independent.

## Approach

1. **Name the findings list in `wiki_fix`.** Rewrite `<pass_through_user_scope>` in place so it covers two forms of user scope. The first is today's scope qualifier, with its examples. The second is a list of confirmed findings that the user supplied or approved in the request. Pass that list to the agent verbatim: by path when it is a file, and as given otherwise. When another skill or agent hands over a list without the user's approval, the list goes back to the user for approval before the agent runs. Keep `<delegate>` as it stands, since a list the user approved is the explicit narrower scope it already admits. Restate none of the agent's checks.
2. **Define the input once in the agent.** Rewrite `<inputs>` in `auto_shaper_wiki.md` to admit an optional confirmed-findings scope. Each entry names a page path, states the defect, and carries the evidence it rests on. That evidence is a quoted span of the page. For a finding about fidelity to a source, meaning whether the page says what its source says, the evidence adds the source path and span.
3. **Define the scoped run once.** Add one block to the agent, for example `<confirmed_findings_scope>`, that states how a run with that input differs from a full audit:
   - Orientation runs unchanged, including the SCHEMA read that the agent never skips.
   - The run pursues the listed findings, the lint carve-out below, and `<log_recorded>`, the objective that `log.md` records the audit. The other `<objective>` items, such as `<index_completeness>`, and the whole-wiki checks, such as `<scaffold_drift>` and `<raw_subtree_drift>`, belong to a full audit.
   - The listed pages replace the derived working set. The agent reads each one in full, together with every source span its entries cite.
   - The agent re-derives each entry against the page and its source before any edit. Each entry leaves with exactly one disposition: fixed with the matching fix move, refuted with the span that refutes it, or surfaced through the contested-page protocol. A fix move is the repair that the agent's check prescribes for that kind of defect.
   - A defect the agent notices outside the list is reported as a new finding and left unfixed.
   - The lint gate compares the final lint run with the run taken at the start of the assess phase. The run leaves no finding that its own edits introduced, and it reports pre-existing findings unfixed. The full-wiki criterion's existing exceptions survive the scoped run: the contested-page warns, the acknowledged insert-only locked-slot extensions, and the `log` rotation finding that `<fix_log_rotation>` clears. The report-only `citation` info findings stay report-only. Write this carve-out once in the block, and point `<lint_clean>` and `<relint_until_clean>` at it.
4. **Report each entry.** Extend `<report_changes>` and `<verify_output>`, the two blocks that define the agent's change report, so a scoped run lists every entry with its disposition. A refuted entry carries its refuting span, and the report names each new finding the run left unfixed. Keep the shape of `<final_line>`, the report's closing line. Add the per-entry dispositions to the list of what `wiki_fix`'s `<surface_report>` relays back to the user.
5. **Prove it on a staged wiki.** Add one layer-2 scenario, named for example `auto-shaper-fixes-approved-findings-only`, under the next id after the highest `AS-` id in `tests/wiki/layer2/evals.json`. Stage it with a `stage_<id>` function in `tests/wiki/layer2/setup_scenarios.sh`, and add the id to that script's `ALL_SCENARIOS` list. The staged sandbox holds these facts:
   - The sandbox wiki sits in a git repository, and its `log.md` holds one prior `audit` entry that records a baseline. Stage one initial commit after the wiki is staged, and record that commit's sha in the prior entry's `Audit baseline:` line, so the scenario has a real baseline to compare against.
   - A findings file outside the wiki lists two confirmed findings on two pages, plus one finding that its page already refutes.
   - A third page carries an off-taxonomy tag that the list does not name. An off-taxonomy tag is a tag outside the wiki's declared tag taxonomy.
   - The request asks `wiki_fix` to fix the approved findings in that file.

   Write the graders under TESTING.md's `## Test Design Principles`, and prove the scenario under TESTING.md's vendor rule.

## Acceptance

1. `<pass_through_user_scope>` in `plugins/knowledge_management/skills/wiki_fix/SKILL.md` names the confirmed-findings list as a form of user scope. It passes the list verbatim, by path for a file, and sends an unapproved list back to the user. Searching the file for the list form returns one statement. `<surface_report>` names the per-entry dispositions among what it relays, and the file still names none of the agent's checks.
2. `<inputs>` in `auto_shaper_wiki.md` admits the confirmed-findings scope with its three entry fields: the page path, the defect, and the evidence. One block states the scoped-run behaviour that **Define the scoped run once** lists, and searching the agent for that behaviour returns one canonical statement.
3. `<lint_clean>` and `<relint_until_clean>` point at the scoped lint carve-out instead of carrying a second copy. A run with no findings list keeps the full-wiki criterion unchanged, including the contested-page warns, the acknowledged insert-only locked-slot extensions, the `log` rotation finding, and the report-only `citation` findings. `<report_changes>` and `<verify_output>` carry the per-entry report, and `<final_line>` keeps its shape.
4. The new scenario passes on these sandbox facts:
   - Both confirmed findings are fixed on their pages.
   - The refuted entry's page is byte-identical to its staged copy. The grader checks this against a staging-time sha256 sidecar, a hash file written when the sandbox was staged.
   - The off-taxonomy tag still stands on the unlisted page.
   - The run's new `audit` entry records the same `Audit baseline:` value as the staged prior entry.
   - No file lands outside the sandbox, and the real home wiki stays absent.
5. The scenario's report fields name each listed entry with its disposition. The refuted entry reads `refuted`, and the off-taxonomy tag appears among the new findings left unfixed.
6. Every existing `AS-*` scenario whose request carries no findings list still passes, so full-scope audits keep their current behaviour.
7. Before the commit, a manual read of every changed shipped file and of this task's own diff finds no session, company, or project name, and no denylist is committed.
