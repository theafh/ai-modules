---
title: The deployment model
created: 2026-08-08
updated: 2026-10-29
type: concept
tags: [deployment, plugin, discovery, repo-structure]
sources: []
confidence: high
---

# The deployment model

## Definition

`deployment/deployment.sh` copies this repository's artefacts into the
configuration trees of six harnesses: VS Code Copilot, Cursor, Claude Code,
OpenAI Codex, Google Antigravity, and OpenCode. It runs in one of two scopes.
Global mode writes into the user configuration directories, and project mode
writes into a single project's own local configuration instead. The script
records every path it wrote into `deployment/deployed_artefacts.log`, and
uninstall replays that log: a scope flag limits removal to the scope it names,
while a scopeless run covers every scope.

The script exists because a marketplace install cannot reach everything. A
plugin manifest delivers components, but it never writes a settings key and it
never reaches a harness whose plugin schema lacks the component type. Deployment
is the path that does.

## Current state of knowledge

### Discovery has two roots

Most artefacts live under `plugins/<plugin>/<asset-folder>/`, and the folder name
selects the type: `agents/` and `commands/` take each top-level Markdown file,
`skills/` takes each immediate subdirectory containing a `SKILL.md`, and
`hooks/` takes each top-level shell or JSON file. Hidden files and README files
are skipped. The script walks up from its own location until it finds a
directory containing `plugins/`, so it does not care where in the tree it sits.

One of those types is retained rather than used. The charter treats a standalone
command as a legacy, deprecated mechanism, so new work exposes a user-invocable
entry point as a thin skill instead, even where that skill only wraps an agent or
a workflow. No plugin ships a `commands/` folder, so the type is live code over an
empty source. The instruction files pin the word down, since "command" otherwise
reads as a shell command or any slash-invocable skill, which makes the deprecation
sound broader than it is.

The second root is repo-root `styles/`, where each top-level Markdown file is one
artefact of the `style` type. It is the first
asset source outside the plugin tree, which made it a structural change rather
than a configuration one, and it is why the type name and the discovery root
were settled before the first deploy wrote either of them into the log. Why the
source sits outside `plugins/` at all is on
[output style delivery design](output-style-delivery-design.md).

### Per-tool configuration

`deployment/deployment.conf` is parsed in robots.txt style: a `#tool` section
heading, then `disallow:` lines that skip a repo-relative path for that tool,
`replace:` lines that substitute a variable inside deployed copies, and a
`style:<name>` line naming which style that tool activates. Today every target
disallows any path matching `*legacy*`, which keeps a legacy artefact in the
repository while ensuring it reaches nobody, and Claude carries
`style:natural-language`.

The style directive lives here rather than in the style file, and
[output style delivery design](output-style-delivery-design.md) records why.

### Copying is not the only transform

A target receives a generated file rather than a copy wherever it reads a
different format. Codex agents are generated as TOML, Antigravity agents with its
own frontmatter and a mapped [tool vocabulary](antigravity-tool-vocabulary.md),
OpenCode agents with its permission object, and Cursor's output style as an
always-apply `.mdc` rule. Antigravity also takes a per-class
fan-out rather than one write, because its
[global roots](antigravity-global-roots.md) diverge by artefact class. Hook
configuration is merged into an existing settings file rather than replacing it.
Codex's `hooks.json`, Claude Code's `settings.json`, and Cursor's `hooks.json`
take an entry-by-entry merge, which adds an ai-modules entry that is missing,
updates one that exists at the position it already holds, and removes one the
shipped config no longer carries, while every foreign entry stays where it was;
Antigravity's file takes a named-key merge under `charter_guardrail` that touches
nothing else in it. Codex is the one target a shipped hook file actually reaches
that way today, and [hook delivery design](hook-delivery-design.md) has the
per-target routing.

The reasons behind each transform are per-harness facts and live on the harness
pages, starting with
[agent definition portability](agent-definition-portability.md).

### Global scope is a default, not a guarantee

On several harnesses a project-level or profile-level setting outranks the
user-level one the global deploy writes. Claude resolves `outputStyle` from three
files, where local project settings outrank checked-in project settings, which in
turn outrank the user-level key. The order and its verification date are on
[Anthropic Claude Code](../entities/anthropic-claude-code.md). Codex applies
a profile file and a project configuration over the user configuration. A global
deploy therefore establishes the machine default, which a project can override.

That override is a silent-failure surface as much as it is a feature. The deploy
merges its key, logs the merge, and reports the run as successful, and nothing in
that report separates a style that took effect from one a project-local key
already shadows. The operator reads a clean summary and then meets a session that
ignores the style. On Claude the confusion compounds, because every interactive
route writes the file that wins, recorded on
[Claude output style selection](claude-output-style-selection.md), so a style
picked by hand sticks while the deployed one looks broken.

What the deploy can honestly say about this is bounded by what it can read. It
resolves its own repository root by walking up from the script's own location to
the directory holding `plugins/`, never from the working directory, so a run can
inspect its own checkout and the project tree it was pointed at, and no other
repository on the machine. The absence of a warning is therefore never a coverage
claim across repositories, and only an unconditional statement of the override rule
holds for the repositories a run cannot open.

### Uninstall restores the value it replaced

Uninstall replays the deployed artefacts log, and a scope flag limits removal to
the scope it names: `--global` removes only entries deployed into the global
scope and `--project-dir DIR` only entries deployed into that project, while a
run without either flag covers every scope.

The deployed artefacts log is tab separated: destination, target, type, source,
and an optional fifth field holding what the destination held before, with a
merged key written as `<target-file>[<key>]`. Removing a
copied file is complete because the file was the whole change. Removing a merged
settings key needs that prior, so the shared key-merge function records it on the
first write of a key, as compact JSON or the literal `@absent` when the key was
missing, and a later redeploy reuses the first recorded value rather than
re-sampling the live one. Uninstall then writes the recorded prior back, or
deletes the key when `@absent` was recorded. Restoring a harness default instead
would be wrong, because the default is whatever the user had rather than a vendor
constant.

Two provisions keep this compatible with what the log already held. A four-field
line written before the capture existed still uninstalls by stripping the key,
which is the honest reading when no prior was recorded. And the post-removal
success check accepts a key still present with its restored prior, treating
absence as success only for `@absent` and for those legacy lines.

The capture sits on the shared merge function rather than on a style-specific
caller, so every scalar settings key gains the same restore, and Antigravity's
named-key hook merge inherits it too. A hook file shared with the user is
different: ai-modules owns only the entries it wrote, so those merge at entry
grain and uninstall removes exactly the listed entries from an `@entries:`
manifest rather than writing a whole-key prior back. The capture shipped with
the first style deploy because a style is delivered as a file plus a settings
key rather than as a file alone. See
[Claude output styles](claude-output-styles.md).

### What the script has become, and the line that keeps it a helper

The script is the largest single executable file in the repository, and it
outweighs every bundled skill script put together. It carries its own
configuration format, its own log format, backup retention, an uninstall path,
a dry run, two-dimensional filtering, and a code generator for each target format
it bridges. It is also the
only substantial program here that ships to nobody, while every machine depends
on it.

That makes the question of whether it is still a helper worth answering with a
test rather than an impression, and the shipped portability rules already supply
one: reserve deploy-time transforms for format bridges. A bridge translates
something the repository already states into the shape a target reads, so its
output is derivable from a repository source plus the target's documented schema.
Everything the script does today passes that test, including the agent
generators, which map one authored Markdown definition onto three target schemas.

Growth alone does not move it off that line, because its capability list is
derived from the artefact-type by harness matrix rather than from purposes of its
own. What would move it is originating content that exists nowhere in the
repository, at which point the deploy is authoring rather than installing, and
the authored thing belongs in the repository where it can be reviewed.

The synthesized whole-prompt route is the closest case, since it invokes another
vendor's binary, parses its output, and substitutes sections inside an
undocumented internal document. It stays a bridge because both inputs are
identifiable, the vendor's live text and the repository's authored prose, and the
script only joins them. It is still the first place where the installer depends
on another product's internals, which is why
[output style delivery design](output-style-delivery-design.md) requires it to
fail loudly rather than improvise.

A second-order risk deserves naming beside the first. Every transform the script
performs is a behaviour a native marketplace install does not get, so the more it
does, the more the two installation paths diverge. That divergence is already
real for generated agents, and it is the same trap the portability rules warn
about when they say a deploy-only convention is invisible on every native install
path.

## Open questions

Whether every harness should receive every artefact class is unsettled. OpenCode
hooks are not implemented, and the `style` type reaches Claude and, at project
scope only, Cursor, while its other harnesses stay unbuilt. So the target matrix
has holes that are decisions
in some cells, sequenced work in others, and gaps in the rest. The command row is
the settled kind, empty in every target's cell because the source is.

## Related concepts

- [Plugin packaging and versioning](plugin-packaging-and-versioning.md).
- [Foreign directory adoption](foreign-directory-adoption.md), for why the
  script writes a variant into each harness's own root instead of relying on one
  harness reading another's files.

## Derived from

- `deployment/README.md`, `deployment/deployment.conf`, and
  `deployment/deployment.sh`.
- `CHARTER.md` at this repository root for the command deprecation, and the
  repo-root instruction files for the definition of the term.
