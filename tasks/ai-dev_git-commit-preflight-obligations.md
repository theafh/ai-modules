---
description: Add a git_commit pre-flight step before gather_context that brings the working tree to its committable state first, so context builds once and drift never flags the model's own edits.
scope: plugins/ai_dev/skills/git_commit
created: 2026-07-14T18:41:53
updated: 2026-07-14T19:12:15
status: open
reported-by: Andreas Hoffmann
---

# Add a pre-flight committable-state step to git_commit before gather_context

## Goal

Give `git_commit` a pre-flight step at the front of its `<primary_workflow>`, before `<gather_context>`, that brings the working tree to its final committable state before any context is captured. Today the workflow opens with `<gather_context>` (`prepare_commit_context.sh`), so a run that must still mutate the tree to satisfy a repo's standing pre-commit obligations — a version bump, a formatter pass, code generation, a reformatting pre-commit hook — reaches that need only after the large context blob is already built. After this task the model satisfies tree-mutating obligations first, then `prepare_commit_context.sh` runs once against the settled tree. Two payoffs follow: the context blob is built and read once instead of twice, and the reviewed-set baseline captured inside it already contains the model's own pre-commit edits, so the drift guard never mistakes them for a concurrent session's foreign drift.

## Context

`git_commit`'s `SKILL.md` wraps its workflow in `<git_commit_skill>`; `<primary_workflow>` holds the ordered children `<gather_context>`, `<consume_context>`, `<compose_message>`, `<detect_drift>`, `<execute_commit>`. Nothing runs before `<gather_context>` today. The drift guard spans two layers — the model-side `<detect_drift>` prose step and the mechanical backstop inside `commit_with_message.sh` — both comparing a commit-time `git status` against the reviewed-set baseline that `prepare_commit_context.sh` captured right after staging. That two-layer guard shipped in [archive/ai-dev_git-commit-drift-guard-in-script.md](archive/ai-dev_git-commit-drift-guard-in-script.md); this task edits the same `<detect_drift>` / `<execute_commit>` region and `references/manual_fallback.md`, so the two must stay in agreement.

When a tree-mutating obligation is handled only after context capture, its edits land paths absent from the reviewed-set baseline, so `<detect_drift>` and the `commit_with_message.sh` backstop read the committer's own changes as a concurrent session's foreign drift and pause. Recovering then forces a rebuild and re-read of the context blob against the now-mutated tree. Both harms trace to the same gap: the tree is still changing after the step that snapshots it.

The repo's standing rules already require a lint-clean tree and lockstep version bumps before a commit; the skill simply has no step that sequences such tree-mutating obligations ahead of context capture. Which obligations exist is repo- and harness-specific, and `git_commit` ships across repos and harnesses, so the step discovers them generically rather than encoding any one repo's rules.

## Approach

Add a new first child of `<primary_workflow>`, before `<gather_context>` (for example `<prepare_worktree>`), instructing the model — before gathering context — to bring the working tree to its final committable state. The step directs the model to discover the repo's standing pre-commit obligations from the sources actually available at commit time (the repo's own standing rules, the harness's standing rule and memory files, and any configured pre-commit tooling) and to satisfy the tree-mutating ones — formatter or lint auto-fix passes, version bumps, code generation, reformatting hooks — so that `prepare_commit_context.sh` then runs once against the settled tree.

Distinguish tree-mutating obligations from check-only ones. Only tree-mutating obligations must precede `<gather_context>`, because only they change the baseline; a check-only obligation (a lint that verifies without rewriting) does not invalidate the baseline, though running it in the pre-flight still avoids spending a context build on a tree that will fail the gate.

Keep `git_commit` the orchestrator of ordering, not the owner of each obligation's logic. Because it is repo- and harness-agnostic, the step names no specific repo's rule and no single harness file as the sole source, references the obligation sources generically, and defers the specifics of what to run to the repo. State both payoffs where the step is defined: context is built once, and the drift baseline already includes the model's own pre-commit edits.

Mirror the pre-flight ordering into `references/manual_fallback.md` so the manual path agrees with the scripted one. Keep `<detect_drift>` and `<execute_commit>` consistent: the drift guard is unchanged and is not weakened; self-inflicted post-capture edits are prevented by ordering, not by relaxing the guard. Reconcile any existing wording that implies context-gathering is the unconditional first workflow action so it reads as following the pre-flight step.

Non-goals: changing commit-message composition, the commit-all default, or the no-miss-over-no-sweep tiebreaker; weakening the drift guard or the `--accept-drift` path; and turning `git_commit` into the runner that enumerates and executes each repo's specific lint, format, version, or hook logic.

## Acceptance

- `<primary_workflow>` gains a step before `<gather_context>` that instructs the model to bring the working tree to its final committable state — satisfying tree-mutating pre-commit obligations — before context is gathered.
- The step is repo- and harness-agnostic: it names no single repo's rule and no single harness file as the sole obligation source, instead referencing the repo's standing rules, the harness's standing rule and memory files, and configured pre-commit tooling generically. Confirm by reading the step that no hardcoded repo rule and no single-harness filename appears in it.
- The step's rationale states both payoffs explicitly: `prepare_commit_context.sh` runs once (no rebuild, no re-read), and the reviewed-set baseline already contains the model's own pre-commit edits so `<detect_drift>` and the `commit_with_message.sh` backstop do not flag them as foreign drift.
- The step distinguishes tree-mutating obligations from check-only ones and requires only the tree-mutating ones to precede `<gather_context>`.
- `references/manual_fallback.md` carries the same pre-flight ordering, with no step that contradicts the scripted path and one canonical statement of the ordering.
- `<detect_drift>` and `<execute_commit>` keep the drift guard's behavior intact — the guard is not weakened and `--accept-drift` is unchanged — and any prior wording implying context-gathering is the unconditional first workflow action is reconciled so one canonical ordering, pre-flight then gather, remains.
