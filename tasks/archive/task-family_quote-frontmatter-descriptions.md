---
description: Make the task skills write description in double quotes, make the task linter block an unquoted value YAML would misread, and let task_fix repair it by quoting.
scope: plugins/ai_dev/skills/task
created: 2026-10-07T08:16:38
updated: 2026-10-16T23:32:34
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Write task descriptions in double quotes and block values YAML would misread

## Goal

The task skills write every task's `description:` as a double-quoted YAML
string, so a colon or a `#` in the prose stays part of the value instead of
breaking the frontmatter or cutting the value short. The bundled task linter
reports an unquoted frontmatter value that YAML would misread as a blocking
finding, so `task_create`'s own lint step catches one the moment it is written,
and `task_fix` repairs it by quoting. Task files then carry valid YAML frontmatter
in every repository that uses the task skills, including repositories that have
no frontmatter gate of their own.

## Context

The `<frontmatter>` section of the base task skill shows the field as
`description: One-line compact summary of what this task delivers.`, unquoted,
and says nothing about quoting. Every writer of task files inherits that example:
the create path, the update flow, `task_auto_check` repairs including its
description-budget rewrite, `task_fix`, and the splits `auto_shaper_task` writes.

Agents often put a colon in a description. On 7 October 2026, 32 task files in
this repository, seven live and 25 archived and about one in seven of all task
files, had an unquoted `description:` containing a colon followed by a space,
which YAML reads as the start of a nested mapping. One more archived task loses
the end of its description, because a `#` after whitespace in an unquoted value
starts a comment. The open toolchain floor task is a typical case: its
description starts `Turn make install into environment preparation: declare the
runtime`.

The task linter accepts all of these. `parse_frontmatter` and `get_raw_scope` in
`scripts/lint.py` cut every frontmatter line at its first `#`, even inside quotes,
then strip surrounding quote characters, and they never test whether YAML would
read the value as written. The base skill's `<lint>` section already places
malformed frontmatter in the blocking bucket, and an unquoted value that YAML
misreads is malformed frontmatter. The task skills ship into other repositories,
where this linter is the only check on task frontmatter.

[The frontmatter gate task](../toolchain_frontmatter-yaml-gate.md) makes `make lint`
reject the same values in this repository and repairs the files it finds there.
Its accepted subset defines which unquoted values are safe, and the linter check
here flags the same unquoted cases. Whichever of the two tasks lands first
repairs the existing task files, and the other finds them clean.

The tests sit in three places. `tests/task/script_tests/run.sh` unit-tests
`lint.py`. The `task_create` evals grade each created file through
`tests/task_create/evals/grade.sh`, whose `fm_field` helper reads a value with its
quotes stripped. The `task_fix` evals stage a backlog and grade the repaired
files.

## Approach

**Writing rule.** In the base task skill's `<frontmatter>` section, rewrite the
example's `description:` line to a double-quoted value, and rewrite the
`description` field bullet to say the value is written in double quotes, with any
`"` or `\` inside it escaped by a backslash. The sibling skills and agents that
write task files inherit the rule through the base skill, so none carries its own
copy.

**Linter check.** In `lint.py`, report a blocking `frontmatter` finding that names
the key for each unquoted top-level value that starts with a character matching
`YAML_HOSTILE_START_RE` in
`plugins/ai_dev/skills/skill_doctor/scripts/discovery_safety.py`,
contains a colon followed by a space or a `#` after whitespace, or ends
with a colon. Make `parse_frontmatter` and `get_raw_scope` read a quoted value
whole, so a `#` inside quotes stays part of the value, and strip a trailing
comment only when its `#` follows whitespace outside quotes.

**Lint rules.** In the base skill's `<lint>` section, name the new case in the
opening sentence that lists what the linter checks and in the `**blocking**`
bucket, and add an entry to the mechanically fixable lint finding set: wrap the
value in double quotes, escaping any `"` or `\` inside it, and leave its text
unchanged.

**Existing files.** Run `task_fix` on this repository's backlog so it applies the
new fix to every task file the check flags, live and archived.

**Tests.** Add `lint.py` scenarios to `tests/task/script_tests/run.sh` for each
flagged case and for the quoted readings, and update the scenario count that the
task harness entry in `tests/README.md` states. Add a check under the
`# --- universal ---` heading in
`tests/task_create/evals/grade.sh` that the created task's `description:` is
double-quoted. Add a `task_fix` eval in `tests/task/evals/` beside `fix` whose staged
backlog holds a live task with an unquoted description containing a colon
followed by a space.

**Out of scope:**

- Rewriting existing task files whose unquoted description YAML reads correctly;
  the writing rule governs what the skills write from now on.
- The same quoting rule for the wiki skill family, whose pages all parse today.

## Acceptance

- The `<frontmatter>` example in the base task skill shows a double-quoted
  `description:` value, and the `description` field bullet states the
  double-quote rule with its backslash escaping.
- `lint.py` exits 1 with a blocking `frontmatter` finding that names the key on
  each staged case: an unquoted description containing a colon followed by a
  space, an unquoted value containing a `#` after whitespace, one starting with a
  backtick, and one ending with a colon.
- `lint.py` reports no finding for a double-quoted description that contains a
  colon followed by a space and a `#`, and a double-quoted description over 200
  characters with a `#` near its start still draws the description-length
  warning, which shows the quoted value is read whole.
- `get_raw_scope` returns a quoted `scope:` label that contains a `#` whole, so the
  scope check treats it as text.
- The `<lint>` section names the new blocking case and lists its fix in the
  mechanically fixable lint finding set.
- The `task_create` grader checks that the created description is double-quoted,
  and every eval registered in `tests/task_create/evals/evals.json` passes with
  that check on the Cursor worker.
- The new `task_fix` eval in `tests/task/evals/` passes on the Cursor worker:
  after the run, the staged description is double-quoted with its text unchanged,
  the body is byte-identical, and the linter reports no blocking finding.
- The linter's archive-inclusive run over this repository reports no finding from
  the new check.
- The task harness entry in `tests/README.md` states the scenario count that
  `run.sh` now runs.
