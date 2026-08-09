# ai_dev

A plugin of skills and agents for day-to-day AI-assisted development: keeping git workflows and changelogs clean, writing and formatting the instructions an AI reads, keeping bundled skill and plugin runtime artefacts portable across agents and operating systems, and applying per-language style conventions.

## Skills

### Git

- **git_commit**: stage new files and create one commit that captures the intended repository state, following the project's commit-message conventions.
- **git_refresh**: refresh the current repository to its detected default branch, fast-forward it only when safe, delete cleanly merged local branches, and offer upstream-gone or force-delete cleanup only behind explicit opt-in.
- **update_changelog**: build or update a day-grouped `CHANGELOG.md` from git history. It writes newest-first immutable day sections with `- **Category:** Plain-English summary.` entries, and hands large per-day context through a readable file path so long histories stay consumable.

### Preparing work for implementation

The `task_*` family prepares one work item at a time to single-shot implementation readiness for an AI agent, with the human in the loop as the driver and sense-maker — more than a record that work exists.

- **task**: manage upcoming work and todos as plain-Markdown files under `tasks/` at the project root, with `tasks/archive/` for `finished` and `deferred` items. One item per task, split at 300 lines, with status and location enforced by a bundled linter. It is a backlog that lives in the filesystem next to the code.

Running a task from skill to skill, instead of handing one prompt to a single implementer, removes the ambiguity that implementer would otherwise resolve silently and wrongly. A one-shot agent fills every underspecified corner with plausible filler that reads right but isn't what you meant. Whatever you leave open to misreading, it misreads, and differently each time. Each gate below catches a different kind of gap before it reaches code: creation forces naming, frontmatter, and structure to be explicit; `task_check` names scope problems and contradictions; and `task_audit` checks the result against the brief. Formatting the work and checking it for consistency at each step makes those gaps visible, so you close them on purpose instead of leaving them to be filled with generic guesses later.

For orientation rather than gating, `task_explain` gives a compact what/why/how readout of one live or archived task without editing it.

The lifecycle spine runs **create → check → implement → audit → finish**, with `task_auto_check` available as an opt-in readiness repair loop:

- **task_create**: a focused on-ramp that quickly creates exactly one well-formed task file, leaving the naming, frontmatter, body, and lint rules to the `task` skill. Use it when a single "make a task for X" should load a narrow surface instead of the whole backlog workflow.
- **task_auto_check**: automatically drive one task to the `ready` status, reusing the read-only `task_check` gate — the readiness check *before* building — as the only readiness bar. `task_check` judges a task against a readiness checklist (structure, premise, approach fitness, scope sizing, focus, complexity, contradictions, ambiguity), reports a `# General assessment` paragraph plus a ranked `## Issues` list, and stamps `ready` when clean or `checked` when blocking issues remain. The loop freezes the task's title and goal, runs its helper agents for a committed-intent check, gated issue reports, repair proposals, and intent-safe approvals, then applies only verified minimum edits and stops at `ready` or a surfaced stuck state.
- **task_implement**: take one existing task file and carry it to done. It reads the task, loads the repo guardrails, builds on the existing code, writes the tests, runs the suite clean, and confirms every acceptance item. It does the work and leaves verification to `task_audit` and close-out to `task_finish`.
- **task_audit**: check one task's claimed completion against the actual codebase. It confirms every body item, acceptance check, and backing test, runs the suite, and reports a verdict (clean, or ordered gaps with fixes). A read-only gate; it hands a clean pass to `task_finish` and gaps to `task_implement`.
- **task_finish**: close out one task. It sets the status to `finished` or `deferred`, bumps `updated`, runs `git mv` to move the file to `archive/`, re-points the links the move touches, and re-lints. The action counterpart to the read-only `task_audit` gate; it owns both the finished and deferred closures and leaves the six close-out steps to the `task` skill.

Three tools sit beside the spine rather than on it:

- **task_select**: recommend what to work on next from the live backlog — the task that most advances the project — without editing anything. It filters eligible tasks at any status, weighs dependencies and ordering, ranks by impact, implementation complexity, friction, and viable bug-fix priority, then names one task and its natural next action, which may be a check pass before implementation. Skippable for a single-task run and leaned on for a larger backlog.
- **task_explain**: explain one task at a high level without editing it. It resolves one live or archived task, names its status and scope, and gives a compact what/why/how readout so a reader can orient before choosing a lifecycle action.
- **task_fix**: audit and repair the whole `tasks/` tree in one pass (orient → assess → remediate → verify). It runs the linter, auto-fixes mechanical findings (naming, frontmatter, status/location, links, datetimes), and surfaces judgement calls (splits, cross-task contradictions) for review by default. On explicit opt-in or confirmed scale, it escalates those calls to `auto_shaper_task`, the single serialized writer for that run. It works on the whole backlog, independent of any single task's lifecycle.

### Guardrail documents

- **guardrail**: the hub and source of truth for the repo-root guardrail docs — `CHARTER.md`, `ARCHITECTURE.md`, `TESTING.md`, `SECURITY.md` — that keep AI agents anchored to human intent across sessions. It explains the doc set, the authority hierarchy (charter → domain guardrails → harness rule files), the shared format contract, and the presence-gated consumption convention the task family already follows; it assesses a repository's nature and suggests which guardrails fit it, grounded in how the repo actually works; and it drafts a doc only on explicit user request, marking open decisions and surfacing creation-time divergences instead of guessing. Bundled references carry the general template and rules for each doc type, so sibling skills wire the hub in rather than duplicating them.
- **guardrail_audit**: the read-only audit sibling. It surfaces doc-vs-doc contradictions and doc-vs-code divergences among the docs that already exist, ranked by the hub's hierarchy, plus grounded missing-doc proposals where repo substance warrants an absent type. Every finding carries evidence and a reconcile recommendation; the run edits nothing and ends by asking how to proceed. Use it when retrofitting a guardrail into a mature repo or health-checking whether existing docs still match the code.

### AI instructions

- **ai_instruction_writing**: write content an AI reads (SKILL.md, .mdc rule files, CLAUDE.md / AGENTS.md / GEMINI.md, prompt templates, system prompts, commands, agent and sub-agent definitions, instruction sets, persona definitions) using positive, action-oriented language as the primary carrier of every instruction.
- **ai_instruction_formatting**: organize content an AI reads into pseudo-XML, wrapping each semantic concern (role, policy, inputs, output contract) in its own tag.

### Harness portability

- **harness_portability**: apply portability rules (across agent harnesses and operating systems) when creating or editing scripts, hooks, MCP helpers, command wrappers, setup flows, or execution and configuration wording bundled inside skills and plugins. It covers OpenAI Codex and Anthropic Claude compatibility, checks against official provider docs, and macOS/Linux behaviour.

### Code and document formatting

- **format_markdown**: apply markdown linting rules and best practices when creating or editing `.md` / `.mdc` files: blank lines around block elements, consistent bullet style, fenced code blocks with language tags, table alignment, header progression, list indentation, and link conventions.
- **format_python**: apply formatting standards, code-quality rules, structure conventions, and lint-prevention practices when writing or editing Python, aligned with flake8, ruff, and pylint.
- **format_rust**: apply clippy-aligned Rust practices when writing or editing `.rs` files: procedural flow, clippy-driven clarity improvements, minimal imports, Result/Option idioms, the error-versus-invariant model with panic discipline and clippy unwrap_used enforcement, fallible builders following the error idiom by consumer, string prefix/suffix handling, clearer borrowing, iteration style, string building, and grouped function signatures.

## Agents

- **auto_drift_task**: reconstructs a task's earliest committed title and Goal for `task_auto_check`, classifies meaning-level drift, and returns recovered-versus-current evidence without editing files.
- **auto_gate_task**: wraps `task_check` for `task_auto_check` and returns `task_check`'s full report followed by a structured verdict derived from it: final status, prior status, ready boolean, per-item checklist record, issue list, and evidence labels.
- **auto_reviewer_task**: proposes minimum task-body repairs from one assigned stance, citing the base `task` skill's `<body>` repair rules and preserving the frozen task intent.
- **auto_verifier_task**: verifies reviewer proposals with a refute-by-default stance, keeping only real, minimum, issue-resolving, frozen-intent-preserving edits for the orchestrator to apply.
- **auto_shaper_task**: resolves `task_fix`'s escalated whole-tree judgement calls as the lone writer, applying verified splits, body-framing reframes, scope relocations, and link repairs while preserving frozen task goals and optional `CHARTER.md` boundaries.

## Hooks

- **charter_guardrail**: protects a repository's root `CHARTER.md` by allowing charter edits only on `guardrail/charter-*` branches. Claude loads it through plugin-root `hooks/hooks.json`; Codex loads a Codex-native plugin hook config from `hooks/codex-plugin-hooks.json` after hook trust review, while `hooks/codex-custom-deploy-hooks.json` feeds explicit config-layer deployment outside plugin installs; Antigravity uses `hooks/antigravity-hooks.json` for explicit config-layer deployment.
