---
description: "Add a harness-plugins discovery root and the plugin artifact type, so a self-contained harness plugin package deploys as one directory."
scope: deployment/deployment.sh
created: 2026-11-05T19:33:23Z
updated: 2026-11-05T19:47:00Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Deploy harness plugin packages as a directory artifact

## Goal

The deployer discovers and installs a harness plugin package. The unit is the
package directory rather than a file inside an asset folder, because a harness
plugin carries its own manifest, source, tests, and README and the harness
loads it as a plugin directory.

## Context

The deployer's two roots both express a harness's *asset* model: `plugins/<plugin>/<asset-folder>/`
yields one artifact per file or per skill directory, and repo-root `styles/`
yields one artifact per style file. A plugin package fits neither. It is a
single installable unit whose internal files mean nothing to the deployer, and
its package manifest is the harness's own entry point rather than something the
deployer generates.

Only OpenCode has a plugin directory concept among the supported targets, so the
type has exactly one target today.

## Approach

Add `harness-plugins/<harness>/` as a third discovery root. Each immediate
subdirectory carrying a `package.json` is one artifact of the new `plugin` type,
carrying the repo-relative path `harness-plugins/<harness>/<name>`. The manifest
is the membership test: a `node_modules` tree sits beside the packages after a
local `bun install`, and without the test it would be discovered as a plugin and
copied into the plugin discovery root as one. Hidden directories are skipped
too, and discovery honours the type filter like the other roots.

Install the type by copying the package whole into the target's plugin
directory, applying the configured replacement rules to the copy, then pruning
any `node_modules` tree from the copy. The harness supplies the plugin API from
its own runtime, so the deployed package needs no dependency tree; pruning also
keeps a `replace:` rule from walking every file of one. Skip every target that
has no plugin directory concept and say so, so a run against all targets reports
the skip rather than failing.

Add `plugin` to the valid type set and to the `--type` documentation.

A whole-directory copy keeps the existing deploy-log, `--update`, and
`--uninstall` behaviour working unchanged: one log line per package, replayed
by `--update` and removed by `--uninstall` as any other artifact is.

Removing the target before copying is what makes a redeploy faithful rather than
additive: a component deleted or renamed upstream is absent from the target
after the next deploy, because the target is recreated from the source instead
of merged over. Plugin configuration lives outside the package directory, in the
harness's own config tree, so replacing the package cannot reach it, and a
global-mode deploy backs up that config tree before touching anything.

## Acceptance

- Discovery emits one `plugin` artifact per immediate subdirectory of
  `harness-plugins/<harness>/` that carries a `package.json`, with the
  repo-relative path as the source.
- A directory without a `package.json`, such as a `node_modules` tree beside the
  packages, is not discovered as a plugin.
- `--type plugin` selects them and other type filters exclude them.
- A plugin deploy copies the package into the OpenCode plugin directory, with no
  per-file transform and no `node_modules` tree in the copy.
- A plugin artifact does not appear in the skill, agent, command, or hook
  deploys.
- Every target without a plugin directory concept skips the artifact with a
  reported reason instead of failing the run.
- A redeploy after a component is deleted upstream leaves no trace of it in the
  target, and after a directory is renamed upstream the target carries only the
  new name.
- The deploy log records one entry per package, `--update` replays it, and
  `--uninstall` removes the directory.
- `tests/deployment/script_tests/run.sh` proves the copy, the vendor-tree
  exclusion at discovery and at install, the non-leak into the other types, the
  removal and rename propagation across a redeploy, the log entry, and the
  uninstall.
