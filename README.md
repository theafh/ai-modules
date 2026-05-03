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

## Deploying

The `deployment/` folder contains `deployment.sh`, which discovers artefacts (agents, commands, skills, hooks) by folder layout and installs them either globally (e.g. `~/.claude/`, `~/.cursor/`) or into a single project's local config.

```bash
./deployment/deployment.sh                                        # show help
./deployment/deployment.sh --global                               # deploy all to global dirs
./deployment/deployment.sh --global --dry-run                     # preview
./deployment/deployment.sh --project-dir /path/to/repo --target claude
./deployment/deployment.sh --uninstall                            # remove logged artefacts
```

See [deployment/README.md](deployment/README.md) for the full reference.
