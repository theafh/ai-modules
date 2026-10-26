# task_auto_check quick reference

## Deterministic checks

```bash
./tests/task_auto_check/run_all.sh
```

This runs `script_tests/run.sh`, which reads the published skill,
agents, READMEs, and marketplace metadata in the host repo. It performs
no LLM calls and does not modify the source tree.

## Behavioral evals

The eval definitions and fixtures are under `evals/`. They cover the
model-mediated behavior that static checks cannot prove:

- Already-ready task: stops after one gate call and applies no edits.
- Already-ready lint-dirty task: runs final mechanical lint cleanup
  before reporting; the gate may stamp ready or checked when the lint
  nit doubles as a gate-visible finding.
- Freeze-time intent drift: surfaces a human intention check before
  any gate call or repair and leaves the current task unchanged.
- Not-ready task: proposes and verifies minimum repairs, applies them,
  re-runs `task_check`, and stops at `ready`.
- Relay by path: a one-round repair reaches ready while every helper
  hand-off travels through a retained `.task_auto_check/<stem>/` relay
  directory; proposal-mode verifier prompts point at gate and reviewer
  returns without copying or steering their content.
- Stray hunk reverted: the first apply plants a Context rewrite; the
  delta audit marks that planted hunk unmapped, the loop restores and
  re-applies, and a later clean delta is required before the next gate.
- Frozen commitments: missing acceptance proof cannot be repaired by silently
  deleting or narrowing the rule; the retained verifier decisions show an
  added proof or a human route.
- Last-call ready: a two-round run reaches ready on the second gate and
  challenges its citations; any refutation returns to the gate without
  another body repair.
- Isolated re-gate: an earlier-run decoy verdict remains outside the gate's
  admitted inputs and cannot hide the missing preservation proof.
- Scope/focus/complexity issue: surfaces a split as stuck instead of
  creating files.
- Fidelity guard: rejects or narrows a proposal that changes the
  original objective.
- No verified fix: stops as `checked`.
- Cap override: honors a user-supplied max-round bound.
- Gate helper failure: stops with a clear helper-failure error, lists
  options, and asks the user. No inline gate, no self-computed
  readiness verdict, and the task file stays untouched.
- Drift helper failure: stops at freeze time with the same user-facing
  error instead of proceeding or improvising a drift verdict.
- Verifier failure: stops with the error and asks the user; zero edits
  applied, nothing bypasses verification.
- Guard re-baseline: adopts the gate's own status/`updated` stamp as
  the post-gate baseline; no false concurrent-modification stop.
- Immediate-ready citations survive: a first-call zero-issue `ready`
  fires the refutation trigger, every citation survives, the stamp
  stands with zero body edits.
- Immediate-ready citations overturn: a historical false-approval
  snapshot with five planted gaps; run it **three times sequentially**
  (repair-class discipline) with `--no-cache` so each run is a fresh
  draw, and record per run into `results/` whether a first-call
  zero-issue verdict occurred, whether its citations were refuted, and
  whether the run reached `ready`. A `ready` from an unchallenged
  first-call zero-issue verdict is a trigger-condition defect.
- Dry-run gap confirmed: every ordinary repair round runs the pre-gate
  implementer dry run on an instruction-prose fixture whose task plants a
  rule conflict with an existing rule it never mentions; the dry run must
  find the conflict, the gate must confirm it with its issue number, and
  the repair must resolve it in the final task text.

```bash
python3 tests/task_auto_check/evals/run.py
python3 tests/task_auto_check/evals/run.py repair_to_ready
```

The runner writes `response.txt`, `stderr.txt`, `timing.json`, and
`grading.txt` under `tests/task_auto_check/workspace/run-*/<eval-id>/`.
Treat `grading.txt` as the programmatic filesystem verdict and inspect
`response.txt` for the `agent-attest` transcript expectations listed by
the grader.

Two operational caveats. The isolation check compares the live `tasks/`
tree to an isolated copy taken in the eval temp dir, and only for basenames
the sandbox contains, so a concurrent session editing some other real task
does not trip it. A fixture name that lands in the live tree is a sandbox
escape. The repair-class scenarios (`repair_to_ready`,
`relay_by_path`, `stray_hunk_reverted`,
`guard_rebaseline_after_gate`, `interaction_scan_surfaces`,
`immediate_ready_citations_overturn`) run the full
nested-agent loop and take ~576 to 2005s solo on Cursor (2026-10-13
re-measure; see the timing-band note below); the harness default
`--timeout` is 2305. A `worker rc=-1` in
`timing.json` means the worker was cut off mid-run: its grade reflects an
unfinished sandbox and is inconclusive, never a behavioral pass or fail
(though the partial state can still show whether an intended edit landed).

## Cost discipline

These behavioral evals are the most expensive surface in the repo. The
standing coverage rule in `TESTING.md` `## Coverage Expectations` (and the
matching bullets in the repo-root `AGENTS.md` / `CLAUDE.md`) treats them as
opt-in proof, not as a default ship gate: after an ordinary
`task_auto_check` change, run `script_tests/run.sh` (and any Acceptance-named
eval); do not open a full-suite re-run, fixture-retune loop, or
timeout-ceiling campaign inside the task. A full suite is an optional
operator measurement pass. An incomplete eval (timeout, empty response, kill)
is inconclusive per the worker-completion gate above, not a fail to chase
inside the change.

When a named behavioral eval *does* run, three habits cut iteration cost:

- **Validate a fixture with a single `task_check` gate before running the
  full loop.** Stage the fixture (`evals/stage.sh <id> <dir>`), then run
  `task_check` alone against the staged task: a `claude -p` that reads
  `plugins/ai_dev/skills/task_check/SKILL.md` and reports its verdict plus
  issue list, ~1 to 3 min. This reveals whether the fixture lands on the
  intended verdict and what side-findings it carries, so a fixture-design
  bug (an unintended second readiness gap, an inaccurate premise) surfaces
  in minutes rather than via a 10 to 33 min repair-loop timeout. Run the full
  loop only once the gate verdict matches what the eval expects.
- **Run the serial nested-loop set one eval at a time.** That set is
  `repair_to_ready`, `relay_by_path`, `stray_hunk_reverted`,
  `guard_rebaseline_after_gate`, `interaction_scan_surfaces`,
  `immediate_ready_citations_overturn`, `regroup_via_reviewer`,
  `regroup_immediate_ready`, `regroup_same_paragraph_ready`,
  `committed_rule_deletion_routed`, `last_call_ready_refuted`,
  `regate_isolated`, and `dryrun_gap_confirmed`. Those jobs do not overlap one another: two of them
  at once contend for the model and both slow past even a 2305s timeout,
  while solo each finishes in ~576 to 2005s. The rest of the suite uses
  the default 4 workers. Launch one `run.py` invocation at a time.
- **Reuse a prior PASS under Re-run Economy.** When the graded record
  postdates every artefact under test, treat it as evidence; re-run that
  eval only when the skill, agent, gate, fixture, grader, or runner changed
  since that record.

When authoring a `grade.sh` check for an edit-supersedes behavior, assert
that the stale content is **gone** (or that the superseding concept is
named), not that a specific token appears: an incidental token, e.g. the
`100` inside `list(range(100))`, false-passes a loose check, while
demanding a literal keyword false-fails a valid supersession that simply
lowered a value.

## Per-eval timeouts, and which evals need them

`evals/run.py` takes a per-eval `"timeout"` from `evals.json`, falling back to
its `--timeout` default. These evals declare their own budget to cover deeper
repair paths and additional verifier or gate calls:

| Eval | Budget | Why |
| --- | --- | --- |
| `mechanical_lint_ready` | 3600s | Pre-gate dry run on an already-ready task plus mechanical description cleanup; raised from the 2305s default after the dry-run rollout hit that ceiling. |
| `mechanical_lint_markdown` | 3600s | Same dry-run-per-round overhead on a mechanical-lint path; raised from the 2305s default after a dry-run rollout timeout. |
| `mechanical_lint_oversized_surface` | 3600s | Same dry-run-per-round overhead on a large mechanical-lint surface; raised from the 2305s default after a dry-run rollout timeout. |
| `drift_gate_narrowing_clean` | 3600s | Drift check plus gate with a dry run each ordinary round; raised from the 2305s default after a dry-run rollout timeout. |
| `repair_to_ready` | 3600s | Full nested repair loop with a dry run before every gate; raised from the 2305s default for dry-run wall-clock headroom. |
| `relay_by_path` | 3600s | Full nested repair loop with relay grading and a dry run each round; raised from the 2305s default for dry-run wall-clock headroom. |
| `stray_hunk_reverted` | 3600s | Fault-injected apply plus corrected delta under a dry run each round; raised from the 2305s default after a dry-run rollout timeout. |
| `fidelity_rejects_drift` | 3600s | Fidelity-checked repair under a dry run each round; raised from the 2305s default after a dry-run rollout timeout. |
| `guard_rebaseline_after_gate` | 3600s | Post-gate re-baseline under a dry run each round; raised from the 2305s default after a dry-run rollout timeout. |
| `interaction_scan_surfaces` | 3600s | Interaction-scan repair under a dry run each round; raised from the 2305s default after a dry-run rollout timeout. |
| `immediate_ready_citations_survive` | 3600s | Immediate-ready citation path with a pre-gate dry run; raised from the 2305s default for dry-run wall-clock headroom. |
| `interaction_scan_no_false_alarm` | 3600s | No-false-alarm ready path with a pre-gate dry run; raised from the 2305s default for dry-run wall-clock headroom. |
| `regroup_via_reviewer` | 3600s | Full repair path: the target carries both a gate-visible Acceptance gap and a `repeated-link` finding, so the reviewer fires several stances before one verifier pass and one apply. |
| `regroup_immediate_ready` | 2700s | Ready verdict plus the repeated-link repair round the `<gate>` rule routes before finalization. |
| `regroup_same_paragraph_ready` | 2700s | The ready-verdict path on a target staged at `ready`, so no citation refutation runs. Both links sit inside one Context paragraph, so the repair round applies the react protocol's one-paragraph case, the verifier must approve it, and the edit keeps `ready` with no gate call after the round. |
| `immediate_ready_citations_overturn` | 3600s | Citation refutation returns to the gate for a second full verdict over the largest fixture in the harness. |
| `committed_rule_deletion_routed` | 3600s | Two unproven promises select several reviewer calls before proposal verification, application, delta audit, and re-gate. |
| `last_call_ready_refuted` | 3600s | A full repair round and second gate are followed by citation verification and, when refuted, one further gate assessment. |
| `regate_isolated` | 3600s | The repair and re-gate exercise the read boundary, including time for its one replacement when an assessment reports an isolation failure. |
| `dryrun_gap_confirmed` | 3600s | A pre-gate dry run and gate confirmation in every round, plus the repair round and re-gate that resolve the planted rule conflict in the final task text. |

A timed-out worker fails its eval whatever `grade.sh` says, because the sandbox
holds partial state. Read `timing.json` before raising a budget: a run killed
at its ceiling with the file already edited was close to finishing, while one
that never touched the file is stuck somewhere else.

## Timing-band re-measurement (2026-10-13)

Cursor vendor (`agent -p` / `auto`), solo sequential `--force`. Measurement
ceilings were raised to 3600s so no draw was cut off. Completing `duration_s`
with `worker_rc` 0:

| Eval | Completing `duration_s` (vendor) |
| --- | --- |
| `repair_to_ready` | 860.2, 774.6 (Cursor) |
| `relay_by_path` | 1178.1, 575.7 (Cursor) |
| `stray_hunk_reverted` | 699.4, 685.1 (Cursor) |
| `guard_rebaseline_after_gate` | 1417.4, 1045.2 (Cursor) |
| `interaction_scan_surfaces` | 1671.9, 2005.0 (Cursor) |
| `immediate_ready_citations_overturn` | 1062.1, 1057.2 (Cursor) |

Band lower end 576s, upper end 2005s. Harness default `--timeout` is
upper + 300 = **2305**. Full campaign notes: `results/timeout_band_measure.md`.

## Sandbox escape observed 2026-09-18, and the guard added for it

During the repeated-link regroup-owners sweep a worker ran a close-out
against the **real** repository: it moved a live task into `tasks/archive/`,
restamped it `finished`, re-pointed its links for the archive location, and
overwrote its `created` value. Nothing in the harness caught it, and the sweep
reported ordinary eval failures while real data sat corrupted.

The isolation check missed it because it probed the real tree for fixture
names only (`api_*.md` and one wiki filename). A worker that acts on a real
task it was never told about matches no fixture name.

`stage.sh` now copies the host `tasks/` tree into the eval temp directory.
`grade.sh` compares the live tree to that copy only for the sandbox's fixture
names. A parallel session that archives or creates some other real task stays
green. A fixture name that appears, moves, or changes in the live tree turns
the check red.

Treat a red on a fixture name as a stop-everything signal, not a flaky eval.
Restore that file before running anything else. An archive of a real task the
sandbox never named is outside this check, because that shape is also what a
parallel backlog session does.

## Two runner gaps that produce misleading verdicts

Both pre-date the per-eval timeouts and neither is fixed here. Recognise them
before treating a red as a regression.

- **A kill can overrun its own deadline.** `subprocess.run(timeout=...)` kills
  the worker but then drains its pipes, and the helper agents are grandchild
  processes holding those pipes open. One observed run reported 3330s against
  an 1800s ceiling.
- **A helper-failure stop grades as a completed run.** A worker that stops per
  `<agent_failure_policy>`, reports the failure and asks the user exits rc 0
  with real output, so `worker_completed()` passes it through and `grade.sh`
  scores an untouched fixture. The transcript ends in a question; the diff is
  empty. Check both before believing the failed checks.
