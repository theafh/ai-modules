# ai-modules

A collection of professional AI skills, agents, commands, and hooks. Each module is packaged as a plugin (currently Claude Code and OpenAI Codex), and can also be deployed globally into vendor environments such as VS Code Copilot, Cursor, Claude Code, OpenAI Codex, Gemini CLI, and Google Antigravity, or scoped to a single project's local config. The deployment script discovers artefacts by plugin layout and installs them where each tool expects them, so the same source of truth lives in one repo.

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
│   │   │   └── wiki_audit.md
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
  Ships `wiki` (persistent, interlinked markdown notes), `executive_summary` (structured prose summaries), `spr` (Sparse Priming Representations), and the `wiki_audit` agent (autonomous lint + semantic audit + fix loop for the repo's wiki).
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
