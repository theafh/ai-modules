# request-concurrency-queue

An OpenCode 2 plugin that limits concurrent model requests per provider through
a process-wide FIFO queue.

It is built for providers that reject excess concurrent requests instead of
queueing them. The plugin keeps OpenCode from exceeding a provider's
concurrency allowance instead of relying on retries after a provider rejects a
request.

## Behavior

- Every model request to a configured provider acquires a slot before it is
  sent.
- The slot is released when the response body finishes, when the request fails
  and is retried, when the session goes idle, or when the session is deleted or
  interrupted.
- When no slot is free, the request waits in a FIFO queue. The oldest waiting
  request is served first.
- There is no timeout. A request waits until a slot is released or the request
  is aborted.
- The queue counts in-flight requests, not sessions. A session that is running
  a tool or waiting for a subagent does not hold a slot.
- The queue is process-wide. It does not coordinate separate OpenCode server
  processes or other applications using the same provider key.

## Configuration

OpenCode's config file is `opencode.json(c)`. The plugin reads its own JSON
config file rather than a section of `opencode.json(c)`. There are three
installation paths, and they expose options differently.

### Package install

Install the plugin as a published package and pass its options through the
`plugins` array:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    {
      "package": "opencode-request-concurrency-queue",
      "options": {
        "providers": {
          "myprovider": 2,
          "openrouter": 4
        }
      }
    }
  ]
}
```

The `options` object is passed to the plugin as `ctx.options`. Restart OpenCode
after changing it.

### Deployed directory (recommended)

The repository deployer copies the plugin package into the global discovery
directory, where OpenCode loads it as a plugin directory:

```bash
./deployment/deployment.sh --global --target opencode --type plugin
```

The deployed copy lands at `~/.config/opencode/plugins/request-concurrency-queue`
and is recorded in the deploy log, so `--update` refreshes it and `--uninstall`
removes it. A deployed copy receives no `ctx.options`, so configure it through
the dedicated config file described below.

### Local file entry (manual alternative)

A `.ts` entry file in a plugin discovery directory is loaded directly and
bypasses the directory resolver. It also receives no `ctx.options`, so it reads
the same dedicated config file.

1. Create the global plugin directory:

   ```bash
   mkdir -p ~/.config/opencode/plugins
   ```

2. Add `request-concurrency-queue.ts` that re-exports the plugin:

   ```ts
   export { default } from "/absolute/path/to/ai-modules/harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts"
   ```

3. Create the plugin config file:

   `~/.config/opencode/request-concurrency-queue.json`:

   ```json
   {
     "providers": {
       "openrouter": 4
     }
   }
   ```

   Add one entry per provider. Set the path with
   `OPENCODE_REQUEST_CONCURRENCY_CONFIG` if the file lives elsewhere. The
   repository's `config.example.json` is a starting point.

4. Restart OpenCode.

Environment variables remain an optional fallback for environments where a
config file is inconvenient:

```bash
export OPENCODE_REQUEST_CONCURRENCY_PROVIDERS='openrouter=4'
export OPENCODE_REQUEST_CONCURRENCY_LOG=1
```

### Precedence

Plugin options win over the config file, which wins over environment variables,
which win over defaults:

1. `options.providers` / `options.maxConcurrency` / `options.log`
2. `~/.config/opencode/request-concurrency-queue.json`
3. `OPENCODE_REQUEST_CONCURRENCY_PROVIDERS` / `OPENCODE_REQUEST_CONCURRENCY_MAX` / `OPENCODE_REQUEST_CONCURRENCY_LOG`
4. Defaults

## Options

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `providers` | string array or provider map | none | Providers to gate. Each provider gets its own queue and maximum. An empty list or object disables the plugin. |
| `maxConcurrency` | positive integer | `1` | Shared maximum for the provider-list form. |
| `log` | boolean | `false` | Debug logging of initialization, acquire, and release events with per-provider queue depth. It does not expose structured state. |

The provider map is the canonical form:

```json
{
  "providers": {
    "myprovider": 2,
    "openrouter": 4
  }
}
```

Each value is that provider's maximum concurrent requests. The list form
`["myprovider", "openrouter"]` applies the shared `maxConcurrency` to every
listed provider. An empty list or object disables the plugin.

Set each maximum to the provider plan's concurrency. A value of 1 is safe but
serializes that provider's requests.

## Provider matching

The plugin matches `event.model.providerID`, the provider ID from
`opencode.json`. That is the stable key: it identifies the configured provider
entry even when the base URL changes, and it keeps separate limits for two
provider entries that happen to share an endpoint.

The endpoint string is not needed for the normal case. Endpoint matching would
only matter if several provider entries were indistinguishable by ID, which
the OpenCode configuration does not require. The current version does not match
on the URL.

## State and observability

The `log` flag is only debug logging. It prints one line when the plugin
initializes and one line per acquire and release, including the provider ID and
that provider's active and queued counts. It is off by default.

The plugin does not yet expose a structured state API. A future OpenCode
desktop GUI panel can read `active`, `queued`, and `max` per provider and render
utilization as `active / max` and demand as `(active + queued) / max`. A useful
color model is green when `active < max` and `queued == 0`, amber when the
provider is at capacity with no queue, and red when `queued > 0` because demand
exceeds the configured capacity. The GUI panel is tracked separately.

## Development

```bash
bun install
bun test
bun run typecheck
```

## Limitations

- The plugin does not handle token-budget limits such as a provider's
  `burst_protection`, nor request-size rejections such as
  `cold_request_too_large`. Those are separate from concurrency.
- The queue is in memory. A server restart clears it.
- A request that never completes holds its slot until the user aborts the
  session or the session fails. This is intentional: the plugin has no timeout.

## License

MIT. See the repository [LICENSE](../../../LICENSE).
