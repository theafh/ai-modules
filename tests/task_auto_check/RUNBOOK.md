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

Two operational caveats. The isolation check watches the real repo's
`tasks/` tree for fixture-namespace files (`api_*.md`, the overturn
snapshot's name) newer than the eval marker, so a concurrent session
editing unrelated real tasks no longer trips it; a hit on a
fixture-namespace file is a genuine sandbox escape. The repair-class scenarios (`repair_to_ready`,
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
