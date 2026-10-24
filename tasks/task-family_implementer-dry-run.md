---
description: "Add auto_dryrun_task to task_auto_check: on a ready verdict it writes the plan an implementer would follow for code, rule, sysadmin, content, or research work, and its gaps become repair issues."
scope: plugins/ai_dev
created: 2026-10-24T20:48:07
updated: 2026-10-24T20:48:07
status: open
reported-by: Andreas Hoffmann
---

# Add an implementer dry run to the task_auto_check readiness loop

## Goal

`task_auto_check` gains a dry run from the implementer's seat. When the gate stamps a task `ready`, a new agent, `auto_dryrun_task`, writes down the plan it would follow if it started implementing now: each artifact it would touch in order, how it would verify each step, and every decision the task left to it. Each gap in that plan becomes a readiness finding that the loop repairs through its existing reviewer, verifier, and delta-audit path. A task leaves the loop `ready` only after the gate's checklist and the implementer's walk-through both come up clean.

The dry run adapts to the kind of work the task describes: code, skill and agent rules, system administration, content, or research. It reads and runs read-only commands and builds no prototype, so a run costs one or two extra agent calls on top of today's loop. The outcome is a loop that catches more of the defects that today surface only after implementation.

## Context

A study of 34 tasks implemented between 2026-09-24 and 2026-10-24 classified 280 findings raised after a task was declared ready. 92 were defects in the ready text, 89 of them at least partly catchable before implementation, and they rooted the longest implement, audit, and review loops. The loop never takes the implementer's seat today: no gate, reviewer stance, or verifier walks the Approach step by step, and 9 of the 95 approved repairs in the surviving relay runs added an edge case or failure mode. The gate's approach-fitness and interaction-scan lenses ask related questions and still cleared these defects. That is why the dry run produces a written plan instead of a second checklist verdict: an analysis that has to be written down cannot be satisfied by a shallower read, the reach class `wiki/concepts/instruction-defect-classes.md` describes.

The defect kinds a reading dry run reaches, from that study:

- contradictions between rules, visible when each case of a new rule is walked against the rules beside it;
- promises no implementation can keep, such as "by construction" or "every";
- measurement designs with no baseline or no stated move after a miss;
- edit sites the task never names, including the harness docs `TESTING.md` keeps current;
- forks that rest on the user's preference.

The same relay runs show the Self-sufficiency advocate stance landing 1 approved edit in 34 reviewer calls, because orchestrators spawned it for gate issues that cite other rules. Selecting it only for issues that cite the single-shot-ready bar saves about as many reviewer calls across those 19 runs as one dry run per run would add.

The edit sites and the shapes to follow:

- `plugins/ai_dev/skills/task_auto_check/SKILL.md` holds the loop: `<path_resolution>`, `<relay>`, `<reviewer_stances>`, `<gate>`, `<plan_repairs>`, `<verification_standard>`, `<loop_bounds>`, and `<output_contract>`.
- `plugins/ai_dev/agents/auto_reviewer_task.md` and `plugins/ai_dev/agents/auto_verifier_task.md` name their admissible issue classes in `<inputs>`: a gate issue and a lint-originated `repeated-link` finding. The `repeated-link` class is the precedent for an issue that enters without the gate and is repaired and verified on equal terms.
- `plugins/ai_dev/agents/auto_gate_task.md` is the shape model for the new agent: its frontmatter field set, its read-only body contract with the stamp as its only write, and its `isolation:` evidence line.
- `tests/task_auto_check/evals/` is the Pattern A harness (`evals.json`, `fixtures/`, `stage.sh`, `grade.sh`, `relay_checks.py`), and `tests/task_auto_check/results/*.md` holds tracked analysis notes.
- `wiki/concepts/agent-delegated-automation.md` names the task family's agent roles.

The agent name `auto_implementer_task` is reserved for the build step of the open autonomous implement loop, so this agent takes the role token `dryrun`.

## Approach

1. **Write `plugins/ai_dev/agents/auto_dryrun_task.md`** with `auto_gate_task`'s frontmatter field set, `version: 1.0.0`, and this contract:
   - **Inputs by path:** the task path, the base `task` skill path, the project root, and `frozen-intent.txt`.
   - **Kind.** Classify the task from what it changes as code; skill, agent, or rule text; system administration; content; research; or a named mix.
   - **Core walk, written as the plan.** The artifacts in edit order, each with the anchor of its edit; the verification for each step and what it shows on today's tree; each decision the task leaves to the implementer; each point where the implementer would need information outside the task and the project; and each step that may fail without the task saying what to do next.
   - **Question set per kind, applied on top of the core walk:**
     - Code: the inputs the change meets, its callers and consumers, and the test that proves each step.
     - Rules: each case of a new or changed rule walked against the rules beside it, stating what an agent following it literally does on each surface.
     - System administration: order of operations, idempotency on a repeat run, rollback, differences between machines, and the steps that need credentials or the user.
     - Content: the audience, the claims that need a source, the channel's limits, and what done means to a reader.
     - Research: the question, the method, whether the data exists, what counts as an answer, and what happens when the hypothesis fails.
   - **Commands.** Read, search, and run read-only commands of the kind `task_check` already runs, such as a search for a pattern the task prescribes or an existing check or linter on the current tree. Record each command with its observed output. The agent writes no file and builds no prototype. Record `isolation: confirmed`, or name each write and each out-of-bounds read, on the `auto_gate_task` model.
   - **Findings.** Each finding names the plan step where the gap sits, quotes the task text or states that the task is silent, names the base `task` skill rule it fails (the single-shot-ready bar, **Decide or label**, the Acceptance contract, **Declare exclusions as an Out of scope boundary**, or **Rewrite in place, don't append**), and states the minimum fix shape. The fix shapes, in order of preference: a settled decision in Approach, an enumeration table in place of a rule, an Acceptance check that fails on the predicted mistake, and a bound in `**Out of scope:**`. A gap the agent cannot ground in task text or code stays a question in the plan.
   - **Return.** A `# auto_dryrun_task return` with `kind:`, the plan, the numbered findings, the commands, and the evidence block; `unassessable` with its blocker when the walk cannot run.
2. **Wire the dry run into `task_auto_check/SKILL.md`:**
   - `<path_resolution>` and `<role>` name `auto_dryrun_task`.
   - `<gate>`: when an accepted verdict reports `ready` and any citation refutation that `<gate>` runs leaves it standing, invoke `auto_dryrun_task` through `<relay>` before the repeated-link repair round and `<finalize_mechanical_lint>`. A dry run with no findings lets the `ready` stand.
   - `<relay>` adds `r<N>-dryrun-prompt.txt` and `r<N>-dryrun.txt` and the `dryrun` helper token, with the existing pointer-only prompt and byte-for-byte return rules.
   - `<plan_repairs>`, `<verify_repairs>`, `<verification_standard>`, and `<apply_repairs>` admit dry-run findings, numbered `dr<k>`, as a third issue class beside gate issues and lint-originated `repeated-link` findings, with the delta audit unchanged.
   - Status follows the base `<status_discipline>` rule: a dry-run repair that changes what the task delivers or how delivery is checked returns the task to `checked` and the loop returns to `<gate>`, while a repair that only makes an existing requirement explicit keeps `ready` and the run proceeds to finalize.
   - `<loop_bounds>`: at most two dry runs per run, the second only after a dry-run repair changed Approach or Acceptance, each counted as a round against the cap.
   - `<reviewer_stances>`: each dry-run finding maps to the stance of the base rule it cites. Rewrite the Self-sufficiency advocate bullet so the stance is selected only for an issue that cites the single-shot-ready bar.
   - `<agent_failure_policy>` covers the new helper as written, and `<output_contract>` reports the dry-run calls, the kind, each finding with its disposition (repaired, rejected, or human-routed), and whether a dry-run round returned the task to `checked`.
3. **Admit the class in the helpers.** Rewrite the issue-class sentences in the `<inputs>` of `auto_reviewer_task` and `auto_verifier_task` so each names the three classes, with a dry-run finding arriving by its `dr<k>` number in `r<N>-dryrun.txt`.
4. **Register and document** the agent as the standing repo rules for adding an agent require, update the `task_auto_check` harness docs and test inventories as `TESTING.md` requires, and record the dry-run role in `wiki/concepts/agent-delegated-automation.md` through the wiki skill family.
5. **Add three evals** under `tests/task_auto_check/evals/`, run without `--vendor` per the standing repo rules:
   - `dryrun_surfaces_gap`: a fixture task the gate passes whose Approach leaves an implementer-blocking gap, such as a measurement with no stated move after a miss.
   - `dryrun_clean_ready`: a fixture task that is genuinely ready, a small additive prose change.
   - `dryrun_kind_sysadmin`: a fixture task that rolls a configuration change out to two hosts and states no rollback.
6. **Replay the agent on five historical ready texts.** Stage each with `git archive <commit>` into a temporary directory outside the checkout, so the dry run reads the codebase as it stood, and run `auto_dryrun_task` once per case. Each case is a defect the gate passed at ready and a later audit or review found:

   | Commit | Task file at that commit | Defect a later round found |
   | --- | --- | --- |
   | `ba6e847` | `tasks/task-family_repeated-link-reorganize-body.md` | A link repeated inside one paragraph has no allowed outcome: the Approach keeps naming the target again in plain text while ruling that stripping link syntax resolves nothing. |
   | `b011c11` | `tasks/task-family_quote-frontmatter-descriptions.md` | The Approach both strips trailing `#` comments and blocks a `#` after whitespace. |
   | `0cf0227` | `tasks/tests_eval-cache-key-granularity.md` | The Goal promises stale passes are impossible "by construction" on top of a static bash lexer, and an Acceptance item requires identical verdicts from LLM eval runs. |
   | `f36e70b` | `tasks/tests_trigger-eval-unavailable-skill-guard.md` | The deployed-mode stubs return "without writing" score fields, while `main` reads `summary['precise_passed']`. |
   | `0cf0227` | `tasks/task-family_implement-requires-ready.md` | The role sentence runs the full suite only on request, below the standing repo rule to re-run the suite, and two READMEs keep the retired "suite clean" phrase. |

**Out of scope:**

- Prototypes or scratch implementations during readiness, since the dry run reads and runs read-only commands only.
- A dry run inside the manual `task_check`, which keeps its checklist as it stands.

## Acceptance

1. `plugins/ai_dev/agents/auto_dryrun_task.md` exists with the inputs, the kind classification, the five question sets, the read-only command rule, the finding fields with the four fix shapes, the `isolation:` line, and the return shape the Approach gives the new agent.
2. `task_auto_check/SKILL.md` names `auto_dryrun_task` in `<path_resolution>`, lists `r<N>-dryrun-prompt.txt`, `r<N>-dryrun.txt`, and the `dryrun` token in `<relay>`, invokes the dry run on an accepted `ready` in `<gate>`, caps dry runs at two per run in `<loop_bounds>`, and reports dry-run calls and finding dispositions in `<output_contract>`.
3. `<plan_repairs>` and `<verification_standard>` in `task_auto_check`, and the `<inputs>` of `auto_reviewer_task` and `auto_verifier_task`, each state the three admissible issue classes once, and the two-class wording no longer appears in any of the four.
4. The Self-sufficiency advocate bullet in `<reviewer_stances>` selects the stance only for an issue that cites the single-shot-ready bar, and the unrestricted bullet is gone.
5. `dryrun_surfaces_gap` passes: the run's relay holds a dry-run return whose findings name the planted gap, and the final task text resolves it.
6. `dryrun_clean_ready` passes: the relay holds exactly one dry-run return with zero findings, the final status is `ready`, and the body carries no edit outside the mechanical lint set.
7. `dryrun_kind_sysadmin` passes: the return's `kind:` line names system administration, and its plan or findings cover rollback and a repeat run.
8. The graders of all three evals fail a run whose relay holds more than two dry-run returns.
9. `tests/task_auto_check/results/dryrun-replay.md` records each of the five replay cases with the return's kind, whether a finding names the listed defect (quoting that finding), the count of other findings, and the wall-clock time of the call. When fewer than three of the five defects are named, the record lists the misses with the plan excerpt that walked past each one, and the ship decision goes to the user instead of another draw.
10. The plugin README, the root README layout tree, and the plugin descriptions name the agent; the harness README and test inventories name the three evals; and `wiki/concepts/agent-delegated-automation.md` names the dry-run role.
