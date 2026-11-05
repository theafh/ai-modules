# guardrail_audit RUNBOOK

## Static contract

```bash
bash tests/guardrail_audit/script_tests/run.sh
```

That entrypoint also runs `sandbox_git_isolation.sh`, which proves fixture
`git commit` cannot land on the host checkout (happy-path stage + refused
orphan/broken `.git` cases).

## Behavioral evals (Cursor worker by default)

Staging needs a working `git init` inside the sandbox (writes under
`<sandbox>/proj/.git`). Run fixture staging outside a filesystem sandbox
that blocks `.git` creation, or the helpers abort instead of walking up
to this repo. That parent-walk is what produced the accidental
`stage presence_gate` host commit.

```bash
python3 tests/guardrail_audit/evals/run.py                 # all six, 4 workers
python3 tests/guardrail_audit/evals/run.py doc_vs_doc      # one
python3 tests/guardrail_audit/evals/run.py --force         # bypass cache
python3 tests/guardrail_audit/evals/run.py --workers 1     # serialize
```

The default id set comes from `evals.json`; the runner stages and grades
through `tests/lib/eval_runner` at `--workers` (default 4). Each job gets
its own `TMPDIR` and its own sandbox root, and `grade.sh` compares only that
sandbox's staged tree. Run directories land under
`tests/guardrail_audit/workspace/run-<timestamp>-<pid>/`; each uncached
eval's `timing.json` records `started_at` and `ended_at` beside
`duration_s`.

Manual three-phase path:

```bash
target=$(mktemp -d)
eval "$(bash tests/guardrail_audit/evals/stage.sh presence_gate "$target")"
# operate in $sandbox_proj with $skill_path / $hub_path / $prompt
bash tests/guardrail_audit/evals/grade.sh presence_gate "$sandbox_proj" /path/to/response.txt
```

## Sandbox git contract

Fixture helpers in `evals/fixtures/_common.sh`:

- Bind every sandbox git call with explicit `GIT_DIR` + `GIT_WORK_TREE`
- Abort if `git init` fails or leaves no usable `$proj/.git`
- `ensure_sandbox_git` requires both pinned and discovery toplevels to
  equal `$proj` before any commit
- `stage.sh` re-checks that contract after each fixture setup
