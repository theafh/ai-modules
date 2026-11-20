---
description: "Make auto_gate_task read an admitted file too large for one tool output in pages from its own path, so it never reads the harness's persisted copy and breaks isolation on Claude."
scope: plugins/ai_dev/agents
created: 2026-11-15T15:07:43Z
updated: 2026-11-19T18:02:07Z
status: ready
reported-by: Andreas Hoffmann
---

# Read large admitted files in pages so the gate keeps its isolation contract

## Goal

`auto_gate_task` reads an admitted file that is too large for one tool output in consecutive pages from that file's own path. It never opens the copy the harness persists when a tool output is too large, so a `task_auto_check` run on Claude no longer stops as a helper failure because the gate read the base `task` SKILL.md back from that copy.

## Context

- **What happened.** In Claude's 2026-11-15 run of `immediate_ready_citations_survive`, the first gate call stamped `ready` and recorded `isolation: confirmed`. The refuted-citation re-gate and its isolation replacement then each read the base `task` SKILL.md with `cat`. Claude Code wrote the oversized output to a file under the session's `tool-results/` directory, and the gate read that file back. Both isolation lines name the read, so the loop stopped under its rule that a second out-of-bounds read ends the run as a helper failure.
- **Why the read is out of bounds.** The `<policy>` rule in `auto_gate_task.md` that opens "Judge the task file as it stands" excludes "session and harness state stores" from both searches and reads, and the persisted file sits in the harness's session store. It held only the admitted skill text, but the rule judges where content came from, and `task_auto_check`'s `<gate>` section re-runs any verdict whose isolation line names such a read.
- **Why this file.** The base `task` SKILL.md is about 100 KB, more than one Bash or Read output holds on Claude, so a whole-file read of it always takes the persisted path there. Cursor has no such store, which is why Cursor runs never show the read.
- **The dry-run agent's rule covers the copy, and the loop reads only the gate's isolation line.** `auto_dryrun_task.md`'s `<rule>Commands` counts content from "any store outside the project" as out of bounds, so a Claude dry run that receives the persisted copy names it in its own `isolation:` line. `task_auto_check` hands that return to the gate as an admitted input and inspects the gate's `isolation:` evidence, so the fix stays confined to `auto_gate_task.md`.

[The return-layout task](archive/task-family_gate-verifier-return-layout.md) rewrites the audit sentence of the same gate rule, so whichever task lands second rewrites on top of the other's text.

## Approach

1. In `auto_gate_task.md`, rewrite the "Judge the task file as it stands" rule in place so it says how to read every admitted file: read it in consecutive pages from its own path with `sed -n` line ranges, one page per call, until every line is read in full and the pages together cover the file. Name the harness's persisted copy of a tool output among the harness state stores the rule excludes. Keep the two sentences scenario s15 of `tests/task_auto_check/script_tests/run.sh` pins word for word: "Reach it with an ignore-aware search that also covers hidden paths" and "A filesystem walker that ignores VCS ignore files, such as `grep -r`, `find`, or a plain recursive listing, is a contract violation". Leave every other sentence of the rule as it stands, so the rewrite adds a paged-read clause and the persisted-copy naming while the rule keeps its relay-closure, git-committable-content, admissible-path, outside-a-repository, and out-of-bounds sentences.
2. In scenario s15 of `tests/task_auto_check/script_tests/run.sh`, add `assert_contains` pins for the paged-read sentence including its `sed -n` line ranges and its `until every line is read in full and the pages together cover the file` clause, the persisted-copy exclusion, and the relay-closure sentence fragment `Treat the relay directory as closed to discovery`.
3. Record in the repo wiki, through the `wiki` skill, on `wiki/entities/anthropic-claude-code.md`, that Claude Code writes a tool output too large to show inline to a file under the session's `tool-results/` directory and points the model at that file, dated 2026-11-15. Settle its provenance channel as that page's `## Derived from` section, with a bullet naming the 2026-11-15 row for `immediate_ready_citations_survive` in `tests/task_auto_check/evals/README.md`: that harness record is lineage, not a source the wiki classifies, so the page's `sources:` entries stay as they are.

## Acceptance

1. `auto_gate_task.md` carries the paged-read instruction for every admitted file and names the persisted tool-output copy as an excluded harness state store, and the two s15 sentences and the rule's relay-closure sentence (`Treat the relay directory as closed to discovery`) are unchanged. The paged-read instruction settles its mechanism on `sed -n` line ranges and requires every line read in full, and the s15 pins carry `assert_contains` for both `sed -n` line ranges and `until every line is read in full and the pages together cover the file`, so an instruction that drops either fails `run_all.sh`.
2. `bash tests/task_auto_check/run_all.sh` passes, including the new pins.
3. The paged read exercises a Claude-specific feature, the persisted tool-output store, so `immediate_ready_citations_survive` runs with `--vendor claude`, and no gate return in its relay directory names a read under `tool-results/`. Its verdict may still fail on the absence-citation gap that [the absence-citation task](task-family_gate-absence-citation-form.md) covers, and the run's record in `tests/task_auto_check/evals/README.md` says so.
4. `wiki/entities/anthropic-claude-code.md`'s `## Derived from` section carries the dated 2026-11-15 bullet, the `tests/task_auto_check/evals/README.md` path that bullet names exists on disk, that page's `sources:` still lists `raw/notes/delegation-probes-2026-10-04.md` and `raw/notes/micro-deployed-worker-home-probes-2026-10-08.md`, and the wiki lints clean.
