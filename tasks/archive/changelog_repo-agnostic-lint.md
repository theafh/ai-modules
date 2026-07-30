---
description: Pin changelog verification to whatever lint tooling the target repo actually provides — never assume make lint, never pull a network linter.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-02T20:06:20
updated: 2026-07-30T18:06:16
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Verify the changelog with the repo's own lint tooling, whatever it is

## Goal

Give the skill a deployment-agnostic verification step so the agent stops
improvising — and stops improvising **wrongly**. `update_changelog` ships into
arbitrary repositories, most of which have no `make lint` target and their own
linter (or none). The skill currently says nothing about how to verify the
written `CHANGELOG.md`, so behavior diverges per run: in one audited session the
agent reached for `npx --yes markdownlint-cli CHANGELOG.md`, which pulls a tool
over the network and applies a **different ruleset** than the repo configures,
then declared "lint passes" — a non-authoritative result. Replace the guesswork
with: discover the lint tooling the repo actually provides, run that, and skip
gracefully when there is none.

## Context

- Skill: `plugins/ai_dev/skills/update_changelog/SKILL.md`. No current clause covers post-write verification.
- Evidence (session-transcript audit, 2026-06-02): one audited session verified with `npx --yes markdownlint-cli CHANGELOG.md` — wrong because it ignores the repo's own markdownlint config (in this repo, `.markdownlint.jsonc` turns off MD033 for the intentional pseudo-XML), and `--yes` fetches from the network. A second session in the same audit correctly used the repo's `make lint` / `make lint-md`. The divergence is purely because the skill leaves verification unspecified.
- Key constraint from the user: **do not hardcode `make lint`.** That target is specific to this meta-repo; most target repos won't have it. The skill must use *whatever lint rules are available in the repo it is running in* — and if none exist, say so and skip rather than inventing one.
- This is a general-skill concern (the skill runs everywhere), distinct from this repo's own lint conventions (the repo rules). The fix lives in the skill prose, not in any repo-specific Makefile.

## Approach

- Add a `<verify>` step to `SKILL.md`'s `<procedure>`, running after `<land_new_days>` so it inspects the file the run actually left on disk: an incremental run holds its composed sections until the single splice in `<land_new_days>`, so a step after `<day_loop>` alone would lint the pre-run `CHANGELOG.md`, while a cold build has flushed every section by that point — one step after `<land_new_days>` covers both run types. The step discovers the repo's available linting in priority order and runs the first that applies, letting the owner of the invocation set its target: a repo entry point runs in the form the repo authored it, whole-repo included, while a linter the step invokes itself is pointed at `CHANGELOG.md`:
  1. A repo lint entry point if present — e.g. a `lint` / `lint-md` Make target (`make -n lint` to check existence first), a `package.json` lint script, a `pre-commit` hook config, or a documented project lint command.
  2. A project-configured markdown linter honoring the repo's own config — e.g. a local `markdownlint`/`markdownlint-cli2` with the repo's `.markdownlint*` config, only if already available in the repo/toolchain.
  3. If no linter is configured or available, **skip and say so** — report "no repo lint tooling found; skipped markdown verification" rather than installing or network-fetching one.
- Forbid the failure modes the audit caught: never `npx --yes`/network-install a linter, and never apply a default ruleset that ignores the repo's own lint config.
- Keep the step advisory and answerable for the changelog only: findings on `CHANGELOG.md` are its verdict, while a non-zero exit or a finding in a file this run did not write is reported as pre-existing repo state that settles nothing about the changelog. When the changelog itself draws findings, report them and leave the written `CHANGELOG.md` in place — the skill delivers the changelog on every branch, verification stays best-effort against whatever the repo offers, and a rewrite-producing lint-fix pass stays with the target repo's own standing rules.
- Phrase it deployment-agnostically (the skill has no idea which repo it's in); reference no specific repo's tooling by name in the normative text — `make lint` may appear only as one *example* among several, explicitly "if the repo has it."

**Out of scope:**

- Bundling a linter with the skill — the step runs only tooling the target repo already provides, and shipping one would add a dependency the standing repo rules keep out of the toolchain.
- Making markdown linting a hard gate on any branch of the ladder, including the branch where a discovered linter runs and reports findings — many target repos configure no linter at all, so a gate would strand the skill in exactly the repos it must still serve.

## Acceptance

- `SKILL.md` has a `<verify>` step that discovers the repo's own lint tooling in a clear priority order and runs the first that applies in the form its owner authored it — a repo entry point as the repo wrote it, a linter the step invokes itself pointed at `CHANGELOG.md` — and skips gracefully with a stated reason when none is found.
- `<verify>` sits in `SKILL.md`'s `<procedure>` after `<land_new_days>` and checks the changelog as it stands on disk at that point, so an incremental run's spliced-in day sections are in the file it reads; no other `<procedure>` step carries a verification directive of its own.
- The step states an outcome for each of the three branches — no tooling found, tooling runs clean, tooling runs and reports findings — and the written `CHANGELOG.md` stands on every one of them: the findings branch reports what the linter said about the changelog and leaves the file as written.
- The step's verdict answers for `CHANGELOG.md` only: a non-zero exit or a finding in a file this run did not write is reported as pre-existing repo state rather than a changelog verdict.
- The step reports and never rewrites: `<verify>` contains no pass that edits `CHANGELOG.md`, and `<date_immutability>` and `<preserve_existing>` are unchanged.
- The step explicitly prohibits `npx --yes`/network-installing a linter and prohibits applying a default ruleset that overrides the repo's lint config.
- No normative clause assumes `make lint` exists; any mention of it is illustrative and conditional.
