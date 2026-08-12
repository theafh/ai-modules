---
description: Flag a task body linking one target more than once, a maintenance tax and a hint the body grew organically. Pair a linter warn with a react protocol and a grouping rule.
scope: plugins/ai_dev/skills/task
created: 2026-08-12T19:46:46
updated: 2026-08-12T22:19:20
status: ready
reported-by: Andreas Hoffmann
---

# Warn when a task body links one target more than once: linter, grouping rule, and react protocol

## Goal

An author writing or rewriting a task body gathers what the body says about one
link target into one place, so one link carries that material instead of the same
target being linked again from each section that mentions it. The linter counts
links to each target within a file and warns when one target is linked more than
once, as a hint that the body may have grown organically and would read more
clearly regrouped. The task skills that run the linter carry a protocol for
acting on the hint: re-read the sections that link that target, gather the
material into one place when it says one thing in several, and keep a repeat link
only where that site earns it.

## Context

The base skill's `<markdown_policy>` settles whether a task-to-task link earns its
place, under the bullet led by **Link to another task file when the
cross-reference carries weight**, and the `<body>` **State once** rule settles
that a rule or decision appears in exactly one place. Neither reaches the shape
this task addresses: one target linked repeatedly from a single file, once per
section that touches it.

**The subject is repeated links to one target, of any kind.** The count runs per
target whatever file sits at the other end, covering skill definitions, agent
definitions, scripts, manifests, wiki pages, and other tasks alike, and whether
or not the target links back. The number of *distinct* targets a task carries is
not the subject: a task naming nine distinct files once each is broad and sound,
while a task linking three files seven times over is the case this catches.

A repeated link to one target carries two costs, and neither buys anything. The
first is a maintenance tax. Every link to a file has to stay correct as that file
moves or is renamed, and the `<archive>` workflow already re-points every relative
link when a task is archived, so three links to one target are three edits to keep
in sync where one would carry the same meaning. The second is a coherence signal.
The more often a body links one target, the more likely it accreted that target's
material across several sittings rather than stating it once, so the count is a
hint that the body grew organically and risks reading incoherently. The signal
strengthens with the count rather than switching on at a line, so a body linking
one target twice gets a mild hint and one linking it seven times gets a strong
one.

The live tree shows the distribution the threshold sits in. Running the loop below
across every live `tasks/*.md` file on 2026-08-12 gave 36 target-and-file pairs
carrying exactly two links, 8 at three, one at four, and one at seven.
Reproduce it with this loop from the tasks directory:

```bash
for f in *.md; do rg -o "\]\(([^)]+)\)" -r '$1' "$f" | sort | uniq -c | awk -v F="$f" '$1>1 {print $1, F, $2}'; done | sort -rn
```

Reading the heaviest cases shows the two outcomes the protocol allows. Some spread
one relationship over Context and Approach, where gathering it into one place
helps. Others name a genuine edit site once per section, where each link earns its
own keep and the repeat stays.

**Reconcile with the shipped rejection.** The archived
`task-family_cross-link-discipline.md` decision established the cross-link rule
this task extends, and its Approach ruled a linter rule out on the ground that
judging whether a link adds value needs judgement the linter cannot apply. That
reasoning holds and this change leaves it intact, because a count judges no link's
value. It reports how many times one file links one target and hands the meaning
to the author, which is the split the recall-biased soft-pointer warning already
ships. State the distinction once in the base skill so a later reader keeps the check
rather than re-deriving the rejection against it (proved by Acceptance item 15).

Two shipped siblings set the pattern of an authoring rule paired with linter
support:
[task-family_soft-pointer-references.md](archive/task-family_soft-pointer-references.md)
for position claims and
[task-family_count-stable-references.md](archive/task-family_count-stable-references.md)
for volatile counts. Read either for the shape of the rule text, the warning
wording, and the candidate-not-verdict triage framing.

Seven surfaces run the linter and inherit the protocol: the base `task` skill,
`task_create`, `task_fix`, `task_implement`, `task_audit`, `task_finish`, and the
`auto_shaper_task` agent.

## Approach

Deliver three parts as one change, since the rule, the detector, and the protocol
are meaningless apart.

Edit surfaces: `plugins/ai_dev/skills/task/scripts/lint.py`; the base `task` skill
(`<markdown_policy>` grouping rule and cross-link-discipline reconciliation prose,
`<lint>` protocol, warn-bucket listing, and mechanically fixable set); `task_fix`
(`<surface_for_review>` entry citing the base `<markdown_policy>` grouping rule
rather than restating the grouping test).

**a. Count links per target in the linter and report the hint.** Add a check
beside the existing link checks in `lint.py` that collects every markdown link in
a body. Count only links outside fenced code blocks — the same fence boundary
`check_no_position_claims` uses via `_scrub_fences`, so documentation examples in
fences do not participate — and skip external targets the way `check_local_links`
skips `://` and `mailto:` URLs. Include every other resolved local target whether
or not its path ends in `.md`, so `SKILL.md`, `plugin.json`, and `scripts/<name>`
helpers count the same as task and wiki `.md` links. The check resolves each
target by normalized path so one file reached through different relative prefixes
counts once, and emits one `SEV_WARN` finding per target linked more than once,
using the warn category `repeated-link`, naming the target and its count. Carry the
more-than-once floor in a named module-level constant with a comment recording the
measured distribution and noting that the hint strengthens with the count, so a
later reader retunes the floor against fresh data if the triage load proves too
broad. Word the message as a hint about the body's order rather than an
instruction to remove a link: the target is linked N times, which suggests the
material about it sits in several places and the body may have grown organically,
so re-read those sections and gather what belongs together. Keep the finding a
candidate rather than a verdict, matching the soft-pointer warning, and leave it
out of the mechanically fixable finding set, because deciding how to regroup a
body is a prose judgement. Prove the lint scenarios through fixtures in
`tests/tasks/script_tests/` run by `tests/tasks/run_all.sh`, matching the standing
`lint.py` unit-test harness for the task family.

**b. Give the task skills a protocol for acting on the hint.** Add the protocol to
the base skill's `<lint>` section so every surface that runs the linter inherits
one procedure: read the sections that link the counted target, decide whether they
state one relationship in several places or name a distinct role each time, then
gather the material into one place carrying one link when it states one
relationship, and keep the repeat when each site carries its own role. Where
gathering the material reveals the body actually grew into separate concerns, take
the scope question to the existing split guidance. A surface that writes applies
the regroup in its own edit round and bumps `updated` once with it. A read-only
surface reports the finding with the sections it covers and leaves the regroup to
the writer. In `task_fix/SKILL.md`, add a `<surface_for_review>` entry citing the
base `<markdown_policy>` grouping rule rather than restating the grouping test,
surfacing the finding for the user to decide rather than repairing it, consistent
with its treatment of the other judgement findings.

**c. State the grouping rule for writing and rewriting.** Add a rule to
`<markdown_policy>` beside the cross-reference bullet that governs authoring at
creation and at every later rewrite. Gather what the body says about one target
into one place, and let one link carry that group. Where a paragraph already links
a target, name it again inside that paragraph in plain text. Keep a further link to
the same target where that site earns it on its own, such as an edit site named in
Approach that Context introduced as background, or an `**Out of scope:**` deferral
naming the owner of excluded work. Treat a target linked from several sections as a
signal to re-read the body and regroup before keeping the links. State once beside
the cross-reference bullet that the repeated-link check counts frequency only and
does not judge whether a link adds value, distinguishing it from the archived
cross-link-discipline value test (proved by Acceptance item 15). Phrase the rule
positively, leading with the grouping action, per the standing repo authoring
conventions the skill already follows.

**Out of scope:**

- Judging whether a link adds value at all, settled by the archived
  `task-family_cross-link-discipline.md` decision Context records and unchanged
  here.
- The number of distinct targets a task links, which measures breadth rather than
  the repeated-link tax this task addresses.
- Auto-regrouping a flagged body, since deciding how material regroups is a prose
  judgement the author owns.
- A migration sweep over the existing tree. Live tasks converge as they pass
  through readiness and repair, matching how the `**Out of scope:**` convention
  converges.

## Acceptance

1. A fixture in `tests/tasks/script_tests/` linking one target twice produces one
   `repeated-link` warning naming that target and the count of 2, and the message
   states that the count is a hint that the body may have grown organically and
   that re-reading those sections to regroup may help.
2. A fixture in `tests/tasks/script_tests/` linking that target once produces no
   warning, proving the floor is more than one link to a single target.
3. A fixture in `tests/tasks/script_tests/` linking one target seven times produces
   one warning whose count is 7, and the message frames a higher count as a stronger
   hint than a lower one.
4. A fixture in `tests/tasks/script_tests/` reaching one file through two
   different relative prefixes produces one warning with a count of 2, proving
   targets resolve by normalized path rather than by written path.
5. A fixture in `tests/tasks/script_tests/` linking a sibling task, a `SKILL.md`, a
   wiki page, a `scripts/<name>` helper, and a `plugin.json` manifest twice each
   produces the finding for every target kind, and a target that never links back
   is counted the same as a reciprocal one.
6. A fixture in `tests/tasks/script_tests/` linking nine distinct targets once each
   produces no warning, proving the check counts repeats of one target rather than
   the total link count.
7. A fixture in `tests/tasks/script_tests/` linking one local target twice only
   inside a fenced code block produces no warning, proving fenced links do not
   participate in the count.
8. A fixture in `tests/tasks/script_tests/` linking the same `https://` URL and the
   same `mailto:` address twice each produces no warning, proving external and
   `mailto:` targets are skipped the same way `check_local_links` skips them.
9. `tests/tasks/script_tests/` covers the fixture scenarios in items 1–8, and
   `tests/tasks/run_all.sh` exits 0.
10. The floor lives in a named constant whose comment records the measured
    distribution and the strengthens-with-count framing, so searching the script
    finds the number and its justification in one place.
11. The base skill's `<lint>` section carries the protocol as one procedure, naming
    the read step, the regroup-or-keep decision, the route to the split guidance
    when regrouping reveals separate concerns, the writing surface's edit round with
    its single `updated` bump, and the read-only surface's report.
12. The base skill's `<lint>` warn bucket lists the `repeated-link` finding, states
    that each hit is a candidate rather than a verdict — read the sections it names
    and triage before regrouping, matching the soft-pointer warning — and the
    mechanically fixable finding set omits it, so an auto-repair sibling surfaces it
    rather than editing it.
13. `task_fix` surfaces the `repeated-link` finding for the user to decide, citing
    the `<markdown_policy>` rule rather than restating the grouping test.
14. `<markdown_policy>` states the grouping rule beside the cross-reference bullet,
    leading with the grouping action, covering the plain-text repeat inside a
    paragraph and the load-bearing further link, naming a target linked from several
    sections as a signal to re-read the body and regroup before keeping the links,
    and passing the `ai_instruction_writing` `<self_check>`.
15. Grepping the base `task` skill's `<markdown_policy>` or adjacent reconciliation
    prose finds one statement that the repeated-link check counts frequency only
    and does not judge whether a link adds value, distinguishing it from the
    archived cross-link-discipline value test (false today — the distinction is
    stated only in this task's Context).
16. Running the linter over the repository's current live `tasks/*.md` tree produces
    no blocking finding, and each `repeated-link` warning names a local target whose
    non-fenced link count exceeds the floor — verified by comparing linter output to
    a filter-aligned reproduction that skips fenced code blocks and `://` /
    `mailto:` targets the way Approach **a** describes.
