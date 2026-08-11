---
description: Make skill_doctor usable in any skill-shipping repo: discover the layout, gate only on what the harness rejects, report a missing version as info, and run the checks the repo defines.
scope: plugins/ai_dev/skills/skill_doctor
created: 2026-08-11T18:24:43
updated: 2026-08-11T18:24:43
status: open
reported-by: Andreas Hoffmann
---

# Make skill_doctor portable across repo conventions

## Goal

A `skill_doctor` run in any repository that ships skills produces findings that
are all real for that repository. Four behaviours change for the user: the run
discovers the skill layout instead of requiring one, it blocks only on what the
harness genuinely refuses to load or route, a missing `version:` reports as info
because no harness field reads it, and the verification step runs the checks the
repository itself defines instead of the ones this repository happens to use. A
foreign repo's healthy skill stops drawing blocking findings that describe this
repo's conventions.

## Context

The skill reads as portable and behaves as repo-specific. Four passages carry
this repository's conventions as hard requirements, and a run against any other
skill-shipping repo trips over them.

**Layout.** `<scope_resolution>` states `Every check targets the repository source
tree that holds`plugins/*/skills/`` and, for anything else, `report that the
layout this walk expects is absent and ask which tree to read`.
`scripts/resolve_scope.py` hardcodes the same shape in its
`*/skills/*/SKILL.md` glob under a `plugins` parent. Repos that ship skills in
other shapes get no scope at all: a `skills/<name>/SKILL.md` tree at the root, a
`.claude/skills/` tree, or a single-skill repo whose `SKILL.md` sits at the top
level.

**Severity.** `<discovery_safety>` blocks on `a missing`name` / `description` /
`version``, and `scripts/discovery_safety.py` appends `version_missing` to
`blocking` with the message `frontmatter lacks usable `version:``. No harness
field reads a skill's `version`. The recognized skill frontmatter keys in the
installed CLI are `allowed-tools`, `disallowed-tools`, `argument-hint`,
`disable-model-invocation`, and `user-invocable`, beside `name` and
`description`; `version` appears nowhere among them. A marketplace of roughly 150
skills in another repository carries no `version:` in any `SKILL.md`, and those
skills load, list, and activate normally. The requirement is this repository's
own, stated in its rule files as **Ship a new skill, agent, or plugin at 1.0.0.**
and **Bump once per commit, with the change — and only at commit time.**, and it
stays enforced there rather than by a portable audit tool.

What the harness does refuse is a different set, visible in the CLI's own load
path: `Failed to load skill from`, a frontmatter it cannot destructure, and
`Skipping plugin skill <path>: not a regular file or exceeds <N> byte limit`. It
also matches the skill file case-insensitively as `skill.md` and logs `Multiple
skill files found in <dir>, using <x>` when a directory holds more than one. Those
are the shape of a blocking finding: the skill is not loaded, or is loaded from a
file the author did not mean.

One severity is genuinely undetermined. The doctor blocks when frontmatter `name:`
disagrees with its directory name, and whether the harness cares is unverified;
this repo's rule files state the alignment as a convention.

**Registration.** The `Registration` step of `<workflow>` prescribes this repo's
manifest set: `.codex-plugin/plugin.json` keeps `"skills": "./skills/"`,
`.claude-plugin/plugin.json` stays in lockstep, marketplace files register
plugins, and the standing **Plugin meta stays lockstep.** rule supplies a version
check. A repo with one manifest, a different marketplace shape, or no manifest at
all fails checks that describe a convention it never adopted.

**Verification.** The `Tests and verification` step of `<workflow>` names a fixed
list: `tests/<skill>/script_tests/`, `tests/<skill>/evals/`, `markdownlint`,
`python3 $AI_INSTRUCTION_FORMATTING_SKILL/scripts/lint_pseudo_xml.py`, `jq empty`,
and `the repository's own deploy preview where it exposes one
(`./deployment/deployment.sh --global --dry-run`in this repo)`. That list is this
repository's `Makefile` inlined: its `lint` target runs the markdown, JSON, and
shell linters, and its `deploy` target wraps that script. Another repo answers the
same questions through entirely different entry points, such as a validator task,
mise tasks, and a pre-commit config, none of which the step knows to look for. The
sibling-skill lint also presumes that sibling is installed, which a foreign
checkout need not have.

Reconcile with [ai-dev_skill-doctor-scope-failure-reporting.md](ai-dev_skill-doctor-scope-failure-reporting.md):
it makes an absent `plugins/*/skills/` tree a first-class resolver failure emitted
identically in all three scope modes, which this task must not undo. The absent
layout stays a failure with that task's message and its three-mode consistency; it
becomes the terminal case reached after discovery finds no `SKILL.md` anywhere,
rather than the response to a repo that simply keeps its skills elsewhere.

Co-edit: [ai-dev_skill-doctor-agent-scope.md](ai-dev_skill-doctor-agent-scope.md)
rewrites the same `<scope_resolution>` block and may add a resolver mode,
[ai-dev_skill-doctor-sibling-nonascii-message.md](ai-dev_skill-doctor-sibling-nonascii-message.md)
and [ai-dev_skill-doctor-listing-budget-length.md](ai-dev_skill-doctor-listing-budget-length.md)
both change findings in `scripts/discovery_safety.py`, and all four add scenarios
to the same script-test runner.

## Approach

Work the four surfaces as one change, since each one's fix is the same move:
derive the requirement from the harness or from the repo, never from this repo's
conventions written in as constants.

**Sort the findings into three tiers by what they can prove.** Block only where
the harness fails to load the skill or cannot route it: frontmatter absent or
unparseable, `name` absent, `description` absent, a parser-hostile or invisible
character in the description, and a file the harness skips, whether over the byte
limit, not a regular file, or one of several skill files in a directory. Read that
byte limit out of the installed CLI at check time rather than writing a constant
into the script, so it tracks the harness. Keep every description-quality
judgement at `warning`, as the severity paragraph already argues. Add a third
`info` tier for a fact that is true of the file but owned by a repo convention,
and move `version_missing` into it with a message that says the field is
convention-owned, citing the repo's own rule when its rule files state one and
saying no rule was found when they do not. `scripts/discovery_safety.py` currently
emits `blocking` and `warnings` only, so the new tier means a new payload key, a
new count, and a matching section in the skill's `<output_contract>` where the
three tiers are reported in order.

Settle the name-versus-directory severity by test rather than by assumption:
stage a plugin skill whose frontmatter `name:` differs from its directory, load it
in the harness, and see whether it lists and invokes. Block when the harness
refuses it, warn when it does not, and record which the test showed so the choice
is auditable.

**Discover the layout instead of requiring one.** Replace the fixed glob with a
walk that finds `SKILL.md` files under `--root`, case-insensitively, skipping
version-control, dependency, build, and cache directories. Recognize the plugin
layout, a repo-root `skills/` tree, a `.claude/skills/` tree, and a single-skill
repo whose `SKILL.md` sits at the root, and report which layout the run resolved
so the reader can see what was walked. Keep the existing family and single-skill
selectors working against whatever the walk finds, and keep `--root`. Group a
found skill under the plugin manifest that owns it when one exists above it, since
the registration step needs that association.

**Derive the registration checks from the files that exist.** Rewrite the
`Registration` step so each check is conditional on its subject being present: a
manifest is checked for the fields the harness reads from it, a marketplace entry
is checked when a marketplace file exists, and a repo that ships no manifest gets
registration reported as not applicable rather than as missing. Keep the
version-lockstep check only where the repo's own rules state it, cited from those
rules rather than assumed, and skip it silently where they do not.

**Point at the repo's own checks instead of naming them.** Rewrite the `Tests and
verification` step as a soft pointer: read the repository's own rule files first,
then discover the check entry points it defines, such as `Makefile` targets, mise
tasks, a pre-commit config, package scripts, or a CI workflow, and run the ones
that cover the selected paths. Report every check that ran with its exact command
and every one that could not run with the reason. Keep the two requirements that
are about skill artifacts rather than repo tooling, stated at the level of
coverage rather than of a path: a skill with bundled scripts needs a test surface
somewhere in the repo, and a behaviour-only skill needs eval or trigger coverage
or a documented reason it has none. Make the sibling-skill pseudo-XML lint
conditional on that sibling resolving, and name it as skipped when it does not.

**Out of scope:**

- The cross-harness and cross-OS portability review of bundled runtime artefacts,
  which the `harness_portability` skill owns and this skill's `<boundary>` already
  routes to it.
- A scope mode for agents, which
  [ai-dev_skill-doctor-agent-scope.md](ai-dev_skill-doctor-agent-scope.md) owns.
- The check-only contract. This task changes which findings the run gates on, and
  the run still edits no target.

## Acceptance

1. Run against a staged repo whose only skill is `skills/demo/SKILL.md`, with no
   `plugins/` tree, the scope resolver returns that skill and the run reports the
   layout it resolved. Repeat with `.claude/skills/demo/SKILL.md` and with a
   single root-level `SKILL.md`, and each resolves.
2. Run against a staged repo holding no `SKILL.md` anywhere, all three scope modes
   still emit the single absent-layout message that
   [ai-dev_skill-doctor-scope-failure-reporting.md](ai-dev_skill-doctor-scope-failure-reporting.md)
   defines, and exit nonzero.
3. A skill whose frontmatter carries `name` and `description` but no `version`
   produces an `info` finding, produces no blocking finding, and the run's
   blocking count is zero. Searching that finding's message for the word
   `convention` returns a match.
4. The same skill checked inside this repository has its `info` message cite this
   repo's own version rule by name, and checked inside a staged repo whose rule
   files state no version rule, the message says no such rule was found.
5. A `SKILL.md` with unparseable frontmatter, one with no `name`, one with no
   `description`, and one carrying an invisible character in its description each
   still produce a blocking finding.
6. A `SKILL.md` larger than the harness's plugin-skill byte limit produces a
   blocking finding naming the limit, and the limit in that message matches the
   value read from the installed CLI rather than a constant in the script.
7. A skill directory holding both `SKILL.md` and `skill.md` produces a blocking
   finding, since the harness picks one and logs the ambiguity.
8. The name-versus-directory severity is recorded with the harness behaviour that
   settled it, and the emitted finding's severity matches that record.
9. Run against a staged repo with a single `.claude-plugin/plugin.json` and no
   marketplace file, the registration step checks that manifest and reports the
   marketplace check as not applicable, with no finding claiming a missing file.
   Against a staged repo with no manifest at all, registration reports as not
   applicable in full.
10. Run against a staged repo whose only check entry point is a `mise` task named
    `lint` plus a `.pre-commit-config.yaml`, the verification summary names those
    two commands as the checks it ran. Searching the skill body for
    `deployment.sh` returns no match, and searching for `markdownlint` returns no
    match outside an illustrative list.
11. Run in an environment where the pseudo-XML lint's sibling skill does not
    resolve, the run completes and names that check as skipped with its reason.
12. `tests/skill_doctor/script_tests/run.sh` gains scenarios for the three
    alternative layouts, the info-tier version finding, the byte-limit block, and
    the ambiguous-skill-file block, and passes alongside its existing scenarios.
