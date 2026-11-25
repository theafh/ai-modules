# charter-guardrail

An OpenCode 2 plugin that runs the repository's shared
`charter_guardrail.sh` from a permission hook, so an attempt to mutate the
repo-root `CHARTER.md` is denied with the same policy Claude, Codex, and
Antigravity already run.

The package carries no policy of its own. It maps an OpenCode permission event
onto the script's `{tool_name, tool_input, cwd}` stdin envelope and turns a
non-zero exit into a `deny` effect whose message is the script's stderr. The
script stays the single source of truth for what a charter mutation is and when
the `guardrail/charter-*` branch allows one.

## Where the script resolves

The plugin package is deployed to `<config>/plugins/charter-guardrail`, and the
deployer copies the shared script to the sibling `hooks` directory. The plugin
therefore resolves the script at `../../hooks/charter_guardrail.sh` from its own
directory:

- `~/.config/opencode/hooks/charter_guardrail.sh` in global scope.
- `<project>/.opencode/hooks/charter_guardrail.sh` in project scope.

Deploy both artifact types together:

```bash
./deployment/deployment.sh --global --target opencode --type plugin,hook
```

When the script is absent the plugin logs one warning and stays inactive rather
than blocking every action. When the script is present but cannot be executed,
the hook fails closed and denies the action.

## Envelope mapping

| Permission event | Script envelope |
| --- | --- |
| `action: "edit"` (gates `edit`, `write`, and `patch`) | one envelope per resource, each with `tool_input.file_path` set to the resource |
| `action: "shell"` | one envelope with `tool_input.command` set to the event's command segments joined by a newline |
| any other action | no envelope, so the script is not run |

`cwd` is the plugin context's `location.directory`, which the script resolves a
relative `file_path` against. A file resource arrives relative to the session
directory; a shell resource is the raw command text the host parsed, which is
what the script's shell scanner reads.

## Limits

- **Subagent bypass.** Whether a permission hook fires inside a subagent spawned
  through the subagent tool is unverified on V2, and the V1 report (OpenCode
  issue #5894) recorded that `tool.execute.before` did not intercept subagent
  tool calls. An agent could route a `CHARTER.md` edit through a subagent and
  slip past the guard. Treat this as a materially weaker guarantee than Claude or
  Codex until it is verified on the pinned version.
- **`permission.evaluate` skips configured denies.** An explicit configured
  `deny` is final and never invokes the hook, so the guard must be mounted behind
  an `ask` or `allow` posture. OpenCode's native permission rules can deny a path
  declaratively but cannot express the guard's "unless on a charter/guardrail
  branch" condition.
- **No `apply_patch`, lowercase actions.** OpenCode has no `apply_patch` tool, so
  that arm of the script never fires here. The permission action for a shell call
  is `shell`, not `bash`.

## Development

```bash
bun install
bun test
bun run typecheck
```

The tests drive `src/guardrail.ts` with a stubbed script runner. The script's own
block and allow behaviour is covered harness-independently by
`tests/charter_guardrail/script_tests/run.sh`.

## License

MIT. See the repository [LICENSE](../../../LICENSE).
