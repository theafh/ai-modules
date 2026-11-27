---
description: "Make auto_checker_spinner the default route for agent_spinner checking passes and keep a general helper from writing under a read-only brief."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-27T09:00:44Z
updated: 2026-11-27T09:00:44Z
status: open
reported-by: Andreas Hoffmann
---

# Route agent_spinner checking passes through the read-only checker role

## Goal

A checking pass spawns `auto_checker_spinner` by default, and a `general` helper briefed read-only cannot write. The run records which route each check used, so a check that ran on a general helper is a visible narrowing rather than an invisible one.

## Context

- `agent_spinner`'s `<degradation>` already says to spawn through `auto_checker_spinner` when the probe finds it, because a registered role can carry a host-enforced read-only lever that a generic spawn lacks. The sessions do not follow it: across the spinner runs in the sweep window, `general` accounted for 1,755 of 2,429 spawns, and only 15 of 80 runs used `auto_checker_spinner` at all.
- The consequence is a real containment breach, not a theoretical one. One wiki sweep dispatched its four verifiers as `general`; a verifier wrote to wiki pages despite a read-only brief, corrupted eight pages, and two later verifiers re-corrupted them with an auto-fixing lint run. The parent had to restore the pages from HEAD and rebuild the edit set.
- `auto_checker_spinner` is defined in `plugins/ai_dev/agents/auto_checker_spinner.md` with `edit` and `shell` denied. A `general` helper has no such lever, so its read-only status rests on the brief's prose.
- The skill's own `<capability_probe>` and `<degradation>` already distinguish a registered role from a generic spawn; the missing piece is the default and the record.

## Approach

1. Rewrite `<degradation>` in `SKILL.md` in place so a checking pass spawns `auto_checker_spinner` whenever the probe finds it, and a generic spawn is a named narrowing with its reason. Keep the inline-floor path unchanged.
2. Rewrite the checking template in `references/role-prompts.md` so its brief names the registered role and the read-only lever, and so a generic checker brief states that the lever is prose-only.
3. Record the route on the ledger row: add a `route` field (or an equivalent record) carrying `auto_checker_spinner`, `general`, or `inline`, and surface a `general` route in the run's report as a narrowing. Keep the ledger schema backward-compatible with rows that predate the field.
4. Add one eval or `ledger_run.sh` scenario in which a checker is spawned as `general` and attempts a write; the run must record the narrowing, and the write must be refused by the checker role when the role is used.
5. Add a static check to `tests/agent_spinner/script_tests/run.sh` that the checking template names the registered role and the read-only lever.

**Out of scope:** changing the `auto_checker_spinner` agent definition itself; its deny rules are already the correct lever.

## Acceptance

- A new scenario or eval spawns a checking pass and asserts that `auto_checker_spinner` is the route when the role is available, and that the roster or report records `general` as a narrowing when it is not.
- A checker spawned through `auto_checker_spinner` cannot write a file: the attempted write is refused, and the run records the refusal rather than a corrupted file.
- `rg -n "auto_checker_spinner" plugins/ai_dev/skills/agent_spinner/SKILL.md plugins/ai_dev/skills/agent_spinner/references/role-prompts.md` finds the default and the narrowing rule in both files.
- `bash tests/agent_spinner/script_tests/run.sh` and `bash tests/agent_spinner/script_tests/ledger_run.sh` pass.
