# harness-plugins/opencode_v2

OpenCode 2 plugins shipped by this repository. Each plugin is a self-contained
Bun package under its own directory: source in `src/`, tests in `test/`, its own
`package.json` and `tsconfig.json`, and usage notes in its own `README.md`.

The deployer treats this directory as one asset source. `deployment/deployment.sh`
discovers each immediate subdirectory as a `plugin` artifact and copies it into
the OpenCode global plugin directory `~/.config/opencode/plugins/<name>`, where
OpenCode loads it as a plugin directory.

## Plugins

| Plugin | Purpose |
| --- | --- |
| [`request-concurrency-queue`](request-concurrency-queue/README.md) | A process-wide FIFO limiter for model requests, so OpenCode stays inside a provider's concurrency allowance. |
| [`slash-skill-autocomplete`](slash-skill-autocomplete/README.md) | Registers every skill as a `/name` command on the server, restoring slash autocomplete for skills. |

## Install

```bash
./deployment/deployment.sh --global --target opencode --type plugin
```

The deployed copy is recorded in the deploy log, so `./deployment/deployment.sh --update`
refreshes it and `--uninstall` removes it. Restart OpenCode after a deploy,
because plugin setup runs at server startup.

A deployed plugin directory receives no `ctx.options`, so a plugin that takes
options reads them from its own configuration file or from environment
variables. Each plugin's README states its own precedence.

## Development

Each plugin is an independent Bun package:

```bash
cd harness-plugins/opencode_v2/request-concurrency-queue
bun install
bun test
bun run typecheck
```

`harness-plugins/opencode_v2/package.json` is a private Bun workspace root, so
`bun install` at this directory installs every plugin at once and
`bun run test` / `bun run typecheck` run both packages. Nothing here is
published to a registry: the deployer ships the packages.

OpenCode supplies `@opencode/plugin` from its own runtime, so a deployed copy
needs no `node_modules`. The dependency in each `package.json` exists for local
type checking and tests only.

## License

MIT. See the repository [LICENSE](../../../LICENSE).
