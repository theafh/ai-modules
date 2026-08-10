---
name: skill_doctor
description: Check-only doctor for skill artifacts — audits SKILL.md frontmatter and dual-audience descriptions, registration, tests, and instruction quality for one skill, a skill family, or every skill in the repo, without editing targets or running harness-portability review. Use when checking a skill, auditing SKILL.md metadata or descriptions, reviewing skill-family readiness, verifying plugin or marketplace registration, or asking whether skill tests and trigger coverage exist before deeper instruction review.
version: 1.0.0
author: Andreas F. Hoffmann
license: MIT
---

# skill_doctor

<skill_doctor_skill>

<role>
skill_doctor is a general skill-quality doctor for AI component artifacts. It checks selected `SKILL.md` files and their surrounding registration, tests, metadata, and documentation for correctness and readiness. It reports concrete findings with paths and evidence. It never implements the target skill's work and never edits selected skill artifacts.
</role>

<when_to_activate>
Activate when the user wants skill definitions checked:

- "Check the ai_instruction_writing skill" / "audit this SKILL.md" / "is this skill's description router-safe?"
- "Check the wiki family skills" / "doctor the task_* skills."
- "Check all skills in this repo" / "skill health-check for the whole tree."

Route cross-harness and cross-OS portability review of bundled runtime artefacts to `harness_portability`. Route authoring rewrites of instruction prose to `ai_instruction_writing` / `ai_instruction_formatting` after this skill reports findings.
</when_to_activate>

<path_resolution>
Bundled scripts live in `scripts/` next to this `SKILL.md`. Resolve each script's absolute path by combining the directory of this `SKILL.md` with `scripts/<script-name>` and invoke that absolute path. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.
</path_resolution>

<check_only>
Report findings only. Leave every selected skill artifact — and every other skill file — byte-for-byte unchanged for the duration of a check run. Applying fixes is a separate user-directed edit, never part of this workflow.
</check_only>

<scope_resolution>
Resolve scope before any check, and name the final target set out loud before continuing.

- **Single skill.** A request that names one skill or one `SKILL.md` / skill-directory path stays on that skill. Run `scripts/resolve_scope.py --root <repo-root> --skill <name-or-path>`.
- **Family.** A request that names a family token expands to the matching sibling set. A family hub is the skill whose frontmatter `name:` equals the family token. Skills share that family-name when their frontmatter `name:` equals the token or equals the token followed by `_` and a non-empty suffix (`token_*`). Resolve a family as the set of `plugins/*/skills/` directories whose skill names share that family-name, unioned with any skills named in the hub `SKILL.md` `<family>` block when that hub and block exist; when no hub or no `<family>` block is present, use that family-name set alone. Run `scripts/resolve_scope.py --root <repo-root> --family <token>`.
- **Whole repo.** A whole-repo request walks every skill directory the repository exposes under `plugins/*/skills/`. Run `scripts/resolve_scope.py --root <repo-root> --all`.

Exclude agents unless the user names them. Agents live under `plugins/*/agents/` and are outside the default skill walk.
</scope_resolution>

<discovery_safety>
Discovery safety is the first required check on every run. After naming the resolved target set, run `scripts/discovery_safety.py` on every selected `SKILL.md` (for a family request, pass every sibling so outliers are visible).

The script — and the manual follow-through when a path needs judgment — covers:

- Parse each selected `SKILL.md` frontmatter with normal YAML handling and flag parser-hostile values.
- Inspect `name`, `description`, and `version` for manifest usability; keep directory name equal to frontmatter `name:` at this layer too.
- Audit each `description:` against the standing repo rule **Write skill descriptions for both audiences.** Treat user readability and LLM trigger matching as separate requirements and judge their balance: a user-readable purpose summary first, then trigger-rich `Use when` language — neither a keyword dump nor a prose-only summary.
- Flag descriptions that leak internal workflow into `description:` and keep those implementation details in the skill body.
- Compare sibling descriptions inside the same selected set for formatting outliers, risky punctuation, non-ASCII characters, routing overlap, and user-readable high-level distinctness.

Severity follows what a finding can prove. A finding blocks when it states a mechanical fact about the file: absent or unparseable frontmatter, a missing `name` / `description` / `version`, a name that disagrees with its directory, a parser-hostile or invisible character, or a sibling purpose summary that is byte-identical to another. Every judgement about description *quality* — dual-audience balance, workflow leakage, routing overlap, risky punctuation, typographic non-ASCII, length outliers — is reported as a warning, because no heuristic separates "carries no trigger coverage" from "phrases its triggers differently", and a false block on a healthy shipped skill costs the reader more than a warning they dismiss. Report every dimension either way; severity changes what the run gates on, never what it inspects.

Leave the standing **Write skill descriptions for both audiences.** rule in the standing repo rule files; cite it, do not relocate or remove it.
</discovery_safety>

<workflow>
Run in order. Edit no skill artifacts.

1. **Orient.** Read the repo instructions. Identify the selected scope (single skill, family, or all skills). Resolve directories with `scripts/resolve_scope.py` per `<scope_resolution>`, then name the final target set before checking.
2. **Discovery safety first.** Run `scripts/discovery_safety.py` on the resolved set per `<discovery_safety>`. Record blocking issues and warnings with paths and evidence.
3. **Registration.** For each selected skill, confirm directory name equals frontmatter `name:`, and H1 is a casing-or-spacing variant of `name:`, per the `ai_instruction_formatting` mechanical rules and the standing **Keep the directory name, the frontmatter `name:`, and the H1 heading aligned.** rule. Confirm registration follows this repo's shape: `.codex-plugin/plugin.json` keeps `"skills": "./skills/"`; `.claude-plugin/plugin.json` stays in version/description/README lockstep without that pointer; marketplace files register plugins (not per-skill arrays); when the repo convention lists skills in the plugin README or root README, confirm each selected skill is named where that convention requires. Apply the standing **Plugin meta stays lockstep.** rule as a version check: plugin `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json`, and marketplace entries share one plugin version; a skill's `version:` that differs from that plugin version is not treated as inconsistency by itself.
4. **Tests and verification.** Before the instruction-quality pass, identify or run the applicable verification surfaces for each selected skill: script tests under `tests/<skill>/script_tests/`, behavioral or trigger evals under `tests/<skill>/evals/` (or the repo's trigger-eval surface), `markdownlint` on applicable selected paths, `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py` on selected skill hosts, `jq empty` on applicable manifest JSON, and `./deployment/deployment.sh --global --dry-run` as preview-only (it applies no deploy writes, so this skill may run it during a check without a fresh user ask; the standing repo rule that gates `make deploy` on an explicit user ask still applies to any non-dry-run deploy). When a selected skill has bundled scripts, require a script-test surface. When it has behavior-only prose, require eval coverage or an explicit documented reason that coverage is missing. Record the exact commands run and name every check that could not run.
5. **Instruction quality.** Apply `ai_instruction_formatting` and `ai_instruction_writing` by citation only — read those skills and check selected bodies against their contracts for pseudo-XML organization, positive action-oriented wording, and clear role, inputs, workflow, and output contract. Keep those rule bodies in their source skills; do not copy them into this skill. When a family is in scope, also check sibling boundaries so each skill's activation surface stays distinct.
6. **Report.** Emit the report per `<output_contract>`.
</workflow>

<output_contract>
Structure the report as:

- A short orientation lead that names the resolved scope mode and the exact target skill set.
- **Blocking issues** first — each with file path and greppable evidence.
- **Warnings** next — same evidence shape.
- A short **verification summary** that lists the exact commands run and calls out every check that could not run.

When clean, write exactly `No blocking issues.` under the blocking section and keep the verification summary. Edit nothing.
</output_contract>

<examples>
- Single skill: `check the ai_instruction_writing skill`
- Family: `check the wiki family skills`
- Whole repo: `check all skills in this repo`
</examples>

<boundary>
skill_doctor checks and reports. It does not apply fixes or rewrites during a check run. It does not run or embed a `harness_portability` cross-harness/OS portability review — that review stays with `harness_portability`.
</boundary>

</skill_doctor_skill>
