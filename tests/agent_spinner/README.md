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
│   ├── README.md                # the signal each eval uses, and why
│   ├── evals.json
│   ├── stage.sh
│   ├── grade.sh
│   ├── run.py                   # vendor worker runner (Cursor by default)
│   └── fixtures/<id>/setup.sh
└── workspace/                   # run output (gitignored)
```

## Surfaces

- **script_tests**: frontmatter and the two size budgets, one block per named
  contract, the six shape tags with their four elements each, the capability
  probe's four capabilities and its deployment-versus-callability rule, the
  per-harness greps that must return nothing, the one-way advisory direction
  (no shipped surface cites `agent_spinner` back), the reference set and its
  action-first templates, the trigger eval set, and registration lockstep
  across both plugin manifests, both marketplaces, both READMEs, and the wiki
  concept page.
- **evals**: 21 staged fixtures, one per independently staged behavioural
  Acceptance item in the task that introduced the skill. Every compound
  acceptance bullet was split into its own fixture, so a failure names one
  behaviour rather than a conjoined verdict.

## How a no-delegation-surface fixture stays honest

Seven evals need a host that exposes no callable spawn surface. The runner
denies the spawn tool on the worker's own command line for those, so the
absence is a harness state the worker runs into rather than a claim a note
makes at it. That is what makes the inline-floor and governed-stop evals
measure anything.

## What "outside the sandbox" means here

Every fixture stages two trees: `proj/`, which the worker runs in, and
`outside/`, a canary tree the run has no reason to touch. `grade.sh` hashes
both, and `run.py` additionally brackets each eval with a `git status
--porcelain` of the host checkout, failing the eval that changed it. The
run's own instrumentation output under `proj/.agent_spinner/` is excluded from
the `proj/` inventory on both sides, so writing a roster never reads as editing
the corpus.
