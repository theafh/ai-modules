# ai_instruction_formatting skill regression test harness

This local harness regression-checks the pseudo-XML linter the skill bundles at
`plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py`.

The skill instructs users to run that linter, and other harnesses call it only
as a pass/fail contract check on their own artefacts. Nothing asserted its
verdicts over purpose-built inputs before this harness, so a parser change was
taken on trust. `script_tests/` now runs the linter over fixtures for each of
the four document shapes it recognises, plus one file that trips an error and
one that trips only a warning, and asserts the exit status, the blocking-issue
count, the error count, and the detected shape.

The skill's agent-level prose behaviour stays out of scope; behavioural evals
belong to a later iteration if that surface needs sample-based coverage.

## How to run

```bash
./tests/ai_instruction_formatting/run_all.sh
bash tests/ai_instruction_formatting/script_tests/run.sh
```

`tests/run_all.sh` discovers this harness at run time, so `make test` runs it
with every other deterministic surface. The authored harness is committed and
linted; `tests/.gitignore` keeps its run output out of git.

## Fixtures

| Fixture | Shape | Expected verdict |
| :--- | :--- | :--- |
| `prose_only.md` | Prose-only markdown | Exit 0, no blocking issue |
| `xml_instruction.md` | XML-instruction body | Exit 0, no blocking issue |
| `tutorial.md` | Tutorial with an `xml` fence | Exit 0, no blocking issue |
| `mixed_agent.md` | Mixed-agent, two wrappers | Exit 0, no blocking issue |
| `error_case.md` | XML-instruction body | Exit 1, two errors |
| `warning_case.md` | XML-instruction body | Exit 0, one warning, no error |
