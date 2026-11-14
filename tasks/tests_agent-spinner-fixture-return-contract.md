---
description: "Bring agent_spinner eval fixture returns up to the ledger phase 2 return contract (objections key, fork option objects) and gate every fixture's staging and open returns in make test."
scope: tests/agent_spinner
created: 2026-11-14T12:46:51Z
updated: 2026-11-14T13:11:22Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Bring agent_spinner fixture returns up to the ledger phase 2 return contract

## Goal

Every agent_spinner behavioural eval stages cleanly again, and every helper return a fixture stages matches the return contract the shipped ledger enforces. A deterministic check in `make test` stages every eval in `tests/agent_spinner/evals/evals.json` and runs `accept` on every return a fixture leaves for the run to accept, so the next ledger change that leaves a fixture behind fails the gate instead of a paid eval run.

## Context

[The ledger phase 2 task](archive/ai-dev_agent-spinner-ledger-phase-2.md) made `objections` a required return key and required each fork option to be an object with a stable `id` and a `cost`. The contract now lives in `plugins/ai_dev/skills/agent_spinner/references/run-protocol.md` under `### Return contract`, and `validate_return` in `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py` enforces it: `accept` refuses a return with `required key missing: objections`, refuses a fork whose option is not an object with `fork option is not an object`, and refuses an objection whose `fork` names no fork of the same return or whose `option` names no option id of that fork.

Every fixture writes its returns through the shared writer `tests/agent_spinner/evals/fixtures/_return.py`, whose default key set has no `objections`. That breaks fixtures in two ways:

- **Staging fails.** A fixture that calls `run_ledger accept` in its own `setup.sh` makes `stage.sh` exit non-zero before any worker starts. The 2026-11-14 full-suite Claude run record, a dated section at the end of `tests/agent_spinner/evals/README.md` that may land on the default branch separately from this task, lists the evals this hid on that run.
- **Staging passes, the run's own `accept` fails.** A fixture that leaves a return in a `dispatched` row for the run to accept stages cleanly, and the worker's `accept` then refuses it for the missing key rather than for anything the scenario stages. `labelled_forks_all_relayed` is also refused for its string fork options. `failure_taxonomy`, `hollow_plan_blocks_writes`, and `uncited_clean_reroute` stage returns that `accept` must refuse by design, and the missing key adds a refusal reason their scenarios never meant.

The `objections` value each staged return should carry follows from the contract: an objection answers a fork in the same return, so a return with no fork can carry only an empty list. `labelled_forks_all_relayed`'s `survey:alpha` is the one staged return with forks, and its scenario relays three forks without objecting to any option. `leading_option_objection_in_packet` and `refuter_alternative_becomes_fork` stage their objection-like content as a refuter finding and a refuter alternative, and their `grade.sh` arms key the surfaced disposition on `refute:facts:findings:0` and `refute:edit2:alternatives:0`, so those records stay where they are.

`tests/agent_spinner/run_all.sh` is the harness's deterministic entrypoint that `make test` reaches through `tests/run_all.sh`. Its header comment counts four runners, and `tests/agent_spinner/README.md` lists them in its layout tree beside the line `run_all.sh                   # drives run.sh, ledger_run.sh, grade_cases.sh, and test_run.py`. The `agent_spinner/` row of the harness inventory table in `tests/CLAUDE.md` describes the same deterministic surfaces; `tests/AGENTS.md` carries no copy of that table, since its `## What's here` section points at the one in `tests/CLAUDE.md`.

## Approach

1. In `_return.py`, add `"objections": []` to the default return dict right after `"forks"`, the position the contract's key list gives it, so every staged return carries the key and a fixture that stages objections passes them through its extras.
2. In `labelled_forks_all_relayed/setup.sh`, rewrite each fork's `options` from bare strings to objects carrying `id`, `text`, and `cost`, keeping each `FORK_*` issue line and each `preferred` end state as they are, so the return's only refusal is gone and the grader's three fork records and three `FORK_*` markers still hold.
3. Add `tests/agent_spinner/script_tests/fixture_stage.py`. For every id in `evals.json` it runs `stage.sh <id> <dir>` into a fresh temporary directory and records a failure with the stage's last error line when the exit code is non-zero. For every roster row the staged run holds in state `dispatched` whose `returns/<label>.md` exists, it copies the staged project to a throwaway directory, runs the bundled ledger's `accept <label>` there, and compares the refusal lines against an expected-refusal map keyed on eval id and label. A return absent from the map must accept with exit 0, a mapped return must be refused with exactly its mapped lines, and a map entry that matches no staged return fails the check. Each map entry carries a comment naming the scenario that stages the refusal. The check removes its temporary directories and exits non-zero on any failure, naming each failing eval and label.
4. Seed the map with the refusals the scenarios stage on purpose: `failure_taxonomy`'s boilerplate `survey:beta` and placeholder `survey:delta`, `hollow_plan_blocks_writes`'s placeholder checklist span, and `uncited_clean_reroute`'s missing receipt. Pin `judge_flaws_capped`'s two judge rows, whose `examined ... has no recorded input version` refusal predates ledger phase 2, with a comment saying the refusal is pinned as observed rather than judged intended.
5. Run the check as its own section of `tests/agent_spinner/run_all.sh`, folding its result into the aggregated exit code, and rewrite the header comment's runner count and list to include it. Rewrite the README layout tree's `run_all.sh` line and add the new script to the tree and to the **script_tests** surface prose, and add the check to the `agent_spinner/` row of the inventory table in `tests/CLAUDE.md`.

**Out of scope:**

- Changing `judge_flaws_capped`'s fixture, since its refusal predates ledger phase 2 and step 4 pins it as observed.
- Restaging `leading_option_objection_in_packet` or `refuter_alternative_becomes_fork` around fork and objection records, since their graders key on the finding and the alternative they stage today.

## Acceptance

- Running `bash tests/agent_spinner/evals/stage.sh <id> <dir>` for every id that `jq -r '.evals[].id' tests/agent_spinner/evals/evals.json` lists exits 0 for each id.
- In every staged sandbox, every file under `proj/.agent_spinner/returns/` whose fenced JSON block parses holds an `objections` key whose value is a list, and the only non-empty lists are ones a fixture's extras set.
- `labelled_forks_all_relayed`'s staged `survey:alpha` return accepts with exit 0 in a throwaway copy, and its `ledger.jsonl` then holds three fork records whose issues carry `FORK_ALPHA`, `FORK_BETA`, and `FORK_GAMMA`.
- `python3 tests/agent_spinner/script_tests/fixture_stage.py` exits 0 on the finished tree, and `bash tests/agent_spinner/run_all.sh` prints its section and exits 0.
- With the `"objections": []` default removed from `_return.py` in the working tree, `python3 tests/agent_spinner/script_tests/fixture_stage.py` exits non-zero and names at least one eval whose stage failed and one staged return refused with `required key missing: objections`. Restoring the line returns it to exit 0.
- With one expected-refusal entry's mapped line edited, the check exits non-zero naming that eval and label, which proves a mapped return is compared line for line.
- `tests/agent_spinner/run_all.sh`'s header comment, the README layout tree and **script_tests** prose, and the `agent_spinner/` row of `tests/CLAUDE.md` each name the fixture staging check, and no passage still counts four runners or lists `run_all.sh` driving only `run.sh`, `ledger_run.sh`, `grade_cases.sh`, and `test_run.py`.
