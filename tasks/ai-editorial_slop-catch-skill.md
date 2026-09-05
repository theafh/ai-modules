---
description: "Build the slop_catch skill: a bundled Python detector (ported from the ai_slop_detector extension) plus a structural-tell ruleset that flags AI writing tells in a draft and returns feedback."
scope: "ai_editorial plugin"
created: 2026-06-01T23:31:06
updated: 2026-09-05T21:26:04
status: open
reported-by: Andreas Hoffmann
---

# Build the slop_catch skill

## Goal

Add the `slop_catch` skill to the `ai_editorial` plugin. Given a draft, it surfaces typical AI writing tells and returns feedback: which tells fired, where, and why each reads as AI-generated. It pairs a deterministic bundled Python detector (ported from the user's `ai_slop_detector` browser extension) with a prose ruleset describing the structural tells to flag.

## Context

- Depends on the plugin shell: build [ai-editorial_plugin-scaffold.md](ai-editorial_plugin-scaffold.md) first. This skill lands in `plugins/ai_editorial/skills/slop_catch/`.
- **Source to port, a prerequisite input.** The detection logic lives in the user's `ai_slop_detector` browser extension, a separate sibling repo under the private-repos root, not part of this repo. Before writing the detector, locate and read that repo to extract the exact tells and how it scores them. If the repo is not reachable from this checkout, gather the tell list and detection logic from the user before building the script. Port the real tells rather than inventing them.
- Pairs with [ai-editorial_ghost-writer-skill.md](ai-editorial_ghost-writer-skill.md): `slop_catch` flags AI tells; `ghost_writer` produces and edits prose that avoids them.
- Write the skill `description:` so it triggers on reviewing a draft and flagging AI writing tells in prose written for people to read. Follow `ai_instruction_writing` and `ai_instruction_formatting` when authoring this skill's own instruction text; they are authoring authorities, not a contrast case for the `description:`.
- Follow the standing repo rules for skill authoring; this task supplies the `slop_catch`-specific detector workflow, source-port requirement, and Python style-guide requirement.

## Approach

1. `plugins/ai_editorial/skills/slop_catch/SKILL.md`: frontmatter `name: slop_catch`; body sections for role, when-to-activate, the detect-and-report workflow, and output contract.
2. `skills/slop_catch/scripts/`: the Python detector ported from `ai_slop_detector`. Define its I/O contract explicitly: how it receives the draft (stdin or a file argument), what it emits (structured findings: tell id, location/span, message), and its exit behaviour. The `SKILL.md` prose states how the skill runs the script and turns its output into reader-facing feedback.
3. `skills/slop_catch/references/`: the structural-tell ruleset: each tell named, with what it looks like and why it reads as AI-generated, so the agent can explain the findings the script flags and catch tells the script cannot.

## Acceptance

- `plugins/ai_editorial/skills/slop_catch/` holds `SKILL.md`, a `scripts/` directory with the detector, and a `references/` directory with the tell ruleset.
- The script's input/output contract is documented, and `SKILL.md` describes how that output becomes reader-facing feedback.
- Every tell the detector and ruleset cover traces to the `ai_slop_detector` source (or to the tell list the user supplied), not invented.
- The Python script adheres to the `format_python` style guide.
- `./deployment/deployment.sh --global --dry-run` previews `slop_catch` without error.
