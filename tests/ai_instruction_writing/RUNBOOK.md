# ai_instruction_writing runbook

Run the deterministic content-contract test:

```bash
./tests/ai_instruction_writing/run_all.sh
```

The test reads the source `SKILL.md` in place and asserts that the
load-bearing-negative guidance remains structurally present:

- the fourth `<self_check>` branch exists and follows the redundant
  inverse branch;
- `<valid_load_bearing_negative>` sits immediately after
  `<invalid_redundant_negative>`;
- the keep and cut examples remain paired;
- the discriminator names the reader-learns and exact-tool-set tests;
- production-rule applicability remains explicit;
- the original absolute enumerable-cut phrases stay removed.
