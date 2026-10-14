---
description: Name in harness_portability that skill and sibling-file paths must be written from the skills-tree perspective, not from the repository root.
scope: plugins/ai_dev/skills/harness_portability
created: 2026-10-14T08:47:49
updated: 2026-10-14T08:47:49
status: open
reported-by: Andreas Hoffmann
---

# Name the skill-relative sibling-path rule in harness_portability

## Goal

`harness_portability` states that paths and sibling-file mentions in skill and plugin prose — and in task bodies that prescribe those loads — are written from the skills tree (the perspective a running skill or a `.skill` archive uses), never from the repository root, so implementers and reviewers stop encoding browse paths that runtime and archive packaging will not resolve.

## Context

- **Motivating miss.** A task in a multi-skill plugin marketplace told the implementer to load shaping materials from `plugins/<plugin>/skills/<sibling>/references/…`. That path exists when browsing the checkout from the repo root, but same-plugin skills already load siblings as `<sibling>/references/…` (first path component = sibling skill directory under `skills/`), and archive builders that resolve same-plugin sibling references keep only that form. Encoding the repo-root form in skill text ships a Chat/archive-broken load even when the disk layout looks fine.
- **What already settles packaging in those marketplaces.** Same-plugin sibling resolution places a referenced sibling file into a consuming skill's archive at the path the pointer names when that pointer is plugin-relative. The gap is authoring guidance: `harness_portability` does not yet name the perspective rule, so tasks and skill rewrites can still prescribe repo-root browse paths.
- **Closest existing rule.** The skill's path-resolution policy already says to resolve paths relative to the script, skill, plugin, or an explicit user-provided root, and to keep user-specific absolute paths out of published artefacts. It does not yet distinguish a skills-tree sibling pointer from a repository-root `plugins/…/skills/…` browse path, nor call out task bodies that prescribe skill loads as the same surface.
- **Edit target.** `plugins/ai_dev/skills/harness_portability/SKILL.md` (policy path-resolution rule and the matching review-checklist path item).

## Approach

1. In `plugins/ai_dev/skills/harness_portability/SKILL.md`, rewrite the path-resolution policy (and the matching review-checklist path item) in place so one canonical rule covers this gap: when skill or plugin prose names a file in the same skill, use the skill-local form the runtime already follows (for example `references/<file>`); when it names a file in another skill of the same plugin, use the skills-tree sibling form whose first component is that sibling's directory name under `skills/` (for example `<sibling>/references/<file>`); never write a repository-root browse path such as `plugins/<plugin>/skills/…` as the load or link target those artefacts follow. State that task bodies, Approach steps, and Acceptance checks that prescribe such loads follow the same perspective, because they are the instructions an implementer copies into the skill.
2. Keep the existing absolute-path and user-path prohibitions; fold the new distinction into the rewritten path rule rather than appending a second, competing path paragraph.
3. Bump the skill's frontmatter `version` once for the rule addition (patch).

**Out of scope:** changing packaging resolvers or wiki docs in consumer marketplace repositories; sweeping live skill or task files elsewhere for stray repo-root load cites beyond whatever a single illustrative check in Acceptance proves.

## Acceptance

- `plugins/ai_dev/skills/harness_portability/SKILL.md` path-resolution policy names the skills-tree perspective for same-skill and same-plugin sibling loads, and explicitly excludes repository-root `plugins/…/skills/…` browse paths as the form those loads use (tree-inspectable in the rewritten policy rule; no surviving sentence that only says "relative to the skill or plugin" without the sibling-versus-repo-root distinction).
- The skill's review-checklist path item restates that same distinction so a portability review catches a repo-root load cite in skill prose or in a task that prescribes one (tree-inspectable).
- Skill frontmatter `version` is one patch above the pre-change value.
- The rewritten policy and checklist items carry at least one positive example of the sibling form (`<sibling>/references/…`) and at least one explicit rejection of the repository-root browse form (`plugins/…/skills/…`) as a load target (tree-inspectable).
