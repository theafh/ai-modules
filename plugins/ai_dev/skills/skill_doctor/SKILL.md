---
name: skill_doctor
description: Check-only doctor for skill artifacts. It audits SKILL.md frontmatter, descriptions that must serve both a browsing user and an LLM router, registration, tests, and instruction quality for one skill, a skill family, or every skill in the repo, editing no targets and running no harness-portability review. Use when checking a skill, auditing SKILL.md metadata or descriptions, reviewing skill-family readiness, verifying plugin or marketplace registration, or asking whether skill tests and trigger coverage exist before deeper instruction review.
version: 1.0.7
author: Andreas F. Hoffmann
license: MIT
---

# skill_doctor

<skill_doctor_skill>

<role>
skill_doctor is a skill-quality doctor for the skill artifacts of any repository that ships skills. It checks selected `SKILL.md` files and their surrounding registration, tests, metadata, and documentation for correctness and readiness, and it derives every requirement it gates on either from what the harness enforces or from what the checked repository's own rules state. It reports concrete findings with paths and evidence. It never implements the target skill's work and never edits selected skill artifacts.
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
Report findings only. Leave every selected skill artifact, and every other skill file, byte-for-byte unchanged for the duration of a check run. Applying fixes is a separate user-directed edit, never part of this workflow.
</check_only>

<scope_resolution>
Resolve scope before any check, and name the final target set out loud before continuing.

Every check targets the repository source tree, so pass that repo root as `--root` and resolve every selector inside it.

The resolver discovers the layout instead of requiring one. It walks the whole tree under `--root` for skill files, matching the filename case-insensitively the way the harness matches it, and it prunes version-control, dependency, build, and cache directories along with every path the repository itself ignores. It recognizes a `plugins/*/skills/` layout, a repo-root `skills/` tree, a `<vendor-config-dir>/skills/` tree, a single-skill repo whose `SKILL.md` sits at the top level, and a nested layout below the root, and it reports which layout each resolved skill came from under `layouts`, so the reader sees what was walked. Where a plugin manifest sits above a resolved skill, the payload records it as that skill's `plugin_host`, and the registration step reads that association. A copy of a skill deployed under a vendor configuration directory outside the repo root is a build output rather than a target, so a selector pointing at one resolves the repository source of the same name and reports the swap under `vendor_substitution`; name that substitution in the orientation lead.

- **Single skill.** A request that names one skill or one skill-file / skill-directory path stays on that skill. Run `scripts/resolve_scope.py --root <repo-root> --skill <name-or-path>`.
- **Family.** A request that names a family token expands to the matching sibling set. A family hub is the skill whose frontmatter `name:` equals the family token. Skills share that family-name when their frontmatter `name:` equals the token or equals the token followed by `_` and a non-empty suffix (`token_*`). Resolve a family as the set of skill directories the walk found whose skill names share that family-name, unioned with any skills named in the hub `SKILL.md` `<family>` block when that hub and block exist; when no hub or no `<family>` block is present, use that family-name set alone. Run `scripts/resolve_scope.py --root <repo-root> --family <token>`.

  The resolver identifies that `<family>` block structurally rather than by first occurrence: the opening tag has to own its line, outside every fenced code block and inline code span, and a closing tag has to follow it. An author may therefore document the tag freely (naming `<family>` in prose, quoting it in backticks, or showing a whole example block inside a fence) and contribute no members. A body carrying an opening tag with no closing tag declares no block at all and resolves by name prefix alone. Members come from the leading backticked token of each block list item, so a trailing mention such as ``- `task_finish`: bump `updated` `` declares one name rather than two.

  A family run reports what its resolution cannot vouch for. The payload groups the resolved set under `by_plugin`, keyed on each member's owning plugin, so a cross-plugin split reads at a glance; a skill with no plugin manifest above it stays in the flat set and is grouped separately. The `warnings` collection carries three findings, each naming the skills and paths involved: a name-prefix set spanning more than one plugin, a prefix sibling the hub's parsed block omits, and a block entry naming no discovered skill. A same-prefix skill in another plugin stays in the resolved set, since a genuine cross-plugin family is what the block's union serves. The run states the split instead of assuming either reading. All three stay warnings, since the harness loads every one of these skills and a hub may deliberately omit a deprecated sibling.
- **Whole repo.** A whole-repo request covers every skill the walk finds under the repo root. Run `scripts/resolve_scope.py --root <repo-root> --all`.

This skill checks skills only. Agent definitions stay outside every scope mode, `--all` included, and in a plugin-shaped repository they live under `plugins/*/agents/`. When a name or path selector identifies such a definition, report that boundary before invoking `scripts/resolve_scope.py`, route the request to `harness_portability` for an agent definition's portable runtime surface and frontmatter, add `ai_instruction_writing` / `ai_instruction_formatting` when the ask is prose authoring, and stop. That pre-resolver stop keeps a named agent off the failure classes below, since the agent never reaches the resolver to read as an unknown skill name or a rejected selector path.

When `scripts/resolve_scope.py` exits nonzero, stop and report its message rather than substituting a target set of your own. Each failure class carries its own remedy:

- **An absent walk**: `no SKILL.md found under <root>`, which `--skill`, `--family`, and `--all` all emit alike. Report that the repository exposes no skill file anywhere under that root and ask which tree to read.
- **An unknown name**: `skill not found:` or `no skills found for family token:`, raised when the tree exists and the selector misses inside it. List the nearest candidates the walk did find, then ask which one the user means.
- **A selector path fault**: `skill path not found:` or `skill path escapes repo root:`. Report the path the resolver rejected and ask for a corrected one.
- **An environment or usage fault**: an unreadable `SKILL.md` (`cannot read`), a `--root` that is not a directory (`root is not a directory:`), or a request that names no scope mode (rejected by argument parsing). Report the fault itself, so the reader fixes the environment or the invocation instead of disambiguating a name.
</scope_resolution>

<discovery_safety>
Discovery safety is the first required check on every run. After naming the resolved target set, run `scripts/discovery_safety.py` under the same `--root` on every selected `SKILL.md` (for a family request, pass every sibling so outliers are visible).

The script, and the manual follow-through when a path needs judgment, covers:

- Inspect the skill file the harness would load: that it is a regular file, that it stays inside the harness plugin-skill byte limit, and that its directory holds exactly one skill file.
- Parse each selected `SKILL.md` frontmatter with normal YAML handling and flag parser-hostile values.
- Inspect `name` and `description` for manifest usability, report a `name:` that disagrees with its directory, and report an absent `version:` as the convention-owned fact it is.
- Audit each `description:` against the standing repo rule **Write skill descriptions for both audiences.** Treat user readability and LLM trigger matching as separate requirements and judge their balance: a user-readable purpose summary first, then trigger-rich `Use when` language, neither a keyword dump nor a prose-only summary.
- Flag descriptions that leak internal workflow into `description:` and keep those implementation details in the skill body.
- Measure each `description:` on its own against the harness skill-listing character budget, so a description long enough to risk losing its listing entry draws a finding whether or not the run selected any siblings.
- Compare sibling descriptions within one comparison group for formatting outliers, risky punctuation, typographic punctuation, routing overlap, and user-readable high-level distinctness.

A sibling finding measures one description against the skills a deliberate declaration binds it to, so the script derives that comparison group itself from the walk under `--root` and takes no grouping argument from the run. It reads the family-name token each selected skill's own name implies, the name's leading segment, which is the broadest token a family request accepts and the one that keeps a hubless prefix family whole. It resolves that token the way a family run resolves it, as the name-prefix set unioned with any members the hub's `<family>` block declares, and then splits a same-prefix member another plugin hosts into its own group unless that block names it. Splitting needs a second plugin to split into, so a family hosted wholly inside one plugin stays one group. A skill that no declaration binds to another is a group of one and draws no sibling finding, and every finding names its group under `comparison_groups` and inside its own message. A repo-wide house-style comparison across unaffiliated skills is a separate question that no finding here claims to answer.

Description length carries two findings that answer different questions, and both stay. The per-skill finding reads one file against the harness listing budget: Claude Code builds its skill listing under a character budget of `contextWindow × 4` bytes-per-token `× skillListingBudgetFraction` (default `0.01`), roughly 8,000 characters at a 200k-token window, and each entry costs its name plus its description truncated to `skillListingMaxDescChars` (default `1536`). When the entries overrun that budget, the listing keeps them greedily by a recency-weighted usage score, `usageCount × max(0.5 ^ (daysSinceUse / 7), 0.1)`, and lists everything else by name alone. A never-invoked skill scores zero on that ranking, so a long description on a new skill is first to lose it, exactly when the description is the only thing that could get the skill invoked. Both are real `settings.json` keys, so a reader whose own numbers come out differently can check for a raised value. The sibling finding reads one comparison group instead and asks whether one description's length is out of step with its family, which is a question about house style rather than about budget risk.

A skill that shows up in a session listing as a bare name with no description at all comes from one of two mechanisms, not from frontmatter the harness failed to parse: the budget truncation above, or a per-skill listing override whose `name-only` value lists the skill without its description. Read the length against the budget and check for that override first, and treat the frontmatter as a parse suspect only once both come back clean.

The typographic-punctuation finding covers the marks that stand in for sentence structure: the em dash, the en dash, the curly single and double quotes, and the ellipsis. Every one of them parses safely in UTF-8 frontmatter, so what the finding reports is a writing habit rather than an encoding hazard, and it stays silent on an accented Latin letter, a proper name, or a non-Latin script. `ai_instruction_writing` bans the em dash and en dash outright in AI-consumed content, so cite that rule and recommend rewriting the description until no dash remains, splitting a dash that joins two clauses into two sentences. Splitting suits a `description:` value in particular, because an unquoted colon in that scalar trips this run's own YAML-safety check. A hyphen, a double hyphen, or an en dash substituted into that slot keeps the original break and counts as no fix, which is why the remedy is a rewrite rather than a substitution. Parse safety is checked on its own axis by character class, so a control character, an invisible mark, and risky punctuation each keep their own finding.

Severity follows what a finding can prove, across three tiers.

**Blocking** holds the cases where the harness fails to load the skill or cannot route it, each one visible in the harness's own skill load path: frontmatter that is absent or that the parser cannot destructure, an absent `name`, an absent `description`, a parser-hostile or invisible character in the description, a skill file the harness skips because it is not a regular file or exceeds the plugin-skill byte limit, more than one skill file in one directory, and a sibling purpose summary byte-identical to another. The ambiguous-file case blocks because the harness matches the skill filename case-insensitively, picks one file, and logs which it used, so the file it loads need not be the file the author edited. The byte limit is read out of the installed harness CLI at check time, from the `Skipping plugin skill ... byte limit` message that CLI itself emits, so the finding tracks the harness actually installed instead of a number frozen into a script. A value read on one host is authoritative for that host alone: the checked skill deploys to other machines that run their own harness builds, so any limit is a hint about every other system. When no installed CLI yields the message, the check runs against the recorded fallback the script carries with its provenance date rather than going silent, and the verification summary names which source supplied the limit; a probed value that disagrees with the recorded fallback is reported as drift so the recording gets refreshed.

**Warning** holds every judgement about description *quality* (dual-audience balance, workflow leakage, routing overlap, risky punctuation, typographic punctuation, listing-budget length, sibling length outliers), because no heuristic separates "carries no trigger coverage" from "phrases its triggers differently", and a false block on a healthy shipped skill costs the reader more than a warning they dismiss. A frontmatter `name:` that disagrees with its directory warns here as well, settled by reading the harness load path rather than by assumption: the loader registers a skill under its frontmatter `name:` and falls back to the directory basename only when that field is absent, so such a skill still loads, lists, and routes. `scripts/discovery_safety.py` carries that observation under `severity_records` and reads the emitted severity from it, so the record and the finding stay in agreement.

**Info** holds a fact that is true of the file while a repository convention owns the requirement rather than the harness. An absent `version:` sits here: no harness field reads a skill's `version`, so the finding states the fact, cites the version rule the checked repository's standing rule files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, and equivalents) state when they state one, and says no such rule was found when they do not.

Report every dimension in each tier; severity changes what the run gates on, never what it inspects.

Leave the standing **Write skill descriptions for both audiences.** rule in the standing repo rule files; cite it, do not relocate or remove it.
</discovery_safety>

<workflow>
Run in order. Edit no skill artifacts.

1. **Orient.** Read the repo instructions. Identify the selected scope (single skill, family, or all skills). Resolve directories with `scripts/resolve_scope.py` per `<scope_resolution>`, then name the final target set before checking.
2. **Discovery safety first.** Run `scripts/discovery_safety.py` on the resolved set per `<discovery_safety>`. Record blocking issues, warnings, and info-tier findings with paths and evidence, and carry the script's `checks` entries into the verification summary so a check it skipped reaches the reader with its reason.
3. **Registration.** Check each registration surface the checked repository actually exposes, and report a surface it never adopted as not applicable rather than as missing. Read the resolved skill's `plugin_host` from the resolver payload: where a plugin manifest owns the skill, name that manifest and check the fields the harness reads from it, including a skills pointer where the manifest shape carries one; where the repository ships no manifest at all, report registration as not applicable in full. Check a marketplace entry when a marketplace file exists, and report the marketplace check as not applicable when none does. Check directory name, frontmatter `name:`, and H1 alignment, and check that each selected skill is listed where a README convention requires it. Each of these is conditional on the checked repository's standing rule files stating that convention, and each produces no finding where they state none. Apply a plugin-version lockstep check only where those rules state one, cite the rule by name from them, and skip it silently where they state none. A skill's `version:` differing from its plugin's version is not an inconsistency by itself.
4. **Tests and verification.** Before the instruction-quality pass, discover the checks the repository defines and run the ones that cover the selected paths. Read the standing harness rule files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, and equivalents) first, since a repository states its own gates there, then find the entry points it exposes (`Makefile` targets, mise tasks, a pre-commit config, package scripts, or a CI workflow) and run those, reporting each with the exact command it ran under and reporting every check that could not run with its reason. Where a discovered entry point publishes or deploys, run only its preview form, and leave the writing form to the user per the checked repository's own gate on it. Two requirements are about the skill artifact rather than repo tooling, so they hold at the level of coverage wherever the repository keeps it: a skill that bundles scripts needs a script-test surface somewhere in the repo, and a behaviour-only skill needs eval or trigger coverage or a documented reason it has none. Warn when either is absent. Run the pseudo-XML lint that `ai_instruction_formatting` bundles when that sibling skill resolves, and name it as skipped with its reason when it does not.
5. **Instruction quality.** Apply `ai_instruction_formatting` and `ai_instruction_writing` by citation only: read those skills and check selected bodies against their contracts for pseudo-XML organization, positive action-oriented wording, and clear role, inputs, workflow, and output contract. Keep those rule bodies in their source skills; do not copy them into this skill. When a family is in scope, also check sibling boundaries so each skill's activation surface stays distinct.
6. **Report.** Emit the report per `<output_contract>`.
</workflow>

<output_contract>
Structure the report as:

- A short orientation lead that names the resolved scope mode, the layout the walk resolved, any vendor-to-source substitution it applied, and the exact target skill set grouped under the plugin that owns each member, with members carrying no plugin manifest grouped separately.
- **Blocking issues** first, each with file path and greppable evidence.
- **Warnings** next, same evidence shape, carrying the resolver's family warnings alongside the discovery-safety ones: a name-prefix family spanning more than one plugin, a prefix sibling the hub's `<family>` block omits, and a block entry naming no discovered skill.
- **Info** next, same evidence shape, for each fact a repository convention owns rather than the harness, naming the rule the finding cites or stating that the rule files carry none.
- A short **verification summary** that lists the exact commands run and calls out every check that could not run, each with its reason.

When clean, write exactly `No blocking issues.` under the blocking section and keep the verification summary. Edit nothing.
</output_contract>

<examples>
- Single skill: `check the ai_instruction_writing skill`
- Family: `check the wiki family skills`
- Whole repo: `check all skills in this repo`
</examples>

<boundary>
skill_doctor checks and reports. It does not apply fixes or rewrites during a check run. It does not run or embed a `harness_portability` cross-harness/OS portability review. That review stays with `harness_portability`.
</boundary>

</skill_doctor_skill>
