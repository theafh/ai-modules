# tests/tasks — task-family harness

Pattern A (skill-creator-aligned). Covers the whole `task` family — the
base `task` skill plus the seven siblings (`task_create`, `task_check`,
`task_select`, `task_implement`, `task_audit`, `task_finish`, `task_fix`). The
siblings ship no scripts of their own, so the bundled-script surface is
the base skill's three programs; each sibling's *behavior* gets its own
eval.

| Surface | Where | What it covers | Runner |
| --- | --- | --- | --- |
| Bundled scripts | `script_tests/run.sh` | `discover_tasks.sh`, `init_tasks.sh`, and the full `lint.py` check set | `./tests/tasks/run_all.sh` |
| Skill behavior | `evals/` | a behavioral eval per family member, plus dependency evals for task_implement / task_select (stage → agent → grade) | operator-driven, see `evals/README.md` |
| Triggering | `../trigger_evals/task.json` | family routing — each sibling wins its phrasings, broad/ambiguous → base `task`, no bleed | `../trigger_evals/run.py` |

## Bundled-script unit tests

```bash
./tests/tasks/run_all.sh
```

Stages a throwaway tree per scenario. ~1 sec, no LLM cost. Groups:

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

The family auto-derives to all seven `task*` skills. A family-only pass
means a sibling is stealing a phrasing — sharpen the *encroaching*
sibling's description, not the expected one.
