---
title: Antigravity global configuration roots
created: 2026-08-09
updated: 2026-08-09
type: concept
tags: [antigravity, discovery, deployment]
sources: []
confidence: medium
---

# Antigravity global configuration roots

## Definition

[Google Antigravity](../entities/google-antigravity.md) ships as three products,
2.0, the IDE, and the CLI, and its global configuration does not sit in one place
for all of them. The divergence runs by **artefact class** rather than by product:
two classes split across the products and everything else converges on a single
root. That is what decides whether one global deploy reaches every product, and it
is the reason a deploy step here fans one artefact class out to three directories
while writing every other class once.

Facts here were verified in July 2026 against `antigravity.google/docs`
(`/skills`, `/ide/skills`, `/cli/plugins`, `/cli/settings`, `/hooks`). Re-verify
before relying on them.

## Current state of knowledge

### The two classes that diverge

**Skills split three ways.** `~/.gemini/config/skills/<skill-folder>/` on
`/docs/skills`, `~/.gemini/antigravity/skills/<skill-folder>/` on
`/docs/ide/skills`, and `~/.gemini/antigravity-cli/skills/` on `/docs/cli/plugins`.

**Plugins split two ways.** `~/.gemini/config/plugins/` for 2.0 and the IDE
against `~/.gemini/antigravity-cli/plugins/<plugin_name>/` for the CLI.

### Everything else converges

Agents, `hooks.json`, `mcp_config.json`, and `sidecars/` are single-rooted under
`~/.gemini/config/`. Global rules are the single file `~/.gemini/GEMINI.md`, one
level above `config/` rather than inside it, and the CLI keeps its own preferences
at `~/.gemini/antigravity-cli/settings.json`.

So the claim that one global deploy reaches the IDE, the CLI, and 2.0 is neither
true nor false as stated. It holds for agents, hooks, MCP, and sidecars, and it
fails for skills and plugins. A deploy that wants uniform reach writes the
converging classes once and fans the two diverging classes out per product, which
is what makes the question resolve per class rather than per product.

### Configuration roots are not output paths

A fourth tree exists and it is not a configuration root. Hook payload examples
show transcripts and artifacts landing under a `brain/<conversationId>/` subtree,
given as `~/.gemini/antigravity/brain/…` on the 2.0 page and
`~/.gemini/antigravity-ide/brain/…` on the IDE page. That is the only place an
`antigravity-ide` tree appears anywhere in the documentation, and reading it as a
place to deploy into would be a mistake.

## Open questions

Whether any single product reads more than one of the three skill roots is
undocumented, and it decides whether the fan-out is free or has a cost. If one
product does scan two of them, a fanned-out skill registers twice under the same
id. The copies a deploy writes are byte-identical, so the consequence would be a
confusing duplicate in a listing rather than divergent behaviour, but nothing in
the documentation confirms which way it goes.

## Related concepts

- [Google Antigravity](../entities/google-antigravity.md) for the harness itself,
  its workspace tree, and its hook contract.
- [The deployment model](deployment-model.md), which implements the per-class
  fan-out described here.
- [Foreign directory adoption](foreign-directory-adoption.md) for the workspace
  side of the same question, where Antigravity's native tree is read by two other
  harnesses.

## Derived from

- `antigravity.google/docs`, the pages named above.
- `deployment/README.md` in this repository, for the fan-out the deploy performs
  and the duplicate-registration caveat it records.
