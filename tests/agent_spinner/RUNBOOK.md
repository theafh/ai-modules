# agent_spinner RUNBOOK

## Static contract

```bash
bash tests/agent_spinner/script_tests/run.sh
```

`run_all.sh` drives five entrypoints with one aggregated exit code:
`script_tests/run.sh`, `script_tests/ledger_run.sh`,
`script_tests/grade_cases.sh`, `script_tests/fixture_stage.py`, and
`evals/test_run.py`. The behavioural evals spawn workers and stay out of band.

## Behavioral evals (Cursor worker by default)

TESTING.md's parity rule under `## Running Tests` governs this suite: an eval
runs and grades the same way on Claude and Cursor, and the suite is
vendor-specific only where an eval names a vendor-specific feature. The suite
command without `--vendor` runs every eval on Cursor's `agent -p` on `auto`,
the default because it is cheaper and faster. The Claude command is a run the
operator asks for, or one an eval needs for a Claude-specific feature, which
the eval names.

```bash
python3 tests/agent_spinner/evals/run.py                     # all evals, default Cursor worker
python3 tests/agent_spinner/evals/run.py inline_floor         # one
python3 tests/agent_spinner/evals/run.py --force              # bypass the cache
python3 tests/agent_spinner/evals/run.py --vendor claude      # the Claude run the operator asks for
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

The manual path runs no mode eval: it stages, operates, and grades one
ordinary eval, and the inline-body, second-turn, staged-agent, and tool-record
modes run through `evals/run.py`. `evals/README.md` `## Runner modes` has the
full account.

## Cheap-first fixture probe

Stage every fixture before spending a worker on any of them. A fixture bug
costs one worker run per eval to discover the slow way:

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

Trigger evals run on both vendors, on Cursor by default, so run them without
`--vendor` where a change needs the measurement, such as a description edit.
Pass a baseline recorded on the same vendor.

```bash
python3 tests/trigger_evals/run.py \
  --eval-set tests/trigger_evals/agent_spinner.json --skill agent_spinner \
  --baseline tests/trigger_evals/results/agent_spinner/<prior-run>
```

A Claude run is one the operator asks for; name it with `--vendor claude` so
the Claude run is visible.

Two routes reach the runner's deployed-mode path. The first is a deployed
skill: `make deploy` installs `agent_spinner` under the run vendor's native
root (`~/.cursor/skills` or `~/.claude/skills`), and a skill missing from that
tree exits with a named unavailability error and writes no score. The second
measures a source description without a deploy: a scratch home directory holds
a copy of the deployed skills with only `agent_spinner`'s files swapped in, and
the run points `HOME` at it. Build the scratch home the way
`tests/lib/micro_deploy.py` does, because the Cursor CLI reads its login
through `Library/Keychains` and runs shell commands from a login shell under
`HOME`: link the real home's `Library/Keychains` and write the three login
profiles that restore the worker's `PATH` from `MICRO_DEPLOY_PATH`.

```bash
cfg=$(mktemp -d)
mkdir -p "$cfg/.cursor" "$cfg/Library"
cp -R ~/.cursor/skills "$cfg/.cursor/skills"
if [ -d "$HOME/Library/Keychains" ]; then
  ln -sfn "$HOME/Library/Keychains" "$cfg/Library/Keychains"
fi
for p in .zprofile .bash_profile .profile; do
  printf '%s\n' 'if [ -n "${MICRO_DEPLOY_PATH:-}" ]; then export PATH="$MICRO_DEPLOY_PATH"; fi' > "$cfg/$p"
done
rm -rf "$cfg/.cursor/skills/agent_spinner"
cp -R plugins/ai_dev/skills/agent_spinner "$cfg/.cursor/skills/agent_spinner"
HOME="$cfg" MICRO_DEPLOY_PATH="$PATH" python3 tests/trigger_evals/run.py \
  --eval-set tests/trigger_evals/agent_spinner.json --skill agent_spinner \
  --skill-path plugins/ai_dev/skills/agent_spinner \
  --runs-per-query 3 --timeout 45 --workers 6
```

`--force-uuid` remains the Claude-only deliberate opt-in to the UUID proxy and,
for `agent_spinner`, also needs
`--skill-path plugins/ai_dev/skills/agent_spinner` because the default source
root is `plugins/knowledge_management/skills/<skill>`.

### Recorded measurements

The set holds eight `should_trigger: true` queries that name no skill, eight
`should_trigger: false` queries, and the two naming queries. Each run is three
runs per query, graded at the 50%-over-three threshold.

| Date | Build | Model | Vendor | Description | True queries (no skill named) | Negative queries | Naming queries |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-04 | `claude` 2.1.226 | `claude-sonnet-4-6` | Claude | today's name-blind text, run 1 | 4/8 | 8/8 | 2/2 |
| 2026-10-04 | `claude` 2.1.226 | `claude-sonnet-4-6` | Claude | today's name-blind text, run 2 | 3/8 | 8/8 | 2/2 |
| 2026-10-04 | `claude` 2.1.226 | `claude-sonnet-4-6` | Claude | conditional sentence | 4/8 | 8/8 | 2/2 |
| 2026-11-09 | Cursor 2026.10.22-27dcf5f | `auto` | Cursor | baseline (parent-commit name-blind text) | 8/8 | 8/8 | 2/2 |
| 2026-11-09 | Cursor 2026.10.22-27dcf5f | `auto` | Cursor | changed (conditional sentence) | 8/8 | 8/8 | 2/2 |
| 2026-11-10 | Cursor 2026.10.22-27dcf5f | `auto` | Cursor | trimmed description under the 1,000-character listing-risk threshold | 8/8 | 8/8 | 2/2 |

The 2026-11-10 Cursor run staged the trimmed description under the same
scratch-home route; its result directory is
`tests/trigger_evals/results/agent_spinner/2026-11-10_123721`.

The 2026-11-09 Cursor runs used the scratch-home route above, with the baseline
run staging the parent commit's `SKILL.md` and the changed run staging the
working tree's. Their result directories are
`tests/trigger_evals/results/agent_spinner/baseline-cursor-20261109-135739` and
`tests/trigger_evals/results/agent_spinner/changed-cursor-20261109-135850`.

**Deploy-time obligation.** The first `make deploy` that installs
`agent_spinner` is the moment its description starts competing for triggers, so
that is when the cross-set regression check earns its cost. Re-run the
pre-existing sets then, each against its own prior run:

```bash
python3 tests/trigger_evals/run.py \
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
