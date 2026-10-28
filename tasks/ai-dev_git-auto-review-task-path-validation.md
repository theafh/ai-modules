---
description: "Reject an unresolvable --task path in run_relay.sh and give the git_auto_review run a stated fallback, so a mistyped scope anchor cannot silently narrow or fabricate scope."
scope: plugins/ai_dev/skills/git_auto_review
created: 2026-10-28T19:49:14
updated: 2026-10-28T19:49:14
status: open
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

It exits 0 and reports success. Three surfaces are told to read the path and
none contemplates its absence: the skill's `<inputs>`, `auto_gate_git`'s
inputs, and `auto_verifier_git`'s inputs. `auto_verifier_git`'s `unable` clause
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

Rewrite the `<inputs>` task-path bullet and the `<initialise>` sentence in
`SKILL.md` so each states the fallback beside the round cap's, as one canonical
statement per surface: a task path that does not resolve is reported and the
run proceeds with no anchor. Extend the script's `--help` text and its header
comment to name the rejection, since both currently describe the stem
derivation as unconditional.

Keep `auto_verifier_git` unchanged. The stated fallback makes an unreadable
anchor unreachable through the normal path, and the guard closes the rest, so
adding a second refusal at the verifier would duplicate the check in a place
that cannot see the path as a path.

Add the assertion to the existing `s7_relay_init_and_preseed` scenario in
`tests/git_auto_review/script_tests/run.sh`, beside the stem-derivation
assertion it already carries. That scenario stages its anchor file inside its
own sandbox, so it exercises the root-relative resolution the guard introduces.

**Out of scope:** A general review of `run_relay.sh` argument validation beyond
`--task`; `--root` already validates its own value.

## Acceptance

1. `scripts/run_relay.sh --task <path that does not exist> --root <repo>` exits
   with the script's environment exit code and prints a message naming the
   unresolvable path, and the invocation leaves no `.git_auto_review`
   directory under `<repo>`.
2. `scripts/run_relay.sh --task <existing file> --root <repo>` still exits 0
   and creates `.git_auto_review/<stem>/ledger.txt`, with `<stem>` the
   basename without its extension, where the path is given relative to
   `<repo>` rather than to the caller's working directory.
3. `tests/git_auto_review/script_tests/run.sh` scenario `s7` asserts both
   outcomes of items 1 and 2, and all scenarios in that file pass.
4. The `<inputs>` task-path bullet and the `<initialise>` sentence each state
   the unresolvable-path fallback, and no surface describes stem derivation as
   unconditional: the script's header comment and `--help` text name the
   rejection.
5. `make lint` passes, and the plugin version moves as the standing repo rules
   direct for an edit to an existing skill, with the plugin manifests and both
   marketplace registrations in lockstep.
