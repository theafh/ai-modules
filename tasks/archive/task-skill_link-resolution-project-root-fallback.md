---
description: Make lint.py resolve body links from the project root as a fallback so repo-relative links stop being false-positive broken-links that force ../ prefixing.
scope: plugins/ai_dev/skills/task
created: 2026-05-28T19:49:23
updated: 2026-05-28T21:41:01
status: implemented
---

# Resolve task-body links from the project root as a fallback

## Goal

A task file under `tasks/` that links to a repo source file with a natural
repo-relative path (e.g. `plugins/knowledge_management/agents/wiki_auto_shaper.md`)
should lint clean. Today it is reported as a blocking `broken-link` unless the
author manually prefixes every such link with `../`. Removing this class of
false positive cuts turns and tokens on every doc that references repo files.

## Context

Two link-like fields in the skill resolve against **different roots**, which is
the root cause:

- `scope:` resolves against the **project root**. In `scripts/lint.py`,
  `check_scope` (around line 307) does:
  `project_root = tasks.parent.resolve()` then `target = (project_root / raw).resolve()`.
- Body markdown links resolve against the **task file's own directory**. In
  `check_links` (around line 405) the only resolution is:
  `candidate = (page.parent / target).resolve()` → `tasks/<link>`.

So a path that is correct for `scope:` (repo-root-relative) is reported broken
when it appears as a body link. An author's mental model is "paths are
repo-relative" — which `scope:` rewards and body links punish.

Observed cost: in the session that turned `todo.md` into six tasks, this single
inconsistency produced 10 blocking findings and forced 7 follow-up `Edit` calls
plus a re-lint to add `../` to every link — pure churn.

## Approach

In `check_links` in `scripts/lint.py`, make resolution try both roots before
declaring a link broken:

1. Resolve `page.parent / target` (current behaviour — sibling-task and
   `./`/`../` relative links keep working unchanged).
2. If that does not exist, resolve `project_root / target`
   (`project_root = tasks.parent`). If **that** exists, accept the link — this
   is the same repo-root-relative convention `scope:` already uses, giving
   authors one consistent mental model.
3. Only when **both** roots miss, emit the `broken-link` blocking finding. When
   exactly one root would have resolved, include that resolved path in the
   message as a hint so a fix is one obvious edit.

`check_links` currently receives `tasks`; derive `project_root = tasks.parent`
inside it (no signature change needed) or pass it in — match whatever
`check_scope` does for consistency.

Non-goal: do not change `scope:` resolution; it is already project-root-based
and correct. Do not touch external-link or non-`.md` skipping logic.

Keep the fix to standard library only (repo toolchain is Make + shell +
markdown + the existing Python linter).

## Acceptance

- A task file under `tasks/` whose body links to a real repo file via a
  repo-root-relative path lints clean **without** a `../` prefix.
- Sibling-task links (a relative `.md` link to another task file) and explicit
  `../`-relative links still resolve.
- A link that resolves under neither root is still a blocking `broken-link`, and
  its message names the path that one root would have resolved to.
- Add a bash unit test under `tests/tasks/script_tests/` covering: (a)
  repo-relative body link resolves via fallback, (b) genuinely-missing link
  still blocks, (c) sibling-task link still resolves. Per repo convention, land
  the lint change with a tight new test and run the existing suite to confirm no
  regression; do not expand the harness further in the same commit.
- `make lint` and `python3 scripts/lint.py` stay clean on the existing
  `tasks/` tree.
