---
description: "Classify a prior-art hit that shares context but covers none of the requested work as Novel, so task_create writes the task instead of stopping to ask, and prove it with a task_create eval."
scope: plugins/ai_dev/skills/task
created: 2026-10-20T11:22:04
updated: 2026-10-20T12:36:00
status: open
reported-by: Andreas Hoffmann
---

# Classify related-but-uncovering precedent as Novel in the prior-art gate

## Goal

The base task skill's `<prior_art>` Tier 2 classification gives a clear class to a matched task that shares context with the request but covers none of the requested work, such as one that touched the same module, the same dependency, or a settled pattern the request will reuse. That case classifies as **Novel**: creation continues to `<scope>`, and the precedent is cross-linked in `## Context` where it carries weight. **Partially covered** stays reserved for a request where part of the requested work itself already exists. The user-visible outcome: a genuinely new request no longer stalls at the prior-art gate with a question and no file because an older task happens to sit next to it.

## Context

The gate lives in the `<prior_art>` section of `plugins/ai_dev/skills/task/SKILL.md`, and `task_create` runs it through its **Prior-art gate.** workflow step without restating the classes. Today the **Novel** entry reads "the hits were incidental keyword overlap; nothing actually covers this work", and the **Partially covered** entry reads "some of the requested work already exists". Related precedent fits neither wording: its overlap is real shared context rather than incidental keywords, yet none of the requested work exists. Agents resolve that gap toward **Partially covered** about half the time. The **Surface, never auto-resolve.** paragraph then requires them to ask the user before writing, so creation stops with no file.

The shipped-match routing that [the prior-art delta task](archive/task-family_prior-art-delta-and-cohesion-sizing.md) added (re-derive the genuinely-new delta, then fold, extend with a follow-up, narrow, or skip) governs real partial coverage, and this change leaves it intact. Related precedent is also exactly what the base **Decide or label** rule consumes as its tier (d) evidence, so classifying it as Novel keeps it available for reconciling forks while drafting.

The defect showed up in the `task_create` harness under `tests/task_create/evals/`. The `reconcile-recorded` eval asked for unit tests of two untested helpers in a module whose other function an archived finished task had tested, sharing its import-stubbing approach. Three of five draws on 2026-10-20 and two of three baseline draws against the pre-change skill stopped at the gate with a "Partially covered" ask. [The guardrail-bound fork task](archive/task-family_guardrail-bound-fork-surfacing.md) records those runs in its findings and reshaped that eval's fixture so its archived precedent covers a different module, which means the overlapping-precedent case has no eval of its own. This task restores it as a dedicated eval.

## Approach

Rewrite the **Novel** entry in `<prior_art>` in place so it names both cases that leave the request uncovered: incidental keyword overlap, and related precedent that shares context (module, dependency, or a settled pattern) while covering none of the requested work. For the related-precedent case, the entry directs the author to continue to `<scope>` and to cross-link the precedent in `## Context` when the `<markdown_policy>` cross-link discipline keeps the link. Tighten the **Partially covered** entry so its test reads as part of the requested work itself already existing, which makes the boundary between the two entries one canonical statement. Leave the other classes, the Tier 1 scan, and the **Surface, never auto-resolve.** disposition list unchanged.

Add one eval to `tests/task_create/evals/evals.json` with id `related-precedent-novel`, a fixture under `tests/task_create/evals/fixtures/related-precedent-novel/`, and its checks in `tests/task_create/evals/grade.sh`. The fixture stages an archived finished task that covered a sibling function in the same module and settled a pattern the new work reuses. It also gives the sandbox a git identity, so `reported-by` resolves without asking. The prompt requests only the uncovered work. The checks assert that exactly one new task file exists with `status: open` and lints clean, that the response finishes without asking the user how to proceed on prior art, and that the body's `## Context` links the archived precedent. Author the checks under the standing repo rules for grader design. List the eval in `tests/task_create/README.md`, and widen the `task_create` row of the `## What's here` table in `tests/CLAUDE.md`, which today describes three evals over the **Decide or label** rule.

Add the eval and record its baseline before rewriting `<prior_art>`, because the runner micro-deploys the skill from the working tree and so measures the unchanged gate only until the rewrite lands.

## Acceptance

- The `<prior_art>` **Novel** entry states that related precedent covering none of the requested work is Novel and is cross-linked in `## Context` when the cross-link discipline keeps it. Today the entry names only incidental keyword overlap, and after the rewrite a search of `plugins/ai_dev/skills/` for the old wording "the hits were incidental keyword overlap; nothing actually covers this work" finds no remaining copy.
- The **Partially covered** entry states its test as part of the requested work itself already existing.
- `tests/task_create/evals/evals.json` carries the `related-precedent-novel` eval with its fixture and grader checks as Approach describes, `tests/task_create/README.md` lists it, and the `task_create` row in `tests/CLAUDE.md` describes the eval set including it.
- Three `--no-cache` draws of `related-precedent-novel` against the pre-change skill are recorded as the baseline in a `## Findings` section of this task file, with run directories. When all three pass, the fixture does not reproduce the gate stop, so strengthen the precedent's overlap and re-run the baseline before measuring the change.
- After the change, five consecutive `--no-cache` draws of `related-precedent-novel` on the default vendor pass in five of five, recorded in the same `## Findings` section with run directories and each draw's `response.txt` as evidence. When any draw stops at the gate, leave the measurement incomplete, revise the wording, and re-run a fresh set of five.
