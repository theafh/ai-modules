---
description: Add skill_doctor to audit skill definitions, metadata, descriptions, tests, trigger readiness, and registration for one skill, a skill family, or all repo skills.
scope: plugins/ai_dev/skills
created: 2026-06-14T16:53:22
updated: 2026-06-15T20:14:48
reported-by: Andreas Hoffmann
status: open
---

# Add a skill_doctor skill

## Goal

Add a new `skill_doctor` skill to the `ai_dev` plugin. It checks skill
artifacts for correctness and readiness without implementing the target
skill's work. The user can ask it to check:

- one named skill or `SKILL.md` path;
- one mentioned skill family;
- every skill in the current repository.

The skill must make scope resolution explicit before checking. A request
that names one skill stays on that skill. A family request expands to the
matching sibling set. A whole-repo request walks all skill directories the
repository exposes.

## Context

The new skill checks AI component artifacts themselves, especially
`SKILL.md` files and their surrounding registration, tests, metadata, and
documentation. It is a general skill-quality doctor, not a wrapper around a
specific skill family or workflow domain.

Skill frontmatter descriptions are load-bearing because the agent harness
uses them to decide when to load a skill. A broken, ambiguous, overlapping,
or parser-hostile description can make a valid skill disappear or route the
wrong skill. The new `skill_doctor` skill must start every run with this
discovery-safety check before deeper content review:

- parse each selected `SKILL.md` frontmatter with normal YAML handling;
- inspect `name`, `description`, and `version` for manifest usability;
- verify that each `description:` serves two distinct audiences with
  different needs:
  - the human reader needs a precise, compact explanation of what the skill is
    about, what class of work it owns, and how it differs from neighboring
    skills;
  - the LLM router needs keyword-rich trigger material it can match before
    loading the body, including `Use when` contexts, likely prompt phrases,
    artifacts, file types, domain terms, and invocation boundaries;
- judge the balance between those audiences: the description should usually
  open with a user-readable summary, then add trigger-rich invocation
  language, without becoming a keyword dump or a prose-only summary that lacks
  routing signals;
- flag descriptions that explain the skill's internal workflow instead of
  describing when to invoke it, and direct those implementation details into
  the skill body;
- compare sibling descriptions inside the same family for formatting
  outliers, risky punctuation, non-ASCII characters, and routing overlap;
- confirm each description says what the skill is for at a user-readable
  high level while remaining distinct from sibling descriptions;
- check that the relevant test and lint surfaces exist and are current
  before judging the skill prose.

The first verification surface should be generic and selected from the
target skills themselves:

- frontmatter descriptions parse safely and use stable characters for the
  current harness;
- names, headings, directories, and manifest entries agree;
- version fields are internally consistent with plugin release metadata;
- bundled scripts have a script-test surface;
- behavior-only skills have eval or trigger-eval coverage, or a documented
  reason that coverage is missing;
- markdown lint, pseudo-XML lint, JSON manifest validation, and deploy
  dry-run are run when they apply to the repository.

## Approach

Implement the new skill as `plugins/ai_dev/skills/skill_doctor/SKILL.md`.
Follow the standing repo rules for skill authoring; this task supplies the
`skill_doctor`-specific behaviour and examples. Ship the new
skill at `version: 1.0.0`.

The check workflow should be read-only by default and report concrete
findings with file paths and evidence. It should not rewrite skill files
unless the user separately asks to fix them.

Recommended workflow:

1. **Orient.** Read the repo instructions and identify the selected scope:
   single skill, family, or all skills in the repo. Resolve each selected
   skill directory and name the final set before checking.
2. **Discovery safety first.** Parse selected `SKILL.md` frontmatter and
   compare sibling descriptions for YAML safety, risky characters,
   human-reader clarity, LLM-router trigger coverage, the balance between
   those two audiences, workflow leakage, and routing overlap. For a family
   request, include every sibling in that family so outliers are visible.
3. **Registration.** Check that each selected skill is registered in the
   plugin metadata, marketplace metadata where applicable, plugin README,
   and root README when the repo convention requires it.
4. **Instruction quality.** Inspect the body for pseudo-XML organization,
   positive action-oriented wording, clear role, inputs, workflow, and output
   contract. Check sibling boundaries when a family exists.
5. **Tests and verification.** Run or identify the applicable script tests,
   behavioral evals, trigger evals, markdown lint, pseudo-XML lint, plugin
   manifest validation, and deploy dry-run. When a selected skill has bundled
   scripts, require a script test surface. When it has behavior-only prose,
   require eval coverage or an explicit reason it is missing.
6. **Report.** Return a concise verdict with blocking issues first, then
   warnings, then a short verification summary. Include the exact commands
   run and call out checks that could not run.

The skill should include examples for all three scopes:

- `check the ai_instruction_writing skill`;
- `check the wiki family skills`;
- `check all skills in this repo`.

## Acceptance

- A new `plugins/ai_dev/skills/skill_doctor/SKILL.md` exists with frontmatter
  `name: skill_doctor`, `version: 1.0.0`, and a clear non-overlapping
  description.
- The skill supports single-skill, family, and whole-repo scopes, and its
  instructions require the resolved target set to be named before checking.
- The first required check is discovery safety for `SKILL.md` frontmatter
  and descriptions, including family outlier comparison, routing overlap,
  trigger-matching coverage, human-readable purpose, and workflow-detail
  leakage.
- The description audit enforces the combined metadata rule: state what the
  skill is, include keyword-rich `Use when` trigger contexts for LLM
  matching, keep the wording clear for users browsing skills, and leave
  implementation workflow details in the body.
- The description audit treats user readability and LLM trigger matching as
  separate requirements: it flags descriptions that read well for humans but
  lack routing keywords, and descriptions that expose many keywords but fail
  to explain the skill's purpose clearly to a user.
- The check set is derived from the selected skill artifacts and applies to
  any skill family, not to one hard-coded family.
- The skill remains read-only by default and reports file-specific findings
  instead of silently editing skill artifacts.
- The skill is registered in the ai_dev plugin metadata, the Codex and
  Claude marketplace manifests, `plugins/ai_dev/README.md`, and the root
  `README.md` wherever this repo lists plugin skills.
- The registration and version metadata follow the standing repo rules for
  adding a skill to an existing plugin; the new skill itself ships at `1.0.0`.
- A focused local test or eval exists for scope resolution and for the
  frontmatter-description discovery-safety check, including a fixture with a
  risky sibling-description outlier.
- Final cleanup removes the temporary skill-description authoring rule from
  the standing repo rules in `AGENTS.md` and `CLAUDE.md` once `skill_doctor`
  owns the reusable description-quality check.

## Related

- `plugins/ai_dev/skills/ai_instruction_formatting/SKILL.md` for the
  pseudo-XML structure expected in AI-consumed instructions.
- `plugins/ai_dev/skills/ai_instruction_writing/SKILL.md` for the
  positive, action-oriented wording expected in skill prose.
- `tests/README.md` and existing `tests/<skill>/` harnesses for local
  script-test, eval, and trigger-eval conventions.
