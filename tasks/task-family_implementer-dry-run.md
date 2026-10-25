---
description: "Add auto_dryrun_task to every task_auto_check round: before the gate it asks how implementing the task as written would go wrong, for any kind of work, and the gate confirms its findings."
scope: plugins/ai_dev
created: 2026-10-24T20:48:07
updated: 2026-10-25T14:11:44
status: checked
reported-by: Andreas Hoffmann
---

# Add an implementer dry run to every round of the task_auto_check loop

## Goal

Every round of `task_auto_check` runs one more agent, `auto_dryrun_task`, before the gate. It reads the task as it stands and answers one question from the implementer's seat: if I were about to implement this task exactly as it is written now, which issues, contradictions, gaps, and risks of introducing new errors would I meet? It first writes down the steps it would take, one line each, and then its findings. The gate receives those findings, confirms each one against the repository the way `task_check` grounds any issue, and reports the confirmed ones as readiness issues, so the round's reviewers and verifier repair them through the existing path. The rest of the loop stays as it is: the run ends when the gate stamps `ready`, `task_check` stays the only status writer, and the round cap bounds the run.

The dry run is task-agnostic. It applies the same question, the same checks, and the same finding format to code, to instructions written in prose (skills, agents, rules, prompts), and to knowledge work (documents, content, research, operations). The kind of work only adds a few prompts that sharpen the walk. The same change selects the Self-sufficiency advocate stance only for issues that cite the single-shot-ready bar, which offsets part of the extra agent call.

## Context

A study of 34 tasks implemented between 2026-09-24 and 2026-10-24 classified 280 findings raised after a task was declared ready. 92 were defects in the ready text, 89 of them at least partly catchable before implementation, and they rooted the longest implement, audit, and review loops. The readiness loop never takes the implementer's seat today: no gate, reviewer stance, or verifier asks how implementing the task as written would go. The gate's approach-fitness and interaction-scan lenses ask related questions and still cleared these defects. Writing the steps down before the findings is what sets the dry run apart, because an analysis that is not written down can be satisfied by a shallower read, the reach class `wiki/concepts/instruction-defect-classes.md` describes.

The defect kinds from that study that a dry run reaches by reading:

- contradictions between rules, visible when each case of a new rule is walked against the rules beside it;
- promises no implementation can keep, such as "by construction" or "every";
- measurement designs with no baseline or no stated move after a miss;
- edit sites the task never names, including the harness docs `TESTING.md` keeps current;
- forks that rest on the user's preference.

The cost is one agent call per round. The relay runs of 2026-10-12 to 2026-10-24 averaged about 2.6 rounds and about 13 reviewer calls per run, and the Self-sufficiency advocate landed 1 approved edit in 34 calls because orchestrators spawned it for issues that cite other rules. Restricting that stance saves about 1.8 calls per run, so a run costs about one extra agent call net, plus one sequential call per round in wall-clock time. Every `task_auto_check` eval slows by the same amount, and that cost is accepted.

`auto_gate_task` already consumes one supplied evidence file: `r<N>-refuted-citations.txt`, named in its `<inputs>` and handled by its policy rule that begins "Consume each entry of a supplied refuted-citation set". The dry-run return enters the gate the same way, with one difference: the gate confirms each dry-run finding before reporting it, because a dry-run finding is a claim, while a refuted citation was already verified.

Shape models for the new agent: `plugins/ai_dev/agents/auto_drift_task.md` for the frontmatter of a helper that writes nothing and runs shell (`readonly: true`, `tools: Read, Grep, Glob, Bash`), and `plugins/ai_dev/agents/auto_gate_task.md` for the body contract (its `isolation:` evidence line and return discipline). The agent name `auto_implementer_task` is reserved for the build step of the open autonomous implement loop, so this agent takes the role token `dryrun`.

## Approach

1. **Write `plugins/ai_dev/agents/auto_dryrun_task.md`** with `auto_drift_task`'s frontmatter key set, `version: 1.0.0`, and this contract:
   - **Inputs by path:** the task path, the base `task` skill path, the project root, and `frozen-intent.txt`. The relay directory stays closed to discovery apart from `frozen-intent.txt`.
   - **The question,** stated verbatim in the agent: "If you were about to implement this task exactly as it is written now, which issues, contradictions, gaps, and risks of introducing new errors would you meet?"
   - **Steps first.** Under `## Steps`, list the steps the implementer would take, in order and one line each, naming what each step changes (a file, a document, a rule, a system) and how the implementer would check that the step is done.
   - **Checks for every kind of work.** Walk the steps and the whole task for:
     - a decision the task leaves to the implementer;
     - information the implementer needs from outside the task and the project, such as data, access, or the user's preference;
     - a step that can fail with no stated next move, including a measurement with no baseline or no stated move after a miss;
     - a promise stated for every case ("every", "never", "always", "by construction") with no named way to prove it;
     - two passages that direct different actions for the same case, inside the task or between the task and a rule, document, or code beside what it changes;
     - something the change affects that the task never names: a caller or consumer, a cross-reference, an inventory or registration, or a document a standing rule keeps current;
     - an Acceptance check that would already pass today, or would pass on a wrong result;
     - a passage the implementer would have to untangle before acting, such as one sentence that stacks several rules or conditions;
     - a way that following the task as written breaks something that works today.
   - **Kind prompts.** Record a `kind:` line (code; instruction prose; knowledge work; or a named mix) and add that kind's prompts to the walk. A mix adds the prompts of every kind it names.
     - Code: the inputs the change meets, its callers and consumers, and the test that proves each step.
     - Instruction prose: each case of a new or changed rule walked against the rules beside it, stating what an agent that follows it literally does.
     - Knowledge work: the reader or user of the result, the claims that need a source or data, the steps that need credentials or the user, what done means to that reader, and recovery when the work changes a live system.
   - **Commands.** Read, search, and run read-only commands of the kind `task_check` already runs, such as a search for a pattern the task prescribes or an existing check on the current tree, and record each command with its observed output. The agent writes no file and builds no prototype. Record `isolation: confirmed`, or name each write and each out-of-bounds read, on the `auto_gate_task` model.
   - **Findings,** numbered `dr<k>`. Each names where it sits by a verbatim label, quotes the task text or states that the task is silent, says what would go wrong for the implementer, names the base `task` skill rule it fails (the single-shot-ready bar, **Compact only to the implementable floor**, **State once**, **Decide or label**, the Acceptance contract, **Declare exclusions as an Out of scope boundary**, **Rewrite in place, don't append**, or the `<readiness_checklist>` **Interaction scan** lens), and gives the minimum fix in this order of preference: a settled decision in Approach, an enumeration table in place of a rule, an Acceptance check that fails on the predicted mistake, or a bound in `**Out of scope:**`.
   - **Questions.** A gap the agent cannot ground in task text, code, or a standing rule goes under `## Questions`, not into the findings.
   - **Return.** `# auto_dryrun_task return`, then `kind:`, `## Steps`, `## Findings`, `## Questions`, and `## Evidence` with the commands and the isolation line; `unassessable` with its blocker when the walk cannot run. The agent gives no readiness verdict, writes no stamp, and proposes no edit text.
2. **Wire the dry run in and update the harness.** Each row names the passage that exists and the state it reaches.

   | File | Passage | Target state |
   | --- | --- | --- |
   | `plugins/ai_dev/skills/task_auto_check/SKILL.md` | `<role>` and `<path_resolution>` | Both name `auto_dryrun_task`, and `<role>` says every round runs a dry run before the gate. |
   | `plugins/ai_dev/skills/task_auto_check/SKILL.md` | `<relay>` | `dryrun` joins the `<helper>` tokens, so `r<N>-dryrun-prompt.txt` and `r<N>-dryrun.txt` follow the pointer-only prompt and byte-for-byte return rules. A new prompt bullet states that a dry-run prompt names the task path, the base `task` skill path, the project root, and `frozen-intent.txt`, and the gate-prompt bullet is rewritten so every gate prompt also names that round's `r<N>-dryrun.txt`. |
   | `plugins/ai_dev/skills/task_auto_check/SKILL.md` | a new `<dry_run>` workflow block placed before `<gate>` | Invoke `auto_dryrun_task` through `<relay>` on the task as it stands. A failed call or an `unassessable` return follows `<agent_failure_policy>`. |
   | `plugins/ai_dev/skills/task_auto_check/SKILL.md` | `<gate>` | Every gate call in a round, an isolation replacement and a refuted-citation re-invocation included, names that round's dry-run return; the rest of `<gate>` stays as it is. |
   | `plugins/ai_dev/skills/task_auto_check/SKILL.md` | `<loop_bounds>` round definition | "A round is one dry run, gate call, reviewer pass, verifier pass, edit application, and next loop decision." replaces the current sentence. |
   | `plugins/ai_dev/skills/task_auto_check/SKILL.md` | `<iterate>` | The loop returns to `<dry_run>` instead of `<gate>`. |
   | `plugins/ai_dev/skills/task_auto_check/SKILL.md` | `<agent_failure_policy>` | The never-role-play sentence names a missing dry-run, gate, drift, reviewer, or verifier result. |
   | `plugins/ai_dev/skills/task_auto_check/SKILL.md` | the Self-sufficiency advocate bullet in `<reviewer_stances>` | The stance is selected only for an issue that cites the single-shot-ready bar. |
   | `plugins/ai_dev/skills/task_auto_check/SKILL.md` | `<output_contract>` | A bullet reports, per round, the dry run's `kind:`, its finding count, and each finding the gate confirmed with the issue number it became. |
   | `plugins/ai_dev/agents/auto_gate_task.md` | `<inputs>` and the isolation sentence in `<policy>` | A `task_auto_check` call also receives `r<N>-dryrun.txt`, admitted beside `frozen-intent.txt` and the refuted-citation file. |
   | `plugins/ai_dev/agents/auto_gate_task.md` | `<policy>`, a new rule beside the refuted-citation rule | Ground each dry-run finding the way `task_check` grounds any issue. Report a confirmed finding as a readiness issue under the checklist item it falls under, marked `(dry run dr<k>)` in its title, and record an unconfirmed one as a question in the general assessment with its reason. No `ready` stamp lands while a confirmed finding stands, and `task_check` writes whatever status its own assessment reaches. |
   | `plugins/ai_dev/agents/auto_gate_task.md` | `## Evidence` in `<output_contract>` | A `dryrun:` line lists each finding as confirmed with its issue number, as not confirmed with the reason, or reads `none supplied`. |
   | `tests/task_auto_check/evals/relay_checks.py` | the admitted-path list in `prompts_isolated` | A gate prompt may name `/<stem>/r<N>-dryrun.txt` beside `frozen-intent.txt` and the refuted-citation file. |
   | `tests/task_auto_check/evals/run.py` | `ARTEFACTS` and `SERIAL_NESTED_LOOP_IDS` | `ARTEFACTS` names `auto_dryrun_task`, and the serial set ends with `dryrun_gap_confirmed`. |
   | `tests/task_auto_check/script_tests/run.sh` | the helper rosters in `s1_files_and_frontmatter`, `s4_loop_controls_and_boundaries`, `s6_docs_and_metadata_registered`, and `s7_pseudo_xml_lints`, and the never-role-play pin in `s10_failure_policy_and_rebaseline` | The rosters cover `auto_dryrun_task` (file, name, semver, `model: inherit`, H1, root README entry, pseudo-XML lint), and the s10 pin expects the five-helper sentence. New pins cover the `<dry_run>` block before `<gate>`, `<iterate>` returning to `<dry_run>`, the round definition, the gate's admission of `r<N>-dryrun.txt`, and the Self-sufficiency selection sentence. |
   | `tests/CLAUDE.md`, `tests/AGENTS.md`, `tests/task_auto_check/RUNBOOK.md` | the ordered serial nested-loop enumerations `test_docs_name_the_serial_set_once` walks | Each lists `dryrun_gap_confirmed` in the order of `SERIAL_NESTED_LOOP_IDS`. |
   | The plugin README, the root README tree, both plugin manifests, and both marketplace registrations | each place that names `auto_drift_task` | Each names `auto_dryrun_task` the same way, per the standing repo rules for adding an agent. |
   | `wiki/concepts/agent-delegated-automation.md` | "four task agents" and "four agents feeding a writer" | Five agents, with the dry-run role named, rewritten through the wiki skill family. |

3. **Add the eval `dryrun_gap_confirmed`** under `tests/task_auto_check/evals/`, run without `--vendor` per the standing repo rules. Its fixture is instruction prose: a task that adds a rule to a fixture skill file where, for one case, the new rule directs the opposite of a rule already in that file, and the task never mentions it. Validate the fixture cheap-first, as the harness guide in `tests/CLAUDE.md` describes, before running the loop.
4. **Re-run the existing `task_auto_check` evals** as the standing repo rules require after a skill change, since every eval now runs a dry run each round. Where a confirmed dry-run finding changes a verdict the eval does not test, adjust that eval's fixture or grader so it tests its own behaviour again.

**Out of scope:**

- Prototypes or scratch implementations during readiness, since the dry run reads and runs read-only commands only.
- A dry run inside the manual `task_check`, which keeps its checklist as it stands.
- The `auto_shaper_task` read-side gate call that `task_fix` escalation makes, which runs without a dry-run return.

## Acceptance

1. `plugins/ai_dev/agents/auto_dryrun_task.md` exists with `version: 1.0.0`, `readonly: true`, `tools: Read, Grep, Glob, Bash`, and `model: inherit`, and carries the verbatim question, the steps-first rule, the checks for every kind of work, the `kind:` line with the three kind prompt sets, the read-only command rule, the finding fields with the four fix shapes, the `## Questions` section for ungrounded gaps, the isolation line, and the return shape.
2. In `task_auto_check/SKILL.md` a `<dry_run>` block precedes `<gate>`, `<iterate>` returns to `<dry_run>`, `<relay>` carries the `dryrun` token and names `r<N>-dryrun.txt` in every gate prompt, and `<role>`, `<path_resolution>`, `<gate>`, and `<output_contract>` carry the changes the table gives them.
3. The `<loop_bounds>` round definition includes the dry run, and the sentence "A round is one gate call, reviewer pass, verifier pass, edit application, and next loop decision." no longer appears.
4. `<agent_failure_policy>` names a missing dry-run result in its never-role-play sentence, and "never role-plays a missing gate, drift, reviewer, or verifier result" no longer appears.
5. The Self-sufficiency advocate bullet selects the stance only for an issue that cites the single-shot-ready bar, and the unrestricted bullet is gone.
6. `auto_gate_task.md` admits `r<N>-dryrun.txt` in `<inputs>` and in its isolation sentence, carries the grounding rule for dry-run findings, and has the `dryrun:` line in its `## Evidence` template.
7. `prompts_isolated` in `relay_checks.py` admits the dry-run return path, and `tests/task_auto_check/script_tests/run.sh` passes with the updated rosters, the s10 pin, and the new pins the table lists.
8. `dryrun_gap_confirmed` passes: every gate return in its relay has a matching `r<N>-dryrun.txt`; the first dry-run return has a `kind:` line naming instruction prose and a finding that names the planted conflict; that round's gate return has a `dryrun:` line marking the finding confirmed with an issue number; and the final task text resolves the conflict.
9. `SERIAL_NESTED_LOOP_IDS` and the serial enumerations in `tests/CLAUDE.md`, `tests/AGENTS.md`, and `tests/task_auto_check/RUNBOOK.md` list `dryrun_gap_confirmed` in the same order, and `ARTEFACTS` names `auto_dryrun_task`.
10. `tests/task_auto_check/results/dryrun-rollout.md` records the re-run of the existing `task_auto_check` evals on the changed skill with each eval's verdict, and names every fixture or grader adjusted because of a confirmed dry-run finding, with the reason. An eval that still fails for that reason is named there, and the decision on it goes to the user.
11. The plugin README, the root README tree, both plugin manifests, and both marketplace registrations name `auto_dryrun_task`, and `wiki/concepts/agent-delegated-automation.md` names five task agents including the dry-run role, with the "four task agents" wording gone.
