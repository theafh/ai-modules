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

- **wiki**: builds and maintains an interlinked markdown wiki. Ingests URLs, articles, papers, PDFs, transcripts, meeting notes, internal notes, and pastes; supports query, lint, audit, archive, and reorganise flows. Page types (`entity`, `concept`, `comparison`, `summary`, `query`, `procedure`) are read from `SCHEMA.md`, so wikis extend the taxonomy without touching the linter. Provenance is anchored by footnotes plus `sha256` drift detection on raw sources. Discovery, init, and lint ship as bundled scripts.
- **wiki_wrapup**: session-end triage front end for the `wiki` skill. Mines the visible chat for durable knowledge, diffs each candidate against `$WIKI`, and emits a triage report (new pages, extensions, contradictions) with both excerpts and reconciliation options per contradiction. Approved writes route back through the `wiki` skill.
- **wiki_import**: single-resource triage front end for the `wiki` skill. Takes a specific URL, file, paper, PDF, transcript, meeting note, internal note, or paste, captures it as raw, then mines the captured raw and emits the same triage report shape as `wiki_wrapup` before any wiki-page write. The raw capture lands immediately; layer-2 writes (entity, concept, comparison, summary, query, procedure) wait for approval and route back through the `wiki` skill.
- **wiki_fix**: one-shot wrapper around the `wiki_auto_shaper` agent. Hands the audit-and-fix loop off to the agent and surfaces its final report. Use when the user asks to fix, repair, lint, audit, or health-check the wiki in one go without further interaction.
- **executive_summary**: distills a document into structured prose at 10 to 15 percent of the original length, preserving the logic and reasoning chain rather than producing bullet-point keywords.
- **spr**: converts input text into a Sparse Priming Representation, a compact, markdown-structured set of non-overlapping, informationally dense priming statements designed to let a second LLM reconstruct the source without ever seeing it.
- **wiki_auto_shaper** *(agent)*: an autonomous two-phase loop over the wiki of the current repo. The first phase assesses (lint plus semantic audit), then a fix loop runs until a re-lint comes back clean. It repairs frontmatter and schema violations, broken links, off-taxonomy tags, oversized or topic-mixing pages, procedure pages leaking instance content, content that drifts from the page-type anatomy, and surfaces cross-page contradictions via the contested-page protocol for human review.

An LLM-wiki sits between a full RAG pipeline and a loose pile of notes. It is structured enough that an agent can navigate it by schema and links, and light enough that maintenance is just markdown edits. Knowledge is compiled once into durable pages instead of re-derived from raw chunks on every query, and as long as the wiki is kept current and reshaped over time, the trade-off between maintenance effort and inference cost is favourable. Living next to a repo, it gives an agent the persistent context it needs to plan work, remember decisions, and carry meta-knowledge across sessions, something a chat transcript cannot do.

### ai_dev

Skills for day-to-day AI-assisted development: keeping git history and changelogs clean, writing and formatting AI-consumed instructions, and applying linter-aligned style conventions at write time.

- **git_commit**: a phase-based commit workflow with a hardened prepare script that handles special-character paths and per-file binary detection. It stages changes, infers an intended commit grouping, and writes a message aligned with the project's existing convention. A sibling manual-fallback reference covers the path when the script can't be used.
- **update_changelog**: generates or refreshes a day-grouped `CHANGELOG.md` from git history. It produces newest-first day sections with status markers (`[active]`, `[changed later]`, `[superseded]`), and processes one day at a time so long histories stay within a single context window.
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
