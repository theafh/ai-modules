---
description: "Reject an unresolvable --task path in run_relay.sh and state that the run stops there, so a mistyped scope anchor cannot silently narrow the run or let an agent fabricate a scope nobody authored."
scope: plugins/ai_dev/skills/git_auto_review
created: 2026-10-28T19:49:14
updated: 2026-10-29T12:21:36
status: ready
reported-by: Andreas Hoffmann
---

# Reject an unresolvable task path in the git_auto_review relay init

## Goal

A `git_auto_review` run given a task file path that does not resolve stops at
`scripts/run_relay.sh` with an environment failure instead of proceeding, and
the skill states what a run does with a task path it cannot read. The
user-visible outcome: a mistyped scope anchor can neither silently narrow the
run to the narrower scope disjunct nor leave an agent free to invent an anchor
and write working-tree changes against a scope nobody authored.

## Context

`git_auto_review` takes an optional task file path that anchors scope. The
relay derives the run stem from that path's basename without reading the file,
so today the path is pure string input:

```text
run_relay.sh --task tasks/typo_does_not_exist.md --root <repo>
Relay initialised at <repo>/.git_auto_review/typo_does_not_exist
exit 0
```

It exits 0 and reports success. No surface that receives the task file path
contemplates its absence. `auto_verifier_git`'s `unable` clause
enumerates exactly what it refuses on — the gate return, the diff, the ledger,
and the target — and the task file is deliberately not among them, so an
unreadable anchor is an unhandled state rather than a refusal condition.

The consequence is asymmetric because the task file carries the wider of the
two **Scope anchor.** disjuncts. Without it a run falls back to "lines the
change added or modified" alone, so an agent that treats the missing file as
absent under-fixes, and one that honours "read the anchoring task file" anyway
can fabricate a boundary and write to the tree on it.

The gap shows as an internal inconsistency. `<inputs>` specifies a fallback for
the optional round cap and none for the optional task path, and `<initialise>`
restates both in one sentence while still giving a fallback for only the cap.

## Approach

Add one guard to `scripts/run_relay.sh`. Resolve `--task` against the already
resolved `repo_root` when the value is relative, because relay paths resolve
from that root and a value relative to the caller's cwd would reject correct
invocations. Reject the value through the existing `die_env` path when the
resolved target is not a readable regular file. Place the guard before the
`mkdir` of `.git_auto_review`, so a rejected path creates no directory, no
`.gitignore`, and no `ledger.txt`, which is exactly the state
`<initialise>` already promises for a helper that exits non-zero.

Rewrite the `<inputs>` task-path bullet, the `<initialise>` sentence, and the
`<relay>` `<run-stem>` derivation sentence in `SKILL.md` so each names the
rejection and the stop it causes, with `<relay>` pointing at the `<inputs>`
bullet's canonical statement, as one canonical statement per surface: a task
path that does not resolve is reported by `scripts/run_relay.sh` and the run
stops under `<agent_failure_policy>`'s `helper-script` class, the state
`<initialise>`'s following paragraph already defines. Extend the script's
`--help` text and its header comment to name the rejection, since both
currently describe the stem derivation as unconditional.

Keep `auto_verifier_git` unchanged. The init stop makes an unreadable anchor
unreachable through the normal path, because the run ends before any verifier
invocation, so adding a second refusal at the verifier would duplicate the check
in a place that cannot see the path as a path.

Add the assertion to the existing `s7_relay_init_and_preseed` scenario in
`tests/git_auto_review/script_tests/run.sh`, beside the stem-derivation
assertion it already carries. That scenario stages its anchor file inside its
own sandbox, so it exercises the root-relative resolution the guard introduces.

The guard also reaches
`tests/git_auto_review/evals/fixtures/routes_decision/setup.sh`, which today
runs `init_repo`, `seed_in_scope_change`, `record_head`, `record_index`, then
`preseed_gate "$target" default 1 "$HERE/gate-r1.txt"`, and stages no anchor
file while its prompt names `tasks/demo_decision.md`. Rewrite that fixture in
place: insert `seed_task_file "$target" tasks/demo_decision.md` before
`record_head`, as the sibling fixtures that seed an anchor do, and pass
`"$(stem_for tasks/demo_decision.md)"` to `preseed_gate` in place of `default`.
The seed commit lands before `record_head` writes `.head.before`, so the
recorded HEAD is the seed commit itself and `grade.sh`'s `head_unchanged` check
compares `HEAD` against that same commit. The fixture's default Goal suffices,
because its only finding sits in the change's own modified lines. The eval then
reaches the decision-pending stop its expectations assert instead of stopping
at init under `helper-script`.

**Out of scope:** A general review of `run_relay.sh` argument validation beyond
`--task`; `--root` already validates its own value.

## Acceptance

1. `scripts/run_relay.sh --task <path that does not exist> --root <repo>` exits
   with the script's environment exit code and prints a message naming the
   unresolvable path, and the invocation leaves no relay state for that path
   under `<repo>`: no `.git_auto_review/<stem>` directory and no `ledger.txt`
   inside it, where `<stem>` is the basename without its extension.
2. `scripts/run_relay.sh --task <existing file> --root <repo>` still exits 0
   and creates `.git_auto_review/<stem>/ledger.txt`, with `<stem>` the
   basename without its extension, where the path is given relative to
   `<repo>` rather than to the caller's working directory.
3. `tests/git_auto_review/script_tests/run.sh` scenario `s7` asserts both
   outcomes of items 1 and 2, and all scenarios in that file pass.
4. The `<inputs>` task-path bullet, the `<initialise>` sentence, and the
   `<relay>` `<run-stem>` derivation sentence each name the rejection and the
   `helper-script` init stop, with `<relay>` pointing at the `<inputs>` bullet's
   canonical statement, and no surface describes stem derivation as
   unconditional: the script's header comment and `--help` text name the
   rejection.
5. The `routes_decision` fixture stages `tasks/demo_decision.md` and pre-seeds
   its round-1 gate pair under the derived `demo_decision` stem, and
   `python3 tests/git_auto_review/evals/run.py --force routes_decision` exits 0
   and prints the runner's `PASS` line for `routes_decision`, so the item reads
   the runner's whole verdict rather than only `grade.sh`'s expectation output.
6. In a repository with no prior relay state for the stem,
   `scripts/run_relay.sh --task <existing directory> --root <repo>` exits with
   the script's environment exit code and prints a message naming that path,
   and the invocation leaves no `.git_auto_review/<stem>` directory and no
   `ledger.txt` under `<repo>`, where `<stem>` is the directory basename
   without its extension.
7. In a repository with no prior relay state for the stem,
   `scripts/run_relay.sh --task <existing regular file without read permission>
   --root <repo>` exits with the script's environment exit code and prints a
   message naming that path, and the invocation leaves no
   `.git_auto_review/<stem>` directory and no `ledger.txt` under `<repo>`, where
   `<stem>` is the file's basename without its extension.
