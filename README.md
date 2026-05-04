# ai-modules

A collection of professional AI skills, agents, commands, and hooks. The same source of truth ships through several equal paths — installed from the bundled Claude Code marketplace, symlinked into vendor config dirs globally by `make deploy` (VS Code Copilot, Cursor, Claude Code, OpenAI Codex, Gemini CLI, Google Antigravity), symlinked into a single repo's local config via `--project-dir`, or used in-place from a checkout. The deployment script discovers artefacts by plugin layout and installs them where each tool expects them.

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

- **knowledge_management**: skills and agents for building, maintaining, and distilling a knowledge base.
  Ships `wiki` (persistent, interlinked markdown notes), `executive_summary` (structured prose summaries), `spr` (Sparse Priming Representations), and the `wiki_auto_shaper` agent (autonomous lint + semantic audit + fix loop for the repo's wiki).
- **ai_dev**: skills for everyday AI-assisted development.
  Ships `git_commit`, `update_changelog`, `ai_instruction_writing`, `ai_instruction_formatting`, and the `format_markdown` / `format_python` / `format_rust` style guides.

## Make targets

Common workflows are wrapped in the [Makefile](Makefile):

```bash
make help        # list targets
make deploy      # deploy artefacts to global config dirs (aliases: global, install)
make uninstall   # remove previously deployed artefacts
make lint        # report lint issues across md / json / sh
make fix         # auto-fix lint issues where possible (markdown only)
```

For finer-grained control, call `deployment/deployment.sh` directly — see [deployment/README.md](deployment/README.md) for flags like `--dry-run`, `--target`, and `--project-dir`.

### Linting tools

`make lint` and `make fix` use `markdownlint-cli`, `jq`, and `shellcheck` (install via Homebrew on macOS).

Markdown rules live in [.markdownlint.jsonc](.markdownlint.jsonc); inline-HTML checks (`MD033`) are disabled because skill prompts use intentional pseudo-XML.
