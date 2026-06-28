# AI-Modules Charter

## Core Purpose

AI-Modules defines, packages, ships, and extends reusable AI assistant
components — skills, agents, hooks, and the deployment machinery that installs
them into supported harnesses. The repository's product is the published AI
component artefact. Building new components, modules, and plugins is as on-charter
as maintaining existing ones, and the product may grow to include companion
tooling that serves those components — for example a viewer for the task backlog
or the wiki — shipped alongside and depending on them.

This repository also runs on the components it ships: coding agents use the task,
wiki, and authoring tools here to build and extend those same tools. The
component is therefore both the product and the workflow. When a request could
mean either invoking a shipped component or editing its definition, confirm which
is intended before acting.

A change is on-charter when its real aim is to improve or extend the correctness,
portability, discoverability, maintainability, packaging, or runtime cost of
those AI components, or to maintain the local task backlog that drives that work —
where the named improvement is the change's actual purpose, not a label attached
to an edit that mainly serves something else.

This charter exists to keep unattended AI agents from drifting the project off its
declared purpose — turning a task to do X into Y, and Y into Z, with no human in
the loop. It is not a brake on progress. Humans set direction, including when and
how to expand the project; AI executes within the boundary the human set.

## DOES / DOES NOT Domain Boundaries

### DOES

- Define, maintain, and extend AI skills, agents, hooks, helper scripts, plugin
  manifests, marketplace registrations, and deployment configuration, including
  new components, modules, and plugins.
- Expose user-invocable entry points as thin skills, including thin wrappers that
  make an agent or a multi-step workflow invocable like a slash command. Treat a
  standalone command as a legacy, deprecated mechanism the deployer still installs
  but new work no longer adds.
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

- Become an unrelated end-user application, hosted service, SaaS backend,
  analytics system, or product UI. Companion tooling that serves the shipped
  components — such as a viewer for the task backlog or the wiki — stays
  on-charter when it ships alongside them and depends on them rather than standing
  in as a separate product.
- Store project knowledge or task state in a database, remote service, hidden
  cache, or vendor-only format when a plain repository file can carry it.
- Treat generated chat transcripts, local harness state, or one developer's
  machine as the source of truth for shipped behavior.
- Add new package managers, runtimes, build systems, or deployment platforms
  unless a published component explicitly needs them and the repo rules allow
  the addition.
- Widen the charter, the task scope, the knowledge domain, or any softer standing
  document to make an off-purpose edit appear valid. When an edit only becomes
  on-charter after such a widening, leave the target unchanged and surface it for
  a human. Recording already-on-charter work in a standing document is fine;
  supplying the authority for the edit that introduces it is not.

## Key Invariants

- The charter is the highest-order guardrail. Softer standing documents (for
  example ARCHITECTURE.md, FEATURES.md, TESTING.md) stay subordinate to it, never
  override it, and never supply the authority for an edit the charter would not
  bless. Any conflict or drift between a softer standing document and the charter
  is resolved in the charter's favor and reported for human review.
- An autonomous component keeps its audit, detection, and coverage scope intact
  when it optimizes for cost or speed: it adopts a cheaper mechanism only when
  that mechanism still surfaces every finding the prior one could. When a cheaper
  path would narrow coverage, gate a check behind a shortcut, or skip a check to
  save cost, it surfaces the tradeoff for human review rather than taking it
  silently.
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
- The default maintenance and deployment surface is Make plus standard Unix shell
  plus Markdown, with jq and git (required by the deployment script) and Python 3
  (shipped by helper scripts in the wiki, task, and formatting skills) as accepted
  standing dependencies.

## Intentional Constraints

- Prefer small, reviewable component changes over broad rewrites that alter
  several skill families or harness surfaces at once.
- Keep user-specific paths, credentials, machine-local assumptions, and private
  operational state out of published artefacts.
- Verify harness-specific behavior against current official provider
  documentation or record the verification gap in the artefact or change report.
- Preserve human review for changes to this charter by editing it only on
  `guardrail/charter-*` branches.
