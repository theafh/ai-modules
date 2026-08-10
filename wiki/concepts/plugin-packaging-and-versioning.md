---
title: Plugin packaging and versioning
created: 2026-08-08
updated: 2026-08-10
type: concept
tags: [plugin, versioning, repo-structure, claude, codex]
sources: []
confidence: high
---

# Plugin packaging and versioning

## Definition

A plugin is the unit of distribution in this repository. Everything an agent
needs at runtime lives inside `plugins/<plugin>/`, and anything placed outside
that tree is invisible to every installation path except an in-place checkout of
the repository itself. That single fact drives most of the packaging rules
below, including the one that keeps a skill's helper scripts inside the skill
directory rather than at the repository root.

Each plugin carries two manifests for the same content. `.claude-plugin/plugin.json`
describes it to Claude, and `.codex-plugin/plugin.json` describes it to Codex,
where the skills entry points at `./skills/`. Two marketplace files register the
same plugins a second time, one per harness. A plugin is therefore described in
four places, and the four have to agree.

## Current state of knowledge

### Why two manifests rather than one

The manifests are not redundant, because the two harnesses read different
component sets from them. Claude reads bundled agents, hooks, MCP servers, and
output styles from a plugin. Codex reads skills, MCP servers, and hooks, and its
schema carries no agent component at all, which is why an agent shipped inside a
plugin never becomes a spawnable role on Codex. The consequence for a plugin
author is covered in
[agent definition portability](agent-definition-portability.md): reaching Codex
with an agent requires a generated TOML file in its own agent directory, and no
manifest edit will substitute for it.

### The versioning contract

Five rules govern versions, and they exist to make the git history readable
rather than to satisfy a package manager.

A new skill, agent, or plugin ships at 1.0.0, with no bump in the commit that
introduces it. An edit to an existing artefact raises its version in the same
commit as the edit, once, and only at commit time. Iterating on a file across
several turns does not earn several bumps, and a task file or plan that
schedules a version bump as a step is writing down something the commit already
handles.

Small maintenance edits take a patch increment. Adding a skill or an agent to an
existing plugin advances that plugin's minor component while the new artefact
itself still ships at 1.0.0.

Plugin metadata moves in lockstep. When any skill or agent version rises, or a
new one is added, both `plugin.json` files and both marketplace registrations
rise to the same new plugin version in the same commit. Four files, one number.

The rule is machine-checkable, and `skill_doctor` reads it as a version check
across those four files. Encoding it settled an ambiguity the prose had left open.
The four have to agree with each other, while a skill's own `version:` is free to
differ from the plugin version that carries it, because the two numbers count
different things: a skill's edit history against its plugin's. A mismatch between
those two is therefore the normal state rather than a finding.

### Where the cost of getting it wrong lands

A version that does not move is a silent failure rather than a loud one. The
installed copy on another machine keeps whatever it fetched, and the mismatch
surfaces later as behaviour that does not match the source. This is the same
class of problem as the stale plugin cache on Codex, described in
[OpenAI Codex](../entities/openai-codex.md), where restarting the harness is not
enough to pick up an edited plugin.

### Marketplace installation is not the only path

Installation can also happen through the deploy script, which copies artefacts
into each harness's own configuration tree. The two paths differ in what they
can reach, and the difference matters most for anything that needs a settings
key written rather than a file copied. That asymmetry is the subject of
[the deployment model](deployment-model.md) and, for one worked case, of
[Claude output styles](claude-output-styles.md).

## Open questions

Two distribution options exist side by side, and which one a given machine uses
is that machine's choice rather than a property of the repository. A marketplace
install reads the manifests and delivers the components each harness's plugin
schema declares. A deploy run copies artefacts into the configuration trees
directly and reaches settings keys no manifest can write. Whether the two stay
equal channels, or one becomes the documented default, is unsettled.

## Related concepts

- [Skill family architecture](skill-family-architecture.md) for how the
  components inside a plugin are named and organised.
- [The ai-modules repository](../summaries/ai-modules-repository.md) for the
  wider layout.

## Derived from

- `CLAUDE.md` and `AGENTS.md` at this repository root, sections on versioning,
  layout, and authoring conventions.
- The four manifest and marketplace files themselves.
