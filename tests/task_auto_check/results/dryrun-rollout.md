# Dry-run rollout record — task_auto_check evals on the pre-gate dry-run skill

Date: 2026-10-25. Vendor: Cursor (`agent -p`, model `auto`), serial set one eval
at a time, default verdict cache. Skill under test: `task_auto_check` 1.0.23
with `auto_dryrun_task` 1.0.0 wired before the gate of every ordinary repair
round and `auto_gate_task` 1.0.14 confirming dry-run findings.

## Re-run verdicts

| Eval | Verdict | Wall clock | Notes |
| --- | --- | --- | --- |
| dryrun_gap_confirmed (new) | see below | ~62 min | First run hit the round cap; fixture adjusted; see the adjustment log. |
| regate_isolated | see below | — | — |

(Verdicts are appended per eval as each serial run lands.)

## Fixture, grader, and timeout adjustments

- **dryrun_gap_confirmed fixture (Acceptance/Goal/description), 2026-10-25.**
  The first run of the new eval exercised the full wiring — every gate return
  had its same-round `r<N>-dryrun.txt`, the first dry run returned
  `kind: instruction prose` with a finding naming the planted newest-first vs
  oldest-first conflict, and the gate's `dryrun:` evidence line confirmed each
  finding with its issue number — but the loop consumed all five ordinary
  rounds without reaching `ready`: the staged Acceptance carried a
  preservation item that was already true today, which the dry run legitimately
  flagged, and each repair's rewording opened fresh acceptance-contract seams
  that the next round's dry run found (already-true bullet, stacked item,
  negation framing). Fixed by restaging one strong flippable Acceptance item —
  "exactly one ordering directive for the pinned entries section, and it
  directs oldest-first" — and framing Goal and description as "give the skill
  one ordering rule", so the fixture tests its own behavior (the find, the
  confirm, the repair, the ready) inside the peer-aligned 3600s budget. The
  planted conflict is unchanged: the task still appends a rule that directs the
  opposite of the skill's existing ordering rule for the pinned case and never
  mentions it. No grader or timeout change; the 3600s entry and RUNBOOK row
  stand as shipped.
- **dryrun_gap_confirmed first run, worker read-check failure (recorded, under
  investigation).** The first run also failed the harness read check with
  worker-side reads inside the repository checkout (`tests/task_auto_check`,
  its `evals/` directory, `evals.json`, the fixture `setup.sh`, a
  `**/_common.sh` glob, and `**/notes_pinned*` globs). The paths match the
  harness surfaces named by this repository's own live task file for this
  change, which `stage.sh`'s `snapshot_isolated_host_tasks` copies to
  `.isolated_host_tasks/` beside every sandbox; no absolute checkout path
  exists inside the sandbox itself. Recorded as a harness-isolation finding for
  the operator; the re-run below shows whether it recurs.

## Accepted-failure watch

None yet.
