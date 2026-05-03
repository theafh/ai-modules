# ai-modules

A collection of Claude and Codex plugins, organised analogously to the `ai-assets` plugin marketplace.

## Layout

```text
ai-modules/
├── .claude-plugin/
│   └── marketplace.json     # registers the plugins below as a Claude marketplace
├── plugins/                 # one subdirectory per plugin
│   └── knowledge-management/
│       ├── .claude-plugin/plugin.json
│       ├── .codex-plugin/plugin.json
│       ├── README.md
│       └── skills/          # one subdirectory per skill, each with SKILL.md
│           └── wiki/
└── deployment/              # deployment script for installing artefacts globally or per-project
    ├── deployment.sh
    ├── deployment.conf
    └── README.md
```

## Plugins

- **knowledge-management** — skills for building and maintaining a personal/team knowledge base.
  Currently ships the `wiki` skill (persistent, interlinked markdown notes).

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
