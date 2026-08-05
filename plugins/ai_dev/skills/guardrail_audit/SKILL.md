---
name: guardrail_audit
description: Read-only audit of a repository's existing guardrail docs — surfaces doc-vs-doc contradictions and doc-vs-code divergences ranked by the guardrail hierarchy, plus grounded missing-doc proposals where repo substance warrants an absent doc. Edits nothing; every finding carries evidence and a reconcile recommendation, and the run ends by asking how to proceed. Use when auditing, health-checking, or retrofitting guardrail docs against each other and the codebase; when a freshly adopted CHARTER.md, ARCHITECTURE.md, TESTING.md, or SECURITY.md needs a divergence report; or when the user asks whether existing guardrails still match the code. For explaining, suggesting, or drafting guardrail docs, route to the guardrail hub.
version: 1.0.0
author: Andreas F. Hoffmann
license: MIT
---

# guardrail_audit

<guardrail_audit_skill>

<role>
guardrail_audit is the read-only audit sibling of the `guardrail` hub: it surfaces divergences among a repository's *existing* guardrail docs, and between those docs and the established codebase, ranked by the hub's hierarchy, and proposes grounded missing docs where repo substance plainly warrants an absent type. It edits nothing — every finding and proposal carries evidence and a reconcile recommendation, and the run ends by asking the user how to proceed. Its headline use case is retrofitting: a guardrail freshly adopted into a mature repository, where the audit flags the pre-existing divergences that forward-looking enforcement cannot reach.
</role>

<when_to_activate>
Activate when the user wants the repo's *existing* guardrail docs audited:

- "Audit the guardrails" / "do the guardrail docs still match the code?" / "health-check CHARTER.md against the repo."
- "Retrofit a charter into this mature repo — what already diverges?"
- "Are ARCHITECTURE.md / TESTING.md / SECURITY.md consistent with each other and with CLAUDE.md?"

Route to the `guardrail` hub when the user wants the system explained, a suggestion of which docs to adopt, or a draft of a new doc. Route to the `task` family for backlog work.
</when_to_activate>

<authority>
The `guardrail` hub skill's `SKILL.md` is the source of truth for the guardrail doc set, the three-tier hierarchy and authority rule, the shared format contract, the per-type references, project-root resolution and repo-nature reading (`<orient>`), grounded missing-doc suggestion (`<suggest>`), and the presence-gated consumption convention. Read the hub and its bundled `references/` at run time and apply those sections by citation — carry no second copy of the tier list, template skeleton, or consumption convention in this skill.
</authority>

<audit_bound>
Keep gap detection and missing-doc proposals to obvious, high-confidence cases. Exhaustive coverage analysis — every possible claim, every possible absent doc, every speculative mismatch — stays outside this skill's job. Prefer a short ranked list of clear findings over a long list of thin ones.
</audit_bound>

<workflow>
Run in order. Edit no guardrail doc and no code in the audited repository.

1. **Orient.** Run the hub's `<orient>` first: resolve the project root, read the repository's nature, and inventory which guardrail docs, peers, and harness rule files are present. Presence-gate every doc read per the hub's `<consumption>` — audit exactly the docs that exist, and raise no missing-doc error for an absent type.
2. **Doc-vs-doc.** Compare the present docs across all three tiers the hub's `<hierarchy>` defines — harness rule files included — for contradictions and obvious gaps. Name the higher-tier doc as authoritative and flag the subordinate passage as the one to reconcile.
3. **Doc-vs-code.** Compare the present docs against the established codebase. Drive the scan from the falsifiable claims — the charter's DOES NOT boundaries and Key Invariants first, then the tier-2 docs' concrete assertions — so the assessment stays tractable on a large repo. Present each divergence neutrally with both reconcile directions (bring the doc back to the code, or evolve the code toward the doc), because steering code toward where a guardrail points can be deliberate.
4. **Missing-doc proposals.** Where repo substance plainly warrants an absent doc, apply the hub's `<suggest>` flow with the audit's evidence: describe what the doc would capture, name nature mismatches instead of proposing an ill-fitting type, and create nothing.
5. **Report and ask.** Emit the ranked findings per `<output_contract>`, leave every audited file byte-for-byte unchanged, and ask the user how to proceed.
</workflow>

<finding_shape>
Every finding carries:

- the docs or code involved
- verbatim-greppable evidence from each side
- the authority direction per the hub's `<hierarchy>`
- a reconcile recommendation (for doc-vs-code: both directions)

Rank findings by the hub's hierarchy: charter conflicts first, then tier-2, then harness-file conflicts.
</finding_shape>

<output_contract>
Structure the report as:

- A short orientation lead: repo nature, inventory of present docs, and the audit bound in force.
- A `## Findings` section ranked by hierarchy. When clean, write exactly `No findings.` Otherwise list each finding with its evidence, authority direction, and reconcile recommendation.
- A `## Missing-doc proposals` section when the hub's `<suggest>` tests pass for an absent type; omit the section when nothing warrants a proposal, and name a nature mismatch instead of proposing an ill-fitting type.
- A closing question asking the user how to proceed — which findings to reconcile, which direction to take, whether to draft any proposed doc through the hub.

Edit nothing. The audited docs and code leave the run byte-for-byte unchanged.
</output_contract>

<family>
This skill is the read-only audit sibling in the `guardrail_*` family; the `guardrail` hub holds the shared rules and this skill wires them in:

- `guardrail` — the hub: explain, assess, suggest, and draft on request
- `guardrail_audit` — read-only audit of existing guardrail docs **(this skill)**

These ship together; a sibling may be absent if a deployment excluded it. The family is a sibling of the task family, not a member.
</family>

</guardrail_audit_skill>
