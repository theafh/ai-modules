---
description: Add a git_checkout skill to ai_dev that switches the repo onto an existing branch wherever it lives, creating a tracking branch from the sole remote carrying the name and holding on ambiguity.
scope: plugins/ai_dev/skills
created: 2026-09-02T18:13:37
updated: 2026-09-02T19:52:26
status: audited
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Add a git_checkout skill

## Goal

Add a new `git_checkout` skill to the `ai_dev` plugin as the third member of the `git_*` family beside `git_commit` and `git_refresh`. It serves one request: put the repository onto an existing branch the user names, whether that branch is already local, exists only on a remote, or needs a choice between remotes that carry the same name. Ship it at `version: 1.0.0`.

The user-visible outcome: after invoking the skill with a branch name, the repository sits on a local branch of that same name, tracking the remote branch it came from when it had to be created, and the run reports which path it took. When the name resolves on several remotes, the run holds and asks which remote to track. When it resolves nowhere, the run says so and stops without creating anything.

## Context

The chore is the everyday "somebody pushed a branch, put me on it" step. Git already covers the happy path: `git switch <name>` finds `origin/<name>`, creates a local branch tracking it, and switches, a behaviour git calls DWIM. What earns a skill is the judgment around that path, where the plain command either fails or does something the user did not ask for.

Four cases carry the value. The remote-tracking ref has to exist locally before DWIM can fire, so a branch pushed after the last fetch needs a fetch first. A name carried by several remotes makes git refuse rather than guess, and the fix is to name the remote explicitly. A narrow `fetch` refspec or a single-branch clone means the remote-tracking ref never arrives at all, and the resulting `pathspec did not match` message points nowhere near that cause. Finally, reaching for the remote-tracking ref directly, as in a checkout of `origin/<name>`, lands in detached `HEAD`, where later commits attach to no branch, so the skill resolves such an argument to the local branch name instead of detaching.

The skill takes the `git_checkout` name for family coherence with `git_commit` and `git_refresh`, and because "checkout" is the word users type. The name is broader than the behaviour, since `git checkout` also restores paths over uncommitted work, so the `description:` and the skill body carry the boundary explicitly rather than leaving the router to infer it from the name.

[git_refresh](../plugins/ai_dev/skills/git_refresh/SKILL.md) is the structural and behavioural model to follow: a pseudo-XML skill body, the git work bundled under `scripts/`, a `references/` manual-fallback note, and the conservative dirty-worktree stance that surfaces blocked state rather than stashing it. Both existing siblings also put the explicit-request guard in the `description:` prose rather than in a frontmatter flag, and `git_checkout` follows that same convention. The standing repo rules own skill authoring, registration, versioning, and the both-audiences `description:` contract; this task supplies only the `git_checkout`-specific behaviour.

## Approach

Implement the skill as `plugins/ai_dev/skills/git_checkout/SKILL.md` with a bundled `scripts/` helper and a `references/` manual-fallback note, following the standing repo rules and the pseudo-XML and positive-language conventions.

The run resolves the branch name the user gave, then switches, in this order:

- **Normalize the argument to a branch name.** Accept a bare name and a remote-qualified form such as `origin/<name>`, and reduce the qualified form to the local branch name plus its named remote. A remote-qualified argument selects that remote: the run skips the multi-remote hold, tracks or reports against that remote only, and on a miss for that remote reports the miss and creates nothing without falling through to other remotes. Bare and qualified forms both create or switch to a named local branch rather than detaching `HEAD`.
- **Fetch before resolving, without pruning.** Run `git fetch --all` so a branch pushed since the last fetch is visible. Leave remote-ref pruning to `git_refresh`, whose default run already owns it, so this skill never removes a ref as a side effect of a switch.
- **Enumerate the candidates from the refs, not from a guess.** List the local branches and every remote-tracking ref matching the name with `git for-each-ref --format '%(refname:short)' refs/heads refs/remotes`, so the run knows which of the cases below applies before it acts.
- **Switch to the branch when it already exists locally.** Use `git switch <name>`, then report that the branch was already present and that no tracking branch was created.
- **Create a tracking branch when the name resolves on exactly one remote.** Set the upstream explicitly from that remote's branch rather than relying on DWIM, so the run behaves the same under any `push.default` or DWIM configuration.
- **Hold and ask when a bare name resolves on several remotes.** List each candidate remote branch and ask which to track; on that first pass create nothing and switch nowhere. Re-enter by invoking again with the remote-qualified form for the chosen remote, which Normalize already resolves without a hold. A remote-qualified argument never enters this hold. The choice belongs to the user, so the run makes no default pick.
- **Report the cause when the name resolves nowhere.** Distinguish a branch that genuinely does not exist from one hidden by a restricted `fetch` refspec or a single-branch clone, using the configured refspec and the available remote refs, and name which case applies rather than passing git's `pathspec did not match` message through unexplained.
- **Stay conservative on a dirty worktree.** Let git decide whether local changes survive the switch, which carries compatible changes across and refuses when they would be overwritten. On refusal, surface the blocking paths and stop, matching the `git_refresh` stance that never stashes, discards, or hides user changes to make a workflow proceed.
- **Report what happened.** Close by path: a switch or create reports the branch now checked out, whether it already existed or was created, the upstream it tracks, and the previous branch left behind; a multi-remote hold reports the candidate list and asks which remote to track, having created nothing and switched nowhere; a miss reports the cause for that miss, having created nothing and switched nowhere.

**Out of scope:**

- Restoring files from the index or from a commit, the behaviour of a path-form checkout and of `git restore`, since this skill moves `HEAD` and creates tracking branches only.
- Creating a branch that exists on no remote and no local ref, which the run reports rather than fills in.
- Checking out a bare commit or tag into detached `HEAD`, since every path this skill takes ends on a named local branch.
- Pruning remote-tracking refs and deleting local branches, which the `git_refresh` sibling owns.

Bundle the git logic under `scripts/` per the repo's helper-script rule, and apply the [harness_portability](../plugins/ai_dev/skills/harness_portability/SKILL.md) skill so the script runs under both OpenAI Codex and Anthropic Claude and across macOS and Linux, where BSD-versus-GNU differences in git porcelain parsing, `sed`, and `grep` are the usual breakage. Write the `description:` for both audiences per the standing rule: a compact statement of what the skill does, the trigger phrases a router needs, and the boundary that keeps file-restore and branch-creation requests away. Mirror the `tests/git_commit/` skill-creator-aligned harness pattern for the new test surface.

This adds shipped content under `plugins/ai_dev/`, so registration and versioning for the landing commit follow the standing repo rules, which own the plugin version-lockstep procedure.

## Acceptance

- A new `plugins/ai_dev/skills/git_checkout/SKILL.md` exists with frontmatter `name: git_checkout` and `version: 1.0.0`, and a both-audiences `description:` carrying the trigger phrases, the explicit-request guard, and the boundary against file restore and branch creation.
- On a fixture repo whose branch exists only on one remote, the run ends with a local branch of the same name whose upstream is that remote branch, verifiable by reading the current branch and its configured upstream.
- On a fixture with more than one remote where the named branch exists only on a non-`origin` remote and was pushed after the local clone's last fetch, the run still checks it out onto a local branch tracking that remote's branch, proving the fetch step covers every remote before resolution.
- The run leaves remote-tracking refs that a pruning fetch would remove in place: a fixture carrying a stale remote-tracking ref still has it after a successful checkout.
- On a fixture where the branch already exists locally, the run switches to it, creates no new branch, and reports it as already present.
- On a fixture with two remotes carrying the same branch name, a bare-name first pass lists both candidates and asks which to track, creating nothing and switching nowhere; a follow-up invocation with the remote-qualified form for the chosen remote then ends on a local branch tracking that remote.
- Given the remote-qualified argument form, the run ends on a named local branch rather than in detached `HEAD`, verifiable because `HEAD` resolves as a symbolic ref.
- On a fixture with two remotes carrying the same branch name, given the remote-qualified argument naming one of them, the run tracks that remote's branch without asking which remote to use.
- Given a remote-qualified argument whose named remote does not carry the branch, the run reports that miss and creates nothing, without falling through to another remote that does carry the name.
- On a fixture whose `fetch` refspec is restricted so the branch's remote-tracking ref never arrives, the run reports that cause specifically rather than only relaying git's `pathspec did not match` message; on a fixture where the branch exists on no remote, it reports the branch as nonexistent and creates nothing.
- On a dirty worktree whose local changes conflict with the target branch, the run surfaces the blocking paths and stops with the original branch still checked out and the changes intact, having run no stash.
- On a dirty worktree whose local changes do not conflict, the run completes the switch with those changes still present and uncommitted.
- Closing report matches **Report what happened**: a switch or create ends with the branch now checked out, whether it was created or already present, its upstream, and the previous branch; a multi-remote hold ends with the candidate list and ask and neither creates nor switches; a miss ends with its cause report and neither creates nor switches.
- The skill bundles its git logic under `scripts/` and carries a `references/` manual-fallback note, mirroring the structure of its two `git_*` siblings.
- A `tests/git_checkout/` harness exists following the skill-creator-aligned pattern, with script tests under `script_tests/` and evals under `evals/`, covering remote-only checkout, the pre-resolution fetch, the already-local case, multi-remote ambiguity (first-pass hold plus remote-qualified re-entry), the remote-qualified argument, both nonexistent-branch causes, and both dirty-worktree branches, on staged fixtures.
- The skill is registered in the `ai_dev` `plugin.json` for Claude and Codex, both marketplace registrations, `plugins/ai_dev/README.md`, and the root `README.md` layout tree and skill list, per the standing registration rules.
