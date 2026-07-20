---
name: task
description: Manage the project task backlog as plain markdown files in tasks. Use for broad backlog work including create, list, query, update, triage, implement, audit, finish, defer, archive, lint, split, or repair tasks.
version: 1.3.22
author: Andreas F. Hoffmann
license: MIT
---

# task

<task_skill>

<role>
The task skill is the hub and source of truth of the `task_*` family: the **project-local backlog** that manages a project's upcoming work and todos as plain-markdown task files living next to the code. The concept behind the whole system: every task file is written to be **self-sufficient** — the file alone is enough to implement the work from, including in a later session with no memory of the task's creation. That sufficiency is a floor, never a filter: at implementation time the implementer draws on everything actually available — the codebase, the project's standing-instruction baseline, the user in the loop.
</role>

<when_to_activate>
Activate this skill when the user:

- Asks to create, write, capture, file, or add a task / todo / backlog item.
- Asks to list, show, find, or query existing tasks.
- Asks to update, edit, refine, or expand a task.
- Says a task is done, finished, implemented, shipped, or completed — move it to archive with status `finished`.
- Says a task should be dropped, parked, deferred, or shelved — move it to archive with status `deferred`.
- Asks to lint, audit, or health-check the tasks directory.
- Mentions the project's tasks, todos, or backlog in any way that implies persisting upcoming work as files rather than chat state.
</when_to_activate>

<not_in_scope>
The wiki skill captures durable knowledge (concepts, procedures, references). The task skill captures *upcoming work* on this project. When a user message is about recording what they learned or how something works, route to `wiki` instead. When they want to track what still needs doing, this skill is right.
</not_in_scope>

<architecture>
```text
<project-root>/
├── CLAUDE.md?        # optional harness-loaded project rule file
├── AGENTS.md?        # optional harness-loaded project rule file
├── GEMINI.md?        # optional harness-loaded project rule file
├── CHARTER.md?       # optional family-consulted hard project-purpose guardrail
├── ARCHITECTURE.md?  # optional family-consulted descriptive project architecture
├── FEATURES.md?      # optional family-consulted behaviour ledger
├── TESTING.md?       # optional family-consulted project-specific testing notes
└── tasks/
    ├── <scope>_<name>.md      # open tasks
    ├── <scope>_<name>.md
    └── archive/
        ├── <scope>_<name>.md  # finished + deferred tasks
        └── <scope>_<name>.md
```

The filing convention has one canonical split: material directly about the task system lives under `tasks/`, and project-wide standing material lives at the repo root as optional `UPPERCASE.md` docs. Two root-doc roles exist there: harness-loaded rule files (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` and equivalents) provide the project's standing-instruction baseline, while family-consulted guardrail docs (`CHARTER.md` / `ARCHITECTURE.md` / `FEATURES.md` / `TESTING.md`) add task-family-specific constraints and context. The task tree stays intentionally two layers — `tasks/` for live work, `tasks/archive/` for closed work. No further task nesting. Scope sits in the filename, not in a folder. A bare project with only `tasks/` remains complete.
</architecture>

<standing_doc_consumption>
Resolve the project root from the base `<discover>` step. The project's standing instructions start with the harness-loaded root rule files: `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` and equivalents. When present, the harness loads those files before the skill runs, and the task family follows that baseline at every touchpoint independent of whether any family guardrail doc exists. The task family adds no separate presence-gated read for those harness files because the harness already supplies them.

Family-consulted guardrail docs are the additive layer over that baseline. Gate each optional family guardrail doc read with POSIX `test -f "$root/<DOC>.md"`. On a hit, the consuming skill or agent reads the doc for the purpose named at its touchpoint; on a miss, it continues unchanged and raises no missing-doc error.

`CHARTER.md` is the highest-order guardrail: any skill or agent about to write or change task content validates the proposed content against the charter's boundaries and invariants and stops on a violation. The harness baseline governs wherever the family guardrail docs are silent. When a harness rule conflicts with a softer guardrail doc (`ARCHITECTURE.md` / `FEATURES.md` / `TESTING.md`), surface the conflict for human review instead of auto-resolving it. The softer docs inform work without blocking it: `FEATURES.md` and `ARCHITECTURE.md` provide prior-art and design context for task creation, `TESTING.md` provides project-specific testing details for implementation and audit, and `ARCHITECTURE.md` is refreshed during finish when completed work extends the design.
</standing_doc_consumption>

<file_format>

<naming>
`<scope>_<name>.md`. One underscore — exactly one — separates scope from name. Inside each side, words use `-`. Both sides are lowercase `a-z 0-9 -`. Examples:

- `wiki-fix_split-page-anatomy.md`
- `tasks-skill_initial-implementation.md`
- `auth_session-token-rotation.md`
- `infra_grafana-dashboard-cleanup.md`

Pick `scope` from the project's natural shared groupings — a skill family, sub-project, module, topic, feature area, or service. Pick `name` to be compact, unique within the tasks tree (open *and* archive), and self-explanatory at a glance. Before creating, list the tasks directory and `archive/` once to confirm the chosen name does not collide.
</naming>

<frontmatter>
Every task carries this YAML frontmatter:

```yaml
---
description: One-line compact summary of what this task delivers.
scope: plugins/ai_dev/skills/task
created: 2026-05-28T19:49:23
updated: 2026-05-28T19:49:23
status: open
reported-by: default_user
---
```

Fields:

- `description` — compact one-liner. Compose to roughly 180 characters; the linter warns above 200, and that gap is headroom for a later broadening edit rather than length to write at. The body carries the full context.
- `scope` — either a relative path under the project root pointing at the directory the task targets (unquoted; e.g. `scope: plugins/ai_dev/skills/task`), or a short descriptive label when no single directory fits (quoted; e.g. `scope: "project xyz"`). The linter resolves an unquoted value against the project root and blocks if the path is missing or escapes the root; a quoted value is accepted as text. Paths win when one fits — the filesystem stays the source of truth.
- `created` — ISO 8601 datetime, set once when the task is created.
- `updated` — ISO 8601 datetime, bumped on every edit and on every status change. See `<bump_updated>` for the legacy-backfill exception.
- `status` — one of:
  - `open` — created and not yet checked.
  - `checked` — `task_check` ran and found blocking issues, either directly or as the gate inside `task_auto_check`.
  - `ready` — implementation-ready, either from a clean `task_check` verdict, from `task_auto_check` reaching that verdict, or from the user declaring readiness through the apply-findings update flow.
  - `implemented` — `task_implement` built the work.
  - `audited` — `task_audit` confirmed every body item, acceptance check, and required test over a current `implemented` task.
  - `finished` — closed out as done and archived.
  - `deferred` — parked or dropped and archived.
- `reported-by` — the user who created the task, written by the create path and resolved via `<user_name_chain>`. See `<bump_updated>` for legacy backfill.
- `implemented-by` — the user who built the work, written by `task_implement` when it stamps `implemented`, required on `implemented`, `audited`, and `finished`, and resolved via `<user_name_chain>`. Deferred tasks omit it because they were never implemented. See `<bump_updated>` for legacy backfill.

Status matches location: `open`, `checked`, `ready`, `implemented`, and `audited` live in `tasks/`; `finished` and `deferred` live in `tasks/archive/`.

<user_name_chain>
Resolve a recorded user name by reading `git config user.name`; when that is empty or the project is not a git repo, ask the user which name to record; when the ask goes unanswered, write the literal string `default_user`.
</user_name_chain>

Obtain the timestamp by running the shell command below and copy its output verbatim — the model has no clock, so a hand-written time is a guess:

```bash
date +%Y-%m-%dT%H:%M:%S        # local time, e.g. 2026-05-28T19:49:23
```

Both `created` (set once, on a fresh task) and `updated` (bumped on every edit, status change, and archive move) take their value from this command's output. When creating several tasks in one turn, run `date` once and reuse the captured value across the batch rather than re-running it per file.
</frontmatter>

<lifecycle_responsibility>
Each stage records the furthest lifecycle point it establishes: `task_create` writes `open`; `task_check` writes `ready` on a clean verdict and `checked` when blocking findings remain; `task_auto_check` edits the task body and reuses `task_check` for those `ready` / `checked` stamps; the apply-findings update flow writes `ready` only when the user declares readiness before implementation; `task_implement` writes `implemented`; `task_audit` writes `audited` only for a clean, complete verdict over a current `implemented`; `task_finish` writes `finished` for done work or `deferred` for parked work.
</lifecycle_responsibility>

<backward_move_guard>
Before a stage writes a status that could move a task backward, read the current status and compare it to the target. The guarded writers are exactly `task_check` and `task_implement`: `task_check` may otherwise overwrite `implemented`, `audited`, or `finished` with `checked` or `ready`, and `task_implement` may otherwise overwrite `audited` or `finished` with `implemented`. On a regression, warn, name the current→target move, and ask the user to confirm the move is intended unless the session context already makes that intent clear, then proceed only when confirmed. Forward moves, same-status stamps, `task_check` revising `ready` back to `checked`, and parking as `deferred` proceed without this guard.
</backward_move_guard>

<markdown_policy>
Task bodies are **100% CommonMark-standard markdown**. The YAML frontmatter at the top is the only allowed extension. The linter blocks on non-standard syntax so the tasks tree stays portable to any renderer and the filesystem stays the source of truth:

- **No footnotes.** `[^name]` references and `[^name]: …` definitions are non-standard. Place attribution inline as a normal markdown link next to the claim.
- **No wikilinks.** `[[target]]` is an Obsidian extension. Use `[text](relative-path.md)` for cross-references.
- **Local cross-references are standard markdown links.** Relative `.md` links to other task files (under `tasks/` or `tasks/archive/`) must resolve on disk — the linter blocks broken targets.
- **Link to another task file when the cross-reference carries weight.** Add a link when it marks a **dependency** (this task builds on, extends, or must follow the other), when reading the linked task would **change how this task is implemented** (it defines a rubric, format, or interface this task consumes), or when the **linked file will be co-edited** (a shared region, a coordinated double-edit, or competing mechanisms to reconcile). The settling test: would reading the linked task, or knowing it exists, change how you implement this task or edit this file? Keep the link when yes; leave out a relatedness-only reference — a bare "see also" / "distinct from" / "pairs with", or a reverse-duplicate pointer whose relationship the linked side already states — since reading the target changes nothing about the work.
- **Locate referenced content by a verbatim label — the soft-pointer rule.** Anchor every pointer to an exact, greppable string in the target — a heading, a pseudo-XML tag, a symbol or rule name, a list item's bold lead-in, or a short quoted phrase — together with the file path, so the reference resolves by search and fails loudly (grep finds nothing) once the target is reworded rather than landing the reader on stale, plausible-looking wrong code. The label carries the whole reference and must be verbatim-greppable: a vague description like "the matchers block" does not qualify. Give extent, when useful, as size — "the ~10-line guard block" — never as position. Keep position claims out: a `:N` suffix on a file path, a bare `line N`, an `around lines N–M` range, and an ordinal list-position reference such as "step 6", "item 3", or "the second bullet" all locate by a position that rots silently as the target evolves. When the referencing task inserts, removes, or reorders items in the target list, anchor to the item's own verbatim label rather than to its ordinal position.

Simplicity, single-topic scope, and standard tooling beat every non-standard extension.
</markdown_policy>

<body>
The body starts with a single `# Title` H1 on the first non-blank line, followed by the rest of the task content. Write the body to be **self-sufficient**: the file carries everything the work needs that the project itself does not already hold, while whatever exists at implementation time — the codebase, the project's standing-instruction baseline, the user in the loop — stays in play and gets used. Self-sufficiency is what lets a task outlive its origins: the conversation that created it is the one context guaranteed to be gone by then. Corollary: content a standing project instruction (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` and equivalents, plus the applicable family guardrail docs) already mandates is cited from the task as a standing repo rule, with the rule's text staying in its source document. Fill these sections:

- **Goal** — what the task delivers and the user-visible outcome.
- **Context** — pointers to the relevant files, modules, prior decisions, related tasks, links.
- **Approach** — the intended implementation path and any constraints, plus the task's declared exclusions when it has them, carried in the single `**Out of scope:**` block the **Declare exclusions as an Out of scope boundary** rule defines.
- **Acceptance** — the contract of concrete checks that say the task is done (a staged fixture the new behaviour is proven on, a file state to inspect, a measurement to record). Every item honours the contract:
  - **Deliverable items flip.** Each item is false today and flipped true by the work, verifiable mechanically — a command to run, a file state to inspect, a behaviour to observe.
  - **Edit items supersede the stale passage.** When the task changes an existing artifact, at least one item checks that the prior passage is superseded and one canonical statement remains, rather than only checking that the new content appears somewhere.
  - **Task-specific gates only.** Every item's outcome changes with this task's work. The project's standing instructions own the generic gates — `make lint`, a deploy dry-run, the full test suite — which run at their standing moments; name a gate only when the task changes what it verifies, such as a new lint rule proven on a staged fixture or a new scenario added to a suite.
  - **Implementer-runnable.** Every item verifies through steps the implementer runs alone; an action the project's standing instructions gate on the user stays out of acceptance.
  - **Measured, with a fail branch.** Stochastic or empirical work names its measurement protocol — run count, fixed denominator, baseline — and the recorded measurement is the deliverable; the item states what happens when the hypothesis fails rather than gating on the hoped-for direction.
  - **Enumerate.** Prefer a list of independently verifiable items over one compound check.

Write the body positive and action-oriented: the primary carrier of every section is what the work does — Goal, Approach, and Acceptance lead with the action taken and what "done" looks like. Negatives earn their place where they carry content of their own: a genuine out-of-scope entry, a guardrail, or the task-specific gate the **Acceptance** contract defines. Keep rejected-option debate out of the body: a brief out-of-scope entry or guardrail stays, while the rationale for options weighed and rejected lives in the change's commit or pull-request description, or in the wiki when it is durable design knowledge. Frame the body as current state to target — what exists, what is not there yet, and the state the work reaches — and let **Rewrite in place, don't append** define the target when an existing passage is affected.

Further rules govern the body's structure:

- **State once.** Each rule, constraint, or decision appears in exactly one place in the body; Goal, Approach, and Acceptance point at that statement rather than re-wording it, so the sections stay in agreement as the task evolves.
- **Decide or label.** On any open decision a task carries — an unresolved fork, a vague pointer, an either/or left undecided — first reconcile, else surface. **Reconcile** by settling the decision to the single path that best fits the task's spirit, drawn from an ordered evidence base: (a) the task's own stated intent across its Goal, Approach, Acceptance, and description; (b) the project's guardrail docs where present, consulted through `<standing_doc_consumption>`, with `CHARTER.md` a hard boundary and the softer docs subordinate; (c) related and older tasks, both linked live siblings and archived precedent; (d) the already-implemented codebase. Adopt the reconciled path when the evidence settles it — the fitting path is determinable from that evidence without introducing a change the context cannot settle — with a stage that can write recording the resolution and a read-only stage recommending it. **Surface** when the evidence leaves the path underdetermined, so adopting one would risk an unintended change not derivable from context alone: hand the decision to the user with its options and at least one suggested path with rationale, rather than choosing arbitrarily. At authoring time this surface is one labeled "Open decision:" that lists the options and names the default an implementer takes without further input, and one labeled open decision is the authoring ceiling because every other fork was reconciled from the material available while writing. Each stage that meets an open decision applies this one procedure at its own point in the lifecycle.
- **Illustrate.** The general statement carries each rule or requirement; specific cases, incident histories, and dated references stay brief illustrations supporting it. A body whose meaning lives only in an example has its altitude inverted.
- **Redact by generalizing.** Keep user-specific and sensitive detail out by default: generalize rather than embedding absolute or home filesystem paths, secrets and credentials, personally identifiable data, and incidental product, project, tool, or person names. Repo-specific detail enters only when the user explicitly asks for it or the work genuinely needs it, and the body surfaces that choice rather than adding it silently.
- **Compact only to the implementable floor.** Write compactly while a one-shot implementer can still act without re-deriving dropped detail. Stop compression when it would stack clauses until the logic between them is lost, name an edit site without the shape of the change, or give a rule without the one example that fixes its meaning. Test the floor with this question: would this file, plus the project, let an implementer produce the intended change without filling a gap from outside?
- **Rewrite in place, don't append.** When a task changes an existing artifact, frame the work as rewriting the affected passage in place to its target form, naming the passage that exists and what it becomes. Default to rewrite or supersede the existing passage so one canonical statement remains. Use a genuine-addition framing where no existing counterpart exists, the surface is append-only by design (a changelog, activity or decision log, or commit message), a comment or design note carries load-bearing evolution, or two similar-looking rules cover genuinely distinct situations and both belong.
- **Declare exclusions as an Out of scope boundary.** Declaring exclusions is optional — a task with nothing to exclude carries no such block. When a task does declare them, they live in one place: a single block inside `## Approach` led by the verbatim label `**Out of scope:**`, one statement per exclusion. Each entry is one of two kinds. A **rejection** stands alone — work this task never does, which the positive, action-oriented authoring rule already lets a task state directly, optionally citing the standing repo rule or `CHARTER.md` boundary that motivates it. A **deferral** names its owner — work recognized but pushed out of this task links the sibling task that owns it per the `<markdown_policy>` cross-link discipline, keeps the implementable detail in that owner, and stays a one-line pointer; the pointer marks ownership, never ordering, and imposes no prerequisite on either side. Scope trimmed from a task at creation, update, or repair lands as a deferral naming its owner or as an explicit rejection, never as a silent drop. Existing tasks converge on this form opportunistically as they pass through update, check, and auto-repair; the convention mandates no migration sweep.

Keep each task scoped to **one** atomic item. Size by cohesion when one change spans many parts of one system: if the work shares one rationale, one edit surface, and one acceptance story, keep it one task even when part count is high. When atomicity and part count pull apart, cohesion decides; the **300-line** ceiling still wins. Split independent items, expandable tangents, and tasks that grow past **300 lines** into siblings before continuing.
</body>

</file_format>

<dependency_signals>
The family's single definition of when one task is a prerequisite of another and how that relationship is read from the backlog. The single-task front ends inherit this block rather than each carrying a copy: `task_select` uses it to sequence candidates during ranking, and `task_implement` uses it to gate a build behind unbuilt prerequisites. The relationships stay inferred from existing task content — no frontmatter dependency field exists.

A **prerequisite** is a live eligible task — frontmatter status `open`, `checked`, or `ready` — that is not yet done and must ship before the task depending on it. A relationship pointing at an `implemented`, `audited`, `finished`, `deferred`, or archived task is already satisfied and imposes no order.

Read the relationship from four signals already present in the task data:

- **Explicit ordering prose** — a task body names the order in words: `depends on`, `blocked by`, `must follow`, `after`, or a companion reference naming another task file.
- **Dependency cross-links** — a task-to-task markdown link that marks a dependency under the `<markdown_policy>` **Link to another task file when the cross-reference carries weight** rule, rather than a relatedness-only "see also".
- **Forward references** — a task names a block, section, rule, symbol, or artefact that another task is the one to create.
- **Shared-surface collisions** — two tasks edit the same file or surface.

A relationship runs in **both directions**. A task is a prerequisite either by its own outbound signal — its body names what it waits on — or by another live task's inbound declaration — another live task's body names a first-ship order over it or forward-references an artefact it creates. Read both directions: a task silent about its own ordering can still be blocked by an inbound note authored in another live task, including one outside a user-applied scope filter.

Split the relationship strength two ways:

- A **hard ordering dependency** sets a required build order. It holds when a task forward-references an artefact another task creates, when explicit prose names the required order, or when a shared-surface collision carries **directional evidence** — one task creates, renames, removes, or rewrites a specific block, symbol, rule, or file state that the other task consumes.
- A **soft companion relationship** carries no required order but is worth surfacing: a coherence or cross-reference tie, or a shared surface without directional evidence.
</dependency_signals>

<readiness_checklist>
The readiness lens for one task file, judged against the self-sufficiency bar `<body>` defines. It lives here as the family's single source: judge a draft against it before writing the file, and judge an existing task against it before handing it to an implementer.

1. **Charter check.** When `CHARTER.md` exists at the project root, validate the task content against its boundaries and invariants. Surface every conflict as a readiness issue, leave the task body unchanged, and keep the task out of `ready` until the conflict is resolved.
2. **Structural check.** Confirm the body opens with a single `# Title` and carries the `## Goal` / `## Context` / `## Approach` / `## Acceptance` sections, with valid frontmatter, per `<body>` and `<file_format>`. A one-shot implementer follows structure literally, so a structural gap is high-severity — run this before the content lens.
3. **Premise check.** Every task body frames current state to target, so verify the described current state against the codebase as it stands now: read the code the task implicates, run the reproducing command when the task names one, and confirm a claimed gap is actually absent rather than already covered. Judge cited details from a written juxtaposition: quote each command, flag, path, and passage the task describes beside the code's actual text, and clear a detail only when the pair matches — a description that drops a flag, renames a path, or paraphrases a directive away is a drifted detail even when the cited anchor exists. Two staleness outcomes exist, and the finding names which one it is. **Invalidated** — the code contradicts the task's reason to exist: the defect already fixed, the capability already present, the need met by a mechanism that shipped since, the target artifact removed, the behaviour misdiagnosed. This is a readiness issue that invalidates the task before any other finding, and it opens a disposition that belongs to the user: closing the task `deferred` through `task_finish` or the `<archive>` workflow is one honest option beside re-scoping the intent or refuting the finding with evidence — a checking or repairing surface presents these options and never applies one itself. **Drifted** — the motivation still holds while described details have moved on: files renamed or relocated, cited passages reworded, part of the work meanwhile shipped. Each drifted detail is an ordinary readiness issue whose repair refreshes the body against the current codebase.
4. **Approach fitness.** Judge the Approach against the code it changes: followed as written, it must deliver the Goal and, when a bug or gap motivates the task, close the described gap completely. Flag an approach that treats a symptom while the named cause stays live, closes only part of the gap, or carries a gap of its own (a missed edit site, an unhandled case, a side effect that breaks adjacent behaviour). Ground the missed-edit-site check in a written enumeration: list the standing directives, invariants, and hard rules in the artifacts the approach touches that interact with the new behaviour, and clear each one against that behaviour — a directive the change would violate, or must amend to stay consistent, is a missed edit site even when every anchor the task names checks out.
5. **Interaction scan.** The code-anchored mirror of the two task-anchored lenses above, standing beside them as its own lens rather than folding into either: instead of starting from what the task describes, start from the task's change and ask what in the codebase now interacts with it that the task never accounts for. The motivating case is a task written before some feature shipped, whose change would now collide with — or be quietly undermined by — code that landed since, with nothing in the task pointing at it. Run a bounded two-step scan keyed on the task's change — derive its interaction surface, then search the repository over that surface — and classify and route each result:
   - **Derive the interaction surface.** Read what the task links and names — its `scope`, the files cited in Context and Approach — and derive the concrete touch-points its change would create, rename, remove, or consume: symbols, function and type names, config keys, rule or tag names, file states, and behaviours.
   - **Search the repository, read the hits, and classify.** Search the repository for references to those touch-points with whatever repository search tools are available, reaching callers, consumers, alternate definitions, tests, and docs the task never linked, and read the hits; for a hard-interaction hit — code that writes or reads the same state, or that the change would break or be broken by — follow one hop to its own references. Classify each result as a **contradiction** — code the task's change would break, or that would break the change — or an **unattended interaction** — shipped behaviour, an invariant, or a feature the task should account for but never mentions.
   - **Hold the scan boundary.** Reach the whole repository through the touch-point search, yet read only the hits it returns plus the one hop for hard-interaction sites — searching the whole repo for the task's touch-points is not reading the whole repo. This is none of a full-repo read, a scan limited to the task's linked files, or a recursive expansion that follows references of references to a fixed point, whose deeper transitive reach is not worth its unbounded cost. Name the search capability generically rather than pinning a specific tool, so the lens stays portable across harnesses.
   - **Route the disposition through Decide or label.** Treat a confirmed finding as a readiness issue, grounded the way this checklist already requires — a written juxtaposition of the interacting code against the task's change — so an unverified suspicion stays a question rather than a numbered issue. Send its disposition through **Decide or label** rather than a parallel one: reconcile the conflict against the found code when that evidence settles the fix, else surface it with its options and at least one suggested path. This lens supplies the detection; **Decide or label** supplies the disposition.
6. **Content lens.** Read the task thoroughly and surface every issue that could derail a correct, complete one-shot implementation:
   - **Scope sizing** — the most compact scope that still delivers a coherent, independently testable unit. Judge cohesion as well as size: shared rationale, shared edit surface, and one acceptance story favor one task; independent items, duplicated rationale, or 300-line risk favor splitting. Flag too-large (multi-pass risk, past the 300-line split) and too-small (coordination overhead, no standalone capability).
   - **Focus** — one atomic item. Flag scope creep that belongs in a sibling task and should be cross-linked rather than folded in.
   - **Complexity** — implementable in a single pass. Flag hidden multi-step or cross-cutting work.
   - **Contradictions** — internal consistency, including behavioural contradictions where one part makes another non-functional; paraphrase drift between sections — what the **State once** rule prevents — is the standard source. The task's own declared boundary is in scope here too: a Goal, Approach, or Acceptance element that requires, delivers, or proves work the task's `**Out of scope:**` block excludes is a contradiction finding, and an entry readable as either a rejection or a deferral — so an implementer cannot tell whether the work is dropped or owned elsewhere — is a finding on the same rank. Route a confirmed boundary finding's disposition through **Decide or label** rather than defining a new one: reconcile against the evidence when it settles which side wins, else surface with options.
   - **Acceptance coverage** — the Acceptance proof set matches the promise set the body makes. Gather the promise set from the whole body: the body's explicit enumerations — validation rules, test cases, handled inputs — and every further commitment the description, Goal, and Approach make, including one carried by a subordinate clause, a parenthetical, or an alternative branch such as a named default or fallback. Pair the promises explicitly: write each promised item beside the Acceptance entry that proves it and give each row a binary verdict — a promise whose row names its proving entry is paired, and a qualified judgement such as weakly, partially, or indirectly paired is an unpaired row. Flag every unpaired item, and judge coverage from that written pairing rather than a prose impression that the sections map cleanly. Keep an unpaired promise a readiness issue even when an implementer following the body would still build the unproven piece — an Acceptance short of the promises defines done short of the work. Trace each proof mechanism the Acceptance names — a fixture, a script, a command, a harness pattern — one level past confirming the referenced pattern exists: establish when it runs and what it can observe, and confirm it can produce the evidence its entry needs; a mechanism that runs at the wrong time or observes the wrong surface leaves its promise unproven, on the same rank as an unpaired promise. Keep this distinct from **Contradictions**, which checks consistency rather than completeness of proof.
   - **Title/description coverage** — the H1 title and frontmatter `description` name the deliverable set the body now carries. Flag either one when its named scope is narrower than the body's deliverables or sections; for example, a title naming two workflow threads over a five-thread body flips the finding on, while a title that covers those five threads flips it off. Fix by widening the stale field in place per **Rewrite in place**. Keep this distinct from **Structural check**, which checks presence, and **Contradictions**, which checks consistency rather than under-coverage.
   - **Ambiguity / under-specification** — missing requirements, unstated assumptions, vague pointers, or over-compressed prose that lead to divergent implementations; an unresolved either/or is a **Decide or label** finding routed through that rule's reconcile-else-surface procedure — when the evidence base reconciles the decision the finding carries the recommended resolution as its fix, and when no evidence settles it the finding carries the labeled decision with its options and at least one suggested path — over-compression is judged against **Compact only to the implementable floor**, and any reference carrying a position claim — a line-number form such as a `:N` path suffix, a bare `line N`, or an `around lines N–M` range, or an ordinal list-position anchor such as "step 6", "item 3", or "the second bullet" — is flagged against the `<markdown_policy>` soft-pointer rule.
   - **Over-specification** — constraints that needlessly narrow an implementation choice the task meant to leave open; a choice meant to stay open is labeled per **Decide or label** rather than silently narrowed.
   - **Restated standing rules** — body passage instructs the implementer with a copy of a rule that the `<body>` corollary says belongs in a standing project instruction; this is a readiness issue, not wording polish, because copied rules drift from their source. Replace the copy with a standing-rule citation, or drop it when the surrounding text carries nothing else. Keep this distinct from **Over-specification**, which narrows an implementation choice, and apply the **Task-specific gates only** acceptance clause for generic project-gate items: a generic gate is a restatement, while a task-specific executable check remains valid.
   - **Negation-framed behaviour** — behaviour defined as "not X" that an implementer must invert to act on; reframe per the body's positive, action-oriented rule, preserving the technical detail and moving rejected-option rationale to its named home.
   - **Sensitive or user-specific detail** — body text embeds identifying or sensitive specifics without an explicit need; point the finding at **Redact by generalizing** rather than restating the rule.
   - **Append-framed artifact edits** — a task changing an existing artifact is framed as "add X" while an affected passage exists; flag it per **Rewrite in place, don't append** unless the rule's genuine-addition carve-outs apply.
</readiness_checklist>

<workflows>

<path_resolution>
The bundled scripts (`discover_tasks.sh`, `init_tasks.sh`, `lint.py`) live in `scripts/` next to this `SKILL.md`. Resolve each script's absolute path by combining the directory of this `SKILL.md` with `scripts/<script-name>` and invoke that absolute path — never a bare `scripts/...`, which resolves against the current working directory (the target project) rather than the skill, and so finds the project's own `scripts/` or nothing. Every agentic IDE that surfaces a skill exposes the file path it loaded the skill from, so the parent directory is always knowable. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed; never conclude the script is absent because of perceived path uncertainty.
</path_resolution>

<verification_economy>
Each linter, test suite, or named check runs to produce evidence about the current state of what it inspects, so run it once per that state rather than once per workflow step. One run's output is evidence for every later step in the same session that faces the identical state, so the family reuses it instead of repeating the run on unchanged inputs. This trims cost and latency while preserving coverage: a re-run skipped on unchanged inputs would surface exactly what the prior run on that same state already surfaced, so the rule keeps every finding available and stays within the project coverage guardrail a `CHARTER.md` sets when present (consulted through `<standing_doc_consumption>`).

Running is the default, and three runs are always sound:

- **First run in a session.** The session holds no prior output for this check, so run it — including a deliberate pre-edit baseline run taken to record the starting state before any change.
- **Post-change re-run.** The tool, or anything the check inspects, changed since the last run whose output is in hand, so run it again to refresh the evidence against the new state.
- **Standing gate at its moment.** A standing repo gate runs at its standing moment regardless of earlier runs; a lint-before-commit rule, for example, fires at commit time even when lint already ran earlier in the session.

Skipping a run is the exception and carries the burden of proof. Skip only when both grounds hold — the prior run's output is visible in the current session, and neither the tool nor anything it inspects has changed since that run — and name the relied-on run when you skip. Run when either ground is uncertain. Skipping a check whose inputs changed, or a standing gate at its moment, stays out of bounds.

Expensive or stochastic surfaces need one more provision. For costly or sampling-noisy checks — LLM evals, long integration runs — repetition on unchanged inputs adds cost and noise rather than assurance, so record the graded result where the project's testing conventions keep it and let a later stage accept that recorded result as evidence when it postdates every artifact under test, re-running only when the record predates an artifact under test or is missing. `TESTING.md`, when present at the project root, names which surfaces count as expensive and where their recorded results live.
</verification_economy>

<discover>
Run the bundled discovery before touching any task file. The script finds the project root (git toplevel first, then project markers like `.git`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `CLAUDE.md`, `AGENTS.md`, `Makefile`; fall back to CWD), prints `<root>/tasks`, and exits 0 if it exists, 1 if not.

```bash
if TASKS=$(scripts/discover_tasks.sh); then
    :                                          # tasks/ already scaffolded
else
    rc=$?
    if [[ $rc -eq 1 ]]; then
        scripts/init_tasks.sh "$TASKS"         # scaffold tasks/ + tasks/archive/
    else
        exit "$rc"
    fi
fi
```

`init_tasks.sh` is idempotent: safe to call again on an existing tasks directory.
</discover>

<create>
Run every step in order:

<gather>
Confirm the user's intent and gather enough material — current state, target behaviour, relevant files — to fill the body sections in `<body>`. If context is too thin to write something a single-shot AI coder could implement from, ask one sharp clarifying question before writing.

When `FEATURES.md` and/or `ARCHITECTURE.md` exist at the project root, read them before the prior-art codebase scan: `FEATURES.md` supplies higher-signal existing behaviour, and `ARCHITECTURE.md` supplies design context. When either doc is absent, continue unchanged.

For an incident-shaped request — a failure case, an error, a "when X happens it breaks" — settle the altitude as part of gathering, as a decision rather than a question: decide from the request and the surrounding code whether the task delivers the point-fix for the reported case or the general behaviour whose absence caused it, and default to the point-fix when the evidence supports nothing more. Record the choice as an explicit clause in the task's `## Goal` — the point-fix for the named case, or the behaviour definition with the incident as its motivating case — and surface it among the assumptions the create report names, so the user's reply is the correction point.

Generalize from the motivating instance when a concrete episode is mined to improve a reusable artifact: for example, a working session with a skill that exposed a rough edge yields a task to improve that skill. The altitude is the general rule the episode argues for, not the point-fix, and the originating episode rides along only as the brief illustration the `<body>` **Illustrate** rule provides.

When a user-specific or sensitive specific might be necessary and it is unclear whether to include it, ask the user for the level of detail rather than silently including or dropping it.
</gather>

<prior_art>
Before naming and writing, confirm the request is not already captured or already built — a two-tier gate that stays cheap until there is a reason to dig.

**Tier 1 — fast scan, always.** Derive a few distinctive terms from the task's intent and `rg` them across both `tasks/` and `tasks/archive/` (the `<query>` search). This is a quick keyword pass over every existing task file, open and closed.

- **No hits** → the request is novel as far as the backlog records; continue to `<scope>`. Stop here; do not escalate.
- **One or more hits** → escalate to Tier 2, scoped to the matched material.

**Tier 2 — in-depth analysis, only when Tier 1 hits.** Investigate whether the requested work is genuinely new, partly done, or fully done. Read each matched task file in full, and inspect the project itself — the code, modules, and docs the request would touch — to judge the real implementation state rather than trusting a task's stated status. Classify the request as one of:

- **Novel** — the hits were incidental keyword overlap; nothing actually covers this work. Continue to `<scope>`.
- **Already an open task** — an open task in `tasks/` already captures this work.
- **Partially covered** — some of the requested work already exists (in a live task, in an archived `finished`/`deferred` task, or already in the codebase) and some is genuinely new. When a hit lands on archived `finished` work or code already in place, re-derive the genuinely-new delta before recommending any file write: identify what is redundant, what extends shipped work, and what remains unrelated and new.
- **Already implemented** — the codebase or archived `finished` work already covers the full request.
- **Already deferred** — an archived `deferred` task already weighed this and parked it.

**Surface, never auto-resolve.** Report the classification with concrete evidence — the matched file paths and the specific code that already covers the work — then surface the overlap and proposed split before asking the user how to proceed: create as new anyway, fold the fitting delta into an open task, file a follow-up that extends and cross-links the shipped `finished` task, narrow this task to only the genuinely-new remainder, reopen the deferred task, or skip creation when overlap is total. Write a file only after the user's call. When they choose to proceed anyway, cross-link the related task(s) in `## Context`.
</prior_art>

<scope>
Pick the `<scope>` from the project's existing groupings — skill family, sub-project, module, feature area, service. Reuse a scope already present in the directory whenever it fits; introduce a new one only when no existing scope applies.
</scope>

<name>
Pick a `<name>` that is compact, descriptive, and unique within `tasks/` *and* `tasks/archive/`. List both directories before writing so the new filename collides with nothing.
</name>

<write>
Create `<tasks>/<scope>_<name>.md` with the frontmatter from `<frontmatter>` (status: `open`, `reported-by` resolved via `<user_name_chain>`, created/updated set to now) and a body that opens with `# Title` and fills the sections in `<body>`.
</write>

<lint_after_create>
Run `python3 scripts/lint.py --quiet` and fix every blocking finding before declaring the task created.
</lint_after_create>

<batch_creation>
When the user hands over multiple tasks in one go, write each as its own atomic file. Pause and split when any single task threatens to exceed 300 lines, or when several items overlap but each is independently expandable.
</batch_creation>

<lossless_conversion>
Whenever a task is **derived from source material**, hold a lossless-conversion contract — and run it on your own, without the user asking. A *source* is any pre-existing body of meaning being mined into tasks: an AI chat session, a pasted note, a `todo.md`, a spec, a PDF, a meeting transcript, a file on disk. The trigger is the presence of a source being mined — never its medium, and never how many tasks result. Producing a single task does not skip the check: one source can carry far more than one task's worth of meaning, so the lone task must still capture all of what's relevant. Source volume scales only how much the coverage pass has to walk, never whether it runs.

- **Every relevant unit of meaning in the source maps to at least one task.** Rewriting, merging, expanding, or restructuring source content is welcome; dropping relevant meaning is not. Where one task results, it carries all of what's relevant; where many do, the meaning spreads across them with nothing left behind. In the artifact-improvement case named in `<gather>`, the relevant unit is the general lesson; the episode's specifics become illustration rather than content to retain verbatim.
- **Source-wide content propagates into each task it governs.** Content that scopes the *whole* source rather than one section — a shared preamble, a global caveat — carries into every derived task it governs rather than staying behind in the source.
- **Run a coverage pass before declaring done.** Walk the source unit by unit — section, bullet, rule, turn — and confirm each is represented in a task. Report the rewrites, merges, and intentional expansions explicitly, and surface anything not yet covered for the user to decide. A thin direct request resolves in one glance; a rich source takes a real walk-through.
- **Leave the source's disposition to the user.** For a shared asset or an on-disk source, never delete, move, overwrite, or truncate it on the skill's own initiative — confirm coverage first, then *propose* what could become of the source and wait for the user's explicit say-so. For an ephemeral source (a live chat session, a paste) there is nothing on disk to dispose of, so disposition here means simply withholding "done" until coverage is clean. Either way: confirm coverage first, then hand the keep/drop decision to the user.
</lossless_conversion>

</create>

<query>
List with `ls "$TASKS"` for open tasks, `ls "$TASKS/archive"` for closed. Filter by scope with `ls "$TASKS"/<scope>_*.md`. For content searches use `rg "<term>" "$TASKS"`. When summarising for the user, lead with open tasks grouped by scope; only surface archive entries when the user asked about closed work.
</query>

<update>
Edit the body or frontmatter as needed, then bump `updated` to the current datetime in the same edit. Re-run `python3 scripts/lint.py --quiet` after the edit. When an update materially changes the scope or adds expandable new work, split into a follow-up task rather than letting the file grow past 300 lines.

**Applying check findings** is a first-class update flow: when the user replies with issue numbers and per-number decisions — accept, reject, or modify — apply each accepted finding's minimum fix to the task file, leave each rejected finding's passage as it is, and fold a user-modified instruction in over the report's suggestion. Numbers index the most recent `task_check` report in the conversation; when no report is in context, ask for the issue list instead of guessing. When the user declares the task ready over remaining findings, stamp `status: ready`. The whole round is one update: bump `updated` once in the same edit round and re-run the linter once at the end.
</update>

<archive>
When a task is finished or being dropped, run all six steps:

1. Set `status` in the frontmatter to `finished` (work is done and shipped) or `deferred` (parked, not pursued for now).
2. Bump `updated` to the current datetime.
3. Move the file from `<tasks>/` to `<tasks>/archive/` with `git mv` (or plain `mv` if the project is not a git repo). The filename does not change.
4. Update cross-references. Re-point every relative link inside the moved task so it still resolves from the file's new home under `archive/`, covering all three outbound classes: a live sibling still at `<tasks>/` (`foo.md` becomes `../foo.md`), an already-archived sibling (`archive/foo.md` becomes `foo.md`), and a target outside the tasks tree, now one `../` deeper (`../plugins/…` becomes `../../plugins/…`). Then scan the whole tasks tree — `tasks/` and `tasks/archive/` alike (e.g. `rg` the moving filename across both) — for inbound links to the moving file, and rewrite every hit to either point at the archived location or convert to plain text plus `(archived)` when the link is no longer load-bearing.
5. When closing as `finished`, `ARCHITECTURE.md` exists at the project root, and the completed work extended the system's design, update `ARCHITECTURE.md` in the same archive pass. When the doc is absent or the task did not change the design, continue unchanged.
6. Run `python3 scripts/lint.py --include-archive --quiet` so the just-moved file is checked in its new location, and resolve every blocking finding for that file before declaring the archive complete; findings in other archived files are pre-existing context for `task_fix` rather than blockers of this close-out.
</archive>

<lint>
The linter checks naming, frontmatter completeness, provenance, status validity, datetime format, status/location consistency, page size (>300 lines), and filename collisions across live + archive. By default it iterates live files in `tasks/*.md`, while still resolving links into `archive/` and checking filename collisions across both roots. `--include-archive` is dual-use. `task_fix` is the archive-maintenance owner: it passes the flag to extend the per-file checks across the whole archive, surface legacy provenance retrofit hints, and migrate non-terminal archived statuses to `finished`. The `<archive>` close-out passes the same flag for a narrower purpose — to verify the single file it just moved, resolving that file's findings and leaving the rest of the archive to `task_fix`.

```bash
python3 scripts/lint.py              # auto-discover via discover_tasks.sh
python3 scripts/lint.py /custom/path # explicit tasks directory
python3 scripts/lint.py --quiet      # blocking + warn only
python3 scripts/lint.py --include-archive  # archive-inclusive: task_fix maintenance + close-out verify
```

Findings come in three buckets:

- **blocking** — bad filename, missing/malformed frontmatter, missing required provenance, invalid status, status/location mismatch, duplicate filenames, legacy archived status migration. Exit 1; must fix.
- **warn** — non-ISO datetimes, overlong description, missing H1 title, oversized page (>300 lines), line-number position claims in an open task body (the soft-pointer rule; fenced code blocks are skipped, inline code stays checked). The soft-pointer check is recall-biased and names candidates including `path:N`, `path ~N`, capitalized or lowercase `line N` / `line ~N` / `around lines N-M`, and parenthesized `(~N)` / `(~N-M)` shapes, while skipping size extents such as `~16 KB`, `512 bytes`, and `100 MB`. Treat each soft-pointer warn as a candidate, not a verdict: read the hit in surrounding context, rewrite a genuine line anchor to a verbatim greppable label, and leave a false positive such as a size, version, count, or quoted claim-shape untouched.
- **info** — reserved for future style nits.

The **mechanically fixable lint finding set** is the authoritative type list for task-family siblings that auto-repair linter output. Apply only the entries whose target is determinable in the current scope, and surface the rest:

- **Frontmatter and lifecycle mechanics** — fill missing or malformed required frontmatter when the value is named by the linter, derivable from git history, derivable from `<user_name_chain>`, or already present in the task context; normalise an unambiguous non-ISO `created` or `updated` value; repair status/location mismatches and archived non-terminal statuses through the lifecycle workflow that owns that move.
- **Description budget** — rewrite an over-budget `description` into one compact canonical line within the linter budget while preserving the named scope, important nouns, and user-visible deliverable; remove the stale over-budget wording rather than appending a second summary.
- **Local markdown links** — re-point a broken relative markdown link when the correct target is determinable from the link text, filename, task title, or existing repository path; surface a broken link when more than one plausible target exists or no target can be found.
- **Standard-markdown conversion** — convert a linter-blocked wikilink or footnote to standard markdown when the linked target or attribution target is determinable; surface it when the conversion target is unclear.
- **Soft-pointer cleanup** — triage each soft-pointer warning as the warning rule above requires, replace a confirmed line-number position claim with a verbatim greppable label, and leave false positives such as sizes, versions, counts, or quoted claim-shapes untouched.

Mechanical lint repair preserves task intent and file semantics. It bumps `updated` once for a content-changing edit group, leaves `updated` unchanged when it makes no change, and reports every surfaced judgement call with the linter category and reason.
</lint>

</workflows>

<pitfalls>

<one_task_per_file>
**One task per file.** Atomic scope. When new material is expandable but tangential, file a sibling task and cross-link rather than folding it in.
</one_task_per_file>

<split_at_300>
**Split at 300 lines.** Below this ceiling, apply the scope-sizing rule in `<body>` before slicing by part count. Past the ceiling, the task has stopped being a single implementable unit. Slice it into siblings that each carry full context.
</split_at_300>

<status_matches_location>
**Status matches location.** `open`, `checked`, `ready`, `implemented`, and `audited` live in `tasks/`; `finished` and `deferred` live in `tasks/archive/`. The linter blocks on a terminal status under `tasks/`; archive-inclusive maintenance migrates a non-terminal archived status to `finished`.
</status_matches_location>

<bump_updated>
**Bump `updated` on every change.** Body edit, frontmatter edit, status change, archive move — all bump `updated` to the current datetime. Legacy provenance backfill and legacy status migration leave `updated` unchanged when they are the only edits in the file; when the same pass also makes a content fix, bump `updated` for that content fix and let the legacy backfill ride along.
</bump_updated>

<single_shot_ready>
**Write for a single-shot implementer.** The task file carries everything the work needs that the project itself does not already hold; everything available at implementation time — codebase, the standing-instruction baseline named in the standing-doc consumption section, the user — stays in play. A body that leans on its birth conversation fails this bar: that conversation is the one context certain to be gone.
</single_shot_ready>

<not_a_wiki>
**Tasks are not wiki pages.** Upcoming work goes here; durable subject knowledge goes in the `wiki` skill. If a task taught a lasting lesson, capture that lesson separately in the wiki when archiving.
</not_a_wiki>

</pitfalls>

<family>
This base `task` skill is the hub of a `task_*` family and can do all of the backlog work itself. Focused front ends each cover one slice and hand off along a chain:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_auto_check` — autonomously repair one task until `task_check` reports ready
- `task_explain` — explain one task at a high level (read-only)
- `task_select` — choose and rank the next eligible task/action (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_fix` — audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The family layers as a graduated drift-prevention spectrum: the plain manual chain follows the harness-loaded standing-instruction baseline and adds no autonomous hard gate; `task_auto_check` adds the optional readiness loop; autonomous writers, including future implementer and shaper surfaces, carry the hard `CHARTER.md` guardrail; and softer standing docs inform work through the verified test-discipline rule, the descriptive `ARCHITECTURE.md`, and the `FEATURES.md` ledger. `ARCHITECTURE.md` describes goals, stack, and design decisions; it is distinct from the charter's falsifiable boundary role and from any status-board, stage-index, or build-order view. The default manual chain is create → check → select → implement → audit → finish, with `task_auto_check` as an opt-in readiness repair loop and fix maintaining the tree.
</family>

</task_skill>
