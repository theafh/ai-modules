---
description: "Isolate the language_humanizer eval worker and judge from host instructions through a shared tests/lib helper, re-measure on Cursor, and keep Claude isolation as compatibility."
scope: tests
created: 2026-10-02T12:56:51
updated: 2026-10-08T22:56:55
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Isolate the language_humanizer eval workers from the host via a shared tests/lib helper, then re-measure

## Goal

The `language_humanizer` behavioural harness measures the skill alone. Its worker
and its judge run through the shared isolation helper
`tests/lib/worker_isolation.py`, under the contract its module docstring states.
A fresh five-pass measurement of the three scenarios under that contract runs on
`--vendor cursor` per `TESTING.md`, and the Claude vendor path keeps the same
helper contract as compatibility.

## Context

- **What the runner does today.** `tests/language_humanizer/evals/run.py` is
  already vendor-aware through `tests/lib/vendor.py`. `run_pass` stages each
  pass's sandbox at `pass_dir / "sandbox"` under the harness's `workspace/`,
  which sits inside the repository, stages the skill into
  `pass_dir / "artefacts"` via `vendor.stage_skill_tree`, and starts the worker
  from that in-repo project directory with `vendor.build_print_cmd`. `judge` in
  `evals/judge.py` starts its own vendor-resolved call without an isolated root
  of its own. The live sandbox still sits inside the repository tree, so host
  standing instructions can still reach the worker.
- **Why isolation matters.** Host settings and standing instruction files carry
  writing rules of their own, so every recorded humanizer measurement so far ran
  under them, in the worker's rewrite and in the judge's verdict alike. That is a
  confound for a skill whose subject is prose. The probes that mapped the Claude
  inheritance path (`--setting-sources`, CLAUDE.md ancestry, deployed output
  styles) are recorded under `### Configuration roots` and
  `### Standing instruction files` on `wiki/entities/anthropic-claude-code.md`
  and under `### A worker inherits the host's instructions unless it is
  isolated` on `wiki/concepts/verification-surfaces.md`. Those Claude mechanisms
  stay the Claude compatibility branch; they are not the reason this harness
  measures on Claude.
- **Cursor-first posture.** `TESTING.md` prefers `--vendor cursor` for behavioral
  runs. This task's proof and re-measurement therefore use Cursor. Claude remains
  available through the same helper for compatibility and for harnesses that
  exercise Claude-only product surfaces such as output-style loading.
- **The shared isolation helper.** This task must follow
  [styles_natural-language-connected-prose.md](styles_natural-language-connected-prose.md),
  because it imports `tests/lib/worker_isolation.py`, which that task builds. The
  helper creates a fresh sandbox root under the system temporary directory,
  raises its create-root refusal for a root under the home directory or inside a
  git repository, and returns the worker arguments for the vendor a caller
  passes. Its module docstring states the isolation contract, including the
  Cursor sources that stay outside it.
- **Existing shared wiring.** `tests/lib/vendor.py` is the shared worker
  abstraction. In the docs pass, rewrite the universal skill path-read rule that
  today assumes a staged copy under each eval's `artefacts/` beside the sandbox
  (`### Skill and agent loading` in `tests/AGENTS.md`, and the matching artefacts
  sentence under `### Model policy` in `tests/CLAUDE.md`) into one canonical
  rule that also covers a harness that copies the skill into an isolated sandbox
  and path-reads that copy.
- **The skill under test.** `evals/stage.sh` points `skill_path` at
  `plugins/ai_editorial/skills/language_humanizer/SKILL.md`, which `main`
  carries since the `ai_editorial` plugin merged, so every Acceptance item that
  starts a worker, and the Approach skill-copy that feeds those items, runs on
  an ordinary checkout.

## Approach

1. **Run each pass outside the repository.** In `run_pass`, stage the sandbox
   under an isolated root from the helper, copy the skill file under test into
   that sandbox, and point the worker prompt at the copy, so that the worker
   reads nothing inside the repository. Start the worker with cwd at the staged
   `sandbox_proj` (the `proj/` directory under that isolated root), carrying the
   helper's arguments for the resolved vendor; grade against that same project
   directory there; then copy the finished sandbox to `pass_dir / "sandbox"`, so
   that the `workspace/` layout the runbook describes and `regrade.py` keep
   working. Remove the temporary root afterwards.
2. **Isolate the judge.** In `judge`, start the judge call from an isolated root
   of its own with the helper's arguments for the resolved vendor, and remove
   that temporary root after the call.
3. **Document the isolation.** Rewrite the universal skill path-read passages so
   one canonical rule remains: workers path-read the skill under test from a staged
   copy that sits outside any graded tree, either under the eval's `artefacts/`
   directory beside the sandbox or inside an isolated sandbox when the harness
   copies the skill there (as this harness does), and never from a graded tree.
   Apply that rewrite at `### Skill and agent loading` in `tests/AGENTS.md` and
   at the matching artefacts sentence under `### Model policy` in
   `tests/CLAUDE.md`, keeping the two guides lockstep. Rewrite the passages of
   the harness `README.md` and `RUNBOOK.md` that describe where a pass runs, so
   that they say the live sandbox sits under the system temporary directory and
   is copied into `workspace/` afterwards.
4. **Re-measure on Cursor.** On a checkout that carries the skill file, run the
   three scenarios under isolation over the harness's five-pass denominator with
   `--vendor cursor`, keeping the harness's measurement contract for a scenario
   that misses the bar. Write `results/isolation-comparison.md`, giving for each
   scenario and assertion the isolated rate beside the rate of the latest
   non-regrade `results/run-*` that reports that scenario, naming that baseline
   run's identifier and denominator.

**Out of scope:**

- Moving the other behavioural runners onto the helper, since this task changes
  the `language_humanizer` runner and judge only.
- Changing the skill, its fixtures or its grader rubrics.
- Building the isolation helper, its unit tests and its `### Worker isolation`
  section, and proving Claude output-style loading, all of which
  [styles_natural-language-connected-prose.md](styles_natural-language-connected-prose.md)
  owns.
- Turning off Cursor User Rules or deployed user-level skills, which the
  helper's isolation contract names as Cursor sources outside its reach.
- Deciding what becomes of the earlier, unisolated results, which the comparison
  hands to the user.

## Acceptance

- `run.py` and `judge.py` both import the helper for every vendor they spawn, the
  worker and judge calls use the helper's arguments for the resolved vendor, and
  neither starts a worker or a judge call from a directory the create-root
  refusal rejects.
- A one-pass plumbing run,
  `python3 tests/language_humanizer/evals/run.py write_path --passes 1 --vendor cursor`,
  leaves `git status` exactly as it was before the run, leaves no directory with
  any isolation prefix `run.py` or `judge.py` passes to the helper under the
  system temporary directory, and leaves a copied `pass_dir/sandbox` from which
  `regrade.py` re-grades the pass.
- The worker prompt points at a copy of the skill file inside the sandbox rather
  than at the path inside the repository.
- The harness `README.md` and `RUNBOOK.md` describe the isolated staging, with no
  passage left saying that a pass runs inside `workspace/`. The same docs pass leaves one canonical skill path-read
  rule in `tests/AGENTS.md` `### Skill and agent loading` and the matching
  artefacts sentence under `tests/CLAUDE.md` `### Model policy`: a staged copy
  outside any graded tree, either under the eval's `artefacts/` beside the
  sandbox or inside an isolated sandbox when the harness copies the skill there,
  with no remaining passage that mandates `artefacts/`-beside-sandbox as the
  only path-read location.
- `results/` holds the isolated five-pass Cursor run of all three scenarios, and
  `results/isolation-comparison.md` sets each scenario's per-assertion rates
  beside those of the latest non-regrade `results/run-*` that reports that
  scenario, naming that baseline run's identifier and denominator. Where a rate
  moved, the comparison names the assertions that moved and leaves the
  disposition of the earlier results to the user.
