---
description: Correct skill_doctor's resolve_scope failure enumeration and make an absent plugins/*/skills tree report as its own failure in every scope mode.
scope: plugins/ai_dev/skills/skill_doctor
created: 2026-08-10T23:20:58
updated: 2026-08-11T20:31:31
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Align skill_doctor's scope-failure reporting with its resolver

## Goal

`skill_doctor` describes its scope resolver's failures accurately and routes
each one to the remedy that fits it. Two behaviours change for the user: a
repository with no `plugins/*/skills/` tree gets told its layout is absent
whichever scope mode was asked for, and a genuine unknown-name failure keeps
the candidate-naming remedy it has today.

## Context

`<scope_resolution>` in `plugins/ai_dev/skills/skill_doctor/SKILL.md` states
`Each of its three failures needs the user to settle it` and then names three:
an unknown skill or family name, a selector path that escapes the repo root,
and a request that names no clear scope mode. `scripts/resolve_scope.py`
reaches `die(` on seven distinct conditions — `cannot read`,
`skill path not found:`, `skill path escapes repo root:`, `skill not found:`,
`no skills found for family token:`, `no skills found under plugins/*/skills/`,
and `root is not a directory:` — plus the argparse error when no mode is
given. So the enumeration understates the resolver and the skill has no
remedy for four of its exits.

The mis-routing follows from that gap. The same `<scope_resolution>` block
tells the skill that `When a repository exposes no plugins/*/skills/ tree` it
reports the absent layout and asks which tree to read, but only `resolve_all`
produces `no skills found under plugins/*/skills/`. Against a directory with
no `plugins/` tree, `--skill foo` exits 2 with `skill not found: foo` and
`--family foo` exits 1 with `no skills found for family token: foo`. Both
messages map to the unknown-name branch, whose remedy is naming the nearest
candidates the walk found, and an absent tree yields no candidates to name.
`discover_skills` already returns an empty list when `plugins` is not a
directory, so the absent-tree condition is available to every mode.

Related: [ai-dev_skill-doctor-agent-scope.md](ai-dev_skill-doctor-agent-scope.md)
rewrites the same `<scope_resolution>` block and may add its own resolver
mode, so the two coordinate on one file and one script.

## Approach

Rewrite the `Each of its three failures needs the user to settle it` passage
in place so it names the resolver's real failure classes and the remedy each
takes, replacing the three-item enumeration rather than extending it. Absorb
the unscoped follow-through that currently sits immediately after that
enumeration — `Name the nearest candidates the walk did find, then ask which
one the user means.` — into the unknown-name remedy only, so that sentence
does not remain as a blanket instruction after every failure class. Group
by remedy rather than by exit site: an absent expected layout asks which tree
to read, an unknown name names the nearest candidates the walk found, a
selector path fault reports the path and asks for a corrected one, and an
environment or usage fault (an unreadable `SKILL.md`, a `--root` that is not a
directory, or argparse rejecting a request that names no scope mode) reports
the fault itself instead of asking the user to disambiguate a name.

Make the absent-layout condition a first-class resolver failure so `--skill`
(name or path), `--family`, and `--all` emit one message. Detect it in
`resolve_scope.py` before mode dispatch when `discover_skills(root)` returns
empty, and exit with the existing `--all` text
`no skills found under plugins/*/skills/`, keeping `skill not found:` and
`no skills found for family token:` for the case where the tree exists and
the selector misses inside it.

**Out of scope:**

- Adding a scope mode for agents, which
  [ai-dev_skill-doctor-agent-scope.md](ai-dev_skill-doctor-agent-scope.md)
  owns.

## Acceptance

- `rg "three failures" plugins/ai_dev/skills/skill_doctor/SKILL.md` returns
  no match; `rg "Name the nearest candidates the walk did find"
  plugins/ai_dev/skills/skill_doctor/SKILL.md` returns no match; and
  `<scope_resolution>` carries one enumeration that names the resolver's
  failure classes with the remedy each takes, with candidate-naming stated
  only under the unknown-name class.
- Run against a staged directory holding no `plugins/` tree and against one
  whose `plugins/*/skills/` tree is empty, each of `--skill foo`,
  `--skill orphan/myskill`, `--family foo`, and `--all` prints
  `no skills found under plugins/*/skills/` and exits nonzero, and none of
  them prints `skill not found:` or `no skills found for family token:`.
- Run against this repository, `--skill omega_flange` still prints
  `skill not found: omega_flange` and `--family omega` still prints
  `no skills found for family token: omega`, so a selector that misses inside
  a present tree keeps the unknown-name remedy.
- `tests/skill_doctor/script_tests/run.sh` gains scenarios covering the
  absent-tree case (missing `plugins/` and empty `plugins/*/skills/`) for
  `--skill` name form, `--skill` path form, `--family`, and `--all`, plus
  the unknown-name case inside a present tree, and the suite passes with
  every scenario reported.
