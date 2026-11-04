---
description: Restore a green wiki layer-2 full-suite run by reconciling the path-suffix assertions and the artefact read-check with prefix-only sandbox roots and command transcripts.
scope: "local test harnesses"
created: 2026-11-04T20:13:17
updated: 2026-11-04T22:45:38
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Restore a green wiki layer-2 regression suite

## Goal

A full-suite `tests/wiki/layer2/run.py` run on the default vendor completes
with every scenario clean again, so a green run is a meaningful regression
signal. The path-suffix assertions and the artefact read-check both agree with
the harness's current prefix-only sandbox roots and command-transcript parsing.

## Context

The last full-suite run before the drift was green on 2026-10-03. Commit
`c0d177b` (2026-10-23, archived task
[tests_sandbox-root-hides-eval-id.md](tests_sandbox-root-hides-eval-id.md))
made every eval sandbox root harness-prefix-only, so a worker cannot read the
scenario id from its working directory. `tests/wiki/layer2/evals.json` still
carries 12 `report_field_endswith` assertions whose suffix embeds the scenario
id (for example `L2-1/HOME/proj/wiki`), so those scenarios fail on the actual
prefix-only path `.../wiki_layer2_<random>/HOME/proj/wiki`.

Three more scenarios (`AS-2`, `AS-4`, `AS-9`) fail
`artefacts_read_from_micro_deployment` because the worker transcript records
the literal path `.../.cursor/skills/wiki/$f`, an unexpanded loop variable read
from the wiki skill's `init_wiki.sh`. `classify_out_of_set` in
`tests/lib/micro_deploy.py` fails such a vendor-layout path closed by design,
so the check needs to distinguish a real out-of-set read from a script
fragment that carries a variable the command never assigns.

The full run `tests/wiki/layer2/workspace/run-20261104-183205` recorded 15
failing scenarios: the 12 path-suffix scenarios (`L2-1`, `L2-3` through
`L2-10`, `WI-1`, `WI-4`, `WU-1`) and `AS-2`, `AS-4`, `AS-9`.

## Approach

1. Scan `layer2/evals.json` for every `report_field_endswith` assertion whose
   suffix carries a scenario id and rewrite each suffix to the part of the
   path that survives the prefix-only root (for example `HOME/proj/wiki`,
   `HOME/wiki`), keeping the scenario-scoped grading as the subject anchor.
   Re-scan for any other assertion type that embeds the scenario id in a path
   suffix.
2. Investigate the `$f` false positive in `classify_out_of_set`. Distinguish a
   path the worker actually read from a shell fragment that carries a variable
   the command never assigns, and make the artefact check treat the fragment
   the way `classify_inside_checkout` already does (an unplaceable path stays
   unflagged), while keeping a genuine vendor-layout read outside the
   deployment failing closed. Add a unit case to the micro-deploy test module
   covering both directions.
3. Run the full suite on the default vendor and confirm every scenario is
   clean.

**Out of scope:**

- Changing `create_sandbox_root`'s prefix-only naming, which is the rule the
  archived task established.
- Adding new layer-2 scenarios or assertions beyond the suffix repair.
- Re-running the full suite on Claude unless a Claude-specific feature is
  under test.

## Acceptance

1. `python3 tests/wiki/layer2/run.py` on the default vendor exits 0 with all 37
   scenarios clean, and its compare reports no regressions against the prior
   full-suite baseline.
2. The 12 path-suffix scenarios and `AS-2`, `AS-4`, `AS-9` pass in that run,
   and a scan of `layer2/evals.json` finds no `report_field_endswith` suffix
   that starts with a scenario id.
3. The new micro-deploy unit case passes in `make test`, and it proves both
   the unflagged-fragment direction and the still-fails-closed genuine
   out-of-set direction.
4. `make lint` and `make test` pass.
