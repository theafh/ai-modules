# tests/agent_spinner

Local Pattern A harness for the `agent_spinner` skill. The skill is prose-only
and bundles no scripts, so `script_tests/` covers the static contract instead
of a bundled-script surface.

```text
tests/agent_spinner/
├── README.md
├── RUNBOOK.md
├── run_all.sh                   # static contract entrypoint
├── script_tests/run.sh          # SKILL.md, references, greps, registration
├── evals/
│   ├── README.md                # the signal each eval uses, and the runner modes
│   ├── evals.json
│   ├── stage.sh
│   ├── grade.sh
│   ├── run.py                   # vendor worker runner with inline-body, second-turn, staged-agent, and tool-record modes
│   ├── test_run.py              # runner plumbing against a stub worker
│   └── fixtures/<id>/setup.sh
└── workspace/                   # run output (gitignored)
```

## Surfaces

- **script_tests**: frontmatter and the two size budgets, one block per named
  contract, the six shape tags with their four elements each, the capability
  probe's four capabilities and its deployment-versus-callability rule, the
  per-harness greps that must return nothing, the one-way advisory direction
  (no shipped surface cites `agent_spinner` back), the reference set and its
  action-first templates, the trigger eval set, registration lockstep across
  both plugin manifests, both marketplaces, both READMEs, and the wiki concept
  page, and `script_tests/` proves the eval runner's stop on a failed or
  empty stage through `tests/lib/check_stage_guard.py`. `evals/test_run.py`
  proves the runner's modes and wiring against a stub worker.
- **evals**: every id in `evals.json` (26 today). Each behavioural eval
  stages one behaviour, and the `smoke_*` evals check the runner's modes. Every
  compound acceptance bullet was split into its own eval, so a failure names
  one behaviour rather than a conjoined verdict.

## How a no-delegation-surface fixture stays honest

`jq -r '.evals[] | select(.harness.needs_real_absence == true) | .id' tests/agent_spinner/evals/evals.json`
lists the evals that need a host exposing no callable spawn surface. The runner withholds the spawn class under
its withheld-tool rule: no Cursor deny entry withholds the spawn tool, so the
class is a declared absence in the prompt on both vendors. That is what makes
the inline-floor and governed-stop evals measure anything. The `## Runner
modes` section of `evals/README.md` holds the full account.

## What "outside the sandbox" means here

Every fixture stages two trees: `proj/`, which the worker runs in, and
`outside/`, a canary tree the run has no reason to touch. `grade.sh` hashes
both, and `run.py` brackets each eval with an owned-name host-status guard
through `tests/lib/eval_runner.py`'s before/after hooks: the before hook
snapshots the host checkout's `git status --porcelain`, and the after hook
blames the eval only for new host paths whose basename appears in that eval's
preserved sandbox copy. The evals run at the default 4 workers, so
overlapping siblings stay attributable: an escape fails the eval whose sandbox
names it, and a sibling's own work never does. The run set is every id in
`evals.json` (26 today), derived at startup rather than frozen. The run's own
instrumentation output under `proj/.agent_spinner/` is excluded from the
`proj/` inventory on both sides, so writing a roster never reads as editing
the corpus.
