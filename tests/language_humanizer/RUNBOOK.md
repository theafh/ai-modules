# RUNBOOK — tests/language_humanizer/

Operational guide for the `language_humanizer` behavioral harness. Design and
rationale live in `README.md`; this file is how to run it and how to read the
result without misleading yourself.

## Pre-flight: worker auth

Every pass spawns a nested `claude -p` worker, so the CLI's own stored OAuth
login has to be alive — the host session's in-memory auth does not reach a
grandchild process. `run.py` probes it once before spending anything and aborts
with the remediation rather than 401-ing fifteen runs in a row.

```bash
claude auth status          # "loggedIn": false means the run cannot start
claude auth login           # interactive; the fix for an expired session
```

A machine with no interactive login (cron, headless) can park a
`claude setup-token` in the keychain instead; `tests/lib/worker_auth.py` picks
it up and it wins over the stored login. See the auth section of
`tests/CLAUDE.md` for the full picture.

## The recorded measurement

```bash
python3 tests/language_humanizer/evals/run.py
```

That is the deliverable run: three scenarios × five passes, `claude-sonnet-4-6`
for both the worker and the judge. The fifteen passes run five at a time
(`--workers`, default 5), so budget roughly 8–15 minutes rather than the hour
the same run takes serially. Each pass is one worker call plus one judge call
inside its own staged sandbox, which is why they parallelize safely — nothing
is shared but the model endpoint.

`--workers 1` forces the serial path when you want a clean latency reading per
pass or suspect the concurrency itself is distorting results. Going much above
5 mostly buys contention: the passes queue on the model, per-pass duration
climbs, and passes start brushing the 600 s worker timeout, which converts a
throughput problem into void measurements.

Narrower invocations, for debugging rather than for the record:

```bash
# one scenario, one pass — plumbing check, ~2 min
python3 tests/language_humanizer/evals/run.py write_path --passes 1

# prove the plumbing with no model at all: point --claude-bin at a stub that
# writes a canned delivered.md, and confirm a faithful stub passes while a
# lossy one fails on exactly the items it dropped
python3 tests/language_humanizer/evals/run.py --passes 2 --workers 6 \
  --skip-judge --claude-bin /path/to/stub-claude

# mechanical checks only: no judge calls, so the qualitative assertions
# stay ungraded and the run is diagnostic, not a measurement of the bar
python3 tests/language_humanizer/evals/run.py --skip-judge

# re-grade an existing pass without re-spawning the worker (responses are
# immutable once captured)
RUN=tests/language_humanizer/workspace/run-<ts>/fidelity_padded/pass-3
python3 tests/language_humanizer/evals/grade.py fidelity_padded \
  "$RUN/sandbox/proj" "$RUN/sandbox/proj/draft.md"
python3 tests/language_humanizer/evals/judge.py fidelity_padded \
  "$RUN/sandbox/.fixture_pristine" "$RUN/sandbox/proj/delivered.md" \
  "$RUN/response.txt"
```

`--passes` changes the denominator explicitly and the chosen value is recorded
in the summary next to every rate, so a five-pass run and a two-pass debug run
can never be mistaken for each other.

## Reading the result

```text
tests/language_humanizer/workspace/run-<ts>/
├── summary.json                      # per-scenario rate + per-assertion counts
├── summary.md                        # the same, human-readable
└── <scenario>/pass-<n>/
    ├── sandbox/proj/{draft.md|notes.md}   # the fixture, must come out untouched
    ├── sandbox/proj/delivered.md          # the delivered document, verbatim
    ├── response.txt                       # the skill's whole reply
    ├── verdict.json                       # every assertion, both graders
    └── timing.json
tests/language_humanizer/results/run-<ts>.{json,md}   # the recorded copy
```

Read `summary.md` first. Per scenario it reports `pass_rate` over the
denominator, whether the bar was met, and — when it was not — exactly which
assertions diverged and on how many passes. `verdict.json` in the failing pass
carries the judge's one-sentence reason per assertion, which is where a
qualitative failure becomes actionable.

## The three ground-truth signals

1. **`run.py`'s exit code** — 0 only when every scenario passed on every pass.
2. **`summary.json`'s `all_scenarios_met_bar`** — the graded verdict.
3. **`timing.json`'s `claude_rc` per pass** — a worker that timed out or
   crashed makes its pass a void measurement, not a real failure. `run.py`
   already fails such a pass rather than trusting a partial sandbox, so check
   this before reading a red result as a skill regression.

Mid-stream notification lines from the host's wrapper around `claude -p` are
subprocess artifacts, not graded verdicts. Trust the files.

## When a scenario misses the bar

The measurement contract is deliberate: report the measured rate and the
diverging assertions, then decide with a human in the loop. Do not re-run for
a better draw — a 4/5 is data about the skill, and burying it under a fresh
sample is how a real weakness survives. The honest next steps are to read the
failing pass's `delivered.md` and judge reasons, decide whether the skill's
prose or the assertion is wrong, and fix whichever it is.

Diagnose by reading, not by counting. A per-assertion rate says which check
fired, never why. The two graders disagreeing is the loudest signal available:
when the regex fails an item the judge passes in context, suspect the regex
first — that is exactly how the causal-joint pattern was caught scoring 0/5 on
rewrites that had kept the joint in other words.

## Re-grading versus re-running

Correcting a grader is not re-rolling the dice, and the two must not be
confused:

```bash
# re-measure the SAME captured outputs with the current graders
python3 tests/language_humanizer/evals/regrade.py \
  tests/language_humanizer/workspace/run-<ts>

# deterministic checks only, carrying the original judge verdicts forward
python3 tests/language_humanizer/evals/regrade.py \
  tests/language_humanizer/workspace/run-<ts> --skip-judge
```

`regrade.py` spawns no worker: responses are immutable once captured, so this
measures the same sample with a fixed instrument. It writes
`verdict.regrade.json` beside each original and `summary.regrade.{json,md}`
for the run, never overwriting the original — the as-run rates stay readable
next to the corrected ones so the correction is auditable instead of a quiet
edit of history. Report both when a fix moves a number.

One caveat the first correction surfaced: the judge is itself a sampled
instrument, so a re-grade can move a borderline verdict on unchanged input
(`no_invented_content` flipped on one pass between draws). Treat a single-pass
judge flip as noise and a repeated one as signal, and lean on the deterministic
checks for anything a regex can settle honestly.

A fresh `run.py` is the right move only after the *skill* changes — then the
new sample measures the new artifact, and the prior run stays on record as the
before.

## Fixing the skill from an eval result: name the target, not the trap

One measured lesson from the first repair round, worth more than the rule it
confirms. Two edits answered two failures the same way — by naming the shape to
avoid — and they went in opposite directions:

- The requirement-strength rule named the exact substitutions that had softened
  a `must` ("a hard limit", "a firm constraint", "a target"). That fixed it:
  `item_strength_must` went 2/5 → 5/5.
- The lead-with-the-main-point move named the shapes that had buried the point
  ("describing the document itself, counting what it contains, naming the
  occasion it came from"). That made it *worse*: `opens_with_main_point` went
  3/5 → **0/5**, with all five openings landing on the counting shape the edit
  had just made vivid.

The difference is what the named negative gives the model. A banned
*substitution* is a lookup — it recognises "hard limit" and reaches for the
modal instead. A banned *shape* is a template — a sentence pattern it can copy,
and salience beats prohibition. So when an eval failure is about form, spend the
words on a positive specification of what the passage must contain (the first
sentence carries the action, its owner, and its date) and let the banned shape
go unnamed. `ai_instruction_writing`'s positive-carrier rule is the authority
here; this is the measurement that shows what ignoring it costs.

## Scope discipline

Ship the scenarios a change needs in the same session as the change, and re-run
the suite to confirm no regression. Keep unbounded harness growth — backfilling
coverage of behavior this change did not touch, or restructuring the harness —
for its own session.
