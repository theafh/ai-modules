# spr behavioural harness

Pattern A harness for `plugins/knowledge_management/skills/spr`.

## What it proves

- **Deterministic (`script_tests/run.sh`)**: the grader's PASS direction and
  one FAIL direction for each check — one bullet per source paragraph, no
  numbered lists, no trailing punctuation on a bullet, the out-of-scope
  boundary, and the final 1-to-10 rating.
- **Behavioural (`evals/`)**: two evals over two fixtures, run through
  `evals/run.py` on the default Cursor worker in the shared
  `tests/lib/eval_runner` pool. `grade.sh` runs the deterministic checks and
  `judge.py` adds a refute-biased verdict on reconstructability and
  non-overlap.

## Layout

```text
evals/
  evals.json
  stage.sh
  grade.sh
  judge.py
  run.py
  fixtures/<id>/setup.sh
script_tests/run.sh
run_all.sh
```

## Running

```bash
bash tests/spr/run_all.sh            # deterministic
python3 tests/spr/evals/run.py       # behavioural, default vendor
```
