---
description: Stage logging copies of git_checkout and git_commit in the git_review eval sandbox and grade evals 10, 12, and 48 on the sibling helper calls instead of attest lines.
scope: tests/git_review
created: 2026-10-02T08:23:20Z
updated: 2026-10-03T19:42:59Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Make git_review's sibling handoffs observable in its harness

## Goal

The `git_review` harness proves the two handoffs the parent task's acceptance names: a run asked to be put onto a remote-only branch switches through `git_checkout`, and a run asked to commit a fix commits through `git_commit`. Evals 10 and 12 grade the `git_checkout` helper call, and eval 48 grades the `git_commit` helper call, each from the sandbox's script log, so a run that hand-runs `git switch` or `git commit` fails.

## Context

`tests/git_review/evals/stage.sh` copies the skill under test into the eval target through `stage_skill_copy` and replaces each bundled script with a logging shim that appends to `script_calls.log` and then runs the real script. It shims only `git_review`'s own `scripts/`. The `WORKER_PROMPT` in `tests/git_review/evals/run.py` names only the `git_review` copy, so the worker reaches the siblings by whatever route its harness offers, and no shim sees the call. After `stage.sh`, `run.py` rebinds `{skill_path}` by copying that `git_review` tree into `artefacts/` via `vendor.stage_skill_tree`, so sibling paths derived from the rebound `{skill_path}` do not exist today.

The `10)` case in `tests/git_review/evals/grade.sh` leaves the `git_checkout` handoff as an `agent-attest` line; the `12)` case checks the dirty-tree blocking outcome (`on_branch`, `file_contains`, `no_stash`, `says`) and has no `git_checkout` attest. Eval 10's response may omit naming `git_checkout`; eval 12's response sometimes names it, so transcript narration is not a stable proof surface for that handoff. The `48)` case checks the commit subject's `file name -> concrete change` form, but the fixture's own history already uses that form, so a hand-run commit that copies it passes too. The sibling helpers are `scripts/checkout_branch.sh` in `git_checkout`, and `scripts/prepare_commit_context.sh` and `scripts/commit_with_message.sh` in `git_commit`. Eval 12's expectations in `evals.json` list only the dirty-tree outcomes and carry no sibling-handoff line today.

The cache key in `run.py`, built by `source_roots_for`, already hashes both sibling source directories, so the cache needs no change for the copies. The runner is vendor-aware; fresh proof runs use `--vendor cursor` per `TESTING.md`. A change to `WORKER_PROMPT` moves every eval's cache key, so the regression re-run after this change covers the whole suite once under that vendor.

## Approach

Extend `stage_skill_copy` in `stage.sh` so it stages `git_checkout` and `git_commit` beside the `git_review` copy under the eval target, shimming every bundled script in both the same way. Rewrite in place the Layout comment block so it names the sibling skill directories beside `git_review`, and rewrite in place the shim-rationale comment above `stage_skill_copy` so it covers those sibling copies. Rewrite `WORKER_PROMPT` in `run.py` so it names the eval-target sibling `SKILL.md` paths under `$target/skill/` that `stage.sh` produced (the shimmed copies that share `script_calls.log`) and instructs the worker to resolve those named sibling handoffs through the staged `$target/skill/{git_checkout,git_commit}/SKILL.md` paths and their bundled scripts. Keep `{skill_path}` as the artefacts-rebound `git_review` path; do not derive sibling paths from that rebound path, and do not also `stage_skill_tree` the siblings into `artefacts/`. The skill itself names its siblings by name only, per the standing repo rule on deployment-agnostic cross-references, so the harness supplies the paths.

Replace the `git_checkout` attest line in the `10)` case with `script_called "checkout_branch.sh"`, add `script_called "checkout_branch.sh"` to the `12)` case beside its existing checks, and replace the `git_commit` attest line in the `48)` case with `script_called "commit_with_message.sh"`, removing the comment above that attest that says the check stays an attest because subject form and trailer are the real evidence. Rewrite the sibling-handoff expectations for evals 10 and 48 in `evals.json` in place, add a sibling-handoff expectation for eval 12 that names the script-log / `script_called` proof, and rewrite the eval entries in `tests/git_review/evals/README.md` in place. Rewrite in place the `## Stage a fixture by hand to inspect it` section in `tests/git_review/RUNBOOK.md` so it records that staging places shimmed `git_checkout` and `git_commit` copies under the eval target beside `git_review` and that those shims append to the same `script_calls.log`. Leave `## The verdict cache` unchanged.

## Acceptance

- A staged eval target carries shimmed copies of `git_checkout` and `git_commit` beside the `git_review` copy, and running a shimmed `checkout_branch.sh --help` appends one line to `script_calls.log` and prints the real script's usage.
- In `tests/git_review/evals/stage.sh`, the Layout comment block names the staged `git_checkout` and `git_commit` directories beside `git_review`, and the shim-rationale comment above `stage_skill_copy` covers those sibling copies.
- The worker prompt `run.py` builds for any eval names both eval-target sibling `SKILL.md` paths under the `stage.sh` skill layout (`$target/skill/`), instructs the worker to resolve those named sibling handoffs through those staged paths and their bundled scripts, and does not derive those paths from the artefacts-rebound `{skill_path}`.
- After `run.py` rebinds `{skill_path}` by copying the `git_review` tree into `artefacts/` via `vendor.stage_skill_tree`, shimmed `git_checkout` and `git_commit` copies exist under the `stage.sh` `$target/skill/` layout and are absent from the artefacts skill tree that `{skill_path}` points at.
- Staging evals 10 and 12 and grading each against an empty `script_calls.log` fails the new `checkout_branch.sh` check, and staging eval 48 and grading it against an empty `script_calls.log` fails the new `commit_with_message.sh` check.
- In `tests/git_review/evals/evals.json`, the sibling-handoff expectations for evals 10, 12, and 48 name the script-log / `script_called` proof for the helper instead of attest or transcript narration of that handoff.
- The `tests/git_review/evals/README.md` entries for evals 10, 12, and 48 describe grading from `script_calls.log`.
- The `## Stage a fixture by hand to inspect it` section in `tests/git_review/RUNBOOK.md` states that staging places shimmed `git_checkout` and `git_commit` copies under the eval target beside `git_review` and that those shims append to the same `script_calls.log`.
- The `## The verdict cache` section in `tests/git_review/RUNBOOK.md` still states that the key covers the `git_checkout` and `git_commit` skill directories.
- In `tests/git_review/evals/grade.sh`, the `10)` and `12)` cases each grade the sibling handoff with `script_called "checkout_branch.sh"`, the `10)` case carries no `git_checkout` handoff `agent-attest` line, and the `48)` case grades the sibling handoff with `script_called "commit_with_message.sh"`, carries no `git_commit` handoff `agent-attest` line, and carries no comment saying the check stays an attest because subject form and trailer are the real evidence.
- Evals 10, 12, and 48 each pass on a fresh `python3 tests/git_review/evals/run.py --vendor cursor <id>` run, with the sibling helper call in that run's script log.
