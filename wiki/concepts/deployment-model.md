---
title: The deployment model
created: 2026-08-08
updated: 2026-08-08
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
uninstall works by replaying that log.

The script exists because a marketplace install cannot reach everything. A
plugin manifest delivers components, but it never writes a settings key and it
never reaches a harness whose plugin schema lacks the component type. Deployment
is the path that does.

## Current state of knowledge

### Discovery is plugin and folder based

Artefacts live under `plugins/<plugin>/<asset-folder>/`, and the folder name
selects the type: `agents/` and `commands/` take each top-level Markdown file,
`skills/` takes each immediate subdirectory containing a `SKILL.md`, and
`hooks/` takes each top-level shell or JSON file. Hidden files and README files
are skipped. The script walks up from its own location until it finds a
directory containing `plugins/`, so it does not care where in the tree it sits.

That single-rooted discovery is the reason a first asset source outside the
plugin tree, such as a repository-level styles directory, is a structural change
rather than a configuration one.

### Per-tool configuration

`deployment/deployment.conf` is parsed in robots.txt style: a `#tool` section
heading, then `disallow:` lines that skip a repo-relative path for that tool, and
`replace:` lines that substitute a variable inside deployed copies. Today every
target disallows any path matching `*legacy*`, which keeps a legacy artefact in
the repository while ensuring it reaches nobody.

### Copying is not the only transform

Three targets receive generated files rather than copies. Codex agents are
generated as TOML, Antigravity agents are generated with its own frontmatter and
a mapped tool vocabulary, and OpenCode agents are generated with its permission
object. Claude, Codex, and Antigravity hook configuration is merged as a JSON key
into an existing settings file rather than replacing it, which is what the
script's key-merge function exists for.

The reasons behind each transform are per-harness facts and live on the harness
pages, starting with
[agent definition portability](agent-definition-portability.md).

### Global scope is a default, not a guarantee

On several harnesses a project-level or profile-level setting outranks the
user-level one the global deploy writes. Claude's project and local settings
outrank the user `outputStyle` key, and Codex applies a profile file and a
project configuration over the user configuration. A global deploy therefore
establishes the machine default and can be overridden per project, which is
usually the desired behaviour but is worth stating rather than assuming.

### Uninstall and the missing prior value

The deployed artefacts log carries four tab-separated fields: destination,
target, type, and source, with a merged key written as `<target-file>[<key>]`.
It has no field for the value that was there before. Removing a copied file is
therefore complete, while removing a merged settings key cannot restore what it
overwrote. Capturing the prior value is the piece of groundwork that the output
style work depends on, because a style is delivered as a file plus a settings
key rather than as a file alone. See
[Claude output styles](claude-output-styles.md).

### What the script has become, and the line that keeps it a helper

The script is the largest single executable file in the repository: 1,911 lines,
40 functions, and seven flags as of 8 August 2026, against roughly 5,200 lines of
executable code across all bundled skill scripts combined. It carries its own
configuration format, its own log format, backup retention, an uninstall path,
a dry run, two-dimensional filtering, and three code generators. It is also the
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
hooks are not implemented today, and Antigravity receives no commands because
the repository ships none, so the target matrix has holes that are decisions in
some cells and gaps in others.

## Related concepts

- [Plugin packaging and versioning](plugin-packaging-and-versioning.md).
- [Foreign directory adoption](foreign-directory-adoption.md), for why the
  script writes a variant into each harness's own root instead of relying on one
  harness reading another's files.

## Derived from

- `deployment/README.md`, `deployment/deployment.conf`, and
  `deployment/deployment.sh`.
