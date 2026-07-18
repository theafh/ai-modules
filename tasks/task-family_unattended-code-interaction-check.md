---
description: Add a code-anchored readiness lens so task_check and task_auto_check surface interacting or contradicting code a task is silent about, found by a keyed repo search over its touch-points.
scope: plugins/ai_dev/skills
created: 2026-07-14T20:48:17
updated: 2026-07-18T07:24:12
status: ready
reported-by: Andreas Hoffmann
---

# Add a code-interaction readiness lens that surfaces shipped code a task is silent about

## Goal

Give `task_check` and `task_auto_check` a new readiness lens that inspects the
code a task would interact with at implementation time and surfaces behaviour,
invariants, or already-shipped features the task **does not mention** but that
could silently contradict or drift against its intended change. The motivating
case: a task written before some feature shipped, whose Approach would now collide
with — or be quietly undermined by — code that landed since, with nothing in the
task pointing at it, so the conflict reaches the implementer undetected.

The lens is **code-anchored**, the mirror of the existing task-anchored checks: it
starts from the task's change and asks "what in the codebase now interacts with
this that the task never accounts for?", rather than starting from what the task
describes. It is authored once in the base `task` skill's `<readiness_checklist>`
and inherited by both front-ends.

The user-visible outcome:

- The base `task` skill carries one new checklist lens defining the code-side
  interaction scan; `task_check` and `task_auto_check` inherit it through their
  existing `<authority>` reference.
- The scan reaches interacting code the task never linked, without reading the
  whole repository: it derives the task's interaction surface, searches the repo
  for references to those touch-points, and reads only the hits.
- Each finding routes through the reconcile-or-surface disposition rather than a
  new one: `task_check` recommends the reconciled fix or surfaces the interaction
  with options; `task_auto_check` refreshes the body against the found code through
  its verified-repair loop, or surfaces the task as stuck when no evidence settles
  the fix. Both keep their existing read-only / write contracts.

## Context

Three files change, all under `plugins/ai_dev/skills/`:

- `task/SKILL.md` — the base skill, where the lens is authored once.
- `task_check/SKILL.md`, `task_auto_check/SKILL.md` — the two front-ends that
  inherit and apply it.

**Why the base skill owns the lens.** The repo's `CHARTER.md` invariant
*"Skill-family rules live in the family base skill when they govern the whole
family; front-end skills inherit those rules instead of carrying divergent
copies"* applies because both front-ends need the same lens.

**The gap this fills.** The two nearest existing lenses in the base
`<readiness_checklist>` are both *task-anchored* — they start from what the task
says:

- The **Premise check** verifies the task's *described* current state against the
  code — "quote each command, flag, path, and passage the task describes beside the
  code's actual text." Its **Drifted** outcome includes "part of the work meanwhile
  shipped," but only for details the task already names.
- **Approach fitness** enumerates interacting directives and invariants, but only
  "in the artifacts the approach touches."

Neither mandates a sweep for interacting code the task is *silent* about and does
not touch by name. This new lens is that sweep, and it sits beside those two as a
sibling premise/fitness lens rather than folding into either.

**The scan boundary — repo-wide reach, bounded read.** A full-repo read is too
costly and a scan of only the task's linked files is incomplete, because the code
that silently interacts is exactly what the task failed to mention. The scan
resolves that tension by keying on the task's own change rather than its link
list:

1. **Read what the task points at.** Read the artifacts the task links and names —
   its `scope`, the files cited in Context and Approach — and derive its
   **interaction surface**: the concrete symbols, function and type names, config
   keys, rule or tag names, file states, and behaviours its change would create,
   rename, remove, or consume.
2. **Search the repo for other hits, then assess.** Search the repository for
   references to those touch-points with whatever repository search tools the agent
   has available, which reaches callers, consumers, alternate definitions, tests,
   and docs the task never linked. Read the hits, and for a hard-interaction hit —
   code that writes or reads the same state, or that the change would break or be
   broken by — follow one hop to its own references, then assess each for a
   contradiction or an unattended interaction.

So the scan searches the whole repo for the task's touch-points but reads only what
those touch-points reach; "search the whole repo for my touch-points" is not "read
the whole repo."

**Disposition reuses the reconcile-or-surface rule.** A surfaced interaction is
handled by the family's reconcile-or-surface rule, now live in the base `task`
skill's `<body>` as **Decide or label** (landed by [the open-decision
reconciliation task](archive/task-family_reconcile-or-surface-open-decisions.md)):
reconcile the conflict against the found code when the evidence settles the fix,
otherwise surface it with suggested options. This lens supplies the *detection*;
that rule supplies the *disposition*.

**Co-edit coordination.** The
[honor-task-dependencies task](task-family_honor-task-dependencies.md) also edits
`task/SKILL.md`. Whichever of the two tasks lands second re-reads that shared file
and anchors its edits to the target passages by their verbatim labels rather than
by position, so the changes compose without clobbering each other.

## Approach

Edit the three `SKILL.md` files in positive, action-oriented language and their
existing pseudo-XML structure. Author the lens once in the base skill; both
front-ends inherit it.

**Base `task` skill — author the lens once:**

1. Add a new lens to the `<readiness_checklist>`, placed beside the **Premise
   check** and **Approach fitness** lenses it complements and anchored by a
   verbatim label the front-ends can cite. The lens directs the assessor to first read
   what the task links and names and derive its interaction surface, then search the
   repository for other references to those touch-points with whatever search tools
   the agent has, read the hits plus one hop for hard-interaction sites, and
   classify each result: a **contradiction** — code the task's change would break
   or that would break the change — or an **unattended interaction** — shipped
   behaviour, invariant, or feature the task should account for but never mentions.
   State that a confirmed finding is a readiness issue, and route its disposition
   through the reconcile-or-surface rule rather than defining a new one: reconcile
   against the found code when the evidence settles the fix, else surface with
   suggested options. Ground the finding the same way the base checklist already
   requires — a written juxtaposition of the interacting code against the task's
   change — so an unverified suspicion stays a question, not a numbered issue.

**`task_check` — apply the lens, stay read-only:**

1. Extend `<assessment>` so the assessment runs the new lens as one of the
   checklist lenses it applies, reports a confirmed contradiction or unattended
   interaction as a readiness issue with its code evidence, and either recommends
   the reconciled resolution as the fix or surfaces the interaction with suggested
   options. Preserve the read-only, stamp-only contract: `task_check` recommends
   and surfaces and writes no body content.

**`task_auto_check` — refresh the body against the found code, or surface:**

1. Wire the lens into the loop so a finding it raises is repaired like a drifted
   premise: the reviewer proposes a minimum body edit that refreshes the task
   against the found interacting code, the verifier keeps it only when it is
   evidence-grounded and intent-preserving, and an unreconcilable finding surfaces
   through the existing stuck / human-routed channel with suggested options rather
   than a newly added channel. Add a reviewer stance for this lens only as a
   concrete application of the base body-repair rules, matching how the existing
   stances are defined.

When a finding's repair adds a check that the interaction is now handled — an
Acceptance item that supersedes the stale silence with a concrete
edit-supersedes proof — add it as part of the body repair. The lens's primary home
is the checklist, and the Acceptance addition is a secondary effect of repairing a
finding, not a separate detection surface.

Non-goals: author the lens once in the base skill and have the front-ends cite it —
do not copy the scan procedure into either front-end. Keep the scan the bounded
two-step — read what the task links and names, then one repository search pass over
its touch-points with whatever search tools the agent has, reading the hits plus one
hop for hard-interaction sites — never a full-repo read, never only the task's
linked files, and not a recursive expansion that follows references of references to
a fixed point (its deeper transitive reach is not worth the unbounded cost). Name
the search capability generically rather than pinning a specific tool, so the lens
stays portable across harnesses. Keep the lens a reasoning procedure the skills
apply, not a bundled script. Leave `task_implement` untouched: it consumes a task already made
ready, and its existing "understand the existing codebase" step is about whether
the work is already done, not this pre-implementation readiness sweep. Leave
`task_select`, `task_audit`, `task_finish`, and `task_fix` untouched. This edits
shipped skill content, so the standing repo version-bump, plugin-lockstep, and
lint-clean-before-commit rules apply at commit time.

## Acceptance

- `task/SKILL.md`'s `<readiness_checklist>` carries one new code-anchored lens,
  placed beside **Premise check** and **Approach fitness**, that defines the
  two-step scan — read what the task links and names to derive its interaction
  surface, then search the repo for other references to those touch-points with the
  agent's available search tools — reading the hits plus one hop for
  hard-interaction sites, and classifying a result as a contradiction or an
  unattended interaction; the lens is distinct from the two adjacent task-anchored
  lenses rather than folded into them.
- The lens states the scan boundary as repo-wide search reach over the task's
  touch-points with a bounded read of only the hits, explicitly neither a full-repo
  read, nor a scan limited to the task's linked files, nor a recursive expansion to
  a fixed point; it names the search capability generically rather than pinning a
  specific tool.
- The lens routes a confirmed finding's disposition through the family
  reconcile-or-surface rule and cites it rather than defining a parallel
  disposition; it requires the same written code-versus-change juxtaposition the
  base checklist already demands before a finding becomes a numbered issue.
- `task_check/SKILL.md`'s `<assessment>` applies the new lens as one of its
  checklist lenses and reports a confirmed contradiction or unattended interaction
  with code evidence, either recommending the reconciled fix or surfacing options;
  the read-only, stamp-only contract is intact and `task_check` writes no body
  content.
- `task_auto_check/SKILL.md` wires the lens into the loop so a finding is repaired
  like a drifted premise through a verifier-approved, intent-preserving body edit
  that refreshes the task against the found code, and an unreconcilable finding
  surfaces through the existing stuck / human-routed channel; any new reviewer
  stance is a concrete application of the base body-repair rules.
- A grep over `task_check` and `task_auto_check` confirms each cites the base lens
  by its verbatim label and neither restates the scan procedure, satisfying the
  `CHARTER.md` family-rule invariant.
- A staged fixture proves the behaviour: a task authored before a feature shipped,
  whose change interacts with that feature through a symbol the task never links,
  has the interaction surfaced by `task_check` and repaired-or-surfaced by
  `task_auto_check`; the repository search reaches the unlinked interacting file
  through a touch-point reference, and the run does not require reading files the
  touch-points never reach. When `task_auto_check` repairs this fixture's
  interaction, the refreshed fixture task carries a new edit-supersedes Acceptance
  item that supersedes the stale silence and proves the interaction is now handled.
- A second fixture confirms no false alarm: a task whose change shares no
  touch-point with surrounding code raises no interaction finding.
