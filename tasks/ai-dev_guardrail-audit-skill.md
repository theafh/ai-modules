---
description: Add a guardrail_audit skill to ai_dev that reports, read-only, contradictions and obvious gaps among a repo's guardrail docs and against its codebase, ranked CHARTER-first.
scope: plugins/ai_dev/skills
created: 2026-06-29T19:01:01
updated: 2026-06-29T19:12:17
status: open
reported-by: Andreas Hoffmann
---

# Add a guardrail_audit skill to ai_dev

## Goal

Add a new user-invoked `guardrail_audit` skill to the `ai_dev` plugin that reads a repository's guardrail documents and surfaces, read-only, the contradictions and obvious gaps among them and between them and the established codebase, with every finding ranked by a guardrail hierarchy: `CHARTER.md` at the top, the design-and-verification docs (`ARCHITECTURE.md`, `TESTING.md`, `FEATURES.md`, and peers) in the middle, and the harness operating-instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) at the bottom. The skill reports each finding with evidence and a reconcile recommendation and edits nothing — it surfaces conflicts for a human, never auto-resolves them. Its headline use case is reconciling a guardrail freshly adopted into a mature repository: it flags the pre-existing code and cross-doc violations a guardrail would have caught had it existed earlier, which the guardrail's own forward-looking enforcement structurally cannot reach. The skill ships at `version: 1.0.0`.

## Context

Guardrail documents and their precedence are already an established model in this repo, owned by the task family's standing-doc framework (see [standing-doc framework](archive/task-family_optional-standing-doc-conventions.md), finished): the optional root `UPPERCASE.md` docs, the graduated drift-prevention spectrum, and the presence-gated consumption convention where each doc read is gated on a portable `test -f "<root>/<DOC>.md"` with the root resolved from the base `task` skill's `<discover>` step. `guardrail_audit` reuses that discovery and presence-gate convention rather than inventing its own, and adds a new capability on top: assessing the guardrail layer itself for internal consistency and consistency with the code.

The hierarchy the skill ranks by is not new. This repo's `CHARTER.md` already codifies its top in the `## Key Invariants` section — "The charter is the highest-order guardrail. Softer standing documents (for example ARCHITECTURE.md, FEATURES.md, TESTING.md) stay subordinate to it ... Any conflict or drift between a softer standing document and the charter is resolved in the charter's favor and reported for human review." The skill operationalizes that stated precedence for the top two tiers and extends it with the user-directed placement of the harness operating-instruction files at the bottom. The general placement rule the skill applies to any guardrail doc: project identity and falsifiable boundaries outrank design-and-verification descriptions, which outrank instructions for how the agent operates.

`CHARTER.md`'s falsifiable structure — the `## Core Purpose`, `## DOES / DOES NOT Domain Boundaries`, `## Key Invariants`, and `## Intentional Constraints` sections — is defined by [charter contract](archive/task-family_charter-guardrail-for-autonomy.md) (finished); the skill keys its top-tier assessment on those four sections and treats the DOES NOT boundaries and the Key Invariants as the falsifiable claims it tests the other docs and the code against. That task also ships the protect hook that hard-blocks edits to `CHARTER.md`; `guardrail_audit` is the read-and-report complement to that fence, not a second enforcement mechanism.

This skill is distinct from the open [intent-drift detection](task-family_intent-drift-detection.md) task, which gives `task_check` a step comparing one task file's `## Goal` against its own committed git history. That is one task drifting from its own past intent; `guardrail_audit` compares guardrail docs against each other and against the current codebase — different artifact, different comparison, and a different edit surface (a new standalone skill, not a step inside `task_check`). Neither subsumes the other, and the skill should not re-implement task-self-history drift.

The skill is a standalone `ai_dev` skill, a sibling to the task family that consumes the same guardrail-doc substrate; it is not a member of the `task_*` family and is not added to that family's roster. It is the only entry point for its capability, so it keeps the ordinary domain-first name (`guardrail_audit`, matching `task_audit`) with no `_auto_` variant.

## Approach

Implement the skill as `plugins/ai_dev/skills/guardrail_audit/SKILL.md` at `version: 1.0.0`, following the standing repo rules for skill authoring — pseudo-XML structure, positive action-oriented prose, a dual-audience `description:`, snake_case naming, and deployment-agnostic cross-references — with this task supplying the guardrail-audit-specific behaviour. Register the new skill wherever the repo lists plugin skills, per the standing repo rules for adding a skill to an existing plugin.

Recognize the guardrail-doc set across three tiers, each read presence-gated with the root resolved from the base `task` skill's `<discover>` step, proceeding unchanged when a doc is absent:

- Tier 1 — `CHARTER.md`: the falsifiable project-identity contract, highest authority.
- Tier 2 — design and verification descriptions: `ARCHITECTURE.md`, `TESTING.md`, `FEATURES.md`, and peers.
- Tier 3 — harness operating instructions: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`.

Assess two axes and report findings ranked by tier and severity:

1. **Doc-vs-doc.** Compare the present guardrail docs against each other for contradictions (one doc permits or mandates what another forbids) and obvious gaps (a higher-tier doc declares a boundary or invariant a lower doc contradicts or omits). Resolve every conflict in the higher tier's favor — for a charter-vs-softer-doc conflict, in the charter's favor per the `## Key Invariants` rule cited above — naming the authoritative doc and flagging the subordinate one as the passage to reconcile.
2. **Doc-vs-code.** Compare the guardrail docs against the established codebase for places the code contradicts a doc. Center the retrofitting case: a guardrail adopted into a mature repo whose existing code already violates it — the violation the guardrail would have flagged had it existed earlier and that its forward-looking enforcement (the protect hook, task-content validation) cannot reach. Drive the scan from the falsifiable claims — the charter's DOES NOT boundaries and Key Invariants first, then the design and test docs' concrete assertions — and search the code for violations of each, so the assessment stays tractable on a large repo without narrowing what it can surface. This honors the charter Key Invariant that an autonomous component keeps its detection scope intact when it economizes.

Keep gap detection to obvious, high-confidence omissions — a stated boundary or invariant no sibling doc or code reflects — rather than exhaustive coverage analysis. The skill is read-only and surfaces, never auto-resolves: each finding carries the docs or code involved, verbatim-greppable evidence (a section heading, a quoted boundary, a symbol or path), the authority direction (which tier wins), and a reconcile recommendation, and the run edits no guardrail doc and no code. The human decides what to change.

Non-goals: editing or auto-resolving any guardrail doc or code; a second enforcement mechanism duplicating the charter protect hook; task-self-history drift detection (owned by the intent-drift task); exhaustive spec-to-code coverage auditing; and membership in the `task_*` family.

Adding a skill counts as a plugin edit, so the commit will bump ai_dev plugin meta in lockstep across both `plugin.json` files and both marketplace registrations per the repo's versioning rule — handled at commit time, not a step here.

## Acceptance

- A new `plugins/ai_dev/skills/guardrail_audit/SKILL.md` exists with frontmatter `name: guardrail_audit`, `version: 1.0.0`, and a dual-audience `description:` (a user-readable summary plus keyword-rich router triggers) distinct from sibling skills.
- The skill recognizes the three-tier guardrail-doc set — `CHARTER.md`; `ARCHITECTURE.md` / `TESTING.md` / `FEATURES.md` and peers; `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` — reads each presence-gated with the root resolved from the base `task` skill's `<discover>` step, and proceeds unchanged when a doc is absent. On a staged fixture exposing only `CHARTER.md` and `CLAUDE.md`, the run assesses exactly those two and raises no missing-doc error.
- On a staged fixture where a lower-tier doc contradicts a higher-tier one (e.g., `CLAUDE.md` mandates what the charter's `## DOES / DOES NOT` forbids), the doc-vs-doc axis surfaces the contradiction, names the higher-tier doc as authoritative, and flags the subordinate doc as the passage to reconcile, citing the charter `## Key Invariants` precedence rule for the charter-vs-softer-doc case.
- On a staged fixture where existing code violates a guardrail — the retrofitting case, e.g., the charter's DOES NOT forbids adding a second package manager and the staged repo already carries one — the doc-vs-code axis surfaces the pre-existing violation as one a guardrail would have flagged had it existed earlier, with verbatim evidence from both the doc passage and the offending code.
- The skill surfaces obvious, high-confidence gaps on both axes and does not perform exhaustive spec-to-code coverage analysis; that non-goal is stated in the skill body.
- The skill ranks findings by the hierarchy CHARTER.md → design/verification docs → harness operating-instruction files and resolves doc-vs-doc conflicts in the higher tier's favor; the skill body states that the top two tiers operationalize the charter's `## Key Invariants` precedence rule while the tier-3 placement of `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` extends it.
- The skill is read-only: a staged fixture run reports findings with evidence and reconcile recommendations and leaves every guardrail doc and every code file byte-for-byte unchanged.
- The skill is registered in the ai_dev plugin metadata (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`), both marketplace manifests (`.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`), `plugins/ai_dev/README.md`, and the root `README.md`, per the standing repo rules for adding a skill to an existing plugin; the new skill ships at `1.0.0`.
- A focused local eval under `tests/guardrail_audit/` (gitignored per the repo's test conventions) proves the doc-vs-doc charter-wins case, the doc-vs-code retrofitting case, the read-only report, and the hierarchy ranking; broader harness growth stays a separate session per the repo's keep-skill-change-and-harness-expansion-separate rule.
