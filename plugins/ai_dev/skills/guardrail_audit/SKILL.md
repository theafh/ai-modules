---
name: guardrail_audit
description: Read-only audit of a repository's existing guardrail docs — surfaces doc-vs-doc contradictions and doc-vs-code divergences ranked by the guardrail hierarchy, plus grounded missing-doc proposals where repo substance warrants an absent doc. Edits nothing; every finding carries evidence and a reconcile recommendation, and the run ends by asking how to proceed. Use when auditing, health-checking, or retrofitting guardrail docs against each other and the codebase; when a freshly adopted CHARTER.md, ARCHITECTURE.md, TESTING.md, or SECURITY.md needs a divergence report; or when the user asks whether existing guardrails still match the code. For explaining, suggesting, or drafting guardrail docs, route to the guardrail hub.
version: 1.0.2
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

<normative_reading>
Read every statement that carries guarding force as a guarding statement, including a mixed sentence that both guards and describes — apply the hub's `<role>` and `<format_contract>` normative obligations whenever guarding force is present. Report code short of a rule as unmet work, name the code as the side to move, and propose no softening of the rule. Read a target in `ARCHITECTURE.md`'s `## Direction` in the declared-direction register the hub defines (its `<hierarchy>` spectrum, its `<format_contract>`, and its `<consumption>` "Steer work toward the declared direction" behaviour): a target the code has not reached is drive-toward work, reported by naming how the code moves toward the target or how the target is revised deliberately, and softening or deleting the target to match today's code is not among the directions offered. Keep the neutral both-directions presentation only for purely descriptive statements — present-tense description of what stands — where bringing the doc back to the repository is a legitimate fix per the hub's `<consumption>` "Surface, never auto-resolve" behaviour.
</normative_reading>

<workflow>
Run in order. Edit no guardrail doc and no code in the audited repository.

1. **Orient.** Run the hub's `<orient>` first: resolve the project root, read the repository's nature, and inventory which guardrail docs, peers, and harness rule files are present. Presence-gate every doc read per the hub's `<consumption>` — audit exactly the docs that exist, and raise no missing-doc error for an absent type.
2. **Doc-vs-doc.** Compare the present docs across all three tiers the hub's `<hierarchy>` defines — harness rule files included — for contradictions and obvious gaps. Name the higher-tier doc as authoritative and flag the subordinate passage as the one to reconcile.
3. **Doc-vs-code.** Compare the present docs against the established codebase. Drive the scan from the falsifiable claims — the charter's DOES NOT boundaries and Key Invariants first, then the tier-2 docs' concrete assertions — so the assessment stays tractable on a large repo. Apply `<normative_reading>`: for a guarding statement, report unmet work with the code named as the side to move and offer no softening of the rule; for a declared direction target the code has not reached, report drive-toward work naming how the code moves toward the target or how the target is revised deliberately, and offer no softening or deletion of the target; for a purely descriptive statement — present-tense description of what stands — present both reconcile directions (bring the doc back to the code, or evolve the code toward the doc).
4. **Format and coverage findings.** Within the `<audit_bound>`, also surface the three finding classes in `<finding_classes>` when the evidence is obvious and high-confidence.
5. **Missing-doc proposals.** Where repo substance plainly warrants an absent doc, apply the hub's `<suggest>` flow with the audit's evidence: describe what the doc would capture, name nature mismatches instead of proposing an ill-fitting type, and create nothing.
6. **Report and ask.** Emit the ranked findings per `<output_contract>`, leave every audited file byte-for-byte unchanged, and ask the user how to proceed.
</workflow>

<finding_classes>
Three targeted finding classes sit inside the `<audit_bound>` and cite the hub rather than restating it:

- **A guarding statement carrying stale-prone content.** A task or backlog link, a line number or code position, or a clause marking the rule as not yet met — content the hub's `<format_contract>` keeps out of a guarding statement. The fix rewrites the statement as a plain rule, since the qualifier goes stale while the rule does not.
- **A descriptive statement naming a technology, component, or convention the code does not use.** This is a finding on the describing half only; a rule the code has not reached draws no such finding, and neither does a `## Direction` target the code has not reached, which the hub's declared-direction register reads as drive-toward work. It misleads twice: it describes a stack the repository does not have, and an agent reading it will build to the named convention believing it matches existing practice. Evidence pairs the naming passage with the absence of any use in the code.
- **An empty or harness-locked tier-3 layer.** Where a repository carries no harness rule file, or its only operating rules sit in a harness-specific rules file that a single product loads, every other agent starts with nothing. Rank the finding below tier-2 findings per the hub's `<hierarchy>`.
</finding_classes>

<finding_shape>
Every finding carries:

- the docs or code involved
- verbatim-greppable evidence from each side
- the authority direction per the hub's `<hierarchy>`
- a reconcile recommendation — for a guarding doc-vs-code finding: unmet work with the code named as the side to move and no softening of the rule; for a declared direction target the code has not reached: drive-toward work naming how the code moves toward the target or how the target is revised deliberately, with no softening or deletion of the target to match today's code; for a purely descriptive doc-vs-code finding, scoped to present-tense description of what stands: both directions

Rank findings by the hub's hierarchy: charter conflicts first, then tier-2, then harness-file conflicts (including the empty-or-harness-locked tier-3 class below tier-2).
</finding_shape>

<output_contract>
Structure the report as:

- A short orientation lead: repo nature, inventory of present docs, and the audit bound in force.
- A `## Findings` section ranked by hierarchy. When clean, write exactly `No findings.` Otherwise list each finding with its evidence, authority direction, and reconcile recommendation.
- A `## Missing-doc proposals` section when the hub's `<suggest>` tests pass for an absent type; omit the section when nothing warrants a proposal, and name a nature mismatch instead of proposing an ill-fitting type.
- A closing question asking the user how to proceed. For present-tense descriptive findings, ask which direction to take. For guarding findings, ask how to evolve the code toward the rule, or park the finding — never offer softening the rule as a direction. For a declared direction finding, ask how to move the code toward the target, or whether to revise the target deliberately — never offer softening the target to the code. Also ask whether to draft any proposed doc through the hub.

Edit nothing. The audited docs and code leave the run byte-for-byte unchanged.
</output_contract>

<family>
This skill is the read-only audit sibling in the `guardrail_*` family; the `guardrail` hub holds the shared rules and this skill wires them in:

- `guardrail` — the hub: explain, assess, suggest, and draft on request
- `guardrail_audit` — read-only audit of existing guardrail docs **(this skill)**

These ship together; a sibling may be absent if a deployment excluded it. The family is a sibling of the task family, not a member.
</family>

</guardrail_audit_skill>
