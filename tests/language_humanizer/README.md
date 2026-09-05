# tests/language_humanizer/

Pattern A (skill-creator-aligned) harness for the `language_humanizer` skill
in the `ai_editorial` plugin. The skill ships no bundled scripts, so there is
no `script_tests/` layer here. The whole harness is behavioral.

```text
tests/language_humanizer/
├── README.md            # this file: what the harness covers and why
├── RUNBOOK.md           # how to run it and how to read the result
├── results/             # one run-<ts>.{json,md} per recorded measurement
├── evals/
│   ├── evals.json       # canonical schema + the full expectation list per scenario
│   ├── stage.sh         # stage one scenario, print the agent-ready inputs
│   ├── grade.py         # deterministic grader (word counts, ledger items, shape)
│   ├── judge.py         # LLM grader for the assertions no regex can settle
│   ├── run.py           # multi-pass runner: worker → grade → judge → aggregate
│   └── fixtures/<id>/setup.sh
└── workspace/run-<ts>/<scenario>/pass-<n>/
```

## What it measures

The skill's load-bearing claim is that a rewrite gets plainer *without* losing
anything: every condition, requirement strength, number, actor, and causal
joint reaches the delivered text, while the text itself comes in no longer
than the draft it replaced. Three scenarios put that claim under pressure from
three directions.

| Scenario | Path | The pressure |
| --- | --- | --- |
| `fidelity_padded` | rewrite | A 390-word padded status update carrying nine load-bearing items. A faithful restatement of all nine needs ~80 words, so the fixture's content is well under half its length. A rewrite has ample room to hit the 75% ceiling *and* keep everything, which makes any dropped item a real failure rather than a length casualty. |
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

The passes run **concurrently** instead (default five at a time), which is what
keeps a fifteen-pass measurement inside ten minutes. Every pass stages its own
sandbox and writes only inside it, so concurrency costs nothing in isolation;
the shared model endpoint is the only contended resource, and `--workers 1`
restores the serial path when a latency reading matters.

## How the two graders split the work

`grade.py` owns everything a regex can settle, and owns it deterministically:
word counts on both sides of every ratio, presence of each ledger item
(names, dates, thresholds with their units, `must` / `should`, the exception
clause, the causal joint), the bullet-cascade shape, a filler-phrase list, and
two harness-integrity checks (the source document came out untouched, and
`delivered.md` was written).

`judge.py` owns the rest of each scenario's named assertions: "reads
plainly", "strength and scope unchanged in context", "opens with its main
point", and "no invented content". It makes one pinned-sonnet call per pass
against a refute-biased rubric: fail the assertion unless the delivered text
plainly satisfies it. Both graders' verdicts gate the pass; a pass is clean only when
every assertion from both sides held.

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

Model policy follows the tree-wide convention in `tests/CLAUDE.md`: the skill
under test runs on `claude-sonnet-4-6`. The judge is pinned to the same model
so a rubric verdict does not drift with the host session, which is the one
place this harness extends the convention. The other harnesses keep their
meta level model-free because their grading is fully deterministic.
