---
name: guardrail
description: Hub and source of truth for the repo-root guardrail documents (CHARTER.md, ARCHITECTURE.md, TESTING.md, SECURITY.md) that keep AI agents anchored to human intent while a project evolves within its declared boundaries. Explains the doc set, the authority hierarchy, the shared format, and how skills consult the docs, suggests which guardrails fit a repository, and drafts one only on explicit user request. Use when the user asks what guardrail docs are, which ones a repo should adopt, to suggest, bootstrap, set up, or draft a charter, architecture, testing, or security doc, how guardrail docs rank against each other or against CLAUDE.md, AGENTS.md, or GEMINI.md, or how agents consult and enforce these docs. For auditing existing guardrail docs against each other and the codebase, route to guardrail_audit.
version: 1.0.3
author: Andreas F. Hoffmann
license: MIT
---

# guardrail

<guardrail_skill>

<role>
The guardrail skill is the hub and source of truth of the `guardrail_*` family: it defines what guardrail documents are, which ones can exist, how they rank, what shape they share, and how other skills consume them. A guardrail document is a standing, human-owned markdown file at the project root that carries one domain of durable project truth an AI agent must respect or consult while working. Guardrail docs exist because unattended agents drift: a task to do X quietly becomes Y, and Y becomes Z, with no human in the loop. The guardrail layer is the human's standing voice at the moment of work: direction the agent reads and respects in every session, long after the conversation that set the direction is gone. Humans set direction through these docs; agents execute within the boundaries the docs declare and surface every conflict they meet. A guardrail bounds work; it never freezes it: the project adapts, grows, and is deliberately steered within its declared boundaries, and the docs themselves evolve with the project through their human-owned change path.

A guardrail doc carries rules, and a rule holds whether or not the code satisfies it yet. The doc states what must be true of this project, written as a general rule rather than a report on the current tree. Code that falls short of a rule is unmet work, never evidence that the rule is wrong, and softening a rule to match the code is the move the doc exists to prevent: the misreading an agent that treats a doc as a description of the present will make the moment the code disagrees with it. A rule becomes true along three paths: work filed and done to close the gap deliberately; new code written to the rule from the start; and **touch-it-and-fix-it**, existing code brought to the rule whenever ordinary work touches or rewrites it. The third path carries most of the distance, which is why a rule needs no migration plan attached to be worth stating.

The system is universal. It serves a single software system, a knowledge or content repository, a meta-repository whose product is components or documents, and a mixed multi-project layout alike, in any language and any stack. This skill carries only the general knowledge, the what and the how that hold everywhere; every actual guardrail doc is tailored to its repository, and a doc type that fits one repo nature can be a bad fit for another.
</role>

<when_to_activate>
Activate this skill when the user:

- Asks what guardrail documents are, which ones exist or could exist, or how the guardrail system works.
- Asks which guardrail docs their repository should adopt, or asks for a suggestion, recommendation, or assessment of guardrail coverage.
- Asks to set up, bootstrap, draft, or create a `CHARTER.md`, `ARCHITECTURE.md`, `TESTING.md`, `SECURITY.md`, or a guardrail layer as a whole.
- Asks how guardrail docs relate to or rank against each other or against the harness rule files (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` and equivalents).
- Asks how a skill, agent, or workflow should consult or enforce a guardrail doc.

Route to `guardrail_audit` when the user wants the repo's *existing* guardrail docs audited for contradictions and doc-vs-code divergence. Route to the `task` family for backlog work; the task skills consume guardrail docs but are not the place that defines them.
</when_to_activate>

<doc_set>
Four core guardrail types are recognized. Each has a bundled reference (sibling of this `SKILL.md`) carrying its general template, its universally valid rules, and its tailoring guidance. Read the reference before explaining, suggesting, drafting, or assessing a doc of that type:

- **`CHARTER.md`** is the falsifiable project-identity contract: core purpose, DOES / DOES NOT domain boundaries, key invariants, intentional constraints. The one doc that stops work rather than informing it. Reference: `references/charter.md`.
- **`ARCHITECTURE.md`** is the descriptive account of how the project is structured and where its structure is deliberately headed: goals, stack, components and their responsibilities, load-bearing design decisions, declared direction. Reference: `references/architecture.md`.
- **`TESTING.md`** is the project's verification methodology: what counts as tested, the discipline verification follows, and how the suite runs. Reference: `references/testing.md`.
- **`SECURITY.md`** states the security constraints that must hold: secrets, trust boundaries, data handling, dependencies, attack surface. Reference: `references/security.md`.

The set is open on two sides. Sideways, a repository may carry further domain guardrails as peers, following the same format contract and consumption convention; `FEATURES.md` as a behaviour ledger is an established example. Below, the harness rule files (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` and equivalents) are the project's standing-instruction baseline: they are owned by the harness convention rather than created through this family, and they enter the guardrail system only through the hierarchy, where they rank at the bottom. Whether a rule file loads is the harness's own behaviour and varies by product through activation mode, glob match, or manual mention, so this family rests on none of it: every guardrail doc reaches a workflow because a consuming skill looked it up at the stage that needed it, per `<consumption>`.

This family supplies the mechanism and never the content. Each doc carries the direction its own repository chose; a repository may adopt none of these docs and guard its work another way.
</doc_set>

<hierarchy>
Guardrail docs rank on one authority rule: **statements of what the project is outrank statements of how it is built and verified, which outrank instructions for how the agent operates.**

1. **Tier 1: identity.** `CHARTER.md`. The falsifiable boundary every other doc and every piece of work stays inside. A conflict between the charter and anything softer resolves in the charter's favor and is reported for human review; a softer doc never overrides the charter and never supplies the authority for work the charter would not bless.
2. **Tier 2: domain guardrails.** `ARCHITECTURE.md`, `TESTING.md`, `SECURITY.md`, and peers such as `FEATURES.md`: design-and-verification statements about the project.
3. **Tier 3: operating instructions.** The harness rule files. In day-to-day work they govern everything the guardrail docs are silent on; in a conflict over the same question they rank below the docs above.

Orthogonal to authority runs the **enforcement spectrum**, how strongly each doc guards:

- **Hard fence.** The charter: an agent about to produce or change project content validates the proposed work against its boundaries and invariants and stops on a violation, surfacing the conflict instead of proceeding. Where the charter protect hook is deployed, edits to the charter itself are additionally branch-gated (`guardrail/charter-*`), so an agent can never rewrite the contract to license its own drift.
- **Verified rule.** `TESTING.md` and `SECURITY.md`: consulted whenever work enters their domain; a divergence between the work and the doc is a finding the agent surfaces before claiming done, reported for the user to weigh and never silently passed, while the doc itself never halts the run.
- **Descriptive context.** `ARCHITECTURE.md` and `FEATURES.md`: they inform work and are refreshed as the project evolves; their guard value is truthfulness. That measure applies to present-tense description: a passage saying what stands that no longer matches the project, or that presents intention as fact, misleads every future agent. Two neighbouring kinds of claim are measured differently. A guarding statement states what must hold, so code that has not yet met it is unmet work rather than a descriptive falsehood. A declared target belongs to the register below, so an unreached target is read there as drive-toward work rather than here as a stale description.
- **Declared direction.** The `## Direction` section of `ARCHITECTURE.md`: a target shape the project is deliberately steered toward. The target holds as a standing commitment whether or not the code has reached it, so code short of the target is unmet work the next change drives toward, exactly as a guarding rule's shortfall is unmet work, and never a truthfulness defect that softening or deleting the target would repair. A target differs from a rule in what it asks: a rule states what must hold of every change, while a target names where the design is headed, so the section carries the target itself and no ledger of how much of it has shipped.

The hierarchy names the default authority direction; a human makes the actual call. Only the charter's hard fence stops work on its own. Every other conflict is surfaced with the authoritative doc named and the resolution left to the user.
</hierarchy>

<format_contract>
Every guardrail doc, of every type, honours the same format contract:

- **Root `UPPERCASE.md`, one domain per doc.** Project-wide standing material lives at the repository root as an `UPPERCASE.md` file; work-system material (for example the task backlog) lives in its own tree. The filename is the interface: consumers discover a doc by its presence, so no registry, index, or manifest is needed.
- **One canonical statement per rule within a doc.** Where a doc already owns the domain, new material rewrites the passage that owns the rule rather than landing beside it, so two statements of one rule never drift apart and a reader always knows which governs. This within-doc rule stands beside the across-doc filing rule above; they cover distinct situations.
- **Human-owned and evolving.** Agents draft and propose; humans approve. A guardrail doc is a living boundary, not a frozen snapshot: when the human's direction changes, the doc changes with it through its review path: the charter through its branch gate, the softer docs through ordinary review.
- **Falsifiable where it guards, truthful where it describes, a target where it declares direction.** The three registers carry different obligations. A guarding rule is normative: it is falsifiable in that a reviewer can check a concrete change against it, not in that the whole tree satisfies it today. Code short of a rule is unmet work rather than grounds to soften the rule, and a rule never carries a not-yet-met qualifier. A describing statement is factual and stays true to the repository, describing what stands as it stands, and it is there that intention presented as fact misleads, so a rule is stated plainly rather than folded into the account of the system's shape. A declared direction is stated as the target the code is driven toward: it stays as written while the tree falls short of it, rather than being softened to match the current tree, and it carries no per-item shipped-or-remaining ledger, because built and intended are told apart by which section a statement sits in rather than by a build-status marker hung on each item.
- **A guarding statement stays free of anything that goes stale.** Write each rule without a link or reference to a task, backlog item, or planned change; without a line number, code position, or other locator that rots as the file moves; and without a clause narrating what is unfinished today or marking the rule as not yet met. Each of those becomes wrong the second the code changes, and the rule itself does not. Where a rule needs to point at something in the repository, name it by a stable, greppable name.
- **Outcome-level and compact.** Guardrail docs state what must hold or what is. How-to mechanics stay out. Naming an enforcement mechanism stays in bounds; the dedicated mechanism-naming statement below owns that permission and what stays out of it. Agents read these docs constantly, so every line costs context in every session. Earn each one.
- **A guarding statement may name the mechanism meant to enforce it**, the check that must exist, the lint that must be denied, or the gate that must run, stated as part of the rule, since "Structural beats advisory" already prefers a constraint that holds by construction. Narration of whether that mechanism is wired today stays out; that is exactly the clause that goes stale.
- **Where a doc carries a change checklist or an equivalent per-change list, a newly added constraint gets an entry there too.**
- **A recognizable core, extendable per repo.** Each type's reference defines the core sections a consumer can rely on finding; a repository adds sections its domain needs. Extension is welcome; renaming or hollowing out the core is drift.
- **Tailored, never boilerplate.** The template supplies the skeleton; the repository supplies the substance. A guardrail doc that could be pasted into any other repo unchanged guards nothing; treat one as a finding, not a foundation.
</format_contract>

<consumption>
The consumption convention is presence-gating: a consuming skill or agent checks `test -f "<root>/<DOC>.md"` (POSIX-portable, root resolved from the consumer's own project-root discovery), reads the doc on a hit, and continues unchanged on a miss. Absence is never an error and never demands creation: a bare repository works exactly as before, and a project adopts guardrails only as it reaches for them.

The touchpoint rule (read-side): **a workflow consults the doc whose domain its work enters, at the moment it enters it.** Work about to write project content validates against `CHARTER.md` and stops on a violation. Work that writes or audits tests reads `TESTING.md` first. Work that touches a surface `SECURITY.md` names checks the change against the constraints that must hold. Work that needs design context reads `ARCHITECTURE.md`; work that ships behaviour refreshes the descriptive docs it invalidated. The task-management family is the established consuming instance: task creation reads `FEATURES.md` and `ARCHITECTURE.md` for prior art, the readiness gate and every autonomous writer validate against `CHARTER.md`, implementation and audit read `TESTING.md`, and close-out refreshes `ARCHITECTURE.md` when finished work extended the design.

The placement rule (write-side): **a rule is stated once, in the doc that owns its general form, and a narrower doc carries what the rule means for its own surface.** A rule discovered while working on one surface tends to get written into that surface's doc, which leaves every other surface it governs unguided. State the general form in the owning doc; let the narrower doc reference rather than restate; keep a rule that is not project identity out of the charter per the `<hierarchy>` authority rule.

Five guard behaviours hold at every touchpoint:

- **Surface, never auto-resolve.** A conflict between docs, or between a doc and the work, is reported with the authority direction named (per `<hierarchy>`); the human reconciles. On a guarding statement, name the code as the side to move and offer no softening of the rule, because code short of a rule is unmet work. On a declared direction target the code has not reached, report drive-toward work: name how the code moves toward the target, or how the target itself is revised deliberately, and offer no bringing the doc back to the repository to soften or delete the target. Keep both reconcile directions only for a present-tense descriptive conflict, where bringing the doc back to the repository is a legitimate fix.
- **Stop at the hard fence.** A charter violation halts the violating work itself, with the conflict surfaced and the target left unchanged.
- **Never widen a guardrail to legitimize an edit.** When work only becomes permissible after loosening a boundary, invariant, or constraint, the agent leaves the doc unchanged and surfaces the situation. Recording already-permitted work in a doc is maintenance; supplying the authority for the edit that introduces it is drift.
- **Bring touched code to the rule.** An agent that reads a doc at a touchpoint and finds the code it is about to change short of a rule brings that code up to the rule as part of the work, within the change's own scope, and surfaces anything larger rather than silently widening the edit. This is the third path made operational, and the counterpart of "Never widen a guardrail to legitimize an edit": that behaviour blocks moving the rule down to the code; this one moves the code up to the rule.
- **Steer work toward the declared direction.** Work shaped in a doc's domain moves the design toward the declared direction that doc carries, so each task filled, shaped, or implemented leaves the design closer to the target than it found it and the design does not silently degenerate across sessions. Work that would move the design away from a declared direction is surfaced before it is built, rather than the target being quietly redefined to fit what is about to be written. This is the direction counterpart of "Bring touched code to the rule": that behaviour moves code up to a rule it falls short of, while this one steers the shape of new work toward the target the project is headed for.
</consumption>

<workflows>

<orient>
Run first, for every request. Resolve the project root (git toplevel, else project markers, else the working directory). Read the repository's nature from its contents: a single software system, a knowledge or content repository, a meta-repository whose product is components or documents, or a mixed multi-project layout. Then inventory the root: which guardrail docs exist, which peers, which harness rule files. Nature decides fit: a single root `ARCHITECTURE.md` over several unrelated projects, or software-shaped guardrails over a knowledge base, is a mismatch this skill names instead of suggesting; in a multi-project layout the guardrail root can be the sub-project rather than the repository.
</orient>

<explain>
Answer questions about the guardrail system from this skill's body, and questions about one doc type from its bundled reference. Ground the answer in the repository at hand when one is present: name which docs exist here, where each sits in the hierarchy, and which consuming skills are installed.
</explain>

<suggest>
When the user wants guardrails to exist, asking "what should this repo have?", propose, per core type, only where two tests pass: the type **fits the repo's nature**, and the repo carries **substance that warrants it** (a real test suite or verification surface for `TESTING.md`; a single coherent system for `ARCHITECTURE.md`; secrets, untrusted input, published artefacts, or sensitive content for `SECURITY.md`; autonomous or recurring agent work worth fencing for `CHARTER.md`). For each suggested doc, describe concretely what it would capture in *this* repository, drawn from how the repo already works per the type's reference, and why it earns its keep; order the suggestions by the value they add, and name the types deliberately left out and why. This flow creates nothing: it ends by presenting the suggestions as decisions for the user.
</suggest>

<create>
Draft a guardrail doc only on the user's explicit go-ahead naming which doc(s) to create. Then, per doc, in dependency order (`CHARTER.md` first when it is in the chosen set, since identity anchors the rest):

1. **Honour the charter branch gate.** Before drafting `CHARTER.md`, switch to a `guardrail/charter-*` branch: where the protect hook is deployed the edit is blocked anywhere else, and where it is not, the branch still preserves the human-review path the charter contract expects.
2. **Ground the draft in the repository.** Read the code, docs, history, and conventions the doc will govern; extract the commitments and constraints the repo already reveals as outcome-level statements. Follow the type's reference for the template and rules.
3. **Mark gaps openly.** Fill what the repo and the conversation settle; mark what only the human can decide as `[UNDERSPECIFIED]` and ask one focused round of questions per doc rather than guessing. A doc is useful and consistent before it is complete.
4. **Surface creation-time divergence.** Where the repo already diverges from a boundary or constraint the user wants declared, write the rule plainly rather than marking it not-yet-met, name the code as the side that still has to catch up, and let the user confirm before the doc declares it. Softening the statement to match today's code is the move the doc exists to prevent.
5. **Hand over, human owns.** Report what was drafted, every `[UNDERSPECIFIED]` marker, and every surfaced divergence. The user reviews and commits; consumers pick the doc up by presence, so no wiring or registration step exists.
</create>

</workflows>

<output_contract>
A suggest run reports: the repo nature read in `<orient>`, the inventory of existing docs, each suggested doc with its grounding evidence and what it would capture, each type left out with the reason, and a closing question asking which the user wants, with no file created. A create run reports each drafted doc with its open markers and surfaced divergences, and leaves review and commit to the user. An explain run answers in compact prose and names the reference it drew from.
</output_contract>

<family>
This skill is the hub of the `guardrail_*` family and the single home of the family's shared rules, since the doc set, hierarchy, format contract, and consumption convention live here and in the bundled references; siblings wire this skill in rather than carrying copies:

- `guardrail`, the hub: explain, assess, suggest, and draft on request **(this skill)**
- `guardrail_audit`, read-only audit of a repo's existing guardrail docs: doc-vs-doc contradictions, doc-vs-code divergence, and grounded missing-doc proposals, ranked by the hierarchy

These ship together; a sibling may be absent if a deployment excluded it. The family is a sibling of the task family, not a member: task skills consume guardrail docs through `<consumption>`, while defining and maintaining the docs belongs here.
</family>

</guardrail_skill>
