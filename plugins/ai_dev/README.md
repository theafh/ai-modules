# ai_dev

A plugin of skills and agents for day-to-day AI-assisted development: keeping git history and changelogs clean, writing and formatting the instructions an AI reads, keeping bundled skill and plugin runtime artefacts portable across agents and operating systems, and applying per-language style conventions.

## Skills

### Git history

- **git_commit**: stage new files and create one commit that captures the intended repository state, following the project's commit-message conventions.
- **update_changelog**: build or update a day-grouped `CHANGELOG.md` from git history. It writes newest-first immutable day sections with `- **Category:** Plain-English summary.` entries, and hands large per-day context through a readable file path so long histories stay consumable.

### Work tracking

- **task**: manage upcoming work and todos as plain-Markdown files under `tasks/` at the project root, with `tasks/archive/` for `finished` and `deferred` items. One item per task, split at 300 lines, with status and location enforced by a bundled linter. It is a backlog that lives in the filesystem next to the code.

Running a task from skill to skill, instead of handing one prompt to a single implementer, removes the ambiguity that implementer would otherwise resolve silently and wrongly. A one-shot agent fills every underspecified corner with plausible filler that reads right but isn't what you meant. Whatever you leave open to misreading, it misreads, and differently each time. Each gate below catches a different kind of gap before it reaches code: creation forces naming, frontmatter, and structure to be explicit; `task_check` names scope problems and contradictions; `task_select` surfaces ordering and dependencies; and `task_audit` checks the result against the brief. Formatting the work and checking it for consistency at each step makes those gaps visible, so you close them on purpose instead of leaving them to be filled with generic guesses later.

The single-task siblings run in lifecycle order, **create → check → select → implement → audit → finish**, with `task_auto_check` available as an opt-in readiness repair loop between create/check and selection:

- **task_create**: a focused on-ramp that quickly creates exactly one well-formed task file, leaving the naming, frontmatter, body, and lint rules to the `task` skill. Use it when a single "make a task for X" should load a narrow surface instead of the whole backlog workflow.
- **task_check**: decide whether one task is ready to build. It judges the task against a readiness checklist (structure, scope sizing, focus, complexity, contradictions, ambiguity) and reports a General assessment plus a ranked Issues list. A read-only gate *before* building, ported from staged-spec's `spec_check`.
- **task_auto_check**: drive one task toward readiness automatically while keeping `task_check` as the only readiness gate. It freezes the task's original goal, asks `auto_gate_task`, `auto_reviewer_task`, and `auto_verifier_task` for gated issue reports, repair proposals, and intent-safe approvals, applies only verified minimum edits, and stops at `ready` or a surfaced stuck state.
- **task_select**: choose what to work on next from the live backlog. It filters eligible tasks, finds dependencies and ordering, ranks by impact, implementation complexity, friction, and viable bug-fix priority, then recommends one unblocked task and its natural next action. A read-only step between readiness and implementation.
- **task_implement**: take one existing task file and carry it to done. It reads the task, loads the repo guardrails, builds on the existing code, writes the tests, runs the suite clean, and confirms every acceptance item. It does the work and leaves verification to `task_audit` and close-out to `task_finish`.
- **task_audit**: check one task's claimed completion against the actual codebase. It confirms every body item, acceptance check, and backing test, runs the suite, and reports a verdict (clean, or ordered gaps with fixes). A read-only gate ported from staged-spec's `spec_audit`; it hands a clean pass to `task_finish` and gaps to `task_implement`.
- **task_finish**: close out one task. It sets the status to `finished` or `deferred`, bumps `updated`, runs `git mv` to move the file to `archive/`, re-points the links the move touches, and re-lints. The action counterpart to the read-only `task_audit` gate; it owns both the finished and deferred closures and leaves the five close-out steps to the `task` skill.

Standing apart from that flow:

- **task_fix**: audit and repair the whole `tasks/` tree in one pass (orient → assess → remediate → verify). It runs the linter, auto-fixes mechanical findings (naming, frontmatter, status/location, links, datetimes), and surfaces judgement calls (splits, cross-task contradictions) for review. The task-backlog version of `wiki_fix`, done inline rather than through an agent. It works on the whole backlog, independent of any single task's lifecycle.

### AI instructions

- **ai_instruction_writing**: write content an AI reads (SKILL.md, .mdc rule files, CLAUDE.md / AGENTS.md / GEMINI.md, prompt templates, system prompts, commands, agent and sub-agent definitions, instruction sets, persona definitions) using positive, action-oriented language as the primary carrier of every instruction.
- **ai_instruction_formatting**: organize content an AI reads into pseudo-XML, wrapping each semantic concern (role, policy, inputs, output contract) in its own tag.

### Harness portability

- **harness_portability**: apply portability rules (across agent harnesses and operating systems) when creating or editing scripts, hooks, MCP helpers, command wrappers, setup flows, or execution and configuration wording bundled inside skills and plugins. It covers OpenAI Codex and Anthropic Claude compatibility, checks against official provider docs, and macOS/Linux behaviour.

### Code and document formatting

- **format_markdown**: apply markdown linting rules and best practices when creating or editing `.md` / `.mdc` files: blank lines around block elements, consistent bullet style, fenced code blocks with language tags, table alignment, header progression, list indentation, and link conventions.
- **format_python**: apply formatting standards, code-quality rules, structure conventions, and lint-prevention practices when writing or editing Python, aligned with flake8, ruff, and pylint.
- **format_rust**: apply clippy-aligned Rust practices when writing or editing `.rs` files: procedural flow, clippy-driven clarity improvements, minimal imports, Result/Option idioms, fallible builders with project error types, string prefix/suffix handling, clearer borrowing, iteration style, string building, and grouped function signatures.

## Agents

- **auto_gate_task**: wraps `task_check` for `task_auto_check` and returns a compact structured verdict: final status, ready boolean, issue list, and evidence labels.
- **auto_reviewer_task**: proposes minimum task-body repairs from one assigned stance, citing the base `task` skill's `<body>` repair rules and preserving the frozen task intent.
- **auto_verifier_task**: verifies reviewer proposals with a refute-by-default stance, keeping only real, minimum, issue-resolving, frozen-intent-preserving edits for the orchestrator to apply.
