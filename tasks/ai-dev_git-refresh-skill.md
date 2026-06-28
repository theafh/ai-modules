---
description: Add a git_refresh skill to ai_dev that fast-forwards the repo's default branch and deletes cleanly-merged local branches by default, gating riskier branch pruning behind an explicit opt-in.
scope: plugins/ai_dev/skills
created: 2026-06-28T18:53:29
updated: 2026-06-28T19:10:29
status: open
reported-by: Andreas Hoffmann
---

# Add a git_refresh skill

## Goal

Add a new `git_refresh` skill to the `ai_dev` plugin: a one-shot "get my local repo back to a clean, current state" command. By default it does only provably safe work — switch to the repository's default branch, fast-forward it to its upstream, and delete the cleanly-merged local branches a merge left behind — and it gates riskier branch pruning behind an explicit user opt-in. It is the cleanup counterpart to `git_commit` in the same `git_*` family, and like `git_commit` it operates on the repository where it is invoked. Ship it at `version: 1.0.0`.

The user-visible outcome: after a default run, the repo sits on an up-to-date default branch with cleanly-merged local branches removed and every branch that could still hold unmerged or unpushed work left untouched. The run closes by reporting in detail what it did — fetched and pruned, which default branch it detected, the switch, how far it fast-forwarded, and each branch it deleted — and then, only when valid riskier candidates exist (upstream-gone or squash-merged branches, or branches a force-delete would remove), ends with a follow-up question offering to handle them behind a per-branch safety check. When no such candidates remain, it says there is nothing further to do.

## Context

This captures a recurring chore — the post-merge "clear the branches a merged PR left behind and get back to a fresh main" cleanup. The happy path alone (switch default branch, `pull --ff-only`, delete merged branches) is a trivial shell sequence; what earns it a skill is the judgment-and-safety layer around the destructive branch-deletion step, the same justification profile that makes [git_commit](../plugins/ai_dev/skills/git_commit/SKILL.md) a skill rather than an alias.

Two things make naive cleanup wrong. First, `git branch --merged` does not report a **squash-merged** branch as merged, because the squash produced a new commit the branch tip is not an ancestor of — and squash-merged PRs are the most common reason local branches pile up. Catching those needs the "upstream tracking branch is `[gone]`" signal that `git branch -vv` / `git for-each-ref` report after a pruning fetch. Second, an upstream-gone branch can equally be one carrying genuine unpushed or unmerged commits the user would lose on a force-delete, so the skill must tell those two cases apart instead of force-deleting everything that looks gone.

`git_commit` is the structural model to follow: a pseudo-XML skill body, a bundled `scripts/` helper that does the git work, a `references/` manual-fallback path, a clear policy block, and `disable-model-invocation: true`. `git_refresh` takes that last setting too — branch deletion is destructive, so it stays an explicit `/git_refresh` invocation rather than something the router can auto-trigger. The standing repo rules own skill authoring, registration, versioning, and the both-audiences `description:` contract; this task supplies only the `git_refresh`-specific behaviour.

## Approach

Implement the skill as `plugins/ai_dev/skills/git_refresh/SKILL.md` with a bundled `scripts/` helper and a `references/` manual-fallback note, following the standing repo rules and the pseudo-XML / positive-language conventions.

The skill splits into a safe default run and explicit, gated extensions.

**Default run — provably safe.** Invoking `/git_refresh` with no further request does only work that cannot drop committed work, so the work itself needs no confirmation prompt and runs straight through:

- **Detect the default branch, never hardcode it.** Resolve it from the remote HEAD (`git symbolic-ref refs/remotes/origin/HEAD`, with `git remote show origin` as a fallback) so the skill works on `main`, `master`, or any other default, and degrade with a clear message when no remote HEAD resolves.
- **Pruning fetch** (`git fetch --prune`) to refresh remote-tracking refs.
- **Switch to the default branch and fast-forward it** to its upstream by fast-forward only (`git pull --ff-only`, or fetch then `merge --ff-only`), never a merge commit or rebase, matching the standing private-repo "fast-forward first" workflow. Report and leave it untouched when the upstream has diverged and cannot fast-forward.
- **Delete only cleanly-merged local branches** with `git branch -d`, which refuses any branch not fully merged, so the default run can never drop unmerged work. The current branch and the default branch are never candidates.
- **Stay conservative on a dirty worktree.** When uncommitted changes would block switching, surface that state and skip the steps it blocks rather than auto-stashing — never discard or hide user changes to make the workflow proceed.
- **Report in detail, then offer the valid gated actions.** Close the default run with a concrete account of every action taken — the fetch and prune, the default branch it detected, the switch, how far it fast-forwarded, and each branch it deleted. Then, when valid riskier candidates exist, end with a single follow-up question that surfaces them and offers to act: list the upstream-gone / squash-merged branches, marking which are safe to remove and which would require a force-delete (naming the commits that would be lost). When no such candidates exist, state plainly that nothing further remains.

**Gated extensions — only on the user's opt-in.** The riskier actions run only when the user opts in, whether by answering the default run's closing offer above or by asking for them directly; the default run never performs them on its own. The skill body holds each as a nested sub-rule carrying its recommended git command sequence and its own safety check:

- **Prune upstream-gone branches** — the squash-merge case, where a merged PR's remote branch was deleted and `git branch --merged` cannot see the local branch as merged. Recommended sequence: list candidates with `git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads` (or `git branch -vv`) filtering for `[gone]`; for each, check for commits absent from the default branch with `git log --oneline <default>..<branch>`; delete the ones with no unique commits via `git branch -d`, and for any branch that does carry unique commits, show those commits and require an explicit confirmation before `git branch -D`.
- **Force-delete an unmerged branch** — recommended sequence: show exactly the commits that would be lost with `git log --oneline <default>..<branch>`, then proceed to `git branch -D` only after an explicit confirmation.

These recommended command sequences are the content the user asked to live inline in the skill's sub-rules; keep them as concrete guidance the skill follows when the gate opens, not as steps the default run ever reaches.

Bundle the git logic under `scripts/` per the repo's helper-script rule, and apply the [harness_portability](../plugins/ai_dev/skills/harness_portability/SKILL.md) skill so the script runs under both OpenAI Codex and Anthropic Claude and across macOS and Linux — BSD-vs-GNU differences in `git` porcelain parsing, `sed`, and `grep` are the usual breakage. Write the skill's own `description:` for both audiences per the standing rule: a compact statement of what it does plus router trigger phrases such as "clean up branches", "refresh main", "delete merged branches", "get back to a clean main", and "prune stale local branches". Mirror the `tests/git_commit/` skill-creator-aligned harness pattern for the new test surface.

This adds shipped content under `plugins/ai_dev/`, so the standing registration and versioning gates apply: the new skill ships at `1.0.0`, and adding it counts as a plugin edit, so the `ai_dev` plugin version rises in lockstep across both `plugin.json` files and both marketplace registrations in the commit that lands it.

## Acceptance

- A new `plugins/ai_dev/skills/git_refresh/SKILL.md` exists with frontmatter `name: git_refresh`, `version: 1.0.0`, `disable-model-invocation: true`, and a both-audiences `description:` carrying the trigger phrases.
- The skill resolves the default branch from the remote HEAD rather than a hardcoded `main`: a fixture repo whose default branch is `master` refreshes correctly.
- The skill updates the default branch by fast-forward only; a diverged, non-fast-forward upstream is reported and left unchanged rather than merged or rebased.
- The default run performs its safe work without per-action prompts: on a staged fixture it fast-forwards the default branch and removes a cleanly-merged branch via `git branch -d`, while leaving an upstream-gone branch that carries a unique unpushed commit undeleted.
- The default run never runs `git branch -D` and never prunes upstream-gone branches; both happen only on the user's opt-in.
- The default run ends with a detailed report of every action it took — the fetch and prune, the detected default branch, the switch, the fast-forward extent, and each deleted branch.
- When valid riskier candidates exist, the run closes with a follow-up question that surfaces them — upstream-gone / squash-merged branches, marked as safe to remove or as requiring a force-delete with the commits that would be lost — and offers to act; when none exist, it states that nothing further remains. A staged fixture with such a branch produces the offer, and one without produces the nothing-further message.
- The current branch and the default branch are never deleted.
- On a dirty worktree that blocks switching, the default run surfaces the state and skips the blocked steps without stashing, discarding, or hiding the changes.
- Gated upstream-gone pruning exists as a nested sub-rule carrying its recommended command sequence: it deletes a gone branch with no unique commits via `git branch -d`, and for a gone branch carrying a unique commit it shows that commit and requires an explicit confirmation before `git branch -D` — covering the squash-merge cleanup case.
- Gated force-delete shows the commits that would be lost before any `git branch -D` and requires an explicit confirmation.
- The skill bundles its git logic under `scripts/` and carries a `references/` manual-fallback note, mirroring `git_commit`'s structure.
- A `tests/git_refresh/` harness exists following the skill-creator-aligned pattern (script tests under `script_tests/`, evals under `evals/`), covering default-branch detection, the safe default run (deletes merged, leaves an upstream-gone-with-unpushed branch untouched), the closing report and conditional offer (offer present when a gated candidate exists, nothing-further message when none do), and the gated upstream-gone pruning with its per-branch safety check, on staged fixtures.
- The skill is registered in the `ai_dev` `plugin.json` (Claude and Codex), both marketplace registrations, `plugins/ai_dev/README.md`, and the root `README.md` layout tree and skill list; the ai_dev plugin version rises in lockstep in the landing commit while the new skill stays at `1.0.0`.
- The plugin README's "Git history" grouping is rewritten to cover the broader git family (for example "Git") so `git_refresh` files sensibly beside `git_commit`.
