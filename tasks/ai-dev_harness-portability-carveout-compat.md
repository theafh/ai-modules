---
description: Add to harness_portability a principle that harness-scoped carve-outs are a valid cross-harness-compat mechanism for skill behaviour, keyed on capability when a harness's capability changes.
scope: plugins/ai_dev/skills/harness_portability
created: 2026-06-30T19:33:12
updated: 2026-06-30T19:33:12
status: open
reported-by: Andreas Hoffmann
---

# State harness-scoped carve-outs as a cross-harness-compatibility mechanism in harness_portability

## Goal

The `harness_portability` skill teaches how to keep bundled runtime artefacts portable across agent harnesses and operating systems, but it states the carve-out pattern only for hooks. Add a stated principle that a **harness-scoped carve-out is a first-class cross-harness-compatibility mechanism for skill behaviour and prose**, not only for hook wiring: when one supported harness needs special attention — a missing tool, a different execution model, a divergent default — a rule scoped exclusively to that harness keeps every other harness's UX unchanged and prevents an error or degraded behaviour in the special harness, so the cross-harness UX stays roughly equivalent. Pair the principle with capability-keying guidance: when the harness property that triggers the carve-out is itself changing (a tool being added or removed across versions), key the carve-out on the underlying **capability** the agent actually has rather than on the harness identity, so the carve-out stays correct as the harness evolves.

The user-visible outcome: an author reading `harness_portability` finds an explicit, positively-framed rule that sanctions scoping a behaviour rule to the harness needing attention, and is told when to key it on capability instead of identity.

## Context

- The skill lives in `SKILL.md` under the `<harness_portability>` element. Its `<policy>` block already carries the design-for-the-running-harness rule, the use-official-provider-docs rule, and the provider-specific-configuration rules, and its `<hook_portability>` block special-cases Codex extensively (`<codex_hook_layers>`, `<codex_plugin_hooks>`, `<dual_harness_layout>`). What is missing is the general principle that a behaviour/prose rule may be scoped to a single harness as a sanctioned compatibility technique — the hook guidance demonstrates the pattern without naming it as a reusable principle for skill behaviour.
- Motivating instance (rides along as illustration, not as the content): the [git_commit consume-context task](ai-dev_git-commit-consume-context-contract.md) needed a shell-based read recipe because OpenAI Codex has historically had no dedicated file-reading tool and reads through the shell (`cat`/`sed`), while Claude, Cursor, and the other supported harnesses expose a Read tool. A Read-tool-only instruction errors on Codex; a harness/capability-scoped clause restores equivalent UX without changing the other harnesses' path.
- Capability-keying detail, also from that instance: recent Codex versions are adding a `read_file` tool, so a carve-out keyed on the Codex identity would go stale while one keyed on the capability ("this agent has no Read tool") stays correct as `read_file` rolls out. This is the concrete case the capability-keying guidance generalises.
- The principle reinforces the existing `<policy>` rule that says design for the harness that will run the skill, and the `<scope>`/`<target_harnesses>` framing; it does not contradict them.

## Approach

Author the principle once, positively framed, in the form the skill already uses (pseudo-XML, action-oriented prose), reusing the repo's standing authoring conventions for skill prompts.

- **Add the carve-out principle to `<policy>`.** Add one rule stating that an author may scope a behaviour or prose rule exclusively to the harness that needs special attention, so the other harnesses keep their shared path and UX while the special harness avoids an error or degraded behaviour — naming this as a sanctioned compatibility mechanism alongside the existing shared-path guidance.
- **Add the capability-keying guidance.** State that when the triggering harness property is changing across versions (a tool added or removed), the carve-out keys on the agent's actual capability rather than the harness identity, so it stays correct as the harness evolves; otherwise harness identity is acceptable.
- **Extend the review surface.** Add a `<review_checklist>` item that checks a harness-specific behaviour rule is scoped to the harness/capability that needs it and leaves the other harnesses' path unchanged, consistent with the new policy rule.
- **Keep scope to behaviour/prose carve-outs.** This task adds the general principle for skill behaviour and prose; it does not rewrite the existing `<hook_portability>` guidance, which remains the detailed treatment for hooks.

Non-goals: this task does not edit `git_commit` or any other consuming skill (the motivating instance is illustration only), and does not change the skill's OS-portability or hook-layering rules.

## Acceptance

- `harness_portability`'s `<policy>` states that a harness-scoped carve-out is a valid cross-harness-compatibility mechanism for skill behaviour and prose, framed positively (scope a rule to the harness needing attention; keep the others on the shared path), and the rule names both compatibility goals it serves: roughly equivalent cross-harness UX and error/degradation avoidance in a specific supported harness.
- The skill states the capability-keying guidance: when the triggering harness property is changing across versions, key the carve-out on the agent's capability rather than the harness identity.
- A `<review_checklist>` item verifies that a harness-specific behaviour rule is scoped to the harness/capability that needs it without altering the other harnesses' path.
- The added rule reads as a distinct, single statement of the behaviour/prose carve-out principle and does not duplicate or contradict the existing `<hook_portability>` guidance or the existing design-for-the-running-harness `<policy>` rule.
