---
title: Install a local OpenCode plugin
created: 2026-11-05
updated: 2026-11-05
type: procedure
tags: [opencode, plugin, deployment]
confidence: high
checked: 2026-11-05
---

# Install a local OpenCode plugin

Deploy the plugin package into an OpenCode plugin discovery directory and
restart the server, because plugin `setup` runs at server startup. This
repository's deployer performs that copy and records it in the deploy log, so
the same command updates and uninstalls the plugin later.

## When this applies

Use this procedure for a plugin that lives in this repository's
`harness-plugins/` tree and is not published to a registry. Use the `plugins`
array with a package name instead when the plugin is installed from a registry
and the target OpenCode release resolves that package.

## The rule

1. Run the deployer scoped to plugins and the OpenCode target:

   ```bash
   ./deployment/deployment.sh --global --target opencode --type plugin
   ```

2. Confirm the package landed at
   `~/.config/opencode/plugins/<plugin-id>`. The directory name is the plugin
   ID and matches the `id` in the plugin's `Plugin.define` call.
3. Create the plugin's dedicated config file in the OpenCode config directory,
   or set the path with the plugin's config-path environment variable. A
   deployed directory receives no `ctx.options`, so a plugin that takes
   configuration reads it from that file. The `request-concurrency-queue`
   plugin reads `~/.config/opencode/request-concurrency-queue.json`.
4. Restart the OpenCode service with `opencode service restart`. Plugin setup
   runs at server startup, so a running service keeps the previously loaded
   plugin set until then.
5. Confirm the plugin loaded with `opencode plugin list`, which reports the
   service's loaded set rather than rescanning the disk. A plugin missing from
   that list after a deploy is usually a service that has not been restarted
   since the copy, not a broken package. Confirm the behavior itself by
   exercising what the plugin changes.

A manual `.ts` entry file remains a supported alternative when the deployer is
not in use: create `~/.config/opencode/plugins/<plugin-id>.ts` that
default-exports the plugin from its source path. The file entry bypasses the
directory resolver and receives no `ctx.options` either, so the config-file
step above applies unchanged.

## Pitfalls and edge cases

- A local package **directory** can fail to load under Bun when the resolver
  cannot find a subpath the manifest names. Prefer the deployer's copy, and fall
  back to the `.ts` entry file if a directory refuses to load. See
  [OpenCode plugin loading](../concepts/opencode-plugin-loading.md).
- A file entry and a deployed directory both lack the `options` object from the
  `plugins` array. Use the plugin's dedicated config file, its environment
  fallback, or publish it as a package.
- Restart the server after changing the plugin or its configuration; a running
  server keeps the previously loaded plugin until then. Use
  `opencode service restart`, and read `opencode plugin list` only after it
  returns, because that command reports the service's in-memory plugin set.
- The plugin runs in the OpenCode server process. It cannot coordinate a
  separate server process or another application using the same provider key.
- A redeploy replaces the deployed directory, so keep hand edits out of
  `~/.config/opencode/plugins/`; the repository copy is the source of truth.

## See also

- [Request concurrency queue](../concepts/request-concurrency-queue.md)
- [OpenCode plugin loading](../concepts/opencode-plugin-loading.md)
- [The deployment model](../concepts/deployment-model.md)
