---
description: "Stop the agent_spinner ledger from turning gitignored residue into per-file check rows, so a run over a repository with large ignored trees stays small and usable."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-27T09:00:44Z
updated: 2026-11-27T09:00:44Z
status: open
reported-by: Andreas Hoffmann
---

# Keep gitignored residue out of the agent_spinner ledger's check rows

## Goal

A run opened over a repository with a large gitignored tree stays usable. `diff --add-checks` records new ignored residue in one aggregate record, or excludes it, instead of creating one `check:` row per ignored file, so the roster stays proportional to the artifacts the ask named and `status` stays readable.

## Context

- `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py` adds a `new-ignored-residue` change for every newly ignored path and then `--add-checks` creates a `check:<slug>` row for every change. A large test-output or review-evidence tree therefore becomes work the run never intended to do.
- The observed failure: a run over this repository recorded 18,925 rows, of which 18,911 were `new-ignored-residue`, 16,794 under `tests/`, 1,038 under a task-check relay, and 953 under a review-evidence tree. It accepted 0, wrote an 8 MB `run.json` and a 7.9 MB `roster.tsv`, and `status` printed 18,925 lines.
- Ignored residue is real evidence of what changed, so the fix keeps it visible in the diff record and the report; it stops treating each ignored file as an independent artifact to check.
- The repository already keeps its own run output under ignored paths, so the regression fixture is cheap: a staged repository with a large ignored tree.

## Approach

1. In `cmd_diff`, keep the `new-ignored-residue` flag for reporting, but stop emitting one change per ignored path. Emit one aggregate change whose path names the residue class (for example `ignored-residue`) and whose diff record carries the count and the paths, capped at a stated size.
2. In the `--add-checks` loop, create no `check:` row for the aggregate residue change. The residue stays visible through `diff` and the report, and it never becomes a dispatchable row.
3. Keep the existing `under_run_dir` exclusion and the `git_ignored` selection unchanged, so a path the run itself writes is still ignored.
4. Add one `ledger_run.sh` scenario that stages a repository with an ignored tree of many files, opens a run, changes one tracked artifact, and runs `diff --add-checks`. Assert that the roster holds no `check:` row for an ignored file, that the residue count appears in the diff record, and that `status` output stays bounded.
5. Rewrite the `new-ignored-residue` passage in `references/run-protocol.md` in place so it states the aggregate form and the no-row rule.

**Out of scope:** changing how tracked-file changes are enumerated; that path already produces one row per artifact and stays as it is.

## Acceptance

- The new `ledger_run.sh` scenario stages an ignored tree of at least 1,000 files and one tracked change. After `diff --add-checks`, `roster.tsv` contains no `check:` row whose path is an ignored file, the diff record names the residue count, and `status` prints fewer than 100 open-row lines.
- A second scenario stages the same tree with no tracked change and confirms the run records the residue aggregate without adding a row.
- `rg -n "new-ignored-residue" plugins/ai_dev/skills/agent_spinner/references/run-protocol.md` finds text that states the aggregate form and the no-row rule.
- `bash tests/agent_spinner/script_tests/ledger_run.sh` passes, including every pre-existing scenario.
