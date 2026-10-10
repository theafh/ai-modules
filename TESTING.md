# Testing

The verification methodology for this repository. It covers the regression
harnesses under `tests/` and the repo-wide linters, and it says what counts as
evidence that a shipped component works.

## Test Design Principles

These four rules are the canonical grader-authoring requirements. A grader
written against them fails only when the behaviour under test is genuinely
wrong, and a failing eval names which behaviour broke.

- **Assert substance, not surface form.** A check names the property that must
  hold and passes on every phrasing and placement that satisfies it. Where a
  rubric permits two repair shapes, the check accepts both. Prose is the most
  variable surface an agent produces, so a grader that pins one sentence fails
  correct work and reads as a regression.
- **Anchor a structured match to its subject.** A check reading a structured
  report field matches the record whose subject is the item under test. A bare
  name match also hits that name inside another record's prose, so subject
  anchoring keeps the grade on the right record.
- **Read prose with wraps collapsed.** A check matching more than one word
  reads the text with hard wraps removed. A wrap falling mid-phrase makes a
  line-based match miss text that is present.
- **Split a long conjunction.** An eval asserting many independent behaviours
  reports per-behaviour results, so one slip localises instead of failing the
  whole eval and hiding what still holds.

Sibling principles that are not part of that four-rule set:

- **Drop negations when scoring a named move.** A run that names a move in
  order to say it did not take that move must not score as having taken it.
- **Prefer a filesystem fact over a claim.** Grade what a run left behind, such
  as a file's bytes, a roster line, or a written brief, before grading what the
  run said about itself. Reach for a response check only where no artifact
  carries the property.
- **State the fail branch.** A check proves the failure case fails, not only
  that the hoped-for direction passes. A fixture that cannot fail measures
  nothing.
- **Stage a sandbox per scenario.** Every harness operates on a fresh temporary
  tree, never on the working checkout. A harness that runs a component against
  a real filesystem carries an explicit escape guard: a copy of the watched
  tree in the eval's temporary directory, compared only for the names the
  sandbox itself contains, or a `git status` of the host checkout where that
  status is the signal. An escape of those watched names fails the scenario
  that caused it. A parallel edit of some other live file stays outside the
  comparison.
- **Declare everything a worker may load, once.** A behavioural eval's worker
  loads only the skills, agents, and styles its runner declares, and that one
  declaration decides what each pass deploys, what the verdict cache hashes,
  and what the worker may read: a pass fails when its worker reads a skill,
  agent, or style file from outside that deployment. Membership follows load
  reach, so the declaration names every artefact a worker may reach by name or
  through a path its prompt gives it, such as a hub skill the subject reads.
  It names a style only where the eval tests that style, because a selected
  style shapes every reply. A change that extends a component's reach extends
  the declaration in the same change. A missing entry fails a pass only when
  the worker reads a copy from outside the deployment. A worker that runs
  without the artefact passes unnoticed, and the cache then replays verdicts
  across edits to it.

## Test Organization

One subdirectory per skill under test, at `tests/<skill_name>/`. The layout,
the two patterns in use, and the per-harness inventory live in
[tests/README.md](tests/README.md); the operator guidance for running them
lives in [tests/CLAUDE.md](tests/CLAUDE.md). Keep both current when a harness
is added or changed.

The authored harness is committed. Everything a run regenerates stays local
through `tests/.gitignore`, and the Makefile's `EXCLUDE` prunes the same
subtrees so lint scope matches git scope. The two lists change together.

## Stack and Runner

Make plus POSIX shell plus Markdown, with `jq`, `git`, and Python 3 as the
standing tools the test runners use. Remaining standing tools belong to the
declared toolchain floor the charter names through `make install`.
Bundled-script tests are plain shell. Behavioural evals spawn one worker per
scenario through the runner's vendor switch. The Cursor worker is the default
for those runs because Cursor tests are cheaper and faster: development and
iteration happen on it (`agent -p` on model `auto`), and its results stand on
their own without a matching Claude run. The Claude worker (`claude -p` on
`sonnet`) runs where a test exercises a Claude-specific feature, which the test
names, and otherwise only when the human operator explicitly asks for a Claude
run, which happens from time to time; an agent never runs Claude tests in the
background. Pin the worker for a
run so results stay comparable, and keep grading on the model-free grader.

## Coverage Expectations

A change to a shipped component lands with the tight scenarios that prove its
own new behaviour, plus the existing suite re-run to confirm no regression.
Unbounded harness growth beyond the change, such as backfilling coverage of
pre-existing untested behaviour or restructuring a harness, belongs in its own
session. The boundary is scope, not timing.

Where a task's acceptance names an eval, that eval is part of the change rather
than something to defer. An acceptance names a Claude run only for an eval
that needs a Claude-specific feature, and it names that run through
`--vendor claude`, also on a Claude-only harness whose default is Claude. That
run is part of the change like any other.

## Running Tests

```bash
make lint                                              # markdown, JSON, shell, repo-wide
bash tests/<skill>/run_all.sh                          # that skill's deterministic surface
bash tests/<skill>/script_tests/run.sh                 # the same, where no run_all.sh exists
python3 tests/<skill>/evals/run.py                    # behavioural evals, default vendor
python3 tests/<skill>/evals/run.py <id>               # one eval
python3 tests/<skill>/evals/run.py --force            # ignore recorded verdicts
```

Run behavioural evals without `--vendor`. The default is the Cursor worker
(`agent -p` with model `auto`), because Cursor tests are cheaper and faster
than the Claude worker; the Claude-only harnesses default to Claude and stop
with an error on an explicit `--vendor cursor`. Pass `--vendor claude`
(`claude -p` on `sonnet`) for an eval that needs a Claude-specific feature,
which the eval names, and otherwise only when the operator has explicitly
asked for a Claude run. Pass it on a Claude-only harness too, where it repeats
the default, so every Claude run shows in its command. The verdict cache keys
on the worker model, so a Cursor result and a Claude result stay separate
evidence. Grading stays model-free on either worker.

Trigger evals answer a different question, whether a skill's `description:`
loads it on a realistic message. The trigger evals are Claude-only (the runner
defaults to Claude), so they run on Claude where a change needs the
measurement, through
`python3 tests/trigger_evals/run.py --vendor claude --eval-set <set> --skill <name> --baseline <prior-run>`.

## Re-run Economy

Running a check produces evidence about the state of what it inspects, so it
runs once per that state. Three runs are always sound: the first run in a
session, a run after the inspected state changed, and a standing gate at its
standing moment, such as `make lint` before a commit.

Beyond those, **re-running a check whose inputs did not change is waste, not
rigour.** It returns what the recorded run already returned, and on a sampling
surface it also resamples noise. Spend a run on what is genuinely unknown.
When that run is a behavioural eval, spend it on the Cursor worker (the
default vendor): Cursor tests are cheaper and faster, and the cache
records them under their own model key.

Judge "changed" by whether the change can reach the behaviour under test, not
by whether some byte moved in a watched directory. A recorded verdict stays
evidence when the edit since it was recorded cannot affect that scenario: a
clause added to one section of a skill does not invalidate an eval exercising a
different section, and an edit to one harness's grader does not invalidate
another harness. When the reach is genuinely unclear, re-run; when it is
clearly out of reach, keep the recorded verdict and say which run it came from.

The behavioural runners implement this: `tests/lib/eval_cache.py` records each
graded verdict under a content key and replays it instead of re-spawning a
worker. A cache hit means byte-identical inputs to a run already graded, so it
can never serve a stale pass. Re-grading a captured run against an updated
grader costs nothing and is the right move when the grader changed and the
behaviour did not.

Two things this rule never excuses: skipping a standing gate at its moment, and
skipping a check whose inputs did change. Name the relied-on run whenever a
run is skipped.

An acceptance criterion that mandates a re-run buying no new information is a
defect in the criterion. Rewrite it to name the evidence that would actually
inform the decision, and record why.

## Test Integrity

Code rises to the tests, never the reverse. A failing check is not weakened,
skipped, or removed to get a suite green: fix the component or the fixture
first, and change the check only when the behaviour it pinned is genuinely
superseded.

One distinction matters here, because both look like editing a test. Broadening
a check that pinned one phrasing of a property the component still satisfies is
a grader fix, and it is correct: the check was asserting surface form rather
than substance. Weakening a check so a component that no longer holds the
property passes is the failure this rule forbids. Say which of the two a change
is, and name the evidence, whenever an existing check is edited.
