---
description: Give every behavioral eval worker a per-pass micro-deployment of the skills, agents, and styles under test, built by the real deploy script alike on Cursor and Claude, and fail reads outside it.
scope: tests
created: 2026-10-08T11:47:48
updated: 2026-10-08T12:05:47
status: open
reported-by: Andreas Hoffmann
---

# Micro-deploy the artefacts under test for every eval worker through one shared mechanism

## Goal

Every behavioral eval worker under `tests/` loads the skills, agents, and output
styles under test from a micro-deployment that the repository's own deploy script
builds for that pass from the version under test, and no deployed copy from the
user's machine is in its view. One shared mechanism in `tests/lib/` builds that
deployment and runs the worker against it, for every runner and on both vendors,
so a Cursor worker and a Claude worker each load the artefacts through their own
native discovery (a skill by name, a named agent, a selected style) in the shape a
real deployment gives them. Each pass records which artefact files its worker
read, and a pass whose worker read one from outside its micro-deployment fails an
integrity check that names the path. The user-visible outcome: an edit to any
skill, agent, or style, a dependency such as the base `task` skill included, is
measured by the next eval run instead of after the next deploy, and both vendors
measure the same deployed shape.

## Context

- **How runners load artefacts today.** Every runner that calls
  `vendor.stage_skill_tree` copies the skill under test into an `artefacts/`
  directory beside its sandbox (wiki layer 2 also copies the `wiki` hub there),
  names that copy's path in the worker prompt, and passes its sandbox project as
  the Cursor `workspace`. No runner stages the other skills its subject reaches by
  name. Named agents are copied unrendered into the sandbox's
  `.{claude,cursor}/agents/` by the local `stage_named_agents` copies in wiki
  layer 2 and `task_auto_check`, and `tests/natural_language/evals/run.py` hands
  its style to the worker itself. None of them goes through the per-vendor
  rendering the deploy script applies. `tests/language_humanizer/evals/run.py`
  stages its copy as a project skill of an isolated root and names that path, a
  mitigation its comment beginning "Traced on 8 October 2026" describes. Each
  cached runner declares the skills a verdict depends on in
  `source_roots_for(...)`, which feeds the cache key.
- **What workers read (traced 8 October 2026).** Stream-json read events of real
  eval runs, with a deployed copy of every repository skill in the user's Cursor
  and Claude skill directories, showed reads outside the staged set:
  - On Cursor, a `language_humanizer` worker told to read a copy staged outside
    its workspace read the deployed copy in three of three runs and never opened
    the staged copy in two of them. A project copy in the workspace did not
    displace the deployed copy when the prompt named no path.
  - Dependencies resolved outside the staged set. `task_create`
    (`reconcile-recorded`) read the deployed base `task` skill on Cursor (and ran
    its deployed scripts) and on Claude, and the rule those evals test lives in
    that base skill. `skill_doctor` (`scope_hub_family`) read the deployed
    `ai_instruction_formatting` and `ai_instruction_writing` on Cursor.
    `guardrail_audit` (`presence_gate`) read the `guardrail` hub from the
    repository checkout, which its in-repo sandbox can reach.
  - A Claude worker's init event lists every deployed user-level skill.
- **What takes deployed copies out of view (verified 8 October 2026).** On
  Cursor, a scratch `HOME` whose `Library` links back to the real one
  authenticates and hides the user's deployed skills, while `CURSOR_CONFIG_DIR`
  alone leaves them in view, because skill discovery follows the home directory.
  On Claude, a scratch `CLAUDE_CONFIG_DIR` with `CLAUDE_SECURESTORAGE_CONFIG_DIR`
  set to the empty string authenticates and hides the user's deployed skills and
  agents. [The agent_spinner role-definitions task](ai-dev_agent-spinner-role-definitions.md)
  records that route under **Hiding deployed roles on Claude**. With every
  repository skill deployed into that scratch home or config directory, both
  workers loaded the deployed copy by name with no path in the prompt. The
  evidence is on [the Cursor entity page](../wiki/entities/cursor.md) and
  [the Claude Code entity page](../wiki/entities/anthropic-claude-code.md), each
  linking its probe notes.
- **Where each vendor loads each artefact type in print mode.** These facts sit
  on the same two entity pages:
  - **Skills:** Cursor reads the home's `.cursor/skills/` (and the `.claude`,
    `.codex`, `.grok`, and `.agents` skill directories beside it), while Claude
    reads its config directory or the project's `.claude/skills/`.
  - **Named agents:** Cursor reads only the workspace's `.cursor/agents/` (the
    user's deployed roles did not appear on 4 October 2026), while Claude reads
    its config directory or the project's `.claude/agents/`.
  - **Styles:** Cursor applies only a project `.cursor/rules/*.mdc` with
    `alwaysApply: true` (a home `rules/` file was not injected on 6 October 2026),
    while Claude applies `output-styles/` plus the `outputStyle` key in its config
    directory's or the project's `settings.json`.
- **The deploy script already performs a micro-deployment.**
  `deployment/deployment.sh --project-dir <dir> --target claude|cursor` copies
  skills, writes a rendered copy of each agent per vendor, generates the Cursor
  style rule `.cursor/rules/<style>.mdc`, and for Claude copies the output style
  and merges `.claude/settings.json`. `--global` writes the user-level layout
  under `$HOME`, which `tests/deployment/script_tests/run.sh` drives with `HOME`
  pointing at a scratch directory. `--type` filters artefact types and `--target`
  vendors, and nothing filters named artefacts. Every run that writes appends to
  `deployment/deployed_artefacts.log`, which `make uninstall` reads, and the
  deployment script tests back that log up and restore it around their runs,
  which concurrent eval passes cannot do safely.
- **Why it matters.** A deployed copy matches the repository only until something
  changes, which is exactly when an eval matters. The cache sharpens that for
  dependencies: the key already hashes the base `task` skill, so editing it
  invalidates the cache, and the re-run then measures the deployed base skill.
- **Shared surfaces.**
  [The agent_spinner runner-modes task](tests_agent-spinner-runner-modes.md) adds
  agent staging with its own frontmatter rendering, which the micro-deployment
  replaces with the deploy script's rendering, so whichever lands second adopts
  the other's helper. The shared Pattern A eval-runner task and the cache-key
  granularity task, both named under **Out of scope:** below, edit `tests/lib/`
  and the shape of `source_roots_for`; whichever declaration shape exists when
  this lands is the one that feeds the micro-deployment. The per-runner
  `tests_*-parallel-evals.md` tasks edit the same `run.py` files, and this task's
  change there is a call swap either order absorbs.

## Approach

1. **Deploy-script support.** In `deployment/deployment.sh`, read an override for
   the deployed-artefacts log path where `DEPLOYED_ARTIFACTS_LOG` is set, so a
   test deployment writes its log inside its own scratch tree and
   `deployment/deployed_artefacts.log` stays untouched. Add `--only NAME[,NAME…]`
   beside `--type` and `--target`, so a run deploys exactly the named artefacts.
   Document both in the script's help and header comment, and cover both in
   `tests/deployment/script_tests/run.sh`.
2. **One micro-deploy helper.** Add `tests/lib/micro_deploy.py`. For one pass it
   creates a scratch home and a workspace root that holds the sandbox project
   beneath it, both outside every tree a grader compares, and runs the deploy
   script with the log override and the runner's declared artefacts. A `--global`
   run with `HOME` set to the scratch home writes the user-level layout, and a
   `--project-dir` run into the workspace root writes the types a vendor loads only
   at project scope (Cursor's agents and style rules). It returns the worker
   environment for the vendor, the workspace root to pass as the Cursor
   `workspace`, and the deployed path of the skill under test for prompts that
   name it:
   - **Cursor:** `HOME` at the scratch home, with the scratch home's `Library`
     linked to the real one so the stored login keeps working.
   - **Claude:** `CLAUDE_CONFIG_DIR` at the scratch home's `.claude`, with
     `CLAUDE_SECURESTORAGE_CONFIG_DIR` set to the empty string.

   It preflights the worker against that environment and stops the eval with the
   CLI's own message when authentication fails, which also covers a platform
   whose login store sits somewhere other than `Library`. After the pass it
   removes the scratch tree, unlinking `Library` first.
3. **One declaration per runner.** Each runner declares once the skills, agents,
   and styles its evals may load, and that declaration feeds both the `--only`
   list and the cache key's `source_roots`, so what is deployed, what is hashed,
   and what a worker may read stay one list. A runner deploys a style only when
   its evals test that style, because a selected style shapes every reply.
4. **One worker-run helper with read provenance.** Add to `tests/lib/` a helper
   that runs a print-mode worker with the vendor's streaming output
   (`--output-format stream-json` on Cursor, `--output-format stream-json
   --verbose` on Claude), building the command through `vendor.build_print_cmd`
   so extra arguments and prompt placement keep working. It decodes partial output
   through `tests/lib/worker_io.py` on timeout and returns the exit code, the
   final result text the runners write to `response.txt` today, stderr, and every
   path the worker read, globbed, or named in a shell command. A shared classifier
   marks a path as out of set when it names a skill, agent, or style file outside
   the scratch home, the workspace root, and the sandbox. Each runner adds an
   integrity check named `artefacts_read_from_micro_deployment` that fails a pass
   with any out-of-set path and records the path list in that pass's verdict.
5. **Adopt in every runner.** Switch every runner that calls
   `vendor.stage_skill_tree` or a local `stage_named_agents`, and the style
   staging in `tests/natural_language/evals/run.py`, to the micro-deploy helper
   and the run helper. `natural_language` keeps its marker preflight as the proof
   that the deployed style loaded. Fold the project-skill staging in
   `tests/language_humanizer/evals/run.py` into the shared helper, and remove
   `vendor.stage_skill_tree` and the local agent-staging copies once no caller
   remains.
6. **Tests.** Add `tests/lib/test_micro_deploy.py`. It runs the real deploy
   script into a scratch tree with no model call and checks the following:
   - The per-vendor layout: skills in the scratch home, Cursor's agents and style
     rules at the workspace root, and Claude's agents, output style, and
     `outputStyle` key in its config directory.
   - That `--only` limits the deployment to the named artefacts, and that
     `deployment/deployed_artefacts.log` comes out byte-identical.
   - The worker environment per vendor, stream parsing for both vendors from
     recorded event lines, and the classifier on in-set and out-of-set paths.
7. **Docs.** Rewrite in place, in lockstep, the canonical rule in
   `tests/CLAUDE.md` (the `### Model policy` passage beginning "Workers path-read
   the skill under test") and in `tests/AGENTS.md` (`### Skill and agent
   loading`). One rule remains: workers load artefacts only from the per-pass
   micro-deployment, deployed copies stay out of view on both vendors, and the
   provenance check enforces it. Update the staging sentence under
   `## Vendor switch` in `tests/README.md` to match.

**Out of scope:**

- `tests/trigger_evals/`, which measures the deployed skill tree by design and
  keeps doing so.
- Moving sandboxes outside the repository through
  `tests/lib/worker_isolation.py`, since this task controls which artefacts a
  worker loads, not which host instruction files it reaches.
- The shared job pool and per-job `TMPDIR`, which
  [the shared Pattern A eval runner](archive/tests_shared-pattern-a-eval-runner.md) owns.
- Narrowing cache keys per eval, which
  [the cache-key granularity task](tests_eval-cache-key-granularity.md) owns.

## Acceptance

- `bash tests/deployment/script_tests/run.sh` passes with cases proving that the
  log override leaves `deployment/deployed_artefacts.log` byte-identical and that
  `--only` deploys exactly the named artefacts.
- `python3 tests/lib/test_micro_deploy.py` passes with the cases Approach step 6
  lists.
- `rg -n 'stage_skill_tree|def stage_named_agents' tests -g '*.py'` prints
  nothing, and `rg -l 'micro_deploy' tests -g 'run.py'` lists every runner that
  loads a skill, an agent, or a style for its worker.
- Each runner with a verdict cache passes one declaration both to the micro-deploy
  helper and to the cache key's `source_roots`.
- Each runner records `artefacts_read_from_micro_deployment`, with its path list,
  in every pass's verdict.
- On `--vendor cursor` and on `--vendor claude`, these evals run with
  `artefacts_read_from_micro_deployment` passing and no artefact path outside the
  micro-deployment in their verdicts: one each of `task_create`
  (`reconcile-recorded`), `skill_doctor` (`scope_hub_family`), `guardrail_audit`
  (`presence_gate`), and `language_humanizer` (`write_path --passes 1`), the
  harnesses whose 8 October 2026 traces read outside the staged set, and wiki
  layer 2 scenario `AS-1`, whose skill spawns the deployed `auto_shaper_wiki`
  agent. A run that still reads outside fails that check, and the report names
  the path and the vendor instead of re-running for a clean draw.
- On `--vendor claude`, `natural_language` scenario `connected_rewrite` with
  `--passes 1` passes its marker preflight with the style coming from the
  micro-deployment.
- `rg -n "under the eval's .artefacts/. directory beside the sandbox" tests/CLAUDE.md tests/AGENTS.md`
  prints nothing, and the two guides state the same micro-deployment rule.
