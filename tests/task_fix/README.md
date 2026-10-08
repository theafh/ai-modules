# tests/task_fix: repeated-link disposition harness

Pattern A (skill-creator-aligned), behavioral only. `task_fix` ships no
scripts of its own. It drives the base `task` skill's `discover_tasks.sh` and
`lint.py`, which `tests/task/script_tests/` already covers, so there is no
`script_tests/` and no `run_all.sh` here. The static family contract across
`task_fix` and its agents is asserted in `tests/task/script_tests/contract_run.sh`
and `tests/task_auto_check/script_tests/run.sh`.

| Surface | Where | What it covers | Runner |
| --- | --- | --- | --- |
| Skill behavior | `evals/` | the base `<lint>` **Repeated-link react protocol** as the inline `task_fix` path applies it: reorganize live bodies, surface what would change Goal or the Acceptance contract, count the archive (stage → agent → grade) | `python3 tests/task_fix/evals/run.py` |

The whole-family behavioral suite keeps its own `fix`, `fix_coherence`, and
`fix_coherence_selector_*` evals in `tests/task/evals/` for the rest of the
`task_fix` surface. This harness is the one that exercises the repeated-link
disposition.

## What the four evals prove

The protocol says the finding is resolved when the body's account of the
counted target sits in one place, not when the link count drops. Each eval
stages one disposition and grades both surfaces the protocol obliges: the task
file's bytes, and the run's per-finding disposition line.

- **`regroup_live_skip_archived`**: a live task narrates one handoff in `##
  Goal` and `## Context`, each site carrying its own link, and an archived task
  links one target twice. The live account gathers into `## Context`, Goal keeps
  stating what the task delivers, `updated` is bumped, and the archived body
  stays exactly as archived and is reported as a count.
- **`regroup_state_and_edit_site`**: `## Context` describes what a reference
  page says today and `## Approach` edits one of its sections, each passage
  with its own link. The page's current state and the edit belong together, so
  the run gathers them into one passage under one link, bumps `updated`, keeps
  the meaning of Goal and the Acceptance contract, and reports the line as
  regrouped. A run that reports the finding kept, or leaves the file as staged,
  fails this eval: judging each link on its own merit is the reading the
  reorganization rule retired.
- **`surfaced_acceptance_contract`**: the two sites are `## Goal` and one
  `## Acceptance` item, and `## Context` says nothing about the sibling. Both
  copies state one account, that the linked task sets the retention window, and
  each is load-bearing for its own section: Goal states the outcome, the item
  states the check that proves it. Neither section can absorb the other's copy,
  so the body stays byte-identical and the line reads surfaced. An agent that
  strips a link while both clauses stay fails this eval too: that moves no
  material and only hides the warn.

  The absent `## Context` copy is the point, not an oversight. Six staged
  designs established that the surfaced class protects `## Goal` and the
  Acceptance contract only, so any duplication that includes a `## Context`
  copy has a benign escape: trim Context, which costs no section its contract.
  A surfaced case therefore has to sit between Goal and Acceptance with nothing
  in Context to give up. Earlier Goal-and-Context designs failed for the
  matching reason, with the worker keeping the code reference Goal needs and
  dropping the separable task reference.
- **`regroup_same_paragraph`**: one `## Context` paragraph links the sibling
  twice and nothing else in the body names it. The material is already
  gathered, so the protocol's one-paragraph case applies: the run names the
  sibling again in plain text inside that paragraph, the warn clears, every
  other section stays as staged, and the line reads regrouped. A run that keeps
  or surfaces the finding fails, and so does one that moves material out of the
  paragraph.

## Running

```bash
python3 tests/task_fix/evals/run.py
```

These consume LLM tokens. See `evals/README.md` for the stage → agent → grade
recipe, the verdict cache, and how the report half is graded.

## Trigger evals

Routing for `task_fix` is covered by the family set at
`../trigger_evals/task.json`, not here.
