---
description: "Define three terms agent_spinner workers guess at: the read-only diagnostic route against the audit row, a task in the multi-file recipe row, and a registered role the spawn surface lists."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T16:08:26Z
updated: 2026-11-14T23:54:21Z
status: open
reported-by: Andreas Hoffmann
---

# Define agent_spinner's read-only diagnostic, task, and registered role

## Goal

Three terms that steer an orchestrator's first moves get a definition the skill states once. A request to find something across many artifacts while changing nothing routes the same way on every draw. A "task" in the multi-file recipe row means a tracked item with its own acceptance list. A registered role means a role the host's own spawn surface lists, so an orchestrator probes roles through that surface and never goes looking for agent definition files on disk.

## Context

The three terms sit near the top of `plugins/ai_dev/skills/agent_spinner/SKILL.md` and in its recipe table:

- **Read-only diagnostic.** `<selector>` says "A read-only diagnostic, or a single judgement question about a mechanism not yet built, is answered inline from your own reads before any helper is spent, takes no recipe". The recipe table in the same block routes "Audit many artifacts, changing nothing" to `check-only-audit.md`. The skill never defines "read-only diagnostic", so an ask like "find the drift across these eight pages, change no file" fits both. On the identical `inline_floor` and `phase_plan_announcement` prompts, `sonnet` (2026-11-13) answered inline as a read-only diagnostic with no phase plan, no item count, and no bound, while `opus` (2026-11-14) ran the check-only-audit recipe. The two evals expect the recipe path.
- **Task.** The recipe row "Implement one task spanning many files" never says what a task is; only `references/recipes/multi-file-task.md`'s trigger ties it to "the task's written acceptance list". On 2026-11-14 the Cursor worker matched that recipe in seven announcements of the suite, once by writing its own `acceptance.md` to fit (`shape_matched_no_recipe`), while Claude matched no recipe on the same prompts. In the same evening's Claude run, `wide_run_plans_session_boundary` routed a hundred-page audit inline as a read-only diagnostic and planned no session boundary.
- **Registered role.** `<capability_probe>` says "A role definition on disk is evidence that the file deployed, not evidence that it can be called". That keeps disk files from proving callability, but it still names them as deployment evidence, which invites a search for them, and no sentence says where a registered role comes from. `<degradation>` says "Where the probe finds `auto_checker_spinner` or `auto_writer_spinner` callable, spawn through it". `references/run-protocol.md` P1 probes "once through each registered role the host lists". In the 2026-11-14 Claude run, the `depth_one_level` worker listed the operator's own agent directory under the home directory, read both role definitions there, and recorded role-route probe rows for roles its host could not spawn. A skill meant to work in any repository and on any host should not lead a worker to read another installation's files. The eval harness is tightening its isolation separately, in [the Claude worker scratch-home task](tests_claude-worker-scratch-home.md); this task fixes the wording that sent the worker looking.

## Approach

1. In `<selector>`, define a read-only diagnostic by what it reads: one artifact or one mechanism, answered from the orchestrator's own reads. State that an ask to inspect many artifacts without changing them routes to the "Audit many artifacts, changing nothing" row whatever verb it uses. Rewrite the existing sentence in place so the definition sits with it.
2. In the recipe table row "Implement one task spanning many files" and in `references/recipes/multi-file-task.md`'s trigger, define a task as a tracked item that carries its own acceptance list, and send a per-artifact job without one to the shape that fits it with no recipe.
3. In `<capability_probe>` and `<degradation>`, and in `references/run-protocol.md`'s P1 probe step, define a registered role as one the host's spawn surface lists or accepts by name. Say that the probe tries each one through that surface and never searches home or configuration directories for definition files. Rewrite the "A role definition on disk is evidence that the file deployed" sentence in place so it no longer names disk files as evidence of anything the run needs. In the same change, reword `probe_definitions_no_spawn`'s expectation, `expected_output`, check label, and first grader alternative in `tests/agent_spinner/evals/` from "definitions as deployment rather than callability" to "on-disk definitions as no evidence of callability, which only the spawn surface establishes", so the eval checks the rewritten rule.

## Acceptance

- SKILL.md `<selector>` carries the read-only-diagnostic definition beside the many-artifacts routing rule, and a grep for the old undefined sentence alone finds it rewritten.
- `<capability_probe>`, `<degradation>`, and the P1 probe step define a registered role through the host's spawn surface, and a grep for "A role definition on disk is evidence" finds nothing.
- A static check in `tests/agent_spinner/script_tests/run.sh` asserts all three definitions are present.
- The recipe row and the multi-file recipe's trigger define a task by its own acceptance list.
- `inline_floor`, `phase_plan_announcement`, `wide_run_plans_session_boundary`, `shape_matched_no_recipe`, and `probe_definitions_no_spawn` run on the default vendor, and their verdicts are recorded in `tests/agent_spinner/evals/README.md`. The first three take the recipe path, `shape_matched_no_recipe` matches no recipe, and the probe eval checks the reworded rule. If any still routes the old way, the record says so and the wording gets another pass.
