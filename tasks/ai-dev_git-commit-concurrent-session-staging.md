---
description: Keep git_commit's whole-repo staging as the default but add a drift-detection guard that pauses when files outside the reviewed set appear (a concurrent session's in-flight work), asking before including them, and biasing to commit-all when detection is uncertain.
scope: plugins/ai_dev/skills/git_commit
created: 2026-06-26T18:38:55
updated: 2026-06-26T19:47:04
reported-by: Andreas Hoffmann
status: open
---

# Add a drift-detection guard to git_commit's whole-repo staging

## Goal

The `git_commit` skill stages the entire working tree (`git add -A`) before committing, which guarantees nothing the user changed is missed but also sweeps files an unrelated concurrent session is mid-edit on into the commit. Keep whole-repo staging as the default — preserving the no-miss guarantee — and add a drift-detection guard on top: when files outside the reviewed set appear in the tree (the concurrency signal), pause and ask whether they belong before committing them. When detection cannot confidently tell foreign drift from this session's own further edits, commit all rather than drop anything. The deliverable is a staging protocol in `SKILL.md` with the scripts as its mechanism.

## Context

- Staging happens at **two** points today. `prepare_commit_context.sh` stages every untracked file (`git ls-files --others --exclude-standard -z | git add`, lines 51-57) so new files show up in the staged diff; `commit_with_message.sh` then runs `git add -A` (line 54) before committing. `references/manual_fallback.md` duplicates both as manual sequences. The guard and any wording change must keep all four sites consistent.
- Failure mode: when a second Claude or Codex session is editing the same working tree, whole-repo staging captures that session's partial, unrelated files into this commit, with a message that does not describe them. Observed in the `ai-assets` repo, where a concurrent wiki-reorganization session's in-flight files were swept into an unrelated commit. The whole-repo default is also why the downstream "verify `git show --stat HEAD` after committing" workaround has to exist at all.
- The whole-repo default stays the backbone on purpose: it guarantees nothing the user changed is missed, and missing an intended file is treated as worse than occasionally over-including one. The guard is therefore additive — it narrows the sweep only where drift is clearly detected, and falls back to commit-all whenever it is in doubt, rather than replacing `git add -A` with a scoped-staging rule that could silently drop an intended file.
- Detection has a known reach limit to record, not solve: a foreign file already present **before** `prepare_commit_context.sh` runs is staged and captured into the reviewed context, so it looks indistinguishable from an intended file and will be committed under the commit-all bias. The guard reliably catches paths that appear or change **after** the context was prepared; the pre-prepare case is accepted as the conservative no-miss tradeoff.
- Separate concern, do not fold in: the untracked-file blind spot of `pre-commit run --all-files` belongs in the consuming repo's docs, not in this staging change.

## Approach

Author the staging protocol once in `SKILL.md` (extend the `<commit_scope>` / `<execution_default>` / `<pause_conditions>` directives into a small decision tree), then implement its mechanism across `prepare_commit_context.sh`, `commit_with_message.sh`, and the matching `references/manual_fallback.md` sequences so prose, scripts, and fallback agree.

The protocol has three branches:

- **Default — commit all.** Stage the whole repo as today and commit, preserving the no-miss guarantee. On a clean single-session tree this proceeds with no prompt, exactly as `<execution_default>` promises now.
- **Detected foreign drift — pause and ask.** When the commit-time tree holds paths that appeared or were modified **after** the reviewed context was prepared and that fall outside the reviewed set, stop and ask the user whether those paths belong in this commit, listing them, rather than sweeping them in silently.
- **In doubt — commit all.** When the guard cannot confidently distinguish foreign drift from this session's own further edits, include everything. The tiebreaker always favors no-miss over no-sweep, so the guard never silently drops a file.

The pause is scoped narrowly to *detected foreign drift only*; an ordinary dirty worktree or pre-existing staged changes with no drift must still proceed without a prompt, so `<execution_default>` keeps its no-prompt promise for the common case and `<pause_conditions>` gains only the drift carve-out.

Mechanism the implementer confirms: where detection lives (the model already holds the reviewed set from the context blob, so the cleanest comparison is commit-time `git status` against that captured set) and how the pause is surfaced. `git add -A` stays the default staging action — guarded by the drift check, not removed.

Non-goals: changing commit-message generation; adding prompts to the no-drift single-session flow; replacing whole-repo staging with a scoped-by-default rule; altering the user's explicit scope-narrowing path.

## Acceptance

- `SKILL.md` carries the protocol: `<commit_scope>` keeps commit-all as the default and documents the drift branch and the commit-all-in-doubt tiebreaker; `<pause_conditions>` gains the narrow foreign-drift carve-out; `<execution_default>` still forbids prompts in the no-drift case. One canonical description remains.
- The workflow detects paths outside the reviewed set that appeared after context preparation and pauses to ask before including them. Running the skill in a tree where an unrelated file is modified after the context is prepared surfaces that path and pauses rather than committing it silently; on a clean single-session tree it commits all intended new and modified files with no prompt.
- When detection is ambiguous, the workflow commits all rather than dropping any file — no intended file is ever silently excluded.
- `references/manual_fallback.md` matches the protocol, including the pause-on-drift step, with no behavior that contradicts the scripted path.
