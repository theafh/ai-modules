# AI-Modules

A set of professional AI skills and agents for AI-assisted development, packaged as plugins. The deployment toolchain installs them into six agent harnesses, along with hooks, output styles, and commands.

## Why You Should Install This

These plugins give an AI coding agent the context a chat session forgets: a backlog of the work still to do, and a knowledge base of what the project has learned. Both are plain CommonMark Markdown files on disk. You can grep them, diff them, version them in git, and open them in any editor, with no database, no SaaS, or proprietary reader in the loop.

**Both close the same gap: the distance between what you mean and what an AI rebuilds from it.** An agent fills in every gap it meets. Where you leave something unsaid, it fills the gap with plausible, generic content that is not what you meant, and it guesses differently each run, because whatever can be read wrong eventually is. Task and wiki narrow that gap. They turn your intent into an explicit, formatted, checked file the agent reads, instead of one it reinvents each time.

Task does this for the work. Running a task through the skill-to-skill lifecycle, instead of handing it to a single one-shot implementer, forces each gap to surface and be filled on purpose. Wiki does this for the knowledge. The agent writes what it learns in its own words, and you correct a page when it reads wrong. Over many sessions the two of you converge, until the agent attaches the same meaning to what matters that you do. Just telling it never gets there.

**Task prepares a work item for single-shot implementation by an AI agent, with you in the loop as driver and sense-maker.** It is an async backlog that lives with the code (like Jira or Trello, but for AI agents), so you add to it now and act on it later, both easy for an agent to do. While you are deep in one change, you can drop a newly spotted bug or idea into a task and keep going. It waits there until you are ready to ship it, or until its description is detailed enough to hand off. Each task is self-contained: an agent can implement it from the file alone, even in a later session that never saw the conversation that created it. A bundled linter checks naming, frontmatter, and task size. The create → check → implement → audit → finish lifecycle gives each step its own skill, with an optional auto-check loop to repair readiness issues while keeping `task_check` as the gate. The read-only gates stay separate from the skills that change files: `task_check` answers whether a task is ready to build and `task_audit` answers whether it is done, while `task_select` is a separate read-only chooser for what to work on next. For orientation rather than gating, `task_explain` gives a compact what/why/how readout of one task without editing it.

**Wiki is a knowledge base an AI can build and navigate on its own.** It finds itself from the current directory and holds far more context than a chat window. The content is interlinked Markdown pages, grouped by type: entities, concepts, comparisons, procedures, and more. Each page is written once as sources arrive, not rebuilt on every query. The agent writes the wiki, and you read it back with the agent's help. Because of this, it surfaces contradictions instead of hiding them, and it gets reshaped over time so it stays usable instead of decaying into scattered notes. It stays reachable through ordinary tools. And because it lives in the repo, the context it gathers compounds as the project grows, which makes later work easier, for both knowledge and code.

The mechanical parts of both (discovery, scaffolding, linting, source hashing) ship as bundled scripts the agent runs, so it does not improvise the bookkeeping each session. This saves back-and-forth turns with your agent, saves tokens, and makes the output more consistent across runs. The same files deploy into Claude Code, Codex, Cursor, Copilot, Antigravity, and OpenCode, so the backlog and the knowledge base follow you whichever agent you drive. That also makes it easy to share one codebase across different setups and agents.

Alongside task and wiki, the same two plugins ship smaller day-to-day skills: clean git commits, repository refreshes, and changelogs, repo-root guardrail documents that hold an agent inside the boundary you set, writing and formatting the instructions an AI reads, portability review for anything bundled inside a skill, linter-aligned code style, and document distillation. See [Plugins](#plugins) below for the rest.

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
│       ├── agents/
│       │   ├── auto_drift_task.md
│       │   ├── auto_gate_task.md
│       │   ├── auto_reviewer_task.md
│       │   ├── auto_verifier_task.md
│       │   └── auto_shaper_task.md
│       ├── hooks/           # shared hook scripts plus Claude/Codex/Antigravity hook configs
│       └── skills/
│           ├── git_commit/
│           ├── git_checkout/
│           ├── git_refresh/
│           ├── git_review/
│           ├── update_changelog/
│           ├── task/
│           ├── task_create/
│           ├── task_check/
│           ├── task_auto_check/
│           ├── task_explain/
│           ├── task_select/
│           ├── task_implement/
│           ├── task_audit/
│           ├── task_finish/
│           ├── task_fix/
│           ├── guardrail/
│           ├── guardrail_audit/
│           ├── ai_instruction_writing/
│           ├── ai_instruction_formatting/
│           ├── skill_doctor/
│           ├── harness_portability/
│           ├── format_markdown/
│           ├── format_python/
│           └── format_rust/
├── styles/                  # tracked output styles (Claude format; deployed, not a plugin component)
│   └── natural-language.md
├── deployment/              # deployment script for installing artefacts globally or per-project
│   ├── deployment.sh
│   ├── deployment.conf
│   └── README.md
├── tasks/                   # this repo's own backlog, kept with the shipped task skill
│   └── archive/             # finished and deferred tasks
├── wiki/                    # this repo's own knowledge base, kept with the shipped wiki skill
├── CHARTER.md               # this repo's own guardrail doc, enforced by the charter_guardrail hook
├── AGENTS.md                # standing repo instructions for coding agents
├── CLAUDE.md                # the same instructions for Claude Code
├── CHANGELOG.md             # day-grouped history, written by the shipped update_changelog skill
└── Makefile                 # deploy, uninstall, lint, and fix entry points
```

The repo runs on the components it ships. Its backlog, knowledge base, charter, and
changelog are all produced by the skills in `plugins/`, so those four directories double
as worked examples of what the plugins do.

## Plugins

Each skill is a written procedure the model loads when its trigger fires. Alongside the prose, a skill can bundle helpers: bash and Python scripts, linters, schema files. These let the agent hand mechanical work to programs that can't hallucinate, and follow a set workflow instead of re-deriving one each session. The effect: fewer turns per task, smaller context per turn, and more consistent output across runs. On metered models, that is time and tokens saved.

### knowledge_management

Skills and agents for building, maintaining, and distilling a knowledge base that persists and compounds. Everything is plain Markdown, readable in any editor or terminal, with no Obsidian or vendor reader required.

The wiki itself, plus paired front ends that wrap two of its workflows so the model has one named entry point per use case:

- **wiki**: the foundation. It builds and maintains an interlinked Markdown wiki. It can ingest URLs, articles, papers, PDFs, transcripts, meeting notes, internal notes, and pastes, then query, lint, audit, archive, and reorganise. The page types (`entity`, `concept`, `comparison`, `summary`, `query`, `procedure`) are read from `SCHEMA.md`, so a wiki can add a type without changing the linter. Each claim links to its source with an inline standard-Markdown link; the `sources:` frontmatter is the full inventory; an optional `## Derived from` section records external material the wiki does not own; and a body-only `sha256` hash detects when a raw source has drifted. Discovery, init, lint, and the sha256 helper all ship as bundled scripts, so the agent runs fixed programs for the mechanical parts instead of inventing them each session.
- **wiki_import** and **wiki_wrapup**: a triage-first ingest pair. `wiki_import` takes one named resource (URL, file, paper, PDF, transcript, meeting note, internal note, or paste); `wiki_wrapup` takes the current chat session. Both capture the source, compare each candidate against the existing wiki, and produce a triage report (new pages, extensions, and contradictions, each with excerpts and concrete options to reconcile them) before any page is written. Approved writes go back through the `wiki` skill. Use them when you want to review changes before they land: after a research chat, or before importing a paper you don't fully trust.
- **wiki_fix** and **auto_shaper_wiki** *(agent)*: a paired audit-and-repair. `wiki_fix` is the one-shot skill wrapper; `auto_shaper_wiki` is the agent it hands off to. The agent runs a two-phase loop: assess (lint plus a semantic audit), fix, then re-lint until clean. It repairs frontmatter and schema violations, broken links, off-taxonomy tags, oversized or topic-mixing pages, procedure pages that leak instance content, and content that drifts from its page type. Cross-page contradictions it does not auto-resolve; it surfaces them for human review through the contested-page protocol.

Two distillation skills that work on text outside the wiki:

- **executive_summary**: condenses a document into structured prose at 10 to 15 percent of its original length, preserving the logic and reasoning chain rather than producing bullet-point keywords.
- **spr**: converts text into a Sparse Priming Representation (SPR): a compact, Markdown-structured set of dense, non-overlapping priming statements that let a second LLM reconstruct the source without ever seeing it.

An LLM wiki sits between a full RAG pipeline and a loose pile of notes. It is structured enough that an agent can navigate it by schema and links, and light enough that upkeep is just Markdown edits. Knowledge is compiled once into lasting pages, not re-derived from raw chunks on every query. As long as you keep the wiki current and reshape it over time, you spend little effort and save inference cost. Because it lives next to the repo, it gives an agent the lasting context it needs to plan work, remember decisions, and carry knowledge across sessions, something a chat transcript cannot do.

### ai_dev

Skills and agents for day-to-day AI-assisted development: keeping git workflows and changelogs clean, writing and formatting the instructions an AI reads, checking skill artifacts with skill_doctor, keeping bundled skill and plugin runtime artefacts portable across agents and operating systems, and applying linter-aligned style conventions as you write.

- **git_commit**: a step-by-step commit workflow with a hardened prepare script that handles special-character paths and detects binary files one by one. It stages changes, works out a sensible commit grouping, and writes a message that matches the project's existing style. A sibling reference covers the manual path when the script can't run.
- **git_checkout**: a branch-switch workflow for the everyday "somebody pushed a branch, put me on it" step. It fetches every remote without pruning, switches when the branch is already local, creates a local branch with an explicit upstream when exactly one remote carries the name, asks which remote to track when several do, and tells a nonexistent branch apart from one a narrow fetch refspec never delivered. Every path ends on a named local branch rather than in detached `HEAD`.
- **git_refresh**: a safe repo-refresh workflow that detects the remote default branch, fetches and prunes, switches to that branch, fast-forwards only, deletes cleanly merged local branches, and offers upstream-gone or force-delete cleanup only behind explicit opt-in.
- **git_review**: a review workflow for the "can this go in?" question. It resolves the target, which is a pull request, a branch, or the uncommitted changes on the default branch, then pins the reviewed commit without touching your tree, collects the git evidence (and the GitHub discussion through `gh` when it is there) into a scratch directory, ranks findings against the guardrail documents the repository declares, and reports under fixed headings: what the change does, what it retires, what is critical, the bugs, the nits, the open decisions, and a yes or no on structural mergeability. Posting to the pull request and fixing the branch each wait for you to ask.
- **update_changelog**: builds or refreshes a day-grouped `CHANGELOG.md` from git history. It writes newest-first immutable day sections with `- **Category:** Plain-English summary.` entries, and hands large per-day context through a readable file path so long histories stay consumable.
- **task**: a project-local backlog of upcoming work, as plain-Markdown files under `tasks/` at the project root, with `tasks/archive/` for `finished` and `deferred` items. Each task is a self-contained brief that a single-shot AI coder could pick up and build. The bundled linter checks naming, frontmatter, status/location consistency, and a 300-line split limit. It complements the `wiki` skill: tasks track *what is still to do*, the wiki holds *what is durably known*.

The lifecycle spine runs **create → check → implement → audit → finish**, with `task_auto_check` available as an opt-in readiness repair loop:

- **task_create**: a focused front end over `task` that creates exactly one well-formed task file with little ceremony. It leaves the naming, frontmatter, body, and lint rules to the `task` skill instead of repeating them, so a one-shot "make a task for X" loads a narrow surface rather than the full backlog workflow.
- **task_auto_check**: automatically drive one task to the `ready` status, reusing the read-only `task_check` gate (the readiness check *before* building) as the only readiness bar. `task_check` judges a task against a readiness checklist (structure, premise, approach fitness, scope sizing, focus, complexity, contradictions, ambiguity), reports a `# General assessment` paragraph plus a ranked `## Issues` list, and stamps `ready` when clean or `checked` when blocking issues remain. The loop freezes the task's title and goal, runs its helper agents for a committed-intent check, gated issue reports, repair proposals, and intent-safe approvals, then applies only verified minimum edits and stops at `ready` or a surfaced stuck state.
- **task_implement**: builds one existing task file end to end, following a strict flow: read, load guardrails, understand the codebase, implement, test, verify. It does the work and stops at a green test suite, leaving codebase verification to `task_audit` and close-out to `task_finish`.
- **task_audit**: checks one task's claimed completion against the codebase. It walks every body item, acceptance check, and backing test, runs the suite, and returns a verdict: `Success`, or an ordered `Gaps:` list with fixes. A read-only gate that changes nothing; it hands a clean pass to `task_finish` and gaps to `task_implement`.
- **task_finish**: closes out one task. It sets the status to `finished` or `deferred`, bumps `updated`, runs `git mv` to move the file to `archive/`, re-points the cross-references the move touches, and re-lints. The action counterpart to the read-only `task_audit` gate; it leaves the six close-out steps to the base `task` skill's `<archive>` workflow.

Standing apart from that flow:

- **task_select**: recommend what to work on next from the live backlog (the task that most advances the project) without editing anything. It filters eligible tasks at any status, weighs dependencies and ordering, ranks by impact, implementation complexity, friction, and viable bug-fix priority, then names one task and its natural next action, which may be a check pass before implementation. Skippable for a single-task run and leaned on for a larger backlog.
- **task_explain**: explains one task at a high level without editing it. It resolves one live or archived task, names its status and scope, and gives a compact what/why/how readout so a reader can orient before choosing a lifecycle action.
- **task_fix**: audits and repairs the whole `tasks/` tree in one pass (orient → assess → remediate → verify), and runs a default backlog-coherence assessment in the same pass. It reads the selected live tasks together with the artifacts they target, judges them against each other and against the code as it stands, and reports a per-task verdict (ship as-is, alter, defer candidate) plus a ship order. It runs `lint.py`, auto-fixes the mechanical findings, and surfaces the judgement calls (splits, cross-task contradictions) for human review by default, then reports how many it resolved and how many it flagged. Coherence reconcile stays gated on the user's acceptance or an escalate opt-in; on either, it escalates those calls to `auto_shaper_task`, the single serialized writer for verified splits, body-framing reframes, scope relocations, link repairs, and accepted backlog-coherence repairs. It works on the whole backlog, independent of any single task's lifecycle.
- **guardrail**: the hub for the repo-root guardrail docs (`CHARTER.md`, `ARCHITECTURE.md`, `TESTING.md`, `SECURITY.md`) that keep AI agents anchored to human intent. It explains the doc set, hierarchy, format, and the presence-gated way skills consult the docs (the task family already reads them this way), suggests which guardrails fit a given repository based on its nature and substance, and drafts one only on explicit request. Per-type references carry the general template and rules for each doc, so sibling skills wire the hub in instead of duplicating them.
- **guardrail_audit**: the read-only audit sibling. It surfaces doc-vs-doc contradictions and doc-vs-code divergences among existing guardrail docs, ranked by the hub's hierarchy, plus grounded missing-doc proposals where repo substance warrants an absent type. Findings carry evidence and reconcile recommendations; the run edits nothing and asks how to proceed. This is the retrofit and health-check entry point for guardrails already in place.
- **ai_instruction_writing**: writes any artefact an AI reads (SKILL.md, `.mdc` rule files, `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, prompt templates, system prompts, commands, agent definitions) using positive, action-oriented language as the primary carrier of every instruction, instead of "don't" rules the model has to invert.
- **ai_instruction_formatting**: organises content an AI reads into pseudo-XML, wrapping each semantic concern (`<role>`, `<policy>`, `<input>`, `<output_contract>`) in its own tag, so the model can find the right section by structure instead of re-reading the prose.
- **skill_doctor**: check-only doctor for skill artifacts. Audits `SKILL.md` frontmatter and dual-audience descriptions, registration, tests, and instruction quality for one skill, a skill family, or every skill in the repo. Reports findings with evidence and never edits targets. Cross-harness portability review stays with `harness_portability`.
- **harness_portability**: applies portability rules (across agent harnesses and operating systems) to scripts, hooks, agent definitions, MCP helpers, command wrappers, setup flows, output styles, and the execution and configuration wording bundled inside skills and plugins. It treats OpenAI Codex and Anthropic Claude as the primary targets, with Cursor, Google Antigravity, SST OpenCode, and GitHub Copilot in VS Code as further ones, and it covers macOS/Linux behaviour. Every concrete harness fact is treated as perishable: the skill re-checks each one against official provider docs, the loader source, or the installed build, and states the gap plainly where a claim stays unconfirmed.
- **format_markdown / format_python / format_rust**: style guides aligned with the linters (`markdownlint`; `flake8`, `ruff`, and `pylint`; `clippy`), read as you write. The point is to produce code that already passes the linter, instead of spending a follow-up turn fixing what it reports.

The `ai_dev` hook surface ships a shared `charter_guardrail` script and
harness-specific hook configs for Claude, Codex, and Antigravity. It protects a
repository's root `CHARTER.md` by allowing charter edits only on
`guardrail/charter-*` branches, while staying inert in projects that have not
adopted a charter. Codex loads its plugin-bundled config from the plugin
manifest after hook trust review. The deployable config-layer Codex and
Antigravity hook sources remain available for explicit global or project
activation outside plugin installs.

## Installing and deploying

The same source of truth ships through several paths. You can install it from
the bundled Claude Code marketplace; copy it into vendor config dirs globally
with `make deploy` (VS Code Copilot, Cursor, Claude Code, OpenAI Codex, Google
Antigravity, OpenCode); copy it into a single repo's local config with
`--project-dir`; or use it in place from a checkout. The deployment script finds
artefacts under two roots: the plugin layout (`plugins/<plugin>/<asset-folder>/`)
and repo-root `styles/` for the `style` type. A per-tool `style:<name>` line in
`deployment/deployment.conf` names the active style; Claude deploy copies that
file into `output-styles/` and merges `outputStyle` into settings. Uninstall of
a merged settings key restores the first-recorded prior value (or deletes the
key when it was absent before the first deploy).

For OpenAI Codex, prefer the deployment script when you need the helper agents.
The Codex marketplace registration remains available, but plugin-only installs
do not create Codex-compatible agent definitions from the bundled `agents/*.md`
files. `./deployment/deployment.sh --global --target codex` generates
`~/.codex/agents/*.toml`, copies the skills, and installs the Codex hook layer
from the same plugin source. Use the project form,
`./deployment/deployment.sh --project-dir /path/to/repo --target codex`, for a
repo-local install.

Common workflows are wrapped in the [Makefile](Makefile):

```bash
make help        # list targets
make deploy      # deploy artefacts to global config dirs (aliases: global, install)
make uninstall   # remove previously deployed artefacts
make clean       # remove managed deployment backups
make lint        # report lint issues across md / json / sh
make fix         # auto-fix lint issues where possible (markdown only)
```

For finer-grained control, call `deployment/deployment.sh` directly. See [deployment/README.md](deployment/README.md) for flags like `--dry-run`, `--target`, and `--project-dir`.

### Linting tools

`make lint` and `make fix` use `markdownlint-cli`, `jq`, and `shellcheck` (install via Homebrew on macOS).

Markdown rules live in [.markdownlint.jsonc](.markdownlint.jsonc). Inline-HTML checks (`MD033`) are off, because skill prompts use pseudo-XML on purpose.
