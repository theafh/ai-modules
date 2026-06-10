---
description: Enforce log.md rotation (so it never reaches tens of thousands of tokens) and switch the prescribed log-read idiom from tail -n N to entry-aware bounded retrieval.
scope: plugins/knowledge_management
created: 2026-05-28T20:05:29
updated: 2026-06-10T22:05:12
status: open
---

# Enforce log rotation and make log reads entry-aware

## Goal

`log.md` never grows large enough to overflow a tool result or exceed the Read token cap, and the orientation step that reads recent log entries does so by entry boundary instead of a fixed line count. Two coupled problems are fixed: the rotation rule that exists on paper is actually enforced, and the read idiom prescribed across the skill and agent stops dumping the whole tail of an oversized log.

## Context

The wiki convention is "rotate `log.md` at 500 entries" (stated in [skills/wiki/references/template_log.md](../plugins/knowledge_management/skills/wiki/references/template_log.md) and [skills/wiki/SKILL.md:53](../plugins/knowledge_management/skills/wiki/SKILL.md)). But the linter's rotation check, `check_log_rotation` in [skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) (around lines 732-741), emits the over-500 finding at **info** severity only. Info never blocks and is routinely accepted, so in practice the log is allowed to grow without bound — well past a thousand entries and tens of KB.

Once the log is that large, the prescribed read idiom breaks:

- [skills/wiki/SKILL.md:387](../plugins/knowledge_management/skills/wiki/SKILL.md) and [skills/wiki/SKILL.md:684](../plugins/knowledge_management/skills/wiki/SKILL.md), and the auto-shaper's `<read_recent_log>` at [agents/wiki_auto_shaper.md:145-149](../plugins/knowledge_management/agents/wiki_auto_shaper.md) (`tail -n 350 "$WIKI/log.md"`), all reach for a fixed line count.
- On an oversized log, `tail -n 350` produces a result large enough to trip the "output too large" handling, and a `Read` with offset/limit can exceed the 25000-token cap that SKILL.md itself warns about at [skills/wiki/SKILL.md:734](../plugins/knowledge_management/skills/wiki/SKILL.md). Every orientation pass pays this.

Agents have independently rediscovered an entry-aware idiom (`grep -n '^## \[' log.md` to get entry anchors, then read a bounded slice). That idiom should be baked into the prescribed steps, and rotation should be enforced so the log never reaches the failure size in the first place.

Files involved:

- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — `check_log_rotation` (~732-741).
- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — log-read guidance (~387, ~684) and the rotation mention (~53, ~652).
- [plugins/knowledge_management/agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — `<read_recent_log>` (~145-149); consider auto-rotation in `<remediate>`.
- [plugins/knowledge_management/skills/wiki/references/template_log.md](../plugins/knowledge_management/skills/wiki/references/template_log.md) — the rotation preamble.

## Approach

1. **Raise the severity / add teeth to rotation.** In `check_log_rotation`, escalate the over-threshold finding beyond bare info so it does not get silently accepted forever — e.g. a `warn` past 500 and a stronger finding well past it (say 1000). Decide the thresholds against the convention in `template_log.md` and keep them consistent. Alternatively (or additionally), have the `wiki_auto_shaper` auto-rotate the log during remediation: rename to `log-YYYY.md`, start a fresh `log.md`, and record the rotation in the new log. Pick the approach that fits the skill's autofix posture; the goal is that the log stops reaching the failure size.
2. **Replace the fixed-line-count read idiom with entry-aware retrieval** everywhere it appears (SKILL.md ~387 and ~684, and the agent's `<read_recent_log>`). Prescribe: get entry anchors with `grep -n '^## \[' "$WIKI/log.md" | tail -<N>`, then `Read` a bounded slice from the earliest needed offset. This reads the last N *entries* regardless of their length and never dumps the whole tail of a huge file.
3. **Cross-reference the cap warning.** Tie the new idiom to the existing 25000-token caution at SKILL.md ~734 so the two are coherent.

## Acceptance

- `check_log_rotation` reports the oversized log above info severity (or the auto-shaper auto-rotates), so an unbounded log is no longer silently tolerated.
- The prescribed log-read step in SKILL.md and the agent uses entry-anchor + bounded-slice retrieval, not `tail -n <fixed>`.
- On a fixture wiki with an oversized `log.md`, the orientation read returns the last N entries without tripping "output too large" or the 25000-token Read cap.
- Script unit tests under `tests/wiki/` cover the rotation severity threshold.
- `tests/wiki/run_all.sh` passes.
