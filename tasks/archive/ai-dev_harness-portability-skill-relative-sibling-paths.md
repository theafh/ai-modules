---
description: Name in harness_portability that skill and sibling-file paths must be written from the skills-tree perspective, not from the repository root.
scope: plugins/ai_dev/skills/harness_portability
created: 2026-10-14T06:47:49Z
updated: 2026-11-10T12:06:12Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Name the skill-relative sibling-path rule in harness_portability

## Goal

`harness_portability` states that paths and sibling-file mentions in skill and plugin prose — and in task bodies that prescribe those loads — are written from the skills tree (the perspective a running skill or a `.skill` archive uses), never from the repository root, so implementers and reviewers stop encoding browse paths that runtime and archive packaging will not resolve.

## Context

- **Motivating miss.** A task in a multi-skill plugin marketplace told the implementer to load shaping materials from `plugins/<plugin>/skills/<sibling>/references/…`. That path exists when browsing the checkout from the repo root, but same-plugin skills already name sibling content without a repository-root prefix — the `$<SLUG>_SKILL/…` placeholder in `wiki_import` and `wiki_wrapup`, and the skills-tree sibling form `git_review/` in `git_auto_review`. Shipped artefacts here still resolve a sibling skill as a filesystem-relative path whose first component is `..`: `task_auto_check` names `../task/` and `../task_check/`, and the `wiki` family's `<resolve_wiki_skill_bundle>` resolution order names `../wiki` from `wiki_import` and `wiki_wrapup` and `../wiki`/`../skills/wiki` from `wiki/SKILL.md` and `agents/auto_shaper_wiki.md`. Those `..`-prefixed forms are correct for a literal filesystem path resolved from the artefact's own directory, so the rule this task states keeps them; it bans only the repository-root browse form and gives the bare sibling-directory form (`git_review/`) to naming a sibling skill by its skills-tree name, while the `$<SLUG>_SKILL/…` prose form those two front-end skills already use stays the precedent. Encoding the repo-root form in skill text ships a Chat/archive-broken load even when the disk layout looks fine.
- **What already settles the form.** The rule already ships in `plugins/ai_dev/skills/git_auto_review/SKILL.md`, whose path rule resolves `git_review` as a same-plugin sibling skill "under the skills-tree sibling form `git_review/`, whose first path component is that sibling's directory name under `skills/` and never a repository-root `plugins/<plugin>/skills/...` browse path". The archive-resolver half of the claim stays unconfirmed here: this repository carries no archive builder (`deployment/deployment.sh` copies components into vendor roots) and `wiki/` has no sibling-resolution page, so the new wording cites the shipped precedent and carries the packaging claim as a stated gap naming what would settle it — official provider documentation, the marketplace archive builder's loader source, or an installed `.skill` build. The gap is authoring guidance: `harness_portability` does not yet name the perspective rule, so tasks and skill rewrites can still prescribe repo-root browse paths.
- **Closest existing rule.** The skill's path-resolution policy already says to resolve paths relative to the script, skill, plugin, or an explicit user-provided root, and to keep user-specific absolute paths out of published artefacts. It does not yet distinguish a skills-tree sibling pointer from a repository-root `plugins/…/skills/…` browse path, nor call out task bodies that prescribe skill loads as the same surface.
- **Edit target.** `plugins/ai_dev/skills/harness_portability/SKILL.md` (policy path-resolution rule and the matching review-checklist path item).

## Approach

1. In `plugins/ai_dev/skills/harness_portability/SKILL.md`, rewrite the path-resolution policy (and the matching review-checklist path item) in place so one canonical rule covers this gap:
   - When skill or plugin prose names a file in the same skill, use the skill-local form the runtime already follows (for example `references/<file>`).
   - When it names a file another skill owns, use the `$<SLUG>_SKILL/<path-within-skill>` placeholder that `ai_instruction_formatting`'s `## Cross-Artefact References` mandates (for example `$WIKI_SKILL/references/raw_taxonomy.md`), so the pointer names the sibling bundle rather than a repository-root path.
   - When prose names a sibling skill by its skills-tree name, use the bare sibling-directory form whose first component is that sibling's directory name under `skills/` (for example `git_review/`). When an artefact resolves a sibling skill or file as a literal filesystem path at runtime or in an archive, keep that path relative to the artefact's own directory (for example `../<sibling>/<path>` or `../../agents/`); never use a repository-root form for either.
   - Never write a repository-root browse path such as `plugins/<plugin>/skills/…` as the load or link target those artefacts follow.
   State that task bodies, Approach steps, and Acceptance checks that prescribe such loads follow the same perspective, because they are the instructions an implementer copies into the skill. Read `ai_instruction_formatting`'s `## Cross-Artefact References` table and take its `$<SLUG>_SKILL/…` form as given; this change does not edit that skill.
2. Keep the existing absolute-path and user-path prohibitions; fold the new distinction into the rewritten path rule rather than appending a second, competing path paragraph.
3. Extend `<scope>`/`<included_artefacts>` and `<objective>` in the same file to name task bodies, Approach steps, and Acceptance checks that prescribe skill or plugin file loads as included prose, so the path rule and review item govern that surface instead of reaching past the scope the skill states.
4. Ground the wording in the shipped `git_auto_review` path rule rather than asserting archive internals: cite that statement as the source the new text agrees with, record the date it was checked, and where the archive-resolver behaviour stays unconfirmed, state the gap and name what would settle it (official provider documentation, the archive builder's loader source, or an installed `.skill` build), per the skill's `<state_the_gap>` rule.

**Out of scope:** changing packaging resolvers or wiki docs in consumer marketplace repositories; sweeping live skill or task files elsewhere for stray repo-root load cites.

## Acceptance

- `plugins/ai_dev/skills/harness_portability/SKILL.md` path-resolution policy names the skills-tree perspective for same-skill loads and for cross-skill file pointers, assigns a cross-skill file pointer in prose to the `$<SLUG>_SKILL/<path-within-skill>` placeholder, names a sibling skill by its skills-tree name using the bare sibling-directory form (`git_review/`), keeps a literal filesystem path relative to the artefact's own directory (`../<sibling>/<path>`, `../../agents/`), and explicitly excludes repository-root `plugins/…/skills/…` browse paths as the form those loads use (tree-inspectable in the rewritten policy rule; no surviving sentence that only says "relative to the skill or plugin" without the sibling-versus-repo-root distinction).
- The skill's review-checklist path item restates that same distinction so a portability review catches a repo-root load cite in skill prose or in a task that prescribes one (tree-inspectable).
- `plugins/ai_dev/skills/harness_portability/SKILL.md` `<scope>`/`<included_artefacts>` and `<objective>` name task bodies, Approach steps, and Acceptance checks that prescribe skill or plugin file loads as included prose, and the path rule and review item reach that same surface (tree-inspectable: no policy or checklist sentence applies to a surface the scope excludes).
- The rewritten policy rule itself names task bodies, Approach steps, and Acceptance checks that prescribe skill or plugin file loads as following the same skills-tree perspective (tree-inspectable in the policy rule, not only in `<scope>`/`<included_artefacts>` and `<objective>`).
- The rewritten policy and checklist items carry at least one positive example of the cross-skill placeholder form (`$<SLUG>_SKILL/…`) and at least one explicit rejection of the repository-root browse form (`plugins/…/skills/…`) as a load target (tree-inspectable).
- The rewritten policy and `ai_instruction_formatting`'s `## Cross-Artefact References` table state one consistent rule: both give the `$<SLUG>_SKILL/…` placeholder to a cross-skill file pointer in prose, and the new policy never directs an author to write a bare sibling-directory pointer where that table requires the placeholder (tree-inspectable in the two rules; `ai_instruction_formatting` is read, not edited).
- The policy rule names a sibling skill by its skills-tree name using the bare sibling-directory form (`git_review/`), not only a sibling file, and `## Context` names `task_auto_check`'s `../task/` and `../task_check/` pointers as artefact-directory-relative literal-path forms the rule keeps (tree-inspectable in the rewritten policy rule and Context bullet).
- The rewritten rule names the source it rests on — the `git_auto_review` path statement with the date it was checked — and any unconfirmed archive-resolver claim is carried as a stated gap naming what would settle it (tree-inspectable).
