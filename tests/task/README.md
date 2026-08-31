# tests/task — task-family harness

Pattern A (skill-creator-aligned). The directory is named for the `task`
skill, matching the standing repo rule that puts one harness under a
directory named for the skill it covers. It holds the whole family: the
base `task` skill plus its siblings (`task_create`, `task_check`,
`task_auto_check`, `task_explain`, `task_select`, `task_implement`,
`task_audit`, `task_finish`, `task_fix`). The siblings ship no scripts of
their own, so the bundled-script surface is the base skill's three
programs; each sibling's *behavior* gets its own eval. `task_create/` and
`task_auto_check/` carry their own behavioral harnesses beside this one.

| Surface | Where | What it covers | Runner |
| --- | --- | --- | --- |
| Bundled scripts | `script_tests/run.sh` | `discover_tasks.sh`, `init_tasks.sh`, and the full `lint.py` check set | `./tests/task/run_all.sh` |
| Family contract | `script_tests/contract_run.sh` | the prose contract across the hub, its siblings, and the family agents — one canonical rule statement per rule, siblings citing rather than copying it, and the standing-doc presence gates | `./tests/task/run_all.sh` |
| Skill behavior | `evals/` | a behavioral eval per family member, plus dependency evals for task_implement / task_select (stage → agent → grade) | operator-driven, see `evals/README.md` |
| Triggering | `../trigger_evals/task.json` | family routing — each sibling wins its phrasings, broad/ambiguous → base `task`, no bleed | `../trigger_evals/run.py` |

## Deterministic runners

```bash
./tests/task/run_all.sh
```

Drives both script runners in order and aggregates their exit codes, so a
failure in one still leaves the other's verdict visible. ~1 sec total, no
LLM cost.

### `script_tests/run.sh` — bundled-script unit tests

Stages a throwaway tree per scenario. Groups:

- **`d*` discover_tasks.sh** — git-toplevel resolution, project-marker
  walk, exit codes (0 when `tasks/` exists, 1 when not, 2 on bad arg),
  `--help`. Staged **outside** the repo (`mktemp`) so the surrounding
  ai-modules git tree doesn't shadow the discovery logic under test.
- **`i*` init_tasks.sh** — scaffolds `tasks/` + `archive/`, idempotency,
  refusal on a non-directory target, arg/exit handling, `--help`.
- **`l*` lint.py link resolution** — task-dir and project-root fallback.
- **`n*`/`f*`/`loc*`/`prov*`/`col*`/`md*`/`sc*`/`sz*`/`c*` lint.py rule set** —
  filename naming, frontmatter completeness/validity, provenance,
  status↔location and archive migration, cross open+archive name collisions, standard-markdown
  (footnotes/wikilinks), scope resolution (unquoted path / escape /
  missing / quoted-empty), oversize warn, and a fully-clean tree.

### `script_tests/contract_run.sh` — family contract assertions

Greps the shipped `SKILL.md` files and the family agents for the prose
each rule is authored once in, and for its absence from the siblings that
must cite it instead. Also stages a two-project fixture to prove the
`CHARTER.md` / `ARCHITECTURE.md` / `FEATURES.md` / `TESTING.md` presence
gates resolve through `discover_tasks.sh`. Every needle is a literal from
live skill prose, so a rule reworded in a skill fails here until the
needle is refreshed to the new wording — that failure is the drift signal,
not a false alarm.

## Behavioral evals

`evals/` holds at least one operator-driven eval per family member (the canonical
skill-creator schema in `evals.json`, fixtures under `fixtures/<id>/`,
graded by `grade.sh`). They consume LLM tokens and are NOT auto-run from
`run_all.sh`. See `evals/README.md` for the stage → agent → grade recipe.
The `create` eval doubles as the trustworthy-timestamps check (the agent
stamps `created`/`updated` from the real wall clock, not a fabricated
time). Per the repo's one-bump-per-commit rule, eval growth lands in its
own commit, separate from the skill change it covers.

## Trigger evals

`../trigger_evals/task.json` validates family routing — see
`../trigger_evals/` and `tests/CLAUDE.md`. Run with:

```bash
python3 tests/trigger_evals/run.py \
  --eval-set tests/trigger_evals/task.json \
  --skill task --skill-path plugins/ai_dev/skills/task \
  --model claude-sonnet-4-6 --runs-per-query 3 --timeout 45 --workers 10
```

Pass `--skill-path` as shown: without it the runner finds no source skill
and the family degenerates to `['task']`, which leaves the family metric
meaningless (precise scoring is unaffected). With it, the family
auto-derives to all ten `task*` skills. A family-only pass means a sibling
is stealing a phrasing — sharpen the *encroaching* sibling's description,
not the expected one.
