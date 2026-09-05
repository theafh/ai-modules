---
name: task_implement
description: Implement one existing task file end to end. Use when the user asks to build, do, or implement the work described by a task. Edit code and tests, run verification, stamp implemented, and leave audit and finish to sibling skills.
version: 1.0.15
author: Andreas F. Hoffmann
license: MIT
---

# task_implement

<task_implement_skill>

<role>
task_implement takes one task file from the project's `tasks/` backlog and carries it all the way to done: it reads the task, loads the repo's guardrails, builds on the existing codebase, writes the code and the tests, runs the full suite clean, and confirms every `## Acceptance` item holds. It is the "do this task now, properly" counterpart to `task_create` (which only writes the file), turning the single-shot-implementable task body the base skill produces into actual shipped work. It *does the work*; it leaves verification to `task_audit` and close-out to `task_finish`.
</role>

<when_to_activate>
Activate when the user points at one task in `tasks/` and wants it built now:

- "Implement this task" / "implement `<task-file>`."
- "Do task X" / "build the thing described in `<task>`" / "make task Y happen."

Route elsewhere when the user wants to create a task (`task_create` or the base `task` skill), assess a task's readiness *before* building (`task_check`), automatically repair readiness issues before building (`task_auto_check`), choose what to work on next (`task_select`), verify a believed-done task against the codebase (`task_audit`), or close and archive a task (`task_finish`).
</when_to_activate>

<authority>
The `task` skill's `SKILL.md` is the source of truth for the task-file shape; read it and use its `<discover>` step to locate `tasks/` and its `<file_format>` / `<body>` sections to read the task you are implementing. Implement the *work the task describes*. Do not restate task-skill rules here.
</authority>

<path_resolution>
The bundled scripts (`discover_tasks.sh`, `lint.py`) ship in `scripts/` next to the base `task` skill's `SKILL.md`, not next to this one. After reading that base `SKILL.md` (per `<authority>`), resolve each script's absolute path by combining the directory you loaded it from with `scripts/<script-name>` and invoke that absolute path, never a bare `scripts/...`, which resolves against the current working directory (the target project) rather than the skill, and so finds the project's own `scripts/` or nothing. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed.
</path_resolution>

<workflow>
Run in order. The read-only steps run first: make no code edit and no status change before **Read the task end-to-end**, **Check task dependencies before building**, **Load the guardrails**, and **Understand the existing codebase** are complete. The **Check task dependencies before building** gate can stop the workflow before any later step runs. It surfaces the task's live prerequisites and holds for the user's answer, so an explicit go-ahead, or the gate finding no live prerequisites, is what lets the build continue.

1. **Read the task end-to-end.** Understand the desired behaviour, the `## Approach`, the context pointers, and the scope and any Out of scope block. The base skill writes each task to be self-sufficient. The file on its own is enough to implement, and you draw on everything actually available alongside it: the codebase, the project's standing instructions, the user. Treat the file as that contract, and restate your understanding before writing any code.
2. **Check task dependencies before building.** Before loading the guardrails or reading the codebase, apply the base `task` skill's `<dependency_signals>` taxonomy to the task at hand in both directions: the outbound signals in its own body, and the inbound ordering declarations authored in other live eligible tasks that point at it, meaning a live task whose body names a first-ship order over it or forward-references an artefact it creates. Count only the live eligible prerequisites the taxonomy's prerequisite rule defines; this step makes no code edit and no status change while it runs. When the task has one or more hard prerequisites, list them in dependency order (a prerequisite's own live prerequisites named first), give the evidence for each (the signal, and the task file it came from), surface any soft companion relationships alongside without letting them force the stop, ask whether the task at hand should really be built ahead of its prerequisites, and **stop** with no code edit and no status change until the user answers. Surface a dependency cycle plainly rather than looping on it. On the user's explicit go-ahead, continue into the rest of the workflow; when the gate finds no live prerequisites, continue without interrupting the user.
3. **Load the guardrails.** Read the governing `CLAUDE.md` files (repo root, this repo, and the one nearest the work) and hold their conventions as defaults for every edit (pseudo-XML and positive-language authoring, the Make + shell + markdown toolchain, snake_case naming, deployment-agnostic cross-references, and the versioning / plugin-lockstep rules), together with any constraint the task's own `## Approach` states.
4. **Understand the existing codebase, and confirm the work isn't already done.** Read the code and tests already in place around the work, and extend the patterns, conventions, and architecture in use rather than inventing a new shape. Before writing anything, check the current state of the target: whether the artifact already exists, and whether the behaviour (or part of it) is already present. Build on or correct what is there instead of re-implementing it or clobbering it.
5. **Implement in order. `## Approach` is the plan, the codebase is ground truth.** Follow the `## Approach` step by step, building everything in scope and skipping everything the task marks out of scope, and name every artifact after the behaviour it delivers. When delivering the Goal or an `## Acceptance` item would require crossing a declared Out of scope boundary, quote the conflicting passages, apply the base skill's **Decide or label** reconcile-or-surface disposition, and hold. Never silently cross the boundary and never silently under-deliver. Where a step's mechanics conflict with what the repo actually requires, do what the codebase requires and report the deviation rather than following the brief literally. When the task leaves a decision open, apply the base skill's **Decide or label** reconciliation rule against its evidence base (here including the fully real codebase), and when that evidence settles the decision, proceed on the reconciled path and record the rationale in the shipped artifact (a code comment, the `SKILL.md` body, a doc), not only in chat; when the evidence leaves it unsettled, surface the decision to the user with its options and at least one suggested path and hold, rather than making an arbitrary call. When the work lands, assess whether the delivered change extended the system's design using the base `<archive>` trigger test, then record the verdict explicitly as `design-extended: true` or `design-extended: false` in frontmatter, in the same stamp pass as `status: implemented` and `implemented-by`. Write it on every stamp rather than leaving a `false` verdict implicit: the base `<frontmatter>` entry makes an absent field read as `false` so tasks predating the field stay clean, and a stamp that states its verdict shows the assessment happened. Report the assessment either way. This detection-and-recording mandate is independent of the separate docs update step, and it supplies the close-out signal without requiring task_finish to re-derive a code-level judgement. Honor the base skill's `<backward_move_guard>`, stamp `status: implemented`, write `implemented-by` resolved via `<user_name_chain>`, and bump `updated`.
6. **Build the tests.** When `TESTING.md` exists at the project root, read it for project-specific testing details (stack, runner, layout, thresholds) before choosing the test shape. When it is absent, continue with the repo and task context already loaded. Map every `## Acceptance` check that implies a test to a real test, aligning its level, framework, and structure with the repo's testing conventions (for this repo, the `tests/<skill>/` Pattern A layout). Tests are required deliverables. A missing test for a stated acceptance check is a gap, not a pass.
7. **Cross-check, then run the verifications the acceptance names.** Walk every `## Acceptance` item and confirm the implementation covers it; resolve any gap before proceeding. Run every verification the task and repo name (`make lint`, the relevant bundled `lint.py`, the matching `tests/<skill>/script_tests`, and any acceptance-named check such as a deploy dry-run) each once per the base `<verification_economy>` rule, naming the run every "done" conclusion relies on. Fix every failure your change introduces. Report a pre-existing failure that is unrelated to this task as such and keep it out of scope, and report the suite's actual state, naming any part still red rather than implying a clean run.
8. **Update docs and versions.** Update whatever documentation the task names, and apply the repo's one-bump-per-commit version and plugin-lockstep rules for any skill or plugin artifact touched.
</workflow>

<boundary>
task_implement does the work, stamps `implemented` in place, and stops at "work done, suite green." It does not verify by audit and does not archive. Those are separate, single-purpose siblings:

- Codebase verification belongs to `task_audit` (the read-only gate).
- Close-out (`status` → `finished` or `deferred`, bump `updated`, `git mv` to `archive/`, re-point links) belongs to `task_finish`.

Stopping here keeps each sibling single-purpose and keeps the close-out (a checkpoint the user owns) out of an automated build step. On success, report the work as done and recommend the next links in the chain (`task_audit` to verify, then `task_finish` to close); leave running them to the user.
</boundary>

<output_contract>
Report each `## Acceptance` item as met or unmet with concrete evidence: the test that covers it, the command that passed. Make no "done" claim without a passing check, and surface anything unmet or skipped plainly. Close by pointing at `task_audit` as the next step.
</output_contract>

<family>
In the `task_*` family, each sibling does one job, then points to the next; the base `task` skill is the hub that can do all of it:

- `task_create`: write one task file
- `task_check`: readiness gate before building (read-only)
- `task_auto_check`: autonomously repair one task until `task_check` reports ready
- `task_explain`: explain one task at a high level (read-only)
- `task_select`: choose and rank the next eligible task/action (read-only)
- `task_implement`: do the work **(this skill)**
- `task_audit`: verify a believed-done task against the codebase (read-only)
- `task_finish`: close out (set status, bump `updated`, archive)
- `task_fix`: audit and repair the whole tasks tree

These ship together as a family; any sibling may be absent if a deployment excluded it. The default manual chain is create → check → implement → audit → finish, with `task_auto_check` as an opt-in readiness repair loop, `task_select` a read-only chooser for what to work on next, and `task_fix` maintaining the tree.
</family>

</task_implement_skill>
