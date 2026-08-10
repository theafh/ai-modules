---
description: Add skill_doctor to audit skill definitions, metadata, descriptions, tests, trigger readiness, and registration for one skill, a skill family, or all repo skills.
scope: plugins/ai_dev/skills
created: 2026-06-14T16:53:22
updated: 2026-08-10T20:47:33
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
status: audited
design-extended: false
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
Cross-harness and cross-OS portability review of bundled runtime artefacts
stays with `harness_portability`; `skill_doctor` does not own that review.

Skill frontmatter descriptions are load-bearing because the agent harness
uses them to decide when to load a skill. A broken, ambiguous, overlapping,
or parser-hostile description can make a valid skill disappear or route the
wrong skill. The standing repo rule **Write skill descriptions for both
audiences.** is the authoring baseline. `skill_doctor` starts every run with
a discovery-safety check that audits selected skills against that baseline
before deeper content review:

- parse each selected `SKILL.md` frontmatter with normal YAML handling;
- inspect `name`, `description`, and `version` for manifest usability;
- audit each `description:` against that standing rule, treating user
  readability and LLM trigger matching as separate requirements and judging
  their balance (user-readable summary first, then trigger-rich language —
  neither a keyword dump nor a prose-only summary);
- flag descriptions that leak internal workflow into `description:` and
  direct those implementation details into the skill body;
- compare sibling descriptions inside the same family for formatting
  outliers, risky punctuation, non-ASCII characters, and routing overlap;
- confirm each description remains distinct from sibling descriptions at a
  user-readable high level;
- check that the relevant test and lint surfaces exist for the skill's
  needs, and that they are run or identified before the instruction-quality
  pass.

The first verification surface should be generic and selected from the
target skills themselves:

- frontmatter descriptions parse safely, and sibling comparison flags
  risky punctuation and non-ASCII characters;
- names, headings, directories, and manifest entries agree;
- version fields follow the standing **Plugin meta stays lockstep.** rule:
  plugin `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json`, and
  marketplace entries share one plugin version; a skill's `version:` need
  not equal that plugin version;
- bundled scripts have a script-test surface;
- behavior-only skills have eval or trigger-eval coverage, or a documented
  reason that coverage is missing;
- `markdownlint` on applicable selected paths,
  `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py`,
  `jq empty` on applicable manifest JSON (JSON manifest validation), and
  `./deployment/deployment.sh --global --dry-run` are run when they apply
  to the repository.

## Approach

Implement the new skill as `plugins/ai_dev/skills/skill_doctor/SKILL.md`.
Follow the standing repo rules for skill authoring; this task supplies the
`skill_doctor`-specific behaviour and examples. Ship the new
skill at `version: 1.0.0`.

The check workflow reports concrete findings with file paths and evidence
and never edits the selected skill artifacts (or any other skill files).

Recommended workflow:

1. **Orient.** Read the repo instructions and identify the selected scope:
   single skill, family, or all skills in the repo. Resolve each selected
   skill directory and name the final set before checking. A family hub is
   the skill whose frontmatter `name:` equals the family token named in the
   request. Skills share that family-name when their frontmatter `name:`
   equals the family token or equals the token followed by `_` and a
   non-empty suffix (`token_*`). Resolve a family as the set of
   `plugins/*/skills/` directories whose skill names share that family-name,
   unioned with any skills named in the hub `SKILL.md` `<family>` block when
   that hub and block exist; when no hub or no `<family>` block is present,
   use that family-name set alone. Exclude agents unless the user names
   them.
2. **Discovery safety first.** Parse selected `SKILL.md` frontmatter and
   compare sibling descriptions for YAML safety, risky characters,
   human-reader clarity, LLM-router trigger coverage, the balance between
   those two audiences, workflow leakage, routing overlap, and
   user-readable high-level distinctness from sibling descriptions (per
   Context). For a family request, include every sibling in that family so
   outliers are visible.
3. **Registration.** Check that each selected skill keeps directory name
   equal to frontmatter `name:`, and H1 a casing-or-spacing variant of
   `name:`, per the `ai_instruction_formatting` mechanical rules (and the
   standing **Keep the directory name, the frontmatter `name:`, and the H1
   heading aligned.** rule; Context: names, headings, directories, and
   manifest entries agree), and that registration follows this repo's
   shape: `.codex-plugin/plugin.json` keeps the directory pointer
   `"skills": "./skills/"`; `.claude-plugin/plugin.json` stays in
   version/description/README lockstep without that pointer; marketplace
   files register plugins (not per-skill arrays); when the repo convention
   lists skills in the plugin README or root README, check that each
   selected skill is named where that convention requires.
4. **Tests and verification.** Run or identify the applicable script tests,
   behavioral evals, trigger evals, `markdownlint` on applicable selected
   paths,
   `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py`,
   `jq empty` on applicable manifest JSON (JSON manifest validation), and
   `./deployment/deployment.sh --global --dry-run`. That dry-run is
   preview-only (it applies no deploy writes), so `skill_doctor` may run it
   during a check without a fresh user ask; the standing repo rule that
   gates `make deploy` on an explicit user ask still applies to any
   non-dry-run deploy. Confirm these surfaces exist for the skill's needs,
   and run or identify them before the instruction-quality pass. When a
   selected skill has bundled scripts, require a script test surface. When
   it has behavior-only prose, require eval coverage or an explicit reason
   it is missing.
5. **Instruction quality.** Apply `ai_instruction_formatting` and
   `ai_instruction_writing` by citation (already listed under Related):
   check selected skill bodies against those skills' contracts for
   pseudo-XML organization, positive action-oriented wording, and clear
   role, inputs, workflow, and output contract. Keep those rule bodies in
   their source skills — do not copy them into `skill_doctor`. Check
   sibling boundaries when a family exists.
6. **Report.** Return a concise verdict with blocking issues first, then
   warnings, then a short verification summary. Include the exact commands
   run and call out checks that could not run.

The skill should include examples for all three scopes:

- `check the ai_instruction_writing skill`;
- `check the wiki family skills`;
- `check all skills in this repo`.

Local harness. Add a Pattern A harness under `tests/skill_doctor/` per
`tests/README.md` that covers the Acceptance focused local test or eval
cases (scope-resolution hub-with-`<family>` and prefix-only cases, plus the
risky sibling-description discovery-safety fixture).

**Shipping `skill_doctor`.** When adding the skill in this task (outside the
check workflow above): name `skill_doctor` in the `ai_dev` plugin
description and README skill listings, and in the root README wherever this
repo lists plugin skills; advance the `ai_dev` plugin version in lockstep
across `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json`, and both
marketplace entries per the standing **Plugin meta stays lockstep.** rule.

**Out of scope:**

- Applying fixes or rewrites to skill artifacts during a `skill_doctor`
  check run.
- Running or embedding a `harness_portability` cross-harness/OS
  portability review as part of `skill_doctor`'s check workflow (that
  review stays with `harness_portability`).

## Acceptance

- A new `plugins/ai_dev/skills/skill_doctor/SKILL.md` exists with frontmatter
  `name: skill_doctor`, `version: 1.0.0`, and a clear non-overlapping
  description.
- The skill supports single-skill, family, and whole-repo scopes, and its
  instructions require the resolved target set to be named before checking.
- Family scope resolution follows the Orient family-name definition (hub
  token equality, `token_*` siblings, optional `<family>` union, agents
  excluded unless named).
- The first required check is discovery safety for `SKILL.md` frontmatter
  and descriptions, including family outlier comparison, risky punctuation,
  non-ASCII characters, routing overlap, trigger-matching coverage,
  human-readable purpose, workflow-detail leakage, and user-readable
  high-level distinctness from sibling descriptions (per Context).
- The description audit enforces the standing **Write skill descriptions for
  both audiences.** rule cited in Context, including workflow-detail leakage
  into the body, and leaves that standing rule in place in the standing repo
  rule files (no relocate or remove).
- The description audit treats user readability and LLM trigger matching as
  separate requirements: it flags descriptions that read well for humans but
  lack routing keywords, and descriptions that expose many keywords but fail
  to explain the skill's purpose clearly to a user.
- The check set is derived from the selected skill artifacts and applies to
  any skill family, not to one hard-coded family.
- The skill is check-only: it reports file-specific findings with evidence
  and never edits skill artifacts, per Approach.
- For each skill in the resolved target set, the workflow checks that
  directory name equals frontmatter `name:` and H1 is a casing-or-spacing
  variant of `name:` per the `ai_instruction_formatting` mechanical rules,
  the standing **Keep the directory name, the frontmatter `name:`, and the
  H1 heading aligned.** rule, and the Context identity bullet, and checks
  registration in plugin metadata, marketplace metadata where applicable,
  the plugin README, and the root README when the repo convention requires
  it.
- For each skill in the resolved target set, the version check applies
  **Plugin meta stays lockstep.** as defined in Context: plugin manifests
  and marketplace entries share one plugin version, and a skill `version:`
  that differs from the plugin version is not treated as inconsistency by
  itself.
- The workflow includes an instruction-quality pass that applies
  `ai_instruction_formatting` and `ai_instruction_writing` by citation only
  (no copied rule bodies), covering pseudo-XML organization, positive
  action-oriented wording, clear role, inputs, workflow, and output contract,
  plus sibling-boundary checks when a family is in scope.
- The workflow identifies or runs the applicable verification surfaces for
  each selected skill — script tests, behavioral or trigger evals,
  `markdownlint` on applicable selected paths,
  `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py`,
  `jq empty` on applicable manifest JSON (JSON manifest validation), and
  `./deployment/deployment.sh --global --dry-run` as preview-only per
  Approach — and requires a script-test surface when bundled scripts exist,
  or eval coverage or an explicit missing-coverage reason for behavior-only
  skills, and requires that those surfaces are run or identified before the
  instruction-quality pass, per Approach **Tests and verification.**
- The report returns blocking issues first, then warnings, then a short
  verification summary, names the exact commands run, and calls out checks
  that could not run.
- The skill documents examples for all three scopes: checking one named
  skill (`ai_instruction_writing`), checking a family (`wiki`), and checking
  all skills in the repo.
- Registration follows Approach **Registration.** for check-only shape:
  `.codex-plugin/plugin.json` keeps `"skills": "./skills/"`;
  `.claude-plugin/plugin.json` stays in version/description/README lockstep
  without that pointer; marketplace files register plugins (not a per-skill
  array); selected skills are named in README listings when the repo
  convention requires it. Shipping follows Approach **Shipping
  `skill_doctor`.**: name `skill_doctor` in the `ai_dev` plugin description
  and README skill listings, and in the root README wherever this repo lists
  plugin skills; plugin.json and marketplace `ai_dev` versions stay lockstep
  per the standing **Plugin meta stays lockstep.** rule.
- The new skill itself ships at `version: 1.0.0` per the standing **Ship a
  new skill, agent, or plugin at 1.0.0.** rule.
- A Pattern A harness under `tests/skill_doctor/` per `tests/README.md`
  exists per Approach **Local harness.**, covering the focused local test
  or eval cases for scope resolution — including a hub-with-`<family>` case
  and a prefix-only (no `<family>`) case — and for the
  frontmatter-description discovery-safety check, including a fixture with
  a risky sibling-description outlier.

## Related

- `plugins/ai_dev/skills/ai_instruction_formatting/SKILL.md` for the
  pseudo-XML structure expected in AI-consumed instructions.
- `plugins/ai_dev/skills/ai_instruction_writing/SKILL.md` for the
  positive, action-oriented wording expected in skill prose.
- `tests/README.md` and existing `tests/<skill>/` harnesses for local
  script-test, eval, and trigger-eval conventions.
