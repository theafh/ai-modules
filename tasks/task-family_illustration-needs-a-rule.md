---
description: Close the gap in the base task skill's Illustrate rule so an incident narrative with no rule attached is explicitly out, not merely under-covered.
scope: plugins/ai_dev/skills/task
created: 2026-08-17T19:32:58
updated: 2026-08-20T18:37:42
status: ready
reported-by: theafh
---

# State that an illustration needs a rule to support, in the base skill's Illustrate bullet

## Goal

The base `task` skill's `<body>` **Illustrate** bullet today is the two-sentence
rule Context quotes. Today the bullet bars an illustration from carrying a rule's whole
meaning, but it never says what happens when an illustration supports no rule at
all — narrative that is accurate and well-written but changes nothing about what
gets built. Closing that gap in the bullet's existing wording, in place, lets
every `task_*` sibling that inherits `<body>` reject rule-less incident narrative
the same way it already rejects duplication and over-compression, from the next
skill load onward.

## Context

`<body>` opens by defining a task body as **self-sufficient**: it carries
everything the work needs that the project itself does not already hold. Two of
its rules already gesture at the same boundary from different angles. **State
once** keeps a rule, constraint, or decision from appearing twice. **Illustrate**
says "The general statement carries each rule or requirement; specific cases,
incident histories, and dated references stay brief illustrations supporting it.
A body whose meaning lives only in an example has its altitude inverted." That
sentence stops an illustration from *replacing* a rule's general statement, but
it never states the sharper case: an illustration with no general statement to
support in the first place. Nothing in `<body>` currently names that as
out-of-bounds, so a body can pass every existing rule while still carrying prose
whose only content is history.

A generalized instance of exactly this shape motivated the gap: after a
downstream measurement gap an existing Acceptance item already required closing
got closed, a Context edit added a paragraph narrating how a related tool bug
was found and fixed, before restating the now-available result. Nothing about
that paragraph changed what the task needed built — the Acceptance item already
covered the requirement generically, satisfied the moment the data existed — and
the edit was reverted once flagged. The author who caught it summarized the
standing intent directly: a task should only contain what it needs to be
implemented and what it should not do; the rest is only distraction. That is the
Illustrate bullet's own logic, stated plainly enough to close the gap.

Every family member that writes or judges a task body draws this boundary from
`<body>` by reference rather than by its own copy: `task_create` fills the
sections `<body>` defines, and `<readiness_checklist>` judges a draft against the
self-sufficiency bar `<body>` sets. The `<family>` list names the full sibling
set. Tightening the one shared bullet reaches all of them the next time each
loads the base skill; none carries a copy of Illustrate to edit separately, which
this task's Acceptance confirms rather than assumes.

## Approach

Rewrite the **Illustrate** bullet in `plugins/ai_dev/skills/task/SKILL.md` in
place, inserting one sentence between its existing two. Keep both existing
sentences byte-identical, add:

> An illustration earns its place only by supporting a rule or requirement the
> body already states; incident narrative with nothing to illustrate — how a
> fact was established, why an earlier attempt failed, what changed since a
> prior version — carries nothing an implementer needs and stays out, however
> accurate.

Land it as one sentence inside the existing bullet rather than a new list entry,
matching **State once**: the rule this task adds is a corollary of Illustrate's
own logic, not a separate concern, so it belongs in the same place a reader
already looks for illustration rules.

**Out of scope:** teaching `lint.py` to detect rule-less incident narrative
automatically. Judging whether a given illustration supports a stated rule is a
prose judgement the linter cannot make, the same reasoning `<body>`'s existing
Illustrate bullet and **Declare exclusions as an Out of scope boundary** both
rest on without automated enforcement; this task states the rule for `task_check`
and a human author to apply, not a check to script.

## Acceptance

- `rg 'An illustration earns its place only by supporting a rule or requirement the body already states; incident narrative with nothing to illustrate — how a fact was established, why an earlier attempt failed, what changed since a prior version — carries nothing an implementer needs and stays out, however accurate.' plugins/ai_dev/skills/task/SKILL.md`
  returns exactly one hit, where it returns none today.
- `rg 'The general statement carries each rule or requirement; specific cases, incident histories, and dated references stay brief illustrations supporting it' plugins/ai_dev/skills/task/SKILL.md`
  still returns exactly one hit, proving the existing first sentence survives
  unchanged rather than being replaced.
- `rg 'A body whose meaning lives only in an example has its altitude inverted' plugins/ai_dev/skills/task/SKILL.md`
  still returns exactly one hit, proving the existing closing sentence survives
  unchanged rather than being replaced.
- `rg -U 'The general statement carries each rule or requirement; specific cases, incident histories, and dated references stay brief illustrations supporting it\.[[:space:]]+An illustration earns its place only by supporting a rule or requirement the body already states; incident narrative with nothing to illustrate — how a fact was established, why an earlier attempt failed, what changed since a prior version — carries nothing an implementer needs and stays out, however accurate\.[[:space:]]+A body whose meaning lives only in an example has its altitude inverted' plugins/ai_dev/skills/task/SKILL.md`
  returns exactly one hit, proving the new sentence sits between the two existing
  sentences rather than before, after, or outside them.
- `rg -c '\*\*Illustrate\.\*\*' plugins/ai_dev/skills/task/SKILL.md` returns `1`,
  proving the new sentence landed inside the existing bullet rather than as a
  second Illustrate entry.
- `rg -l 'specific cases, incident histories' plugins/` returns exactly one file,
  `plugins/ai_dev/skills/task/SKILL.md`, proving no sibling skill carries a copy
  of the Illustrate rule that would also need this edit.
- `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py plugins/ai_dev/skills/task/SKILL.md`
  reports PASS, with every tag still closed.
