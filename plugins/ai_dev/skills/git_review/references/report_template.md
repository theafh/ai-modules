# Review report template

Worked examples of the report form pinned by `SKILL.md`'s `<report>` stage
and its `<form>` rule. Use these examples to see those rules on the page;
the skill body owns the binding form, heading presence, labels, and variants.

---

I reviewed `<sha>` (`<ref>`) and left the tree `<clean | dirty, unchanged>`.
The change is `<approvable | approvable once ... | not approvable because ...>`,
with `<the one change that would flip the verdict>` as the shortest path to yes.
The forge layer is `<available via gh | unavailable because ...>`.
The diff contains `<n>` changed files, `<a>` added and `<r>` removed lines,
with `<p>`% binary or generated (`<paths>`).
`<Gate names>` ran `<locally | on the forge only>`, with `<skipped gates>` skipped.
The discussion contains `<review, issue-comment, and thread counts>`.
`<Unread paths or ranges>` remain unread.

## What the changes do and implement

## What it retires

## What of the existing workflow changes

## What is critical

## Bugs it may introduce

## What should be fixed though it is not a clear bug

## Decisions the implementer must make before fixing

## Can it be structurally merged as it is

---

## A finding on the page

**`<path>:<line>`: `<the defect in one clause>` (`verified`, `non-blocking`).**

`<The evidence, quoted from the diff or reproduced by a command that was run>`.
`<The consequence, as what goes wrong and for whom>`. `<The governing document
and nearest precedent, when the finding rests on one>`.
Fix: `<concrete enough to act on, with a clause pointing to the decisions
section when the fix needs a judgement call>`.

## A decision on the page

> **`<the decision>`.** Option A `<...>`. Option B `<...>`. Suggested default:
> `<A or B>`, because `<reason>`.

## The closing answer on the page

> **Yes.** The test merge against `<base>` is conflict-free, the branch is
> `<n>` ahead and `<m>` behind, and `<k>` of `<k>` checks pass on `<sha>`.
> Context outside this answer: the branch protection requires `<n>` approvals
> and currently has `<m>`.

## A delta tag on the page

> **`<path>:<line>` — `<the prior finding>`.** `closed`: `<what in the tree
> closed it>`.

The tag vocabulary is closed and `<re_review>` owns it.
