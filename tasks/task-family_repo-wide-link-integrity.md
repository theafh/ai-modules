---
description: Widen the task linter from task-file .md links to every in-repo link from every repo file, ignore anything leaving the repo, and wire the remit into the skills and agents that consume it.
scope: plugins/ai_dev/skills/task
created: 2026-09-12T17:31:37
updated: 2026-09-12T17:31:37
status: open
reported-by: Andreas Hoffmann
---

# Lint every in-repo link from every repo file, and ignore every link that leaves it

## Goal

`lint.py` resolves and reports every markdown link whose target is a file inside
the repository, wherever that link is written and whatever kind of file it
points at. A link that dangles is then caught by the tool that owns link
integrity, rather than surviving until some other linter happens to look or
until a reader follows it. Links that leave the repository stay silent: an
internet URL, a `mailto:`, and a path resolving outside the repo root draw no
finding and no warning, so widening the remit costs no noise. The skills and
agents that consume the linter state the widened remit, so an agent repairing
links knows the whole repo is in scope.

## Context

Two restrictions in `plugins/ai_dev/skills/task/scripts/lint.py` bound what the
linter can see today. Both are visible in `check_local_links` and in the page
walk that feeds it.

**The walk covers task files only.** The linter iterates `tasks/*.md`, extends
to `tasks/archive/` under `--include-archive`, and narrows to one file under
`--file`. A link written in any other repo file is never examined, so a link
*into* the tasks tree is unchecked in the direction that breaks most often: when
`task_finish` moves a file to `tasks/archive/`, every outside pointer to it goes
stale at once.

The worked case that prompted this. In a consuming repo, a wiki page carried
`](../../tasks/elcp-intro_stress-test-epoch-boundaries.md)`. `task_finish`
archived that task and re-pointed the inbound links it could see, which is the
tasks tree alone, exactly as
[task-family_archive-inbound-link-scan](archive/task-family_archive-inbound-link-scan.md)
specified. The wiki link dangled for several commits and surfaced only because
that repo also runs a wiki linter with its own broken-link check. A repo
carrying tasks and no wiki linter would keep the dangling link indefinitely.

**Only `.md` targets are checked.** `check_local_links` skips any target that
does not end `.md`, so a task body pointing at a script, a chapter source, a
data file, or a directory gets no check at all. Renaming or moving such a target
breaks the pointer silently. Task bodies in consuming repos do link these: a
tooling script, a `.tex` chapter, a `.bib` bibliography.

What is already settled and stays. Resolution tries the linking file's own
directory and then the project root, which
[task-family_link-resolution-project-root-fallback](archive/task-family_link-resolution-project-root-fallback.md)
established; `://` and `mailto:` targets are already skipped; `#` fragments and
trailing titles are already stripped before resolving. The repeated-link warn
from
[task-family_cross-link-hygiene](archive/task-family_cross-link-hygiene.md)
keeps its current per-file behaviour.

The artefacts that consume the linter and carry its remit in prose are the base
`task` skill, its nine siblings (`task_audit`, `task_auto_check`,
`task_check`, `task_create`, `task_explain`, `task_finish`, `task_fix`,
`task_implement`, `task_select`), and the four agents under
`plugins/ai_dev/agents/` that invoke it (`auto_gate_task`,
`auto_reviewer_task`, `auto_shaper_task`, `auto_verifier_task`;
`auto_drift_task` is the fifth agent and reads git history rather than the
linter, so it stays out). Bundled-script behaviour is tested by
`tests/task/script_tests/run.sh`, whose `l*` group already covers
`check_local_links` body-link resolution and is the group this work extends.

## Approach

Change the linter first, then the prose that describes it.

**Widen the walk to the repository.** Keep the existing per-file task checks
(frontmatter, naming, status, provenance, datetime, size, collisions) on task
files alone, and run link resolution over every markdown file under the repo
root. Skip what a repo walk must always skip: `.git/`, and any directory the
repo declares uninteresting by the mechanism already used for the page walk.
Report a finding against the file that carries the link, so the report says
where to edit.

**Widen the target filter from `.md` to any in-repo path.** Resolve the target
the same way, and treat existence under either root as the test. A target that
resolves to a directory counts as present.

**Make leaving the repo the silence rule.** A target draws no finding when it
carries `://`, starts with `mailto:`, is empty or fragment-only, or resolves
outside the repo root once normalised, which covers an absolute path elsewhere
on the machine and a relative path climbing past the root. State the rule once
in the function's docstring so the exclusion is readable next to the check.

**Wire the remit into the consumers.** Each artefact named in Context that
describes the linter states that its link check covers every in-repo link from
every repo file and ignores everything outside. Two carry more than a
description: `task_fix` owns tree repair and states that a repair pass fixes
in-repo links wherever they live, and `task_finish` states that archiving
re-points inbound links across the repository rather than across the tasks tree
alone, superseding the tasks-tree-only wording the archived inbound-link-scan
task named in Context put there.

**Cover the behaviour in the script tests.** Extend the `l*` group in
`tests/task/script_tests/run.sh` with the cases Acceptance names, following the
scratch-fixture pattern its neighbours use.

**Out of scope:**

- The wiki linter at
  `plugins/knowledge_management/skills/wiki/scripts/lint.py`, a separate tool
  with its own link check and its own repo walk.
- Whether a resolving link points at the *right* file. This task checks that a
  target exists, not that the prose around it is accurate.
- Liveness of external URLs and DOIs, which stay out by the silence rule above.
- Changing how `scope:` frontmatter resolves, which keeps the behaviour the
  archived project-root-fallback task named in Context settled.

## Acceptance

- A staged fixture where a non-task repo file links a path under `tasks/` that
  does not exist produces one blocking `broken-link` finding naming that
  non-task file, where the current linter reports nothing.
- A staged fixture where a task body links an existing non-`.md` in-repo file
  produces no finding, and one where it links a missing non-`.md` in-repo file
  produces one blocking `broken-link` finding, where the current linter reports
  nothing in both cases.
- A staged fixture carrying an `https://` URL, a `mailto:` target, an absolute
  path outside the repo root, and a relative path climbing above the root
  produces no finding of any severity for those four links.
- A staged fixture where a link resolves to an existing directory produces no
  finding.
- `tests/task/script_tests/run.sh` covers each of the four cases above in its
  `l*` group and passes.
- Running the linter over this repository reports every in-repo dangling link it
  now sees, and that run's output is recorded in the implementation report with
  each finding either fixed or named as pre-existing.
- The base `task` skill, its nine siblings, and the four linter-invoking
  `auto_*_task` agents each state that the link check covers every in-repo link from every repo file
  and ignores every target outside the repo.
- `task_fix` states that a repair pass fixes in-repo links wherever they live,
  and `task_finish` supersedes its tasks-tree-only inbound-link wording with
  repository-wide re-pointing.
