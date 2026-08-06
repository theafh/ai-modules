---
description: Enforce log.md rotation (so it never reaches tens of thousands of tokens) and switch the prescribed log-read idiom from tail -n N to entry-aware bounded retrieval.
scope: plugins/knowledge_management
created: 2026-05-28T20:05:29
updated: 2026-08-06T11:01:19
status: open
reported-by: Andreas Hoffmann
---

# Enforce log rotation and make log reads entry-aware

## Goal

`log.md` never grows large enough to overflow a tool result or exceed the Read token cap, and the orientation step that reads recent log entries does so by entry boundary instead of a fixed line count. Two coupled problems are fixed: the rotation rule that exists on paper is actually enforced, and the read idiom prescribed across the skill and agent stops dumping the whole tail of an oversized log.

## Context

The wiki convention is "rotate `log.md` at 500 entries" (stated in [skills/wiki/references/template_log.md](../plugins/knowledge_management/skills/wiki/references/template_log.md) and the `<rotate_log_at_500>` rule in [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md)). But the linter's rotation check, `check_log_rotation` in [skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py), emits the over-500 finding at **info** severity only. Info never blocks and is routinely accepted, so in practice the log is allowed to grow without bound — well past a thousand entries and tens of KB.

Once the log is that large, the prescribed read idiom breaks:

- The `tail -n 350` log-read idiom in [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) (both `<resuming_an_existing_wiki>` and the `<searching>` block), the auto-shaper's `<read_recent_log>` step in [agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) (`tail -n 350 "$WIKI/log.md"`), and the "roughly the last 350 lines of `log.md`" orientation wording in [skills/wiki_import/SKILL.md](../plugins/knowledge_management/skills/wiki_import/SKILL.md) (three sites: `<orient_first_top>`, `<orient_first>`, and its orientation step) and [skills/wiki_wrapup/SKILL.md](../plugins/knowledge_management/skills/wiki_wrapup/SKILL.md) (its orientation step; its `<orient_first>` policy already counts entries) all reach for a fixed line count.
- On an oversized log, `tail -n 350` produces a result large enough to trip the "output too large" handling, and a `Read` with offset/limit can exceed the 25000-token cap that [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) itself warns about (the `exceeds maximum allowed tokens (25000)` caution). Every orientation pass pays this.

Rotation also interacts with the auto-shaper's incremental audits: the agent scopes its page walk from the newest prior `audit` entry in `log.md` that records a usable git baseline (the `Audit baseline:` line written by `<append_audit_log_entry>`). Rotating moves every prior audit entry into `log-YYYY.md`, so the first audit after a rotation finds no baseline in the fresh log and falls back to the full cold walk.

**Severity is coupled to the agent's clean-exit bar.** The `auto_shaper_wiki` agent's `<lint_clean>` objective and `<relint_until_clean>` verify step both finish only when lint "exits 0 with no blocking or warn findings", and the agent ships no fix move that rotates a log — `<fix_log_preamble_drift>` restores preamble lines and leaves the entries below untouched. Escalating `check_log_rotation` to `warn` without also giving the agent a rotation move therefore hands it a finding it cannot clear while `<run_until_done>` tells it not to stop early. That is the same unreachable-bar hazard [wiki_auto-shaper-internal-contradictions.md](archive/wiki_auto-shaper-internal-contradictions.md) resolves for the contested-page warn, and its carve-out is deliberately contested-only, so a rotation warn gets no relief from it. That task also rewrites the clean-bar statement this task's new finding must stay clearable under — read it before wording the severity change.

Agents have independently rediscovered an entry-aware idiom (`grep -n '^## \[' log.md` to get entry anchors, then read a bounded slice). That idiom should be baked into the prescribed steps, and rotation should be enforced so the log never reaches the failure size in the first place.

Co-edit coordination: [wiki_log-heading-uniqueness-and-repair.md](wiki_log-heading-uniqueness-and-repair.md) edits the same `template_log.md` preamble (adding the timestamped heading format and the repair carve-out) and adds its own on-demand fix move to the agent's `<remediate>` phase beside this task's rotation move. Both preamble edits drift every existing wiki's `log.md` boilerplate once until its next audit realigns it, so landing them together spends that drift a single time; word this task's rotation-rule preamble line against whichever heading-format text is current when it builds, and keep the two `<remediate>` moves distinct siblings.

Files involved:

- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — `check_log_rotation`.
- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — the `tail -n 350` log-read guidance and the `<rotate_log_at_500>` rotation rule.
- [plugins/knowledge_management/agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) — `<read_recent_log>`; consider auto-rotation in `<remediate>`.
- [plugins/knowledge_management/skills/wiki_import/SKILL.md](../plugins/knowledge_management/skills/wiki_import/SKILL.md) — the three "last 350 lines" orientation mentions.
- [plugins/knowledge_management/skills/wiki_wrapup/SKILL.md](../plugins/knowledge_management/skills/wiki_wrapup/SKILL.md) — the "last 350 lines" orientation step.
- [plugins/knowledge_management/skills/wiki/references/template_log.md](../plugins/knowledge_management/skills/wiki/references/template_log.md) — the rotation preamble.

## Approach

1. **Give rotation teeth on both channels — escalated severity and an agent rotation move — in one change.** Escalate the over-threshold finding in `check_log_rotation` beyond bare info so it stops being accepted forever: a `warn` past 500 and a stronger finding well past it (say 1000), with the thresholds decided against the convention in `template_log.md` and kept consistent with it. In the same change, add a rotation fix move to the agent's `<remediate>` phase: `git mv` the log to `log-YYYY.md`, start a fresh `log.md` carrying the canonical preamble from `template_log.md`, and record the rotation as the new log's first entry. The fix move is what makes the escalated finding clearable, per the clean-exit coupling in Context — the severity alone would strand every audit on a wiki whose log has already grown, so the two halves ship together rather than as alternatives. Rotation deliberately accepts a one-time post-rotation cold walk from the incremental-audit mechanism — rare (once per 500 entries) and self-healing, since the first audit after rotation records a fresh baseline in the new log — and the rotation rule states that fallback so it is designed rather than accidental.
2. **Replace the fixed-line-count read idiom with entry-aware retrieval** everywhere it appears: the `tail -n 350` idiom in SKILL.md (`<resuming_an_existing_wiki>` and `<searching>`), the agent's `<read_recent_log>`, and the "roughly the last 350 lines" orientation wording in `wiki_import` and `wiki_wrapup`. Prescribe: get entry anchors with `grep -n '^## \[' "$WIKI/log.md" | tail -<N>`, then `Read` a bounded slice from the earliest needed offset. This reads the last N *entries* regardless of their length and never dumps the whole tail of a huge file. State the idiom once in the base skill's log-read guidance and have the front ends cite it rather than restate it, per the family's author-once convention.
3. **Cross-reference the cap warning.** Tie the new idiom to the existing 25000-token caution in SKILL.md so the two are coherent.

## Acceptance

- `check_log_rotation` reports the oversized log above info severity at both thresholds, so an unbounded log is no longer silently tolerated.
- `auto_shaper_wiki` carries a `<remediate>` rotation fix move that renames the log to `log-YYYY.md`, starts a fresh `log.md` with the canonical preamble, and records the rotation as the new log's first entry. On a fixture wiki whose log trips the escalated finding, a `wiki_fix` pass clears it by rotating, so the agent reaches its clean bar instead of holding a warn it has no move for.
- The rotation rule (the `template_log.md` preamble and the `<rotate_log_at_500>` statement) names the post-rotation audit behaviour: the next audit cold-walks once and records a fresh baseline in the new log.
- The prescribed log-read step in SKILL.md, the agent, `wiki_import`, and `wiki_wrapup` uses entry-anchor + bounded-slice retrieval, not a fixed line count; `rg "350" ../plugins/knowledge_management/skills/wiki_import/SKILL.md ../plugins/knowledge_management/skills/wiki_wrapup/SKILL.md` returns no log-read idiom.
- On a fixture wiki with an oversized `log.md`, the orientation read returns the last N entries without tripping "output too large" or the 25000-token Read cap.
- Script unit tests under `tests/wiki/` cover the rotation severity threshold.
- `tests/wiki/run_all.sh` passes.
