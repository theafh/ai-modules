# request-concurrency-queue

An OpenCode 2 plugin that admits concurrent model requests per provider through
one process-wide scheduler shared by every open location.

It is built for providers that reject excess concurrent requests instead of
queueing them. The plugin keeps OpenCode from exceeding a provider's
concurrency allowance instead of relying on retries after a provider rejects a
request.

## Behavior

- One scheduler per configured provider is shared by the whole OpenCode server
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
- When no slot is free, the request waits in a queue. The scheduler admits the
  first waiting request that fits the concurrency, token-budget, and
  context-in-flight gates, so a smaller request can start ahead of an older one
  that does not yet fit.
- The queue itself has no timeout. A request waits until it is admitted or the
  request is aborted. `scheduler.queueDeadlineMs` is an optional aid, off by
  default: when the client's own header timeout counts time spent waiting in
  the queue, a long wait is killed by the client anyway, and setting a shorter
  deadline only replaces that opaque error with a `QueueTimeoutError` that
  names the queue. It never prevents a failure the client would not have
  caused, and it can reject a request that a deep-but-healthy queue would have
  served. Leave it at `0` unless you want that clearer error.
- A provider that stops serving is detected by a circuit breaker. Two
  consecutive attempts that produce no response — a transport stall, a header
  timeout, or a `5xx` — open the circuit for `scheduler.breaker.cooldownMs`
  (default 60000). In `fail` mode (the default) every queued request is
  rejected at once and new requests fail fast with a `CircuitOpenError`, so a
  dead provider cannot keep growing the queue. In `wait` mode requests stay
  queued and are admitted when the cooldown ends. After the cooldown one probe
  is allowed: a success closes the circuit, another stall reopens it. A `429`
  never counts as a stall, because the provider answered.
- A waiting request whose session ends — idle, deleted, failed, or interrupted —
  is removed from the queue and rejected, so it is never dispatched for a
  session nobody is listening to. A request already holding a slot is released
  as before.
- When a provider has a token budget configured, a request must also fit that
  provider's new-context allowance. It waits for the bucket to refill, and a
  `Retry-After` on a `429` pauses the whole provider for the stated time.
- With `adaptive` enabled, the effective maximum halves only on a capacity
  signal: a concurrency `429`, a transport failure such as a header timeout, or
  a `5xx`. A `429` carrying `burst_protection` pauses the token bucket instead,
  and an invalid-request, context-size, or plan/quota error never narrows the
  width. Four clean completions restore one step, up to the configured maximum,
  which remains the hard ceiling.
- With `subagents` configured, the plugin wraps the built-in `subagent` tool and
  limits how many child sessions run at once. Because that tool returns at
  launch, each permit is bound to the child's session ID and released when the
  child goes idle; launches beyond the limit wait in FIFO order. With
  `hostAware`, the effective ceiling also drops from the machine's one-minute
  load average and a critical-memory floor, so a loaded host queues fan-out
  instead of accepting it.
- A plugin reload keeps queued work. When the last instance is disposed the
  store stays adoptable for a grace period (`reloadGraceMs`, default 5000), so
  a redeploy hands the queue, its waiters, and the live child sessions to the
  new instance instead of cancelling them. Admission pauses during that window
  so a freed slot cannot be dispatched ungated. If no reload arrives, the grace
  expires and the waiters are cancelled with a message that names the unload.
- The queue counts in-flight requests, not sessions. A session that is running
  a tool or waiting for a subagent does not hold a slot.
- The queue spans one server process. A separate OpenCode server process, or
  another application using the same provider key, keeps its own queue.
- The first plugin instance in the process fixes the provider set and maximums
  for the process. A later instance configured differently keeps the existing
  queue and logs the mismatch (with `log` enabled), so one location cannot
  change another location's cap.

## Configuring from the window

Open the Concurrency dialog from the status bar to edit the settings in place:
provider maximums, the token budget, the context cap and lanes, the circuit
breaker, the subagent ceiling, and `adaptive`. Each field is checked on the
server before anything is written; a rejected value returns an error list and
leaves the file untouched. **Save** writes the config file atomically and
applies the change to the running store, so in-flight requests and queued
waiters survive it. Adding or removing a provider changes the set of
schedulers those requests are already using, so that one edit reports
`restartRequired: true` instead of half-applying.

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
     },
     "tokens": {
       "openrouter": {
         "capacity": 400000,
         "refillPerMinute": 400000,
         "safetyFactor": 1.1
       }
     },
     "adaptive": true,
     "scheduler": {
       "contextCapacity": 1200000,
       "contextCeiling": 1200000,
       "queueDeadlineMs": 0,
       "breaker": { "threshold": 3, "cooldownMs": 60000, "mode": "fail" }
     },
     "subagents": {
       "max": 8,
       "hostAware": true
     }
   }
   ```

   `tokens` is optional and per provider. `capacity` and `refillPerMinute` are
   the provider's documented new-context budget; `safetyFactor` multiplies the
   request-size estimate, and the estimate itself already errs high (3.5 bytes
   per token). `adaptive` is optional and defaults to off.
   `scheduler` is optional. `contextCapacity` caps the total context tokens in
   flight, which is what a wide fan-out exhausts even when the request count is
   within the provider's concurrency allowance; `0` disables the cap.
   `contextCeiling` bounds its adaptive recovery after transport stalls.
   `queueDeadlineMs` bounds how long a request may wait for admission, and
   `breaker` decides how a provider that stops answering is handled.
   `reserveShare` keeps part of the token budget available for requests above
   `smallShare` of capacity, and `agingMs` lets an old waiter ignore that
   reserve. A request that cannot be admitted waits before it takes a slot, so a
   large burst cannot starve small requests behind it. A waiting request is
   checked again as soon as the bucket refills, the reserve lifts, or the
   cooldown ends, and at least every two seconds, so it never depends on another
   request finishing before it can start.
   `subagents` is optional. `max` is the hard ceiling on live child sessions and
   is required when the section is present, because the right number follows
   each account's own concurrency allowance. `hostAware` defaults to `false`;
   set it to `true` to let the machine's load average lower the ceiling (never
   below one) and queue the rest.

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
waiter. Every instance forwards the shared queue's transitions, so the bar's
dialog sees them whichever location emitted them.

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
so a row reads as one line. The numbers are coloured on an eight-anchor load scale:
dark green at 0%, light green at 100%, light yellow at 150%, orange at 200%,
light red at 250%, dark red at 300%, dark pink at 350%, and magenta from 400% on,
interpolated between those anchors and held at magenta above 400%. The active
count and utilization use the
`active / max` load, while the combined count, queued count, and demand use
`(active + queued) / max`. Below the provider rows, a compact monospace feed
lists the recent transitions newest first with their timestamp, kind, provider,
session, and counts; it renders the newest 20 and scrolls. When a status fetch
fails, the bar shows `Status unavailable` and the dialog shows no provider rows,
until a later fetch succeeds.

## Development

```bash
bun install
bun test
bun run typecheck
bun run build:gui
```

## Limitations

- A provider's `burst_protection` is handled only when that provider has a
  `tokens` entry, because the budget numbers are provider-specific. A
  request-size rejection such as `cold_request_too_large` is not handled: the
  provider answers it, and the plugin neither predicts nor retries it.
- The queue is in memory. A server restart clears it.
- A primary request that never completes holds its slot until the user aborts
  the session or the session fails. This is intentional: the plugin has no
  timeout.

## License

MIT. See the repository [LICENSE](../../../LICENSE).
