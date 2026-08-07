---
description: Deploy the output style to Antigravity as an always-on rule, writing a marked block into the single global rules file and sizing the content for the per-file character cap.
scope: deployment
created: 2026-08-07T23:39:03
updated: 2026-08-07T23:39:03
status: open
reported-by: Andreas Hoffmann
---

# Deploy the output style to Antigravity

## Goal

Antigravity receives the repository's output style as an always-on rule, deployed by the same `style` artefact type the groundwork task adds. Because Antigravity's global rules live in one user-owned file rather than a directory, the deploy writes a delimited block into that file and removes exactly that block on uninstall, leaving the user's own rule content intact.

## Context

This builds on [the Claude groundwork task](deployment_output-style-claude-groundwork.md), which creates the repo-root source directory, the `style` artefact type, and the deploy-log restore behaviour. Ship that first; this task adds one target and no new machinery beyond the marked-block write described below.

The `harness_portability` skill records the mechanism in the `<antigravity_counterparts>` block of its `<claude_output_styles>` section, with the paths in `<antigravity_config_tree>`. The essentials: Antigravity documents no tone, persona, output-format, or system-prompt-replacement feature at all, so the whole mapping runs through rules; workspace rules are Markdown files under the workspace agents directory while global rules are a single file one level above the global configuration directory; each rule file is capped at 12,000 characters; and Always On is the activation mode corresponding to a standing voice. Antigravity is append-only, so the deployed prose competes with default guidance rather than displacing it.

The character cap is the constraint that shapes this task. The style body is well inside it today, but the cap binds whatever ships, so the deploy checks the generated content against it rather than assuming it fits, and fails with a clear message when it does not.

Antigravity is also the one non-Claude harness whose plugin bundle can carry rules, so a plugin-integrated route exists here. This task takes the global route only, matching the machine-wide mode the groundwork task establishes.

## Approach

Generate an Antigravity variant of the style and write it as a delimited block into the single global rules file, using begin and end markers that carry the artefact name so the block is found again on redeploy and on uninstall. Replace the block in place when it is already present, so repeated deploys do not accumulate copies. Leave every line outside the markers untouched, since the file belongs to the user.

Check the generated block against the 12,000-character per-file cap before writing, and fail with a message naming the actual size and the limit when it does not fit, rather than truncating or writing a file the harness will reject.

Generate rather than copy. Strip the Claude frontmatter, which this target does not implement, and rewrite the one clause in the style body naming Claude's `keep-coding-instructions` mechanism, using the per-tool substitution facility in `deployment/deployment.conf`.

**Out of scope:**

- The source directory, the `style` artefact type, and the log restore behaviour, all owned by [the Claude groundwork task](deployment_output-style-claude-groundwork.md).
- The workspace-scoped rules directory and the plugin bundle's rules component, both of which reach narrower scopes than the machine-wide mode this task delivers.

## Acceptance

- A dry run restricted to the style type and the Antigravity target reports one block write into the global rules file and no other file changes.
- A real deploy against a scratch rules file that already contains unrelated user content leaves that content byte-identical and adds the style between its begin and end markers.
- Deploying twice in a row leaves exactly one marked block, verified by counting the begin marker in the target file.
- Uninstalling removes the marked block and leaves the surrounding user content byte-identical to its state before the first deploy.
- A deploy attempt with a generated block exceeding 12,000 characters fails with a message naming the actual size and the limit, and writes nothing.
- The deployed block contains no Claude output-style frontmatter keys, verified by searching it for `keep-coding-instructions` and `force-for-plugin` and finding neither.
- `deployment/README.md` gains an Antigravity row for the style type naming the global rules file, the marked-block behaviour, the character cap, and the fact that this target appends rather than replaces.
