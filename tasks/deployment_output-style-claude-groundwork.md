---
description: Track the natural-language output style in a repo-root styles/ directory and add a style artefact type to the deployment script that deploys it to Claude as file plus outputStyle key.
scope: deployment
created: 2026-08-07T23:39:03
updated: 2026-08-07T23:39:03
status: open
reported-by: Andreas Hoffmann
---

# Track output styles in the repo and deploy them to Claude

## Goal

The repository holds its output styles as tracked source, and `make deploy` installs them into a Claude configuration so the style governs every Claude session on the machine. Today the working style exists only as an untracked file in the user's own Claude configuration directory, so it lives on one machine, has no history, and cannot be reviewed. After this task it is versioned in the repo and reproducible on any machine by running the deploy.

This task also lays the groundwork every later harness reuses: the source directory, the artefact type, the discovery root, and the uninstall behaviour for a deployed configuration key. The sibling harness tasks listed under **Context** each add one target on top of it and add no new machinery.

## Context

An output style is a Claude-only component. The `harness_portability` skill documents the mechanism in its `<claude_output_styles>` block, and the two facts this task depends on are in `<two_delivery_modes>` and `<style_locations_and_activation>`: a machine-wide style is two placements rather than one, a Markdown file in the user configuration tree plus an `outputStyle` key in the user settings file, and nothing in the plugin system writes either of them. A deploy step is therefore the only route to that mode, which is why this work belongs to the deployment script rather than to a plugin.

The style file itself is the one currently in use on the reporting user's machine, under their Claude configuration directory as `output-styles/natural-language.md`. It carries `keep-coding-instructions: true`. The implementer copies that file into the repo unchanged, frontmatter included, since Claude reads the frontmatter and strips it before injection.

Deployment mechanics that this task extends, all in `deployment/`:

- Artifact discovery is plugin- and folder-based today, described in `deployment/README.md` under the heading `## Artifact Discovery`, and resolves `plugins/<plugin>/<asset-folder>/` with the folder name selecting the type. This task adds the first asset source outside that tree, so discovery grows a second root.
- `deployment/deployment.sh` already merges a JSON key into a target settings file through its `merge_json_key` function, used for Claude hooks. The Claude style key reuses that path.
- `deployment/deployed_artefacts.log` is tab-separated with four fields per line, destination then target then type then source, and a merged key is already logged with the destination written as `<target-file>[<key>]`. There is no field for a previous value, which is what the restore requirement below adds.
- `deployment/deployment.conf` is parsed for per-tool `disallow:` and `replace:` lines, so it is the natural home for a line naming which style is the active one.

Sibling tasks, each adding one target on top of this groundwork and each waiting for it to ship: [Cursor](deployment_output-style-cursor.md), [Codex](deployment_output-style-codex.md), [OpenCode](deployment_output-style-opencode.md), [Antigravity](deployment_output-style-antigravity.md), and [VS Code Copilot](deployment_output-style-vscode.md).

## Approach

Add a repo-root `styles/` directory holding one Markdown file per style, in Claude's own output-style format. Keep it out of `plugins/` and do not register it as a Claude plugin component. A plugin-root `output-styles/` folder would be auto-discovered by Claude and produce a second, namespaced copy of the same style that is availability-only and competes with the deployed one; the repo's standing rules also make the plugin the unit of distribution, and a style belongs to no single plugin's capability. A repo-root directory for a repo-wide asset belonging to no skill is what the standing repo rules permit on explicit request, and this task is that request.

Add a `style` artefact type to `deployment/deployment.sh`, selectable through the existing `--type` filter, discovering each top-level `*.md` file in the repo-root `styles/` directory. Settle the type name and the discovery root as part of this task rather than later, because both are recorded in the deploy log and renaming either one afterwards means migrating log entries that already exist.

For the Claude target, deploy in two parts. Copy the style file verbatim, frontmatter included, into the Claude user configuration tree under `output-styles/<name>.md`. Then merge `"outputStyle": "<name>"` into the Claude user settings file through the existing key-merge path, so the deployed style is active rather than merely available. Take the name from a per-tool line in `deployment/deployment.conf` naming the active style, which is where it has to live: the output-style frontmatter schema is strict at four keys and rejects a fifth, so a marker inside the style file would break Claude's own loader.

Extend the deploy log so a merged key can be reversed to what it replaced. On the first write of a key, record the previous value, or an explicit marker when the key was absent. On uninstall, restore that recorded value, and delete the key only when nothing was recorded. Restoring to a hardcoded harness default is wrong here, because the default is whatever the user had rather than a vendor constant, and a user who had selected a built-in style would lose it. The storage shape is the implementer's choice between a further log field and a sidecar file, provided existing four-field log lines keep parsing.

Update `README.md` at the repo root and `deployment/README.md` so both describe the new artefact type, the new discovery root, the `deployment.conf` line naming the active style, and the restore behaviour on uninstall.

**Out of scope:**

- Every harness other than Claude, each owned by the sibling task named for it under **Context**.
- Transforming the style body for a harness that cannot read Claude's format, which is per-target work owned by those same sibling tasks.
- Shipping the style as a Claude plugin component, which the **Approach** rejects outright rather than defers, since the plugin route cannot reach the machine-wide mode this task delivers.

## Acceptance

- A repo-root `styles/` directory exists and holds the natural-language style as a tracked Markdown file whose content matches the file currently deployed in the reporting user's Claude configuration directory, frontmatter included.
- `grep -c "output-styles" plugins/*/.claude-plugin/plugin.json` returns no match, and no plugin directory contains an `output-styles/` folder, confirming the style is not also shipping as a plugin component.
- `deployment/deployment.sh --help` lists `style` among the values accepted by `--type`.
- A dry run restricted to the new type and the Claude target reports two actions for one style: a file copy into the Claude `output-styles/` directory, and a key merge into the Claude user settings file.
- A real deploy into a scratch target directory produces the style file byte-identical to the repo source, and the target settings file parses as JSON with `outputStyle` set to the name given by the `deployment.conf` line.
- Deploying twice in a row leaves the same single log entry per artefact and the same settings value, with no duplicate lines.
- Running the deploy against a scratch settings file that already sets `outputStyle` to a different value, then uninstalling, leaves that original value in place rather than the deployed one or an absent key.
- Running the deploy against a scratch settings file with no `outputStyle` key, then uninstalling, leaves the key absent rather than set to any default.
- Log lines written before this change still parse after the change, verified by running an uninstall dry run against a log containing four-field lines.
- `README.md` and `deployment/README.md` both describe the `style` type, its discovery root, the `deployment.conf` line naming the active style, and the uninstall restore behaviour.
