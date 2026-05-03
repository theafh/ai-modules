# ai-modules

A collection of professional AI skills, agents, commands, and hooks. Each module is packaged as a plugin (currently Claude Code and OpenAI Codex), and can also be deployed globally into vendor environments such as VS Code Copilot, Cursor, Claude Code, OpenAI Codex, Gemini CLI, and Google Antigravity, or scoped to a single project's local config. The deployment script discovers artefacts by plugin layout and installs them where each tool expects them, so the same source of truth lives in one repo.

## Layout

```text
ai-modules/
├── .claude-plugin/
│   └── marketplace.json     # registers the plugins below as a Claude marketplace
├── plugins/                 # one subdirectory per plugin
│   └── knowledge_management/
│       ├── .claude-plugin/plugin.json
│       ├── .codex-plugin/plugin.json
│       ├── README.md
│       └── skills/          # one subdirectory per skill, each with SKILL.md
│           ├── wiki/
│           ├── executive_summary/
│           └── spr/
└── deployment/              # deployment script for installing artefacts globally or per-project
    ├── deployment.sh
    ├── deployment.conf
    └── README.md
```

## Plugins

- **knowledge_management**: skills for building, maintaining, and distilling a knowledge base.
  Ships `wiki` (persistent, interlinked markdown notes), `executive_summary` (structured prose summaries), and `spr` (Sparse Priming Representations).

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
