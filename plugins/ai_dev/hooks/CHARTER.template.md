# Project Charter

## Core Purpose

Define the durable reason this repository exists. State the product or system it
maintains, the users or operators it serves, and the kind of change that is
on-charter.

## DOES / DOES NOT Domain Boundaries

### DOES

- Define the work this repository owns.
- Name the artefacts, services, datasets, interfaces, or documents that belong
  inside the repository.
- Name the maintenance and verification work that supports those artefacts.

### DOES NOT

- Name neighboring products, services, domains, or workflows that this
  repository does not own.
- Name storage, deployment, dependency, or workflow classes that would move the
  repository outside its purpose.
- Name the authority boundary an autonomous agent uses when a proposed edit
  would expand the charter instead of serving it.

## Key Invariants

- List properties that must stay true after every change.
- Write each invariant so a reviewer can inspect a proposed change and decide
  whether the invariant still holds.
- Keep implementation preferences out unless violating them would break the
  repository's identity.

## Intentional Constraints

- List accepted tradeoffs, narrow tool choices, review gates, or portability
  requirements that shape how work happens here.
- Keep constraints falsifiable: a reviewer should be able to point at a change
  and say whether it complies.
- Treat changes to this charter as human-reviewed project-identity work.
