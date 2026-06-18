# ai_dev

A plugin bundling the skills used for day-to-day AI-assisted development: keeping git history and changelogs clean, writing and formatting AI-consumed instructions, keeping bundled skill/plugin runtime artefacts portable, and applying per-language style conventions.

## Skills

### Git history

- **git_commit**: stage all new files and create one commit that captures the intended repository state, following project commit-message conventions.
- **update_changelog**: create or update a day-grouped `CHANGELOG.md` from git history — newest-first sections with status markers (`[active]`, `[changed later]`, `[superseded]`), processed one day at a time to stay within context limits.

### Work tracking

- **task**: manage upcoming work and todos as plain-markdown task files under `tasks/` at the project root, with `tasks/archive/` for `finished` and `deferred` items. Atomic per task, split at 300 lines, status/location enforced by a bundled linter; a filesystem-native backlog that lives next to the code.

The single-task siblings run in lifecycle order — **create → check → select → implement → audit → finish**:

- **task_create**: focused on-ramp that creates exactly one well-formed task file fast, deferring the naming, frontmatter, body, and lint rules to the `task` skill. Use it when a single "make a task for X" should load a narrow surface instead of the whole backlog workflow.
- **task_check**: assess whether one task is ready to build — judge it against a readiness checklist (structure, scope sizing, focus, complexity, contradictions, ambiguity) and report a General assessment plus a ranked Issues list. Read-only gate *before* building, ported from staged-spec's `spec_check`.
- **task_select**: choose what to work on next from the live backlog — filter eligible tasks, detect dependency and ordering relationships, rank by impact, implementation complexity, friction, and viable bug-fix priority, then recommend one unblocked task plus its natural next action. Read-only selection helper between readiness and implementation.
- **task_implement**: take one existing task file and carry it to done — read it, load the repo guardrails, build on the existing code, write the tests, run the suite clean, and confirm every acceptance item. It does the work and leaves verification to `task_audit` and close-out to `task_finish`.
- **task_audit**: verify one task's claimed completion against the actual codebase — confirm every body item, acceptance check, and backing test, run the suite, and report a verdict (clean, or ordered gaps with fixes). Read-only gate ported from staged-spec's `spec_audit`; hands a clean pass to `task_finish` and gaps to `task_implement`.
- **task_finish**: close out one task — set its status to `finished` or `deferred`, bump `updated`, `git mv` it to `archive/`, re-point the links the move touches, and re-lint. The action counterpart to the read-only `task_audit` gate; owns both the finished and deferred closures and defers the five close-out steps to the `task` skill.

Standing apart from that flow:

- **task_fix**: audit and repair the whole `tasks/` tree in one inline pass (orient → assess → remediate → verify) — run the linter, auto-fix mechanical findings (naming, frontmatter, status/location, links, datetimes), and surface judgement calls (splits, cross-task contradictions) for review. The task-backlog analogue of `wiki_fix`, done inline rather than via an agent. Operates on the whole backlog, independent of any single task's lifecycle.

### AI instructions

- **ai_instruction_writing**: write AI-consumed content (SKILL.md, .mdc rule files, CLAUDE.md / AGENTS.md / GEMINI.md, prompt templates, system prompts, commands, agent and sub-agent definitions, instruction sets, persona definitions) using positive, action-oriented language as the primary carrier of every instruction.
- **ai_instruction_formatting**: organize AI-consumed content into pseudo-XML by wrapping each semantic concern in a dedicated tag for role, policy, inputs, and output contract.

### Harness portability

- **harness_portability**: apply cross-agent-harness and cross-OS portability rules when creating or editing scripts, hooks, MCP helpers, command wrappers, setup flows, or execution/configuration wording bundled inside skills and plugins. Keeps OpenAI Codex and Anthropic Claude compatibility, official provider documentation checks, and macOS/Linux behavior in scope.

### Code and document formatting

- **format_markdown**: apply markdown linting compliance and best practices when creating or editing `.md` / `.mdc` files — blank-line rules around block elements, consistent bullet style, fenced code blocks with language tags, table alignment, header progression, list indentation, and link conventions.
- **format_python**: apply formatting standards, code-quality rules, structure conventions, and linting prevention when generating or editing Python — aligned with flake8, ruff, and pylint.
- **format_rust**: apply clippy-aligned Rust practices when writing or editing `.rs` — procedural flow, clippy-driven clarity improvements, minimal imports, Result/Option idioms, fallible builders with project error types, string prefix/suffix handling, borrowing clarity, iteration style, string building, and function signature grouping.
