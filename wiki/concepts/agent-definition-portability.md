---
title: Agent definition portability
created: 2026-08-08
updated: 2026-08-09
type: concept
tags: [agent, frontmatter, portability, claude, codex, opencode, antigravity, verification-gap]
sources: []
confidence: medium
---

# Agent definition portability

## Definition

An agent or subagent definition is its own portability surface. Each harness
parses the file under its own schema, registers the role through its own
mechanism, and names its tools in its own vocabulary, so a definition that loads
on one target can fail silently on the next.

The design question is when one shared Markdown file can carry several
harnesses' native fields side by side, and when a target has to be reached
through a generated variant instead.

## Current state of knowledge

### Three tolerance categories, not two

Before sharing one file across targets, classify each one.

Ignore-unknown targets tolerate foreign keys.
[Claude](../entities/anthropic-claude-code.md) and
[Cursor](../entities/cursor.md) are both in this group, which is what makes the
union-of-native-fields pattern work at all.

Strict-schema targets reject a single unrecognised key and leave the agent
unloaded while the harness keeps running. No live target sits here today, which
matters: the category has to be defined on its own terms rather than through
whichever product last occupied it.

Pass-through targets are the third category and the reason two is not enough.
[OpenCode](../entities/sst-opencode.md) passes any unrecognised frontmatter
option directly to the provider as a model option, so a stray `version:` or
`effort:` is neither ignored nor rejected but injected into the provider call as
a bogus parameter. Like a strict target, it cannot safely read a shared
multi-harness file, but for the opposite reason.

[Antigravity](../entities/google-antigravity.md)'s tolerance is unconfirmed and
the evidence leans tolerant, so it is classified as pending verification rather
than as strict, and that pending state decides how aggressively its generated
variant filters keys.

### Tool vocabularies are disjoint

Claude's `tools:` takes a comma-separated string of capitalised names, and
omitting the field inherits every tool. Antigravity's `tools` is a YAML array of
lowercase snake_case names. One value cannot satisfy both, so a shared file
carries at most one harness's tools field and reaches the others through their
own.

Codex offers no per-agent allowlist at all. Cursor exposes no tools field, though
it has its own identifiers. OpenCode replaced its boolean tools map with a
`permission` object keyed by capability, and its own page carries the version
that boundary falls on.

The failure modes differ in severity, which is why a generator drops rather than
guesses. An unmapped name on Antigravity may hang the subagent process at
runtime rather than failing at load, and no canonical tool list is published to
validate against.

### Dropping happens at field granularity

A variant generator that meets a value it cannot map drops it rather than
emitting a guess. It drops at the granularity the field has: from a structured
allowlist it drops only the unmappable entry and keeps every name that mapped,
and it reserves the whole-field drop for a value carrying no per-entry structure.

Dropping a whole array also drops the enforcement its mapped names carried. On
Antigravity the `tools` array is half the read-only lever, so a whole-field drop
un-restricts exactly the agents that lever protects. When no entry maps at all
the field falls back to its own documented default, and that default's meaning is
per-harness rather than uniform: omitting Claude's `tools:` inherits every tool,
while Antigravity documents `tools` as defaulting to an empty array without
stating what an empty array grants.

### Read-only roles need native levers plus a body contract

Each harness has its own lever. Claude uses a `tools:` allowlist of read-only
tools. Cursor uses `readonly: true`. Codex uses `sandbox_mode = "read-only"` in
the generated TOML, with the caveat that its read-only semantics gate command
execution behind approval, so a role needing `git log` may pause for
confirmation. Antigravity needs both halves, a `tools` array holding only
read-only names and `commandExecutionPolicy` set to `off`, or to `sandbox` where
the role still needs contained execution. OpenCode uses a `permission` object
with `edit: deny`, plus `bash: deny` where no shell is needed, because its `edit`
key gates all file modification.

The prompt-level prohibition stays in the agent body as the universal floor.
Frontmatter enforcement binds only where the agent actually spawns as a separate
agent, while the body contract also governs harnesses that degrade the role to
inline execution.

### Inheritance by omission, and where a pin belongs

Omitting the model and effort keys lets a subagent inherit the spawning session's
settings, which works on both primary harnesses and keeps the user's session
setting as the single knob.

Codex expresses inheritance by key omission specifically. A shared source that
writes `model: inherit`, a sentinel Claude and Cursor understand natively and
Antigravity documents as its default, must have that sentinel translated to key
omission while generating the Codex TOML. Emitting `model = "inherit"` is invalid
output.

Where a role must run at a fixed depth, the pin is expressed as a union of native
keys: Claude reads frontmatter `effort`, the Codex TOML key is
`model_reasoning_effort`, and the two names are disjoint, so both sit side by
side in one Markdown file while a generated OpenCode variant strips both.

### Registration is verified, not inferred

A harness without the registered role usually keeps the orchestrating skill
working, because the main agent performs the role inline, where agent-file
enforcement never applies. Confirm registration on the target itself: the agent
directory, the installed plugin cache, and the spawnable-role list the harness
advertises. Write orchestrating skills so their policy survives inline
degradation rather than assuming a subagent boundary exists everywhere.

The sharpest case is Codex, whose plugin schema carries no agent component at
all, so a plugin-distributed agent reaches it only as generated TOML in an agent
directory.

### Deploy-time transforms are for format bridges only

A native plugin or marketplace install reads the raw file, so a deploy-only
convention such as a vendor-prefixed key takes effect only on machines where the
deploy ran and is invisible on every native install path. Reserve a generation
step for two situations: the target reads a different format entirely, which is
the Markdown to TOML bridge, or the target cannot safely read a shared
multi-harness file, which covers both the strict and the pass-through categories.

## Open questions

Antigravity's frontmatter tolerance is the open item that most changes the
design, because a tolerant loader would let the Google target read a shared file
while a strict one would not. It is also what sets this page's confidence: the
Claude, Cursor, Codex, and OpenCode classifications rest on documentation and
source, while the three-category model is only as sound as the one category
still assigned by inference.

## Related concepts

- [Foreign directory adoption](foreign-directory-adoption.md), which decides
  where a generated variant is written.
- [The deployment model](deployment-model.md), which implements the generators.

## Derived from

- Provider documentation for all six targets, verified July and August 2026 and
  cited on the per-harness entity pages.
- The `harness_portability` skill in this repository, before its August 2026
  split.
