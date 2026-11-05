---
description: "Register every discovered skill as a /name command, with collision skipping, discovery order, and a neutral default prompt instead of the skill body."
scope: harness-plugins/opencode_v2/slash-skill-autocomplete
created: 2026-11-05T20:33:23
updated: 2026-11-05T20:33:23
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Register skills as slash commands

## Goal

Each discovered skill appears in the `/` menu under its own ID, shows the
skill's description, and loads the skill with its reference files attached
rather than pasting `SKILL.md` into the prompt. A skill whose name would
collide with a command the host already exposes is skipped and reported.

## Context

The host lists commands, not skills, so a skill is reachable only by typing its
exact name. Closing that gap without changing the skill mechanism means
contributing one command per skill and having each command prompt the session
with the skill attached.

Two name sets compete for one namespace. The host owns a fixed set of built-in
command names, and the server may carry commands the user configured. Both are
reserved, and the built-in set is a constant while the server's set is runtime
data.

## Approach

Map each skill ID to a slash command of the same name, preserving discovery
order so the menu follows it. Build the reserved set from the built-in constant
plus the server's live command list, and skip any skill that collides with it,
carries an unusable ID, or repeats a name an earlier skill already claimed. The
first claimant wins, which keeps the result stable when one skill is reachable
through more than one discovery root.

Attach the skill through `skills: [{ id }]` on the session prompt. Use typed
text as the prompt when the user supplies it and a neutral directive when they
do not, because pasting the skill body is the behaviour the plugin exists to
avoid.

## Acceptance

- One slash command is registered per discovered skill, named after the skill
  ID, showing the skill's `description` when it has one.
- Text typed after the command becomes the prompt; with no text the prompt is a
  neutral directive and never the skill body.
- A skill colliding with a built-in name is skipped, not silently shadowed.
- A skill colliding with a server-configured command is skipped.
- The first of duplicate IDs wins and discovery order is preserved.
- An ID that would not parse as a command head is skipped.
- The skip reasons are reported in tests rather than at runtime, so the menu
  stays free of duplicates.
- `bun test` covers the mapping, the collision cases, the ordering rule, and the
  prompt fallback.
