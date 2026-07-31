---
description: "Scaffold and register the new ai_editorial plugin shell — both plugin.json files, README, skills/ dir, marketplace entry, and root README update."
scope: "ai_editorial plugin"
created: 2026-06-01T23:31:06
updated: 2026-07-31T18:41:44
status: ready
reported-by: Andreas Hoffmann
---

# Scaffold and register the ai_editorial plugin

## Goal

Stand up the shell of a third plugin, `ai_editorial`, alongside `ai_dev` and `knowledge_management`, and register it everywhere a plugin must be listed — so the three skills filed as sibling tasks have a home to land in. The plugin's domain is **editorial craft on prose written for people to read**. Outcome: `ai_editorial` is a recognized, registered, lint-clean plugin that previews cleanly in a dry-run deploy, with an empty `skills/` directory ready for its skills.

## Context

- This is a meta-repository; plugins live under `plugins/`. Two exist today — `ai_dev` and `knowledge_management` — and this adds the third. The standing repo rules own the generic plugin checklist; this task supplies the `ai_editorial`-specific values.
- Three skills are filed as sibling tasks and depend on this scaffold. Build this first, then [ai-editorial_slop-catch-skill.md](ai-editorial_slop-catch-skill.md), [ai-editorial_ghost-writer-skill.md](ai-editorial_ghost-writer-skill.md), and [ai-editorial_language-humanizer-skill.md](ai-editorial_language-humanizer-skill.md).
- **Domain distinction (governs the plugin description and its skills).** `ai_editorial`'s domain is editorial craft on prose written for people to read — reports, proposals, updates, documentation. Name that domain positively in the plugin description, as a peer to the other two plugins. Keep the distinction to subject matter: every skill in this repo is invoked by a person and consumed by a model, so no plugin here is for people rather than for models, and `ai_dev`'s `ai_instruction_*` skills are the authorities to follow when authoring instruction text rather than a contrast case to steer away from.
- Naming is settled: the plugin is `ai_editorial`; do not rename it.

## Approach

1. Create `plugins/ai_editorial/`:
   - `.claude-plugin/plugin.json` — name `ai_editorial`, description, author, license; mirror `ai_dev`'s shape.
   - `.codex-plugin/plugin.json` — same metadata plus `"skills": "./skills/"`.
   - `README.md` — plugin overview that lists the three planned skills (`slop_catch`, `ghost_writer`, `language_humanizer`).
   - `skills/` — the directory, empty for now.
2. Register `ai_editorial` in every marketplace file the standing repo rules require for a new plugin, matching each file's existing entry shape. Supply the `ai_editorial`-specific values under `plugins[]`: name `ai_editorial`, source path `./plugins/ai_editorial`, and description.
3. Update the root `README.md`: add `ai_editorial` to the layout tree and the **Plugins** bullet list.

**Out of scope:**

- Authoring the skills themselves; each is owned by its sibling task named in Context, and this task ships the shell only.

## Acceptance

- `plugins/ai_editorial/` holds both `plugin.json` files (the `.codex-plugin` one carrying `"skills": "./skills/"`), a `README.md`, and a `skills/` directory.
- The plugin `README.md` lists all three planned skills — `slop_catch`, `ghost_writer`, and `language_humanizer`.
- `ai_editorial` is registered in every marketplace file the standing repo rules require for a new plugin, and appears in the root `README.md` layout tree and **Plugins** list.
- `./deployment/deployment.sh --global --dry-run` previews `ai_editorial` without error.
