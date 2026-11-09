---
description: "Replace the gate's hand-written shell scanner with a per-harness declaration so every deterministic eval file runs exactly once and an undecided harness fails by name."
scope: tests
created: 2026-11-02T07:13:09Z
updated: 2026-11-04T09:27:27Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Make the harness eval-file coverage decision explicit and decidable

## Goal

The aggregate gate decides which `evals/test_run.py` and `evals/test_grade.py` files it runs from an explicit per-harness declaration rather than by guessing whether an entrypoint invokes them, so every deterministic eval file runs exactly once and a harness whose coverage is undecided fails the gate by name.

The user-visible outcome: `bash tests/run_all.sh --list` names each eval file exactly once, and a harness that carries an eval file without stating who runs it makes the gate exit non-zero with a message naming that harness and the path it must add.

## Context

`tests/run_all.sh` discovers a harness, runs its entrypoint (`run_all.sh` or `script_tests/run.sh`), then adds every `evals/test_run.py` or `evals/test_grade.py` the entrypoint "does not already run", so each deterministic file runs once. `TESTING.md` `## Running Tests` restates that promise, and the repo rule that makes `make test` the default test run rests on it. The gate that carries the promise was built by [the single deterministic gate task](tests_single-deterministic-gate.md), whose Goal is the outcome this task preserves.

The coverage decision lives in `entrypoint_invokes()`, a hand-written awk scanner built from `scan()`, `tokenize()`, `first_command()`, `is_interpreter()`, `loop_invokes()`, and `segment_invokes()`. It models shell syntax well enough to decide whether an entrypoint executes a file, and each miss costs real time: a miss in one direction drops a suite silently, a miss in the other runs it twice and doubles both its runtime and its failure output. Review rounds on the gate each found a further shape it misread, including a comment-only mention, a here-doc usage line, a variable interpreter, a `for` loop, an arithmetic `(( shift = 1 << 3 ))` command, an arithmetic expression continued across lines, and an invocation behind `then`, `do`, `else`, `elif`, `{`, or `!`.

The class stays open. A shape probe against the committed gate still double-runs an eval file for a launcher with options (`env -i python3 …`, `nice -n 10 …`, `stdbuf -oL …`, `time -p …`, `sudo -u root …`, `uv run --python 3.11 …`), for direct execution (`./evals/test_run.py`), for a file path held in a variable (`SCRIPT=evals/test_run.py` then `python3 "$SCRIPT"`), and for `xargs`. Every added shape is another special case in the same scanner, so the defect returns with the next spelling.

The durable pin for the current behaviour is `tests/lib/test_run_all_gate.py`, whose `ENTRYPOINT_CASES` and `synthetic_listing()` build a scratch tree per entrypoint shape. The reproduction scripts under the ignored `.git_auto_review/` relay are not durable: git ignores that folder and the next run clears it, so a committed test is the only pin that survives.

## Approach

Replace the guess with a declaration the gate reads as plain text.

- Add a per-harness declaration file at `tests/<harness>/evals/covered-by-entrypoint`, listing one eval file name per line for each eval file that harness's entrypoint runs.
- In `tests/run_all.sh`, replace `entrypoint_invokes()` and every awk helper it calls with a read of that declaration. The gate's run set holds each eval file the declaration omits and adds no file it names, so no shell parsing remains anywhere in the coverage decision. `--list` prints the coverage tree rather than the run set: one line per surface, then beneath it that surface's entrypoint when it has one, every `tests/lib/test_*` file for the `lib` surface, and every `evals/test_run.py` or `evals/test_grade.py` the surface carries, so each file is named exactly once, the `lib` surface keeps its `tests/lib/test_*` rows, and a declared eval file runs only through its entrypoint.
- Fail closed on an undecided harness. The check is its own top-level step in `tests/run_all.sh`, run after the surface set is discovered and before `--list` prints or any surface runs, so its `exit 1` sets the script's exit status rather than ending a command substitution inside `harness_names()` or `harness_files()`. When a harness carries an `evals/test_run.py` or `evals/test_grade.py` and no declaration file, that step exits non-zero, prints to stderr the harness name and the declaration path it must create, and applies to `--list` and a run alike, so a new harness states its coverage instead of inheriting a guess. Presence (`[ -f ]`), not size (`[ -s ]`), is the test, so an empty declaration states that the entrypoint runs none of the harness's eval files.
- Migrate every harness that carries an eval file today by writing its declaration from what its entrypoint actually executes, so the gate's run set is unchanged for those harnesses.
- Rewrite the coverage promise in place at each of the three sites that carry it today: the `tests/run_all.sh` header comment (its "does not already run" sentence), `TESTING.md` `## Running Tests` (its "that entrypoint leaves out" sentence), and `tests/README.md` `## Current harnesses` (its "the entrypoint leaves out" sentence), so one canonical statement describes the declaration contract. Replace the sentence that stands at each site rather than adding a new one beside it.
- Replace `ENTRYPOINT_CASES` in `tests/lib/test_run_all_gate.py` with declaration-conformance cases, keeping `synthetic_listing()` as the scratch-tree builder: a declared eval file appears once in the listing and is not run as a separate surface, an undeclared one appears in the listing as a surface the gate runs, and a harness with an eval file and no declaration fails the gate by name. Build one scratch harness per fixture in this explicit set, each with its own eval file and counter file, so the shape coverage `ENTRYPOINT_CASES` pins today survives the replacement as a per-fixture exactly-once check: the six shape classes, each instantiated by a runnable form — launcher options (`launcher`, running `nice -n 10 python3 "$SCRIPT_DIR/evals/test_run.py"`, unprivileged because `nice` only raises niceness), direct execution (`direct`, whose eval file is written with a `#!/usr/bin/env python3` first line and mode 0755), a variable-held path (`var_path`, `SCRIPT="$SCRIPT_DIR/evals/test_run.py"` then `python3 "$SCRIPT"`), `xargs` (`xargs`, `printf '%s\n' "$SCRIPT_DIR/evals/test_run.py" | xargs python3`), arithmetic (`arith_command` and `arith_multiline`), and a reserved word (`reserved_then`, `reserved_do` running `i=0; while [ "$i" -eq 0 ]; do i=1; python3 "$SCRIPT_DIR/evals/test_run.py"; done`, `reserved_group`, `reserved_bang`) — plus the remaining `ENTRYPOINT_CASES` invoking shapes `literal`, `variable`, `loop`, `loop_multiline`, and `semicolon`; each fixture's entrypoint resolves its own directory into `SCRIPT_DIR` before invoking its eval file, so the counter line lands when the gate runs the surface from the scratch root. The comment-only and here-doc usage shapes invoke nothing, so they take no counter check; every fixture harness carries its `evals/covered-by-entrypoint` file, empty for those two shapes, so the fail-closed step accepts every fixture and the scratch tree lists.

The declaration is plain text, so the gate stays on the repo's standing toolchain with no new dependency and no hidden state.

**Out of scope:** Rewriting the behavioural eval runners or their `--vendor` handling; this task changes only the aggregate gate's deterministic coverage decision.

## Acceptance

- `bash tests/run_all.sh --list` names each path that `ls tests/*/evals/test_run.py tests/*/evals/test_grade.py` finds exactly once, and a command that counts its occurrences in the listing reports one per file. Beneath the `lib` surface it names every path that `ls tests/lib/test_*` finds exactly once, and `python3 tests/lib/test_run_all_gate.py` passes with its `listing matches every tests/lib/test_* file on disk` check green.
- One fixture harness per fixture in the explicit set `## Approach` enumerates — `launcher` (launcher options), `direct` (direct execution), `var_path` (a variable-held path), `xargs`, `literal`, `variable`, `loop`, `loop_multiline`, `semicolon`, `arith_command`, `arith_multiline`, `reserved_then`, `reserved_do`, `reserved_group`, and `reserved_bang` — each harness's declaration naming that file, is listed with its entrypoint and its declared eval file, each named exactly once; `--surface <fixture>` runs only that fixture's entrypoint, and each fixture's eval file appends one line to its own counter file that the check reads and finds holding exactly one line, so every listed shape is proven to invoke its file exactly once. The comment-only and here-doc fixtures each carry an empty declaration, and the scratch tree listing exits 0 with each of their eval files named as a surface the gate runs.
- In a scratch tree holding a fixture harness that carries an eval file and no declaration, both `bash tests/run_all.sh --list` and `bash tests/run_all.sh` exit non-zero, and each writes a stderr message naming that harness and the declaration path it must create.
- `entrypoint_invokes()` and the helpers `scan()`, `tokenize()`, `first_command()`, `is_interpreter()`, `loop_invokes()`, and `segment_invokes()` are absent from `tests/run_all.sh`, and its header comment states the declaration contract as the only coverage rule.
- `TESTING.md` `## Running Tests` and `tests/README.md` `## Current harnesses` each state the declaration contract as the only coverage rule, and neither keeps its superseded "leaves out" phrasing; the "does not already run" phrasing appears nowhere in `tests/run_all.sh`.
- `tests/lib/test_run_all_gate.py` exercises the three declaration cases above and fails when the declaration read is inverted, proven by running it against a scratch copy of the gate with that read inverted.
