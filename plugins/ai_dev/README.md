# ai_dev

A plugin bundling the skills used for day-to-day AI-assisted development: keeping git history and changelogs clean, writing and formatting AI-consumed instructions, and applying per-language style conventions.

## Skills

### Git history

- **git_commit**: stage all new files and create one commit that captures the intended repository state, following project commit-message conventions.
- **update_changelog**: create or update a day-grouped `CHANGELOG.md` from git history — newest-first sections with status markers (`[active]`, `[changed later]`, `[superseded]`), processed one day at a time to stay within context limits.

### AI instructions

- **ai_instruction_writing**: write AI-consumed content (SKILL.md, .mdc rule files, CLAUDE.md / AGENTS.md / GEMINI.md, prompt templates, system prompts, commands, agent and sub-agent definitions, instruction sets, persona definitions) using positive, action-oriented language as the primary carrier of every instruction.
- **ai_instruction_formatting**: organize AI-consumed content into pseudo-XML by wrapping each semantic concern in a dedicated tag for role, policy, inputs, and output contract.

### Code and document formatting

- **format_markdown**: apply markdown linting compliance and best practices when creating or editing `.md` / `.mdc` files — blank-line rules around block elements, consistent bullet style, fenced code blocks with language tags, table alignment, header progression, list indentation, and link conventions.
- **format_python**: apply formatting standards, code-quality rules, structure conventions, and linting prevention when generating or editing Python — aligned with flake8, ruff, and pylint.
- **format_rust**: apply clippy-aligned Rust practices when writing or editing `.rs` — procedural flow, clippy-driven clarity improvements, minimal imports, Result/Option idioms, fallible builders with project error types, string prefix/suffix handling, borrowing clarity, iteration style, string building, and function signature grouping.
