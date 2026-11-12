# request-concurrency-queue

An OpenCode 2 plugin that limits concurrent model requests per provider through
one process-wide FIFO queue shared by every open location.

It is built for providers that reject excess concurrent requests instead of
queueing them. The plugin keeps OpenCode from exceeding a provider's
concurrency allowance instead of relying on retries after a provider rejects a
request.

## Behavior

- One FIFO queue per configured provider is shared by the whole OpenCode server
  process. The configured maximum caps concurrent requests across every open
  location (project), not once per location.
- Primary model requests (the agent loop) to a configured provider acquire a
  slot before they are sent. Auxiliary model requests (title, compaction, and
  generate) acquire no slot and are outside the provider cap: the runtime gives
  no per-request failure signal for them, so a slot held by an auxiliary request
  that failed before its response headers would have no release path.
- The slot is released when the response body finishes, when the attempt fails
  and is retried, when the session goes idle, or when the session is deleted or
  interrupted.
- A retry releases only the slot of the attempt that failed, so a concurrent
  request's slot stays held.
- When no slot is free, the request waits in a FIFO queue. The oldest waiting
  request is served first.
- There is no timeout. A request waits until a slot is released or the request
  is aborted.
- The queue counts in-flight requests, not sessions. A session that is running
  a tool or waiting for a subagent does not hold a slot.
- The queue spans one server process. A separate OpenCode server process, or
  another application using the same provider key, keeps its own queue.
- The first plugin instance in the process fixes the provider set and maximums
  for the process. A later instance configured differently keeps the existing
  queue and logs the mismatch (with `log` enabled), so one location cannot
  change another location's cap.

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

The desktop sidecar sends the plugin's stdout to `/dev/null`, so `log` output
never reaches `opencode.log` or the status bar. The bar and its dialog feed are
the desktop observability surface: the dialog lists recent concurrency
transitions, and `log` remains for terminal runs. The feed records identifiers
and counts only; it never carries prompts, message content, API keys, or tool
arguments.

The plugin serves a read-only status snapshot over the shared
`request-concurrency-queue` RPC definition. Every location's handler reads the
same process-wide queue, so the snapshot is the same whichever location serves
it. The snapshot reports one record per configured provider with `providerID`,
`active`, `queued`, `max`, utilization (`active / max`), and demand
(`(active + queued) / max`). Providers with no configured limit do not appear.
The snapshot also carries the most recent 50 transitions, oldest first, each
with a timestamp, provider ID, kind (`acquired`, `queued`, `released`,
`dequeued`), session ID, active count, and queued count. A release handoff
records `released` for the releasing session and then `acquired` for the waiter.
The server emits a `changed` event on every count-changing transition: a free
slot acquired, a request joining the wait queue, a queued request aborted, a
release that frees a slot, and a release that hands the slot to the next
waiter. Every instance forwards the shared queue's transitions, so the panel
sees them whichever location emitted them.

The desktop GUI part ships as the prebuilt `./gui-experimental` bundle and adds
a full-width status bar in the window's bottom slot. The bar is the only
persistent desktop surface. It is visible in every window, including Home, and
shows each provider as one `X/Y` count, where `X` is active plus queued and `Y`
is the configured maximum, so a fully loaded provider reads `8/8` and an
overloaded one reads `12/8`. The count is coloured by its own load,
`(active + queued) / max`; hovering it reports how many slots are in demand.
Clicking the bar opens a larger **Concurrency** dialog with the provider table
and the activity feed. The bar hides itself when no provider is configured and
until the first status fetch settles. It reads the built-in server, because the
queue is process-wide and every location returns the same snapshot.

The bar's subscription refetches on every `changed` event and on a slow
interval, so a missed event recovers, and the dialog renders that same snapshot.
Each provider gets one row with its in-flight count, configured maximum, and
queue depth as absolute numbers, and its utilization and demand as percentages.
A header labels the columns, and the counts are right-aligned in tabular figures
so a row reads as one line. The numbers are coloured on a six-anchor load scale:
dark green at 0%, light green at 100%, light yellow at 150%, orange at 200%,
light red at 250%, and dark red from 300% on, interpolated between those anchors
and held at dark red above 300%. The active count and utilization use the
`active / max` load, while the combined count, queued count, and demand use
`(active + queued) / max`. Below the provider rows, a compact monospace feed
lists the recent transitions newest first with their timestamp, kind, provider,
session, and counts; it renders the newest 20 and scrolls. When a status fetch
fails, the panel shows `Status unavailable` and no provider rows until a later
fetch succeeds.

## Development

```bash
bun install
bun test
bun run typecheck
bun run build:gui
```

## Limitations

- The plugin does not handle token-budget limits such as a provider's
  `burst_protection`, nor request-size rejections such as
  `cold_request_too_large`. Those are separate from concurrency.
- The queue is in memory. A server restart clears it.
- A primary request that never completes holds its slot until the user aborts
  the session or the session fails. This is intentional: the plugin has no
  timeout.

## License

MIT. See the repository [LICENSE](../../../LICENSE).
