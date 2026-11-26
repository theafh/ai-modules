# executive_summary behavioural harness

Pattern A harness for `plugins/knowledge_management/skills/executive_summary`.

## What it proves

- **Deterministic (`script_tests/run.sh`)**: the grader's PASS direction and
  one FAIL direction for each check — the 8-17% length window (the 10-15%
  target with measurement tolerance), the no-bullet/no-numbered-list rule, the
  1-to-10 self-rating, and the invented-term boundary.
- **Behavioural (`evals/`)**: two evals over two fixtures, run through
  `evals/run.py` on the default Cursor worker in the shared
  `tests/lib/eval_runner` pool. `grade.sh` runs the deterministic checks and
  `judge.py` adds a refute-biased verdict on fidelity and ordering.

## Layout

```text
evals/
  evals.json
  stage.sh            stage an eval, print sandbox_proj/skill_path/prompt
  grade.sh            deterministic checks
  judge.py            refute-biased fidelity and ordering judge
  run.py              Pattern A runner
  fixtures/<id>/setup.sh
script_tests/run.sh   grader PASS/FAIL cases
run_all.sh            deterministic entrypoint
```

## Running

```bash
bash tests/executive_summary/run_all.sh            # deterministic
python3 tests/executive_summary/evals/run.py       # behavioural, default vendor
```
