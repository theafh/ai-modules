# ai-modules

A collection of professional AI skills, agents, commands, and hooks. The same source of truth ships through several equal paths. You can install it from the bundled Claude Code marketplace, symlink it into vendor config dirs globally with `make deploy` (VS Code Copilot, Cursor, Claude Code, OpenAI Codex, Gemini CLI, Google Antigravity), symlink it into a single repo's local config via `--project-dir`, or use it in-place from a checkout. The deployment script discovers artefacts by plugin layout and installs them where each tool expects them.

## Layout

```text
ai-modules/
├── .claude-plugin/
│   └── marketplace.json     # registers the plugins below as a Claude marketplace
├── plugins/                 # one subdirectory per plugin
│   ├── knowledge_management/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── .codex-plugin/plugin.json
│   │   ├── README.md
│   │   ├── agents/          # one .md file per agent
│   │   │   └── wiki_auto_shaper.md
│   │   └── skills/          # one subdirectory per skill, each with SKILL.md
│   │       ├── wiki/
│   │       ├── wiki_wrapup/
│   │       ├── wiki_import/
│   │       ├── wiki_fix/
│   │       ├── executive_summary/
│   │       └── spr/
│   └── ai_dev/
│       ├── .claude-plugin/plugin.json
│       ├── .codex-plugin/plugin.json
│       ├── README.md
│       └── skills/
│           ├── git_commit/
│           ├── update_changelog/
│           ├── task/
│           ├── task_create/
│           ├── task_implement/
│           ├── task_finish/
│           ├── ai_instruction_writing/
│           ├── ai_instruction_formatting/
│           ├── format_markdown/
│           ├── format_python/
│           └── format_rust/
└── deployment/              # deployment script for installing artefacts globally or per-project
    ├── deployment.sh
    ├── deployment.conf
    └── README.md
```

## Plugins

Each skill is a written procedure the model loads when its trigger fires. Bundling deterministic helpers (bash and python scripts, linters, schema files) alongside the prose lets the agent offload mechanical work to programs that can't hallucinate, and follow a written workflow instead of re-deriving one each session. The practical effect is fewer turns per task, smaller context per turn, and more consistent output across runs. On metered models, that translates directly into time and tokens saved.

### knowledge_management

Skills and agents for building, maintaining, and distilling a persistent, compounding knowledge base. Everything is plain markdown, readable in any editor or CLI, with no Obsidian or vendor reader required.

The wiki itself plus paired front ends that wrap two of its workflows so the model has a single named entry point per use case:

- **wiki**: the foundation. Builds and maintains an interlinked markdown wiki — ingest URLs, articles, papers, PDFs, transcripts, meeting notes, internal notes, and pastes; query, lint, audit, archive, and reorganise. The page-type enum (`entity`, `concept`, `comparison`, `summary`, `query`, `procedure`) is read from `SCHEMA.md`, so a wiki extends its taxonomy without touching the linter. Provenance is anchored by footnotes plus body-only `sha256` drift detection on raw sources. Discovery, init, lint, and the sha256 helper all ship as bundled scripts, so the agent runs deterministic programs for the mechanical parts instead of inventing them inline each session.
- **wiki_import** and **wiki_wrapup**: triage-first ingest pair. `wiki_import` takes one named resource (URL, file, paper, PDF, transcript, meeting note, internal note, or paste); `wiki_wrapup` takes the current chat session. Both capture the source, diff each candidate against the existing wiki, and emit a triage report (new pages, extensions, contradictions with both excerpts and concrete reconciliation options) before any wiki-page write lands. Approved writes route back through the `wiki` skill. Use them when "review what you'd change before changing it" matters — for example, after a research chat, or before importing a contested paper.
- **wiki_fix** and **wiki_auto_shaper** *(agent)*: paired audit-and-repair. `wiki_fix` is the one-shot skill wrapper; `wiki_auto_shaper` is the agent it hands off to. The agent runs a two-phase loop — assess (lint plus semantic audit), then fix, then re-lint until clean. It repairs frontmatter and schema violations, broken links, off-taxonomy tags, oversized or topic-mixing pages, procedure pages leaking instance content, content that drifts from the per-type page anatomy, and surfaces cross-page contradictions via the contested-page protocol for human review rather than auto-resolving them.

Two distillation skills that operate on text outside the wiki:

- **executive_summary**: distills a document into structured prose at 10 to 15 percent of the original length, preserving the logic and reasoning chain rather than producing bullet-point keywords.
- **spr**: converts input text into a Sparse Priming Representation, a compact, markdown-structured set of non-overlapping, informationally dense priming statements designed to let a second LLM reconstruct the source without ever seeing it.

An LLM-wiki sits between a full RAG pipeline and a loose pile of notes. It is structured enough that an agent can navigate it by schema and links, and light enough that maintenance is just markdown edits. Knowledge is compiled once into durable pages instead of re-derived from raw chunks on every query, and as long as the wiki is kept current and reshaped over time, the trade-off between maintenance effort and inference cost is favourable. Living next to a repo, it gives an agent the persistent context it needs to plan work, remember decisions, and carry meta-knowledge across sessions, something a chat transcript cannot do.

### ai_dev

Skills for day-to-day AI-assisted development: keeping git history and changelogs clean, writing and formatting AI-consumed instructions, and applying linter-aligned style conventions at write time.

- **git_commit**: a phase-based commit workflow with a hardened prepare script that handles special-character paths and per-file binary detection. It stages changes, infers an intended commit grouping, and writes a message aligned with the project's existing convention. A sibling manual-fallback reference covers the path when the script can't be used.
- **update_changelog**: generates or refreshes a day-grouped `CHANGELOG.md` from git history. It produces newest-first day sections with status markers (`[active]`, `[changed later]`, `[superseded]`), and processes one day at a time so long histories stay within a single context window.
- **task**: project-local backlog of upcoming work as plain-markdown files under `tasks/` at the project root, with `tasks/archive/` for `implemented` and `deferred` items. Each task is written as a self-contained brief a single-shot AI coder could pick up and implement; the bundled linter enforces naming, frontmatter, status/location consistency, and a 300-line split threshold. Complementary to the `wiki` skill: tasks track *what is still to do*, the wiki captures *what is durably known*.
- **task_create**: a focused front end over `task` that creates exactly one well-formed task file with minimal ceremony, deferring the naming, frontmatter, body, and lint rules to the `task` skill rather than restating them. It gives a one-shot "make a task for X" a narrow, trigger-precise surface instead of loading the full backlog-management workflow.
- **task_implement**: implements one existing task file end-to-end via a strict read → load-guardrails → understand-codebase → implement → test → verify flow ported from staged-spec's `spec_implement`. It does the work and stops at a green suite, leaving codebase verification (`task_audit`) and close-out (`task_finish`) to its single-purpose siblings.
- **task_finish**: closes out one task — sets its status (`implemented` or `deferred`), bumps `updated`, `git mv`s it to `archive/`, re-points the cross-references the move touches, and re-lints. The action counterpart to the read-only `task_audit` gate, deferring the five close-out steps to the base `task` skill's `<archive>` workflow.
- **ai_instruction_writing**: writes any AI-consumed artefact (SKILL.md, `.mdc` rule files, `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, prompt templates, system prompts, commands, agent definitions) using positive, action-oriented language as the primary carrier of every instruction, instead of negative prohibitions the model has to invert.
- **ai_instruction_formatting**: organises AI-consumed content into pseudo-XML, wrapping each semantic concern (`<role>`, `<policy>`, `<input>`, `<output_contract>`) in a dedicated tag so the model can locate the right section by structure rather than by re-reading the prose.
- **format_markdown / format_python / format_rust**: linter-aligned style guides (`markdownlint`, `flake8` plus `ruff` plus `pylint`, `clippy`) consulted at write time. The point is to land code that already passes the linter, instead of spending a follow-up turn reacting to lint output.

## Make targets

Common workflows are wrapped in the [Makefile](Makefile):

```bash
make help        # list targets
make deploy      # deploy artefacts to global config dirs (aliases: global, install)
make uninstall   # remove previously deployed artefacts
make lint        # report lint issues across md / json / sh
make fix         # auto-fix lint issues where possible (markdown only)
```

For finer-grained control, call `deployment/deployment.sh` directly. See [deployment/README.md](deployment/README.md) for flags like `--dry-run`, `--target`, and `--project-dir`.

### Linting tools

`make lint` and `make fix` use `markdownlint-cli`, `jq`, and `shellcheck` (install via Homebrew on macOS).

Markdown rules live in [.markdownlint.jsonc](.markdownlint.jsonc); inline-HTML checks (`MD033`) are disabled because skill prompts use intentional pseudo-XML.
