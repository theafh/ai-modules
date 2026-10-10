# tests/language_humanizer/

Pattern A (skill-creator-aligned) harness for the `language_humanizer` skill
in the `ai_editorial` plugin. The skill ships no bundled scripts, so its
deterministic surface is a static contract over `SKILL.md` and its
registration, plus unit tests that prove the grader can fail. `run_all.sh`
drives both. The measurement itself is behavioral and runs out-of-band
through `evals/run.py`.

```text
tests/language_humanizer/
├── README.md            # this file: what the harness covers and why
├── RUNBOOK.md           # how to run it and how to read the result
├── run_all.sh           # the deterministic surface: static contract + grader tests
├── script_tests/
│   └── run.sh           # static SKILL.md / README / registration contract
├── results/             # one run-<ts>.{json,md} per recorded measurement
├── evals/
│   ├── evals.json       # canonical schema + the full expectation list per scenario
│   ├── stage.sh         # stage one scenario, print the agent-ready inputs
│   ├── grade.py         # deterministic grader (word counts, ledger items, shape)
│   ├── test_grade.py    # grader unit tests: a faithful rewrite passes, each lossy one fails
│   ├── judge.py         # LLM grader for the assertions no regex can settle
│   ├── run.py           # multi-pass runner: worker → grade → judge → aggregate
│   ├── regrade.py       # re-grade a captured run with the current graders
│   └── fixtures/<id>/setup.sh
└── workspace/run-<ts>/<scenario>/pass-<n>/   # each pass's record, sandbox copied in
```

## What it measures

The skill's load-bearing claim is that a rewrite gets plainer *without* losing
anything: every condition, requirement strength, number, actor, and causal
joint reaches the delivered text, while the text itself comes in no longer
than the draft it replaced. Three scenarios put that claim under pressure from
three directions.

| Scenario | Path | The pressure |
| --- | --- | --- |
| `fidelity_padded` | rewrite | A 390-word padded status update carrying thirteen load-bearing items: two actors, one deadline, two thresholds, the current latency figure, two musts, two shoulds, one exception, and two causal joints. A faithful restatement of all thirteen needs under 80 words, which `evals/test_grade.py` proves stays under half the fixture. A rewrite has ample room to hit the 75% ceiling *and* keep everything, which makes any dropped item a real failure rather than a length casualty. |
| `compression_trap` | rewrite | One long paragraph whose argument lives entirely in its transitions, plus one hedged uncertain claim. The two obvious "readability" moves, bulleting the paragraph and asserting the hedge flatly, both destroy meaning. |
| `write_path` | write | Unordered retro notes carrying five load-bearing items among the noise, with no draft length to measure against. Tests that the write path leads with the main point and adds no filler of its own. |

## The measurement contract

Each scenario runs over a **fixed denominator** of passes (default 5). The
recorded per-scenario pass rate over that denominator is the deliverable, and
the bar is every assertion holding on every pass. A scenario that misses the
bar is reported with its measured rate and the diverging assertions. The
report hands the disposition to the operator instead of re-rolling the dice
for a friendlier draw.

There is deliberately **no verdict cache** here, unlike `tests/git_commit/`
and `tests/task/`. Those harnesses cache to avoid paying for a re-run whose
inputs did not change; here the repeated independent draws *are* the
measurement, so replaying a stored verdict would report a sample size the run
never took.

The passes run **concurrently** instead (default four at a time), which is what
keeps a fifteen-pass measurement inside ten minutes. Every pass runs in its own
isolated sandbox root and writes only inside it, so concurrency costs nothing;
the shared model endpoint is the only contended resource, and `--workers 1`
restores the serial path when a latency reading matters.

## Isolation from the host

The skill's subject is prose, and the host's standing-instruction files carry
writing rules of their own, so a worker that can see them measures the host as
much as the skill. Every pass therefore runs under the shared
`tests/lib/worker_isolation.py` contract. `run.py` stages each pass's sandbox
under a fresh root in the system temporary directory, outside the home
directory and outside any git repository, and starts the worker from the
staged project with the helper's arguments for the resolved vendor. `judge.py`
starts every judge call from an isolated root of its own in the same way.
Once a pass is graded, `run.py` copies the finished sandbox into
`workspace/run-<ts>/<scenario>/pass-<n>/sandbox/` and removes the temporary
root, so the live sandbox never sits inside the repository while the copy
stays available to `regrade.py`.

The skill under test reaches the worker through the shared micro-deployment
in `tests/lib/micro_deploy.py`. `run.py` calls it with the staged project (not
the root) as the sandbox project, so the deploy script builds the skill into a
scratch home that hides the user's deployed skills on both vendors, and the
worker's prompt names the `SKILL.md` path from the returned path map. The
worker starts with `worker_isolation.isolation_args(vendor)` as its extra
arguments, so the host-instruction isolation stays in force alongside the
scratch home. Each pass also records `artefacts_read_from_micro_deployment` in
`timing.json` and `verdict.json`, and a read of any skill, agent, or style file
outside the scratch home or the sandbox fails the pass.

Before the scratch home is removed, `run.py` copies the deployed `SKILL.md`
from the path map into `<root>/language_humanizer/SKILL.md`. That copy
travels into `pass-<n>/sandbox/language_humanizer/SKILL.md`, so every pass
records exactly which `SKILL.md` it measured. User Rules, which Cursor keeps in
its settings, stay outside the helper's reach.

## How the two graders split the work

`grade.py` owns everything a regex can settle, and owns it deterministically:
word counts on both sides of every ratio, presence of each ledger item
(names, dates, thresholds and the current measurement with their units,
`must` / `should`, the exception clause, the causal joint), the bullet-cascade
shape, a filler-phrase list, and two harness-integrity checks (the source
document came out untouched, and `delivered.md` was written).
`evals/test_grade.py` stages each real fixture, feeds the grader a faithful
rewrite that must pass every check, then lossy variants that must fail on
exactly the check naming what they dropped, so a grader that cannot fail is
caught before a worker call is spent on it.

`judge.py` owns the rest of each scenario's named assertions: "reads
plainly", "strength and scope unchanged in context", "opens with its main
point", and "no invented content". It makes one isolated call per pass on the
vendor-resolved judge model against a refute-biased rubric: fail the assertion
unless the delivered text plainly satisfies it. Both graders' verdicts gate the
pass; a pass is clean only when every assertion from both sides held.

The dividing line is *fact versus meaning*, and the first run taught it the
hard way. Two assertions started out as keyword proxies for meaning and both
misfired: counting `because|since|so that|therefore` scored the causal joint
0/5 against rewrites that said "so missing it is not an option", and counting
the source's own transition words failed rewrites that substituted "yet" for
"but" while keeping every joint. Both moved to the judge, which names the
specific joints and accepts any wording that carries them, and both grew
*stricter* in the move: the judge now fails a joint that survives only as
juxtaposition with no connective. Keep new assertions on the right side of
that line: a regex may ask whether a string is present, never whether meaning
survived.

Model policy follows the tree-wide convention in `tests/CLAUDE.md` /
`tests/AGENTS.md` via `--vendor`: the skill under test runs on `auto` (Cursor)
or the latest `sonnet` (Claude). The recorded measurement runs on Cursor, per
`TESTING.md`, and it stands without a matching Claude run. A Claude-pinned
sample runs under the same isolation contract, and only when the operator
explicitly asks for one. The judge uses `auto` on Cursor and inherits
the default model on Claude, so it is no longer pinned to the worker model.
Other harnesses keep their meta level model-free because their grading is
fully deterministic.
