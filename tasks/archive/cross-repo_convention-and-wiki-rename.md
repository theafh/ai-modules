---
description: Establish the naming convention — manual skills family-first, autonomous skills `<family>_auto_<rest>`, agents `auto_<role>_<family>` — and rename wiki_auto_shaper to auto_shaper_wiki.
scope: "repo-wide"
created: 2026-06-21T17:28:26
updated: 2026-06-22T23:08:21
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Skill and agent naming convention and wiki_auto_shaper rename

## Goal

Establish one naming system that tells three kinds of artifact apart at a glance, document it as a standing authoring rule, and apply it to the one agent that exists today. The token `auto` marks automation, and where it sits in the name encodes the kind:

- A **manually-invoked skill** keeps its ordinary family-first name with no `auto` — `task_implement`, `wiki_fix`.
- An **autonomous skill** — still user-invoked, but it drives a loop and spawns agents — keeps the family-first shape and inserts `auto` right after the family: `<family>_auto_<rest>`, as in `task_auto_implement` (the loop wrapper) beside `task_implement` (the plain manual one), and `task_auto_check`.
- A **spawned agent**, never invoked by hand, leads with the `auto_` prefix and ends with its family token: `auto_<role>_<family>`, as in `auto_shaper_wiki`, `auto_reviewer_task`, `auto_verifier_task`, `auto_implementer_task`. A standalone agent in no family is simply `auto_<role>`.

So a name beginning `auto_` is always a spawned agent; a name carrying `auto` in the middle is always an autonomous skill; and the family token leads a skill but trails an agent. Settling this now matters because the autonomous task skills being designed — `task_auto_check`, `task_auto_implement`, `task_auto_shaper` — spawn `auto_reviewer_task`, `auto_verifier_task`, and `auto_implementer_task`, so the convention is fixed and the lone existing agent renamed before those land.

## Context

Today `wiki_fix` is an invokable skill that delegates to a `wiki_auto_shaper` agent — the right skill/agent split, but the agent's name neither marks it as spawned nor stays clear of the `wiki_*` skill namespace. The `auto_` prefix plus the family suffix fix both. The standing repo rules — here `AGENTS.md` and `CLAUDE.md` — are where authoring conventions live and already carry a cross-reference example that names the agent, so the convention is documented there.

The agent identity appears in two forms, and the rename turns both around: snake_case `wiki_auto_shaper` → `auto_shaper_wiki` (frontmatter `name:`, skill and README references, marketplaces, plugin manifests, prose, and the filename) and title-case `Wiki Auto Shaper` → `Auto Shaper Wiki` (the agent file's H1 and one docstring example in `ai_instruction_formatting`'s `lint_pseudo_xml.py`). Three carve-out groups keep the old name: this task file — its title, frontmatter, and the prose describing the rename; `CHANGELOG.md`, which is git-history-derived rather than hand-edited and records the agent under the name it carried when each change shipped; and historical archived tasks under `tasks/archive/`, which preserve the references they carried when the old name was current. The unrelated `wiki_auto-shaper-*` task slugs (note the hyphen) are a different string and stay untouched. Deployment needs no edit: `deployment.sh` discovers agents by globbing the `agents/` directory, so the `git mv` keeps the renamed agent deployable.

## Approach

Two pieces: document the convention, then rename the agent everywhere.

Document the convention in the standing repo rules (`AGENTS.md` and `CLAUDE.md`), covering all three kinds keyed on where `auto` sits: a manually-invoked skill keeps its family-first name with no `auto` (`task_implement`); an autonomous skill — user-invoked but loop-driving and agent-spawning — inserts `auto` after the family, `<family>_auto_<rest>` (`task_auto_implement`); and a spawned agent, never hand-invoked, leads with the `auto_` prefix and ends with its family token, `auto_<role>_<family>` (`auto_implementer_task`, `auto_shaper_wiki`). State the one-line rationale: the position of `auto` tells the three apart at a glance — leading for a spawned agent, mid-name for an autonomous skill, absent for a manual skill — and keeps their namespaces from colliding.

Rename the agent with a single repo-wide search-and-replace rather than a file-by-file walk. Run `git mv plugins/knowledge_management/agents/wiki_auto_shaper.md` to `auto_shaper_wiki.md`, then replace both name forms in every file across the repo except the three carve-out groups (this task file, `CHANGELOG.md`, and historical archived tasks under `tasks/archive/`): `wiki_auto_shaper` → `auto_shaper_wiki` and `Wiki Auto Shaper` → `Auto Shaper Wiki`. That one sweep covers everything current that names the agent — the renamed agent file's own `name:`, H1, and self-paths; the `wiki_fix` and `wiki` skills and `raw_taxonomy.md`; both READMEs; both marketplace registrations; both plugin manifests; the `ai_instruction_formatting` `SKILL.md` and its `lint_pseudo_xml.py` docstring; `task_fix`'s design note; the standing-rules cross-reference example; and every live task file under `tasks/` that mentions the agent. This mechanical name-sweep rewrites references without changing any live task's meaning, so it does not bump the `updated` stamp on the co-swept live task files. The `wiki_fix` → agent delegation behaviour does not change; only the name does.

Non-goals: changing what the wiki shaper does or restructuring the `wiki_fix` → agent delegation; building the autonomous task skills and their agents, which ship with their own tasks; and renaming any skill — only the spawned agent's name changes.

## Acceptance

- The naming convention is documented in `AGENTS.md` and `CLAUDE.md`, covering all three kinds: a manual skill is family-first with no `auto` (`task_implement`); an autonomous skill is `<family>_auto_<rest>`, `auto` after the family (`task_auto_implement`); a spawned agent is `auto_<role>_<family>`, the `auto_` prefix leading and the family token last, never hand-invoked (`auto_implementer_task`); and the rationale — the position of `auto` tells the three apart and keeps their namespaces clear — is stated.
- `wiki_auto_shaper.md` is renamed to `auto_shaper_wiki.md` with `git mv`, and the renamed file carries `name: auto_shaper_wiki` and the H1 `# Auto Shaper Wiki`, confirmed by running `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py plugins/knowledge_management/agents/auto_shaper_wiki.md`.
- The old name is gone in both forms everywhere but the three carve-out groups: `rg --hidden -g '!.git' -F -e 'wiki_auto_shaper' -e 'Wiki Auto Shaper'` across the repo returns matches only in `CHANGELOG.md`, within this task file itself, and under `tasks/archive/`. The command searches hidden directories so the marketplace and plugin-manifest dotfiles are covered, excludes `.git`, and matches the two exact agent-identity strings so the unrelated `wiki_auto-shaper-*` task slugs and their cross-links stay untouched. Every other occurrence — the agent file, the `wiki_fix` and `wiki` skills, `raw_taxonomy.md`, both READMEs, both marketplaces, both plugin manifests, the `ai_instruction_formatting` `SKILL.md` and `lint_pseudo_xml.py` docstring, `task_fix`'s design note, the standing-rules cross-reference example, and every live task file under `tasks/` — now reads `auto_shaper_wiki` or `Auto Shaper Wiki`.
- `wiki_fix` still resolves and invokes the renamed agent with its delegation unchanged: its description, `<role>`, `<orient_first_top>`, `<delegate>`, and `<steps>` references name `auto_shaper_wiki`, and `plugins/knowledge_management/skills/wiki_fix/SKILL.md` contains no `wiki_auto_shaper`.
