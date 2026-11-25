# ai_instruction_formatting runbook

Run the deterministic bundled-script tests:

```bash
./tests/ai_instruction_formatting/run_all.sh
```

The suite runs `script_tests/run.sh`, which invokes the skill's
`scripts/lint_pseudo_xml.py` once per fixture under `script_tests/fixtures/`
and asserts, per fixture:

- the linter's exit status;
- the blocking-issue count on its closing tally line;
- the error count on that line;
- the document shape it detected.

The four shape fixtures and the clean-file check expect exit 0 with zero
blocking issues. `error_case.md` expects exit 1 with two errors. The
warning-only `warning_case.md` expects exit 0 with one blocking issue and zero
errors, which pins the split between warnings and the exit status.

Per-run output lands in `results/script_tests.log`, which
`tests/.gitignore` keeps out of git.

A FAIL here means the linter's verdict over a known input changed. Read the
fixture and the linter rule it exercises before changing the expectation: the
expectation is the contract, so a parser fix updates both together.
