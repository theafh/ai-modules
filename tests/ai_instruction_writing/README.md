# ai_instruction_writing skill regression test harness

This local harness checks the static prose contract for
`plugins/ai_dev/skills/ai_instruction_writing/SKILL.md`.

The skill ships no bundled helper scripts, so the current deterministic
surface is a content-contract test under `script_tests/`. Behavioral
evals can be added later if the skill's agent-level output quality needs
sample-based coverage.

## How to run

```bash
./tests/ai_instruction_writing/run_all.sh
```

The authored harness under `tests/` is committed and linted; `tests/.gitignore`
keeps its run output out of git.
