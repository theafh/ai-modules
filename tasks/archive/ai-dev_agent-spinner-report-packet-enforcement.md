---
description: "Make agent_spinner's report-opening and decision-packet rules hold: every restatement and the P6 check name all four opening facts, and the ledger refuses a fork without an anchored passage."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-19T22:20:06Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Make agent_spinner's report-opening and decision-packet rules hold

## Goal

An orchestrator that follows agent_spinner writes a report whose opening sentence carries the answer, the tier, helpers dispatched against returned, and whether `close` exited 0. Every decision packet it renders names each passage the fork touches, verbatim with its anchor. Today both rules live only in reference prose, and the 2026-11-14 Claude run (`opus` at high effort) broke both while it kept every rule that `accept` or `show` enforces.

## Context

All paths are under `plugins/ai_dev/skills/agent_spinner/`.

**The opening sentence.** SKILL.md `<reporting>` states the rule: "The opening sentence gives the answer, the tier, helpers dispatched against returned, and whether `close` exited 0". Every other place that restates the opening names only one of those facts:

- SKILL.md `<degradation>` says "State the tier reached in the run's opening sentence".
- SKILL.md `<run_state>` and `references/run-protocol.md`'s no-clean-close rule name the close status alone.
- The P6 self-check in `references/run-protocol.md`, the report's only self-check, tests the close status alone.
- `references/recipes/fidelity-review.md` names per-phase counts.
- `references/report-shapes.md`'s stop template ("Stopped after 2 of 4 writers, at the spawned-roles tier, 2 dispatched against 2 returned.") puts the close status in a second sentence.

Across the 71 Opus reports of that run, 29 carried the tier and dispatched-against-returned within the first two sentences, and 61 carried both somewhere in the opening paragraph. A run that did not close cleanly tended to lead with the failure, as the close-status restatements ask, and pushed the other facts to sentences three to five. The four evals `clean_corpus`, `containment_one_path`, `planted_defect`, and `roster_partial_stop` fail on that; their grader already allows two sentences. The evening Claude run of the repaired suite failed the same rule in `containment_one_path`, `roster_partial_stop`, `report_rederivation`, and `skipped_close_reported`, the last on "the report's opening says no clean close exists".

**The decision packet.** `references/report-shapes.md` says a packet carries "each passage the fork touches verbatim with its anchor", and its stop-report example shows a "Passages touched:" block with "anchor: request, sentence 2". `references/run-protocol.md` asks to "Render each decision packet with `show --packet ID` … rather than by hand". But the fork schema there says "A fork may also carry `passages`", `validate_return` in `scripts/run_ledger.py` checks `passages` only when it is present, and `show --packet` prints "Passages touched:" followed by "none" for a fork that carries none. A fully compliant run can therefore render a packet with no passage. `unanswered_gate_stops_with_packet` failed because its worker wrote the packet by hand without passages; the gap would survive a run that used `show`.

This task, [the terminal-states task](ai-dev_agent-spinner-ledger-terminal-states.md), and [the brief-contract task](ai-dev_agent-spinner-ledger-brief-contract.md) all edit `scripts/run_ledger.py` and `references/run-protocol.md`. Land this one after both.

## Approach

1. Keep the opening rule as SKILL.md `<reporting>` states it, and rewrite in place each passage that restates the report's opening so it names all four opening facts or points at `<reporting>` instead of naming one of them: the restatements listed above plus the further phrase hits in `references/report-shapes.md`, `references/degradation-examples.md`, and `references/recipes/research-synthesis.md`, which Acceptance item 1's phrase sweep covers. The no-clean-close restatements keep their instruction to say so first, inside that same opening sentence. SKILL.md `<degradation>` is the exception: it governs the pre-dispatch announcement, so rewrite it in place to state the tier for the announcement that opens the run before the first helper, dropping the "run's opening sentence" phrasing so it neither demands facts that do not exist before dispatch nor reads as a restatement of the report's opening sentence. The Probe step in `references/degradation-examples.md` states that same announcement rule, and the check accepts its tier-only outcome.
2. Rewrite the P6 self-check in `references/run-protocol.md` so it checks all four facts in the opening sentence, and rewrite `references/report-shapes.md`'s stop template so its first sentence carries all four, the close status included.
3. Make an anchored passage part of the fork contract, in one edit across every surface that states the fork shape. Add `passages` to `RETURN_LIST_FIELDS`'s `("forks", ("issue", "options", "preferred"))` entry so `render_return_block` prints it in the `- forks: objects with …` line of every brief's closing block, and rewrite `references/role-prompts.md`'s `## Closing block` fork sentence in place to name `passages` beside `issue`, `options`, and `preferred`. Then `validate_return` refuses a fork with no `passages` entry carrying an anchor, `show --packet` refuses to render a fork without one and names the missing passage, `references/run-protocol.md`'s fork schema states the requirement in place of "A fork may also carry `passages`", and P3's fork bullet, under "`accept` applies every rejection rule below", states the same refusal in place of its present passage clause. A fork that touches only the request names the request sentence as its passage. Because `accept` imports no passage-less fork once that check lands, prove the `show --packet` refusal on a staged legacy run directory: the scenario appends one pre-change fork row (`"type": "fork"` with `issue`, `options`, `preferred`, and no `passages`) to that directory's `.agent_spinner/ledger.jsonl`, surfaces it through `dispose --id … --disposition surfaced --packet …`, and runs `show --packet`.
4. Run `python3 tests/agent_spinner/script_tests/fixture_stage.py`. Each fixture whose staged return carries a fork without an anchored passage now fails it; give each such fork a passage taken from its fixture's own text. Then run `bash tests/agent_spinner/script_tests/ledger_run.sh`. `scenario_brief_contract` in that script stages its `emit_return` for `check:r` with a fork of `issue`, `options`, and `preferred` only and asserts "a return built from the rendered contract is accepted", so give that staged fork a passage taken from the scenario's own fixture (`{"text": "alpha", "anchor": "a.txt:1"}`, the text and anchor its own finding already carries) and keep the assertion, which then proves the rendered contract and `accept` agree; the scenario's "the closing block states the forks fields" check reads the fork field list the rendered template prints, so it states `passages` beside `issue`, `options`, and `preferred`.

**Out of scope:** The ledger record for a fork the run raises itself (a widening, an estimate above the stated guideline, a scope question) — owned by [the unanswered-fork task](ai-dev_agent-spinner-unanswered-fork-holds-run.md), which names that record in its Goal.

## Acceptance

- A static check in `tests/agent_spinner/script_tests/run.sh` takes every passage in SKILL.md and
  `references/` that contains the phrase "opening sentence" and asserts one of three outcomes from
  that passage's own tokens:
  - it carries all four report facts: the tokens `answer`, `tier`, `dispatched`, `returned`, and
    `exited`;
  - or it carries the literal pointer `<reporting>`;
  - or it is a pre-dispatch announcement passage — SKILL.md's `<degradation>` block or the Probe
    step of `references/degradation-examples.md` — naming the tier it reached (`tier`, `inline
    floor`, or `spawned roles`) and carrying none of `answer`, `dispatched`, or `exited`.
  The check fails a matched passage meeting none of the three, and prints each matched site by
  file and phrase, so a site added later shows up as a named failure rather than being skipped.
- The P6 self-check text and the stop template's first sentence each carry all four facts, and SKILL.md `<degradation>` still states the tier for the announcement that opens the run, without naming a `close` exit or a dispatched-against-returned count.
- A static check in `tests/agent_spinner/script_tests/run.sh` reads the fork bullet under "`accept` applies every rejection rule below" and the `forks` bullet in `references/run-protocol.md`'s `### Return contract`, and asserts each requires an anchored `passages` entry, neither states `passages` as optional, and the sentence "A fork may also carry `passages`" is absent.
- A `ledger_run.sh` scenario: `accept` rejects a return whose fork has no anchored passage and takes the same return once the fork carries one; on a staged run directory whose `.agent_spinner/ledger.jsonl` carries an appended pre-change fork row with no `passages`, surfaced through `dispose --id … --disposition surfaced --packet …`, `show --packet` exits non-zero and names the missing passage.
- `brief` renders `passages` in the closing block's `- forks: objects with …` line, and `references/role-prompts.md`'s `## Closing block` fork sentence names `passages`; a static check in `tests/agent_spinner/script_tests/run.sh` asserts the role-prompts sentence, and `scenario_brief_contract` in `tests/agent_spinner/script_tests/ledger_run.sh` accepts a return built from the rendered contract once its staged fork carries the anchored passage its own fixture supplies and reads the rendered fork field list with `passages` in it.
- `python3 tests/agent_spinner/script_tests/fixture_stage.py` passes for every eval.
- Every eval that grades the opening or the decision packet runs on the default vendor, and the result is recorded in `tests/agent_spinner/evals/README.md`. The set is `REPORT_CONTRACT_EVALS` in `tests/agent_spinner/evals/grade.sh` plus every eval branch that calls `opening_has` or `report_carries_decision_packet` (today `verdict_waits_for_open_checker`, `skipped_close_reported`, `unanswered_gate_stops_with_packet`), and the record checks every member that selector and those branches resolve to, so an eval added to either later is covered without editing this item. If any member fails on the opening or the packet, the record says which fact or field was missing, and the task stays open for another pass on the wording rather than adjusting the grader to the miss.
