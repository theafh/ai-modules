# tests/

Regression test harnesses for the skills shipped in this repo. The
authored harness is committed: `evals.json`, fixtures and their
`setup.sh` stagers, the run and grade scripts, and each subdirectory's
`README.md` and `RUNBOOK.md`. Everything a run regenerates stays local
via `tests/.gitignore` — `workspace/`, `scratch/`, `.eval_cache/`,
`__pycache__/`, the per-run logs and reports under `results/`, and the
staged `wiki/layer2/{AS,L2,WI,WU}-*` sandboxes. The Makefile's lint
targets prune exactly those regenerated subtrees, so `make lint` covers
the committed harness and nothing else. Keep the two prune lists in
step whenever either changes.

## Convention

One subdirectory per skill under test. Two patterns are in use:

### Pattern A — skill-creator-aligned (preferred for new harnesses)

Skill-level evals follow Anthropic's official `skill-creator` skill:
canonical `evals/evals.json` schema, free-form `expectations` strings
graded by a subagent, `workspace/iteration-N/eval-<id>/{with_skill,
without_skill}/` runtime layout. Bundled-script unit tests sit
alongside in `script_tests/` (not a "layer" of the eval — just plain
shell unit tests for the scripts the skill ships).

```text
tests/<skill_name>/
├── README.md
├── RUNBOOK.md
├── run_all.sh                    # bundled-script unit tests entrypoint
├── results/
├── script_tests/
│   ├── run.sh
│   └── scratch/<id>/             # transient per-scenario sandboxes
├── evals/                        # skill-creator
│   ├── README.md
│   ├── evals.json                # canonical schema
│   └── fixtures/<name>/setup.sh  # per-eval sandbox stagers
└── workspace/                    # skill-creator run output
    └── iteration-N/
```

Reference: `skill-creator/SKILL.md` and `skill-creator/references/schemas.md`
(installed under `~/.claude/plugins/.../skill-creator/`).

### Pattern B — home-grown two-layer (legacy)

Pre-dates the skill-creator alignment. Mature in `tests/wiki/`.

```text
tests/<skill_name>/
├── layer1/      # script-level, deterministic, bash + Python
└── layer2/      # skill-level, custom orchestrator + typed assertions
```

Migrate to Pattern A on the next significant iteration of the harness;
don't bring up new harnesses under Pattern B.

## Current harnesses

- **`wiki/`** — Pattern B. Full Layer 1 (deterministic, `layer1/run.sh`
  prints its own scenario tally) + Layer 2 (every scenario in
  `layer2/evals.json`, each over that file's top-level `passes`
  denominator). Mature, working.
- **`git_commit/`** — Pattern A. `script_tests/` implemented (16
  bundled-script scenarios). `evals/` holds nine behavioral evals with
  fixtures, run through a sonnet-pinned `evals/run.py` with a
  deterministic `grade.sh`. See `evals/README.md`.
- **`git_checkout/`** — Pattern A. `script_tests/` implemented (14
  bundled-script scenarios over staged clones with real remotes).
  `evals/` defined (7 evals over 5 fixtures) and run operator-driven
  in a session: stage a fixture, let the agent run the skill, inspect
  the repository and transcript against the expectations. See
  `evals/README.md`.
- **`git_review/`** — Pattern A. `script_tests/` implemented (20
  bundled-script scenarios over staged clones with real remotes, plus the
  plugin-meta lockstep checks): the ordered evidence collection, the two
  commit walks, the base-side versions of deleted files, the test merge, the
  head-against-its-upstream relationship the fast-forward decision rests on,
  the stub-`gh` thread pagination, and the heading-range helper. `evals/` holds 48
  behavioral evals over 36 fixtures, run through a sonnet-pinned
  `evals/run.py` with a deterministic `grade.sh`. Forge fixtures put a stub
  `gh` on `PATH` that serves fixture JSON and logs every call, so a run that
  posts nothing is provable. See `evals/README.md`.
- **`language_humanizer/`** — Pattern A, behavioral only (the skill
  ships no scripts, so there is no `script_tests/`). 3 scenarios × a
  fixed 5-pass denominator, graded by a deterministic `grade.py` plus a
  refute-biased `judge.py`. No verdict cache: the repeated draws are
  the measurement.
- **`task/`** — Pattern A. The `task_*` family hub, holding both
  deterministic surfaces: `script_tests/run.sh` unit-tests the bundled
  `lint.py`, `discover_tasks.sh`, and `init_tasks.sh` (54 scenarios), and
  `script_tests/contract_run.sh` asserts the family contract across the
  hub, its siblings, and the family agents. `run_all.sh` drives both and
  aggregates their exit codes. `evals/` holds a behavioral eval per family
  member, run out-of-band via `evals/run.py`.
- **`task_create/`** — Pattern A, behavioral only (the skill drives the
  base `task` skill's scripts, covered under `task/script_tests/`). Three
  staged evals over the base **Decide or label** rule as the create path
  applies it: `reconcile-recorded` (evidence-settled fork, no label),
  `labeled-why-open` (no tier settles it), and `guardrail-bound-surface`
  (every path crosses a boundary). Grades the written task file and the
  worker's captured response, since the rule obliges both.
- **`task_auto_check/`** — Pattern A. `script_tests/` covers the static
  skill contract; `evals/` drives the autonomous readiness loop over staged
  fixtures — repair-to-ready, the gate / verifier / drift stop conditions,
  and the mechanical lint cleanup — through a sonnet-pinned `run.py` with a
  deterministic `grade.sh`. The deepest loop here, so `RUNBOOK.md` records
  the cheap-first fixture probe that keeps a fixture bug off the full run.
- **`guardrail_audit/`** — Pattern A, prose-only skill. `script_tests/`
  covers the static SKILL.md / registration contract; `evals/` has five
  staged fixtures (presence-gating, doc-vs-doc, doc-vs-code retrofit,
  grounded TESTING.md proposal, multi-project nature mismatch) with
  byte-identity grading and a sonnet-pinned `run.py`.
- **`skill_doctor/`** — Pattern A. `script_tests/` cover
  `resolve_scope.py` (hub-with-`<family>` and prefix-only) and
  `discovery_safety.py` (risky sibling-description outlier,
  dual-audience gaps, both sides of the block-versus-warn severity
  line including a fixture per promised blocking class, and
  false-positive regression guards over real shipped description
  shapes), plus the static SKILL.md contract. `evals/` has three
  staged fixtures driven by a sonnet-pinned `run.py` with a
  deterministic `grade.sh`; `run_all.sh` drives only the script tests.
- **`git_refresh/`** — Pattern A. `script_tests/` covers the bundled
  `refresh_repo.sh` over staged repositories. `evals/` defines four
  behavioral evals with fixtures but ships no runner, so an eval sweep
  reaches only the script surface here.
- **`ai_instruction_writing/`** — Pattern A, script-only. The skill ships
  no bundled scripts, so `script_tests/` asserts its static prose
  contract instead.
- **`charter_guardrail/`** — Pattern A, script-only. `script_tests/run.sh`
  greps the guardrail doc set against its documented contract. No
  `run_all.sh`; run `script_tests/run.sh` directly.
- **`format_rust/`** — Pattern A, script-only. `script_tests/run.sh` greps
  SKILL.md and the plugin README for the error-versus-invariant model,
  panic discipline, and clippy wiring. No `run_all.sh`.
- **`update_changelog/`** — Pattern A, script-only. `script_tests/` covers
  the deterministic parts of the incremental day-grouping walk.
- **`deployment/`** — Pattern A, script-only, and the one harness that
  belongs to the deploy script rather than to a skill. `script_tests/run.sh`
  covers the OpenCode, Antigravity, and bytecode-exclusion paths;
  `script_tests/style_run.sh` covers output-style deployment and uninstall.
- **`trigger_evals/`** — a different axis from the rest: whether a skill's
  `description:` makes Claude load it on a realistic user message. Driven
  by the local `run.py` wrapper, with hermetic unit tests for the
  detector under `script_tests/`.

## Adding a harness for a new skill

1. Create `tests/<skill_name>/` with Pattern A's layout.
2. Implement `script_tests/run.sh` first if the skill ships bundled
   scripts — cheap, deterministic, fast feedback on the mechanical
   surface. Stage a fresh sandbox per scenario; never operate on the
   host repo's working tree.
3. Author `evals/evals.json` and per-eval fixture `setup.sh` scripts
   for any skill-prose behavior that scripts can't verify (message
   format discipline, fallback discipline, user-prompting behavior,
   skill triggering). Run via skill-creator's `scripts.run_eval`.
