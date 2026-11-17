---
description: Deploy the output style to OpenCode through the additive instructions list in its configuration tree, and record why the base-prompt swap was rejected.
scope: deployment
created: 2026-08-07T21:39:03Z
updated: 2026-11-17T10:15:03Z
status: open
reported-by: Andreas Hoffmann
---

# Deploy the output style to OpenCode

## Goal

OpenCode receives the repository's output style through the additive instructions list in its own configuration tree: a generated style file inside that tree, with its path added to the instructions list in the same tree's configuration file.

## Context

This builds on [the Claude groundwork task](archive/deployment_output-style-claude-groundwork.md), which shipped the repo-root source directory, the `style` artefact type, and the deploy-log restore behaviour. This task adds one target and no new shared deploy machinery.

The wiki records the route and the rejected alternative on its [SST OpenCode](../wiki/entities/sst-opencode.md) page and in [system prompt substitution across harnesses](../wiki/comparisons/system-prompt-substitution-across-harnesses.md), read off the source rather than the documentation, which states none of it.

The additive route is the instructions list in OpenCode's global configuration file. Its resolution rules are what make it deployable: a leading home-directory marker expands, an absolute path is globbed by its basename within its own directory, every match resolves into a set so a repeated deploy is idempotent, and each file is injected labelled with its own path. Reach is wider than a Claude style because the appended tail governs every agent including subagents. This route adds to the user's existing rules rather than replacing them, which the global rules file would not: that file resolves by first match, so writing one would stop the user's own global rules file loading altogether.

Both the deployed file and the configuration entry live in OpenCode's own configuration tree. Its discovery of the Claude tree is an adoption path the standing rule in the harness portability skill's policy treats as contamination to disable, not a delivery channel.

## Approach

Build the additive route, and record the decision with its reasoning in the implementation notes.

**Decision: the additive instructions list.** It is a supported configuration key, idempotent by construction, leaves the user's own rules intact, and reaches subagents. Its cost is that the prose appends and therefore competes with OpenCode's base prompt rather than displacing it, which is weaker than what Claude gives. It builds the merged array from the existing file and passes it through `merge_json_key`'s prior capture, since no array-append helper exists.

Generate the variant, write it into a dedicated directory inside OpenCode's configuration tree, and add its path to the instructions list in the configuration file in that same tree. Resolve both from the script's existing OpenCode directory variable rather than a hardcoded path, so the route serves `--global` and `--project-dir` alike: OpenCode reads a project configuration and a project instructions entry the same way it reads the global pair, and a project entry adds to the contributor's own rules rather than displacing anything.

Generate rather than copy. Strip the Claude frontmatter, which this target does not implement, and rewrite the one clause in the style body naming Claude's `keep-coding-instructions` mechanism through the generator, following the Cursor style generator, because the source carries no `$VAR$` placeholder for the `replace:` facility.

**Out of scope:**

- The replacing route, which swaps a synthesized base prompt on the default primary agent. OpenCode ships no supported way to read the resolved base prompt, so a generator either reads the public repository and risks a version mismatch against the installed build or extracts the text from the installed application bundle; the result is also pinned to one model and one OpenCode version. Inside a repository it would replace the base prompt for every contributor, not only the person who deployed it. The wiki pages named in **Context** carry the full account of the route.
- The plugin route through OpenCode V2's hook surfaces (`session`, `permission`, `shell`, and `tool`), which is a code artefact rather than reviewable prose.
- Writing the global rules file in OpenCode's configuration tree, which the **Context** rejects because first-match resolution would suppress the user's own global rules.

## Acceptance

- The additive route and the reasoning behind it are recorded in the implementation notes.
- A dry run restricted to the style type and the OpenCode target reports the writes the route implies, all inside OpenCode's own configuration tree and none in the Claude tree; the global backup at `~/.opencode-config_<timestamp>` is explicitly excepted.
- A `--project-dir` dry run reports the same two writes resolved against that project's OpenCode tree and touches nothing under the home directory, and a real project deploy leaves the global configuration file unchanged.
- A real deploy into a scratch configuration produces the generated file, and the configuration file parses as valid JSON or JSONC afterwards, editing the existing file that loads last.
- Deploying twice in a row leaves one file and one configuration entry, with no duplicate entry in the instructions list.
- Running the deploy against a scratch configuration that already carries unrelated instructions entries, then uninstalling, removes only the entry this deploy added and leaves the others in place.
- The deployed file contains no Claude output-style frontmatter keys, verified by searching it for `keep-coding-instructions` and `force-for-plugin` and finding neither.
- `deployment/README.md` gains an OpenCode row in the Generated Formats style section naming the additive route, its configuration key, and that the result appends, and its existing Target Layout Styles cell for OpenCode no longer reads `not yet`.
