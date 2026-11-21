---
title: Claude output styles
created: 2026-08-08
updated: 2026-11-21
type: concept
tags: [claude, output-style, system-prompt, frontmatter, deployment]
sources: []
confidence: high
---

# Claude output styles

## Definition

An output style is a Markdown file whose body Claude injects into the system
prompt in place of the built-in style guidance. It is a Claude-only component:
Codex's plugin manifest carries no `outputStyles` key, and Cursor, OpenCode, and
Antigravity document no equivalent, so a style shipped through a multi-harness
plugin is live on Claude and inert everywhere else.

What makes it a distinct mechanism, rather than a rule with better placement, is
that it displaces rather than appends. Understanding that requires reading the
system prompt as two layers.

Facts below were verified on 7 August 2026 against
`code.claude.com/docs/en/output-styles` and `/docs/en/plugins-reference`, plus
the Claude Code build installed on that date and the desktop application bundle,
unless a passage names its own later date. The built-in roster and the
frontmatter handling were re-checked on 1 October 2026 against the docs page,
the Claude Code changelog, and build 2.1.284, and each of those passages names
that date. The selection facts carry their own dates on
[Claude output style selection](claude-output-style-selection.md). Re-verify
before relying on them.

## Current state of knowledge

### The two layers

A style layer holds exactly one occupant. The built-in Default fills it unless a
style is selected, and Proactive, Concise, Explanatory, and Learning are the
other built-in occupants a user switches between. Concise arrived in v2.1.237,
which the changelog and the docs page both stated on 1 October 2026.

An engineering layer holds the built-in software-engineering instructions
covering how to scope changes, write comments, and verify work.

Selecting a custom style displaces whatever held the style layer, so the Default
style's tone, format, and verbosity guidance is gone whatever the frontmatter
says. `keep-coding-instructions: true` governs the engineering layer alone. A
style is therefore a replacing mechanism at both settings of that flag, and the
flag decides only how much of the engineering layer comes back beside it.

That shape is the whole reason the feature exists as its own component. The same
prose placed in `CLAUDE.md` or `AGENTS.md` appends, and then competes with
default style guidance it has no way to remove, which is why user-authored style
rules placed there land weakly and inconsistently. Claude reinforces the
difference at runtime by issuing reminders to adhere to the active style during
the conversation, which no rules file receives.

A style body handed to a headless worker with `--append-system-prompt-file`
arrives the same way. On 2 October 2026 against build 2.1.226, a marker style
body passed with that flag reached the worker, and the CLI's help describes the
append flags as adding to the default system prompt, so the body sits beside
whatever holds the style layer rather than in its place. That build's option
list leaves the flag out and names it only inside the `--bare` description.

### Two scope limits

A style applies to the main conversation only. A subagent runs its own system
prompt, and only a fork inherits the parent's, so an agent definition's policy
has to stand on its own.

A custom style, user-level or plugin-supplied, is disabled under safe mode in the
build checked, which annotates the saved value as `<name> (disabled in safe
mode)`. A rule that must hold in every session belongs somewhere other than a
style.

### Two delivery modes

A global style is the default for every session on the machine that no
project-local key overrides, and it is two placements rather
than one: the file at `~/.claude/output-styles/<name>.md`, and
`"outputStyle": "<name>"` in `~/.claude/settings.json`. Nothing in the plugin
system writes either of them. A marketplace install, a `/plugin` enablement, and
a plugin manifest all leave the user configuration tree untouched, so a component
repository reaches this mode only through a deploy step that copies the file and
merges the settings key.

That is the mirror image of the usual caution about deploy-only conventions,
where an effect that depends on a deploy step is invisible on native install
paths. Here the effect is reachable by the deploy path alone, so the absence of a
plugin channel is the design of the feature rather than a gap to work around.

A plugin-integrated style ships inside the plugin under `output-styles/` and is
live only while that plugin is loaded and enabled, which makes its coverage a
property of the plugin rather than of the user.

The two modes need different placements, different activation instructions, and
different removal steps, so a style written for one does nothing when dropped
into the other's channel.

### Locations

A style file lives at user level in `~/.claude/output-styles/`, at project level
in `.claude/output-styles/`, or in the managed-settings directory, and the
filename supplies the style name unless frontmatter `name:` overrides it. Project
styles load from every `.claude/output-styles/` between the working directory and
the repository root, and since v2.1.178 the directory nearest the working
directory wins a collision.

A style takes effect once the `outputStyle` settings key names it. Which file
each route writes, why a machine-wide style has no interactive route, when a
switch applies, and the history of the `/output-style` command are on
[Claude output style selection](claude-output-style-selection.md).

### Plugin-bundled styles

A plugin auto-discovers one Markdown file per style from `output-styles/` at the
plugin root. An `outputStyles` entry in `.claude-plugin/plugin.json` takes a path
or an array of paths and replaces that default scan, so list `./output-styles/`
explicitly alongside any custom path to keep both. A marketplace entry can
declare `outputStyles` as well, with append or replace semantics; declaring
components in both places at once is an error Claude reports rather than merging.

A plugin style is namespaced `<plugin>:<style>`, where the style half comes from
frontmatter `name:` or the filename, so any settings value selecting it carries
the prefix. Without a `description:` the picker shows a generated line naming the
source plugin.

`force-for-plugin: true` makes a plugin style apply on its own, overriding the
user's `outputStyle` for as long as the plugin is enabled, and the first style
loaded wins when several enabled plugins force one. Four gaps remain even so: an
unforced style merely waits in the picker, a forced one is absent wherever the
plugin is not enabled, both are off under safe mode, and an edit needs
`/reload-plugins` or a restart. That is why forcing is not a route to the global
mode.

### Frontmatter

The schema declares four keys: `name`, `description`,
`keep-coding-instructions`, and `force-for-plugin`. Build 2.1.284, read on
1 October 2026, checks a style's frontmatter against that strict schema only as
a shadow validation. An unknown key or a wrong value type is reported to
telemetry, and the style loads regardless. The docs page agrees that a misspelled
field is ignored without an error. It adds that frontmatter which fails to parse
still loads the style under its file name with no fields set.

The 7 August pass recorded that a fifth key was rejected outright. Build 2.1.226
already carried the same shadow-check telemetry, and no earlier build was
re-read, so it is unknown whether any build ever rejected one.

A fifth key is therefore harmless to the loader, and it is still pointless,
because Claude ignores it and no other harness reads a style file. The
union-of-native-fields pattern that agent frontmatter needs has nothing to unite
here, so a style file stays single-harness in its metadata as well as its effect.

Claude strips the frontmatter and injects the body alone, so a port to another
harness carries the body and drops the block rather than shipping the file whole.

`force-for-plugin` is meaningful only on a plugin-bundled style. Set on a
user-level file it is ignored and logged as a warning on every load. Build
2.1.284 still carried that warning on 1 October 2026.

## Open questions

Whether a repository-tracked style should be deployed at global scope, project
scope, or both is settled on Claude and open elsewhere. The Claude arm resolves
both placements against the same configuration-directory variable, so one code
path serves the user tree and a project tree, and it shipped that way. Which scope
is primary on Cursor, Antigravity, and VS Code, where the project tree is the
native home, stays open.

## Related concepts

- [Claude output style selection](claude-output-style-selection.md) for the
  routes that set the `outputStyle` key and the scope each one writes.
- [System prompt substitution across harnesses](../comparisons/system-prompt-substitution-across-harnesses.md)
  for what carries the same intent on the other five targets.
- [Output style delivery design](output-style-delivery-design.md) for what this
  repository actually decided to write, where, and why.
- [The deployment model](deployment-model.md) for how the settings-key half is
  written, and for the prior-value capture that lets uninstall restore what the
  `outputStyle` merge replaced.

## Derived from

- `code.claude.com/docs/en/output-styles` and `/docs/en/plugins-reference`.
- The Claude Code build and desktop bundle installed on 7 August 2026.
- The raw Markdown of `code.claude.com/docs/en/output-styles` and the full Claude
  Code changelog, read on 1 October 2026.
- Claude Code builds 2.1.284 and 2.1.226, read on 1 October 2026 for the
  shadow-only frontmatter validation and the `force-for-plugin` warning.
- Claude Code build 2.1.226 on one machine, probed on 2 October 2026 with a
  marker style body, for `--append-system-prompt-file`.
- The `harness_portability` skill in this repository, before its August 2026
  split.
