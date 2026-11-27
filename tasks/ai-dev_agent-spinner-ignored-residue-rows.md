---
description: "Stop the agent_spinner ledger from turning gitignored residue into per-file check rows, so a run over a repository with large ignored trees stays small and usable."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-27T09:00:44Z
updated: 2026-11-27T19:08:15Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Keep gitignored residue out of the agent_spinner ledger's check rows

## Goal

A run opened over a repository with a large gitignored tree stays usable. `diff --add-checks` records new ignored residue in one aggregate record instead of creating one `check:` row per ignored file, so the roster stays proportional to the artifacts the ask named and `status` stays readable.

## Context

- `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py` adds a `new-ignored-residue` change for every newly ignored path and then `--add-checks` creates a `check:<slug>` row for every change. A large test-output or review-evidence tree therefore becomes work the run never intended to do.
- The observed failure: a run over this repository recorded 18,925 rows, of which 18,911 were `new-ignored-residue`, 16,794 under `tests/`, 1,038 under a task-check relay, and 953 under a review-evidence tree. It accepted 0, wrote an 8 MB `run.json` and a 7.9 MB `roster.tsv`, and `status` printed 18,925 lines.
- Ignored residue is real evidence of what changed, so the fix keeps it visible in the diff record and the report; it stops treating each ignored file as an independent artifact to check, and it keeps the exact total while naming only the first 50 paths, so the trimming narrows the listing without losing the count.
- The repository already keeps its own run output under ignored paths, so the regression fixture is cheap: a staged repository with a large ignored tree.

## Approach

1. In `cmd_diff`, keep the `new-ignored-residue` flag for reporting, but stop emitting one change per ignored path. Emit one aggregate change whose path is the angle-bracket metadata form `<ignored-residue>`, like the existing `<HEAD>` and `<stash>` entries. That change carries the exact count as an integer `ignored_total` field and a `diff` key naming `diffs/ignored-residue.diff`, written through the same `led.path("diffs", ...)` helper `make_change` uses, so the path list never lands inline in the `indent=2` `run.json` body. The diff file opens with a cap line naming the cap of 50 paths, the exact total, and the number trimmed, in the form `references/report-shapes.md` gives its payload cap, then lists the first 50 ignored paths. The angle-bracket path keeps the change out of condition 3's per-path check and out of the `--add-checks` loop while the diff record still reports it.
2. In the `--add-checks` loop, create no `check:` row for the aggregate residue change. The residue stays visible through `diff` and the report, and it never becomes a dispatchable row.
3. Keep the existing `under_run_dir` exclusion and the `git_ignored` selection unchanged, so a path the run itself writes is still ignored.
4. Add one `ledger_run.sh` scenario that stages a repository with an ignored tree of many files, opens a run, changes one tracked artifact, and runs `diff --add-checks`. Assert that the roster holds no `check:` row for an ignored file, that the residue count appears in the diff record, and that `status` output stays bounded. Register each new `scenario_*` function by name in `run_all_scenarios` in the same file, which calls every scenario explicitly and discovers none, passing it its own scratch subdirectory under `$root`.
5. Document the residue rule inside the existing `### diff` section of `references/run-protocol.md`: add one bullet beside the `--add-checks` bullet that states the aggregate `<ignored-residue>` form and the no-row rule and names `new-ignored-residue` so the flag stays greppable. The skill's prose carries no residue passage today, so this bullet is a genuine addition placed in that section, not a rewrite of existing text.

**Out of scope:** changing how tracked-file changes are enumerated; that path already produces one row per artifact and stays as it is.

## Acceptance

- The new `ledger_run.sh` scenario stages an ignored tree of at least 1,000 files and one tracked change. After `diff --add-checks`, `roster.tsv` contains no `check:` row whose path is an ignored file, the diff record names the residue count, and `status` prints fewer than 100 open-row lines.
- In that same scenario, the `<ignored-residue>` change entry carries an integer `ignored_total` equal to the exact number of staged ignored files and a `diff` key naming `diffs/ignored-residue.diff`; that file states the same total on its cap line, lists exactly 50 ignored paths, and names the remaining count as trimmed; and `run.json` stays under 1 MB.
- A second scenario stages the same tree with no tracked change and confirms the run records the residue aggregate without adding a row.
- The `run_all_scenarios` body in `tests/agent_spinner/script_tests/ledger_run.sh` names the new residue scenarios, so a suite run executes them rather than only defining them.
- `rg -n "new-ignored-residue" plugins/ai_dev/skills/agent_spinner/references/run-protocol.md` finds text that states the aggregate form and the no-row rule.
- `bash tests/agent_spinner/script_tests/ledger_run.sh` passes, including every pre-existing scenario.
