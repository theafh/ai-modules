# Review report template

The skeleton to fill, plus one worked example of each shape. The rules that
govern the report live in `SKILL.md`'s `<report>` stage and are not repeated
here: which headings a run omits or keeps, the closing heading for the
uncommitted-changes target, which findings carry which label, and what a
critical finding must cite. Read `<report>` for the rules and this file for the
form they take on the page.

---

Reviewed commit: `<sha>` (`<ref>`). Tree state: `<clean | dirty, unchanged>`.
Forge layer: `<available via gh | unavailable because ...>`.
Diff: `<n>` changed files, `<a>` added and `<r>` removed lines, `<p>`% binary or
generated (`<paths>`).

**Approvable in general:** `<yes | yes once ... | no because ...>`. The shortest
path to yes is `<the one change that would flip the verdict>`.

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

> **`<path>:<line>` — `<the defect in one clause>`.** `<the evidence, quoted
> from the diff or reproduced by a command that was run>`. `<the consequence,
> as what goes wrong and for whom>`. Fix: `<concrete enough to act on>`.
> Decides: `<who>`, where the fix is a judgement call. `(verified,
> non-blocking)`

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
