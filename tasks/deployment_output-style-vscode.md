---
description: Deploy the output style to GitHub Copilot in VS Code as a user-profile instructions file in its own configuration root, with no activation key required.
scope: deployment
created: 2026-08-07T23:39:03
updated: 2026-08-07T23:39:03
status: open
reported-by: Andreas Hoffmann
---

# Deploy the output style to VS Code Copilot

## Goal

GitHub Copilot in VS Code receives the repository's output style as a generated instructions file in its own user-profile configuration root, applying across every workspace with no activation key to set. This is the cheapest of the non-Claude targets, since deployment and activation are the same act.

## Context

This builds on [the Claude groundwork task](deployment_output-style-claude-groundwork.md), which creates the repo-root source directory, the `style` artefact type, and the deploy-log restore behaviour. Ship that first; this task adds one target and no new machinery.

The `harness_portability` skill records the mechanism in the `<vscode_counterparts>` and `<vscode_delivery_modes>` blocks of its `<claude_output_styles>` section. The essentials: instructions files combine rather than compete, the user-profile instructions root applies across every workspace and sits above repository and organization instructions in the documented precedence, and nothing has to be switched on for a file placed there to take effect. VS Code is append-only, so the deployed prose competes with default guidance rather than displacing it, which the docs should say plainly.

One trap belongs in the implementation. Copilot also reads a rules folder and a `CLAUDE.md` from the Claude configuration tree, and the documentation presents that path alongside its own. Those are adoption roots, and the standing rule in the harness portability skill's policy is to deliver a per-harness variant into the target's own native root and treat adoption as contamination. Writing the variant into the Claude tree would put one file in front of two harnesses and hand VS Code a Claude-shaped artefact, so the deploy writes only into Copilot's own instructions root.

## Approach

Generate a VS Code variant of the style and write it into Copilot's user-profile instructions root as a single Markdown file. Confirm during implementation whether that root expects a plain `.md` extension or the `.instructions.md` form the workspace-scoped files use, and follow whichever the installed VS Code accepts; record the answer in the harness skill's `<vscode_counterparts>` block so the next reader does not repeat the check.

Generate rather than copy. Strip the Claude frontmatter, which this target does not implement, and rewrite the one clause in the style body naming Claude's `keep-coding-instructions` mechanism, using the per-tool substitution facility in `deployment/deployment.conf` that the groundwork task's Claude path already leaves in place.

**Out of scope:**

- The source directory, the `style` artefact type, and the log restore behaviour, all owned by [the Claude groundwork task](deployment_output-style-claude-groundwork.md).
- Delivering the style through a Copilot agent plugin, which has no instructions component, so its only routes are a selectable agent or an on-demand skill and neither is standing.
- Writing anything into the Claude configuration tree to reach this target, which the **Context** rejects as adoption rather than delivery.

## Acceptance

- A dry run restricted to the style type and the VS Code target reports exactly one file write, into Copilot's own user-profile instructions root and nowhere in the Claude configuration tree.
- A real deploy into a scratch target produces a Markdown file whose extension matches what the installed VS Code accepts, with the answer and the version tested recorded in the harness skill's `<vscode_counterparts>` block.
- The deployed file contains no Claude output-style frontmatter keys, verified by searching it for `keep-coding-instructions` and `force-for-plugin` and finding neither.
- The deployed body contains no reference to Claude's keep-coding-instructions mechanism, and the clause that named it reads correctly for a harness that only appends.
- Uninstalling removes the deployed file and leaves any other instructions files in the same root untouched.
- `deployment/README.md` gains a VS Code row for the style type naming the instructions root, stating that no activation key is needed, and stating that this target appends rather than replaces, so adherence is weaker than on Claude.
