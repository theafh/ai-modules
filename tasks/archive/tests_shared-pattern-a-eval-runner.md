---
description: Ship one Pattern A eval-runner helper (default 4 workers, per-job isolation) and lockstep the CLAUDE.md/AGENTS.md/README.md parallel-workers rule with the vendor.py comment.
scope: tests/lib
created: 2026-10-04T22:11:10
updated: 2026-10-08T20:43:59
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Extract a shared Pattern A eval runner with operator-doc lockstep and default four workers

## Goal

`tests/lib/` ships one importable Pattern A eval-runner helper for isolated-sandbox
behavioral harnesses. The helper runs evals through a thread pool whose
`--workers` default is `vendor.DEFAULT_PARALLEL_WORKERS` (4), gives each job its
own `TMPDIR`, records cache hits the way `tests/lib/eval_cache.py` already does,
and decodes worker output through `tests/lib/worker_io.py`. Each job callable
stages its own sandbox. Cursor and Claude differ only in `tests/lib/vendor.py`.
The user-visible outcome: adding parallelism or a vendor flag happens in one
module, and a copied `run.py` loop is no longer the way a harness grows.

## Context

Two runners already parallelize with that default: `tests/wiki/layer2/run.py`
(scenarios concurrent, passes of one scenario sequential) and
`tests/language_humanizer/evals/run.py` (one staged sandbox per pass). Every
other Pattern A `evals/run.py` still walks evals in a dict comprehension or a
`for` loop; a subset of those runners carries a `# Sequential on purpose`
comment.

The copies have drifted. Workspace roots split between `tests/<skill>/workspace`
and `tests/<skill>/evals/workspace`. Default id lists are frozen in some
runners (`git_commit`, `guardrail_audit`, `task_auto_check`) and derived from
`evals.json` in others (`skill_doctor`, `task_fix`). Skills stage under each
eval's `artefacts/` via `vendor.stage_skill_tree`; spawnable named agents land
in the workdir under `.{claude,cursor}/agents/` via the local
`stage_named_agents` copy in wiki layer-2 and `task_auto_check` — a different
root from `stage_skill_tree`'s optional `agent_files=`. `tests/lib/worker_auth.py`
is a Claude-only wrapper around `vendor.worker_env` / `vendor.preflight_auth`.
Operator policy lives in `tests/CLAUDE.md` under
`### Parallel workers: default 4 only where each job has its own sandbox` and
in the shorter `### Parallel workers` block in `tests/AGENTS.md`; both still
list the Pattern A runners as sequential.

Live siblings consume this helper rather than inventing a second pool:

- [git_commit parallel evals](../tests_git-commit-parallel-evals.md)
- [git_review parallel evals](../tests_git-review-parallel-evals.md)
- [task hub parallel evals](../tests_task-hub-parallel-evals.md)
- [task_create parallel evals](../tests_task-create-parallel-evals.md)
- [task_fix parallel evals](../tests_task-fix-parallel-evals.md)
- [task_auto_check parallel evals](../tests_task-auto-check-parallel-evals.md)
- [agent_spinner parallel evals](../tests_agent-spinner-parallel-evals.md)
- [guardrail_audit parallel evals](../tests_guardrail-audit-parallel-evals.md)
- [skill_doctor parallel evals](../tests_skill-doctor-parallel-evals.md)
- [wiki layer-2 runner dedup](../tests_wiki-layer2-runner-dedup.md)
- [language_humanizer shared pool](../tests_language-humanizer-shared-pool.md)
- [git checkout and refresh runners](../tests_git-eval-runner-parity.md)

Host-instruction isolation for the language_humanizer worker and judge stays
with [the isolation task](../tests_language-humanizer-worker-isolation.md). Cache
key narrowing stays with [the granularity task](../tests_eval-cache-key-granularity.md).
Alignment of trigger-eval `--workers` to `DEFAULT_PARALLEL_WORKERS` stays
with [the Cursor vendor task](../tests_trigger-evals-cursor-vendor.md).

## Approach

Add `tests/lib/eval_runner.py` beside
`vendor.py`. It exposes:

- A `--workers` argparse helper whose default is `vendor.DEFAULT_PARALLEL_WORKERS`.
- A job runner that takes callables, runs them in a `ThreadPoolExecutor` when
  workers is greater than 1, and reassembles results in submission order
  (eval-id / file order) in the printed summary.
- A per-job environment builder that sets `TMPDIR` (and `TEMP` / `TMP` when a
  worker honors those) to a fresh directory unique to that job, then removes it
  after the job returns.
- Optional before/after hooks for a host-checkout escape guard, serialized so
  two finishing jobs cannot mis-attribute `git status` noise.
- Shared surfaces every copy already inlines: write `response.txt` /
  `stderr.txt` / `timing.json` with both `worker_rc` and `claude_rc`, and
  decode timeout / `TimeoutExpired` captured stdout/stderr through
  `worker_io.as_text`.
- Helper-chosen contracts the runner also exposes: load eval ids from
  `evals.json` in file order, resolve `workspace/` to
  `tests/<skill>/workspace`, and skip/record through `eval_cache`.

The helper stages neither skills nor agents; job callables own sandbox
staging, including workdir agent placement when a harness needs spawnable
agents.

Rewrite `### Parallel workers: default 4 only where each job has its own sandbox`
in `tests/CLAUDE.md` and the `### Parallel workers` block in
`tests/AGENTS.md` in place: lead with the helper contract (isolated-sandbox
evals that use `eval_runner` default to 4 concurrent jobs; `--workers 1`
serializes; a harness keeps a sequential subset only when jobs share a
resource the helper cannot isolate — today the `task_auto_check`
repair-class nested loops). Keep naming the Pattern A runners that stay
sequential until their sibling conversion tasks wire them onto the helper.
Also keep naming every runner that already defaults to
`DEFAULT_PARALLEL_WORKERS` outside this helper (today wiki layer 2 and
`language_humanizer`, plus any other present when this lands).
Rewrite the existing `Isolated-sandbox runners default to 4 parallel workers`
sentence under `## Vendor switch` in `tests/README.md` in place so the three
operator docs agree. Rewrite the comment above
`DEFAULT_PARALLEL_WORKERS` in `tests/lib/vendor.py` to match.

Prove the helper with `tests/lib/test_eval_runner.py` in the style of
`tests/lib/test_vendor.py`: default workers is 4, two concurrent dummy jobs get
distinct temp dirs with `TMPDIR`/`TEMP`/`TMP` each equal to that job's temp dir
and cannot see each other's files, `--workers 1` runs serially, and a hook pair
around two overlapping jobs still attributes a deliberate host-tree touch to one
job.

**Out of scope:**

- Switching any existing `evals/run.py` onto the helper; each sibling named in
  Context owns that conversion.
- Authoring or live-running harnesses for an unshipped editorial plugin skill.
- Changing what any eval asserts.
- Changing `worker_auth.py`; it stays the thin Claude wrapper around
  `vendor.worker_env` / `vendor.preflight_auth`.

## Acceptance

- `tests/lib/eval_runner.py` exists and `python3 tests/lib/test_eval_runner.py`
  passes, covering default workers 4, two overlapping jobs under that default
  get distinct temp dirs with `TMPDIR`/`TEMP`/`TMP` each equal to that job's
  temp dir and cannot see each other's files, serial `--workers 1`, a hook
  pair around two overlapping jobs that attributes a deliberate host-tree
  touch to one job, loading eval ids from fixture `evals.json` in file order,
  resolving `workspace/` to `tests/<skill>/workspace`, and submission-order
  (eval-id / file order) summary printing.
- `python3 tests/lib/test_eval_runner.py` also proves the `--workers` argparse
  helper registers default 4: after registration, `parse_args([])` yields
  `--workers` equal to `vendor.DEFAULT_PARALLEL_WORKERS` (4).
- `python3 tests/lib/test_eval_runner.py` also proves each job's temp directory
  is removed after the job callable returns.
- `python3 tests/lib/test_eval_runner.py` also proves the job API runs
  caller-supplied callables that stage their own sandboxes (create their own
  workdirs and, when needed, place spawnable agents under workdir
  `.{claude,cursor}/agents/`); sandbox staging and workdir agent placement
  remain the callable's responsibility.
- `python3 tests/lib/test_eval_runner.py` also proves the helper writes
  `response.txt`, `stderr.txt`, and `timing.json` with both `worker_rc` and
  `claude_rc`.
- `python3 tests/lib/test_eval_runner.py` also proves skip-on-hit and
  record-on-miss through `eval_cache`.
- `python3 tests/lib/test_eval_runner.py` also proves the timeout bytes path
  decodes through `worker_io.as_text`.
- `vendor.DEFAULT_PARALLEL_WORKERS` remains 4, and the comment above it states
  the isolated-sandbox default rather than listing Pattern A runners as
  sequential.
- `tests/CLAUDE.md` states that same default under
  `### Parallel workers: default 4 only where each job has its own sandbox`,
  and `tests/AGENTS.md` states it under `### Parallel workers`, both in
  lockstep; they lead with the helper contract, still name every runner that
  already defaults to `DEFAULT_PARALLEL_WORKERS` outside this helper (today
  wiki layer 2 and `language_humanizer`, plus any other present when this
  lands), and still name the Pattern A runners that remain sequential until
  sibling conversion tasks wire them (plus any permanent isolation
  exceptions). `tests/README.md` `## Vendor switch` rewrites the prior
  `Isolated-sandbox runners default to 4 parallel workers` sentence in place
  so one canonical statement remains and the three operator docs agree.
- `tests/lib/eval_runner.py` keeps Cursor/Claude differences behind
  `tests/lib/vendor.py`.
