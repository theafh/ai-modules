---
description: Implement guardrail_audit as a slim read-only sibling wired into the guardrail hub: only the audit delta — doc-vs-doc, doc-vs-code, and grounded missing-doc findings, ranked by hierarchy.
scope: plugins/ai_dev/skills
created: 2026-06-29T19:01:01
updated: 2026-08-04T19:02:57
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Add a guardrail_audit sub-skill wired into the guardrail hub

## Goal

Add a user-invoked `guardrail_audit` skill to the `ai_dev` plugin as a slim sibling of the `guardrail` hub skill: a read-only audit that surfaces divergences among a repository's existing guardrail docs and between those docs and the established codebase, ranked by the hub's hierarchy, plus grounded proposals where repo substance plainly warrants an absent doc. The skill edits nothing — every finding and proposal is presented with evidence and a reconcile recommendation, and the run ends by asking the user how to proceed. Its headline use case is retrofitting: a guardrail freshly adopted into a mature repository, where the audit flags the pre-existing divergences that the guardrail's forward-looking enforcement structurally cannot reach. All definitional knowledge — the guardrail doc set, the three-tier hierarchy and authority rule, the per-type templates, repo-nature fit, and the presence-gated consumption convention — comes from the `guardrail` hub skill and its bundled references; this task implements only the audit delta on top. The skill ships at `version: 1.0.0`.

## Context

The `guardrail` hub skill (`plugins/ai_dev/skills/guardrail/SKILL.md`) is the family's source of truth: its `<doc_set>` and `<hierarchy>` sections define the recognized docs and the CHARTER.md → domain-guardrail → harness-file authority ranking, `<format_contract>` and the bundled `references/` files define each type's expected shape, `<orient>` defines project-root resolution and repo-nature reading, `<suggest>` defines grounded missing-doc suggestion, and `<consumption>` defines presence-gating and the surface-never-auto-resolve guard behaviours. `guardrail_audit` wires that hub in the way `task_check` wires the base `task` skill in — an `<authority>` block naming the hub as source of truth — and carries no copy of the definitional content.

The hub already names and routes to this sibling while the skill directory is still absent: `plugins/ai_dev/skills/guardrail/SKILL.md` frontmatter `description:` ends with the audit route, `<when_to_activate>` routes audit requests to `guardrail_audit`, and `<family>` lists `guardrail_audit` as the read-only sibling. The remaining gap is the missing `plugins/ai_dev/skills/guardrail_audit/` skill directory plus the registration surfaces that still omit the skill (plugin manifests, marketplace manifests, `plugins/ai_dev/README.md`, root `README.md`).

The audit is the read-and-report complement to the charter protect hook shipped by [charter guardrail](task-family_charter-guardrail-for-autonomy.md) (finished), not a second enforcement mechanism. It is also distinct from the archived [intent-drift detection](task-family_intent-drift-detection.md) work, which compares one task file's `## Goal` against its own git history: different artifact, different comparison, different edit surface — the skill leaves task-self-history drift alone.

The skill is a `guardrail_*` family member and a sibling of the task family, not a `task_*` member. It is the only entry point for its capability, so it keeps the ordinary family-first name (`guardrail_audit`, matching `task_audit`).

## Approach

Implement `plugins/ai_dev/skills/guardrail_audit/SKILL.md` per the standing repo rules for skill authoring, opening with an `<authority>` block that names the `guardrail` hub skill's `SKILL.md` as the source of truth for the doc set, hierarchy, format contract, orientation, and consumption convention — read the hub and its references at run time rather than restating them. Run the hub's `<orient>` first (project root, repo nature, doc inventory), then produce three kinds of finding, each ranked by the hub's hierarchy:

1. **Doc-vs-doc.** Compare the present guardrail docs — all three tiers, harness rule files included — for contradictions and obvious gaps. Name the higher-tier doc as authoritative per the hub's `<hierarchy>` and flag the subordinate passage as the one to reconcile.
2. **Doc-vs-code.** Compare the present docs against the established codebase, driving the scan from the falsifiable claims — the charter's DOES NOT boundaries and Key Invariants first, then the tier-2 docs' concrete assertions — so the assessment stays tractable on a large repo without narrowing what it can surface. Present each divergence neutrally with both reconcile directions (bring the doc back to the code, or evolve the code toward the doc), because steering code toward where a guardrail points can be deliberate.
3. **Missing-doc proposals.** Where repo substance plainly warrants an absent doc, apply the hub's `<suggest>` flow with the audit's evidence, describing what the doc would capture and creating nothing.

Keep gap detection and proposals to obvious, high-confidence cases rather than exhaustive coverage analysis, and state that non-goal in the skill body. Every finding carries the docs or code involved, verbatim-greppable evidence, the authority direction, and a reconcile recommendation; the run edits no doc and no code and ends by asking the user how to proceed. Leave the hub's frontmatter `description:`, `<when_to_activate>`, and `<family>` passages that already name and route to `guardrail_audit` intact — create `plugins/ai_dev/skills/guardrail_audit/` and register the skill only on the surfaces that still omit it (plugin manifests, marketplace manifests, `plugins/ai_dev/README.md`, root `README.md`), per the standing repo rules for adding a skill to an existing plugin.

**Out of scope:**

- Creating, editing, or auto-resolving any guardrail doc or code in the audited target repository during an audit run.
- Duplicating the hub's definitional content into the skill body.
- A second charter enforcement mechanism.
- Task-self-history drift detection.
- Exhaustive spec-to-code coverage auditing.
- Membership in the `task_*` family.

## Acceptance

- `plugins/ai_dev/skills/guardrail_audit/SKILL.md` exists with frontmatter `name: guardrail_audit`, `version: 1.0.0`, and a dual-audience `description:` distinct from the hub's — the audit entry point rather than the hub's explain/suggest/create surface.
- The skill body opens with an `<authority>` block naming the `guardrail` hub, and a read of the body finds no second copy of the hub's definitional content — no restated tier list, template skeleton, or consumption convention beyond citation.
- A read of `plugins/ai_dev/skills/guardrail_audit/SKILL.md` finds an explicit high-confidence / non-exhaustive audit bound: the body limits gap detection and missing-doc proposals to obvious high-confidence cases and states that non-goal (exhaustive coverage stays excluded).
- On a staged fixture exposing only `CHARTER.md` and `CLAUDE.md`, the run audits exactly those two and raises no missing-doc error (presence-gating per the hub).
- On a staged fixture where a lower-tier doc mandates what the charter's `## DOES / DOES NOT` forbids, the doc-vs-doc axis surfaces the contradiction with verbatim-greppable evidence from both the charter passage and the subordinate passage, names the charter as authoritative, and flags the subordinate passage as the one to reconcile.
- On a staged fixture where existing code diverges from a charter boundary (the retrofitting case), the doc-vs-code axis surfaces the divergence with verbatim evidence from both the doc passage and the diverging code, and presents both reconcile directions without assuming the code is wrong.
- On a staged fixture carrying a real test suite and no `TESTING.md`, the run proposes a grounded `TESTING.md` through the hub's `<suggest>` flow and creates no file; on a fixture whose nature makes a doc a bad fit — a mixed multi-project layout, or a knowledge-oriented repo — the run names the mismatch and proposes nothing ill-fitting.
- The skill is read-only: a fixture run reports findings ranked by the hub's hierarchy, ends by asking the user how to proceed, and leaves every guardrail doc and every code file byte-for-byte unchanged.
- The hub passages that already name and route to `guardrail_audit` — frontmatter `description:`, `<when_to_activate>`, and `<family>` in `plugins/ai_dev/skills/guardrail/SKILL.md` — remain unchanged and remain the single canonical hub forward; the work adds no second hub edit for the sibling.
- The skill is registered in the ai_dev plugin metadata (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`), both marketplace manifests, `plugins/ai_dev/README.md`, and the root `README.md`.
- A focused local eval under `tests/guardrail_audit/` (gitignored per the repo's test conventions) proves the fixture behaviours above.
