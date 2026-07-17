---
description: Stop created/updated timestamps being model-fabricated — SKILL gives the exact date shell command to run, and lint cross-checks created against filesystem birth time when available.
scope: plugins/ai_dev/skills/task
created: 2026-05-28T19:49:23
updated: 2026-06-14T18:14:02
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Make created/updated timestamps trustworthy

## Goal

`created` and `updated` should reflect the real wall clock, not a value the
model invents. The model has no clock, so when the SKILL says "get it from the
environment context" it fills in a plausible-but-wrong time. Fixing this is a
reliability win and removes a guessing step.

## Context

Two gaps combine:

1. **The SKILL tells the model to source the time from context.** In
   `SKILL.md`, the `<frontmatter>` block ends with: "Use the user's current date
   for both `created` and `updated` on a fresh task. Get it from the environment
   context, not from guessing." Context only carries the date, never the
   time-of-day, so the model fabricates the time.

   Observed: a real session stamped every task `2026-05-28T14:30:00` while the
   actual wall clock was ~19:26 — the date was right, the time invented.

2. **The linter only checks timestamp *format*, never plausibility.** In
   `scripts/lint.py`, `DATETIME_RE` (`^\d{4}-\d{2}-\d{2}`) and the
   `for date_field in ("created", "updated")` loop only warn on non-ISO-8601
   shape. A fabricated-but-well-formed datetime passes clean.

## Approach

Two coordinated changes; land them together (one skill, one version bump).

**Part A — SKILL gives the command, not a vibe.** In `SKILL.md`, replace the
"get it from the environment context" sentence with an instruction to obtain the
timestamp by running a shell command, and show it inline so the model runs it
rather than guesses:

```bash
date +%Y-%m-%dT%H:%M:%S        # local time, e.g. 2026-05-28T19:49:23
```

State that both `created` (on a fresh task) and `updated` (on every edit,
status change, and archive move) take their value from this command's output.
Reuse one captured value across a batch creation in the same turn rather than
re-running per file. Keep the existing rule that `updated` is bumped on every
change.

**Part B — lint cross-checks created vs filesystem birth time, when available.**
In `scripts/lint.py`, add a **warn-level** check: when the OS exposes a file
birth time, compare it to the `created` frontmatter timestamp and warn if the
two disagree by more than an hour. (Tightened from the originally-proposed
one-day window: a `created` taken from `date` at creation matches birth time
within seconds, so an hour of slack covers batch reuse and clock drift while
still catching the same-day time-of-day fabrication that motivated this task —
the one-day window would have sailed right past it.)

- macOS: `stat -f %B <file>` → birth time as epoch seconds.
- Linux: `os.stat(...).st_birthtime` where present, else `stat -c %W` (which
  returns `0`/`-` when the filesystem does not record birth time).
- When birth time is unavailable or zero, **skip silently** — emit nothing.
- Keep it `warn`, never `blocking`. A `git mv`/rename **preserves** birth time
  (verified), so the archive workflow stays clean; only a fresh clone/checkout
  or a `cp` copy resets it. This is advisory drift detection, not a hard gate.
  Note that caveat in the warning text so the author knows a clone/checkout can
  trip it.

Prefer `os.stat` introspection over shelling out where the attribute exists, to
keep it stdlib and fast; fall back to `stat` only if needed. Match the existing
`Issue(SEV_WARN, "frontmatter", ...)` pattern.

Non-goal: do not validate `updated` against mtime (every lint-adjacent edit
would churn it); only `created` vs birth time.

## Acceptance

- `SKILL.md` contains the copy-pasteable `date` command and instructs the model
  to stamp `created`/`updated` from its output; the "get it from the environment
  context" wording is gone.
- On a filesystem that records birth time, a task whose `created` timestamp
  differs from the file's birth time by more than an hour produces a `warn`
  (including a same-day, wrong-time-of-day fabrication); a task whose `created`
  matches within the hour stays clean.
- On a filesystem without birth time, the check emits nothing (no false warn).
- Add bash unit tests under `tests/tasks/script_tests/` for the supported and
  unsupported branches (skip-if-unsupported guard for the birth-time assertion).
- `make lint` and `python3 scripts/lint.py` stay clean on the existing `tasks/`
  tree (these files were just stamped from `date`, so they should match birth
  time within tolerance).
- Behavioural eval coverage (model stamps `created`/`updated` from `date`
  rather than fabricating) is tracked separately in
  [task-family_testing-new-features](task-family_testing-new-features.md)
  and lands in its own commit, per the repo's one-bump-per-commit rule.
