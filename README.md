# AI-Modules

A collection of professional AI skills, agents, commands, and hooks for AI-assisted development, packaged as plugins.

## Why You Should Install This

These plugins give an AI coding agent durable, file-native context that a chat session does not keep: a backlog of the work still to do, and a knowledge base of what the project has learned. Both live as plain CommonMark markdown on disk, so they stay greppable, diffable, versioned in git, and readable in any editor, with no database, SaaS, or proprietary reader in the loop.

**Task is an asynchronous backlog that lives with the code:** It works like Jira or Trello, but for AI agents. You fill it now and act on it later, and both filling it and reading it back are trivial for an agent. While you are deep in one change, you can fire off a newly spotted bug or idea as a task and keep going. It then sits there until you are ready to ship it, or until its description has matured enough to hand off. Each task is written to be self-sufficient: an agent can implement it from the file alone, even in a later session that never saw the conversation that created it. A bundled linter enforces naming, frontmatter, and a size-based split threshold. The create → check → select → implement → audit → finish lifecycle gives each step its own focused skill. The read-only gates (is this ready to build, what should I work on next, is it actually done) stay apart from the skills that change files.

**Wiki is an internal knowledge base an AI can build and navigate on its own:** It auto-discovers from the current directory and holds far more context than a chat window. The content lives as interlinked markdown pages, organized by type (entities, concepts, comparisons, procedures, and more). Each page is written up once as sources arrive, rather than reconstructed on every query. The agent writes the wiki and people read it back with the agent. As a result, it surfaces contradictions rather than burying them, and it gets reshaped over time to stay usable instead of degrading into scattered notes. It stays reachable through standard tools. And because it is tied to the repo, the meta context it accumulates compounds as the project grows. That makes later work easier, across both knowledge management and coding tasks.

The mechanical parts of both families (discovery, scaffolding, linting, source hashing) ship as bundled scripts the agent runs rather than improvising the bookkeeping each session. This saves you turns with your coding agent going back and fourth, saves tokens and makes workflows more deterministic. And because the same files deploy into Claude Code, Codex, Cursor, Copilot, Gemini, and Antigravity, the backlog and the knowledge base come with you whichever agent you happen to be driving wile making it easy to colaborate on a shared codebase across different user setups and AI agents.

Alongside task and wiki, the same two plugins ship a set of smaller day-to-day skills: clean git commits and changelogs, authoring and formatting for the instructions an AI reads, linter-aligned code style, and document distillation. See [Plugins](#plugins) below for the rest.

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
│           ├── task_check/
│           ├── task_select/
│           ├── task_implement/
│           ├── task_audit/
│           ├── task_finish/
│           ├── task_fix/
│           ├── ai_instruction_writing/
│           ├── ai_instruction_formatting/
│           ├── harness_portability/
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

Skills for day-to-day AI-assisted development: keeping git history and changelogs clean, writing and formatting AI-consumed instructions, keeping bundled skill/plugin runtime artefacts portable, and applying linter-aligned style conventions at write time.

- **git_commit**: a phase-based commit workflow with a hardened prepare script that handles special-character paths and per-file binary detection. It stages changes, infers an intended commit grouping, and writes a message aligned with the project's existing convention. A sibling manual-fallback reference covers the path when the script can't be used.
- **update_changelog**: generates or refreshes a day-grouped `CHANGELOG.md` from git history. It produces newest-first day sections with status markers (`[active]`, `[changed later]`, `[superseded]`), and processes one day at a time so long histories stay within a single context window.
- **task**: project-local backlog of upcoming work as plain-markdown files under `tasks/` at the project root, with `tasks/archive/` for `implemented` and `deferred` items. Each task is written as a self-contained brief a single-shot AI coder could pick up and implement; the bundled linter enforces naming, frontmatter, status/location consistency, and a 300-line split threshold. Complementary to the `wiki` skill: tasks track *what is still to do*, the wiki captures *what is durably known*.
  The single-task siblings run in lifecycle order — **create → check → select → implement → audit → finish**:
- **task_create**: a focused front end over `task` that creates exactly one well-formed task file with minimal ceremony, deferring the naming, frontmatter, body, and lint rules to the `task` skill rather than restating them. It gives a one-shot "make a task for X" a narrow, trigger-precise surface instead of loading the full backlog-management workflow.
- **task_check**: assesses whether one task is ready to hand to an implementer — runs a structural check then a content lens (scope sizing, focus, complexity, contradictions, ambiguity, over-specification, negation-framed behaviour) and emits `spec_check`'s shape (a `# General assessment` paragraph plus a ranked `## Issues` list). A read-only gate *before* building, the pre-implementation counterpart to `task_audit`.
- **task_select**: recommends what to work on next from the live backlog — filters eligible tasks, detects dependency and ordering relationships, ranks by impact, implementation complexity, friction, and viable bug-fix priority, then names one unblocked task plus its natural next action. A read-only selector between readiness and implementation.
- **task_implement**: implements one existing task file end-to-end via a strict read → load-guardrails → understand-codebase → implement → test → verify flow ported from staged-spec's `spec_implement`. It does the work and stops at a green suite, leaving codebase verification (`task_audit`) and close-out (`task_finish`) to its single-purpose siblings.
- **task_audit**: verifies one task's claimed completion against the codebase — walks every body item, acceptance check, and backing test, runs the suite, and emits `spec_audit`'s verdict shape (`Success`, or ordered `Gaps:` with fixes). A read-only gate that changes nothing, handing a clean pass to `task_finish` and gaps to `task_implement`.
- **task_finish**: closes out one task — sets its status (`implemented` or `deferred`), bumps `updated`, `git mv`s it to `archive/`, re-points the cross-references the move touches, and re-lints. The action counterpart to the read-only `task_audit` gate, deferring the five close-out steps to the base `task` skill's `<archive>` workflow.

  Standing apart from that flow:
- **task_fix**: audits and repairs the whole `tasks/` tree in one inline pass (orient → assess → remediate → verify) — runs `lint.py`, auto-fixes the mechanical findings, and surfaces the judgement calls (splits, cross-task contradictions) for human review, closing with an `audit complete — N resolved, K flagged` report. The task-backlog analogue of `wiki_fix`, done inline rather than via an agent because the tree is small and the fixes are mechanical. Operates on the whole backlog, independent of any single task's lifecycle.
- **ai_instruction_writing**: writes any AI-consumed artefact (SKILL.md, `.mdc` rule files, `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, prompt templates, system prompts, commands, agent definitions) using positive, action-oriented language as the primary carrier of every instruction, instead of negative prohibitions the model has to invert.
- **ai_instruction_formatting**: organises AI-consumed content into pseudo-XML, wrapping each semantic concern (`<role>`, `<policy>`, `<input>`, `<output_contract>`) in a dedicated tag so the model can locate the right section by structure rather than by re-reading the prose.
- **harness_portability**: applies cross-agent-harness and cross-OS portability rules to scripts, hooks, MCP helpers, command wrappers, setup flows, and execution/configuration wording bundled inside skills and plugins. It keeps OpenAI Codex and Anthropic Claude compatibility, official provider documentation checks, and macOS/Linux behavior in scope.
- **format_markdown / format_python / format_rust**: linter-aligned style guides (`markdownlint`, `flake8` plus `ruff` plus `pylint`, `clippy`) consulted at write time. The point is to land code that already passes the linter, instead of spending a follow-up turn reacting to lint output.

## Installing and deploying

The same source of truth ships through several equal paths. You can install it from the bundled Claude Code marketplace, symlink it into vendor config dirs globally with `make deploy` (VS Code Copilot, Cursor, Claude Code, OpenAI Codex, Gemini CLI, Google Antigravity), symlink it into a single repo's local config via `--project-dir`, or use it in-place from a checkout. The deployment script discovers artefacts by plugin layout and installs them where each tool expects them.

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
