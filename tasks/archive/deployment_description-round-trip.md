---
description: Make each deploy generator that rebuilds frontmatter carry the source description through unchanged, and prove the round trip for every YAML scalar form in the deploy harness.
scope: deployment
created: 2026-10-07T06:03:07Z
updated: 2026-11-13T20:39:54Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
audited-by: Andreas Hoffmann
design-extended: false
---

# Carry the source description through every deploy generator unchanged

## Goal

Every deploy generator that rebuilds frontmatter writes the source's
`description` so that the target harness reads exactly the text the source
declares, whichever YAML scalar form the source uses: plain, single-quoted,
double-quoted, or a `>` or `|` block scalar. The deploy harness proves this round
trip for each generator and each form, so a generator change that alters a
description fails a test.

## Context

The deploy script copies skills verbatim, and it rewrites agent frontmatter for
VS Code, Cursor, and Claude through `rewrite_agent_frontmatter`, which passes the
description lines through and so preserves every form. Four generators rebuild
frontmatter key by key instead, each reading `description` with its own
single-line pattern. On 7 October 2026 a probe ran each of them on fixture sources
and compared what a parser reads from the output with the source:

| Generator | Quoted value | Block scalar |
| --- | --- | --- |
| `generate_opencode_agent` | kept, reads correctly | description lost |
| `generate_antigravity_agent` | kept, reads correctly | description lost |
| `generate_cursor_style_rule` | quotes stripped, so a value holding a colon followed by a space no longer parses | description lost |
| `generate_toml_agent` (Codex) | quote characters become part of the TOML string | description becomes `>` or `\|` |

A plain value survives all four. The block-scalar loss comes from the line loops:
`generate_opencode_agent` and `generate_antigravity_agent` skip the indented lines
after a key, which leaves an empty `description: >`, while
`generate_cursor_style_rule` and `generate_toml_agent` capture only the key line.

`escape_toml_basic_string` escapes `\` and `"` only. `generate_toml_agent` uses it
for the single-line basic strings (`name`, `description`, `model`,
`model_reasoning_effort`) and for the multi-line `developer_instructions` string,
where raw newlines are legal.

The deploy script runs on a runtime floor of Bash 3.2, `jq`, `perl`, and `rsync`,
so decoding has to happen in shell or perl. The tests can use Python: `tomllib`
(Python 3.11 or newer) reads the Codex output, and the frontmatter check that
[the frontmatter gate task](toolchain_frontmatter-yaml-gate.md) adds prints each
file's decoded top-level values as JSON through its `--values` mode, which reads a
fixture source and a generated YAML file alike. This task uses that mode, so it
lands after the gate task.

The forms to support are the scalar forms the frontmatter check accepts: plain,
single-quoted (an embedded `'` written as `''`), double-quoted with backslash
escapes, and `|` or `>` block scalars with an optional `-` or `+` chomping
indicator.

## Approach

The generators in scope are those that rebuild frontmatter rather than copy it:
the four in the Context table, plus any such generator that has landed since.

**YAML targets.** In `generate_opencode_agent`, `generate_antigravity_agent`, and
`generate_cursor_style_rule`, carry the source's `description` entry through as
written: the key line as it stands, quotes included, followed by the indented
continuation lines of a block scalar. Remove the quote stripping from
`generate_cursor_style_rule`.

**Codex.** In `generate_toml_agent`, decode the YAML scalar into its text before
encoding it, in shell or perl, by the rules the frontmatter check's `--values` mode
already applies (`decode_double` and `decode_single` for quoting and escapes,
`decode_block` and `fold_lines` for block scalars, in `scripts/lint_frontmatter.py`):
undo the quoting of a single- or double-quoted value, expanding every escape
`decode_double` expands, and for a block scalar join the continuation lines by
the literal or folded rule with the chomping indicator applied, keeping the
more-indented lines and interior blank lines `fold_lines` preserves. Write the result as a
single-line TOML basic string that escapes newlines and other control characters
as well as `\` and `"`. `developer_instructions` keeps its multi-line string and
its current escaping.

**Harness.** Add a round-trip script beside `style_run.sh` under
`tests/deployment/script_tests/`, run from `tests/deployment/run_all.sh`. It stages
fixture agent and style sources in a temporary directory, one per scalar form,
with values that exercise each form's escaping: a colon followed by a space and a
`#` after whitespace in every form that allows them, an embedded quote in the
quoted forms, a backslash, a `\n`, a `\t`, and a `\u` escape in the double-quoted
fixture, an interior blank line and a more-indented line in one `>` fixture, and
more than one line in the block scalars, with the
block-scalar fixtures covering the clip, `-`, and `+` chomping forms so their
trailing blank lines and final newline differ. It calls each generator in scope the way `style_run.sh` calls
`merge_json_key`: inside a subshell that runs `set -- --uninstall`, sets
`DEPLOYMENT_SH_SKIP_MAIN=1`, and then sources the deploy script, because
`deployment.sh` prints usage and exits at its zero-argv check before it reaches
the skip-main check. It runs `rewrite_agent_frontmatter` on the same fixtures so
the passthrough path stays covered. Because every generator in scope ends by appending to
`$DEPLOYED_ARTIFACTS_LOG`, the script sets that variable to a file inside its
temporary directory in the shell that sources the deploy script, before it calls
any generator, so no fixture row reaches the developer's deploy log. For each
output it compares the description a parser reads with
the one the source declares, reading YAML through the frontmatter check's
`--values` mode and the Codex TOML through `tomllib`. The same change updates the
two standing inventories that enumerate the deployment script tests by filename,
so each lists the new script beside every other script test in
`tests/deployment/script_tests/`, found by listing that directory at
implementation time: the `deployment/` bullet under `## Current harnesses` in
`tests/README.md`, and the `deployment/` row of the harness table in
`tests/CLAUDE.md`.

**Out of scope:**

- Other frontmatter keys the generators carry, such as `name`, `model`, and
  `tools`, which hold identifiers and plain values today.

## Acceptance

- The round-trip script runs from `tests/deployment/run_all.sh` and passes with a
  nonzero reported comparison count, comparing every generator in scope and
  `rewrite_agent_frontmatter` against every scalar form.
- The deploy log that `deployment.sh` resolves with `DEPLOYED_ARTIFACTS_LOG`
  unset is byte-identical before and after a run of the round-trip script, and
  every row the run appends lands in the script's own temporary log.
- The harness includes a negative control that feeds the comparison a
  description with its quotes stripped, and the comparison reports that mismatch.
- The `deployment/` bullet in `tests/README.md` and the `deployment/` row in
  `tests/CLAUDE.md` each name the new round-trip script beside every other script
  test in `tests/deployment/script_tests/`, and listing that directory leaves no
  script test unnamed in either inventory.
- The Cursor style rule generated from a double-quoted description that contains a
  colon followed by a space parses, and its description reads as the source text.
- The Codex TOML generated from a single-quoted and from a double-quoted
  description reads through `tomllib` as the source text, with no quote
  characters the text itself lacks, including a double-quoted description
  carrying a `\n`, a `\t`, and a `\u` escape, which reads back through
  `tomllib` as the newline, tab, and character those escapes denote.
- A `>` and a `|` block-scalar description reach the OpenCode, Antigravity, Cursor
  style rule, and Codex outputs with their full text, folded or kept literal as
  the indicator requires, and with the clip, `-`, and `+` chomping forms each
  keeping or stripping the source's trailing newlines and blank lines, and a `>`
  description holding an interior blank line and a more-indented line reaches
  those outputs with the paragraph break and the preserved indented line the
  source declares.
- `tomllib` reads the `developer_instructions` of a generated Codex agent as the
  source body.
