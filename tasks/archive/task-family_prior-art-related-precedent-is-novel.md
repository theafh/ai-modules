---
description: "Classify a prior-art hit that shares context but covers none of the requested work as Novel, so task_create writes the task instead of stopping to ask, and prove it with a task_create eval."
scope: plugins/ai_dev/skills/task
created: 2026-10-20T11:22:04
updated: 2026-10-22T13:46:44
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Classify related-but-uncovering precedent as Novel in the prior-art gate

## Goal

The base task skill's `<prior_art>` Tier 2 classification gives a clear class to a matched task that shares context with the request but covers none of the requested work, such as one that touched the same module, the same dependency, or a settled pattern the request will reuse. That case classifies as **Novel**: creation continues to `<scope>`, and the precedent is cross-linked in `## Context` where it carries weight. **Partially covered** stays reserved for a request where part of the requested work itself already exists. The user-visible outcome: a genuinely new request no longer stalls at the prior-art gate with a question and no file because an older task happens to sit next to it.

## Context

The gate lives in the `<prior_art>` section of `plugins/ai_dev/skills/task/SKILL.md`, and `task_create` runs it through its **Prior-art gate.** workflow step without restating the classes. Today the **Novel** entry reads "the hits were incidental keyword overlap; nothing actually covers this work", and the **Partially covered** entry reads "some of the requested work already exists". Related precedent fits neither wording: its overlap is real shared context rather than incidental keywords, yet none of the requested work exists. Agents resolve that gap toward **Partially covered** about half the time. The **Surface, never auto-resolve.** paragraph then requires them to ask the user before writing, so creation stops with no file.

The shipped-match routing that [the prior-art delta task](task-family_prior-art-delta-and-cohesion-sizing.md) added (re-derive the genuinely-new delta, then fold, extend with a follow-up, narrow, or skip) governs real partial coverage, and this change leaves it intact. Related precedent is also exactly what the base **Decide or label** rule consumes as its tier (d) evidence, so classifying it as Novel keeps it available for reconciling forks while drafting.

The defect showed up in the `task_create` harness under `tests/task_create/evals/`. The `reconcile-recorded` eval asked for unit tests of two untested helpers in a module whose other function an archived finished task had tested, sharing its import-stubbing approach. Three of five draws on 2026-10-20 and two of three baseline draws against the pre-change skill stopped at the gate with a "Partially covered" ask. [The guardrail-bound fork task](task-family_guardrail-bound-fork-surfacing.md) records those runs in its findings and reshaped that eval's fixture so its archived precedent covers a different module, which means the overlapping-precedent case has no eval of its own. This task restores it as a dedicated eval.

## Approach

Rewrite the **Novel** entry in `<prior_art>` in place so it names both cases that leave the request uncovered: incidental keyword overlap, and related precedent that shares context (module, dependency, or a settled pattern) while covering none of the requested work. For the related-precedent case, the entry directs the author to continue to `<scope>` and to cross-link the precedent in `## Context` when the `<markdown_policy>` cross-link discipline keeps the link. Tighten the **Partially covered** entry so its test reads as part of the requested work itself already existing, which makes the boundary between the two entries one canonical statement. Leave the other classes, the Tier 1 scan, and the **Surface, never auto-resolve.** disposition list unchanged. Rewrite the last sentence of `<output_contract>` in `plugins/ai_dev/skills/task_create/SKILL.md` in place so it applies only when the gate surfaces an overlap class, matching **Prior-art gate.**: today "When the prior-art gate found a match, report the classification and evidence and reflect the user's decision instead of silently creating a duplicate."; after: "When the prior-art gate surfaces an overlap class (already an open task, partially covered, already implemented, or already deferred), report the classification and evidence and reflect the user's decision instead of silently creating a duplicate."

Add one eval to `tests/task_create/evals/evals.json` with id `related-precedent-novel`, a fixture under `tests/task_create/evals/fixtures/related-precedent-novel/`, its checks in `tests/task_create/evals/grade.sh`, and a matching arm in `tests/task_create/evals/stage.sh` that runs that fixture and sets the prompt, keeping the usage and help strings in lockstep with the new id. The fixture stages an archived finished task that covered a sibling function in the same module and settled a pattern the new work reuses. It also gives the sandbox a git identity, so `reported-by` resolves without asking. The prompt requests only the uncovered work. The checks assert that exactly one new task file exists with `status: open` and lints clean, and that the body's `## Context` links the archived precedent. Author the checks under the standing repo rules for grader design. [The grader label-false-fails task](tests_task-create-grader-label-false-fails.md) also edits `tests/task_create/evals/grade.sh`, `stage.sh`, `evals.json`, and the harness READMEs, and [the parallel-evals task](../tests_task-create-parallel-evals.md) keeps `grade.sh` marker checks while its Goal still hardcodes the three Decide-or-label evals; whichever lands second rebases on the landed state, and this task's four-eval inventory rewrite is authoritative so parallel-evals refreshes that three-count Goal when it next lands. Rewrite the inventory and suite-framing prose that still brands the harness as three Decide-or-label / open-decision-only evals—the harness title, table blurb, and `## What the three evals prove` heading/count in `tests/task_create/README.md`; the `task_create` rows in `tests/CLAUDE.md` and `tests/README.md`; the `skill_name` string in `tests/task_create/evals/evals.json`; the title and framing in `tests/task_create/evals/README.md`; and the “open-decision eval(s)” headers in `tests/task_create/evals/stage.sh`, `grade.sh`, and `run.py`—so each names both rule surfaces (**Decide or label** and `<prior_art>` Novel) and the four evals, describing `related-precedent-novel` as the prior-art Novel case.

Add the eval and record its baseline before rewriting `<prior_art>`, because the runner micro-deploys the skill from the working tree and so measures the unchanged gate only until the rewrite lands.

## Acceptance

- The `<prior_art>` **Novel** entry names both uncovered cases (incidental keyword overlap and related precedent covering none of the requested work), classifies related precedent as Novel, directs the author to continue to `<scope>`, and cross-links in `## Context` when the cross-link discipline keeps it. Today the entry names only incidental keyword overlap, and after the rewrite a search of `plugins/ai_dev/skills/` for the old wording "the hits were incidental keyword overlap; nothing actually covers this work" finds no remaining copy.
- The **Partially covered** entry states its test as part of the requested work itself already existing, and a search of `plugins/ai_dev/skills/task/SKILL.md` still finds the wording "re-derive the genuinely-new delta" once and only inside that entry.
- The Approach leave-unchanged boundary holds: a search of `plugins/ai_dev/skills/task/SKILL.md` still finds the Tier 1 lead-in "**Tier 1: fast scan, always.**", the unedited Tier 2 class lead-ins "**Already an open task**", "**Already implemented**", and "**Already deferred**", and the disposition lead-in "**Surface, never auto-resolve.**", each once and only inside `<prior_art>`.
- The last sentence of `<output_contract>` in `plugins/ai_dev/skills/task_create/SKILL.md` states that reporting the classification, evidence, and the user's decision applies when the gate surfaces an overlap class (already an open task, partially covered, already implemented, or already deferred), so a related-precedent Novel path writes the task without waiting for a user decision. Today that sentence applies to any prior-art match, and after the rewrite a search of `plugins/ai_dev/skills/task_create/SKILL.md` for the old wording "When the prior-art gate found a match" finds no remaining copy.
- `tests/task_create/evals/evals.json` carries the `related-precedent-novel` eval with its fixture and grader checks as Approach describes, `tests/task_create/evals/stage.sh` has a `related-precedent-novel` arm that runs that fixture and sets the prompt with usage and help strings updated to match, and the inventory and suite-framing prose in `tests/task_create/README.md` (including its harness title), `tests/CLAUDE.md`, `tests/README.md`, `tests/task_create/evals/evals.json` (`skill_name`), `tests/task_create/evals/README.md`, and the open-decision suite headers in `tests/task_create/evals/stage.sh`, `grade.sh`, and `run.py` names both rule surfaces and the four evals with `related-precedent-novel` as the prior-art Novel case, as Approach describes.
- Three `--no-cache` draws of `related-precedent-novel` against the pre-change skill are recorded as the baseline in a `## Findings` section of this task file, with run directories. When all three pass, the fixture does not reproduce the gate stop, so strengthen the precedent's overlap and re-run the baseline before measuring the change.
- After the change, five consecutive `--no-cache` draws of `related-precedent-novel` on the default vendor pass in five of five, recorded in the same `## Findings` section with run directories and each draw's `response.txt` as evidence. When any draw stops at the gate, leave the measurement incomplete, revise the wording, and re-run a fresh set of five.

## Findings

Vendor for every draw: Cursor (`agent -p`, model `auto`), `--no-cache`.

### Baseline (pre-change skill)

Three consecutive draws against the unchanged `<prior_art>` Novel wording. None of the three passed the full grade: each wrote one open task (so the gate did not stop with a Partially covered ask on these Cursor draws) and failed `Context links the archived related precedent`. Because the three draws did not all pass, the fixture was not strengthened for a missing gate-stop reproduction; the missing Context cross-link was the measured pre-change gap the rewritten Novel entry closes.

| Draw | Run directory | Grade | Evidence |
| --- | --- | --- | --- |
| 1 | `tests/task_create/evals/workspace/run-20261022-110954/` | FAIL (9 pass, 1 fail: Context link) | `related-precedent-novel/response.txt`, `related-precedent-novel/grading.txt` |
| 2 | `tests/task_create/evals/workspace/run-20261022-111149/` | FAIL (9 pass, 1 fail: Context link) | `related-precedent-novel/response.txt`, `related-precedent-novel/grading.txt` |
| 3 | `tests/task_create/evals/workspace/run-20261022-111347/` | FAIL (9 pass, 1 fail: Context link) | `related-precedent-novel/response.txt`, `related-precedent-novel/grading.txt` |

### Post-change (rewritten Novel + Partially covered + task_create output_contract)

Five consecutive `--no-cache` draws accepted from the current-byte audit evidence. Every response classifies the related precedent as Novel, writes the task, and records the Context cross-link; every grade passes all 10 checks. The response artifacts were written from 12:40:23 through 12:46:59, after the skill artifacts' 11:26:15 modification time.

| Draw | Run directory | Grade | Evidence |
| --- | --- | --- | --- |
| 1 | `tests/task_create/evals/workspace/run-20261022-123821/` | PASS (10 pass, 0 fail) | `related-precedent-novel/response.txt`, `related-precedent-novel/grading.txt` |
| 2 | `tests/task_create/evals/workspace/run-20261022-124023/` | PASS (10 pass, 0 fail) | `related-precedent-novel/response.txt`, `related-precedent-novel/grading.txt` |
| 3 | `tests/task_create/evals/workspace/run-20261022-124207/` | PASS (10 pass, 0 fail) | `related-precedent-novel/response.txt`, `related-precedent-novel/grading.txt` |
| 4 | `tests/task_create/evals/workspace/run-20261022-124356/` | PASS (10 pass, 0 fail) | `related-precedent-novel/response.txt`, `related-precedent-novel/grading.txt` |
| 5 | `tests/task_create/evals/workspace/run-20261022-124524/` | PASS (10 pass, 0 fail) | `related-precedent-novel/response.txt`, `related-precedent-novel/grading.txt` |

Versions bumped in this implement pass (lockstep for commit): `task` 1.3.44 → 1.3.45, `task_create` 1.1.10 → 1.1.11, `ai_dev` plugin and both marketplace registrations 1.14.23 → 1.14.24.
