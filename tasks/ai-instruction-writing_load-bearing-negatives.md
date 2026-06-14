---
description: "Add a load-bearing-negative case to ai_instruction_writing: keep an enumerated ban that names specific traps or mirrors a mechanical check, rather than cutting it as a redundant inverse."
scope: plugins/ai_dev/skills/ai_instruction_writing
created: 2026-06-13T01:10:16
updated: 2026-06-13T01:10:16
status: open
reported-by: Andreas Hoffmann
---

# Recognise load-bearing negatives in ai_instruction_writing

## Goal

The `ai_instruction_writing` skill should tell an author to **keep** an enumerated negative when that negative carries information the positive cannot — the specific wrong forms a writer would reach for, or the exact set a downstream mechanism (a linter, a parser) acts on. Today the skill has no category for this case, and its existing guidance on enumerable negatives points the other way: it would have the author delete a load-bearing ban as a "redundant inverse." After this change the skill separates a genuinely redundant inverse (cut it) from a load-bearing negative specification (keep it), and states a clear test for telling the two apart.

## Context

`ai_instruction_writing` is this repo's rubric for positive, action-oriented instruction writing. Its `<core_rule>` is that every instruction's primary carrier is a positive statement, and a negative earns its place only as a catch-all for a long tail no positive could enumerate.

The skill's `<self_check>` gives exactly three outcomes once you delete a rule's negative portion:

- the positive is empty or vague → the rule is inverted; rewrite the positive (`<when_positive_is_empty_or_vague>`);
- the positive is complete → the negative is a redundant inverse; drop it (`<when_positive_is_complete>`);
- the negative names a broader class than any positive could list → keep it as a catch-all (`<when_negative_names_a_broader_class>`).

**The gap.** A fourth, common case falls between these three: a negative whose excluded cases are *enumerable* (so it is not a catch-all) yet *load-bearing* (so it is not redundant), because the enumeration names something the positive does not imply. The skill has nowhere to place such a negative — and its one worked example of an enumerable negative, `<invalid_redundant_negative>` ("Use 4-space indentation; don't use tabs or 2-space indents." → drop the negative), tells the author to cut it. Applied literally, that example mis-fires on a legitimate ban.

**The concrete case that exposed it.** While reviewing the soft-pointer rule in the `task` skill — *anchor every reference on a verbatim label; keep position claims out: a `:N` path suffix, a bare `line N`, an `around lines N–M` range* — the three banned shapes are an enumerable negative, so the skill's `<invalid_redundant_negative>` pattern would say "cut them." Cutting them is wrong, because the enumeration carries information the positive ("use a verbatim label") cannot:

- it names the **specific traps** a writer reaches for — you would never derive a `:N` suffix or an `around lines N–M` range from "use a verbatim label"; and
- it mirrors a **mechanical check** — a linter flags exactly those shapes, so the prose must name them to stay in step with the tool.

**Why the redundant-inverse example is genuinely different.** In "Use 4-space indentation; don't use tabs," the positive already implies every excluded case (choosing 4-space leaves nothing to spell out), and no tool keys on the words "tabs" or "2-space." That negative really is redundant. The discriminator between the two is one question: **does the reader learn a banned form they could not derive from the positive carrier, or does a tool act on the exact named set?** When yes, keep the negative; when no, it is the redundant inverse the skill already covers.

**The `<applicability>` framing is also too narrow.** `<applicability>` currently legitimises negative *examples* only in "meta or teaching context — including this skill," which implies a production rule should avoid them. But production rules — like the `task` skill's soft-pointer rule — legitimately need negative specifications, so the framing should recognise them there too.

This task refines the skill's own ruleset. It is distinct from the archived family-wide sweep that *applied* the rubric to the `task_*` skills (that task treated the three-outcome `<self_check>` as fixed and rewrote prose to match it); this task changes the rubric itself by adding the missing fourth case.

## Approach

Edit the `ai_instruction_writing` `SKILL.md` so the skill recognises the load-bearing negative as its own case. Lead every addition with a positive carrier, matching the skill's house style.

1. **Add a fourth `<self_check>` outcome** for the enumerable-but-load-bearing negative: keep the negative when its listed cases carry information the positive cannot imply — the specific wrong forms a writer would reach for, or the exact set a downstream mechanism (a linter, a parser) acts on.
2. **Add a matching category** beside `<catch_all_negative>` — a sibling block for a valid negative *specification* — that contrasts directly with `<invalid_redundant_negative>`. Give two worked examples that resolve oppositely: keep "anchor on a verbatim label; keep position claims out — a `:N` suffix, a bare `line N`, an `around lines N–M` range" (the shapes name traps and mirror a linter); cut "Use 4-space indentation; don't use tabs" (the positive already implies the rest and no tool keys on the names).
3. **State the discriminator test** in the new guidance so it cannot be stretched to excuse any negative: keep only when the reader learns a banned form they could not derive from the positive, or a tool acts on the exact named set; otherwise it is the redundant inverse `<invalid_redundant_negative>` already covers.
4. **Broaden `<applicability>`** so it recognises negative specifications as legitimate in production rules, not only in meta or teaching context.

Keep the change to framing and categories: leave the `<core_rule>`'s thrust intact (a positive carrier leads every instruction), and keep the pseudo-XML structure, the `name:`/H1 alignment, and the rest of the skill unchanged.

## Acceptance

- `<self_check>` carries a fourth outcome branch that keeps an enumerable negative when its cases carry information the positive cannot imply (false today: `<self_check>` offers only the inverted / redundant / broader-class outcomes).
- A category beside `<catch_all_negative>` presents two enumerable-negative examples that resolve oppositely — a "keep" (the soft-pointer-style ban, justified by named traps and parity with a mechanical check) explicitly contrasted with `<invalid_redundant_negative>`'s "cut" — so an author can tell the load-bearing negative from the redundant one (false today: the only enumerable-negative example says cut).
- The new guidance states the discriminator test: keep when the reader learns a banned form they could not derive from the positive or a tool acts on the exact named set; cut when the positive already implies every excluded case (false today: no such test exists).
- `<applicability>` no longer implies negatives are legitimate only in meta or teaching context; it recognises negative specifications in production rules (false today: `<applicability>` limits legitimacy to "meta or teaching context — including this skill").
- The added content leads with positive carriers and keeps the skill's pseudo-XML structure and `name:`/H1 alignment intact, so the rubric still obeys its own `<core_rule>` (the edit practices what the skill preaches).
