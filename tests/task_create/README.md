# tests/task_create — open-decision burden-of-proof harness

Pattern A (skill-creator-aligned), behavioral only. `task_create` ships no
scripts of its own — it drives the base `task` skill's `discover_tasks.sh`,
`init_tasks.sh`, and `lint.py`, which `tests/tasks/script_tests/` already
covers — so there is no `script_tests/` and no `run_all.sh` here.

| Surface | Where | What it covers | Runner |
| --- | --- | --- | --- |
| Skill behavior | `evals/` | the base **Decide or label** rule as the create path applies it: reconcile silently, else label *and* surface (stage → agent → grade) | `python3 tests/task_create/evals/run.py` |

The whole-family behavioral suite lives in `tests/tasks/evals/` and keeps its
own `create`, `create_scope_trim`, `standing_rules_create`, and
`lossless_single` evals for the rest of the create path. This harness is the
one that exercises the open-decision half of it.

## What the three evals prove

The rule under test says: settle silently every fork the ordered evidence base
can settle, and treat a decision as genuinely open only when that evidence is
insufficient or the fork is guardrail-bound. A genuinely open decision is then
handled twice over — written into the task as a labeled `Open decision:`
carrying its options, a suggested default, and the why-open clause, *and*
surfaced to the user.

- **`reconcile-recorded`** — every tier agrees, so no label may appear. The
  fixture mirrors the observed failure the tightening closes: an authoring
  session that labeled an evidence-settled test-reachability fork as its open
  decision, with a default the evidence had already picked. Permissive
  behaviour fails this eval; the tightened rule passes it.
- **`labeled-why-open`** — no tier reaches the fork, which rests on the user's
  own risk appetite. Exactly one label, carrying options, a default, and a true
  why-open clause, surfaced to the user.
- **`guardrail-bound-surface`** — both available paths cross a guardrail
  boundary (`CHARTER.md` forbids the dependency, `ARCHITECTURE.md` forbids the
  hand-rolled alternative), which the standing hierarchy never auto-resolves.
  Same labeled-and-surfaced handling.

## Running

```bash
python3 tests/task_create/evals/run.py
```

These consume LLM tokens. See `evals/README.md` for the stage → agent → grade
recipe, the verdict cache, and how the surfaced half of the obligation is
graded.

## Trigger evals

Routing for `task_create` is covered by the family set at
`../trigger_evals/task.json`, not here.
