---
title: System prompt substitution across harnesses
created: 2026-08-08
updated: 2026-08-08
type: comparison
tags: [system-prompt, portability, output-style, claude, codex, opencode, antigravity, cursor, copilot]
sources: []
confidence: high
---

# System prompt substitution across harnesses

## What is being compared and why

A [Claude output style](../concepts/claude-output-styles.md) displaces the
built-in style guidance rather than arguing with it. The question this page
answers is what carries the same intent on the other five targets, and how much
of the displacement survives the port.

The answer matters because the same prose does different work depending on where
it lands. A rule written to remove something silently does nothing on a harness
that can only append, so a variant delivered without that caveat is presented as
equivalent when it is not.

Sorting the targets into a Claude-versus-the-rest split turns out to be wrong.
There are three tiers, because two non-Claude harnesses expose a whole-prompt
slot whose current contents can be re-derived, edited, and written back.

## Dimensions

### Displacement tier

| Harness | Tier | Mechanism |
| --- | --- | --- |
| Claude Code | native | The style layer is a configurable slot with exactly one occupant. |
| OpenAI Codex | synthesizable | `model_instructions_file` fills the single `BaseInstructions` slot. |
| SST OpenCode | synthesizable | An agent `prompt` replaces the per-model vendor base prompt. |
| Cursor | append-only | Rules are included at the start of context, replacing nothing. |
| Google Antigravity | append-only | Rules are constraints only; no tone or persona feature exists. |
| Copilot in VS Code | append-only | Instructions combine rather than compete. |

### What a global deploy has to write

| Harness | File | Activation |
| --- | --- | --- |
| Claude Code | `~/.claude/output-styles/<name>.md` | `outputStyle` key in `~/.claude/settings.json` |
| OpenAI Codex | instructions file under `~/.codex/` | `model_instructions_file` in `config.toml` |
| SST OpenCode | agent file, or a path in the `instructions` array | none for `instructions`; agent selection for the replacing route |
| Cursor | none that is documented | user rules live in the application settings |
| Google Antigravity | `~/.gemini/GEMINI.md` (the workspace `.agents/rules/` tree is project scope) | Always On activation mode |
| Copilot in VS Code | `~/.copilot/instructions` | none |

Copilot is the cheapest target to reach, with one file and no settings key.
Cursor is the most expensive, because its machine-wide carrier is not a file at
all and a deploy step cannot write it.

### Plugin-integrated route

Three harnesses can ship a standing style inside a plugin, by three unlike
mechanisms: Claude's `output-styles/` component, Antigravity's bundled `rules/`
directory, and an OpenCode plugin mutating the assembled prompt through an
experimental code hook. Copilot offers a partial fourth, bundling a selectable
agent or an on-demand skill but no instructions component, so a plugin there buys
availability rather than effect. Codex and Cursor leave the global configuration
deposit as their only channel.

### Injection position

Three positions are in play, and prose written for one reads oddly in another. A
Claude style occupies a system-prompt slot. OpenCode's `instructions` content
arrives in an appended system section, labelled with its own file path. A Copilot
custom agent's body is prepended to the user chat prompt rather than merged into
the system prompt, so wording that assumes a system voice arrives inside the user
turn.

### Reach

A Claude style reaches the main conversation only, since a subagent runs its own
system prompt. OpenCode's `instructions` tail is appended to every request
whatever agent is running, so it governs subagents too, which is wider reach than
the native tier offers. Antigravity caps each rule file at 12,000 characters, so
a long style splits across several files rather than travelling as one.

## Verdict

### The synthesizable tier is the real finding

Both Codex and OpenCode expose their current base prompt as sectioned Markdown,
so a deploy step can re-derive that text, substitute the style sections, and
write the result back. The outcome behaves like a style-layer swap while
remaining an all-or-nothing slot underneath.

Codex is the better-instrumented of the two. `codex debug models` renders the
resolved base instructions as JSON, so the live text needs no committed copy and
re-derives on every run. OpenCode ships no equivalent, so a generator either
reads the public repository and risks a version mismatch against the installed
build, or extracts the string from the application bundle.

OpenCode splits the prompt more cleanly. Its replacement swaps the vendor base
prose while the environment block, project rules, MCP instructions, and skills
catalogue survive untouched, which is a finer seam than Claude's all-or-nothing
`keep-coding-instructions` flag. The trade is that the slot is per agent rather
than global, so making the swap the default means overriding the built-in primary
agent.

### The price of synthesis

Three costs apply on both harnesses. The generator owns the whole prompt, so
anything it fails to carry over is simply gone. The result is frozen against
model switches, since neither harness re-derives once the slot is set by hand,
and on OpenCode switching models mid-session is a keystroke. And the section
names are undocumented internal structure, so a generator that cannot find an
expected heading must fail loudly rather than append and hope.

### What to state in any plan

Name which tier each target sits in rather than generalising from Claude. On the
append-only tier, say plainly that adherence will be weaker and less consistent,
because the ported prose argues with default guidance it cannot remove. On the
synthesizable tier, state how the base text is re-derived, which model it belongs
to, and what happens when an expected heading is gone.

## Related pages

- [Claude output styles](../concepts/claude-output-styles.md) for the native
  mechanism in full.
- [Output style delivery design](../concepts/output-style-delivery-design.md)
  for the decisions this comparison fed into.
- [System prompt substitution experiments](../summaries/system-prompt-substitution-experiments.md)
  for the research programme this comparison makes possible.
- The six entity pages for the per-harness detail behind each row.

## Derived from

- Provider documentation for all six targets, verified 7 August 2026 and cited on
  the entity pages.
- `github.com/openai/codex` on `main` and `github.com/sst/opencode` on `dev`.
- The `harness_portability` skill in this repository, before its August 2026
  split.
