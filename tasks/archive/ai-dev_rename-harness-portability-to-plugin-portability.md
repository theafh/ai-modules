---
description: Rename the harness_portability skill to plugin_portability across active artefacts; historic task and changelog content keeps the old name except for breaking path references.
scope: plugins/ai_dev/skills/harness_portability
created: 2026-06-30T19:55:47
updated: 2026-07-26T08:17:31
status: deferred
reported-by: Andreas Hoffmann
---

# Rename the harness_portability skill to plugin_portability

## Goal

Rename the `ai_dev` skill currently named `harness_portability` to `plugin_portability` across every **active** artefact in the repo: its directory, the skill file's identifiers, both plugin manifests, both marketplace registrations, and every README reference. The skill keeps teaching how to make the components of a plugin — skills, hooks, agents, commands, MCP helpers, bundled scripts — cross-harness and cross-OS compatible; only its identifier changes, so the new name reflects that it is about plugin-component portability.

Historic records keep the old name: the body and filename of existing task files and the `CHANGELOG.md` entries stay as written, because they record work done under the old name. The one exception inside historic files is a **path reference** that points into the renamed directory — those are re-pointed so they still resolve, while the surrounding prose and the `harness_portability` name in that prose stay untouched.

User-visible outcome: after the work, `rg "harness_portability"` returns only historic task bodies and changelog entries (plus generic "harness portability" concept phrasing); the skill loads as `plugin_portability`, every manifest/marketplace/README names it `plugin_portability`, and `make lint` passes.

## Context

The skill lives at `plugins/ai_dev/skills/harness_portability/SKILL.md` and bundles no scripts (the directory holds only `SKILL.md`). Its identifier appears as the frontmatter `name:`, the `# harness_portability` H1, and the `<harness_portability>` / `</harness_portability>` root pseudo-XML element.

Active reference sites carrying the literal name or its skill-label phrasing, all to be renamed:

- `plugins/ai_dev/.claude-plugin/plugin.json` and `plugins/ai_dev/.codex-plugin/plugin.json` — the aggregate `description` field contains the skill-label phrase `harness portability for bundled scripts and plugin wiring`.
- `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json` — the `ai_dev` entry's `description` carries the same `harness portability for bundled scripts and plugin wiring` phrase.
- `plugins/ai_dev/README.md` — the skill bullet that opens with `**harness_portability**`.
- `README.md` (repo root) — the layout-tree line `harness_portability/` and the skill bullet that opens with `**harness_portability**`.

Historic files that keep the old name in their content (the carve-out the user asked for):

- `tasks/archive/ai-dev_harness-portability-carveout-compat.md` — an archived task that edited this skill's `<policy>`. Its `scope:` frontmatter is the path `plugins/ai_dev/skills/harness_portability`, which the task linter resolves against the project root and which breaks once the directory moves; this single path reference is re-pointed to the new directory. Its description, body prose, and filename keep the `harness_portability` name as historic content.
- `tasks/archive/ai-dev_git-refresh-skill.md` — contains a markdown link whose target is `../../plugins/ai_dev/skills/harness_portability/SKILL.md`; only the link target path is re-pointed, while the link text and surrounding prose keep the old name.
- `tasks/ai-dev_git-commit-consume-context-contract.md`, `tasks/archive/task-family_charter-guardrail-for-autonomy.md`, `tasks/archive/task-family_optional-standing-doc-conventions.md` — these mention the concept ("harness-portability clause", "harness_portability requires…", "cross-harness portability rule") as prose with no path reference into the renamed directory; they are left entirely unchanged.
- `CHANGELOG.md` — records shipping the `harness_portability` skill under the old name. It is git-history-derived and maintained only through the `update_changelog` skill, so its historic entries are left as written and not hand-edited here.

The standing repo authoring conventions apply: snake_case skill/directory naming, aligned directory name + frontmatter `name:` + H1, the skill-list update procedure (plugin README, both `plugin.json` files, root README, both marketplace registrations), and `make lint` before commit.

## Approach

Move the directory, rename the identifiers inside it, then sweep the active reference sites; finish with the narrow path-only fixes inside historic files.

- **Rename the directory.** `git mv plugins/ai_dev/skills/harness_portability plugins/ai_dev/skills/plugin_portability` so the only contained file (`SKILL.md`) moves with it and history is preserved.
- **Rename the skill identifiers in `SKILL.md`.** Set frontmatter `name: plugin_portability`, change the H1 to `# plugin_portability`, and rename the root element to `<plugin_portability>` … `</plugin_portability>`. Leave the skill's `description:` frontmatter and its `<objective>` / `<scope>` / `<policy>` body prose as they are — the concept (cross-agent-harness, cross-OS portability of plugin components) is unchanged, so this rename does not rewrite that prose.
- **Update the plugin manifests and marketplaces.** In both `plugin.json` files and both marketplace registrations, rewrite the skill-label phrase `harness portability for bundled scripts and plugin wiring` to `plugin portability for bundled scripts and plugin wiring`, leaving the rest of each description intact.
- **Update the READMEs.** In `plugins/ai_dev/README.md` and root `README.md`, rename the `**harness_portability**` bullet lead to `**plugin_portability**`, and rename the `harness_portability/` entry in the root README layout tree to `plugin_portability/`.
- **Fix only path references in historic files.** Re-point `tasks/archive/ai-dev_harness-portability-carveout-compat.md`'s `scope:` to `plugins/ai_dev/skills/plugin_portability`, and re-point the markdown link target in `tasks/archive/ai-dev_git-refresh-skill.md` to `../../plugins/ai_dev/skills/plugin_portability/SKILL.md`. Change nothing else in those files — keep the `harness_portability` name everywhere it reads as prose, and keep both task filenames as they are.
- **Re-point this rename task's own `scope:`.** After the directory move, change this file's frontmatter `scope:` from `plugins/ai_dev/skills/harness_portability` to `plugins/ai_dev/skills/plugin_portability`, so it resolves against the renamed directory the move created rather than the deleted one; make no other change to this file's frontmatter or body.

Non-goals: this task does not rewrite the skill's descriptive/objective prose, does not edit the open `harness-portability-carveout-compat` task's body or rename its file, does not hand-edit `CHANGELOG.md`, and does not touch the concept-only prose mentions listed in Context. Skill/plugin `version:` and marketplace-lockstep bumps follow the standing repo versioning rules at commit time and are not enumerated here.

## Acceptance

- The directory `plugins/ai_dev/skills/plugin_portability/` exists with `SKILL.md` inside it, and `plugins/ai_dev/skills/harness_portability/` no longer exists.
- `plugins/ai_dev/skills/plugin_portability/SKILL.md` has `name: plugin_portability` in frontmatter, a `# plugin_portability` H1, and a `<plugin_portability>` root element with a matching closing tag; no `<harness_portability>` tag, H1, or `name:` value remains in the file.
- Both `plugins/ai_dev/.claude-plugin/plugin.json` and `plugins/ai_dev/.codex-plugin/plugin.json`, and both `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`, contain `plugin portability for bundled scripts and plugin wiring` and no longer contain `harness portability for bundled scripts and plugin wiring`.
- `plugins/ai_dev/README.md` and root `README.md` open the skill bullet with `**plugin_portability**`, and the root README layout tree lists `plugin_portability/`; neither file references the old `harness_portability` skill name.
- `tasks/archive/ai-dev_harness-portability-carveout-compat.md` has `scope: plugins/ai_dev/skills/plugin_portability`, and `tasks/archive/ai-dev_git-refresh-skill.md`'s markdown link resolves to `../../plugins/ai_dev/skills/plugin_portability/SKILL.md`; the body prose, descriptions, filenames, and the `harness_portability` name in the prose of both files are unchanged.
- This rename task's own frontmatter `scope:` reads `plugins/ai_dev/skills/plugin_portability`, resolving against the renamed directory rather than the deleted `plugins/ai_dev/skills/harness_portability`.
- `tasks/ai-dev_git-commit-consume-context-contract.md`, the two named archive task files, and `CHANGELOG.md` are byte-for-byte unchanged.
- `rg "harness_portability" -l` returns only historic task bodies and `CHANGELOG.md`; no manifest, marketplace, README, or the renamed skill file appears.
- `make lint` passes (markdownlint, jq syntax check, shellcheck) and the task linter reports the moved-target `scope:` and link path as resolving.
