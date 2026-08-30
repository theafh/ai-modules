# Wiki skill regression test results

Repo: `ai-modules` · Skill: `plugins/knowledge_management/skills/wiki`
Latest run: `run-20260822-172921` (targeted subset after the log-scope change) · 2026-08-22
Prior run: `run-20260822-134337`

## Status: clean

- Layer 1: **124/124** scenarios pass (script-level discovery / init / lint, deterministic)
- Layer 2 (this run): the 10 `auto_shaper_wiki` scenarios the log-scope change
  touches — `AS-8`–`AS-11` plus the new `AS-13`–`AS-18` — pass at **2 passes
  each, 20/20 runs clean**, with **0 regressions** against the prior run.
  The `L2-*`, `WI-*`, `WU-*`, and `AS-1`–`AS-5` scenarios were not re-run in
  this subset.
- No filesystem leak: `~/wiki` was never created; all writes stayed in sandboxes

The per-surface tables below describe the original baseline and have not been
regenerated since. The live inventories are `grep -E '^scenario ' layer1/run.sh`
and `jq -r '.evals[].id' layer2/evals.json`.

## How to re-run

```bash
# Layer 1 only (fast, deterministic, ~1 sec)
./tests/wiki/run_all.sh

# Layer 1 + Layer 2 (full regression, ~5–10 min via claude -p)
./tests/wiki/run_all.sh --layer2

# Layer 2 alone — single scenario while debugging:
python3 ./tests/wiki/layer2/run.py --scenario L2-2
```

Each Layer 2 run produces a self-contained `report.html` plus `benchmark.md`
and `benchmark.json` under `tests/wiki/layer2/workspace/run-<ts>/`. The
aggregator compares against the most recent prior `benchmark.json` and exits
non-zero on regression.

## What's covered

### Layer 1 (deterministic, 19 scenarios)

| Group | Scenarios | What's tested |
| --- | --- | --- |
| Discovery | d1–d12 | every walk-up branch in `discover_wiki.sh` (no wiki/no marker, marker at CWD/home/all-levels, existing wiki, upstream wiki ambiguity, multi-level walk-up, outside-HOME fallback in 3 sub-cases, `--check` flag, retired-wiki marker) |
| Init | i1–i4 | fresh init, refusal over existing, refusal at `.no_wiki`, no-args help |
| Lint | l1–l3 | clean fresh wiki, blocking on missing SCHEMA, blocking on missing index |

### Layer 2 (skill-level, 5 scenarios × 2 passes)

| ID | Scenario | Discovery exit | Asks? | Init? | Result |
| --- | --- | --- | --- | --- | --- |
| L2-1 | existing wiki at CWD; user adds a page | 0 | no | no | concept + raw + index/log update, lint clean |
| L2-2 | upstream wiki + empty CWD (the D6 case) | 2 | YES | no | candidates presented, user must pick |
| L2-3 | wiki already exists at CWD; user asks "init" | 0 | no | no | recognized existing, no re-init |
| L2-4 | fresh CWD, user pre-decides "use local" | 2 | (n/a, pre-decided) | yes | scaffolded SCHEMA + index + log + dir tree |
| L2-5 | `.no_wiki` at CWD, wiki at HOME | 0 | no | no | adopted HOME wiki, page added |

### The load-bearing assertion

For every scenario:

- `real_home_wiki_absent` — fail-safe that catches subagents leaking into `~/wiki`
- `no_files_outside_sandbox` — every `files_created`/`files_modified` path must be inside the sandbox

These two assertions guarantee that future skill changes can't silently
cause data leaks during testing.

## Variance across passes (latest run)

Pass-1 vs pass-2 had **0 disagreements** on assertion outcomes — both
passes produced identical PASS/FAIL for every assertion. Variance was
entirely in timing/tokens, and across-run consistency vs. the prior
run was clean (no regressions):

| Scenario | Mean duration | sd | Mean tokens | sd |
| --- | --- | --- | --- | --- |
| L2-1 existing-wiki-add-page | 121.5s | ±33.4s | 45 902 | ±3 559 |
| L2-2 ambiguous-discovery-must-ask | 32.7s | ±7.2s | 32 822 | ±120 |
| L2-3 init-when-wiki-exists | 24.7s | ±0.2s | 32 942 | ±313 |
| L2-4 init-fresh-with-pre-decision | 39.2s | ±3.2s | 35 298 | ±395 |
| L2-5 no-wiki-marker-routes-to-home | 129.7s | ±4.6s | 48 280 | ±1 527 |

L2-2 and L2-3 are the lightest (discovery only). L2-1 and L2-5 are
heaviest (full ingest with sources + concept page + lint).

## Instrumentation fixes between the two runs

The first run surfaced three real instrumentation problems that the second
run cleaned up:

1. **Inconsistent `report.md` capture.** The Agent harness rejects subagent
   `Write` calls for some absolute paths. 6 of 10 first-run pass dirs
   ended up without `report.md`. Fix: added `normalize.py` that extracts
   the TEST REPORT block from `response.txt` and writes `report.md` if
   missing. Wired into both the in-session orchestration and `run.py`.
2. **Noisy responses.** Agents narrated the harness rejection ("The
   harness blocked the file write...") in their final text. Fix:
   tightened the prompt — "end response with the TEST REPORT block and
   nothing after it; do not narrate harness behavior" — and `normalize.py`
   strips known noise patterns from older runs.
3. **Inconsistent report fields.** Some agents reported
   `ambiguity_presented_to_user: n/a` when discovery exited 0 (auto-resolved);
   others reported `no`. Fix: prompt now requires strict `yes|no` for
   that field; assertions use the new `report_field_in` check type to
   accept either value as semantically equivalent for backward
   compatibility.

## Adding a new scenario

1. Stage the sandbox in `layer2/setup_scenarios.sh`.
2. Add a scenario block to `layer2/evals.json` with assertions.
3. Re-run. Layer 2 picks it up automatically.

Assertion types supported by `grade.py`:

- `report_field_eq`, `report_field_contains`, `report_field_endswith`
- `file_exists`, `file_exists_and_changed`, `path_does_not_exist`,
  `glob_exists`, `all_dirs_exist`
- `no_files_outside_sandbox`, `real_home_wiki_absent`
- `response_text_contains`, `response_text_matches`,
  `response_text_does_not_match`, `response_text_contains_path`

## Files

```text
tests/wiki/
├── run_all.sh                   # entrypoint (Layer 1; --layer2 to add Layer 2)
├── RUNBOOK.md                   # operator guide
├── results/SUMMARY.md           # this file
├── layer1/run.sh                # 19 deterministic scenarios
└── layer2/
    ├── evals.json               # canonical scenarios + assertions
    ├── setup_scenarios.sh       # restages all 5 sandboxes
    ├── build_prompt.py          # eval -> agent prompt
    ├── grade.py                 # report + sandbox -> grading.json
    ├── aggregate.py             # gradings -> benchmark.json + regressions
    ├── render_report.py         # benchmark + grading -> report.html
    ├── run.py                   # standalone orchestrator (claude -p)
    └── workspace/run-<ts>/      # one dir per regression run
        ├── L2-*/pass-N/
        │   ├── prompt.md, response.txt, report.md, timing.json
        │   ├── grading.json
        │   └── sandbox-snapshot/
        ├── benchmark.json
        ├── benchmark.md
        ├── grading_summary.json
        └── report.html
```

The authored harness under `tests/wiki/` is committed; `tests/.gitignore`
keeps run output out. This summary is one of the few hand-written result
notes that are tracked.

## L2-6 — changes-only log rule (2026-07-30)

Scenario `L2-6` (`answer-only-query-writes-no-log-entry`) guards the rule that
`log.md` gains an entry exactly when an operation created or updated wiki files.
It stages a populated wiki, asks a single-page-lookup question, directs the agent
through the `<query>` workflow step by step, and asserts `log.md` is byte-identical
to a checksum recorded at staging time.

Measured on `claude-sonnet-4-6`, 8 passes per side, comparing the pre-rewrite skill
text against the changes-only rewrite:

| Skill text | Log entry written | Scenario verdict |
| --- | --- | --- |
| Pre-rewrite (`Update log.md with the query and whether it was filed`) | 4 of 8 passes | fails intermittently |
| Changes-only rewrite | 0 of 8 passes | 8/8 clean |

The pre-rewrite text is a coin flip, not a consistent failure — both behaviours are
defensible readings of the contradictory instructions, which is what motivated the
rewrite. The failing passes reproduce the original incident exactly, appending an
entry whose body reads "Not filed — trivial single-page lookup". Treat this scenario
as a stochastic guard: run at least 5 passes when comparing skill revisions, and
read the pass rate rather than a single verdict.

Run evidence, both sides, under `layer2/workspace/`: the pre-rewrite baseline in
`run-20260730-105103` and `run-20260730-110127`, the changes-only rewrite in
`run-20260730-105111` and `run-20260730-110134`. The rewrite-side runs were produced
from a worktree checkout of the rewritten skill and copied here, so their `grading.json`
sandbox paths point at that worktree; read them as frozen records rather than re-grading
them in place. `run-20260730-104834` and `run-20260730-104908` are the first, blunter
version of the scenario, kept only as history — they predate both the sharpened
constraints and the per-pass snapshot fix, so their per-pass verdicts are coupled.

Two harness capabilities landed with it: the `file_matches_baseline` and
`glob_absent` assertion types, and per-pass `sandbox-snapshot/` capture in `run.py`.
The snapshot closes a latent grading flaw — sandboxes are restaged between passes,
so before this every filesystem assertion in every scenario graded against whatever
the last pass left behind. `grade.py` now reads the per-pass snapshot when present
and falls back to the live sandbox, while path-prefix checks (`no_files_outside_sandbox`,
`response_text_contains_path`) keep comparing against the live sandbox root.
