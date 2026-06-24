---
description: Establish the optional root UPPERCASE.md doc convention: document the tasks-vs-root filing rule, define ARCHITECTURE.md as an optional descriptive doc, and document the tiered adoption model.
scope: plugins/ai_dev
created: 2026-06-21T15:17:35
updated: 2026-06-24T18:45:14
status: checked
reported-by: Andreas Hoffmann
---

# Optional standing-doc conventions for the task family

## Goal

Define how the task family optionally recognizes standing project documents at the repo root, without adding any required ceremony. Three deliverables land together: the filing convention that separates task-system material under `tasks/` from project-wide material at the root, an optional `ARCHITECTURE.md` as a descriptive project doc detached from the task lifecycle and distinct from the falsifiable intent guardrail, and the family's tiered adoption model that makes the optional tiers and their dependencies discoverable. All three are opt-in, so a bare task repo with no root docs keeps working exactly as it does today, and a project adopts richness only as it reaches for it.

## Context

The filing rule the family adopts: material that is directly about the task system lives under `tasks/`, and material that is about the project as a whole lives at the repo root as an `UPPERCASE.md` document. The other root docs governed by this same convention are defined in sibling tasks — the project identity contract in [intent guardrail](task-family_intent-guardrail-for-autonomy.md), the behaviour ledger in [feature-ledger behavior record](feature-ledger_behavior-record-skill.md), and the test methodology in [optional testing discipline](task-family_optional-testing-discipline.md) — so the convention defined here stays consistent with where those land.

The architecture question settled here: `ARCHITECTURE.md` is an optional, actively-maintained descriptive document — goals, stack, and design decisions — kept deliberately distinct from the intent contract, because the two sit at different altitudes. The intent contract is a falsifiable guardrail checked against diffs; the architecture doc is explanatory narrative read to understand the system. It is therefore not folded into the intent doc, and it must not regress into a status-board or stage index — that ordering role is served by `task_select` and the optional regenerated build-order view, so the architecture doc stays a description and can be omitted entirely.

The tiered adoption model this task documents: the plain task chain by default, then the optional autonomous readiness loop, the autonomous layer with its coupled intent guardrail, and the optional standing docs (architecture here, intent, the behaviour ledger, and test methodology in their own tasks) — each adopted step by step so users take on richness only as they need it.

## Approach

Document the filing convention (task-system material under `tasks/`, project-wide material as root `UPPERCASE.md`) in the base `task` skill prose — the family's standing documentation — as the single statement of the rule, keeping it skill-based and deployment-agnostic rather than tied to any one repo's README. Document `ARCHITECTURE.md` as an optional descriptive convention, explicitly contrasted with both the intent contract (falsifiable guardrail) and any index/status-board role (which it must not take on). Document the tiered adoption model so the optional tiers and their dependencies are discoverable. Hold the line that none of these become a hard requirement: the default experience is unchanged.

Non-goal: making architecture or any root doc mandatory, and re-introducing a maintained global index/status board. The test methodology doc and its wiring are owned by the sibling testing task, not this one.

## Acceptance

- The filing convention (task-system material under `tasks/`, project-wide material as root `UPPERCASE.md`) is documented once in the base `task` skill prose.
- `ARCHITECTURE.md` is documented as an optional descriptive doc, explicitly distinct from the intent contract and explicitly not a status-board or stage index.
- The tiered adoption model (plain chain → optional review → autonomous layer plus intent guardrail → optional standing docs) is documented so each tier and its prerequisites are discoverable.
