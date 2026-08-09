---
description: Deploy the output style to GitHub Copilot in VS Code as an instructions file at global and project scope, each in its own configuration root, with no activation key required.
scope: deployment
created: 2026-08-07T23:39:03
updated: 2026-08-09T20:31:12
status: open
reported-by: Andreas Hoffmann
---

# Deploy the output style to VS Code Copilot

## Goal

GitHub Copilot in VS Code receives the repository's output style as a generated instructions file, deployed at whichever scope the run selects and needing no activation key at either. Under `--global` it lands in Copilot's own user-profile instructions root and applies across every workspace. Under `--project-dir` it lands in that project's own instructions directory and applies to work in that repository. This is the cheapest of the non-Claude targets, since deployment and activation are the same act in both scopes.

## Context

This builds on [the Claude groundwork task](archive/deployment_output-style-claude-groundwork.md), which creates the repo-root source directory, the `style` artefact type, and the deploy-log restore behaviour. Ship that first; this task adds one target and no new machinery.

The wiki records the mechanism on its [GitHub Copilot in VS Code](../wiki/entities/github-copilot-vs-code.md) page and in [system prompt substitution across harnesses](../wiki/comparisons/system-prompt-substitution-across-harnesses.md). The essentials: instructions files combine rather than compete, the user-profile instructions root applies across every workspace and sits above repository and organization instructions in the documented precedence, and nothing has to be switched on for a file placed there to take effect. VS Code is append-only, so the deployed prose competes with default guidance rather than displacing it, which the docs should say plainly.

One trap belongs in the implementation. Copilot also reads a rules folder and a `CLAUDE.md` from the Claude configuration tree, and the documentation presents that path alongside its own. Those are adoption roots, and the standing rule in the harness portability skill's policy is to deliver a per-harness variant into the target's own native root and treat adoption as contamination. Writing the variant into the Claude tree would put one file in front of two harnesses and hand VS Code a Claude-shaped artefact, so the deploy writes only into Copilot's own instructions root.

## Approach

Generate a VS Code variant of the style and write it as a single Markdown file, resolving the destination from the script's existing Copilot directory variable rather than a hardcoded path so the same code serves both scopes. Under `--global` that is Copilot's user-profile instructions root; under `--project-dir` it is that project's own instructions directory.

Confirm during implementation what each scope expects of the filename, since the workspace-scoped files use the `.instructions.md` form while the user-profile root may accept a plain `.md`. Follow whichever the installed VS Code accepts at each scope, and record both answers on the wiki's [GitHub Copilot in VS Code](../wiki/entities/github-copilot-vs-code.md) page so the next reader does not repeat the check. Where the project-scoped file supports an `applyTo` glob, write the value that scopes it to every file rather than leaving the field out, so the rule is unambiguously always-on.

Generate rather than copy. Strip the Claude frontmatter, which this target does not implement, and rewrite the one clause in the style body naming Claude's `keep-coding-instructions` mechanism, using the per-tool substitution facility in `deployment/deployment.conf` that the groundwork task's Claude path already leaves in place.

Close the instructions adoption path in the same pass, so the deployed file is the only route this style reaches VS Code by. VS Code reads user-level instructions from `~/.claude/rules` as well as its own root, and `chat.instructionsFilesLocations` maps a path to a boolean where a `false` disables it even when it is a documented default. Merge `{"~/.claude/rules": false}` into the user's VS Code settings through the script's existing key-merge function, which captures the prior value on first write and restores it on uninstall, and narrow the merge to that one path so every other entry the user set survives. The hook counterpart of this switch, covering `.claude/settings.json` and `~/.claude/settings.json`, belongs to [deployment_vscode-hook-routing.md](deployment_vscode-hook-routing.md); the two tasks merge sibling keys into the same settings file, so whichever lands second reuses the first's merge helper rather than adding a second one.

**Out of scope:**

- The source directory, the `style` artefact type, and the log restore behaviour, all owned by [the Claude groundwork task](archive/deployment_output-style-claude-groundwork.md).
- Delivering the style through a Copilot agent plugin, which has no instructions component, so its only routes are a selectable agent or an on-demand skill and neither is standing.
- Writing anything into the Claude configuration tree to reach this target, which the **Context** rejects as adoption rather than delivery.

## Acceptance

- A dry run under `--global` restricted to the style type and the VS Code target reports exactly one file write, into Copilot's own user-profile instructions root and nowhere in the Claude configuration tree.
- A dry run under `--project-dir` reports exactly one file write, into that project's own instructions directory, and touches nothing under the home directory.
- A real deploy at each scope produces a Markdown file whose extension matches what the installed VS Code accepts there, with both answers and the version tested recorded on the wiki's [GitHub Copilot in VS Code](../wiki/entities/github-copilot-vs-code.md) page.
- The project-scoped file carries an `applyTo` value scoping it to every file, so it is always-on rather than pattern-limited.
- The deployed file contains no Claude output-style frontmatter keys, verified by searching it for `keep-coding-instructions` and `force-for-plugin` and finding neither.
- The deployed body contains no reference to Claude's keep-coding-instructions mechanism, and the clause that named it reads correctly for a harness that only appends.
- Uninstalling removes the deployed file and leaves any other instructions files in the same root untouched.
- A global dry run reports a `chat.instructionsFilesLocations` merge setting `~/.claude/rules` to `false` and capturing the key's prior value, and an unrelated entry placed in that key beforehand survives the deploy.
- `deployment/README.md` gains a VS Code row for the style type naming the instructions root, stating that no activation key is needed, and stating that this target appends rather than replaces, so adherence is weaker than on Claude.
