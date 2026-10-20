---
description: "Name every eval sandbox root by its harness prefix alone, so a worker cannot read the eval id or scenario name, and the expected answer it often encodes, from its own working directory."
scope: "local test harnesses"
created: 2026-10-20T11:45:48
updated: 2026-10-20T12:36:00
status: open
reported-by: Andreas Hoffmann
---

# Keep the eval id out of the sandbox path a worker can see

## Goal

Every behavioural eval runner creates its sandbox root from its harness prefix alone, so the directory a worker runs in carries no eval id, scenario id, or pass number. A worker then judges the request from the fixture and prompt it was given, and an eval result reflects the skill under test rather than a hint read from the path. The rule that sandbox paths stay free of eval identity is stated once in the tests tree's worker-isolation documentation, so new runners follow it.

## Context

`create_sandbox_root` in `tests/lib/worker_isolation.py` builds each root with `tempfile.mkdtemp(prefix=prefix)`, and most runners pass a prefix that appends the eval identity to the harness prefix, as `f"{ISOLATION_PREFIX}{eval_id}_"` does. The worker's working directory is the sandbox project under that root, so the id is in every path it sees. Many ids name the behaviour the eval expects, such as `guardrail-bound-surface` or `reconcile-recorded`. On 2026-10-20 a `task_create` worker in a `guardrail-bound-surface` draw wrote that "the eval name suggests a guardrail-bound fork", which shows workers do read it.

The affected set is every caller whose `create_sandbox_root` prefix carries more than its harness's `ISOLATION_PREFIX`, derived by searching `tests` for `create_sandbox_root(` and reading each call's prefix argument (the call often spans lines). It includes the per-eval form in the Pattern A runners, the `{scenario}_{n}_` form in `tests/language_humanizer/evals/run.py`, and the `{sid}_{pass_num}_` form in `tests/wiki/layer2/run.py`. [The eval-workers-outside-checkout task](archive/tests_eval-workers-outside-checkout.md) introduced this adoption set and the isolation documentation this task extends. The live `tests_*-parallel-evals` tasks also edit these runners, so whichever lands second rebases its runner edits on the other.

## Approach

Change each affected caller to pass its bare `ISOLATION_PREFIX`, and keep the eval identity in the run directory and its logs, which stay inside the checkout where the worker cannot read them. Where a runner needs the id to find its own sandbox later, keep it in a local variable or the run directory rather than in the root's name. Leave `create_sandbox_root`'s refusal checks unchanged.

Add a static case to `tests/lib/test_worker_isolation.py` that scans every `*.py` file under `tests` (skipping the gitignored run-output subtrees) for `create_sandbox_root(` calls, reads each call's argument across line breaks, and fails when the argument is anything other than the bare name `ISOLATION_PREFIX`. That case keeps a runner added later from reintroducing the leak.

Add one sentence to the `### Worker isolation` section of `tests/CLAUDE.md` and to the `### Verdict cache, timeouts, isolation` section of `tests/AGENTS.md`, stating that a sandbox root's name carries only the harness prefix, because a worker reads its working directory and an eval id there leaks the expected behaviour. Through the wiki skill family, record the same rule and the 2026-10-20 observation as its dated source in `wiki/concepts/verification-surfaces.md` under `### A worker inherits the host's instructions unless it is isolated`, which already describes `create_sandbox_root`.

## Acceptance

- `python3 tests/lib/test_worker_isolation.py` passes, including the new static case. Today that case fails on the per-eval runners, `tests/language_humanizer/evals/run.py`, and `tests/wiki/layer2/run.py`.
- `tests/CLAUDE.md` `### Worker isolation`, `tests/AGENTS.md` `### Verdict cache, timeouts, isolation`, and `wiki/concepts/verification-surfaces.md` `### A worker inherits the host's instructions unless it is isolated` each state the harness-prefix-only rule once.
- One run of `python3 tests/task_create/evals/run.py --no-cache guardrail-bound-surface` on the default vendor completes, and no entry in its `timing.json` `artefacts_read_from_micro_deployment.paths` list contains the string `guardrail-bound-surface`. Today those paths run through a root named `task_create_guardrail-bound-surface_<random>`.
