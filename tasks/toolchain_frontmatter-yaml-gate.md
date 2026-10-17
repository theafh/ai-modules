---
description: Gate make lint on frontmatter that a strict YAML checker accepts, run skill_doctor's discovery check in place, and repair the files that fail today.
scope: "repo toolchain"
created: 2026-10-07T07:46:48
updated: 2026-10-16T23:32:34
status: open
reported-by: Andreas Hoffmann
---

# Check every tracked frontmatter block in `make lint`

## Goal

`make lint` fails when a tracked file's YAML frontmatter falls outside a strict
subset that every YAML parser reads the same way. Every block that would fail to
parse falls outside it, and so does every value a parser would silently shorten.
`make lint` also runs skill_doctor's discovery-safety check over every skill
through that skill's own bundled script. `make lint` is the enforcement point,
because the standing repo rules run it before every commit. The tree passes from
the first run, because this task also repairs every file the check rejects today.

The outcome is frontmatter that every harness can read: an artefact deployed to a
harness with a strict YAML parser loads there, and each harness reads the whole
value its author wrote. The check can also print the values it reads, which lets
another harness compare a generated file with its source.

## Context

No gate in the repository parses frontmatter as YAML today. `make lint` runs
markdownlint, which skips frontmatter content, a `jq` syntax check, and shellcheck.
The task linter, the wiki linter, and skill_doctor's `discovery_safety.py` each
read frontmatter with their own lenient standard-library parser, and each runs
only when its skill is invoked.

On 7 October 2026 a real YAML parser rejected 34 of the 308 tracked files outside
`tests/` that open with frontmatter: the agent definitions `auto_gate_task` and
`auto_shaper_task`, seven live tasks, and 25 archived tasks. Every rejection had
one cause, a plain (unquoted) `description:` value containing a colon followed by
a space, which YAML reads as the start of a nested mapping. The archived task
`task-family_test-harness-consolidation` parses but loses the end of its
description, because a `#` after whitespace inside a plain scalar starts a
comment. Claude Code loads both agents anyway, so its parser tolerates the colon;
whether the other harnesses do is unverified.

The repaired values have to suit the deploy generators. The Codex agent generator
copies a quoted `description:` value into its TOML output with the quote
characters inside the string, while the OpenCode and Antigravity generators keep a
quoted value intact. Skills are copied verbatim, so a quoted skill description is
safe on every target. The task linter strips surrounding quotes when it reads a
value, so quoting a task's description changes nothing the task tooling reads.

skill_doctor already checks this class of problem for skills.
`parse_frontmatter_fields` in `discovery_safety.py` flags a plain value containing
`:` and a value that starts with a YAML-significant character. The script exits 1
on a blocking finding and prints a JSON report whose `blocking` list and
`warning_count` carry the result. On the same date all 31 skills passed it, with
one warning-tier finding. Calling the script in place from the repository's gate
gives the repository that coverage on every run, and because the gate runs the
skill's own code, the two cannot drift apart. The dependency runs from the
repository to the skill, so skill_doctor stays portable to repositories that have
no such gate.

The frontmatter in the repository uses a small set of YAML shapes: plain scalars,
single- and double-quoted scalars, flow sequences such as `tags: [a, b]`, one
folded block scalar (`description: >`), and one block sequence under an empty
key. It uses no nested mappings, flow mappings, anchors, or multi-document blocks.
A prototype of the subset in Approach, run over the tree on the same date,
rejected exactly the 35 files above and accepted every other one.

The [toolchain floor task](toolchain_make-install-dependency-floor.md) declares
the tools `make lint` needs and rewrites the README sentence this task also edits,
so whichever of the two lands second adapts that passage.

## Approach

Write the check as `scripts/lint_frontmatter.py`, a Python 3 script that uses the
standard library alone, so it adds no install step on any machine. The standing
repo rules permit a repo-root `scripts/` directory for repo-wide tooling on the
user's request, which this check has.

**File set.** By default the script checks every tracked file (`git ls-files`)
ending in `.md` or `.mdc` whose first line is exactly `---`, leaving out files
under `tests/`, since a test fixture may carry broken frontmatter on purpose. It
also accepts explicit file paths, which the script tests use and which lets
another harness check files it generates.

**Accepted subset.** The script accepts a block that closes with a `---` line and
whose lines all take one of these shapes, and it reports every other line as a
finding that names the path, the line, and the key where one applies:

- a blank line, or a comment line starting at the first column;
- a top-level `key: value` line whose key uses letters, digits, `_`, and `-` and
  appears once in the block;
- a plain value that starts with no YAML indicator character, contains neither a
  colon followed by a space nor a `#` after whitespace, and does not end with a
  colon;
- a single-quoted value on one line, with an embedded `'` written as `''`;
- a double-quoted value on one line, using YAML's backslash escapes;
- a `|` or `>` block scalar with an optional `-` or `+` chomping indicator,
  followed by its indented continuation lines;
- a flow sequence on one line, such as `[a, b]`, whose items are quoted values or
  plain values free of `,`, `[`, `]`, `{`, and `}`;
- an empty value followed by indented `- item` lines, each item a plain or quoted
  value.

Whatever the subset accepts parses as YAML to the value its author wrote. A
repository that needs a new shape widens the subset by editing the checker.

**Values.** With `--values`, the script prints the decoded top-level values of
each file it is given as JSON keyed by path: quoting undone, escapes resolved, and
block scalars joined by the literal or folded rule with the chomping indicator
applied.

**Skill check.** The script also runs skill_doctor's `discovery_safety.py` in
place, resolving its path inside the repository from the script's own location,
in one call over every `SKILL.md` in its file set with the repository root as
`--root`. It fails on that script's blocking findings and prints each one's code,
path, and message, and it reports the warning count without failing. When the
script is missing from that path, the check fails and names the path, so a moved
skill surfaces as a failure.

**Make wiring.** Add a `lint-frontmatter` target that runs the script, and run it
from `lint` the way `lint` runs `lint-md`, `lint-json`, and `lint-sh`, so
`make lint` fails when it fails. Its output opens with a section header like the
other lint sections and ends with the number of files and skills checked.

**Repair.** Run the check on the tree and repair every file it reports. Reword the
`description:` of each reported agent definition so it contains no colon followed
by a space and stays unquoted, keeping its meaning, since the Codex generator
still copies quote characters into its output. Wrap each reported task file's
`description:` value in double quotes, escaping any `"` or `\` inside it, and
apply the task skill's `<bump_updated>` rule to that edit. A file of any other
kind follows the same test: reword a value the deploy generators read, and quote
one they do not.

**Documentation.** Rewrite in place each passage that says what `make lint` runs
or needs, so it names the frontmatter check and Python 3:

- the header comment and the `lint` help text in the Makefile;
- the `make lint` comment in the README's command block, and the README sentence
  beginning "`make lint` and `make fix` use", or the toolchain floor task's tool
  manifest when that task has already replaced the sentence;
- the `make lint` / `make fix` bullet under `## Common tasks` in `CLAUDE.md` and
  `AGENTS.md`;
- the `make lint` line in the `## Running Tests` block of `TESTING.md`.

List `scripts/` in the README's layout tree and in the `## Layout` block of
`CLAUDE.md` and `AGENTS.md`.

**Tests.** Add a script-test harness at `tests/lint_frontmatter/script_tests/run.sh`,
register it as the `## Test Organization` section of `TESTING.md` requires, and
stage every scenario in a temporary directory outside the checkout.

**Out of scope:**

- Checking what the deploy generators write, owned by
  [the description round-trip task](deployment_description-round-trip.md).
- A git pre-commit hook; `make lint`, which the standing repo rules run before
  every commit, is the enforcement point.
- Replacing the parsers inside the task linter, the wiki linter, or skill_doctor
  with this checker; the shipped linters keep their own parsers so they run in
  any repository.
- How the task skills write and lint a `description:` value, owned by
  [the description quoting task](archive/task-family_quote-frontmatter-descriptions.md).

## Acceptance

- `make lint` on the repaired tree prints a frontmatter section that reports the
  files and skills it checked and exits 0, `make -n lint` shows `lint` running
  `lint-frontmatter`, and `python3 scripts/lint_frontmatter.py` run alone reports
  no finding.
- The harness passes and shows the check failing, with a finding that names the
  file, on each of these staged cases:
  - plain values that contain a colon followed by a space, end with a colon,
    contain a `#` after whitespace, or start with a backtick;
  - a single-quoted value holding a lone `'`, and a double-quoted value holding
    an unescaped `"`;
  - a flow-sequence item containing a brace;
  - a key that appears twice, a nested mapping line, and a block with no closing
    `---`;
  - a `SKILL.md` with no `name:`, which `discovery_safety.py` blocks;
  - a staged copy of the check whose `discovery_safety.py` path is missing, where
    the finding names that path.
- The same harness shows every accepted shape passing, including a quoted value
  that contains a colon followed by a space, and it shows a `SKILL.md` whose only
  finding is warning-tier passing, a file without frontmatter skipped, and a
  broken file under `tests/` left out of the default file set and reported when
  passed as an explicit path.
- `--values` run on a fixture that holds each accepted scalar form prints the
  expected text the harness states for it: `''` collapsed in a single-quoted
  value, escapes resolved in a double-quoted value, and folded and literal block
  scalars joined by their rules with each chomping indicator applied.
- No agent definition under `plugins/*/agents/` carries a quoted `description:`
  value or a plain one containing a colon followed by a space.
- Every passage the Documentation step names states the frontmatter check and
  Python 3, and none still describes `make lint` as covering markdown, JSON, and
  shell alone.
- The README layout tree and the `## Layout` blocks list `scripts/`, and the
  testing inventory names the new harness.
