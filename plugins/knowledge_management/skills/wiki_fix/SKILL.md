---
name: wiki_fix
description: Audit and autonomously fix every issue in the wiki by invoking the `auto_shaper_wiki` agent. The issues it covers are structure, content, splits, links, tags, scaffold drift, and cross-page contradictions. Use when the user asks to fix, repair, lint, audit, health-check, clean up, or auto-repair their wiki.
version: 1.1.4
author: Andreas F. Hoffmann
license: MIT
---

# wiki_fix

<wiki_fix>
  <role>Front end for the `auto_shaper_wiki` agent. Hand the audit-and-fix loop off to the agent and surface its report to the user.</role>
  <authority>The `wiki` skill's `SKILL.md` is the source of truth for the shared family rules this front end inherits: wiki structure, discovery, orientation, ingest, and lint. It states each of those rules once, so cite its blocks by tag rather than restating them. The audit run itself is delegated: `<delegate>` names the execution delegate and the phases it owns.</authority>
  <orient_first_top>**The `auto_shaper_wiki` agent reads `$WIKI/SCHEMA.md` once at the start of every audit it runs.** This skill itself does no orientation and delegates immediately, but the SCHEMA read inside the agent is non-skippable. The agent's `<orient_first_top>` enforces it.</orient_first_top>
  <objective>Run the agent against the wiki of the current repository so it audits end to end and autonomously fixes every issue it finds.</objective>
  <policy>
    <delegate>Invoke the `auto_shaper_wiki` agent. The agent owns wiki discovery, orientation, assess, remediate, and verify phases. Do not duplicate its scope, re-list its checks, or narrow it unless the user supplied an explicit narrower scope.</delegate>
    <pass_through_user_scope>When the user supplied an additional scope qualifier (e.g., "only the procedures directory", "skip the scaffold check"), pass it to the agent as an extra instruction. Otherwise hand the agent its default full-wiki scope.</pass_through_user_scope>
    <surface_report>Pass the agent's final report back to the user verbatim: the per-file change list, the final lint outcome, and any contested or contradicting pages flagged for human review.</surface_report>
  </policy>
  <steps>
    <step>Invoke the `auto_shaper_wiki` agent, forwarding any narrower scope the user supplied.</step>
    <step>Return the agent's final report to the user.</step>
  </steps>
  <output_contract>
    <final>The agent's own final report: assess output, per-file change list, final lint outcome, and the `audit complete — N issues resolved, K contested pages flagged` line.</final>
  </output_contract>
</wiki_fix>
