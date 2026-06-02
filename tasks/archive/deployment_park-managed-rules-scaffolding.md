---
description: Park the dormant managed-global-rules variables in deployment.sh as commented scaffolding with a revival note, clearing the SC2034 shellcheck findings.
scope: deployment
created: 2026-06-02T19:23:55
updated: 2026-06-02T22:59:28
status: implemented
---

# Park the dormant managed-global-rules scaffolding in deployment.sh

## Goal

`deployment/deployment.sh` carries five variables left over from a
managed-global-rules feature that another repo used to inject a shared rules
block into each tool's instruction file. The feature is not wired up here, so the
variables are declared and never read, and `shellcheck` — which `make lint`
runs over every shell file with no severity filter — exits 1 on five
**SC2034 "appears unused"** warnings.

Keep the scaffolding for possible future revival rather than deleting it, and
clear the lint findings by **commenting the five declarations out** with a short
note explaining what they were for and how to bring them back. Outcome:
`make lint` comes back clean, and the intent and exact strings of the dormant
feature stay recorded in place so it need not be reinvented if global-rules
deployment is wanted again.

## Context

The flagged lines in `deployment/deployment.sh` (current line numbers):

```text
233  # Instruction files that need rule references
234  CLAUDE_MD="${CLAUDE_DIR}/CLAUDE.md"
235  AGENTS_MD="${CODEX_DIR}/AGENTS.md"
236  GEMINI_MD="${GEMINI_DIR}/GEMINI.md"
237
238  # Markers for the managed block
239  MARKER_BEGIN="<!-- BEGIN GLOBAL RULES -->"
240  MARKER_END="<!-- END GLOBAL RULES -->"
```

These three paths plus two markers were the inputs to a routine that wrote a
`<!-- BEGIN GLOBAL RULES -->` … `<!-- END GLOBAL RULES -->` block into
`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`. That routine is gone; only the inputs
remain. A vestige also survives in the summary machinery — `SUMMARY_RULE_UPDATES`
(line ~256) and the `"instruction update(s)"` entry in `print_summary`
(line ~264) — but that counter is **read** by `print_summary`, so shellcheck does
not flag it and `set -u` would break if it were removed. Leave the summary
machinery exactly as is; this task touches only the five unused declarations.

Lines 241–242 (`DEPLOYED_ARTIFACTS_LOG`, `DEPLOYMENT_CONF`) directly follow the
parked block and stay live and unchanged.

Background: the global-rules injection was used in another repo's copy of this
script. Whether this repo ever uses it again is undecided — one likely direction
is codifying global rules into skills instead — so the scaffolding is parked, not
removed, pending that decision. This task is independent of
[the conf/log relocation task](../deployment_relocate-state-to-home.md), which
touches lines 241–242 but not the parked variables; whichever lands first, the
other still applies cleanly.

## Approach

- Comment out the five declarations (lines 234–236 and 239–240) so shellcheck no
  longer sees them as live unused variables.
- Replace the two terse header comments (233, 238) with a single short note that
  states the variables belong to a dormant managed-global-rules feature, that
  they are parked to keep the strings and intent on record, and the one line a
  reviver needs: re-enable these declarations and restore the routine that writes
  the marker-delimited block into each instruction file. Keep the note positive
  and brief.
- Leave `SUMMARY_RULE_UPDATES`, `print_summary`, and lines 241–242 untouched.

Keep the parked block as plain commented shell so it reads as code-in-waiting,
not prose. Prefer commenting the declarations over a `# shellcheck disable=SC2034`
directive: the variables are genuinely unused, so commenting them out represents
that honestly, whereas a disable directive would keep live-but-unused
declarations and hide the fact that the feature is dormant.

## Acceptance

- `shellcheck deployment/deployment.sh` reports no SC2034 findings for
  `CLAUDE_MD`, `AGENTS_MD`, `GEMINI_MD`, `MARKER_BEGIN`, `MARKER_END`; `make lint`
  exits 0.
- The five declarations remain in the file as commented scaffolding with their
  exact original right-hand-side values intact, under a note that explains the
  dormant feature and how to revive it.
- `SUMMARY_RULE_UPDATES`, the `print_summary` body, and lines 241–242 are
  unchanged, and the script still runs under `set -u`:
  `./deployment/deployment.sh --global --dry-run` completes without error.
