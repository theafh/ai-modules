# tests/task_create: open-decision burden-of-proof harness

Pattern A (skill-creator-aligned). `task_create` ships no scripts of its own.
It drives the base `task` skill's `discover_tasks.sh`, `init_tasks.sh`, and
`lint.py`, which `tests/task/script_tests/` already covers. So
`script_tests/run.sh` here tests the eval grader instead: each case stages an
eval, installs a chosen task body under the sandbox's `tasks/`, and reads one
`evals/grade.sh` check's verdict, which keeps the label forms recorded draws
produced covered after their workspace runs are gone. There is no
`run_all.sh`, so drive `script_tests/run.sh` directly.

| Surface | Where | What it covers | Runner |
| --- | --- | --- | --- |
| Grader | `script_tests/` | `evals/grade.sh` verdicts on chosen task bodies: the one-label count reading only block-start lead-ins (heading-form labels included) and skipping a Context pointer to the Approach label, wrapped or not, the guardrail-bound why-open ground, both options named by uppercase markers or an either-or sentence, a non-`rich` styling path named by its substance, and an empty sandbox reporting zero files, each beside a control that still fails; plus every fixture's git identity and the eval runner's stop on a failed or empty stage through `tests/lib/check_stage_guard.py` | `bash tests/task_create/script_tests/run.sh` |
| Skill behavior | `evals/` | the base **Decide or label** rule as the create path applies it: reconcile silently, else label *and* surface (stage → agent → grade) | `python3 tests/task_create/evals/run.py` |

The whole-family behavioral suite lives in `tests/task/evals/` and keeps its
own `create`, `create_scope_trim`, `create_regroup_owner_account`,
`standing_rules_create`, and `lossless_single` evals for the rest of the create
path. This harness is the
one that exercises the open-decision half of it.

## What the three evals prove

The rule under test says: settle silently every fork the ordered evidence base
can settle, and treat a decision as genuinely open only when that evidence is
insufficient or the fork is guardrail-bound. A genuinely open decision is then
  handled twice over: written into the task as a labeled open-decision lead-in
  (bare or qualified) carrying its options, a suggested default, and the
  why-open clause, *and* surfaced to the user.

Every fixture stages its sandbox as a committed git repository whose identity,
`Evals`, supplies `reported-by`, so no run stops to ask which name to record
and the worker's reply carries only the decision under test.

- **`reconcile-recorded`**: every tier agrees, so no label may appear. The
  fixture mirrors the observed failure the tightening closes: an authoring
  session that labeled an evidence-settled test-reachability fork as its open
  decision, with a default the evidence had already picked. Permissive
  behaviour fails this eval; the tightened rule passes it. The archived
  precedent covers a different module that imports the same backend, so the
  run reaches drafting without a prior-art question.
- **`labeled-why-open`**: no tier reaches the fork, which rests on the user's
  own risk appetite. Exactly one label, carrying options, a default, and a true
  why-open clause, surfaced to the user.
- **`guardrail-bound-surface`**: both available paths cross a guardrail
  boundary (`CHARTER.md` forbids the dependency, `ARCHITECTURE.md` forbids the
  hand-rolled alternative), which the standing hierarchy never auto-resolves.
  Same labeled-and-surfaced handling.

## Running

```bash
bash tests/task_create/script_tests/run.sh
python3 tests/task_create/evals/run.py
```

The script tests run in seconds and start no worker. The evals consume LLM
tokens. See `evals/README.md` for the stage → agent → grade recipe, the
verdict cache, and how the surfaced half of the obligation is graded.

## Trigger evals

Routing for `task_create` is covered by the family set at
`../trigger_evals/task.json`, not here.
