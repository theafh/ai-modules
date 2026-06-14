---
description: Add skill_doctor to audit skill definitions, metadata, descriptions, tests, trigger readiness, and registration for one skill, a skill family, or all repo skills.
scope: plugins/ai_dev/skills
created: 2026-06-14T16:53:22
updated: 2026-06-14T16:56:15
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
Use the repo's normal skill-authoring conventions: pseudo-XML structure,
positive action-oriented instructions, deployment-agnostic references, and
snake_case naming. Ship the new skill at `version: 1.0.0`.

The check workflow should be read-only by default and report concrete
findings with file paths and evidence. It should not rewrite skill files
unless the user separately asks to fix them.

Recommended workflow:

1. **Orient.** Read the repo instructions and identify the selected scope:
   single skill, family, or all skills in the repo. Resolve each selected
   skill directory and name the final set before checking.
2. **Discovery safety first.** Parse selected `SKILL.md` frontmatter and
   compare sibling descriptions for YAML safety, risky characters,
   user-readable purpose, and routing overlap. For a family request, include
   every sibling in that family so outliers are visible.
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
  and descriptions, including family outlier comparison and routing overlap.
- The check set is derived from the selected skill artifacts and applies to
  any skill family, not to one hard-coded family.
- The skill remains read-only by default and reports file-specific findings
  instead of silently editing skill artifacts.
- The skill is registered in the ai_dev plugin metadata, the Codex and
  Claude marketplace manifests, `plugins/ai_dev/README.md`, and the root
  `README.md` wherever this repo lists plugin skills.
- Because this adds a skill to an existing plugin, the ai_dev plugin metadata
  is bumped lockstep in the implementation commit according to the repo
  versioning rule. The new skill itself ships at `1.0.0`.
- A focused local test or eval exists for scope resolution and for the
  frontmatter-description discovery-safety check, including a fixture with a
  risky sibling-description outlier.
- `make lint` and `./deployment/deployment.sh --global --dry-run` pass.

## Related

- `plugins/ai_dev/skills/ai_instruction_formatting/SKILL.md` for the
  pseudo-XML structure expected in AI-consumed instructions.
- `plugins/ai_dev/skills/ai_instruction_writing/SKILL.md` for the
  positive, action-oriented wording expected in skill prose.
- `tests/README.md` and existing `tests/<skill>/` harnesses for local
  script-test, eval, and trigger-eval conventions.
