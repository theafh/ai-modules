---
description: Pin changelog verification to whatever lint tooling the target repo actually provides — never assume make lint, never pull a network linter.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-02T20:06:20
updated: 2026-06-02T21:12:48
status: open
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
- Evidence (session-transcript audit, 2026-06-02): session `fa358b26` verified with `npx --yes markdownlint-cli CHANGELOG.md` — wrong because it ignores the repo's own markdownlint config (in this repo, `.markdownlint.jsonc` turns off MD033 for the intentional pseudo-XML), and `--yes` fetches from the network. Session `8fad43d6` correctly used the repo's `make lint` / `make lint-md`. The divergence is purely because the skill leaves verification unspecified.
- Key constraint from the user: **do not hardcode `make lint`.** That target is specific to this meta-repo; most target repos won't have it. The skill must use *whatever lint rules are available in the repo it is running in* — and if none exist, say so and skip rather than inventing one.
- This is a general-skill concern (the skill runs everywhere), distinct from this repo's own `CLAUDE.md` lint conventions. The fix lives in the skill prose, not in any repo-specific Makefile.

## Approach

- Add a `<verify>` step (after the day-write loop) to `SKILL.md` that discovers the repo's available linting in priority order and runs the first that applies, scoped to `CHANGELOG.md`:
  1. A repo lint entry point if present — e.g. a `lint` / `lint-md` Make target (`make -n lint` to check existence first), a `package.json` lint script, a `pre-commit` hook config, or a documented project lint command.
  2. A project-configured markdown linter honoring the repo's own config — e.g. a local `markdownlint`/`markdownlint-cli2` with the repo's `.markdownlint*` config, only if already available in the repo/toolchain.
  3. If no linter is configured or available, **skip and say so** — report "no repo lint tooling found; skipped markdown verification" rather than installing or network-fetching one.
- Forbid the failure modes the audit caught: never `npx --yes`/network-install a linter, and never apply a default ruleset that ignores the repo's own lint config.
- Keep the step advisory to the changelog only — it verifies the file the skill just wrote, not the whole repo.
- Phrase it deployment-agnostically (the skill has no idea which repo it's in); reference no specific repo's tooling by name in the normative text — `make lint` may appear only as one *example* among several, explicitly "if the repo has it."

Non-goals: don't add a bundled linter to the skill; don't make markdown linting a hard gate that blocks output when no linter exists. The skill produces the changelog regardless; verification is best-effort against whatever the repo offers.

## Acceptance

- `SKILL.md` has a `<verify>` step that discovers and runs the repo's own lint tooling against `CHANGELOG.md`, with a clear priority order and a graceful skip when none is found.
- The step explicitly prohibits `npx --yes`/network-installing a linter and prohibits applying a default ruleset that overrides the repo's lint config.
- No normative clause assumes `make lint` exists; any mention of it is illustrative and conditional.
- Running `make lint` in *this* repo still comes back clean for the edited skill.
