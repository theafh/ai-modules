---
description: "Build the ghost_writer skill: rules for writing and especially editing strong prose, with one ruleset per genre — scientific, essays, blog posts, social media, case studies."
scope: "ai_editorial plugin"
created: 2026-06-01T23:31:06
updated: 2026-07-31T18:41:44
status: open
reported-by: Andreas Hoffmann
---

# Build the ghost_writer skill

## Goal

Add the `ghost_writer` skill to the `ai_editorial` plugin. It carries the rules for writing strong human-facing prose and, especially, for **editing** existing text, with a dedicated ruleset per target genre — scientific writing, essays, blog posts, social media, and case studies. Given a draft or a brief plus a genre, it writes or edits prose to that genre's rules.

## Context

- Depends on the plugin shell: build [ai-editorial_plugin-scaffold.md](ai-editorial_plugin-scaffold.md) first. This skill lands in `plugins/ai_editorial/skills/ghost_writer/`.
- **Rule content needs a source — prerequisite input.** The substance of this skill is the rulesets themselves. Before authoring, gather the source from the user — existing style guides, the user's own writing notes and preferences, or named references per genre. With no source provided, agree the rule content with the user rather than inventing five genre rulesets unprompted. This task is ready to *build* once that input exists; until then it is ready to *scaffold and outline*.
- Pairs with [ai-editorial_slop-catch-skill.md](ai-editorial_slop-catch-skill.md): `slop_catch` flags AI tells; `ghost_writer` produces and edits prose that avoids them. Decide whether `ghost_writer` references `slop_catch`'s tell ruleset to stay consistent (a deployment-agnostic, direct reference if so).
- Write the `description:` so it triggers on producing and editing prose written for people to read, keyed by genre, and so a router can tell it from [ai-editorial_language-humanizer-skill.md](ai-editorial_language-humanizer-skill.md), the third prose skill in this plugin. That task fixes the axis and owns its own side of the split: `language_humanizer` works toward comprehension and coherence for a named reader, on whatever material it is handed, while `ghost_writer` works toward a target genre's craft standard. This task owns the `ghost_writer` side of that wording.
- **Authoring authorities.** Two registers meet here and stay separate. The `SKILL.md` and the genre rulesets this task writes are instructions an AI consumes, so they follow `ai_instruction_writing` for positive, action-oriented carriers and `ai_instruction_formatting` for structure — those two siblings own how to write for an AI reader and how to shape a skill file, and they guide this authoring rather than serving as a contrast case for the `description:`. The rules those files carry then govern something else: the prose `ghost_writer` produces, which people read. Neither register borrows the other's form, so a genre ruleset states its rules as instructions rather than demonstrating the genre in its own voice — the blog-post ruleset is not itself written as a blog post.
- Follow the standing repo rules for skill authoring; this task supplies the `ghost_writer`-specific workflow, genre set, and source requirements.

## Approach

1. `plugins/ai_editorial/skills/ghost_writer/SKILL.md` — frontmatter `name: ghost_writer`; body sections for role, when-to-activate, the write-and-edit workflow keyed by genre, and output contract. State that editing existing text is the primary mode.
2. `skills/ghost_writer/references/` — the shared prose-writing and editing rules, plus one ruleset per genre: scientific writing, essays, blog posts, social media, case studies. Each ruleset states what good looks like for that genre and how to edit toward it. Populate from the source gathered in Context.
3. If the file set outgrows a single coherent unit — for instance if each genre ruleset becomes substantial — split the per-genre rulesets into a follow-up task rather than letting this one pass 300 lines.

## Acceptance

- `plugins/ai_editorial/skills/ghost_writer/` holds `SKILL.md` and a `references/` set covering the shared prose/editing rules plus the five named genre rulesets.
- Each genre ruleset traces to the agreed source from Context, not invented unprompted.
- The `SKILL.md` and every genre ruleset state their rules as instructions to follow rather than demonstrating their genre in their own voice, and the `SKILL.md` passes `ai_instruction_formatting`'s bundled `scripts/lint_pseudo_xml.py`.
- The skill `description:` triggers on genre-keyed writing and editing of prose written for people to read, and states the genre-craft axis that tells it apart from `language_humanizer`'s comprehension-and-coherence axis.
- `./deployment/deployment.sh --global --dry-run` previews `ghost_writer` without error.
