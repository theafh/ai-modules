---
title: Antigravity tool vocabulary
created: 2026-08-09
updated: 2026-08-09
type: concept
tags: [antigravity, agent, hook, verification-gap]
sources: []
confidence: medium
---

# Antigravity tool vocabulary

## Definition

A [Google Antigravity](../entities/google-antigravity.md) subagent declares its
tools as a YAML array of lowercase snake_case names, and its hook matchers select
tools by the same kind of name. What makes the vocabulary worth its own page is
that no canonical list of those names is published anywhere, while a wrong name
fails at runtime rather than at load. There is nothing to validate against and
nothing that tells you validation failed.

Facts here were verified in July 2026 against `antigravity.google/docs/subagents`
and `/docs/hooks`. Re-verify before relying on them.

## Current state of knowledge

### Two surfaces publish names, and neither is complete

The subagents page names three: `view_file`, `grep_search`, and `run_command`.

The hooks page's matcher list adds seventeen more: `write_to_file`,
`replace_file_content`, `multi_replace_file_content`, `list_dir`, `find_by_name`,
`search_web`, `read_url_content`, `manage_task`, `schedule`, `list_permissions`,
`ask_permission`, `invoke_subagent`, `define_subagent`, `send_message`,
`manage_subagents`, `ask_question`, and `generate_image`.

Nothing in the documentation says these are different namespaces, so the working
assumption is that they are one vocabulary published in two incomplete places.
That assumption is untested, and it is the reason this page carries the
`verification-gap` tag.

Two names in wide circulation appear on neither page: `read_file` and
`edit_file`. Their absence is worth knowing precisely because they are the names
someone porting from another harness would reach for first.

### The failure mode is a hang, not a rejection

An unmapped or misspelled name may cause the subagent process to hang during
execution rather than fail validation at load. That is the detail to design
around, and it compounds with the missing canonical list: there is no registry to
check a name against beforehand, and no loud failure afterwards. A mistake
surfaces as a subagent that stops responding, which reads as a model problem
rather than a configuration one.

### What follows for anything generating a variant

The consequence for a generator is a rule rather than a fact, and it lives with
the other cross-harness agent rules in
[agent definition portability](agent-definition-portability.md): drop an
unmappable name rather than guessing at one, drop at field granularity so mapped
names survive, and remember that dropping Antigravity's whole `tools` array also
drops half of its read-only lever.

## Open questions

Whether the subagents page and the hooks page describe one namespace or two is
undocumented, and the answer changes what a generator may safely emit. Treating
them as one vocabulary is the current working assumption rather than a verified
fact.

Whether an empty `tools` array grants everything or nothing is also unstated. The
field documents `[]` as its default without saying what that default permits.

## Related concepts

- [Google Antigravity](../entities/google-antigravity.md) for the subagent
  frontmatter this field sits in, and for the hook matcher syntax.
- [Agent definition portability](agent-definition-portability.md) for how
  disjoint tool vocabularies across harnesses force a generated variant.
- [Hook surface portability](hook-surface-portability.md), since the matcher half
  of this vocabulary is part of Antigravity's hook contract.

## Derived from

- `antigravity.google/docs/subagents` and `/docs/hooks`.
- The `harness_portability` skill in this repository, before its August 2026
  split.
