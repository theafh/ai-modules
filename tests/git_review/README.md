# tests/git_review/

Regression harness for the `git_review` skill, on Pattern A
(skill-creator-aligned). Two surfaces, each in its own subdirectory.

| Surface | Where | What it covers | Runner |
| --- | --- | --- | --- |
| `script_tests/` | `collect_review_evidence.sh`, `extract_heading_range.sh` | Stdout, exit codes, and the written evidence set over real staged repositories with real remotes | `./tests/git_review/run_all.sh` |
| `evals/` | Skill agent behavior | Target resolution, the fixed report shape, the two verdicts, the criteria ranking, the delta re-review, the publishing gate, and the reviewer-edit gate | `python3 tests/git_review/evals/run.py` |

## script_tests: fast, deterministic, no LLM cost

```bash
./tests/git_review/run_all.sh
```

Nineteen scenarios plus the four plugin-meta lockstep checks. Each one stages a
fresh bare origin and clone under `script_tests/scratch/<id>/`; nothing touches
the host repository's working tree.

The load-bearing ones:

- **s1** asserts the fetch precedes the three-dot diff, read off the ordered
  `steps.log` rather than off the mere presence of a fetch.
- **s2** asserts the manifest names the whole evidence set the skill's
  `<evidence_set>` promises.
- **s4** asserts the two commit walks differ where they must: the merge commit
  is absent from the no-merges walk and present along the first parent.
- **s5** asserts the removed-hunks view and the base-side `git show` of a
  deleted file, which is the evidence the retirement heading rests on.
- **s12** asserts the collector leaves a dirty tree exactly as it found it, with
  no stash, no reset, and no extra worktree.
- **s14** drives a stub `gh` through two pages of review threads and asserts the
  resolved and outdated threads survive into the collected set.
- **s16** through **s19** cover the heading-range helper: inclusive of both named
  headings, the run-to-end form, the error exits, and the same-heading-twice
  case.

## evals: skill behavior, one sonnet worker per eval

```bash
python3 tests/git_review/evals/run.py            # every eval
python3 tests/git_review/evals/run.py 1 13 32    # a subset
python3 tests/git_review/evals/run.py --force 32 # ignore the cached verdict
```

Forty-eight evals over thirty-six fixtures. `evals/README.md` has the per-eval
expectations and the fixture map; `RUNBOOK.md` has the operating notes.

Forge-layer evals stage a stub `gh` on `PATH` that serves fixture JSON and
records every invocation in `gh_calls.log`. That log is half the evidence for
every publishing eval: a run that posts nothing leaves an empty log, and a run
told to resolve one thread leaves exactly one `resolveReviewThread` line.

## What "all green" guarantees here

- **script_tests**: the evidence the model reads is complete, ordered, and
  collected without touching the user's tree.
- **evals**: the agent resolved the target the user named, reported under the
  fixed headings, kept the two verdicts apart, ranked findings against the
  documents the repository declares, and published or edited only where the user
  asked.

It does not guarantee the review's judgement is good on real-world code. That
stays a human question.
