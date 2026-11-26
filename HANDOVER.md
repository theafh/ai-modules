# Handover — 2026-11-26

Written at the point the session stopped for a machine shutdown. Read this before
resuming the autonomous backlog loop.

## Where the repository stands

- `main` is clean, in sync with `origin/main`, at commit `31fda97`.
- **22 tasks finished and archived** in this run; 20 remain live in `tasks/`.
- Every batch was pushed. Nothing is stranded locally.

## What was in flight when the session stopped

**Iteration 23, `tasks/tests_agent-spinner-rule-free-prompts.md`, was abandoned
mid-build.** Its readiness repair landed (`31fda97`, the eval id corrected to
`beyond_brief_find_reported`), but the implementation did not.

A background implementer may still be running. If `git status` shows changes
under `tests/agent_spinner/evals/`, discard them — they are an incomplete rewrite
of the eval prompts and their README selection section:

```bash
git checkout -- tests/agent_spinner/
```

The task is still `ready`, so restart it cleanly with `task_implement`.

## What needs the owner's attention

1. **The machine config was changed.** `~/.ai_asset_deploy/config` gained
   `style:natural-language` under `#codex`, because the Codex output-style task's
   Acceptance required the machine activation. A dry run confirms it now
   generates `~/.codex/instructions/natural-language.md` and merges
   `model_instructions_file`. Backup at
   `~/.ai_asset_deploy/config.bak-before-codex-style`.

2. **One design decision was settled on a review gate's suggested default**, not
   by you: the user-level VS Code instructions file stays frontmatter-free, with
   its automatic-activation gap recorded in `deployment/README.md`, the wiki, and
   the generator comment rather than asserted. Revisit if you would rather it
   carried `applyTo: "**"`.

3. **`tasks/ai-editorial_slop-catch-skill.md` carries three non-blocking
   task-linter warnings** from an owner edit: a 222-character description, a
   341-line body, and a `lines 25–190` soft-pointer. Left as written.

4. **The live deploy state migration ran** (with approval): `deployment.conf` is
   gone from the repo, `~/.ai_asset_deploy/config` and `deployed.log` hold the
   real state, and the committed defaults are
   `deployment/ai_asset_deploy.conf.template`.

## How the loop was running

Per task: `task_select` → (`task_auto_check` if not `ready`) → `task_implement` →
commit → `task_audit` (repair and re-audit on gaps) → `task_finish` → commit →
`git_auto_review` (gate, triage, fixer, ledger, delta audit, re-review rounds) →
commit → push.

Two operating rules that mattered repeatedly:

- **Review rounds kept finding stale cross-references** left by earlier edits in
  the same batch. When you edit a doc or a task body, sweep for other places that
  name the thing you changed.
- **Every edited file needs its `updated:` bumped** — task bodies, archived task
  bodies, and wiki pages alike. This was the single most common review finding.

## Suggested next steps

1. Confirm the tree is clean (`git status`).
2. Restart iteration 23: `task_implement` on
   `tasks/tests_agent-spinner-rule-free-prompts.md`.
3. Continue `task_select` over the remaining 20 live tasks.

The `git_auto_review` relay directories under `.git_auto_review/batch*` hold the
per-batch gate reports, round diffs, ledgers, and `report.txt` files if you want
to audit the loop's own work.
