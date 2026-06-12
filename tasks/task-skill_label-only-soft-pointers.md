---
description: Tighten the task-family soft-pointer rule to verbatim greppable labels only — no path:N or "line N" position claims — at every rule site, plus a fence-aware warn-level lint check.
scope: plugins/ai_dev/skills
created: 2026-06-12T14:22:20
updated: 2026-06-12T23:26:49
status: open
---

# Ban line-number references in task files: label-only soft pointers

## Goal

Rewrite the task family's soft-pointer rule so a task-file reference anchors on a **verbatim, greppable label alone** — an exact quoted phrase, regex, symbol, or heading, together with the file path — and position claims (a `:N` suffix on a file path, a bare `line N`, an `around lines N–M` range) are banned from task bodies. Apply the rewrite verbatim-consistently at every site in the family that states or restates the rule, and back it with a warn-level lint check engineered against false positives. The rule update is the unconditional core; the lint check ships with it under the safety design below.

## Context

**Why.** A label-only reference fails loudly (grep finds nothing once the target is reworded) instead of quietly wrong (a stale number lands the reader on plausible-looking wrong code). Agents — the primary readers per the base skill's self-sufficiency bar — locate by string search, not position. And label-only is the only variant a linter can mechanically enforce: "numbers must be current" is uncheckable without fuzzy cross-file matching. Field evidence (2026-06-12): one upstream commit shifted a referenced script by ~8 lines, and within 9 days every line-number companion in the referencing tasks pointed at wrong code, while every verbatim label still resolved on first grep.

**Rule sites** (from `grep -rnE "soft-pointer|line number" plugins/ai_dev/`, 2026-06-12 — re-grep before finishing):

- `plugins/ai_dev/skills/task/SKILL.md`, `<markdown_policy>` soft-pointer bullet — the rule itself. Remove the clause "A line number may accompany the label; the label carries the reference." Replace with: the label must be verbatim-greppable (vague descriptions like "the matchers block" no longer qualify); position claims are banned; extent, when useful, is expressed as size ("the ~10-line guard block"), never position.
- `plugins/ai_dev/skills/task/SKILL.md`, `<readiness_checklist>` ambiguity bullet — "a reference that leans on a bare line number is flagged" widens to: any reference carrying a line-number position claim is flagged.
- `plugins/ai_dev/skills/task_fix/SKILL.md`, the Remediate step — "a reference carried by a bare line number → re-anchor" becomes a mechanical auto-fix: using the cited line number as the lookup, strip it, verify the label resolves by grep, and strengthen a vague label to the verbatim quote at that location.
- `plugins/ai_dev/skills/task_check/SKILL.md` (Issues output contract) and `plugins/ai_dev/skills/task_create/SKILL.md` (the Write step) reference the rule by name and read through — verify their wording stays coherent, edit only if they restate the dropped clause. `task_implement`, `task_audit`, and `task_finish` had no hits as of 2026-06-12.

**Lint check — the false-positive question, answered by design:**

- **Warn severity, never blocking in v1.** `lint.py` exits 1 only on blocking findings (its docstring: "0 no blocking issues / 1 one or more blocking issues found"), so a warn finding cannot fail any flow or CI — it only surfaces. This bounds the blast radius of any residual false positive to one advisory line.
- **Skip fenced code blocks.** Quoted tool output (grep output, stack traces, expected-output blocks) is the dominant false-positive source and lives in fences. Inline code spans stay checked, because real references live there; the companion writing convention: outputs go in fenced blocks, references in inline code.
- **Anchored patterns.** Path claims match only with a known file extension before the colon; prose claims are word-order-sensitive — a `line N` / `around lines N–M` shape warns, while a trailing `N lines` count keeps the family's own split rule legal. This keeps URLs, `host:port`, timestamps, and issue refs silent. The patterns, with worked matches and non-matches kept inside the fenced block (so the rule's own illustration stays label-only in prose):

  ```text
  path claim:   \.(md|sh|py|json|ya?ml|toml|js|ts|go|rs|c|h)\:[0-9]+
  prose claim:  \b(around )?lines? [0-9]

  warns:    deployment.sh:242    line 42    around lines 95–105
  silent:   localhost:8080    300 lines    grows past 300 lines    13:40:10
  ```

- **Open tasks only.** Archived tasks are closed historical records nobody maintains; checking them would create permanent noise. The check applies to `tasks/`, not `tasks/archive/`.
- **Fallback decision rule.** Run the updated linter over this repo's own open tasks. If a false positive survives the design above, demote the check to info — never weaken the patterns silently to make a true positive disappear; record the demotion rationale when archiving this task.

**Follow-through (separate task).** Bringing the rest of this repo's open `tasks/` into compliance is its own unit of work — a later run of the updated `task_fix` over the tree — and stays **out of scope here**. This task makes only its own body compliant and proves the check on one untouched task as a reduced acceptance demonstration (see **Acceptance**).

Non-goals: the wiki family's pointer conventions are untouched; ephemeral chat output is unaffected (clickable `file:line` stays right where the artifact lives minutes, not weeks); no blocking severity in v1; the repo-wide sweep of the existing backlog is deferred to a follow-up task, not part of this work.

## Approach

1. Rewrite the rule sites listed in Context, keeping the rule's name ("the soft-pointer rule") stable so read-through references in sibling skills stay valid.
2. Implement the lint check in `plugins/ai_dev/skills/task/scripts/lint.py` (warn severity, fence-skip, anchored patterns, open-tasks-only). Two cautions the existing code imposes: the fence-skip must keep **inline** code spans, since references legitimately live there and must stay checked — the existing `_scrub_code` helper also blanks inline code (correct for its footnote/wikilink callers, wrong for this check), so parametrize it or add a fence-only sibling rather than reusing it as-is; and because `iter_task_files` also yields archived pages, gate this open-tasks-only check behind the existing `is_archived` check so `archive/` stays untouched.
3. Prove both branches on staged fixtures in `tests/tasks/script_tests/`, per the repo's land-with-a-tight-scenario rule (broader harness growth stays in its own session): a warn fixture whose body carries an extension`:N` path claim and an "around lines" phrase (both must warn), and a quiet fixture carrying `localhost:8080`, "grows past 300 lines", a timestamp like `13:40:10`, and a fenced grep-output block (all must stay silent).
4. Run `tests/tasks/run_all.sh`; the SKILL.md prose changes additionally get the evals surface per `tests/README.md` conventions.
5. Confirm this task's own body stays silent under the new check, and prove the check fires on one untouched task as the reduced acceptance demonstration (see **Acceptance**); the repo-wide sweep stays deferred (see **Follow-through**). Run the standing `make lint` gate per CLAUDE.md before commit.

## Acceptance

- `grep -n "may accompany" plugins/ai_dev/skills/task/SKILL.md` returns nothing, and the `<markdown_policy>` soft-pointer bullet requires a verbatim greppable label and bans position claims (false today: the may-accompany clause is the current rule).
- `task_fix`'s Remediate step names strip-the-number-and-re-anchor as a mechanical auto-fix (false today: its wording presupposes numbers may remain).
- On the warn fixture, `lint.py` reports exactly the two new warn findings naming file and matched pattern; on the quiet fixture it reports none of them; **both runs exit 0** (false today: the check does not exist).
- A re-grep of "line number" and "soft-pointer" across `plugins/ai_dev/skills/` shows every remaining mention consistent with the label-only rule (false today: two sites carry the old clause).
- Once the new check exists, running it over this task file reports zero position-claim warns — every illustration here uses a non-digit placeholder (`:N`, `line N`, `around lines N–M`) or sits inside a fenced block, so the file defining the rule stays clean (the body was made compliant while the task was shaped; this item confirms the check keeps it clean).
- Reduced acceptance test on one untouched task: a tree-wide run of the new check flags [wiki_log-rotation-and-retrieval.md](wiki_log-rotation-and-retrieval.md) — left unmodified — with the position-claim warns it currently carries (a `file.md:N` path claim and an `around lines N–M` prose claim among them), naming file and matched pattern, at exit 0. The repo-wide sweep that would clear those warns across the tree is deferred to a follow-up task, so other open tasks still warning here is expected, not a failure (false today: the check does not exist).
