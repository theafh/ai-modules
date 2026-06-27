# AI-Modules Charter

## Core Purpose

AI-Modules defines, packages, and ships reusable AI assistant components: skills,
agents, commands, hooks, and the deployment machinery that installs those
components into supported harnesses. The repository's product is the published
AI component artefact, not a demo workflow or an application built with those
components.

A change is on-charter when it improves the correctness, portability,
discoverability, maintainability, or packaging of those AI components, or when it
maintains the local task backlog that drives that work.

## DOES / DOES NOT Domain Boundaries

### DOES

- Define and maintain AI skills, agents, commands, hooks, helper scripts, plugin
  manifests, marketplace registrations, and deployment configuration.
- Keep task and knowledge-management components plain-file, repo-local, and
  portable across supported agent harnesses.
- Improve cross-harness behavior for OpenAI Codex, Anthropic Claude, Cursor,
  VS Code, Gemini, Antigravity, and future harnesses when the behavior is
  encoded in published components or deployment support.
- Maintain local backlog tasks and regression harnesses that verify published
  components.
- Document component behavior in the repository files that ship with or explain
  the components.

### DOES NOT

- Become an end-user application, hosted service, SaaS backend, analytics
  system, or product UI.
- Store project knowledge or task state in a database, remote service, hidden
  cache, or vendor-only format when a plain repository file can carry it.
- Treat generated chat transcripts, local harness state, or one developer's
  machine as the source of truth for shipped behavior.
- Add new package managers, runtimes, build systems, or deployment platforms
  unless a published component explicitly needs them and the repo rules allow
  the addition.
- Change a project's charter, task scope, or knowledge domain to make an
  autonomous edit appear valid.

## Key Invariants

- Published artefacts remain self-contained enough for a future AI agent to use
  them from the repository or from an installed plugin cache.
- Skill-family rules live in the family base skill when they govern the whole
  family; front-end skills inherit those rules instead of carrying divergent
  copies.
- Plugin metadata, local marketplaces, and documentation describe the same
  shipped component set.
- Helper scripts are bundled beside the skill, hook, command, or deployment
  surface that executes them, and they resolve paths from documented roots.
- Task files stay plain CommonMark with YAML frontmatter, one atomic work item
  per file, and lifecycle status matching their location.
- The Make plus shell plus Markdown toolchain remains the default maintenance
  surface for this repository.

## Intentional Constraints

- Prefer small, reviewable component changes over broad rewrites that alter
  several skill families or harness surfaces at once.
- Keep user-specific paths, credentials, machine-local assumptions, and private
  operational state out of published artefacts.
- Verify harness-specific behavior against current official provider
  documentation or record the verification gap in the artefact or change report.
- Preserve human review for changes to this charter by editing it only on
  `guardrail/charter-*` branches.
