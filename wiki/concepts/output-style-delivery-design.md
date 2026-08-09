---
title: Output style delivery design
created: 2026-08-08
updated: 2026-08-09
type: concept
tags: [output-style, deployment, portability, claude, codex, opencode, antigravity, cursor, copilot]
sources: []
confidence: high
---

# Output style delivery design

## Definition

This page records the design decisions behind delivering one authored style to
six harnesses from this repository, and the reasoning that produced each. It is
the decision record that sits under the six `deployment_output-style-*` backlog
tasks, so a later reader can tell which parts were argued and which were assumed.

The mechanism each harness offers is on
[system prompt substitution across harnesses](../comparisons/system-prompt-substitution-across-harnesses.md).
This page is about what the deploy actually writes, and why the source lives
where it does.

Decided 7 and 8 August 2026.

## Current state of knowledge

### The source is a repo-root `styles/` directory, deploy-only

Three candidate homes were considered and two were rejected.

A repo-root `.claude/output-styles/` is wrong on two counts. That path is project
scope for sessions working inside ai-modules, so it makes the style available to
agents editing the repository rather than to consumers, which is the
product-versus-workflow confusion the repo rules warn about. It is also invisible
to every install path except an in-place checkout.

A plugin-hosted `plugins/<plugin>/output-styles/` looked attractive because that
folder name is Claude's native plugin component and the deploy script's discovery
already resolves `plugins/<plugin>/<asset-folder>/`, so one source directory
would feed both delivery modes. One premise behind rejecting it was wrong and had
to be corrected first: the script writes into configuration trees regardless of
plugin enablement, so hosting the source in a plugin would not tie the deployed
global style to that plugin being loaded.

The real objection runs the other way. Hosting it in a plugin buys the plugin
channel whether or not it is wanted, because Claude auto-discovers
`output-styles/` at a plugin root. The result is two copies of the same style on
Claude: the deployed global one, and a plugin one namespaced `<plugin>:<style>`
that is availability-only, per project, and off under safe mode. A second, weaker,
differently named duplicate competing with the real one. Add that the Codex
plugin manifest has no `outputStyles` key, so it would be a Claude-only component
in a dual-manifest repository, and that a voice style is not scoped to any single
plugin's capability, and the plugin folder is the wrong home three times over.

So the source is a repo-root `styles/` directory, deploy-only, never registered
as a plugin component, using the neutral name rather than Claude's because the
plugin discovery is being avoided deliberately. The one real cost is that the
style arm becomes the deploy script's first non-plugin asset source, so
[discovery](deployment-model.md) grows a second root.

### What the deploy writes per target

| Target | Deploy writes | Activation | Shape |
| --- | --- | --- | --- |
| Claude | `~/.claude/output-styles/<name>.md`, verbatim | merge `outputStyle` into the settings file | file plus key |
| Copilot in VS Code | `~/.copilot/instructions/<name>.md`, body only | none, always on | file only |
| OpenCode | a file under the global config tree, body only | add its path to the `instructions` array | file plus key; route decision open |
| Codex | a generated instructions file under the Codex configuration tree, synthesized per the whole-prompt mechanism | merge `model_instructions_file` into the user configuration | file plus key, replacing |
| Antigravity | a marked block in `~/.gemini/GEMINI.md` | none | block in a user-owned file, under its rules-file character cap |
| Cursor | `.cursor/rules/<name>.mdc` with `alwaysApply: true` | none | project scope, global path unverified |

The Claude row is the only one built. It shipped on 8 August 2026 with the
`style` artefact type, the repo-root source directory, and the prior-value
restore, at both global and project scope. The other five rows stay per-target
backlog work, and each is a delivery decision rather than new machinery.

Two rows carry a caveat. The Codex row records the decided route: the
synthesized replacement won over a marked block in its global rules file, and
the Codex task lists that additive alternative as out of scope. The OpenCode row
records the initial lean rather than a decision, because its task still owns the
choice between this additive entry and the replacing agent-prompt route; the
project-scope rejection below applies to the replacing route either way.

### The marked block is the one new mechanism

Antigravity's global carrier is a single file the user owns,
`~/.gemini/GEMINI.md`. Writing it wholesale would destroy the user's own
content, so the deploy writes a delimited block inside it, between begin and end
markers, rewrites only that block on redeploy, and removes only that span on
uninstall. It is the Markdown counterpart of the JSON key merge the script
already performs for hook configuration, and it generalises: wherever a
harness's global carrier is one user-owned file rather than a directory, a
marked block is the safe write. Codex's `~/.codex/AGENTS.md` is the same shape
and would take the same block, but that additive route lost to the synthesized
replacement, so nothing writes it today.

### The content transform needs no new machinery

Claude receives the file verbatim, because it is the only target that parses the
frontmatter. Every other target receives the body with the frontmatter stripped,
which is what Claude itself does before injecting a style. The one sentence in
the style body that names `keep-coding-instructions`, a Claude-only concept,
becomes a placeholder variable substituted per tool through the existing
`replace:` rule in the deploy configuration.

Codex is the exception, and it is an exception in kind rather than degree. Its
`model_instructions_file` displaces the built-in instructions with no
keep-the-original flag, so its variant cannot be the body with the frontmatter
stripped. It has to be a larger document that also supplies the scoping, editing,
and verification guidance Codex would otherwise have contributed. Codex is
therefore the only target needing authored content rather than a transform, and
the work should be scoped as such.

### Selecting the active style lives in the deploy configuration

If the deploy always merges the `outputStyle` key, the arm has to know which
style is the default when the source directory holds more than one file. Claude's
frontmatter schema is strict at four keys and rejects a fifth outright, so a
`default:` marker cannot live in the style file without breaking the loader. The
marker goes into the deploy configuration instead, as a per-tool line naming the
active style, which reuses a file the script already parses and keeps the style
files portable.

### Both scopes come free, and two targets reject one of them

The script already resolves each tool's directory variable to the project tree
under project mode, so an arm written against that variable serves global and
project scope through one code path. A project-mode skip would be extra code
suppressing behaviour the path already provides.

Project scope is not a secondary mode everywhere. For Cursor, Antigravity, and
VS Code the project tree is the native home and the global side is the awkward
one, so for those three the real question is which scope is primary.

The whole-prompt replacing routes on Codex and OpenCode reject project scope, as
a judgement rather than a limitation. A committed whole-prompt replacement
changes the operating instructions for everyone who works in that repository
rather than for the person who deployed it, and the generated text is pinned to
one model and one harness version, so it is wrong for every contributor on a
different one. Codex adds a third reason: project layers load only for a trusted
project, so the placement would silently do nothing until trust is granted. On
OpenCode the rejection is scoped to the replacing route only, since the additive
`instructions` entry displaces nothing.

### Why Claude went first

Claude is not only the target where the mechanism works natively, it is also the
best target to build the shared machinery against, because it is the only one
with a two-part deploy. A file plus a settings key forces the key merge, the
prior-value capture, and the restore on uninstall to exist in the first task
rather than being retrofitted. Starting with a file-only target such as VS Code
would have built half the machinery and discovered the other half later.

That bet paid out as intended. The capture and restore landed on the shared
key-merge function rather than on a style-only wrapper, so the hook merges that
predate this work inherited the restore too, and the five remaining targets each
add a delivery route onto machinery that already exists. See
[the deployment model](deployment-model.md).

The per-harness split follows from the research rather than from a preference for
small tasks. Each harness carries its own unresolved decision: Cursor's
undocumented global rules directory, Codex's derivation and section-heading
fragility, OpenCode's default-agent override. Bundled into one task those are
several verification items hanging off a single piece of work; split per harness,
each is small and independently landable.

## Open questions

An early framing of this work held that a style setting
`keep-coding-instructions: true` is effectively additive, so every target's
additive channel reproduces it faithfully and only reach and injection position
vary. The two-layer finding recorded on
[Claude output styles](claude-output-styles.md) supersedes that: selecting a
style displaces the style layer whatever the flag says, and the flag governs the
engineering layer alone. Any plan still resting on the older framing understates
how much an append-only target loses.

## Related concepts

- [Claude output styles](claude-output-styles.md) for the native mechanism.
- [The deployment model](deployment-model.md) for the discovery and merge
  machinery this extends.

## Derived from

- Session discussion in this repository, 7 and 8 August 2026, in which the source
  directory, per-target delivery, marked-block mechanism, activation marker, and
  scope decisions were argued and settled.
- The six `deployment_output-style-*` task files in `tasks/`, which carry these
  decisions as work items.
