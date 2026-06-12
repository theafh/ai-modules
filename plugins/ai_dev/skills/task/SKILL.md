---
name: task
description: Manage upcoming work as plain-markdown task files inside the current project — a filesystem-native backlog that lives next to the code. Use when the user asks to create, write, capture, list, query, update, finish, complete, implement, defer, archive, or lint a task or todo; mentions "tasks", "todos", "the task list", "what's left to do"; asks to break work into trackable items; or otherwise wants upcoming work persisted as files alongside the project rather than as conversation state.
version: 1.3.0
author: Andreas F. Hoffmann
license: MIT
---

# task

<task_skill>

<role>
The task skill is the hub and source of truth of the `task_*` family: the **project-local backlog** that manages a project's upcoming work and todos as plain-markdown task files living next to the code. The concept behind the whole system: every task file is written to be **self-sufficient** — the file alone is enough to implement the work from, including in a later session with no memory of the task's creation. That sufficiency is a floor, never a filter: at implementation time the implementer draws on everything actually available — the codebase, the project's standing instructions, the user in the loop.
</role>

<when_to_activate>
Activate this skill when the user:

- Asks to create, write, capture, file, or add a task / todo / backlog item.
- Asks to list, show, find, or query existing tasks.
- Asks to update, edit, refine, or expand a task.
- Says a task is done, finished, implemented, shipped, or completed — move it to archive with status `implemented`.
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
└── tasks/
    ├── <scope>_<name>.md      # open tasks
    ├── <scope>_<name>.md
    └── archive/
        ├── <scope>_<name>.md  # implemented + deferred tasks
        └── <scope>_<name>.md
```

The tree is intentionally two layers — root for open, `archive/` for everything closed. No further nesting. Scope sits in the filename, not in a folder.
</architecture>

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
---
```

Fields:

- `description` — compact one-liner. Compose to roughly 180 characters; the linter warns above 200, and that gap is headroom for a later broadening edit rather than length to write at. The body carries the full context.
- `scope` — either a relative path under the project root pointing at the directory the task targets (unquoted; e.g. `scope: plugins/ai_dev/skills/task`), or a short descriptive label when no single directory fits (quoted; e.g. `scope: "project xyz"`). The linter resolves an unquoted value against the project root and blocks if the path is missing or escapes the root; a quoted value is accepted as text. Paths win when one fits — the filesystem stays the source of truth.
- `created` — ISO 8601 datetime, set once when the task is created.
- `updated` — ISO 8601 datetime, bumped on every edit and on every status change.
- `status` — one of `open`, `implemented`, `deferred`.

Obtain the timestamp by running the shell command below and copy its output verbatim — the model has no clock, so a hand-written time is a guess:

```bash
date +%Y-%m-%dT%H:%M:%S        # local time, e.g. 2026-05-28T19:49:23
```

Both `created` (set once, on a fresh task) and `updated` (bumped on every edit, status change, and archive move) take their value from this command's output. When creating several tasks in one turn, run `date` once and reuse the captured value across the batch rather than re-running it per file.
</frontmatter>

<markdown_policy>
Task bodies are **100% CommonMark-standard markdown**. The YAML frontmatter at the top is the only allowed extension. The linter blocks on non-standard syntax so the tasks tree stays portable to any renderer and the filesystem stays the source of truth:

- **No footnotes.** `[^name]` references and `[^name]: …` definitions are non-standard. Place attribution inline as a normal markdown link next to the claim.
- **No wikilinks.** `[[target]]` is an Obsidian extension. Use `[text](relative-path.md)` for cross-references.
- **Local cross-references are standard markdown links.** Relative `.md` links to other task files (under `tasks/` or `tasks/archive/`) must resolve on disk — the linter blocks broken targets.
- **Link to another task file when the cross-reference carries weight.** Add a link when it marks a **dependency** (this task builds on, extends, or must follow the other), when reading the linked task would **change how this task is implemented** (it defines a rubric, format, or interface this task consumes), or when the **linked file will be co-edited** (a shared region, a coordinated double-edit, or competing mechanisms to reconcile). The settling test: would reading the linked task, or knowing it exists, change how you implement this task or edit this file? Keep the link when yes; leave out a relatedness-only reference — a bare "see also" / "distinct from" / "pairs with", or a reverse-duplicate pointer whose relationship the linked side already states — since reading the target changes nothing about the work.
- **Locate referenced content by a verbatim label — the soft-pointer rule.** Anchor every pointer to an exact, greppable string in the target — a heading, a pseudo-XML tag, a symbol or rule name, or a short quoted phrase — together with the file path, so the reference resolves by search and fails loudly (grep finds nothing) once the target is reworded rather than landing the reader on stale, plausible-looking wrong code. The label carries the whole reference and must be verbatim-greppable: a vague description like "the matchers block" does not qualify. Give extent, when useful, as size — "the ~10-line guard block" — never as position. Keep position claims out: a `:N` suffix on a file path, a bare `line N`, and an `around lines N–M` range each carry a number that rots silently as the file evolves.

Simplicity, single-topic scope, and standard tooling beat every non-standard extension.
</markdown_policy>

<body>
The body starts with a single `# Title` H1 on the first non-blank line, followed by the rest of the task content. Write the body to be **self-sufficient**: the file carries everything the work needs that the project itself does not already hold, while whatever exists at implementation time — the codebase, the project's standing instructions, the user in the loop — stays in play and gets used. Self-sufficiency is what lets a task outlive its origins: the conversation that created it is the one context guaranteed to be gone by then. Corollary: content a standing project instruction already mandates is cited from the task, with the rule's text staying in its source document. Fill these sections:

- **Goal** — what the task delivers and the user-visible outcome.
- **Context** — pointers to the relevant files, modules, prior decisions, related tasks, links.
- **Approach** — the intended implementation path, plus any constraints or non-goals.
- **Acceptance** — the contract of concrete checks that say the task is done (a staged fixture the new behaviour is proven on, a file state to inspect, a measurement to record). Every item honours the contract:
  - **Deliverable items flip.** Each item is false today and flipped true by the work, verifiable mechanically — a command to run, a file state to inspect, a behaviour to observe.
  - **Task-specific gates only.** Every item's outcome changes with this task's work. The project's standing instructions own the generic gates — `make lint`, a deploy dry-run, the full test suite — which run at their standing moments; name a gate only when the task changes what it verifies, such as a new lint rule proven on a staged fixture or a new scenario added to a suite.
  - **Implementer-runnable.** Every item verifies through steps the implementer runs alone; an action the project's standing instructions gate on the user stays out of acceptance.
  - **Measured, with a fail branch.** Stochastic or empirical work names its measurement protocol — run count, fixed denominator, baseline — and the recorded measurement is the deliverable; the item states what happens when the hypothesis fails rather than gating on the hoped-for direction.
  - **Enumerate.** Prefer a list of independently verifiable items over one compound check.

Write the body positive and action-oriented: the primary carrier of every section is what the work does — Goal, Approach, and Acceptance lead with the action taken and what "done" looks like. Negatives earn their place where they carry content of their own: a genuine non-goal, a deferred or explored alternative, a guardrail, the task-specific gate the **Acceptance** contract defines.

Three further rules govern the body's structure:

- **State once.** Each rule, constraint, or decision appears in exactly one place in the body; Goal, Approach, and Acceptance point at that statement rather than re-wording it, so the sections stay in agreement as the task evolves.
- **Decide or label.** Resolve every either/or before the file is written. When one decision genuinely stays open, label it explicitly ("Open decision:"), list the options, and name the default an implementer takes without further input; one labeled open decision is the ceiling.
- **Illustrate.** The general statement carries each rule or requirement; specific cases, incident histories, and dated references stay brief illustrations supporting it. A body whose meaning lives only in an example has its altitude inverted.

Keep each task scoped to **one** atomic item. When you notice scope creep — material that overlaps but is itself expandable — file it as a separate task and cross-link instead of folding it in. When a task grows past **300 lines**, you must split it into multiple tasks before continuing.
</body>

</file_format>

<readiness_checklist>
The readiness lens for one task file, judged against the self-sufficiency bar `<body>` defines. It lives here as the family's single source: judge a draft against it before writing the file, and judge an existing task against it before handing it to an implementer.

1. **Structural check first.** Confirm the body opens with a single `# Title` and carries the `## Goal` / `## Context` / `## Approach` / `## Acceptance` sections, with valid frontmatter, per `<body>` and `<file_format>`. A one-shot implementer follows structure literally, so a structural gap is high-severity — run this before the content lens.
2. **Content lens.** Read the task thoroughly and surface every issue that could derail a correct, complete one-shot implementation:
   - **Scope sizing** — the most compact scope that still delivers a coherent, independently testable unit. Flag too-large (multi-pass risk, past the 300-line split) and too-small (coordination overhead, no standalone capability).
   - **Focus** — one atomic item. Flag scope creep that belongs in a sibling task and should be cross-linked rather than folded in.
   - **Complexity** — implementable in a single pass. Flag hidden multi-step or cross-cutting work.
   - **Contradictions** — internal consistency, including behavioural contradictions where one part makes another non-functional; paraphrase drift between sections — what the **State once** rule prevents — is the standard source.
   - **Ambiguity / under-specification** — missing requirements, unstated assumptions, or vague pointers that lead to divergent implementations; an unresolved either/or is a **Decide or label** finding, and any reference carrying a line-number position claim — a `:N` path suffix, a bare `line N`, an `around lines N–M` range — is flagged against the `<markdown_policy>` soft-pointer rule.
   - **Over-specification** — constraints that needlessly narrow an implementation choice the task meant to leave open; a choice meant to stay open is labeled per **Decide or label** rather than silently narrowed.
   - **Negation-framed behaviour** — behaviour defined as "not X" that an implementer must invert to act on; reframe per the body's positive, action-oriented rule, preserving the technical detail.
</readiness_checklist>

<workflows>

<path_resolution>
The bundled scripts (`discover_tasks.sh`, `init_tasks.sh`, `lint.py`) live in `scripts/` next to this `SKILL.md`. Resolve each script's absolute path by combining the directory of this `SKILL.md` with `scripts/<script-name>` and invoke that absolute path — never a bare `scripts/...`, which resolves against the current working directory (the target project) rather than the skill, and so finds the project's own `scripts/` or nothing. Every agentic IDE that surfaces a skill exposes the file path it loaded the skill from, so the parent directory is always knowable. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed; never conclude the script is absent because of perceived path uncertainty.
</path_resolution>

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

For an incident-shaped request — a failure case, an error, a "when X happens it breaks" — settle the altitude as part of gathering, as a decision rather than a question: decide from the request and the surrounding code whether the task delivers the point-fix for the reported case or the general behaviour whose absence caused it, and default to the point-fix when the evidence supports nothing more. Record the choice as an explicit clause in the task's `## Goal` — the point-fix for the named case, or the behaviour definition with the incident as its motivating case — and surface it among the assumptions the create report names, so the user's reply is the correction point.
</gather>

<prior_art>
Before naming and writing, confirm the request is not already captured or already built — a two-tier gate that stays cheap until there is a reason to dig.

**Tier 1 — fast scan, always.** Derive a few distinctive terms from the task's intent and `rg` them across both `tasks/` and `tasks/archive/` (the `<query>` search). This is a quick keyword pass over every existing task file, open and closed.

- **No hits** → the request is novel as far as the backlog records; continue to `<scope>`. Stop here; do not escalate.
- **One or more hits** → escalate to Tier 2, scoped to the matched material.

**Tier 2 — in-depth analysis, only when Tier 1 hits.** Investigate whether the requested work is genuinely new, partly done, or fully done. Read each matched task file in full, and inspect the project itself — the code, modules, and docs the request would touch — to judge the real implementation state rather than trusting a task's stated status. Classify the request as one of:

- **Novel** — the hits were incidental keyword overlap; nothing actually covers this work. Continue to `<scope>`.
- **Already an open task** — an open task in `tasks/` already captures this work.
- **Partially covered** — some of the requested work already exists (in an open task, in an archived `implemented`/`deferred` task, or already in the codebase) and some is genuinely new.
- **Already implemented** — the codebase already does this, whether or not a task records it.
- **Already deferred** — an archived `deferred` task already weighed this and parked it.

**Surface, never auto-resolve.** Report the classification with concrete evidence — the matched file paths and the specific code that already covers the work — and ask the user how to proceed: create as new anyway, fold the delta into the existing task, narrow this task to only the genuinely-new part, reopen the deferred task, or skip creation. Write a file only after the user's call. When they choose to proceed anyway, cross-link the related task(s) in `## Context`.
</prior_art>

<scope>
Pick the `<scope>` from the project's existing groupings — skill family, sub-project, module, feature area, service. Reuse a scope already present in the directory whenever it fits; introduce a new one only when no existing scope applies.
</scope>

<name>
Pick a `<name>` that is compact, descriptive, and unique within `tasks/` *and* `tasks/archive/`. List both directories before writing so the new filename collides with nothing.
</name>

<write>
Create `<tasks>/<scope>_<name>.md` with the frontmatter from `<frontmatter>` (status: `open`, created/updated set to now) and a body that opens with `# Title` and fills the sections in `<body>`.
</write>

<lint_after_create>
Run `python3 scripts/lint.py --quiet` and fix every blocking finding before declaring the task created.
</lint_after_create>

<batch_creation>
When the user hands over multiple tasks in one go, write each as its own atomic file. Pause and split when any single task threatens to exceed 300 lines, or when several items overlap but each is independently expandable.
</batch_creation>

<lossless_conversion>
Whenever a task is **derived from source material**, hold a lossless-conversion contract — and run it on your own, without the user asking. A *source* is any pre-existing body of meaning being mined into tasks: an AI chat session, a pasted note, a `todo.md`, a spec, a PDF, a meeting transcript, a file on disk. The trigger is the presence of a source being mined — never its medium, and never how many tasks result. Producing a single task does not skip the check: one source can carry far more than one task's worth of meaning, so the lone task must still capture all of what's relevant. Source volume scales only how much the coverage pass has to walk, never whether it runs.

- **Every relevant unit of meaning in the source maps to at least one task.** Rewriting, merging, expanding, or restructuring source content is welcome; dropping relevant meaning is not. Where one task results, it carries all of what's relevant; where many do, the meaning spreads across them with nothing left behind.
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

**Applying check findings** is a first-class update flow: when the user replies with issue numbers and per-number decisions — accept, reject, or modify — apply each accepted finding's minimum fix to the task file, leave each rejected finding's passage as it is, and fold a user-modified instruction in over the report's suggestion. Numbers index the most recent `task_check` report in the conversation; when no report is in context, ask for the issue list instead of guessing. The whole round is one update: bump `updated` once in the same edit round and re-run the linter once at the end.
</update>

<archive>
When a task is finished or being dropped, run all five steps:

1. Set `status` in the frontmatter to `implemented` (work is done and shipped) or `deferred` (parked, not pursued for now).
2. Bump `updated` to the current datetime.
3. Move the file from `<tasks>/` to `<tasks>/archive/` with `git mv` (or plain `mv` if the project is not a git repo). The filename does not change.
4. Update cross-references. Re-point any link inside the moved task that still names a sibling at `<tasks>/` to its new relative path. Then scan the whole tasks tree — `tasks/` and `tasks/archive/` alike (e.g. `rg` the moving filename across both) — for inbound links to the moving file, and rewrite every hit to either point at the archived location or convert to plain text plus `(archived)` when the link is no longer load-bearing.
5. Run `python3 scripts/lint.py --quiet` and resolve every blocking finding before declaring the archive complete.
</archive>

<lint>
The linter checks naming, frontmatter completeness, status validity, datetime format, status/location consistency, page size (>300 lines), and filename collisions across open + archive.

```bash
python3 scripts/lint.py              # auto-discover via discover_tasks.sh
python3 scripts/lint.py /custom/path # explicit tasks directory
python3 scripts/lint.py --quiet      # blocking + warn only
```

Findings come in three buckets:

- **blocking** — bad filename, missing/malformed frontmatter, invalid status, status/location mismatch, duplicate filenames. Exit 1; must fix.
- **warn** — non-ISO datetimes, overlong description, missing H1 title, oversized page (>300 lines), line-number position claims in an open task body (the soft-pointer rule; fenced code blocks are skipped, inline code stays checked).
- **info** — reserved for future style nits.
</lint>

</workflows>

<pitfalls>

<one_task_per_file>
**One task per file.** Atomic scope. When new material is expandable but tangential, file a sibling task and cross-link rather than folding it in.
</one_task_per_file>

<split_at_300>
**Split at 300 lines.** A task longer than that has stopped being a single implementable unit. Slice it into siblings that each carry full context.
</split_at_300>

<status_matches_location>
**Status matches location.** `open` lives in `tasks/`; `implemented` and `deferred` live in `tasks/archive/`. The linter blocks on any mismatch.
</status_matches_location>

<bump_updated>
**Bump `updated` on every change.** Body edit, frontmatter edit, status change, archive move — all bump `updated` to the current datetime.
</bump_updated>

<single_shot_ready>
**Write for a single-shot implementer.** The task file carries everything the work needs that the project itself does not already hold; everything available at implementation time — codebase, standing instructions, the user — stays in play. A body that leans on its birth conversation fails this bar: that conversation is the one context certain to be gone.
</single_shot_ready>

<not_a_wiki>
**Tasks are not wiki pages.** Upcoming work goes here; durable subject knowledge goes in the `wiki` skill. If a task taught a lasting lesson, capture that lesson separately in the wiki when archiving.
</not_a_wiki>

</pitfalls>

<family>
This base `task` skill is the hub of a `task_*` family and can do all of the backlog work itself. Focused front ends each cover one slice and hand off along a chain:

- `task_create` — write one task file
- `task_check` — readiness gate before building (read-only)
- `task_implement` — do the work
- `task_audit` — verify a believed-done task against the codebase (read-only)
- `task_finish` — close out: set status, bump `updated`, archive
- `task_fix` — audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The natural chain is create → check → implement → audit → finish, with fix maintaining the tree.
</family>

</task_skill>
