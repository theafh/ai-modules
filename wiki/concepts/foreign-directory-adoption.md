---
title: Foreign directory adoption
created: 2026-08-08
updated: 2026-08-08
type: concept
tags: [discovery, portability, claude, opencode, copilot, cursor, antigravity]
sources: []
confidence: high
---

# Foreign directory adoption

## Definition

Foreign directory adoption is a harness loading components from another
harness's configuration directories. A skill, agent, or rules file deployed for
one tool then appears unbidden in another, carrying frontmatter keys, activation
flags, and conventions the reading harness does not implement.

The standing position here is that adoption is contamination to detect, not a
delivery channel. Every supported artefact is delivered as a per-harness variant
written into that harness's own native root. Relying on adoption is defensible
only as a deliberate, stated fallback for a harness with no native root for that
artefact class.

## Current state of knowledge

### Why adoption is the wrong delivery path

A harness that adopts a foreign file reads it happily and degrades it silently.
The foreign frontmatter is ignored, or worse, acted on: OpenCode passes
unrecognised agent frontmatter straight to the model provider as a bogus model
option. What arrives is a silently degraded artefact where a generated variant
would have delivered a correct one.

The failure has no error message. That is what makes mapping the roots worth the
effort: the leak has to be made visible before it can be switched off.

### Who adopts what

[SST OpenCode](../entities/sst-opencode.md) discovers skills from `.claude/skills/`
and `.agents/skills/` beside its own, both per project and globally, and resolves
rules by first match across `~/.config/opencode/AGENTS.md` then
`~/.claude/CLAUDE.md`. First match rather than accumulation is the sharp edge: a
global OpenCode rules file suppresses the user's `~/.claude/CLAUDE.md` instead of
sitting beside it. Agents and commands it takes only from its own tree.

[GitHub Copilot in VS Code](../entities/github-copilot-vs-code.md) reaches
further into the Claude tree than OpenCode does. With Agent Host enabled it reads
`~/.claude/rules`, finds `CLAUDE.md` at a workspace root, in a `.claude` folder,
or at `~/.claude/CLAUDE.md`, and loads custom agents from a workspace
`.claude/agents`.

[Cursor](../entities/cursor.md) reads agents from `.claude/agents/` and
`.codex/agents/` beside its own, and reads a project `CLAUDE.md` exactly as it
reads `AGENTS.md`.

[Google Antigravity](../entities/google-antigravity.md) looks like the opposite
case, by absence of evidence rather than by statement. No documentation page
reviewed in July 2026 mentions discovering artefacts from `.claude`, `.cursor`,
or `.codex`, and none documents a variable or key that would scope such
discovery. Plan on own-roots-only loading and confirm on the installed build.

Antigravity's own `.agents/skills/` is a converse case worth naming: it is that
harness's native root, and Codex project-level skill deployment and OpenCode
discovery both land there too, so one directory serves three harnesses and a
duplicate skill id resolves by whichever tool scans last.

### Isolation switches

OpenCode's switches are environment variables rather than configuration keys, and
they are listed on its own page. The broad one disables Claude Code compatibility
and, since v1.1.50, also stops `.agents/skills` discovery, which is a materially
different trade for an operator who also runs Antigravity, because it scopes away
that harness's native workspace skills in the same stroke.

No other target documents an equivalent switch. Where none exists, plan for the
foreign file arriving and keep the native variant authoritative.

### The worked case: output styles

Neither OpenCode's nor Copilot's adoption list includes `~/.claude/output-styles`,
so adoption would not carry a Claude style even if it were the chosen route. A
style file placed where either harness does read would arrive carrying
`keep-coding-instructions` and a frontmatter schema neither implements.

The conclusion the evidence reaches is the same one the principle reaches
independently: deposit a generated variant in each target's own tree, and disable
the adoption paths so the Claude originals stop competing with it.

## Open questions

Whether Antigravity's apparent isolation is real or merely undocumented is
untested on an installed build. Until someone checks, the claim rests on the
absence of documentation, which is the weakest evidence type in use here.

## Related concepts

- [The deployment model](deployment-model.md), which implements the
  native-root-per-target rule.
- [Agent definition portability](agent-definition-portability.md), where the same
  reasoning produces generated variants rather than one shared file.

## Derived from

- `opencode.ai/docs`, `code.visualstudio.com/docs/copilot/customization`,
  `cursor.com/docs/context/rules`, `antigravity.google/docs`.
- `packages/opencode/src/session/instruction.ts` on the `dev` branch of
  `github.com/sst/opencode`, 7 August 2026.
- The `harness_portability` skill in this repository, before its August 2026
  split.
