#!/usr/bin/env bash
# fix_coherence fixture: one live backlog whose tasks are each individually
# plausible but jointly incoherent, plus the target artifacts they point at.
# Shared by three evals — fix_coherence (assess only),
# fix_coherence_reconcile_escalated, and
# fix_coherence_reconcile_inline_staleness — the same
# update / update_contract precedent of one fixture behind several prompts.
#
# The twelve planted defects, by the letters the task's Acceptance uses:
#   (a) one edit double-owned: tool_severity-label-rename.md and
#       tool_severity-label-docstring.md both rewrite severity_label();
#       tool_severity-label-consumer.md assumes the rename task owns it.
#       The docstring task names the helper in its ## Goal WITHOUT quoting
#       `def severity_label(`: the rename task renames that symbol, so a Goal
#       quoting it would force the anchor refresh to edit a frozen Goal, and the
#       correct repair would then violate the frozen-Goal rule it must honour.
#       Keep every anchor a sibling can rename out of the ## Goal.
#   (b) stale anchor: tool_clean-bar-note.md quotes unreachable_clean_bar,
#       which archive/tool_rename-clean-bar.md (finished) renamed away.
#   (c) re-blocked loop: tool_loop-exception.md carves the accepted-info
#       exception so the loop terminates; tool_missing-license-finding.md
#       adds its finding at SEV_WARN, which re-blocks it with no handling.
#   (d) short sweep: tool_check-docstring-sweep.md states a rule over every
#       check module and enumerates 2 of the 5 that exist.
#   (e) opposite postures: tool_path-check-severity.md and
#       tool_glob-check-severity.md add the SAME new finding class (a duplicate
#       declaration) to sibling check modules, one at SEV_WARN and one at
#       SEV_INFO, with no reason recorded on either.
#   (f) underdetermined fork: tool_config-format.md leaves TOML vs JSON open with
#       nothing in the tree settling it, and tool_severity-registry.md's lookup
#       helper has to consume that format, so the fork blocks two selected tasks.
#       As a fork inside ONE task it was correctly dismissed as a per-task
#       readiness matter; the joint read only owns it once a sibling depends on
#       the unsettled choice.
#   (g) clean: tool_exit-code-doc.md has no cross-task or premise defect.
#   (h) invalidated premise: tool_json-output.md claims there is no JSON
#       output mode; tool/report_json.py exists and cli.py wires it.
#   (i) Goal-altering repair: tool_drop-legacy-module.md wants tool/legacy.py
#       gone with nothing importing it, while archive/tool_keep-compat-shim.md
#       (finished) settled that the shim stays until external callers migrate.
#       That decision is closed and its owners are outside this repo, so no live
#       task can absorb the edit and the only repair narrows (i)'s own Goal to
#       deprecate-then-remove. An earlier version leaned on a LIVE sibling
#       instead, and the assessment simply altered the sibling — the correct call
#       for a movable counterpart, and the reason this plant needs an immovable
#       one.
#   (j) hard ordering pair: tool_severity-registry.md creates
#       SEVERITY_REGISTRY; tool_register-path-check.md forward-references it.
#   (k) ready + additive note only: tool_summary-line.md.
#   (l) Acceptance-altering repair: tool_quiet-flag.md, whose Acceptance rests on
#       the clean bar counting every tier — which the accepted-info exception in
#       tool_loop-exception.md changes.
#
# Severity tiers are named in Approach and Acceptance, never in a ## Goal, for
# (c) and the (e) pair. Their repair shapes can change the tier or record the
# reason for keeping it, and a Goal naming the tier would force any tier change
# to alter a frozen Goal — turning a repairable alter finding into the
# Goal-altering class (i) plants deliberately.
#
# Four plants had to be re-scoped after measured runs. Keep the reasons: each
# one is a way a coherence fixture can look right on paper and plant nothing.
#   * (e) first differed on WHICH defect each check reports (unresolved path
#     versus non-matching glob). A reasonable assessor read that as a principled
#     distinction — a broken path is always wrong, a non-matching glob often is
#     not — and returned ship-as-is. The second attempt said "empty declaration",
#     which the stubs' own `if not p` already implements, so both premises came
#     back invalidated. It is now a duplicate declaration: no stub detects it,
#     both premises hold, and the two sides differ on nothing but the tier.
#   * (i) was first a task collapsing the three severity tiers into one. It
#     contradicted ten siblings at once, so the assessment folded (c) and (e)
#     into that single design fork and marked them ship-as-is "in multi-tier
#     world". (i) now conflicts on its own surface — a legacy shim — and touches
#     one sibling, so the three findings no longer interfere.
#   * (c) took three passes. It first rested on SEV_WARN re-blocking the loop,
#     which tool_loop-exception says warn findings do BY DESIGN, so no
#     contradiction was derivable. The fixture then recorded that no module carries
#     a license header and no live task adds one, so the warn finding fires on
#     every module with nothing to fix it. That still planted nothing, because
#     reachable_clean_bar already ignored SEV_INFO: the exception task's premise
#     came back invalidated, and an exception that already exists cannot be
#     re-blocked. The bar now counts EVERY tier, so tool_loop-exception has real
#     work to do and (c)'s unfixable warn findings genuinely defeat it.
#   * (l) first contradicted itself: its Acceptance expected a quiet run to print
#     a SEV_INFO finding while its Approach printed only what the bar counts, and
#     the bar then counted no info finding. That is a within-task finding, not the
#     cross-task one (l) exists to plant. Its Acceptance now rests on the bar
#     counting info findings, which is exactly what the accepted-info exception
#     takes away.
#
# The lesson under three of these four: a coherence plant is only real when the
# CODE leaves the task something to do. Check every premise against the seeded
# artifacts before trusting the prose — an already-satisfied premise turns the
# intended cross-task finding into a defer candidate and silently unplants
# whatever depended on it.
#
# The backlog is seeded lint-clean and git-committed, so any post-run diff or
# lint finding is attributable to the run. The prompt asks for the assessment
# in coherence-report.md as well as in the response: grade.sh never sees the
# agent's response text, so writing the report into the sandbox is what makes
# the assess-phase verdicts deterministically gradeable. The content graded is
# exactly what task_fix's <output_contract> already mandates.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

# --- target artifacts (the shared set T the tasks point at) -------------------

mkdir -p "$proj/tool/checks" "$proj/docs"

cat > "$proj/tool/severity.py" <<'EOF'
"""Severity tiers and the autonomous loop's clean bar."""

SEV_BLOCK = "block"
SEV_WARN = "warn"
SEV_INFO = "info"


def severity_label(sev):
    """Return the display label for one severity value."""
    return {SEV_BLOCK: "blocking", SEV_WARN: "warn", SEV_INFO: "info"}[sev]


def reachable_clean_bar(findings):
    """Only an empty finding set clears the bar: every tier counts today."""
    return not findings
EOF

cat > "$proj/tool/report_json.py" <<'EOF'
"""JSON output mode for the checker."""

import json


def render(findings):
    return json.dumps({"findings": findings}, indent=2)
EOF

cat > "$proj/tool/legacy.py" <<'EOF'
"""Deprecated rendering shim kept for the current CLI output path."""


def render_compat(labels):
    return "\n".join(labels)
EOF

cat > "$proj/tool/cli.py" <<'EOF'
"""Command-line entry point."""

from tool import legacy, report_json
from tool.severity import reachable_clean_bar, severity_label


def main(argv, findings):
    if "--json" in argv:
        return report_json.render(findings)
    return legacy.render_compat([severity_label(f["sev"]) for f in findings])


def exit_code(findings):
    return 0 if reachable_clean_bar(findings) else 1
EOF

# Five check modules: path_check and glob_check carry a module docstring,
# license_check / docstring_check / encoding_check do not. The sweep task's
# rule implies all five sites and enumerates only the first two.
cat > "$proj/tool/checks/path_check.py" <<'EOF'
"""Check that every declared path resolves."""


def run(paths):
    return [{"sev": "warn", "msg": p} for p in paths if not p]
EOF

cat > "$proj/tool/checks/glob_check.py" <<'EOF'
"""Check that every declared glob matches at least one file."""


def run(globs):
    return [{"sev": "info", "msg": g} for g in globs if not g]
EOF

cat > "$proj/tool/checks/license_check.py" <<'EOF'
def run(files):
    return [{"sev": "info", "msg": f} for f in files if not f]
EOF

cat > "$proj/tool/checks/docstring_check.py" <<'EOF'
def run(modules):
    return [{"sev": "info", "msg": m} for m in modules if not m]
EOF

cat > "$proj/tool/checks/encoding_check.py" <<'EOF'
def run(files):
    return [{"sev": "info", "msg": f} for f in files if not f]
EOF

cat > "$proj/docs/exit-codes.md" <<'EOF'
# Exit codes

| Code | Meaning |
| --- | --- |
| 0 | the clean bar is met |
| 1 | at least one finding blocks |
EOF

# --- the archived finished sibling that invalidates (b)'s anchor -------------

cat > "$proj/tasks/archive/tool_rename-clean-bar.md" <<EOF
---
description: Rename the clean-bar helper so its name states the reachable bar it checks.
scope: tool
created: $now
updated: $now
status: finished
reported-by: Test User
implemented-by: Test User
---

# Rename the clean-bar helper

## Goal

The clean-bar helper in tool/severity.py is named for the bar it reaches, so a
reader stops inferring that the bar is unreachable by design.

## Context

The helper was called \`unreachable_clean_bar\`, which described a defect rather
than the check.

## Approach

Rename it to \`reachable_clean_bar\` and update every caller.

## Acceptance

- \`rg 'unreachable_clean_bar' tool/\` returns no match.
- \`rg 'reachable_clean_bar' tool/cli.py\` matches.
EOF

cat > "$proj/tasks/archive/tool_keep-compat-shim.md" <<EOF
---
description: Keep render_compat as the compatibility shim until the external callers pinned to the pre-1.0 output format migrate.
scope: tool
created: $now
updated: $now
status: finished
reported-by: Test User
implemented-by: Test User
---

# Keep the compatibility shim until external callers migrate

## Goal

tool/legacy.py stays in place and the CLI keeps rendering through
\`render_compat\`, so the external callers pinned to the pre-1.0 output format
keep working until they migrate.

## Context

Those callers live outside this repository and their migration is tracked
outside this backlog, so nothing here can retire the shim on their behalf.

## Approach

Keep \`render_compat\` and the CLI call to it, and deprecate rather than delete
the module while the pinned callers remain.

## Acceptance

- tool/legacy.py exists and tool/cli.py renders non-JSON runs through it.
EOF

# --- (a) the double-owned edit, plus the task that assumes one owner --------

cat > "$proj/tasks/tool_severity-label-rename.md" <<EOF
---
description: Rename severity_label to display_label so the helper reads as the display-string producer it is.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Rename severity_label to display_label

## Goal

The severity display helper in tool/severity.py is named \`display_label\`, and
every caller uses the new name.

## Context

[tool/severity.py](../tool/severity.py) defines \`severity_label\`, and
[tool/cli.py](../tool/cli.py) imports it.

## Approach

Rewrite the \`def severity_label(\` definition in tool/severity.py to
\`def display_label(\` and re-point the import and call site in tool/cli.py.

## Acceptance

- \`rg 'def display_label' tool/severity.py\` matches.
- \`rg 'severity_label' tool/\` returns no match.
EOF

cat > "$proj/tasks/tool_severity-label-docstring.md" <<EOF
---
description: Rewrite the severity_label docstring so it names the three tiers it maps and the KeyError it raises.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Document the severity label mapping

## Goal

The severity display helper in tool/severity.py carries a docstring that names
the three tiers it maps and the KeyError an unknown tier raises.

## Context

[tool/severity.py](../tool/severity.py) currently documents the helper in one
line that names neither the tier set nor the failure mode.

## Approach

Rewrite the \`def severity_label(\` definition's docstring in place, keeping the
signature and the mapping body as they are.

## Acceptance

- The docstring under \`def severity_label(\` names SEV_BLOCK, SEV_WARN, and
  SEV_INFO.
- The docstring states that an unknown tier raises KeyError.
EOF

cat > "$proj/tasks/tool_severity-label-consumer.md" <<EOF
---
description: Re-point the checks package onto the renamed display_label helper once the rename task has landed it.
scope: tool
created: $now
updated: $now
status: open
reported-by: Test User
---

# Re-point the check modules onto the renamed label helper

## Goal

Every module under tool/checks/ that formats a finding calls the renamed
display helper rather than reaching into the tier constants directly.

## Context

[tool_severity-label-rename.md](tool_severity-label-rename.md) owns the rename
itself, so this task only updates the consumers after that lands.

## Approach

Import the renamed helper in each check module that formats a finding and
replace the inline tier string with a call to it.

## Acceptance

- \`rg 'display_label' tool/checks/\` matches in every module that formats a
  finding.
EOF

# --- (b) the task whose quoted anchor the archived sibling invalidated -------

cat > "$proj/tasks/tool_clean-bar-note.md" <<EOF
---
description: Add a design note to the docs stating which findings the clean-bar helper counts against the bar.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Document what the clean bar counts

## Goal

The docs state which severity tiers the clean-bar helper counts, so a reader
knows what an autonomous loop has to reach before it can stop.

## Context

The helper is \`unreachable_clean_bar\` in [tool/severity.py](../tool/severity.py),
and it counts every finding against the bar whatever its tier.

## Approach

Add a short section to docs/exit-codes.md quoting the \`unreachable_clean_bar\`
predicate and naming the tiers it counts.

## Acceptance

- docs/exit-codes.md names the tiers the clean-bar predicate counts.
EOF

# --- (c) the exception, and the finding whose severity re-blocks it ----------

cat > "$proj/tasks/tool_loop-exception.md" <<EOF
---
description: Suppress accepted info findings from the clean bar so an autonomous repair loop can terminate cleanly.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Let the clean bar ignore accepted info findings

## Goal

An autonomous repair loop reaches the clean bar on a tree whose only remaining
findings are accepted info-tier ones, so the loop terminates instead of
circling on findings nobody intends to fix.

## Context

The clean-bar predicate in [tool/severity.py](../tool/severity.py) counts every
finding whatever its tier, so any finding at all keeps the bar unreached until it
is repaired. The bar has to stay reachable for the loop to terminate at all: one
finding nobody intends to fix, sitting at a tier the bar counts, keeps the loop
circling forever.

## Approach

Add an accepted-finding set to the clean-bar predicate and skip a SEV_INFO
finding that appears in it, leaving SEV_BLOCK and SEV_WARN counted.

## Acceptance

- The clean-bar predicate clears on a finding set holding only accepted
  SEV_INFO findings.
- A SEV_WARN finding still keeps the bar unreached.
EOF

cat > "$proj/tasks/tool_missing-license-finding.md" <<EOF
---
description: Report a missing license header from the license check at warn severity so the gap shows up in every run.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Report a missing license header

## Goal

A source file with no license header produces a finding, so the gap shows up
in a run rather than passing silently.

## Context

[tool/checks/license_check.py](../tool/checks/license_check.py) currently emits
its findings at SEV_INFO. No module under tool/ carries a license header today,
and no live task adds one, so the finding fires on every module in the package.

## Approach

Rewrite the license check's emitted severity from SEV_INFO to SEV_WARN and
extend it to flag a file whose first line carries no license marker.

## Acceptance

- The license check emits SEV_WARN for a file with no license marker.
- \`rg 'SEV_INFO' tool/checks/license_check.py\` returns no match.
EOF

# --- (d) the task whose sweep enumerates a subset of its own rule's sites ----

cat > "$proj/tasks/tool_check-docstring-sweep.md" <<EOF
---
description: Give every check module a module docstring naming what it checks, and enforce that with the docstring check.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Give every check module a docstring

## Goal

Every module under tool/checks/ opens with a module docstring naming what it
checks, and the docstring check enforces that rule for the package.

## Context

The rule covers the whole [tool/checks/](../tool/checks) package.

## Approach

Add the missing module docstring to each check module the rule covers:

- tool/checks/path_check.py
- tool/checks/glob_check.py

Then extend the docstring check to fail a module under tool/checks/ with no
module docstring.

## Acceptance

- Every module under tool/checks/ opens with a module docstring.
- The docstring check fails a check module with no module docstring.
EOF

# --- (e) two siblings answering one severity question oppositely ------------

cat > "$proj/tasks/tool_path-check-severity.md" <<EOF
---
description: Emit a duplicate-path-declaration finding at warn severity so the same entry declared twice is reported.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Report a duplicate path declaration

## Goal

The path check reports a duplicate declaration as a finding of its own, so the
same entry declared twice is not silently accepted.

## Context

[tool/checks/path_check.py](../tool/checks/path_check.py) inspects each
declaration on its own and detects no duplication across them.

## Approach

Emit the duplicate-declaration finding from the path check at SEV_WARN.

## Acceptance

- The path check emits SEV_WARN for a declaration that appears twice.
EOF

cat > "$proj/tasks/tool_glob-check-severity.md" <<EOF
---
description: Emit a duplicate-glob-declaration finding at info severity so the same entry declared twice is reported.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Report a duplicate glob declaration

## Goal

The glob check reports a duplicate declaration as a finding of its own, so the
same entry declared twice is not silently accepted.

## Context

[tool/checks/glob_check.py](../tool/checks/glob_check.py) inspects each
declaration on its own and detects no duplication across them.

## Approach

Emit the duplicate-declaration finding from the glob check at SEV_INFO.

## Acceptance

- The glob check emits SEV_INFO for a declaration that appears twice.
EOF

# --- (f) the genuinely underdetermined fork ---------------------------------

cat > "$proj/tasks/tool_config-format.md" <<EOF
---
description: Read per-project severity overrides from a config file the checker discovers at the project root.
scope: tool
created: $now
updated: $now
status: open
reported-by: Test User
---

# Read severity overrides from a config file

## Goal

The checker reads per-project severity overrides from a config file it
discovers at the project root, so a project can lower one finding's tier
without patching the checker.

## Context

No config file exists in the tree yet, and no check reads one.

## Approach

Discover the config file at the project root, parse it, and apply each
override to the emitted severity. The file format is left open between TOML
and JSON.

## Acceptance

- A project-root config file lowering one finding's tier changes that
  finding's emitted severity.
- A project with no config file behaves as it does today.
EOF

# --- (g) the clean task ----------------------------------------------------

cat > "$proj/tasks/docs_exit-code-table.md" <<EOF
---
description: Add the reserved exit code for a checker crash to the exit-code table so callers can tell a crash from a finding.
scope: docs
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Document the crash exit code

## Goal

The exit-code table names the reserved code a checker crash returns, so a
caller can tell a crash apart from a run that found something.

## Context

[docs/exit-codes.md](../docs/exit-codes.md) documents codes 0 and 1 and stops
there.

## Approach

Add one row to the table in docs/exit-codes.md for the reserved crash code and
state that it is never returned for a finding.

## Acceptance

- The table in docs/exit-codes.md carries a third row for the crash code.
- The table states that the crash code is never returned for a finding.
EOF

# --- (h) the task whose premise the target artifacts invalidate -------------

cat > "$proj/tasks/tool_json-output.md" <<EOF
---
description: Add a JSON output mode to the checker so a caller can consume findings without parsing the human-readable lines.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Add a JSON output mode

## Goal

The checker can emit its findings as JSON, so a caller consumes them without
parsing the human-readable output.

## Context

The checker has no JSON output mode: [tool/cli.py](../tool/cli.py) renders
findings only as display labels, and no renderer produces machine-readable
output.

## Approach

Add a JSON renderer beside the CLI and wire a flag that selects it.

## Acceptance

- A run with the JSON flag prints a parseable JSON object of findings.
- A run without the flag prints the display lines unchanged.
EOF

# --- (i) the task whose fitting repair would alter its own Goal -------------

cat > "$proj/tasks/tool_drop-legacy-module.md" <<EOF
---
description: Delete the deprecated rendering shim tool/legacy.py so no module imports it and the CLI renders directly.
scope: tool
created: $now
updated: $now
status: open
reported-by: Test User
---

# Delete the deprecated rendering shim

## Goal

tool/legacy.py is gone and no module imports it, so the CLI renders its output
directly instead of routing through a deprecated shim.

## Context

[tool/legacy.py](../tool/legacy.py) exposes \`render_compat\`, and
[tool/cli.py](../tool/cli.py) still renders every non-JSON run through it. The
shim was kept deliberately by
[tool_keep-compat-shim.md](archive/tool_keep-compat-shim.md).

## Approach

Inline the shim's join into tool/cli.py, drop the \`legacy\` import, and delete
tool/legacy.py.

## Acceptance

- tool/legacy.py does not exist.
- \`rg 'legacy' tool/\` returns no match.
EOF

# --- (j) the hard ordering pair --------------------------------------------

cat > "$proj/tasks/tool_severity-registry.md" <<EOF
---
description: Add a severity registry to tool/severity.py so each check declares its emitted tier in one place.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Add a severity registry

## Goal

tool/severity.py carries a \`SEVERITY_REGISTRY\` mapping so each check declares
its emitted tier in one place instead of hard-coding it at the emit site.

## Context

[tool/severity.py](../tool/severity.py) defines the tier constants and nothing
that records which check emits which tier. The lookup helper also has to read the
per-project overrides that [tool_config-format.md](tool_config-format.md)
introduces, so its call shape depends on the file format that task leaves open.

## Approach

Add a \`SEVERITY_REGISTRY\` dict to tool/severity.py keyed by check name, plus a
lookup helper the checks call at emit time.

## Acceptance

- \`rg 'SEVERITY_REGISTRY' tool/severity.py\` matches.
- The lookup helper returns the registered tier for a registered check.
EOF

cat > "$proj/tasks/tool_register-path-check.md" <<EOF
---
description: Register the path check in the severity registry so its emitted tier is declared rather than hard-coded.
scope: tool
created: $now
updated: $now
status: open
reported-by: Test User
---

# Register the path check in the severity registry

## Goal

The path check declares its emitted tier through \`SEVERITY_REGISTRY\` rather
than hard-coding it at the emit site.

## Context

The registry itself is created by
[tool_severity-registry.md](tool_severity-registry.md); this task consumes it.

## Approach

Add the path check's entry to \`SEVERITY_REGISTRY\` and replace the hard-coded
tier in tool/checks/path_check.py with the registry lookup.

## Acceptance

- \`SEVERITY_REGISTRY\` carries an entry for the path check.
- tool/checks/path_check.py reads its tier from the registry lookup.
EOF

# --- (k) the ready task eligible for an additive out-of-scope note only -----

cat > "$proj/tasks/tool_summary-line.md" <<EOF
---
description: Print a one-line run summary counting findings per tier so a reader sees the shape of a run at a glance.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Print a run summary line

## Goal

A run closes with one summary line counting the findings it produced per tier,
so a reader sees the shape of the run without counting the lines above it.

## Context

[tool/cli.py](../tool/cli.py) prints one line per finding and nothing after
them.

## Approach

Append a summary line to the CLI's rendered output, counting the findings per
tier in the order the tiers are declared.

## Acceptance

- A run with findings closes with a summary line naming a count per tier.
- A run with no findings closes with a summary line naming zero counts.
EOF

# --- (l) the task whose accepted repair alters Acceptance semantics ---------

cat > "$proj/tasks/tool_quiet-flag.md" <<EOF
---
description: Add a quiet flag that prints nothing on a clean run and only the blocking findings otherwise.
scope: tool
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Add a quiet flag

## Goal

A quiet run prints as little as the caller can act on: nothing at all when the
clean bar is met, and only the findings that keep it unreached otherwise.

## Context

[tool/cli.py](../tool/cli.py) always renders every finding, with no way to
narrow the output.

## Approach

Add a quiet flag to the CLI that suppresses rendering when the clean-bar
predicate clears, and otherwise renders only the findings the bar counts.

## Acceptance

- A quiet run over a finding set whose only entries are SEV_INFO prints those
  findings, since the clean bar counts every tier.
- A quiet run over a finding set that clears the bar prints nothing.
EOF

git_commit_all "$proj" "seed: jointly incoherent backlog plus its target artifacts"

echo "fix_coherence sandbox staged at $proj"
