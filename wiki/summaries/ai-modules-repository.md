---
title: The ai-modules repository
created: 2026-08-08
updated: 2026-08-09
type: summary
tags: [repo-structure, plugin, skill, agent, deployment]
sources: []
confidence: high
---

# The ai-modules repository

## Topic and scope

ai-modules is a meta-repository. Its product is the published AI component
artefact: skills, agents, hooks, output styles, plugin manifests, marketplace
registrations, and the deployment machinery that installs all of it into agent
harnesses. It ships no end-user application, though it does contain real programs: the
bundled linters and the deploy script are substantial code, and they are
tooling that serves the components rather than products of their own. Every
`SKILL.md`, `plugin.json`, and `marketplace.json` is a shipped file, and an edit
propagates to every machine that re-runs the deploy.

The repository also runs on the components it ships. Coding agents working here
use the task backlog, this wiki, and the authoring skills to build and extend
those same tools. The component is both the product and the workflow, which is
why a request to "apply the task skill" is ambiguous until someone says whether
they mean invoking it or editing its definition.

This page is the orientation page. Packaging and versioning have their own page
in [plugin packaging and versioning](../concepts/plugin-packaging-and-versioning.md),
naming and family structure in
[skill family architecture](../concepts/skill-family-architecture.md), and
installation in [the deployment model](../concepts/deployment-model.md).

## Key findings by sub-topic

### What the repository contains

Two plugins hold everything. `ai_dev` carries the day-to-day development
surface: the git skills, the changelog skill, the whole `task_*` family and its
five `auto_*_task` agents, the guardrail pair, the two AI-instruction authoring
skills, the three language formatting skills, and the portability skill.
`knowledge_management` carries the `wiki` family and its `auto_shaper_wiki`
agent, plus `executive_summary` and `spr`.

Around the plugins sit the marketplace registrations, one for Claude under
`.claude-plugin/` and one for Codex under `.agents/plugins/`, the `deployment/`
directory, the `tasks/` backlog, the `styles/` directory holding the tracked
output styles, a local-only test tree, and the repo-root instruction and
guardrail files. `styles/` is the one artefact source that sits outside
`plugins/`, deliberately, so that
[the deployment model](../concepts/deployment-model.md) reaches it without
Claude's plugin discovery also picking it up.

### The two knowledge systems it ships, and now uses

The repository's own README frames task and wiki as answers to the same problem,
which is the distance between what a person means and what an agent rebuilds
from it. Task narrows that distance for the work by forcing each gap to surface
during a create, check, implement, audit, finish lifecycle. Wiki narrows it for
the knowledge by having the agent write what it learned and the human correct
the page when it reads wrong.

Until August 2026 the repository dogfooded only one of the two. `tasks/` has
been live for a long time and the guardrail documents are in place, while the
wiki family was designed and maintained here against instances that lived in
other repositories. This wiki closes that gap, and it exists for its own sake as
well: the harness research had grown past what a shipped skill should carry.

### Toolchain

The toolchain is deliberately small. The charter states it exactly: Make plus
standard Unix shell plus Markdown, with `jq` and `git` required by the deploy
script and Python 3 shipped by helper scripts in the wiki, task, and formatting
skills, all four accepted as standing dependencies. The repo-root instruction
files compress that to Make, shell, and Markdown, which reads as a rule about
what to add rather than a complete inventory of what is in use. Python is not a
footnote to that list: inside the plugins tree it carries more executable code
than shell does, and shell only leads repo-wide because the deploy script is
written in it.

`make lint` runs `markdownlint`, a `jq` syntax check, and `shellcheck`; `make
fix` auto-fixes Markdown only; `make deploy` installs; `make uninstall` reverses
a deploy from its log. New languages, package managers, and build steps get added
only when the maintainer asks for them, which keeps the repository readable by
the same agents that consume it.

### Authoring conventions

Skill prose is written as pseudo-XML, with each semantic concern in its own tag,
and in positive action-oriented language. Those two rules are themselves shipped
skills, `ai_instruction_formatting` and `ai_instruction_writing`, so the
repository's house style and its product are the same thing. A skill
description serves two audiences at once: a human browsing a list, and an LLM
router deciding whether to load the body.

Cross-references between artefacts are written by name rather than by plugin,
marketplace, or installed path, because a published skill lands on machines
whose directory layout the author cannot see.

### The wiki's place beside the other document sets

The repo-root guardrail documents and instruction files exist to keep a coding
agent anchored while it executes a task without a human watching. A skill that
reaches a stage where one of the guardrail docs applies goes looking for the file
and applies what it finds, and their job is to constrain the work in progress.
This wiki is read by an agent that stepped out of the work to research, and its
job is to inform. Both audiences are the same LLM coding agents, which is why the
two sets look similar on the page and do different work. What a guardrail
document is, and why its statements are rules rather than descriptions, is
[guardrail documents as normative rules](../concepts/guardrail-documents-as-rules.md).

Overlap between them is expected and fine. What must not happen is a rule living
in two places and drifting, so a rule that governs execution stays in the
guardrail or the skill, and the evidence and derivation behind it come here. The
routing rule is [deciding where knowledge belongs](../procedures/deciding-where-knowledge-belongs.md).

## Open threads

The wiki is new, so the coverage is uneven by design: the harness research is
deep because it was migrated wholesale, while the repository's own procedures
are thin because the instruction files already state them as rules.

Whether the wiki earns its keep is an open question with a concrete test. If a
piece of harness work six months from now starts by reading a page here instead
of re-deriving from provider documentation, it worked.

## Derived from

- `README.md`, `CLAUDE.md`, `AGENTS.md`, and `CHARTER.md` at this repository root.
- `deployment/README.md` for the install surface.
