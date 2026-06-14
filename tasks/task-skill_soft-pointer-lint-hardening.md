---
description: Harden the task linter's soft-pointer detector (catch tilde/capital-Lines shapes, skip size extents) and teach skills to triage each warn — rewrite genuine line anchors, ignore false positives.
scope: plugins/ai_dev/skills
created: 2026-06-13T14:33:01
updated: 2026-06-13T14:47:16
status: open
reported-by: Andreas Hoffmann
---

# Harden the soft-pointer detector and its triage contract in the task skills

## Goal

This task delivers two coupled changes — a broader detector and the contract for consuming it safely:

1. **A broadened, size-aware detector.** `check_no_position_claims` flags every line-number position-claim shape that turns up in real task bodies — not only the lowercase `line N` / `path:N` forms it matches today, but also the tilde-approximate and capital-`Lines` claims an audit found rotting silently — while treating a number followed by a size unit as a permitted extent. The finding stays at `warn`, never blocking.
2. **A consumer triage contract.** Because broader recall deliberately trades away precision, the base `task` lint guidance and `task_fix`'s auto-fix gain an explicit rule: a soft-pointer warn is a candidate, not a verdict. The skill reads the hit in its surrounding context and rewrites only a genuine line anchor, leaving a false positive — a size, a version, a count, or a claim-shape quoted as subject matter — untouched. A dismissable warn costs far less than a stale line number slipping through unseen.

## Context

The soft-pointer rule in the base `task` skill's `<markdown_policy>` bans every line-number position claim and permits extent stated as size. `plugins/ai_dev/skills/task/scripts/lint.py` enforces it in `check_no_position_claims` with two regexes:

```text
POSITION_PATH_RE   <path>.<ext> immediately followed by :<digits>
POSITION_PROSE_RE  (?:around )?lines? <digits>[-–<digits>]   — lowercase only; a digit must follow the space
```

A whole-tree `task_fix` pass found claims both regexes miss; each passed lint while its number silently rotted:

```text
Lines 241–242       capital L — POSITION_PROSE_RE is lowercase-only
Line 1532           capital L
(~158-188)          bare tilde range — no "lines" keyword, no path:N suffix
SKILL.md ~734       path then space-tilde — POSITION_PATH_RE needs a colon
currently line ~18  "line ~N" — the regex needs a digit right after the space
around line ~554    "line ~N"
```

Two gaps produce all of them: **case** (the prose regex is lowercase) and **tilde / approximate forms** (`~N`, `(~N-M)`, a path-then-`~N`, and `line ~N` — none matched).

Adding tilde matching would make `~16 KB` / `100 MB` false-positive, but the rule allows extent stated as size — so the detector skips a number whose immediate suffix is a size unit (`B`, `KB`, `MB`, `GB`, `TB`, `bytes`, case-insensitive). The fence-awareness (fenced blocks skipped, inline code checked) and the `SEV_WARN` / `"soft-pointer"` bucket stay unchanged.

The bias is recall over precision: a missed claim drops silently and misleads a later reader, while a false positive surfaces as a `warn` dismissed in one glance — so the detector leans toward flagging and never escalates past `warn`.

That bias places an obligation on the skills that read the warn. The size carve-out removes the commonest false positive, but recall over precision concedes others will surface — a version (`~1.5`), a count (`~500 entries`), or a claim-shape quoted as subject matter, as this very task's examples are. The linter cannot enumerate every non-position number, so the residual judgment falls to the reader. Today that judgment is uncodified: `task_fix`'s `<remediate>` treats a soft-pointer hit as mechanically strippable, and the base `<lint>` description states only what the check flags — neither warns that a hit may be a false positive to leave alone. Broadening recall makes codifying the triage necessary rather than optional.

Predecessors, both implemented:

- [task-skill_label-only-soft-pointers.md](archive/task-skill_label-only-soft-pointers.md) added `check_no_position_claims` with its fence-aware, warn-level behavior; this task hardens that detector.
- [task-skill_soft-pointer-references.md](archive/task-skill_soft-pointer-references.md) established the label-over-line-number rule it enforces.

## Approach

1. **Broaden the prose match.** Make `POSITION_PROSE_RE` (or a sibling) case-insensitive and cover the approximate forms: capital `Lines`/`Line`, a leading `~` on the number, `line ~N`, and a bare `(~N)` / `(~N-M)` parenthetical with hyphen or en-dash.
2. **Extend the path match.** Catch a path followed by `~N` (the `SKILL.md ~734` shape), not only `path:N`.
3. **Exclude size extents.** Before emitting, drop a match whose number's immediate suffix is a size unit (`B|KB|MB|GB|TB|bytes`, case-insensitive); the rule's extent-as-size allowance is the rationale.
4. **Hold severity and scrubbing.** Keep the finding at `SEV_WARN` in the `"soft-pointer"` bucket and leave the fenced-block scrubbing as it is.
5. **Document the shapes and the triage rule.** In the base `task` skill's `<lint>` soft-pointer description, name the broadened shapes and the size carve-out, and state that the check is recall-biased: a warn is a candidate the reader confirms by reading the hit in context, rewriting a genuine line anchor and leaving a false positive (a size, version, count, or quoted claim-shape). State the rule once here as the single source.
6. **Guard the auto-fix.** In `task_fix/SKILL.md`'s `<remediate>`, condition the soft-pointer auto-strip on that judgment — read the hit's surrounding context first, strip only a genuine line anchor, leave a false positive untouched — citing the base rule rather than restating it.
7. **Prove on a fixture.** Stage a task body in `tests/tasks/script_tests/` carrying each missed shape plus the size and fenced no-match cases.

Non-goals: no new severity tier; the detector still only reports, with the author or `task_fix` acting on its warns; no widening of the path-extension set beyond the `~N` adjacency.

## Acceptance

- Each shape in the Context block of missed claims — the capital-`Lines`/`Line` claims and the four tilde forms — produces a `soft-pointer` finding in an open task body (false today: the lowercase, `:N`-only regexes miss all of them).
- A body holding both a `(~N-M)` tilde range and a `~16 KB` size extent yields exactly one finding, the range — the size is skipped (false today: zero findings, since no tilde form is matched at all).
- A `512 bytes` or `100 MB` extent on its own produces no `soft-pointer` finding.
- The finding is emitted at `SEV_WARN` in the `"soft-pointer"` bucket; no shape escalates to blocking.
- Fenced code blocks stay skipped and inline code stays checked, confirmed by a fixture whose fenced block holds a `path:N`-style line that draws no finding.
- The base `task` skill's `<lint>` soft-pointer description names the broadened shapes and the size carve-out, and states the recall-bias triage rule — a warn is confirmed in context, a genuine anchor rewritten and a false positive (size/version/count/quoted shape) left alone (false today: it names only what the check flags).
- `task_fix/SKILL.md`'s `<remediate>` conditions its soft-pointer auto-strip on reading the hit's surrounding context and confirming a genuine position claim, leaving a false positive untouched (false today: `<remediate>` strips a soft-pointer hit mechanically, with no false-positive gate).
- `tests/tasks/script_tests/` covers the match and no-match cases above, and `tests/tasks/run_all.sh` exits 0.
