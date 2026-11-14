---
description: "Make agent_spinner briefs carry the contract the ledger enforces: a labelled brief token, a recorded version for every mandated input, and a corrected re-brief for a brief-caused rejection."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-14T23:20:22Z
status: open
reported-by: Andreas Hoffmann
---

# Make agent_spinner briefs carry the return contract the ledger enforces

## Goal

A helper that follows its rendered brief literally writes a return that `accept` takes, because the brief names every value and object shape `accept` checks. A reading helper that reads several committed files can carry a valid receipt for each one. When `accept` rejects a return because the brief itself left the helper unable to comply, the orchestrator re-invokes on a corrected brief rather than an identical one, so the retry can succeed. Today the brief leaves out part of the contract `accept` checks, and the skill's retry rule repeats any violation the brief caused.

## Context

Everything here lives under `plugins/ai_dev/skills/agent_spinner/`:

- **The brief token is unlabelled.** `cmd_brief` in `scripts/run_ledger.py` ends the rendered brief with a closing block that lists the return template's keys ("Return template: fenced json block with label, brief, status, verdict, ...") and then appends the bare token as its last line. `references/role-prompts.md` documents that line as "Repeat the brief token: [token].", and nothing in the rendered brief says that the return's `brief` key must repeat it or which `status` and `verdict` values `accept` allows. `validate_return` rejects a mismatch with "brief token disagrees with the roster". Across the stored runs under `tests/agent_spinner/workspace/` (gitignored), token mismatches are about a fifth of all `accept_reject` records, and in the 2026-11-14 Claude run a lighter-model triage helper put its label in `brief` and lost both of its tries (`triage_pass_routes_missed_hit`). The brief also lists the return's keys by name only, while `references/run-protocol.md` alone, which a helper never reads, gives their shapes ("`forks` is a list of objects with `issue`, two to four `options`, and `preferred`"). In the evening Claude run, both sweepers in `snapshot_search_positive_control` answered `status: "complete"` twice, the role checker in `checker_spawned_through_role` returned string-valued forks twice, and `clean_corpus` lost two rows to a `spans` list and plain-string objections; each row ended `failed` after its identical retry.
- **A reader can record only one input version.** `brief --target` takes a single path. `snapshot` writes its copies to `snapshots/<label>/<path>`, while `recorded_input_path`, which `validate_return` consults for each examined path, reads `snapshots/inputs/<label>/<path>` and two `baseline/` locations. A judge or lens reading several committed files therefore cannot carry a valid receipt for more than one of them, and the documented `snapshot` verb never satisfies the check. That conflicts with `references/checks.md` C8 ("Take a read receipt of its path and one verbatim line for every mandated input") and with `references/run-protocol.md`'s "Every reading pass reads a snapshot, a file copy under `snapshots/` made by `snapshot`". The `judge_flaws_capped` fixture reads a single candidate per judge, so it records that one input through `brief --target` and needs no multi-input support.
- **The retry rule repeats a brief-caused violation.** SKILL.md `<helper_failure>` gives "a **contract violation**, meaning a return `accept` rejects" one "identical-prompt re-invocation". When the brief caused the violation, the identical prompt reproduces it. Workers handled this three ways in the 2026-11-14 run: they applied the rule literally and lost the row, they hand-repaired the return JSON, or they re-briefed and then rebuilt the overwritten first brief by hand, because `brief` overwrites `briefs/<label>.txt` on a second call. The same block's "inline redo only after the user chooses it" also leaves open whether the one re-invocation may itself run inline at the inline floor; one run read it each way.

This task, [the terminal-states task](ai-dev_agent-spinner-ledger-terminal-states.md), and [the report-and-packet task](ai-dev_agent-spinner-report-packet-enforcement.md) all edit `run_ledger.py`, `references/run-protocol.md`, and `tests/agent_spinner/script_tests/ledger_run.sh`. Land the terminal-states task first and this one second.

## Approach

1. Rewrite `cmd_brief`'s closing block so it labels the token line "Repeat the brief token: <token>", says the return's `brief` key carries that token verbatim, lists the `status` and `verdict` values `validate_return` accepts, and renders the object shape of every list key the template names (each finding's, fork's, objection's, and confirmation's required fields), all taken from the same constants the validator reads so the two cannot drift. Bring `references/role-prompts.md`'s return section into line with the rendered text.
2. Let a reading row record every mandated input by making `cmd_snapshot` write its copies to `snapshots/inputs/<label>/<path>`, the location `brief --target` already writes for a reader row and `recorded_input_path` already reads. One location then holds every recorded input, and `snapshot <label> <path>...` records several inputs for one row, while `brief --target` keeps its single path. Move the `snapshot --base` copies the same way, and update the `close` cleanup loop that removes `snapshots/` subdirectories if the move changes what it has to remove. Document the result once in `references/run-protocol.md`'s `snapshot` section and in the reading-pass sentence quoted above.
3. Make a second `brief` call for the same label keep the first: move the earlier `briefs/<label>.txt` to a numbered attempt file and record the re-brief in the ledger, so a corrected re-brief is a ledger event rather than a hand reconstruction.
4. Rewrite SKILL.md `<helper_failure>`'s contract-violation rule in place. A rejection the brief caused, because the brief lacked or misstated what `accept` checks, earns one re-invocation on a brief corrected through `brief`, recorded as such. Every other contract violation keeps the identical-prompt re-invocation. In the same edit, state whether that one re-invocation may run inline at the inline floor without a user choice, as distinct from the degraded inline redo after a failed re-invocation.

## Acceptance

- A `ledger_run.sh` scenario renders a brief and checks that its closing block carries the labelled token line, names the `brief` key, lists the accepted `status` and `verdict` values, and states the required fields of each list key's objects; a return built only from that rendered text is accepted.
- A `ledger_run.sh` scenario briefs one reading row over two committed files and accepts a return whose two examined paths each carry a matching receipt; with one receipt's verbatim line altered, `accept` rejects that return.
- A `ledger_run.sh` scenario runs `snapshot` for a reading row and then accepts a return whose receipt matches the snapshot copy, which today's `snapshots/<label>/` location never satisfies.
- A `ledger_run.sh` scenario calls `brief` twice for one label. The first text survives as an attempt file, and the ledger holds a record of the re-brief.
- SKILL.md `<helper_failure>` states the brief-caused re-invocation rule and the inline-floor answer, and the old blanket "identical-prompt re-invocation" sentence for contract violations no longer stands on its own.
