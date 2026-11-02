---
description: "Replace the gate's hand-written shell scanner with a per-harness declaration so every deterministic eval file runs exactly once and an undecided harness fails by name."
scope: tests
created: 2026-11-02T08:13:09
updated: 2026-11-02T08:13:09
status: open
reported-by: Andreas Hoffmann
---

# Make the harness eval-file coverage decision explicit and decidable

## Goal

The aggregate gate decides which `evals/test_run.py` and `evals/test_grade.py` files it runs from an explicit per-harness declaration rather than by guessing whether an entrypoint invokes them, so every deterministic eval file runs exactly once and a harness whose coverage is undecided fails the gate by name.

The user-visible outcome: `bash tests/run_all.sh --list` names each eval file exactly once, and a harness that carries an eval file without stating who runs it makes the gate exit non-zero with a message naming that harness and the path it must add.

## Context

`tests/run_all.sh` discovers a harness, runs its entrypoint (`run_all.sh` or `script_tests/run.sh`), then adds every `evals/test_run.py` or `evals/test_grade.py` the entrypoint "does not already run", so each deterministic file runs once. `TESTING.md` `## Running Tests` restates that promise, and the repo rule that makes `make test` the default test run rests on it. The gate that carries the promise was built by [the single deterministic gate task](archive/tests_single-deterministic-gate.md), whose Goal is the outcome this task preserves.

The coverage decision lives in `entrypoint_invokes()`, a hand-written awk scanner built from `scan()`, `tokenize()`, `first_command()`, `is_interpreter()`, `loop_invokes()`, and `segment_invokes()`. It models shell syntax well enough to decide whether an entrypoint executes a file, and each miss costs real time: a miss in one direction drops a suite silently, a miss in the other runs it twice and doubles both its runtime and its failure output. Review rounds on the gate each found a further shape it misread, including a comment-only mention, a here-doc usage line, a variable interpreter, a `for` loop, an arithmetic `(( shift = 1 << 3 ))` command, an arithmetic expression continued across lines, and an invocation behind `then`, `do`, `else`, `elif`, `{`, or `!`.

The class stays open. A shape probe against the committed gate still double-runs an eval file for a launcher with options (`env -i python3 …`, `nice -n 10 …`, `stdbuf -oL …`, `time -p …`, `sudo -u root …`, `uv run --python 3.11 …`), for direct execution (`./evals/test_run.py`), for a file path held in a variable (`SCRIPT=evals/test_run.py` then `python3 "$SCRIPT"`), and for `xargs`. Every added shape is another special case in the same scanner, so the defect returns with the next spelling.

The durable pin for the current behaviour is `tests/lib/test_run_all_gate.py`, whose `ENTRYPOINT_CASES` and `synthetic_listing()` build a scratch tree per entrypoint shape. The reproduction scripts under the ignored `.git_auto_review/` relay are not durable: git ignores that folder and the next run clears it, so a committed test is the only pin that survives.

## Approach

Replace the guess with a declaration the gate reads as plain text.

- Add a per-harness declaration file at `tests/<harness>/evals/covered-by-entrypoint`, listing one eval file name per line for each eval file that harness's entrypoint runs.
- In `tests/run_all.sh`, replace `entrypoint_invokes()` and every awk helper it calls with a read of that declaration. The gate runs each eval file the declaration omits and adds no file it names, so no shell parsing remains anywhere in the coverage decision.
- Fail closed on an undecided harness. When a harness carries an `evals/test_run.py` or `evals/test_grade.py` and no declaration file, the gate exits non-zero and names the harness and the declaration path it must create, so a new harness states its coverage instead of inheriting a guess.
- Migrate every harness that carries an eval file today by writing its declaration from what its entrypoint actually executes, so the aggregate listing is unchanged for those harnesses.
- Rewrite the coverage promise in the `tests/run_all.sh` header comment, in `TESTING.md` `## Running Tests`, and in the repo rule that repeats it, so one canonical statement describes the declaration contract. Delete the superseded "does not already run" wording rather than adding beside it.
- Replace `ENTRYPOINT_CASES` in `tests/lib/test_run_all_gate.py` with declaration-conformance cases, keeping `synthetic_listing()` as the scratch-tree builder: a declared eval file stays unlisted, an undeclared one is listed, and a harness with an eval file and no declaration fails the gate by name.

The declaration is plain text, so the gate stays on the repo's standing toolchain with no new dependency and no hidden state.

**Out of scope:** Rewriting the behavioural eval runners or their `--vendor` handling; this task changes only the aggregate gate's deterministic coverage decision.

## Acceptance

- `bash tests/run_all.sh --list` names each path that `ls tests/*/evals/test_run.py tests/*/evals/test_grade.py` finds exactly once, and a command that counts its occurrences in the listing reports one per file.
- A fixture harness whose entrypoint invokes its eval file through each shape this task's Context lists (launcher options, direct execution, a variable-held path, `xargs`, arithmetic, and a reserved word) and whose declaration names that file is listed with only its entrypoint, and `--surface <fixture>` runs the eval file exactly once, proven by the eval file appending one line to a counter file that the check reads.
- A fixture harness carrying an eval file and no declaration makes the gate exit non-zero with a message naming that harness and the declaration path it must create.
- `entrypoint_invokes()` and the helpers `scan()`, `tokenize()`, `first_command()`, `is_interpreter()`, `loop_invokes()`, and `segment_invokes()` are absent from `tests/run_all.sh`, and its header comment states the declaration contract as the only coverage rule.
- `TESTING.md` `## Running Tests` states the declaration contract, and the "does not already run" phrasing appears in neither `tests/run_all.sh` nor `TESTING.md`.
- `tests/lib/test_run_all_gate.py` exercises the three declaration cases above and fails when the declaration read is inverted, proven by running it against a scratch copy of the gate with that read inverted.
