# evals: task_create Decide-or-label and prior-art Novel behaviour

Canonical skill-creator schema in `evals.json`, fixtures under
`fixtures/<id>/setup.sh`, deterministic grading in `grade.sh`, and a
vendor worker runner in `run.py` that runs on Cursor by default.
`../script_tests/run.sh` pins the grader's checks on chosen task bodies.

## stage → agent → grade

1. `stage.sh <id> <target>` wipes `<target>`, builds a self-contained sandbox
   project at `<target>/proj` with its own `tasks/` tree and a discovery marker,
   and prints `sandbox_proj` / `skill_name` / `skill_path` / `prompt` as
   `printf %q`-quoted lines safe to `eval` in bash. It also writes
   `<target>/.eval_started_at`, the run-start epoch the grader uses for
   timestamp tolerance and isolation checks.
2. `run.py` spawns one vendor print-mode worker per eval with `sandbox_proj` as
   the working directory, so the skill's `discover_tasks.sh` resolves the
   sandbox and never the real repo. The worker prompt tells it to load the
   `SKILL.md` at `skill_path`, which is the micro-deployed copy. Edits under
   `plugins/` are what gets tested, not whatever is deployed.
3. `grade.sh <id> <sandbox_proj>` checks the post-run state and exits 0 only
   when every check passed.

## Two graded surfaces

The **Decide or label** evals impose a dual obligation: a genuinely open
decision is written into the task body *and* surfaced to the user. Neither half
proves the other, so the grader reads both.

- The **written** half comes from the sandbox: the task file, its frontmatter,
  its labeled open-decision lead-in (bare or qualified) and the paragraph
  around it, and the guardrail docs the run must leave untouched.
- The **surfaced** half comes from the worker's captured `response.txt`.
  `run.py` exports `RESPONSE_FILE` when it calls the grader; a hand-run grade
  should export it too. When no response is readable, the surface checks FAIL
  rather than pass vacuously. A label the user never saw is exactly the
  failure mode those three evals exist to catch.

The **`related-precedent-novel`** eval grades the written half only: one open
task whose `## Context` links the archived related precedent. Stopping at a
Partially covered ask leaves zero task files and fails the universal one-file
check.

## What stays prose

Whether a why-open clause is *true*, and whether a recorded resolution is the
*right* one, are judgements a regex cannot make. The grader asserts the clause
is present and the structure is right; the `expectations` strings in
`evals.json` carry the substance judgement, and `grade.sh` prints agent-attest
notes for what an operator confirms from `response.txt`.

## Verdict cache

`.eval_cache/<id>.json` holds the last conclusive verdict, keyed on the
`task_create` and base `task` skill sources, this directory, the model, and the
prompt. Editing either skill invalidates it. Timeouts and crashes are never
cached. They are environmental, not a property of the inputs.
