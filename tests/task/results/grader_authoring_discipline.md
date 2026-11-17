# Grader-authoring discipline — task-family Cursor eval summary

Vendor: `cursor` (`agent -p`, model `auto`).
Run label: `run-20261004-222734`.
Command: `python3 tests/task/evals/run.py --vendor cursor`.
Overall: **18/43** evals fully green; **291** behaviours passed, **25** behaviours failed.

Per-eval per-behaviour results from each eval's `grading.txt`.
Every still-failing behaviour keeps its reason rather than dropping
from the set. Concurrent edits under the host `tasks/` tree during
this run caused many isolation checks to fail; those are recorded
below as failed behaviours with that reason.

## `create`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: exactly one task file created under tasks/ (got 1)
- PASS: nothing written under archive/ (create does not archive)
- PASS: the new task lints clean
- PASS: status is open
- PASS: reported-by is populated
- PASS: created == updated (both stamped once)
- PASS: created is the real wall clock, not fabricated
- PASS: description fits the ~180-char budget (<=200)
- PASS: acceptance has no generic project-gate items

(eval-create: 9 pass, 1 fail)

## `check`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: status stamped checked for a not-ready verdict

(eval-check: 1 pass, 1 fail)

## `standing_rules_create`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: fixture has CLAUDE.md and AGENTS.md
- PASS: fixture has no family guardrail docs
- PASS: source note left untouched
- PASS: exactly one task file created under tasks/
- PASS: created task lints clean
- PASS: created task does not copy the standing rule verbatim
- PASS: created task cites the standing/repo rule(s)

(eval-standing_rules_create: 8 pass, 0 fail)

## `standing_rules_check`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: status stamped checked for the restated-rule finding
- PASS: task_check preserved body content while reporting

(eval-standing_rules_check: 2 pass, 1 fail)

## `standing_rules_check_control`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: status stamped ready for the cited-rule control
- PASS: control task cites the standing/repo rules
- PASS: control task does not copy the standing rule

(eval-standing_rules_check_control: 3 pass, 1 fail)

## `explain`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: read-only: the sandbox git tree is unchanged
- PASS: fixture archived task remains in archive/
- PASS: fixture archived task keeps status finished

(eval-explain: 3 pass, 1 fail)

## `select`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: read-only: the sandbox git tree is unchanged

(eval-select: 1 pass, 1 fail)

## `implement`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: calc.add implemented (no NotImplementedError left)
- PASS: a test_*.py was written under tests/
- PASS: the test suite passes (unittest discover, exit 0)
- PASS: task is stamped implemented with implemented-by
- PASS: task was not moved to archive/

(eval-implement: 6 pass, 0 fail)

## `implement_dep_gate`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: gate stopped: sandbox git tree unchanged (no code edit)
- PASS: task A left status ready (gate made no status change)
- PASS: task A has no implemented-by stamp
- PASS: prerequisite task B still present and open
- PASS: render.py hardcoded COLORS map left intact (not wired)

(eval-implement_dep_gate: 5 pass, 1 fail)

## `select_inbound_dep`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: read-only: the sandbox git tree is unchanged

(eval-select_inbound_dep: 2 pass, 0 fail)

## `select_dep_regression`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: read-only: the sandbox git tree is unchanged

(eval-select_dep_regression: 1 pass, 1 fail)

## `audit_gaps`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: read-only: the sandbox git tree is unchanged
- PASS: no test file was added (audit reports, it does not fix)

(eval-audit_gaps: 3 pass, 0 fail)

## `audit_clean`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: status stamped audited after clean verdict
- PASS: fixture sanity: the suite genuinely passes

(eval-audit_clean: 3 pass, 0 fail)

## `finish`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: target moved to archive/ (gone from tasks root)
- PASS: archived task status is finished
- PASS: updated is a valid ISO timestamp
- PASS: git tracks the move (git mv, not a fresh write)
- PASS: open-sibling inbound link re-pointed to archive/
- PASS: archived-task inbound link re-pointed (../ dropped)
- PASS: backlog lints clean after close-out

(eval-finish: 8 pass, 0 fail)

## `fix`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: blocking findings driven to zero in archive mode
- PASS: legacy archived status migrated to finished
- PASS: non-ISO created datetime normalised to ISO
- PASS: bare line-number reference re-anchored to a label
- PASS: oversized page left intact (split is a judgement call)
- PASS: no coherence repair was written on an unaccepted run

(eval-fix: 6 pass, 1 fail)

## `query`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: read-only: the sandbox git tree is unchanged

(eval-query: 1 pass, 1 fail)

## `update`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: target task still present in tasks/ root
- PASS: task not archived (update is an edit, not close-out)
- PASS: status stays open
- PASS: created preserved (update bumps updated, not created)
- PASS: description was edited (differs from the seed)
- PASS: updated bumped to the real wall clock
- PASS: tracked file shows a modification (not a fresh write)
- PASS: backlog lints clean after the edit

(eval-update: 9 pass, 0 fail)

## `update_contract`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: target task still present at tasks/auth_token-rotation.md
- PASS: task not archived (update is an edit, not close-out)
- PASS: archive/ still holds no task (no lifecycle move made)
- PASS: status stays open
- PASS: created preserved (update bumps updated, not created)
- PASS: updated bumped to the real wall clock
- PASS: the 24-hour rotation window is recorded on disk
- PASS: the 1-hour overlap decision is recorded on disk
- PASS: both TBD placeholders superseded (rewritten in place)
- PASS: sibling auth_session-timeout.md byte-identical to seed
- PASS: exactly one file changed, and it is tasks/auth_token-rotation.md
- PASS: backlog lints clean after the edit

(eval-update_contract: 13 pass, 0 fail)

## `triage`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: target task still present in tasks/ root
- PASS: task not archived (apply round is an edit, not close-out)
- PASS: status stays open
- PASS: accepted finding 1 applied (429 in, 'works properly' out)
- PASS: rejected finding 2 untouched (Goal byte-identical)
- PASS: modified finding 3 follows the user (docs/api.md, not server.py)
- PASS: created preserved (round bumps updated, not created)
- PASS: updated bumped once to the real wall clock
- PASS: tracked file shows a modification (not a fresh write)
- PASS: backlog lints clean after the round

(eval-triage: 11 pass, 0 fail)

## `lossless_split`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: source doc left untouched (disposition is the user's call)
- PASS: several tasks derived from the multi-section source (>=2)
- PASS: section 'connection pooling' covered (pgbouncer)
- PASS: section 'read replicas' covered (replica)
- PASS: section 'backup cadence' covered (WAL / point-in-time)
- PASS: shared preamble propagated into EVERY derived task (canary)
- PASS: derived tasks lint clean

(eval-lossless_split: 7 pass, 1 fail)

## `lossless_single`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: source note left untouched (disposition is the user's call)
- PASS: exactly one task derived (the content collapses to one)
- PASS: repro detail preserved (race condition)
- PASS: culprit preserved (SessionCache)
- PASS: backward-compatibility constraint preserved
- PASS: the derived task lints clean

(eval-lossless_single: 7 pass, 0 fail)

## `check_boundary_contradiction`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: status stamped checked for the boundary contradiction
- PASS: read-only stamp: the **Out of scope:** block is preserved
- PASS: read-only stamp: the conflicting --yaml acceptance is preserved

(eval-check_boundary_contradiction: 3 pass, 1 fail)

## `check_boundary_clean`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: control fixture carries no **Out of scope:** block
- PASS: the checked task file is still present
- PASS: task_check ran (status stamped off open to checked/ready, so a no-op cannot pass this control)

(eval-check_boundary_clean: 3 pass, 1 fail)

## `implement_boundary_cross`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: backstop held: sandbox git tree unchanged (no crossing edit)
- PASS: task left status ready (backstop made no status change)
- PASS: task has no implemented-by stamp
- PASS: src/theme.py left byte-for-byte unchanged (boundary honored)
- PASS: src/report.py left unchanged (work held before crossing)

(eval-implement_boundary_cross: 6 pass, 0 fail)

## `implement_boundary_agree`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: no boundary interruption: calc.add is implemented (returns a+b)
- PASS: the deferred calc.sub was correctly skipped (stub intact)
- PASS: a test_*.py was written under tests/
- PASS: the test suite passes (unittest discover, exit 0)
- PASS: add task stamped implemented with implemented-by
- PASS: add task was not archived
- PASS: deferred owner task (calc_subtract-function.md) still open

(eval-implement_boundary_agree: 7 pass, 1 fail)

## `create_scope_trim`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: exactly one task file created under tasks/ (got 1)
- PASS: nothing written under archive/
- PASS: the new task lints clean (no broken deferral link, valid form)
- PASS: created task carries an **Out of scope:** block
- PASS: trimmed --yaml work landed inside the Out of scope block
- PASS: trimmed --csv work landed inside the Out of scope block

(eval-create_scope_trim: 6 pass, 1 fail)

## `auto_check_boundary`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: the target task file is still present
- PASS: the target task lints clean after the loop
- PASS: status is checked (surfaced stuck) or ready (repaired)

(eval-auto_check_boundary: 3 pass, 1 fail)

## `check_exclusion_requirement`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: status stamped checked for the miscategorized-exclusion finding
- PASS: read-only stamp: the guardrail entry is preserved in the body
- PASS: read-only stamp: the meta not-an-exclusion note is preserved
- PASS: read-only stamp: the body is byte-identical to the seed
- PASS: the task still lints clean

(eval-check_exclusion_requirement: 5 pass, 1 fail)

## `check_exclusion_requirement_control`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: status stamped ready for the genuine-exclusions control
- PASS: control block still holds only work-not-done rejections
- PASS: control fixture carries no meta not-an-exclusion note
- PASS: read-only stamp: the body is byte-identical to the seed
- PASS: the task still lints clean

(eval-check_exclusion_requirement_control: 6 pass, 0 fail)

## `check_exclusion_waiver`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: status stamped checked for the rule-waiving exclusion
- PASS: fixture sanity: the root CLAUDE.md states the lint gate
- PASS: fixture sanity: no CHARTER.md (ordinary standing-rule path)
- PASS: fixture sanity: the gate is satisfiable (Makefile lint target)
- PASS: read-only stamp: the waiving entry is preserved in the body
- PASS: read-only stamp: the body is byte-identical to the seed
- PASS: the task still lints clean

(eval-check_exclusion_waiver: 7 pass, 1 fail)

## `check_exclusion_waiver_control`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: status stamped ready for the carve-out control
- PASS: fixture sanity: the root rule provides the fixtures carve-out
- PASS: fixture sanity: the gate is satisfiable (Makefile lint target)
- PASS: control entry tracking the carve-out is preserved
- PASS: read-only stamp: the body is byte-identical to the seed
- PASS: the task still lints clean

(eval-check_exclusion_waiver_control: 7 pass, 0 fail)

## `check_commit_proof_surface`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: status stamped checked for the commit-proof violation
- PASS: read-only stamp: the body is byte-identical to the seed
- PASS: the task still lints clean

(eval-check_commit_proof_surface: 3 pass, 1 fail)

## `check_commit_proof_surface_control`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: status stamped ready for the tree-proof control
- PASS: read-only stamp: the body is byte-identical to the seed
- PASS: the task still lints clean

(eval-check_commit_proof_surface_control: 3 pass, 1 fail)

## `check_count_stable`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: status stamped checked for the count-stable finding
- PASS: fixture sanity: exactly 3 plugin manifests, so the count is true today
- PASS: fixture sanity: no CHARTER.md (ordinary standing-rule path)
- PASS: read-only stamp: the frozen-count phrase is preserved
- PASS: read-only stamp: the measurement-protocol item is preserved
- PASS: read-only stamp: the body is byte-identical to the seed
- PASS: the task still lints clean

(eval-check_count_stable: 7 pass, 1 fail)

## `finish_arch_extended`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: target moved to archive/ (gone from tasks root)
- PASS: archived task status is finished
- PASS: updated is a valid ISO timestamp
- PASS: git tracks the move (git mv, not a fresh write)
- PASS: design-extended preserved through the move
- PASS: ARCHITECTURE.md was refreshed (differs from seed)
- PASS: backlog lints clean after close-out

(eval-finish_arch_extended: 7 pass, 1 fail)

## `finish_arch_declined`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: target moved to archive/ (gone from tasks root)
- PASS: archived task status is finished
- PASS: updated is a valid ISO timestamp
- PASS: git tracks the move (git mv, not a fresh write)
- PASS: design-extended preserved through the move
- PASS: ARCHITECTURE.md is byte-identical to the seed
- PASS: the sibling task was left in the tasks root
- PASS: backlog lints clean after close-out

(eval-finish_arch_declined: 9 pass, 0 fail)

## `finish_arch_absent`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: target moved to archive/ (gone from tasks root)
- PASS: archived task status is finished
- PASS: updated is a valid ISO timestamp
- PASS: git tracks the move (git mv, not a fresh write)
- PASS: design-extended preserved through the move
- PASS: no ARCHITECTURE.md was created (presence gate held)
- PASS: backlog lints clean after close-out

(eval-finish_arch_absent: 7 pass, 1 fail)

## `fix_coherence`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: the assessment report was written to coherence-report.md
- PASS: assess-only: no tracked file was modified
- PASS: the selected live set covers the whole live tree (17 tasks)
- PASS: (a) the double-owned severity_label edit is an alter finding
- PASS: (a) the report names both owners of that one edit
- PASS: (a) the report names the shared edit as the evidence
- PASS: (b) the stale-anchor task is an alter finding
- PASS: (b) the stale anchor is named as the evidence
- PASS: (c) the re-blocking finding is an alter finding
- PASS: (c) the report ties it to the loop exception it re-blocks
- PASS: (d) the short sweep is an alter finding
- PASS: (d) the un-enumerated check modules are named
- PASS: (e) the opposed posture is an alter finding
- PASS: (e) the report names both sides of the posture split
- PASS: (f) the underdetermined fork keeps both options on the table
- PASS: (f) the fork is surfaced as a decision, not silently settled
- PASS: (f) the dependent sibling is tied to the unsettled fork by name
- PASS: (g) the clean task is ship-as-is
- PASS: (h) the invalidated premise is a defer candidate
- PASS: (h) the shipped JSON renderer is named as the evidence
- PASS: (i) the Goal-altering candidate is surfaced as such
- PASS: (i) that task's ## Goal is untouched
- PASS: (l) the Acceptance-altering candidate is surfaced as such
- PASS: (l) that task's ## Acceptance is untouched
- PASS: (j) the ship order places the registry before its consumer
- PASS: the backlog still lints clean in archive mode

(eval-fix_coherence: 26 pass, 1 fail)

## `fix_coherence_reconcile_escalated`

- FAIL: isolation: no writes to the real repo's tasks/ tree — host `tasks/` gained a file newer than the eval start marker (concurrent host backlog edits during the suite; not a sandbox escape into this eval's own tree)
- PASS: the report was written to coherence-report.md
- PASS: the run reports the escalated writer mode
- PASS: the escalation names auto_shaper_task as the single writer
- PASS: (a) a coordination link ties the two owners together
- PASS: (a) one owner is named and the counterpart verifies or follows in order
- PASS: (b) the stale anchor is gone from the clean-bar note task
- PASS: (b) the refreshed anchor names the shipped helper
- PASS: (b) updated bumped on the edited file
- PASS: (c) the license-finding severity task was repaired
- PASS: (c) the repair records the clean-bar reason or couples the sibling
- PASS: (d) the short sweep is completed by enumeration or by a selector
- PASS: (e) the posture split is reconciled or its reason recorded
- PASS: (f) the unaccepted fork is left unresolved
- PASS: (i) the Goal-altering candidate is not applied
- PASS: (l) the Acceptance-altering candidate is not applied
- PASS: (k) the unaccepted ready task is untouched
- PASS: no task's status was written by the reconcile pass
- PASS: every edited task's ## Goal is byte-identical to its pre-reconcile Goal
- PASS: an archive-inclusive lint run reports zero blocking findings

(eval-fix_coherence_reconcile_escalated: 19 pass, 1 fail)

## `fix_coherence_reconcile_inline_staleness`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: the report was written to coherence-report.md
- PASS: the run reports the inline writer mode
- PASS: no auto_shaper_task escalation ran
- PASS: (b) the stale anchor is refreshed to the shipped helper
- PASS: (b) updated bumped on the anchor-refresh file
- PASS: (k) the additive Out of scope note landed
- PASS: (k) updated bumped on the note file
- PASS: (k) the ready task stays ready after the additive note
- PASS: (k) its ## Goal is byte-identical
- PASS: (l) the Acceptance-altering repair is not applied
- PASS: (l) the report flags that task for re-check
- PASS: (a) the double-owned edit stays unrepaired (rename side)
- PASS: (a) the double-owned edit stays unrepaired (docstring side)
- PASS: (c) the license-finding severity stays unrepaired
- PASS: (d) the short sweep stays unrepaired
- PASS: (e) the path-check posture stays unrepaired
- PASS: (e) the glob-check posture stays unrepaired
- PASS: (f) the fork stays unresolved
- PASS: (i) the Goal-altering candidate is not applied
- PASS: no task's status was written by the reconcile pass
- PASS: every edited task's ## Goal is byte-identical to its pre-reconcile Goal
- PASS: an archive-inclusive lint run reports zero blocking findings

(eval-fix_coherence_reconcile_inline_staleness: 23 pass, 0 fail)

## `fix_coherence_selector_scope`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: the assessment report was written to coherence-report.md
- PASS: assess-only: no tracked file was modified
- PASS: the selected set carries the tool-scope alpha task
- PASS: the selected set carries the tool-scope beta task
- PASS: the selected set carries the tool-scope gamma task
- PASS: the docs-scope delta task is outside the selected set
- PASS: the docs-scope epsilon task is outside the selected set
- PASS: the backlog still lints clean in archive mode

(eval-fix_coherence_selector_scope: 9 pass, 0 fail)

## `fix_coherence_selector_explicit_list`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: the assessment report was written to coherence-report.md
- PASS: assess-only: no tracked file was modified
- PASS: the selected set carries the first named task
- PASS: the selected set carries the second named task
- PASS: the unnamed gamma task is outside the selected set
- PASS: the unnamed delta task is outside the selected set
- PASS: the backlog still lints clean in archive mode

(eval-fix_coherence_selector_explicit_list: 8 pass, 0 fail)

## `fix_coherence_selector_whole_tree`

- PASS: isolation: no writes to the real repo's tasks/ tree
- PASS: the assessment report was written to coherence-report.md
- PASS: the report assesses the live alpha task
- PASS: the report assesses the live beta task
- PASS: the report assesses the live gamma task
- PASS: the archived sibling stays out of the selected live set
- PASS: no live task's ## Goal moved
- PASS: the backlog still lints clean in archive mode

(eval-fix_coherence_selector_whole_tree: 8 pass, 0 fail)
