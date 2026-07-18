---
description: git_commit pre-flight step before gather_context that satisfies tree-mutating agent-directed obligations first, so they aren't skipped, context builds once, and drift ignores self-edits.
scope: plugins/ai_dev/skills/git_commit
created: 2026-07-14T18:41:53
updated: 2026-07-18T05:21:05
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Add a pre-flight committable-state step to git_commit before gather_context

## Goal

Give `git_commit` a pre-flight step at the front of its `<primary_workflow>`, before `<gather_context>`, that brings the working tree to its final committable state before any context is captured. The step's domain is the **agent-directed rules that bear on the commit** — obligations written for an AI agent to read and invoke, living in whatever surface the harness exposes them through (a repo's standing rules, the user's standing rules, an agent memory, a prompt, or anywhere else a harness surfaces instructions to its agent; the location does not matter). Nothing mechanical triggers these, so only an active workflow step makes the agent honor them. Today `<primary_workflow>` opens straight with `<gather_context>` (`prepare_commit_context.sh`), so these rules are surfaced by no step at all, and a run that must still mutate the tree to satisfy one — a lockstep version bump, a changelog update, a lint- or format-fix pass, code generation — reaches that need only after the large context blob is already built, if it reaches it at all.

Three payoffs follow. First, reliability: the step is the single anchor that connects the commit action to the standing agent-directed rules in force, so an obligation like a version bump is honored as part of committing instead of depending on the model to recall a passive background rule mid-run — the failure this task exists to prevent, observed when a run committed a skill edit and skipped the required lockstep version bumps because no workflow step ever surfaced the rule. Second, the context blob is built and read once instead of twice. Third, the reviewed-set baseline captured inside it already contains the model's own pre-commit edits, so the drift guard never mistakes them for a concurrent session's foreign drift.

## Context

`git_commit`'s `SKILL.md` wraps its workflow in `<git_commit_skill>`; `<primary_workflow>` holds the ordered children `<gather_context>`, `<consume_context>`, `<compose_message>`, `<detect_drift>`, `<execute_commit>`. Nothing runs before `<gather_context>` today. The drift guard spans two layers — the model-side `<detect_drift>` prose step and the mechanical backstop inside `commit_with_message.sh` — both comparing a commit-time `git status` against the reviewed-set baseline that `prepare_commit_context.sh` captured right after staging. That two-layer guard shipped in [ai-dev_git-commit-drift-guard-in-script.md](ai-dev_git-commit-drift-guard-in-script.md); this task edits the same `<detect_drift>` / `<execute_commit>` region and `references/manual_fallback.md`, so the two must stay in agreement.

When a tree-mutating obligation is handled only after context capture, its edits land paths absent from the reviewed-set baseline, so `<detect_drift>` and the `commit_with_message.sh` backstop read the committer's own changes as a concurrent session's foreign drift and pause. Recovering then forces a rebuild and re-read of the context blob against the now-mutated tree. Both harms trace to the same gap: the tree is still changing after the step that snapshots it.

The in-scope obligations are defined by their nature, not by a list, so any instance fits without enumerating them all. An **agent-directed rule** here is a standing instruction that is addressed to an AI agent, fires only when the agent chooses to act on it — no command or hook triggers it mechanically — and bears on the commit. What it asks for (a lockstep version bump, a changelog update, a lint- or format-fix) and where it lives (a repo's standing rules, the user's standing rules, an agent memory, a prompt, or anywhere else a harness surfaces instructions to its agent) are both open: the test is that nature, not any wording or location. `git_commit` ships across repos and harnesses, so the step applies this test to whatever the sources available at commit time offer, rather than encoding one repo's rule or naming a single file as the source. The same test draws the line against mechanical hooks: a hook fails the "only the agent invokes it" clause because the commit command fires it, so it is out of scope by that same nature test.

That hook exclusion matters concretely because of double execution. A git hook or a harness hook that the `git commit` command fires on its own already runs at commit time; if the pre-flight step also ran or pre-empted that hook's logic, it would execute twice — once in the pre-flight and again when `commit_with_message.sh` invokes `git commit`. The step leaves command-triggered hooks to the commit command that owns them. (This is also why the framing is agent-directed rules rather than "pre-commit obligations": a reformatting pre-commit hook is exactly the command-triggered case the step stays out of.)

## Approach

Add a new first child of `<primary_workflow>`, before `<gather_context>` (for example `<prepare_worktree>`), that runs as an explicit discover → satisfy → confirm gate rather than a soft preamble. Before gathering context, the model discovers the agent-directed rules that bear on this commit — every standing instruction the agent alone must invoke, wherever the harness surfaces it — satisfies the tree-mutating ones, and confirms each is settled before proceeding to `<gather_context>`, so `prepare_commit_context.sh` then runs once against the final tree. Framing it as a checkpoint the model must clear, not an optional nicety, is what keeps the obligation from being silently skipped.

Scope the step to agent-directed rules and leave command-triggered mechanical hooks to the commit command that fires them — neither running nor pre-empting a hook in the pre-flight — for the double-execution reason set out in the Context.

Distinguish tree-mutating obligations from check-only ones. Only tree-mutating obligations must precede `<gather_context>`, because only they change the baseline; a check-only obligation (a lint that verifies without rewriting) does not invalidate the baseline, though running it in the pre-flight still avoids spending a context build on a tree that will fail the gate.

Keep `git_commit` the orchestrator of ordering, not the owner of each obligation's logic. Because it is repo- and harness-agnostic, the step names no specific repo's rule and no single harness file as the sole source, references the rule sources generically, and defers the specifics of what to run to the repo. State all three payoffs where the step is defined: obligations are honored rather than skipped, context is built once, and the drift baseline already includes the model's own pre-commit edits.

Mirror the pre-flight ordering into `references/manual_fallback.md` so the manual path agrees with the scripted one. Keep `<detect_drift>` and `<execute_commit>` consistent: the drift guard is unchanged and is not weakened; self-inflicted post-capture edits are prevented by ordering, not by relaxing the guard. Reconcile any existing wording that implies context-gathering is the unconditional first workflow action so it reads as following the pre-flight step.

Non-goals: changing commit-message composition, the commit-all default, or the no-miss-over-no-sweep tiebreaker; weakening the drift guard or the `--accept-drift` path; turning `git_commit` into the runner that enumerates and executes each repo's specific lint, format, version, or hook logic; running or pre-empting command-triggered git or harness hooks; and encoding any model-tier or model-capability branch — the step is one strong, clearly-anchored gate for every model, not conditional on which model runs.

## Acceptance

- `<primary_workflow>` gains a step before `<gather_context>` that instructs the model to bring the working tree to its final committable state — satisfying the tree-mutating agent-directed obligations that bear on the commit — before context is gathered.
- The step reads as an explicit discover → satisfy → confirm gate the model must clear, not a soft preamble: it directs the model to confirm each discovered tree-mutating obligation is settled before proceeding, so an obligation cannot be silently skipped.
- The step defines its in-scope domain by nature, not by an enumeration: a standing instruction addressed to the agent that only the agent invokes and that bears on the commit, with any example surfaces named as open-ended so a source not listed still qualifies. It stays repo- and harness-agnostic, naming no single repo's rule and no single harness file as the source; confirm by reading the step that no hardcoded repo rule and no single-harness filename appears in it.
- The step explicitly excludes command-triggered mechanical hooks (git hooks, harness commit hooks) from its scope, with the rationale that such hooks run at commit time on their own and must not be duplicated in the pre-flight.
- The step's rationale states all three payoffs explicitly: obligations are honored rather than skipped; `prepare_commit_context.sh` runs once (no rebuild, no re-read); and the reviewed-set baseline already contains the model's own pre-commit edits so `<detect_drift>` and the `commit_with_message.sh` backstop do not flag them as foreign drift.
- The step distinguishes tree-mutating obligations from check-only ones and requires only the tree-mutating ones to precede `<gather_context>`.
- `references/manual_fallback.md` carries the same pre-flight ordering, with no step that contradicts the scripted path and one canonical statement of the ordering.
- `<detect_drift>` and `<execute_commit>` keep the drift guard's behavior intact — the guard is not weakened and `--accept-drift` is unchanged — and any prior wording implying context-gathering is the unconditional first workflow action is reconciled so one canonical ordering, pre-flight then gather, remains.
