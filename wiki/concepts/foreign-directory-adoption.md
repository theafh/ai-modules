---
title: Foreign directory adoption
created: 2026-08-08
updated: 2026-08-09
type: concept
tags: [discovery, portability, claude, opencode, copilot, cursor, antigravity, verification-gap]
sources: []
confidence: medium
---

# Foreign directory adoption

## Definition

Foreign directory adoption is a harness loading components from another
harness's configuration directories. A skill, agent, or rules file deployed for
one tool then appears unbidden in another, carrying frontmatter keys, activation
flags, and conventions the reading harness does not implement.

The standing position here is that adoption is contamination to detect, not a
delivery channel. Every supported artefact is delivered as a per-harness variant
written into that harness's own native root, and where the reading harness
documents a switch, the deploy turns the adoption off rather than leaving it to
compete. Relying on adoption is defensible only as a deliberate, stated fallback
for a harness with no native root for that artefact class.

The reason is delivery quality rather than tidiness. A harness that reads
another's artefacts never implements them fully: it takes the file, ignores the
frontmatter keys it has no concept for, maps what it recognises onto its own
model, and silently drops the rest. What the user gets is a partial version of a
feature that works properly in the harness it was written for, with no error to
say so. Writing the native variant instead keeps the delivery under the deploy's
control and lets each harness receive the artefact in the shape it actually
implements.

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
further into the Claude tree than any other harness here, and it is the only one
that adopts executable policy rather than prose. With Agent Host enabled it reads
`~/.claude/rules`, finds `CLAUDE.md` at a workspace root, in a `.claude` folder,
or at `~/.claude/CLAUDE.md`, and loads custom agents from a workspace
`.claude/agents`. For hooks it reads `.claude/settings.json` and
`.claude/settings.local.json` at workspace scope and `~/.claude/settings.json` at
user scope, which is the same file a Claude hook deploy merges into.

That crosses the line the rest of this page is about. Adopting a rules file means
a second harness reads prose written for the first. Adopting a hook configuration
means a second harness **runs a command** that was wired for the first, under its
own event names, its own envelope, and its own blocking contract. Any Claude hook
deploy is therefore a two-harness deploy, and the shared policy script has to
expect a caller nobody deployed it to.

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

Two targets document a switch, and they take opposite shapes.

OpenCode's are environment variables rather than configuration keys, and they are
listed with their version boundaries on its own page. The broad one disables
Claude Code compatibility and also stops `.agents/skills` discovery, which is a
materially different trade for an operator who also runs Antigravity, because it
scopes away that harness's native workspace skills in the same stroke.

VS Code's are settings keys, and they are the finest-grained control in the set.
`chat.hookFilesLocations` and `chat.instructionsFilesLocations` each map a path to
a boolean, and a path set to `false` is disabled **including a documented
default**, so the Claude sources come off one at a time rather than as a block:
`.claude/settings.json` and `~/.claude/settings.json` for hooks,
`~/.claude/rules` for instructions. Because the granularity is per path, turning
off Claude adoption there costs nothing else, unlike OpenCode's broad switch. A
third key, `github.copilot.chat.claudeAgent.enabled`, is a different mechanism
worth not confusing with these: it governs running Claude as a harness inside VS
Code rather than reading Claude's files.

Cursor documents no equivalent switch, and Antigravity documents neither a switch
nor the adoption it would scope. Where none exists, plan for the foreign file
arriving and keep the native variant authoritative.

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
absence of documentation, which is the weakest evidence type in use here. That
single claim sets this page's confidence: the OpenCode, Copilot, and Cursor
sections rest on source reads and corroborating documentation, while the deploy
design leans on the Antigravity one, so the page is only as good as its weakest
load-bearing claim.

## Related concepts

- [The deployment model](deployment-model.md), which implements the
  native-root-per-target rule.
- [Agent definition portability](agent-definition-portability.md), where the same
  reasoning produces generated variants rather than one shared file.
- The per-harness switch-off steps, one page each:
  [OpenCode](../procedures/isolating-opencode-from-foreign-config.md),
  [VS Code](../procedures/isolating-vs-code-from-foreign-config.md), and
  [Cursor](../procedures/isolating-cursor-from-foreign-config.md).

## Derived from

- `opencode.ai/docs`, `code.visualstudio.com/docs/copilot/customization`,
  `cursor.com/docs/context/rules`, `antigravity.google/docs`.
- `packages/opencode/src/session/instruction.ts` on the `dev` branch of
  `github.com/sst/opencode`, 7 August 2026.
- The `harness_portability` skill in this repository, before its August 2026
  split.
