---
title: Task lifecycle and status rules
created: 2026-10-10
updated: 2026-10-13
type: concept
tags: [skill, frontmatter, repo-structure]
sources: [raw/notes/task-status-rules-owner-statements-2026-10-10.md, raw/notes/task-status-rules-owner-statements-2026-10-13.md]
confidence: high
---

# Task lifecycle and status rules

This page states how the `task_*` family is meant to move a task through its lifecycle, so an agent can hold a skill's instructions, a run's status writes, or an eval's expectations against it and see where they diverge.

## Definition

The task system keeps each unit of upcoming work as one markdown file in `tasks/`, and the file's `status` frontmatter field records how far the work has come. The hub skill `task` owns the file format and the rules, and each sibling skill owns one step of the lifecycle, as [skill family architecture](skill-family-architecture.md) describes.

The task text is a contract. Before implementation the contract may still be shaped, and `task_check`'s readiness verdict covers exactly the text it read. Once the work is built, the text records what was delivered. From then on the text stays as it is and the status moves forward, with one exception: when a re-audit finds gaps in an `audited` task, the task goes back to `implemented` and the gaps are fixed on that same task. The owner's line for completed work is that it is either left alone or was never implemented ([owner statements, 2026-10-10](../raw/notes/task-status-rules-owner-statements-2026-10-10.md)), and gaps a re-audit finds keep the work open rather than spawning new tasks ([owner statements, 2026-10-13](../raw/notes/task-status-rules-owner-statements-2026-10-13.md)).

Each status has one owner, and each stage allows a different kind of edit to the text:

| Status | Meaning | Written by | Text at this stage |
| --- | --- | --- | --- |
| `open` | Captured, not yet checked. | `task_create`, and a split for each file it creates. | May change. |
| `checked` | Checked with blocking findings left, or a `ready` task rewritten substantively. | `task_check`, or the skill or agent that makes the substantive rewrite. | May change. |
| `ready` | Passed the readiness gate. | `task_check`, also when `task_auto_check` drives it, and the user's readiness declaration. | May change, and a substantive rewrite returns the task to `checked`. |
| `implemented` | Built, or re-opened for gaps a re-audit found. | `task_implement`, and `task_audit` when a re-audit of an `audited` task finds gaps. | Frozen, apart from mechanical link and lint fixes. |
| `audited` | Verified against the code. | `task_audit`, on a clean verdict. | Frozen, apart from mechanical link and lint fixes. |
| `finished` | Closed as done and moved to the archive. | `task_finish`. | Frozen, apart from mechanical link rewrites. |
| `deferred` | Parked and moved to the archive. | `task_finish`. | Frozen, apart from mechanical link rewrites. |

## Current state of knowledge

### Before implementation, only a substantive rewrite costs the readiness verdict

A task at `open`, `checked`, or `ready` may be rewritten, and `open` and `checked` keep their status through any rewrite. A `ready` task goes back to `checked` in the same edit when the rewrite changes what the task delivers or how that delivery is checked. The run's report then names the task and what changed. The owner settled the trigger on 2026-10-10 ([owner statements](../raw/notes/task-status-rules-owner-statements-2026-10-10.md)):

- A Goal change always returns the task to `checked`.
- A mechanical change to links never does, whether it re-points a link or turns a link into plain text, and neither does any other mechanical lint fix.
- An added or changed Approach step or Acceptance item returns the task to `checked` when it asks for work or a check that the task did not already require. It keeps `ready` when it only makes an existing requirement explicit, because the owner judges such a change by its size rather than by its kind.
- Rewording that keeps the meaning, a regroup under the repeated-link react protocol, and a clarifying note all keep `ready`.

This trigger replaced one that sent every rewrite outside the linter's mechanical fix set back to `checked`, regroups and additive notes included. The re-check exists to catch a contract that moved after the gate read it. A change that moved nothing would cost a gate run and buy no information, so the trigger looks at what changed rather than at whether any byte did.

Two guards keep the verdict honest. Lowering `ready` to `open` is never the way to signal that a re-check is owed, because it destroys the verdict `task_check` established and leaves no later stage able to tell the demotion from a task that was never checked. And only `task_check`, alone or inside `task_auto_check`, and the user's readiness declaration in the hub's apply-findings flow write `ready`. A file that a split creates starts at `open` whatever its parent carried, because no gate verdict transfers to text the gate never read.

### After implementation, status moves forward, and a re-audit can re-open

The forward moves are `implemented` to `audited` to `finished`, plus a move from any status to `deferred`. The one move back is the re-audit re-open. When a re-audit of an `audited` task finds gaps that `task_implement` should fix, `task_audit` writes `implemented` with its gap verdict, `task_implement` fixes the gaps on the same task, and the implement and audit loop repeats until a clean audit stamps `audited` again. The user may ask for the same move through the hub's update workflow. No skill or agent writes `open`, `checked`, or `ready` over an implemented or later status, or any status over `finished` or `deferred`, and a confirmation opens no other backward move, since an implemented task is never marked `checked`.

A new follow-up task is the exception, because filing one for every gap inflates the backlog ([owner statements, 2026-10-13](../raw/notes/task-status-rules-owner-statements-2026-10-13.md)). It is filed only when the implement and audit loop stalls and keeps repeating the same findings, when a finding is a genuinely different issue with no real overlap with the delivered task, or when the gaps sit in an archived `finished` task, whose status is final. A repair skill or agent that finds something to change in an `implemented` or `audited` body reports the finding and routes it to `task_audit` or to `task_finish`, and it applies only mechanical link and lint fixes. An edit the user explicitly asks for through the hub's update workflow stays the user's call, and it leaves the status where it is.

### Archived status is final, and archiving rewrites only links

`task_finish` runs the hub's archive workflow. That workflow sets `finished` or `deferred`, moves the file into `tasks/archive/`, and repairs links: it re-points the moved file's own links and every inbound link in other tasks, or it turns an inbound link into plain text plus `(archived)`. Those rewrites are mechanical, so they change no task's status, and the close-out's own move is the only status the workflow writes. A `finished` or `deferred` task keeps its status for good, also when a later mechanical rewrite touches its file in the archive.

### The repeated-link warning asks for a reorganization before implementation

The task linter warns when one body links the same local target more than once. The warning says that the task may have grown organically, with what it says about one target spread over several sections, and that those sections may need reorganizing ([owner statements](../raw/notes/task-status-rules-owner-statements-2026-10-10.md)). The answer is a regroup that gathers the material about the target into the section that owns it, so fewer links are the result of the reorganization rather than its aim. Only a task whose text may still change can act on that prompt. So the warning, and the oversized-page warning that shares its gate, belong on `open`, `checked`, and `ready` tasks only.

### How a divergence shows

Each rule above leaves a trace that an agent can look for in a skill, a run, or a test:

- **In a skill's instructions:** a step that writes a status the table does not give that skill, a backward move after implementation other than the re-audit re-open, a confirmation that unlocks any other backward move, a route that sends re-audit gaps in an `audited` task to a new task by default, an archive step that writes any status besides the close-out's own, or a sibling that restates a status rule instead of citing the hub.
- **In a run:** a `ready` task sent to `checked` after only link or lint edits, a `ready` task left at `ready` after its Goal changed, a split file written at any status but `open`, a status moved backward after implementation other than a re-audit re-open, a follow-up task filed for gaps the implement and audit loop could still fix on the same task, a repair applied to an implemented or audited body, or an archived task whose status changed.
- **In a test:** an eval expectation or grader check that asserts the opposite of a rule, such as a regroup that ends at `checked` or a second readiness check after a regroup, or a check that cannot fail when the rule is broken. [Verification surfaces](verification-surfaces.md) covers what makes a grader trustworthy.

## Open questions

None remain from the owner's statements. This page first restated two points in its own words: the size test for an Approach or Acceptance change, and the routing of gaps in audited or archived work to a new follow-up task. The owner confirmed both on 2026-10-10 ([owner statements](../raw/notes/task-status-rules-owner-statements-2026-10-10.md)). On 2026-10-13 the owner revised the routing for `audited` tasks, which a re-audit now re-opens, and kept the follow-up task for stalled loops, unrelated issues, and archived work ([owner statements, 2026-10-13](../raw/notes/task-status-rules-owner-statements-2026-10-13.md)).

## Related concepts

- [Skill family architecture](skill-family-architecture.md) explains why these rules live once in the hub skill and why the siblings cite them.
- [Agent-delegated automation](agent-delegated-automation.md) covers how `task_auto_check` and `task_fix` delegate repairs while only `task_check` writes the readiness stamp.
- [Verification surfaces for a shipped skill](verification-surfaces.md) covers how the evals that pin these rules are built and graded.
- [Deciding where knowledge belongs](../procedures/deciding-where-knowledge-belongs.md) explains why the executable rule sits in the hub skill and its reasoning sits here.

## Derived from

- The hub skill `plugins/ai_dev/skills/task/SKILL.md`, whose status, backward-move, archive, and lint blocks carry these rules as instructions for agents.
