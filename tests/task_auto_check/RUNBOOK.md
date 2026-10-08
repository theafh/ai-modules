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
`guard_rebaseline_after_gate`, `interaction_scan_surfaces`,
`immediate_ready_citations_overturn`) run the full
nested-agent loop and take ~900 to 1500s solo, so pass `--timeout 1800` or
more, since the default 900 cuts many of them off. A `worker rc=-1` in
`timing.json` means the worker was cut off mid-run: its grade reflects an
unfinished sandbox and is inconclusive, never a behavioral pass or fail
(though the partial state can still show whether an intended edit landed).

## Cost discipline

These behavioral evals are the most expensive surface in the repo. Two
habits, learned from a session that burned hours re-running them, cut
the iteration cost sharply:

- **Validate a fixture with a single `task_check` gate before running the
  full loop.** Stage the fixture (`evals/stage.sh <id> <dir>`), then run
  `task_check` alone against the staged task: a `claude -p` that reads
  `plugins/ai_dev/skills/task_check/SKILL.md` and reports its verdict plus
  issue list, ~1 to 3 min. This reveals whether the fixture lands on the
  intended verdict and what side-findings it carries, so a fixture-design
  bug (an unintended second readiness gap, an inaccurate premise) surfaces
  in minutes rather than via a 15 to 25 min repair-loop timeout. Run the full
  loop only once the gate verdict matches what the eval expects.
- **Run repair-class evals sequentially, never concurrently.** Two deep
  nested-agent loops in parallel contend for the model and both slow past
  even an 1800s timeout; solo, each finishes in ~900 to 1500s. Launch one
  `run.py` invocation at a time.

When authoring a `grade.sh` check for an edit-supersedes behavior, assert
that the stale content is **gone** (or that the superseding concept is
named), not that a specific token appears: an incidental token, e.g. the
`100` inside `list(range(100))`, false-passes a loose check, while
demanding a literal keyword false-fails a valid supersession that simply
lowered a value.

## Per-eval timeouts, and which evals need them

`evals/run.py` takes a per-eval `"timeout"` from `evals.json`, falling back to
its `--timeout` default. Four evals declare their own budget because they run
materially longer than the ~700-1000s the loop normally takes:

| Eval | Budget | Why |
| --- | --- | --- |
| `regroup_via_reviewer` | 3600s | Full repair path: the target carries both a gate-visible Acceptance gap and a `repeated-link` finding, so the reviewer fires several stances before one verifier pass and one apply. |
| `regroup_immediate_ready` | 2700s | Ready verdict plus the repeated-link repair round the `<gate>` rule routes before finalization. |
| `regroup_same_paragraph_ready` | 2700s | The same ready-verdict path, with both links inside one Context paragraph, so the repair round applies the react protocol's one-paragraph case and the verifier must approve it. |
| `immediate_ready_citations_overturn` | 3600s | Citation refutation returns to the gate for a second full verdict over the largest fixture in the harness. |

A timed-out worker fails its eval whatever `grade.sh` says, because the sandbox
holds partial state. Read `timing.json` before raising a budget: a run killed
at its ceiling with the file already edited was close to finishing, while one
that never touched the file is stuck somewhere else.

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
