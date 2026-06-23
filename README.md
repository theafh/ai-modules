# AI-Modules

A set of professional AI skills and agents for AI-assisted development, packaged as plugins. The deployment toolchain can also install commands and hooks.

## Why You Should Install This

These plugins give an AI coding agent the context a chat session forgets: a backlog of the work still to do, and a knowledge base of what the project has learned. Both are plain CommonMark Markdown files on disk. You can grep them, diff them, version them in git, and open them in any editor, with no database, no SaaS, or proprietary reader in the loop.

**Both close the same gap: the distance between what you mean and what an AI rebuilds from it.** An agent fills in every gap it meets. Where you leave something unsaid, it fills the gap with plausible, generic content that is not what you meant, and it guesses differently each run, because whatever can be read wrong eventually is. Task and wiki narrow that gap. They turn your intent into an explicit, formatted, checked file the agent reads, instead of one it reinvents each time.

Task does this for the work. Running a task through the skill-to-skill lifecycle, instead of handing it to a single one-shot implementer, forces each gap to surface and be filled on purpose. Wiki does this for the knowledge. The agent writes what it learns in its own words, and you correct a page when it reads wrong. Over many sessions the two of you converge, until the agent attaches the same meaning to what matters that you do. Just telling it never gets there.

**Task is an async backlog that lives with the code.** It works like Jira or Trello, but for AI agents. You add to it now and act on it later, and both are easy for an agent to do. While you are deep in one change, you can drop a newly spotted bug or idea into a task and keep going. It waits there until you are ready to ship it, or until its description is detailed enough to hand off. Each task is self-contained: an agent can implement it from the file alone, even in a later session that never saw the conversation that created it. A bundled linter checks naming, frontmatter, and task size. The create → check → select → implement → audit → finish lifecycle gives each step its own skill. The read-only gates stay separate from the skills that change files, and they answer three questions without editing anything: is this ready to build, what should I work on next, and is it done?

**Wiki is a knowledge base an AI can build and navigate on its own.** It finds itself from the current directory and holds far more context than a chat window. The content is interlinked Markdown pages, grouped by type: entities, concepts, comparisons, procedures, and more. Each page is written once as sources arrive, not rebuilt on every query. The agent writes the wiki, and you read it back with the agent's help. Because of this, it surfaces contradictions instead of hiding them, and it gets reshaped over time so it stays usable instead of decaying into scattered notes. It stays reachable through ordinary tools. And because it lives in the repo, the context it gathers compounds as the project grows, which makes later work easier, for both knowledge and code.

The mechanical parts of both (discovery, scaffolding, linting, source hashing) ship as bundled scripts the agent runs, so it does not improvise the bookkeeping each session. This saves back-and-forth turns with your agent, saves tokens, and makes the output more consistent across runs. The same files deploy into Claude Code, Codex, Cursor, Copilot, Gemini, and Antigravity, so the backlog and the knowledge base follow you whichever agent you drive. That also makes it easy to share one codebase across different setups and agents.

Alongside task and wiki, the same two plugins ship smaller day-to-day skills: clean git commits and changelogs, writing and formatting the instructions an AI reads, linter-aligned code style, and document distillation. See [Plugins](#plugins) below for the rest.

## Layout

```text
ai-modules/
├── .claude-plugin/
│   └── marketplace.json     # registers the plugins below as a Claude marketplace
├── .agents/
│   └── plugins/marketplace.json  # the same plugins registered as a Codex marketplace
├── plugins/                 # one subdirectory per plugin
│   ├── knowledge_management/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── .codex-plugin/plugin.json
│   │   ├── README.md
│   │   ├── agents/          # one .md file per agent
│   │   │   └── auto_shaper_wiki.md
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

Each skill is a written procedure the model loads when its trigger fires. Alongside the prose, a skill can bundle helpers: bash and Python scripts, linters, schema files. These let the agent hand mechanical work to programs that can't hallucinate, and follow a set workflow instead of re-deriving one each session. The effect: fewer turns per task, smaller context per turn, and more consistent output across runs. On metered models, that is time and tokens saved.

### knowledge_management

Skills and agents for building, maintaining, and distilling a knowledge base that persists and compounds. Everything is plain Markdown, readable in any editor or terminal, with no Obsidian or vendor reader required.

The wiki itself, plus paired front ends that wrap two of its workflows so the model has one named entry point per use case:

- **wiki**: the foundation. It builds and maintains an interlinked Markdown wiki. It can ingest URLs, articles, papers, PDFs, transcripts, meeting notes, internal notes, and pastes, then query, lint, audit, archive, and reorganise. The page types (`entity`, `concept`, `comparison`, `summary`, `query`, `procedure`) are read from `SCHEMA.md`, so a wiki can add a type without changing the linter. Each claim links to its source with an inline standard-Markdown link; the `sources:` frontmatter is the full inventory; and a body-only `sha256` hash detects when a raw source has drifted. Discovery, init, lint, and the sha256 helper all ship as bundled scripts, so the agent runs fixed programs for the mechanical parts instead of inventing them each session.
- **wiki_import** and **wiki_wrapup**: a triage-first ingest pair. `wiki_import` takes one named resource (URL, file, paper, PDF, transcript, meeting note, internal note, or paste); `wiki_wrapup` takes the current chat session. Both capture the source, compare each candidate against the existing wiki, and produce a triage report (new pages, extensions, and contradictions, each with excerpts and concrete options to reconcile them) before any page is written. Approved writes go back through the `wiki` skill. Use them when you want to review changes before they land: after a research chat, or before importing a paper you don't fully trust.
- **wiki_fix** and **auto_shaper_wiki** *(agent)*: a paired audit-and-repair. `wiki_fix` is the one-shot skill wrapper; `auto_shaper_wiki` is the agent it hands off to. The agent runs a two-phase loop: assess (lint plus a semantic audit), fix, then re-lint until clean. It repairs frontmatter and schema violations, broken links, off-taxonomy tags, oversized or topic-mixing pages, procedure pages that leak instance content, and content that drifts from its page type. Cross-page contradictions it does not auto-resolve; it surfaces them for human review through the contested-page protocol.

Two distillation skills that work on text outside the wiki:

- **executive_summary**: condenses a document into structured prose at 10 to 15 percent of its original length, preserving the logic and reasoning chain rather than producing bullet-point keywords.
- **spr**: converts text into a Sparse Priming Representation (SPR): a compact, Markdown-structured set of dense, non-overlapping priming statements that let a second LLM reconstruct the source without ever seeing it.

An LLM wiki sits between a full RAG pipeline and a loose pile of notes. It is structured enough that an agent can navigate it by schema and links, and light enough that upkeep is just Markdown edits. Knowledge is compiled once into lasting pages, not re-derived from raw chunks on every query. As long as you keep the wiki current and reshape it over time, you spend little effort and save inference cost. Because it lives next to the repo, it gives an agent the lasting context it needs to plan work, remember decisions, and carry knowledge across sessions, something a chat transcript cannot do.

### ai_dev

Skills for day-to-day AI-assisted development: keeping git history and changelogs clean, writing and formatting the instructions an AI reads, keeping bundled skill and plugin runtime artefacts portable across agents and operating systems, and applying linter-aligned style conventions as you write.

- **git_commit**: a step-by-step commit workflow with a hardened prepare script that handles special-character paths and detects binary files one by one. It stages changes, works out a sensible commit grouping, and writes a message that matches the project's existing style. A sibling reference covers the manual path when the script can't run.
- **update_changelog**: builds or refreshes a day-grouped `CHANGELOG.md` from git history. It writes newest-first immutable day sections with `- **Category:** Plain-English summary.` entries, and hands large per-day context through a readable file path so long histories stay consumable.
- **task**: a project-local backlog of upcoming work, as plain-Markdown files under `tasks/` at the project root, with `tasks/archive/` for `finished` and `deferred` items. Each task is a self-contained brief that a single-shot AI coder could pick up and build. The bundled linter checks naming, frontmatter, status/location consistency, and a 300-line split limit. It complements the `wiki` skill: tasks track *what is still to do*, the wiki holds *what is durably known*.

The single-task siblings run in lifecycle order, **create → check → select → implement → audit → finish**:

- **task_create**: a focused front end over `task` that creates exactly one well-formed task file with little ceremony. It leaves the naming, frontmatter, body, and lint rules to the `task` skill instead of repeating them, so a one-shot "make a task for X" loads a narrow surface rather than the full backlog workflow.
- **task_check**: decides whether one task is ready to hand to an implementer. It runs a structural check, then a content review (scope sizing, focus, complexity, contradictions, ambiguity, over-specification, behaviour framed as "not X"), and returns `spec_check`'s shape: a `# General assessment` paragraph plus a ranked `## Issues` list. A read-only gate *before* building. It is the counterpart to `task_audit`, which checks *after*.
- **task_select**: recommends what to work on next from the live backlog. It filters eligible tasks, finds dependencies and ordering, ranks by impact, implementation complexity, friction, and viable bug-fix priority, then names one unblocked task and its natural next action. A read-only step between readiness and implementation.
- **task_implement**: builds one existing task file end to end, following a strict flow: read, load guardrails, understand the codebase, implement, test, verify (ported from staged-spec's `spec_implement`). It does the work and stops at a green test suite, leaving codebase verification to `task_audit` and close-out to `task_finish`.
- **task_audit**: checks one task's claimed completion against the codebase. It walks every body item, acceptance check, and backing test, runs the suite, and returns a verdict in the `spec_audit` shape (`Success`, or an ordered `Gaps:` list with fixes). A read-only gate that changes nothing; it hands a clean pass to `task_finish` and gaps to `task_implement`.
- **task_finish**: closes out one task. It sets the status to `finished` or `deferred`, bumps `updated`, runs `git mv` to move the file to `archive/`, re-points the cross-references the move touches, and re-lints. The action counterpart to the read-only `task_audit` gate; it leaves the five close-out steps to the base `task` skill's `<archive>` workflow.

Standing apart from that flow:

- **task_fix**: audits and repairs the whole `tasks/` tree in one pass (orient → assess → remediate → verify). It runs `lint.py`, auto-fixes the mechanical findings, and surfaces the judgement calls (splits, cross-task contradictions) for human review, then reports how many it resolved and how many it flagged. It is the task-backlog version of `wiki_fix`, done inline rather than through an agent because the tree is small and the fixes are mechanical. It works on the whole backlog, independent of any single task's lifecycle.
- **ai_instruction_writing**: writes any artefact an AI reads (SKILL.md, `.mdc` rule files, `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, prompt templates, system prompts, commands, agent definitions) using positive, action-oriented language as the primary carrier of every instruction, instead of "don't" rules the model has to invert.
- **ai_instruction_formatting**: organises content an AI reads into pseudo-XML, wrapping each semantic concern (`<role>`, `<policy>`, `<input>`, `<output_contract>`) in its own tag, so the model can find the right section by structure instead of re-reading the prose.
- **harness_portability**: applies portability rules (across agent harnesses and operating systems) to scripts, hooks, MCP helpers, command wrappers, setup flows, and the execution and configuration wording bundled inside skills and plugins. It covers OpenAI Codex and Anthropic Claude compatibility, checks against official provider docs, and macOS/Linux behaviour.
- **format_markdown / format_python / format_rust**: style guides aligned with the linters (`markdownlint`; `flake8`, `ruff`, and `pylint`; `clippy`), read as you write. The point is to produce code that already passes the linter, instead of spending a follow-up turn fixing what it reports.

## Installing and deploying

The same source of truth ships through several equal paths. You can install it from the bundled Claude Code marketplace; symlink it into vendor config dirs globally with `make deploy` (VS Code Copilot, Cursor, Claude Code, OpenAI Codex, Gemini CLI, Google Antigravity); symlink it into a single repo's local config with `--project-dir`; or use it in place from a checkout. The deployment script finds artefacts by their plugin layout and installs them where each tool expects them.

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

Markdown rules live in [.markdownlint.jsonc](.markdownlint.jsonc). Inline-HTML checks (`MD033`) are off, because skill prompts use pseudo-XML on purpose.
