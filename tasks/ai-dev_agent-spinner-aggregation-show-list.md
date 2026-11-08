---
description: "Correct `<aggregation>`'s `show` record list to the record types the shipped ledger imports, and name the channel that carries a beyond-brief find."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-08T22:07:15
updated: 2026-11-08T22:07:15
status: open
reported-by: Andreas Hoffmann
---

# Correct `<aggregation>`'s `show` record list to the record types the ledger imports

## Goal

After this task, `<aggregation>` sends the orchestrator through `show` only to record types the shipped ledger actually imports, and names the channel that carries a beyond-brief find and a disagreement between two returns. A run reads every judgement record the ledger holds, and no instruction points at a record the program never writes.

## Context

- **Current state.** `plugins/ai_dev/skills/agent_spinner/SKILL.md`'s `<aggregation>` block says: "Read through `show`, in full, every record that needs your judgement: forks, decide-class findings, contradictions, beyond-brief finds, incidents, and own-authority calls."
- **What the ledger imports.** `RECORD_LISTS` in `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py` imports `findings`, `forks`, `incidents`, `own_authority`, `alternatives`, `brief_corrections`, `dropped_suspicions`, and `confirmations`. `beyond_brief` is a validated return key in `RETURN_KEYS` and never becomes a record, and no contradiction record type exists. `show <label>` therefore prints no beyond-brief record and no contradiction record.
- **What does carry a beyond-brief find.** `dispose --flag LABEL --reason TEXT` writes a flag record. The shipped `beyond_brief_defect_reported` eval already records a beyond-brief defect that way, and its grader asserts a `"type": "flag"` record, so the body currently contradicts its own eval.
- **Why the text is wrong today.** The archived [ledger-doctrine task](archive/ai-dev_agent-spinner-ledger-doctrine.md) froze this sentence as its `<aggregation>` target text, so the ledger-doctrine audit confirmed the block matched that text rather than the program. This task supersedes that one sentence; the archived task stays unedited as the decision record.
- **Ownership.** The live judgement-containment and checking-doctrine tasks rewrite other blocks (`<judgement>`, `<containment>`, `<phase_plan>`, `<delegation_depth>`, `<capability_probe>`, `<degradation>`, and the checking blocks), not `<aggregation>`, so this task owns this sentence alone.
- **Reproduction.** Accept a return carrying a `beyond_brief` entry in a scratch run, then run `show <label>`: it prints only the dispatch and accept records, and `ledger.jsonl` carries no beyond-brief line.

## Approach

Rewrite the `show` sentence in `<aggregation>` in place so it matches the shipped program:

- List only record types `RECORD_LISTS` imports, meaning forks, decide-class findings, incidents, and own-authority calls.
- State that a beyond-brief find is recorded as a flag through `dispose --flag` and read the same way.
- State how a disagreement between two returns is handled without inventing a record type: check each side and record the disagreement as a finding.
- Keep the rest of the block and its economy. `<aggregation>` measured 907 bytes before this task; keep it at or under 1,000 bytes, and keep `SKILL.md` under 25,000 bytes.

Add a static check in `tests/agent_spinner/script_tests/run.sh` that inspects the `<aggregation>` block alone: it fails when the block names `contradictions` or `beyond-brief finds` as `show` records, and passes when the block names the `dispose --flag` channel for a beyond-brief find. Prove the check fails on a scratch copy carrying the old sentence.

Bump the `agent_spinner` skill version (patch) and raise the `ai_dev` plugin version with both plugin manifests and both marketplace registrations in lockstep, per the repo rules.

**Out of scope:**

- Adding a `contradiction` or `beyond_brief` record type to `scripts/run_ledger.py`, since this task corrects the prose to the shipped program's behaviour.
- The rest of `<aggregation>`'s content and the digest example in `references/report-shapes.md`.
- The other blocks the judgement-containment and checking-doctrine tasks own.

## Acceptance

- `<aggregation>` names no record type `RECORD_LISTS` lacks, and states that a beyond-brief find is recorded through `dispose --flag`.
- `grep` over the `<aggregation>` block finds 0 matches for `contradictions` and for `beyond-brief finds`.
- The block measures at most 1,000 bytes from opening tag through closing tag, and `wc -c` on `SKILL.md` reports under 25,000 bytes.
- `bash tests/agent_spinner/script_tests/run.sh` passes with the new `<aggregation>` check, and that check fails on a scratch copy carrying the old sentence.
- `beyond_brief_defect_reported` keeps its `"type": "flag"` grader assertion and its prompt's `dispose --flag` instruction, and the body now agrees with both.
- `make lint` is clean.
- `agent_spinner` and `ai_dev` versions are consistent across the skill, both plugin manifests, and both marketplace registrations.
- A read of the changed files finds no session, company, or project name.
