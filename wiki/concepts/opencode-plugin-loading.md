---
title: OpenCode plugin loading
created: 2026-11-05
updated: 2026-11-05
type: concept
tags: [opencode, plugin, discovery, deployment]
confidence: high
checked: 2026-11-05
---

# OpenCode plugin loading

An OpenCode 2 plugin is a module that exports a `Plugin.define` part, and
OpenCode loads it from a plugin discovery directory or from the `plugins` array
in `opencode.json(c)`. The two routes differ in what the loader resolves and in
whether the plugin receives options, and that difference decides how a plugin
that takes configuration is packaged.

## Definition and explanation

A plugin's discovery roots are its own config tree. Globally they are
`~/.config/opencode/plugins/<id>`, and per project they are
`.opencode/plugins/<id>`. Each entry is either a directory holding the plugin
package or a single `.ts` file.

The module contract is small. A plugin file default-exports
`Plugin.define({ id, setup })`, the `id` matches the directory name, and `setup`
receives a context carrying `session.hook`, `event.subscribe`, `command`,
`skill`, and `options`. The parts a plugin may export are split by surface: the
server part is the package root, `./tui` reaches only the terminal UI, and
`./gui-experimental` reaches only the desktop app. The server part is the one
shared origin, because every client reads the server's command list and
sessions.

## Current state of knowledge

**Runtime and dependencies.** OpenCode 2 runs on Bun and supplies
`@opencode/plugin` from its own runtime, so a plugin directory needs no
`node_modules` to load. The dependency belongs in `package.json` for local type
checking and tests, not for deployment. A plugin copied into a discovery
directory therefore works as a plain source tree.

**Options arrive only through the `plugins` array.** A plugin listed there as a
package receives its `options` object as `ctx.options`. A plugin discovered as a
directory or a `.ts` file receives no `ctx.options`, so a plugin that takes
configuration needs a second channel: a dedicated JSON config file read at
`setup` time, with environment variables as a fallback. The two channels
compose by precedence rather than replacing each other, which lets a package
install and a directory install share one configuration model.

**Directory resolution is the fragile route.** The V2 loader resolves a local
package directory through its host resolver, which can fail under Bun when a
subpath the manifest names is missing. A `.ts` entry file bypasses that
resolution and is the narrower, more predictable load path. Deploying the
package as a directory and letting the loader read its `package.json` is the
path this repository's deployer takes, and both remain supported.

**Reload behaviour.** Skills and commands are read when the server builds its
command list, so a command-contributing plugin picks up an installed skill
without a restart. Plugin `setup` itself runs at server startup, so a changed
plugin needs a restart to take effect.

## Open questions and debates

Whether the directory route should be preferred over the `.ts` file entry is
not settled by the loader contract: the file entry is the narrower, more
predictable load path, and the directory is the packaging-friendly one. The
practical resolution is to ship the directory and document the file entry as a
manual alternative, which is what
[the deployer's plugin handling](../concepts/deployment-model.md) does.

## Related concepts

- [The deployment model](deployment-model.md)
- [Install a local OpenCode plugin](../procedures/install-a-local-opencode-plugin.md)
- [SST OpenCode](../entities/sst-opencode.md)

## Derived from

- OpenCode 2.2.5 plugin API types from `@opencode/plugin`.
- Local load probes against an installed OpenCode 2.2.5 desktop build.
