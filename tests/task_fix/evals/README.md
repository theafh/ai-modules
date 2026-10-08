# evals: task_fix repeated-link disposition

Canonical skill-creator schema in `evals.json`, fixtures under
`fixtures/<id>/setup.sh`, deterministic grading in `grade.sh`, and a
sonnet-pinned worker runner in `run.py`.

## stage → agent → grade

1. `stage.sh <id> <target>` wipes `<target>`, builds a self-contained sandbox
   project at `<target>/proj` with its own `tasks/` tree, commits it so the
   grader has the staged bytes to compare against, and prints `sandbox_proj` /
   `skill_name` / `skill_path` / `prompt` as `printf %q`-quoted lines safe to
   `eval` in bash. It also writes `<target>/.eval_started_at`, the run-start
   epoch the grader uses for its isolation check.
2. `run.py` spawns one `claude -p` worker per eval with `sandbox_proj` as the
   working directory, so the skill's `discover_tasks.sh` resolves the sandbox
   and never the real repo. The worker prompt tells it to load the `SKILL.md`
   at `skill_path`, which is the repo copy. Edits under `plugins/` are what
   gets tested, not whatever is deployed.
3. `grade.sh <id> <sandbox_proj>` checks the post-run state and exits 0 only
   when every check passed.

Each prompt is the ordinary everyday invocation, `Health-check and clean up the
tasks backlog.` Nothing in it names the repeated-link finding, so the run has
to reach the disposition from the linter's own output through the inline
`task_fix` path.

## Two graded surfaces

The base `<lint>` **Repeated-link react protocol** obliges both, and neither
half proves the other.

- The **file** half comes from the sandbox, compared against the staged commit.
  A regroup must land in one passage with `updated` bumped; a surfaced finding
  must leave the file byte-identical, and every link target and archived body
  must be untouched on every eval.
- The **report** half comes from the worker's captured `response.txt`. The
  per-finding disposition line exists nowhere else. `run.py` exports
  `RESPONSE_FILE` when it calls the grader; a hand-run grade should export it
  too. When no response is readable, the report checks FAIL rather than pass
  vacuously.

## Why the grader reads the linter, not the prose

A regroup writes a sentence nobody can predict, so grading it by matching text
would score phrasing. Instead `no_repeated_link_finding` asks the linter, and
`sections_naming` and `sections_matching` count the H2 sections that carry the
target or its material. The protocol is explicit that the surviving link count
is not the measure of a resolved finding; in these fixtures everything the
repeated links carry belongs in one passage, so a genuine reorganization
necessarily clears the warn and the linter's verdict is a sound proxy. Two
checks keep the proxy honest. On the regroup evals, the section checks fail a
run that strips link syntax while the material stays spread across sections,
because the warn then clears for a gathering that never happened. On
`regroup_same_paragraph` the material already sits in one paragraph, so
naming the sibling again in plain text there is the whole edit, and the
section checks instead fail a run that moves material out of that paragraph.
On `surfaced_acceptance_contract` the correct outcome leaves the warn standing,
and dropping a link to clear it fails.

## What stays prose

Whether a gathered sentence reads as one account, and whether a surfaced reason
is the *right* reason, are judgements a regex cannot make. The grader asserts
the disposition and the file state; the `expectations` strings in `evals.json`
carry the substance judgement, and `grade.sh` prints agent-attest notes for
what an operator confirms from `response.txt`.

## Verdict cache

`.eval_cache/<id>.json` holds the last conclusive verdict, keyed on the
`task_fix` skill, the base `task` skill, the `auto_*_task` agents, this
directory, the model, and the prompt. Editing the react protocol invalidates
it. Timeouts and crashes are never cached. They are environmental, not a
property of the inputs.
