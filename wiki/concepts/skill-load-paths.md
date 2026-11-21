---
title: Skill load paths
created: 2026-10-01
updated: 2026-11-21
checked: 2026-08-13
type: concept
tags: [skill, discovery, frontmatter, portability, claude, codex]
sources: [raw/notes/delegation-probes-2026-10-04.md]
confidence: high
---

# Skill load paths

## Definition

A skill load path is the code a harness runs to find a skill file, load it, and
register the name it routes under. Its checks decide which faults actually stop
a skill. A requirement the load path leaves unchecked, such as a `version:` field
or a `name:` that matches its directory, is a repository convention rather than
a harness constraint.

Two load paths have been read out of installed builds, those of
[Anthropic Claude Code](../entities/anthropic-claude-code.md) and
[OpenAI Codex](../entities/openai-codex.md), and they enforce different things.
Skill facts for the other harnesses stay on their entity pages.
[Skill family architecture](skill-family-architecture.md) takes its auditor's
severity lines from the Claude path, so a change recorded here can move those
lines.

## Current state of knowledge

### Claude Code

These mechanics govern whether a skill file is found, loaded, and routable. All
were read on 13 August 2026 out of the installed Claude Code build 2.1.226
and its desktop counterpart 2.1.227, which agree, and they are the load path's
own code rather than documentation about it.

The skill filename is matched **case-insensitively** against the pattern
`skill.md` over the file's basename, so `SKILL.md`, `skill.md`, and `Skill.md`
all load. When one directory holds more than one file matching that pattern, the
loader takes the first and logs `Multiple skill files found in <dir>, using
<name>`, which makes the file it loads a matter of directory order rather than
of authorial intent.

A plugin skill is read through a guard that stats the path and requires a
**regular file no larger than 1048576 bytes**, one mebibyte. Failing either
condition the loader skips the skill entirely and warns `Skipping plugin skill
<path>: not a regular file or exceeds <N> byte limit`, interpolating the limit
from its own constant. The stat follows symbolic links, so a symlink resolving to
a regular file loads normally and only a broken link, a link to a directory, or a
non-regular file trips the guard. A frontmatter the parser cannot destructure
fails separately with `Failed to load skill from <path>: <error>`.

The name a skill is **registered and routed under** is its frontmatter `name:`
when that field is a non-empty string, falling back to the containing
directory's basename only otherwise. The result is sanitised by replacing every
character outside `[a-zA-Z0-9_-]` with a hyphen, then namespaced as
`<plugin>:<skill>`. A `name:` disagreeing with its directory therefore loads,
lists, and routes without complaint. The alignment this repository requires is
its own convention rather than a harness constraint, which is why
[skill family architecture](skill-family-architecture.md) records the auditor
reporting the mismatch below its blocking tier.

A skill's `version:` is read by no field that gates loading or routing. The
frontmatter key is recognised, and every schema that accepts it marks it
optional, so a skill with no `version:` loads and activates normally. Any
requirement for the field is a repository convention.

### Codex

Read on 13 August 2026 out of the installed CLI binary, `codex-cli
0.147.0-alpha.6.5`. That binary ships off `PATH` inside the ChatGPT desktop
application, which [OpenAI Codex](../entities/openai-codex.md) records together
with the lookups it defeats.

Codex splits skill validation from skill loading, and the two enforce different
things. The skill-creation and install tooling requires `name` and `description`
in `SKILL.md` frontmatter and validates every key against a closed allowlist of
`name`, `description`, `license`, `allowed-tools`, and `metadata`, rejecting
anything else with an `Unexpected key(s) in SKILL.md frontmatter` error. The
runtime loader is tolerant of what that allowlist rejects: skill files placed
under `skills/` by direct copy carrying keys outside the allowlist (`version`,
`author`) load and run. A skill's `version:` is therefore not merely unread here,
it is outside the tooling's allowlist entirely, while still tolerated at load
time. The skill's name comes from frontmatter, with the tooling offering a name
override that "defaults to SKILL.md frontmatter"; no equality between the name
and its directory is enforced.

At the listing layer the runtime truncates skill metadata to fit a skills
context budget, omits a skill whose metadata is too large to list, and caps the
`/skills` scan at a traversal limit. Each is visible in the binary's own strings
(`truncated skill metadata to fit skills context budget`, `Some skills were
omitted because their metadata is too large.`, `/skills scan reached its
traversal limit`).

One negative is worth recording because a task in this repository asserted the
opposite: the per-file loader messages the Claude Code build emits appear nowhere
in the Codex binary. Those messages are `Skipping plugin skill <path>: not a
regular file or exceeds <N> byte limit`, `Multiple skill files found`, and
`Failed to load skill from`. That message family, and the one-mebibyte
plugin-skill byte limit it names, belong to the Claude Code load path above.
Codex's tooling resolves the exact uppercase `SKILL.md` spelling.

A live probe of build 0.160.0 on 4 October 2026 watched how a project skill
behaves at run time ([probes](../raw/notes/delegation-probes-2026-10-04.md)).
The probe trusted the project for that run with
`-c 'projects."<dir>".trust_level="trusted"'`. Codex then discovered and loaded
a skill at `.agents/skills/<name>/SKILL.md` in the project, and the model read
the skill's `SKILL.md` through a shell `cat` command.

## Open questions

Whether the Codex runtime matches the skill filename case-insensitively, as the
Claude loader does, is unverified.

## Related concepts

- [Skill family architecture](skill-family-architecture.md), whose auditor takes
  its blocking tier from the Claude load path.
- [Agent definition portability](agent-definition-portability.md), which asks
  the same tolerance question of agent files.

## Derived from

- The skill load path read out of installed Claude Code builds 2.1.226 and
  2.1.227 on 13 August 2026.
- The `codex-cli 0.147.0-alpha.6.5` binary bundled in the ChatGPT desktop
  application, read on 13 August 2026.
