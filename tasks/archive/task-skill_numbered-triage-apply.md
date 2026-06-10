---
description: "Make applying selected check findings a first-class update flow: the user picks issue numbers from the last task_check report, update applies exactly those, bumps, and re-lints."
scope: plugins/ai_dev/skills/task
created: 2026-06-09T12:34:16
updated: 2026-06-10T20:50:09
status: implemented
---

# Numbered-triage apply path in the update workflow

## Goal

Applying selected check findings is a first-class update flow: after a
`task_check` report, the user replies with issue numbers and decisions —
accept, reject, or modify per number — and the update path applies exactly
the accepted ones to the task file, bumps `updated`, and re-lints. The
freeform "fix the task based on your suggestions" round becomes a precise,
repeatable hand-off.

## Context

- Evidence from mined sessions (2026-05/06): after nearly every check the
  user issued a freeform apply instruction, and triage happened by number —
  "1) align it … 2) refine as suggested 3) can stay as it is 4) fix" —
  including rejections. Roughly a quarter of numbered findings were rejected
  or left unaddressed across sessions, so auto-applying a full report is
  wrong, and the manual loop costs a fumbling turn per round.
- The numbered `## Issues` list from `task_check`'s output contract is the
  interface this flow consumes; numbers reference the most recent check
  report in the conversation.
- Edit site: the base `task` skill's `<update>` workflow in `task/SKILL.md`.
  `task_check` stays read-only and unchanged — its report already carries the
  ordered list this flow indexes.

## Approach

- Extend `<update>` in `task/SKILL.md` with the apply-findings flow: given a
  user reply naming issue numbers from the latest check report, apply each
  accepted finding's minimum fix to the task file, honour rejections by
  leaving those passages as they are, fold user-modified instructions in over
  the report's suggestion, then bump `updated` in the same edit round and
  re-run the linter once at the end.
- State the number-reference rule once in that flow: numbers always index the
  most recent `task_check` report in the conversation; when no report is in
  context, ask for the issue list instead of guessing.
- Keep the flow an update-path addition; the check side needs no change.

## Acceptance

- `task/SKILL.md` `<update>` describes the numbered apply flow: accepted
  numbers applied with their minimum fix, rejections left untouched, user
  modifications winning over the report's suggestion, one `updated` bump and
  one re-lint per round.
- The number-reference rule (latest report; ask when absent) is stated once
  in that flow.
