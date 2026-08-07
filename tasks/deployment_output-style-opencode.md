---
description: Deploy the output style to OpenCode, choosing between the additive instructions list and a synthesized base-prompt swap on its default primary agent.
scope: deployment
created: 2026-08-07T23:39:03
updated: 2026-08-07T23:39:03
status: open
reported-by: Andreas Hoffmann
---

# Deploy the output style to OpenCode

## Goal

OpenCode receives the repository's output style through its own configuration tree, by whichever of its two routes the implementer selects from the evidence below. Both routes are real and they differ in strength and in cost, so this task settles the choice with its findings recorded, then implements the selected one.

## Context

This builds on [the Claude groundwork task](deployment_output-style-claude-groundwork.md), which creates the repo-root source directory, the `style` artefact type, and the deploy-log restore behaviour. Ship that first; this task adds one target and no new machinery.

The `harness_portability` skill records both routes in the `<opencode_counterparts>` and `<opencode_delivery_modes>` blocks of its `<claude_output_styles>` section, read off the source rather than the documentation, which states none of it.

The additive route is the instructions list in OpenCode's global configuration file. Its resolution rules are what make it deployable: a leading home-directory marker expands, an absolute path is globbed by its basename within its own directory, every match resolves into a set so a repeated deploy is idempotent, and each file is injected labelled with its own path. Reach is wider than a Claude style because the appended tail governs every agent including subagents. This route adds to the user's existing rules rather than replacing them, which the global rules file would not: that file resolves by first match, so writing one would stop the user's own global rules file loading altogether.

The replacing route is an agent's prompt field, which substitutes the per-model base prompt while the environment, instructions, MCP, and skills content still append afterwards. Those base prompts are sectioned Markdown, so the same synthesized style-layer swap the Codex task performs is available here. Two costs come with it. There is no supported way to read the resolved text, since OpenCode ships no catalog-dump command, so a generator either reads the public repository and risks a version mismatch against the installed build or extracts the text from the installed application bundle. And the slot is per agent, so making the swap the default means overriding the built-in primary agent by defining one under its name, since agent configuration merges by name and a supplied prompt wins.

Both routes deploy into OpenCode's own configuration tree. Its discovery of the Claude tree is an adoption path the standing rule in the harness portability skill's policy treats as contamination to disable, not a delivery channel.

## Approach

Decide the route from the evidence in **Context** and record the decision with its reasoning in the implementation notes, then build only the selected one.

**Open decision:** which route ships. The additive instructions list is the lower-risk option and the recommended default: it is a supported configuration key, it is idempotent by construction, it leaves the user's own rules intact, and it reaches subagents. Its cost is that the prose appends and therefore competes with OpenCode's base prompt rather than displacing it, which is weaker than what Claude gives. The replacing route delivers the stronger outcome and costs bundle extraction plus ownership of the default agent's definition, and it freezes the text across model switches because the per-model base prompt is never consulted once a prompt is set. An implementer with no further input takes the additive route.

For the additive route, generate the variant, write it into a dedicated directory inside OpenCode's global configuration tree, and add its path to the instructions list in the global configuration file. For the replacing route, derive the base prompt for the target model, substitute its tone and formatting sections, write the result as the prompt file, and define the default primary agent to point at it.

Generate rather than copy either way. Strip the Claude frontmatter, which this target does not implement, and rewrite the one clause in the style body naming Claude's `keep-coding-instructions` mechanism, using the per-tool substitution facility in `deployment/deployment.conf`.

**Out of scope:**

- The source directory, the `style` artefact type, and the log restore behaviour, all owned by [the Claude groundwork task](deployment_output-style-claude-groundwork.md).
- The plugin route through OpenCode's system-transform hook, which carries `experimental` in its own name and is a code artefact rather than reviewable prose.
- Writing the global rules file in OpenCode's configuration tree, which the **Context** rejects because first-match resolution would suppress the user's own global rules.

## Acceptance

- The selected route and the reasoning behind it are recorded in the implementation notes, naming which evidence in **Context** settled it.
- A dry run restricted to the style type and the OpenCode target reports the writes the selected route implies, all inside OpenCode's own configuration tree and none in the Claude tree.
- A real deploy into a scratch configuration produces the generated file, and the configuration file parses as valid JSON afterwards.
- Deploying twice in a row leaves one file and one configuration entry, with no duplicate entry in the instructions list.
- Running the deploy against a scratch configuration that already carries unrelated instructions entries, then uninstalling, removes only the entry this deploy added and leaves the others in place.
- The deployed file contains no Claude output-style frontmatter keys, verified by searching it for `keep-coding-instructions` and `force-for-plugin` and finding neither.
- When the replacing route is selected, the derived base prompt's operating sections survive the substitution byte-for-byte, and a missing expected section heading fails the run with a message naming the heading rather than falling back to appending.
- `deployment/README.md` gains an OpenCode row for the style type naming the selected route, its configuration key, and whether the result appends or replaces.
