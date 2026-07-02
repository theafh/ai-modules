# CHARTER.md — general template and rules

The tier-1 identity guardrail: a falsifiable contract stating what the project is, what it does and does not do, and what must stay true after every change. It is the one guardrail doc that stops work rather than informing it — the hard fence of the enforcement spectrum. Its purpose is drift prevention at the root: it keeps an unattended agent from turning a task to do X into Y, and Y into Z, by giving every session a boundary the human set and the agent can test proposed work against. It fences purpose, not progress: humans set direction, including when and how the project grows, and work adapts and evolves freely within the boundary.

## Base template

```markdown
# <Project> Charter

## Core Purpose

<The durable reason this repository exists: the product, system, or corpus it
maintains, whom it serves, and the kind of change that is on-charter.>

## DOES / DOES NOT Domain Boundaries

### DOES

- <The work this repository owns.>
- <The artefacts, services, datasets, documents, or interfaces that belong here.>
- <The maintenance and verification work that supports them.>

### DOES NOT

- <Neighbouring products, domains, or workflows this repository stays out of.>
- <Storage, dependency, or workflow classes that would move it off purpose.>
- <The authority boundary: what an agent surfaces instead of deciding.>

## Key Invariants

- <Properties that must stay true after every change, each written so a
  reviewer can inspect a proposed change and say whether it still holds.>

## Intentional Constraints

- <Accepted tradeoffs, narrow tool choices, review gates, or portability
  requirements that deliberately shape how work happens here.>
```

Projects with a wide integration or commitment surface may add sections in the same spirit — `## Architectural Commitments` for non-negotiable structural decisions, `## Integration Contract Surface` for the defined set of external touchpoints — keeping every added item as falsifiable as the core.

## General rules

- **Every item is falsifiable.** A reviewer — human or agent — can point at a concrete change and decide whether the item permits it. "Be maintainable" fails this bar; "task state lives in plain repository files, never a database or remote service" passes it.
- **Outcome-level, identity-only.** The charter states what the project is and what must hold, and leaves implementation preferences to softer docs and the code — an implementation preference enters only when violating it would break the project's identity.
- **Compact.** Roughly 15–25 falsifiable items across the whole document is the healthy range, fewer when the project is genuinely simple. The charter is validated against constantly; every line costs context in every session.
- **Highest authority.** Softer standing documents stay subordinate: a conflict between the charter and any other doc resolves in the charter's favor and is reported for human review, and no softer doc supplies the authority for work the charter would not bless.
- **Never widened to legitimize an edit.** When a change only becomes on-charter after loosening a boundary or invariant, the charter stays unchanged and the situation is surfaced for a human. Humans widen charters; agents surface the wish.
- **Changes are human-reviewed project-identity work.** Charter edits happen on `guardrail/charter-*` branches. Where the charter protect hook is deployed, that gate is enforced mechanically — an edit anywhere else is blocked — and the initial draft is created on such a branch too.

## Tailoring

Purpose, boundaries, invariants, and constraints exist for every repository nature; only their substance changes. A software system fences its runtime, storage, and dependency classes. A knowledge repository fences its subject domain, source-of-truth rules, and what kinds of content it will never hold. A meta-repository whose product is components fences what counts as a publishable artefact and what its tooling floor is. A mixed multi-project layout usually charters each sub-project rather than the root. In every nature, the DOES NOT list and the invariants carry the guard value — they are the claims an agent can test work against.

## Consumption

Any skill or agent about to write or change project content validates the proposed work against the charter's boundaries and invariants and stops on a violation, surfacing the conflict and leaving the target unchanged. Read-only gates (readiness checks, audits) report charter conflicts as findings. The protect hook is the tamper fence for the charter file itself; validation at the write moment is what reading-and-respecting provides, and the two together close the loop.
