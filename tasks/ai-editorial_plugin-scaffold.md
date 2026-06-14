---
description: "Scaffold and register the new ai_editorial plugin shell — both plugin.json files, README, skills/ dir, marketplace entry, and root README update."
scope: "ai_editorial plugin"
created: 2026-06-01T23:31:06
updated: 2026-06-14T18:35:44
status: open
reported-by: Andreas Hoffmann
---

# Scaffold and register the ai_editorial plugin

## Goal

Stand up the shell of a third plugin, `ai_editorial`, alongside `ai_dev` and `knowledge_management`, and register it everywhere a plugin must be listed — so the two launch skills (filed as sibling tasks) have a home to land in. The plugin's domain is **human-facing prose quality / editorial craft**. Outcome: `ai_editorial` is a recognized, registered, lint-clean plugin that previews cleanly in a dry-run deploy, with an empty `skills/` directory ready for its skills.

## Context

- This is a meta-repository; plugins live under `plugins/`. Two exist today — `ai_dev` and `knowledge_management` — and this adds the third. The standing repo rules own the generic plugin checklist; this task supplies the `ai_editorial`-specific values.
- The two launch skills are filed as sibling tasks and depend on this scaffold. Build this first, then [ai-editorial_slop-catch-skill.md](ai-editorial_slop-catch-skill.md) and [ai-editorial_ghost-writer-skill.md](ai-editorial_ghost-writer-skill.md).
- **Domain distinction (governs the plugin description and both skills).** `ai_editorial` is human-facing prose — the opposite vector from `ai_dev`'s `ai_instruction_writing`, which is machine-facing (prompts, rules, SKILL.md). Word the plugin description as a peer to the other two so it does not blur into the `ai_instruction_*` space.
- Naming is settled: the plugin is `ai_editorial`; do not rename it.

## Approach

1. Create `plugins/ai_editorial/`:
   - `.claude-plugin/plugin.json` — name `ai_editorial`, description, author, license; mirror `ai_dev`'s shape.
   - `.codex-plugin/plugin.json` — same metadata plus `"skills": "./skills/"`.
   - `README.md` — plugin overview that lists the two planned skills (`slop_catch`, `ghost_writer`).
   - `skills/` — the directory, empty for now.
2. Register in `.claude-plugin/marketplace.json` under `plugins[]`: name, `source: ./plugins/ai_editorial`, description.
3. Update the root `README.md`: add `ai_editorial` to the layout tree and the **Plugins** bullet list.

Non-goal: the skills themselves land in the two sibling tasks — this task ships the shell only.

## Acceptance

- `plugins/ai_editorial/` holds both `plugin.json` files (the `.codex-plugin` one carrying `"skills": "./skills/"`), a `README.md`, and a `skills/` directory.
- The plugin appears in `.claude-plugin/marketplace.json` and in the root `README.md` layout tree and **Plugins** list.
- `./deployment/deployment.sh --global --dry-run` previews `ai_editorial` without error.
