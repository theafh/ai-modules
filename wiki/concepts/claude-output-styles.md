---
title: Claude output styles
created: 2026-08-08
updated: 2026-08-10
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
unless a passage names its own later date. The selection facts under
`### Locations and activation` were re-verified on 10 August 2026 against build
2.1.226. Re-verify before relying on them.

## Current state of knowledge

### The two layers

A style layer holds exactly one occupant. The built-in Default fills it unless a
style is selected, and Proactive, Explanatory, and Learning are the other
built-in occupants a user switches between.

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

### Two scope limits

A style applies to the main conversation only. A subagent runs its own system
prompt, and only a fork inherits the parent's, so an agent definition's policy
has to stand on its own.

A custom style, user-level or plugin-supplied, is disabled under safe mode in the
build checked, which annotates the saved value as `<name> (disabled in safe
mode)`. A rule that must hold in every session belongs somewhere other than a
style.

### Two delivery modes

A global style governs every session on the machine and is two placements rather
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

### Locations and activation

A style file lives at user level in `~/.claude/output-styles/`, at project level
in `.claude/output-styles/`, or in the managed-settings directory, and the
filename supplies the style name unless frontmatter `name:` overrides it. Project
styles load from every `.claude/output-styles/` between the working directory and
the repository root, and since v2.1.178 the directory nearest the working
directory wins a collision.

Selection is the `outputStyle` settings key, and project and local settings
outrank the user-level key that the global mode sets, on the three-file order
recorded under `### Configuration roots` on
[Anthropic Claude Code](../entities/anthropic-claude-code.md). Running `/config`
and choosing Output style writes the pick to `.claude/settings.local.json` at
local project scope, so an operator who selects a style that way has bound one
project rather than the machine. The picker offers no scope choice at all, which
sets it apart from the permission-rules editor in the same dialog, where a rule
can be filed at user, project, or local scope. Both facts were re-verified on
10 August 2026 against build 2.1.226, from the picker's own write target and from
observed behaviour where a project-local value beat a user-level one.

The consequence for deployment is that a machine-wide style has no interactive
route. Since neither the picker nor any CLI subcommand writes the user-level key —
the retired surfaces are on
[Anthropic Claude Code](../entities/anthropic-claude-code.md) — writing the
user-level settings file is the only way to set it, and a project holding its own
local `outputStyle` keeps overriding that value until the key is removed there.

The style is read into the system prompt once at session start, so an edit to
either half takes effect after `/clear` or in a new session.

Two documented activation routes are gone and are recorded on
[Anthropic Claude Code](../entities/anthropic-claude-code.md).

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

The schema accepts exactly four keys: `name`, `description`,
`keep-coding-instructions`, and `force-for-plugin`. It rejects a fifth key
outright rather than ignoring it, which is the opposite of Claude's tolerant
agent frontmatter. So the union-of-native-fields pattern has no equivalent here,
and a style file stays single-harness in its metadata as well as its effect.

Claude strips the frontmatter and injects the body alone, so a port to another
harness carries the body and drops the block rather than shipping the file whole.

`force-for-plugin` is meaningful only on a plugin-bundled style. Set on a
user-level file it is ignored and logged as a warning on every load.

## Open questions

Whether a repository-tracked style should be deployed at global scope, project
scope, or both is settled on Claude and open elsewhere. The Claude arm resolves
both placements against the same configuration-directory variable, so one code
path serves the user tree and a project tree, and it shipped that way on
8 August 2026. Which scope is primary on Cursor, Antigravity, and VS Code, where
the project tree is the native home, is still open backlog work.

## Related concepts

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
- The `harness_portability` skill in this repository, before its August 2026
  split.
