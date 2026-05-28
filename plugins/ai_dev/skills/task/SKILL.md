---
name: task
description: Manage upcoming work as plain-markdown task files inside the current project — a filesystem-native backlog that lives next to the code. Use when the user asks to create, write, capture, list, query, update, finish, complete, implement, defer, archive, or lint a task or todo; mentions "tasks", "todos", "the task list", "what's left to do"; asks to break work into trackable items; or otherwise wants upcoming work persisted as files alongside the project rather than as conversation state.
version: 1.1.1
author: Andreas F. Hoffmann
license: MIT
---

# task

<task_skill>

<role>
The task skill manages upcoming work and todos for the current project as plain-markdown files under `tasks/` at the project root. Each task is a single self-contained markdown file written so a single-shot AI coder could pick it up and implement it with no further context from chat. Open work lives in `tasks/`; finished and dropped work moves to `tasks/archive/`. This skill is the **project-local backlog** — a filesystem-native task tracker that lives next to the code, complementary to the `wiki` skill (which captures durable knowledge across projects).
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

- `description` — compact one-liner (<=200 chars). The body carries the full context.
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

Simplicity, single-topic scope, and standard tooling beat every non-standard extension.
</markdown_policy>

<body>
The body starts with a single `# Title` H1 on the first non-blank line, followed by the rest of the task content. Write the body so a single-shot AI coder picking up only this file has every piece of context they need to implement the work end to end:

- **Goal** — what the task delivers and the user-visible outcome.
- **Context** — pointers to the relevant files, modules, prior decisions, related tasks, links.
- **Approach** — the intended implementation path, plus any constraints or non-goals.
- **Acceptance** — concrete checks that say the task is done (tests to pass, behaviour to verify, lint to come back clean).

Keep each task scoped to **one** atomic item. When you notice scope creep — material that overlaps but is itself expandable — file it as a separate task and cross-link instead of folding it in. When a task grows past **300 lines**, you must split it into multiple tasks before continuing.
</body>

</file_format>

<workflows>

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
</gather>

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

</create>

<query>
List with `ls "$TASKS"` for open tasks, `ls "$TASKS/archive"` for closed. Filter by scope with `ls "$TASKS"/<scope>_*.md`. For content searches use `rg "<term>" "$TASKS"`. When summarising for the user, lead with open tasks grouped by scope; only surface archive entries when the user asked about closed work.
</query>

<update>
Edit the body or frontmatter as needed, then bump `updated` to the current datetime in the same edit. Re-run `python3 scripts/lint.py --quiet` after the edit. When an update materially changes the scope or adds expandable new work, split into a follow-up task rather than letting the file grow past 300 lines.
</update>

<archive>
When a task is finished or being dropped, run all five steps:

1. Set `status` in the frontmatter to `implemented` (work is done and shipped) or `deferred` (parked, not pursued for now).
2. Bump `updated` to the current datetime.
3. Move the file from `<tasks>/` to `<tasks>/archive/` with `git mv` (or plain `mv` if the project is not a git repo). The filename does not change.
4. Update cross-references. Re-point any link inside the moved task that still names a sibling at `<tasks>/` to its new relative path, and rewrite inbound links from other open tasks to either point at the archived location or convert them to plain text plus `(archived)` when the link is no longer load-bearing.
5. Run `python3 scripts/lint.py --quiet` and resolve every blocking finding before declaring the archive complete.
</archive>

<lint>
The linter checks naming, frontmatter completeness, status validity, datetime format, status/location consistency, page size (>300 lines), filename collisions across open + archive, and — where the filesystem records it — agreement between the `created` date and the file's birth time.

```bash
python3 scripts/lint.py              # auto-discover via discover_tasks.sh
python3 scripts/lint.py /custom/path # explicit tasks directory
python3 scripts/lint.py --quiet      # blocking + warn only
```

Findings come in three buckets:

- **blocking** — bad filename, missing/malformed frontmatter, invalid status, status/location mismatch, duplicate filenames. Exit 1; must fix.
- **warn** — non-ISO datetimes, overlong description, missing H1 title, oversized page (>300 lines), and a `created` timestamp that disagrees with the file's birth time by more than an hour (advisory drift detection — a `git mv`/rename preserves birth time, but a fresh clone/checkout or a copy resets it, and the check stays silent on filesystems that don't record one).
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
**Write for a single-shot implementer.** A task body that needs the original chat to make sense is a task that has not captured enough context.
</single_shot_ready>

<not_a_wiki>
**Tasks are not wiki pages.** Upcoming work goes here; durable subject knowledge goes in the `wiki` skill. If a task taught a lasting lesson, capture that lesson separately in the wiki when archiving.
</not_a_wiki>

</pitfalls>

</task_skill>
