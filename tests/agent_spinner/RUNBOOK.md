# agent_spinner RUNBOOK

## Static contract

```bash
bash tests/agent_spinner/script_tests/run.sh
```

`run_all.sh` drives the same entrypoint and nothing else; the behavioural evals
spawn workers and stay out of band.

## Behavioral evals (Cursor worker by default)

```bash
python3 tests/agent_spinner/evals/run.py                     # all 21
python3 tests/agent_spinner/evals/run.py inline_floor         # one
python3 tests/agent_spinner/evals/run.py --force              # bypass the cache
```

Staging needs a working `git init` inside the sandbox (it writes under
`<sandbox>/proj/.git`). Run fixture staging outside a filesystem sandbox that
blocks `.git` creation, or the helpers abort rather than walking up to this
repository.

Manual three-phase path:

```bash
target=$(mktemp -d)
eval "$(bash tests/agent_spinner/evals/stage.sh inline_floor "$target")"
# operate in $sandbox_proj with $skill_path / $prompt
bash tests/agent_spinner/evals/grade.sh inline_floor "$sandbox_proj" /path/to/response.txt
```

## Cheap-first fixture probe

Stage every fixture before spending a worker on any of them. A fixture bug
costs one `claude -p` run per eval to discover the slow way:

```bash
for f in tests/agent_spinner/evals/fixtures/*/; do
  id=$(basename "$f")
  t=$(mktemp -d)
  bash tests/agent_spinner/evals/stage.sh "$id" "$t" >/dev/null || echo "STAGE FAILED: $id"
  rm -rf "$t"
done
```

## Sandbox contract

Fixture helpers in `evals/fixtures/_common.sh`:

- Bind every sandbox git call with explicit `GIT_DIR` + `GIT_WORK_TREE`.
- Abort when `git init` fails or leaves no usable `$proj/.git`.
- `ensure_sandbox_git` requires both the pinned and the discovery toplevel to
  equal `$proj` before any commit; `stage.sh` re-checks after each setup.
- `new_project` also stages the `outside/` canary tree, and `seal` records both
  hash inventories.

## Trigger evals

Trigger evals are Claude-only, so they run on Claude where a change needs the
measurement, such as a description edit, with `--vendor claude` in the command
so the Claude run is visible.

```bash
python3 tests/trigger_evals/run.py --vendor claude \
  --eval-set tests/trigger_evals/agent_spinner.json --skill agent_spinner
```

The skill has to be deployed for the runner's deployed-mode path. An unavailable
skill exits with a named unavailability error and writes no score;
`--force-uuid` remains the deliberate opt-in to the UUID proxy and, for
`agent_spinner`, also needs
`--skill-path plugins/ai_dev/skills/agent_spinner` because the default
source root is `plugins/knowledge_management/skills/<skill>`.

**Deploy-time obligation.** The first `make deploy` that installs
`agent_spinner` is the moment its description starts competing for triggers, so
that is when the cross-set regression check earns its cost. Re-run the
pre-existing sets then, each against its own prior run:

```bash
python3 tests/trigger_evals/run.py --vendor claude \
  --eval-set tests/trigger_evals/<set>.json \
  --skill <skill> --baseline tests/trigger_evals/results/<skill>/<prior-run>
```

Scope it to the sets that can actually bleed, rather than all six. A set only
competes with this skill where its queries share vocabulary with the deployed
`description:`, so establish that first with
`tests/agent_spinner/trigger_overlap.py`:

```bash
python3 tests/agent_spinner/trigger_overlap.py
```

Re-run only the sets it names, and treat a reported regression as description
bleed from the new skill. Measured on 2026-09-16, one query across all 121
overlapped, on the single word "verify" in unambiguous `task_audit` territory,
so no set qualified and the sweep was skipped. Re-run the overlap check after
any material edit to this skill's `description:`, since that is what moves the
answer. Running the full six-set sweep on no overlap is the case `TESTING.md`'s
re-run economy rule excludes.
