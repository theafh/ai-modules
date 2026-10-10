---
description: Ship two generic agent definitions, auto_checker_spinner (read-only) and auto_writer_spinner, to every target, and prove on the default eval vendor that a checker spawns through its role.
scope: plugins/ai_dev/agents
created: 2026-10-03T15:54:08
updated: 2026-10-09T17:46:37
status: open
reported-by: Andreas Hoffmann
---

# Ship two generic helper roles: `auto_checker_spinner` and `auto_writer_spinner`

## Goal

agent_spinner is the skill an orchestrating agent reads before it runs helper agents. Today no agent definition ships for those helpers, so an orchestrator has no named role of its own to spawn them through. A spawn without a named role is a generic spawn. It lacks two things a named role can carry. One is a read-only lever, a setting in the role's definition, such as `readonly: true`, that the host itself enforces. The other is a depth setting, the model and reasoning effort the role runs at.

After this task, two generic roles ship under `plugins/ai_dev/agents/`: `auto_checker_spinner`, which is read-only, and `auto_writer_spinner`. A role is an agent definition file that a host can spawn by name. `make deploy` maps both roles to every target, so each harness it deploys to gets its own copy. The orchestrator, the agent that runs agent_spinner and spawns the helpers, opens each run with a capability probe. The probe tests what the host can actually call. When the probe finds a role callable, the orchestrator spawns through it, so a checker can carry the host-enforced read-only lever and the depth setting. Where the probe finds no role, the orchestrator spawns generically and records that route.

Each role body is a few fixed sentences. Its first line is "Read the brief file your prompt names, in full, and follow it." The brief is the instruction file the orchestrator renders for each helper, and it carries everything the role needs. The body therefore names no agent_spinner and restates no doctrine, meaning none of agent_spinner's rules. It returns exactly as that brief's closing block says, the block at the end of every brief that states how to return.

One eval, run as two cases, proves the spawn route. In one case the checker role is staged, meaning copied into the project's agent directory where the worker's host discovers it, and the checker spawns through the role. In the other case no role is staged, and the run records a generic spawn. Both cases pass on the default vendor, Cursor, and run unchanged on Claude when the operator asks for that run.

Both names carry the owner-approved `spinner` token. skill_doctor's scope resolution, which works out the set of skills it checks, stays unchanged by them.

## Context

- **Current state, read on 2026-10-04.** `plugins/ai_dev/agents/` holds only the task family's agents, each named `auto_<role>_task`. The read-only ones, such as `auto_verifier_task.md`, carry `readonly: true` and a `tools:` list of read and search tools. Every one carries `model: inherit`, `effort: max`, and `model_reasoning_effort: xhigh`. `make deploy` maps each top-level `*.md` under a plugin's `agents/` to every target. For each target it rewrites the frontmatter or generates a file in that target's format, as the agent rows of the mapping table in `deployment/README.md` list. In one generated format `readonly: true` becomes a read-only sandbox mode, and in another an edit-deny permission. `plugins/ai_dev/README.md` lists each agent under `## Agents`, and the root `README.md` layout tree lists each file under `plugins/ai_dev/agents/`.
- **Checks that reach these files.** These existing checks will read the new role files:
  - In `tests/agent_spinner/script_tests/run.sh`, the check "no agent definition cites agent_spinner" greps the whole agents directory, descriptions included.
  - The check "the skill bundles no agent definitions" looks only at the skill's own directory, so roles in the plugin's `agents/` directory pass it.
  - skill_doctor checks skills alone: its SKILL.md keeps agent definitions "outside every scope mode, `--all` included".
  - ai_instruction_formatting's `scripts/lint_pseudo_xml.py` scans `agents/*.md` files and accepts a prose-only body, one that uses no pseudo-XML tags.
- **Naming.** The standing repo rule "Name skills and agents by invocation mode and collision risk." names a spawned agent `auto_<role>_<family>`, where the last segment names the skill family the agent serves. skill_doctor derives a skill's family token from the first segment of its name, which for agent_spinner is `agent`. On 2026-10-04 the owner confirmed the names `auto_checker_spinner` and `auto_writer_spinner`. The owner's reason: `spinner` is the distinguishing term for these roles, while `agent` is generic and names what gets spawned. These names are a deliberate, owner-approved departure from the derived `agent` token. Every naming check this task adds therefore accepts the `spinner` token.
- **Decision this task implements.** On 2026-10-03 the owner approved two generic plugin roles. `make deploy` deploys them, and an orchestrator spawns them only when the capability probe establishes them callable. That decision reverses two items of [the archived spinner task](archive/ai-dev_agent-spinner-skill.md): the Goal's "no bundled helper agent definitions", and the Out of scope item "Bundled `auto_<role>_agent` helper definitions". That item's reason was that a marketplace install would rest the definitions on roles that do not exist. The reason no longer holds, because the repository now deploys directly. The archived task stays unedited as the decision record.
- **Role facts, observed in a probe run on 2026-10-04.** A probe run here is a set of small test sessions, each in a scratch git repository. The builds were Claude Code 2.1.226 and Cursor `agent` 2026.10.01, both in print mode, the CLI's non-interactive `-p` mode, and `codex-cli` 0.160.0.
  - **Read-only levers.** A lever holds when the host blocks what it forbids. Claude's `tools:` allowlist holds: a role listing `Read, Grep, Glob` ran with exactly those tools, and its write and shell attempts found no tool. Cursor's `readonly: true` holds in print mode: the role ran in ask mode, and both its file write and its shell command were refused. Codex's `sandbox_mode = "read-only"`, which `make deploy` generates from `readonly: true`, does not hold under a writing parent, a parent session that may write. The role still wrote a file and ran a shell command. On Codex, only the checker's body contract, the prohibition written in its body, keeps it read-only. The run's capability probe counts the lever as enforced only when its write attempt leaves no file. On Codex the probe therefore records the lever as not enforced.
  - **Staged and deployed roles.** Both print-mode CLIs spawn a role by name when it is staged in the project's agent directory: `.claude/agents/` on Claude, and `.cursor/agents/` on Cursor. A deploy also writes each role into each vendor's user agent directory. Claude's deployed user-level roles and skills reach a sandboxed print-mode session. Cursor's deployed user-level roles do not reach a sandboxed print-mode worker.
  - **Hiding deployed roles on Claude.** One environment hides the deployed roles from a Claude worker and still lets it sign in. The worker ran with the environment that the runner's `_claude_worker_env()` returns, plus a scratch `CLAUDE_CONFIG_DIR` and `CLAUDE_SECURESTORAGE_CONFIG_DIR` set to the empty string. It authenticated and listed only built-in roles and skills. The eval runner's per-pass micro-deployment (`tests/lib/micro_deploy.py`) now runs every Claude worker in that environment, and every Cursor worker under a scratch `HOME`, so no agent_spinner eval sees a deployed role.
- **Why the checker body carries its own read-only sentence.** A definition-level lever can leave a write path open, as the Codex result shows. harness_portability's rule beginning "Enforce a read-only agent role with each harness's own native lever" therefore pairs every lever with a prompt-level prohibition in the agent body. That prohibition is a property of the role, so it sits in the body. Every rule about the run stays in the brief.
- **Prerequisites.** Each of these tasks ships something this task builds on.
  - [The runner-modes task](tests_agent-spinner-runner-modes.md) gives the eval runner its `agents` harness key, a setting in an eval's `harness` block. The key adds a plugin role to one eval's micro-deployment and not to its sibling's. That task also adds the stub-worker tests in `tests/agent_spinner/evals/test_run.py`, which run the runner against a fake worker. It adds the `## Runner modes` section of `tests/agent_spinner/evals/README.md` too, and this task extends both.
  - [The run-ledger task](ai-dev_agent-spinner-run-ledger.md) ships the run ledger, the script that keeps a run's records on disk. Its roster, one line per helper, carries a spawn route column. That column names a registered role or a generic spawn, with the lever and depth as the probe found them. Its `init --probe` verb renders the probe brief once per role the host lists.
  - [The ledger-doctrine task](ai-dev_agent-spinner-ledger-doctrine.md) writes P1 of `references/run-protocol.md`, the protocol step that opens a run. P1 spawns the probe brief through each registered role the host lists.
  - [The judgement-containment task](ai-dev_agent-spinner-judgement-containment.md) has `<degradation>` name both roles and spawn through a callable one, recording the route on the roster. `<degradation>` is the agent_spinner block that sets how a run adapts to what the host offers. The eval tests that rule, so this task lands after it.
- **Grader rules.** A grader is the check that scores an eval run. Every new grader follows TESTING.md's `## Test Design Principles`. Shell added to `run.sh`, `grade.sh`, or a fixture stays within the bash 3.2 floor that harness_portability states in its rule beginning "Target bash 3.2 as the interpreter floor".

## Approach

### The role files

Create `plugins/ai_dev/agents/auto_checker_spinner.md` and `plugins/ai_dev/agents/auto_writer_spinner.md`. Give each the frontmatter keys the existing agents carry, with each `name:` equal to its file stem.

- **Descriptions.** Each description is one line. It says what the role does and that an orchestrator spawns it through a rendered brief. Neither description names agent_spinner.
- **Checker frontmatter.** The checker carries `readonly: true` and a `tools:` list of read and search tools only, as `auto_verifier_task.md` carries it. Keep `model: inherit`, and pin the deepest effort the existing agents pin, `effort: max` and `model_reasoning_effort: xhigh`. A checker runs at or above the depth of its producer, the helper whose work it checks. A fixed deepest pin meets that wherever the target honours it. harness_portability's rule beginning "Express model and reasoning-effort inheritance by omitting the key" allows such a pin for a role that must run at a fixed depth.
- **Writer frontmatter.** The writer carries `model: inherit`, with no read-only lever, no `tools:` list, and no effort key. Its depth then follows the spawning session and the run's per-role plan wherever the host honours them.
- **Bodies.** Each body is prose and holds only these sentences, the first on the body's first line:
  - "Read the brief file your prompt names, in full, and follow it."
  - For the checker only: "Work read-only: change no file, and run no command that writes, even where a shell stays callable."
  - "Return exactly as that brief's closing block says."
  - "If that file is missing or unreadable, reply with one line naming its path, and stop."

### Static checks

`tests/agent_spinner/script_tests/run.sh` holds one-way checks, which keep other components from citing agent_spinner. Beside them, add checks for these facts:

- Both role files exist.
- Each `name:` equals its file stem and matches `^auto_(checker|writer)_spinner$`.
- The checker carries `readonly: true` and a `tools:` list holding no write or shell tool.
- The writer carries no `readonly: true`.
- Each body's first line reads "Read the brief file your prompt names, in full, and follow it."

These are new checks under TESTING.md's `## Test Integrity`, the section that governs how the test suite may change.

### Deploy check

Run `deployment/deployment.sh --project-dir <scratch> --type agent` on a scratch project directory. Stage that directory the way `tests/deployment/script_tests/run.sh` stages its project directory, which leaves the user's harness directories untouched. Read each generated copy of the two roles. Compare each checker copy with the read-only mapping its target's agent row in `deployment/README.md` names.

### The eval

Add two eval ids to `tests/agent_spinner/evals/evals.json`. They share one fixture design, and each has its own `fixtures/<id>/setup.sh` and its own checks in `grade.sh`.

The fixture stages one page edited from a recorded instruction, together with its baseline, the page as it stood before the edit. The prompt asks for a check of that edit. It also answers the pre-dispatch gates, the questions the skill would otherwise put to the user before it spawns a helper. Each grader asserts its roster or filesystem fact before any response marker, a phrase it looks for in the worker's reply. Both cases are new checks under TESTING.md's `## Test Integrity`.

Each case uses one spec on Claude and Cursor, since neither exercises a Claude-specific feature, and neither `harness` block pins a vendor. A listed role reaches the worker only through the runner's `agents` harness key, which adds the role to the eval's micro-deployment. The deploy script then renders it per vendor, into the scratch Claude configuration directory's `agents/` or the sandbox project's `.cursor/agents/`. Both print-mode CLIs spawn a role staged there, so both cases run on either vendor and are proven on the default vendor. A failure is fixed inside this task, in the role file, the fixture, or the runner.

- `checker_spawned_through_role` lists `plugins/ai_dev/agents/auto_checker_spinner.md` under its `agents` harness key. Its grader asserts these facts:
  - A probe row for the `auto_checker_spinner` route records it as established. A probe row is the ledger's record of one probe spawn.
  - The checker's roster row names `auto_checker_spinner` as its spawn route, with the read-only lever as the probe recorded it.
  - The checker's return is accepted with source `relayed`. That source means the ledger took the checker's final message, passed on by the orchestrator, rather than a return file.
- `checker_spawned_without_role` leaves its `agents` key empty, so its micro-deployment carries no role on either vendor, and the micro-deployment keeps the user's deployed roles out of view. Its grader asserts that no probe row records a role route. It also asserts that the checker's roster row records a generic spawn, with the lever value the probe recorded for that route. A probe row that establishes the role means a deployed copy is visible to the worker. The case then fails with a message naming that copy, so a deployed role never passes as a generic spawn.
- Both cases also assert that the edited page and every file outside `.agent_spinner/` stay byte-identical.

### Docs

- Add one bullet per role to `## Agents` in `plugins/ai_dev/README.md`, and list both files under `plugins/ai_dev/agents/` in the root `README.md` layout tree.
- The ai_dev description reads identically in both `plugin.json` files and both marketplace registrations. Its agent_spinner clause gains the two roles in all four copies, because CHARTER.md requires plugin metadata, local marketplaces, and documentation to describe the same shipped component set.
- Add one row per eval id to the `## Signal per eval` table in `tests/agent_spinner/evals/README.md`.
- Keep every agent_spinner eval-count statement in `tests/agent_spinner/`, `tests/README.md`, and `tests/CLAUDE.md` equal to `jq '.evals | length' tests/agent_spinner/evals/evals.json`.

**Out of scope:**

- The `<degradation>` wording that names the roles, which the judgement-containment task owns.
- Recording how each deploy target reads the role files beyond the deploy check. Two sources already cover that: the agent rows of `deployment/README.md` state each target's generated keys and read-only mapping, and the run's capability probe measures the lever on the host it runs on.
- A third, lighter read-only role, since the approved design ships two roles.

## Acceptance

- Both role files exist, and each `name:` equals its file stem and matches `^auto_(checker|writer)_spinner$`.
- The checker carries `readonly: true`, a `tools:` list of read and search tools only, `model: inherit`, `effort: max`, and `model_reasoning_effort: xhigh`. The writer carries `model: inherit` and no read-only lever, `tools:` list, or effort key.
- Each body's first line is "Read the brief file your prompt names, in full, and follow it.", and each body holds only the sentences Approach lists for its role. run.sh's "no agent definition cites agent_spinner" passes.
- `bash tests/agent_spinner/script_tests/run.sh` passes with the new role checks. Each new check fails on a scratch copy holding the one violation it targets. Such violations include a checker without `readonly: true`, a checker `tools:` list naming a shell tool, a role named with the derived `agent` token such as `auto_checker_agent`, and a body whose first line differs.
- `ls plugins/*/agents plugins/*/skills` shows each name once, as its agent file. `python3 plugins/ai_dev/skills/skill_doctor/scripts/resolve_scope.py --root . --all` resolves the same skill set as at the parent commit, with neither name in it.
- `python3 plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py` reports no issue on either role file.
- A scratch deploy in project-directory mode writes a copy of each role for every target the agent rows list, and each checker copy carries the read-only mapping its target's row names.
- Both eval ids exist in `evals.json` with their fixtures and grade.sh cases, each checking its named fact before any response marker. Neither `harness` block pins a vendor, and `checker_spawned_without_role` lists no agent. Both cases pass under `python3 tests/agent_spinner/evals/run.py`, the default vendor. Re-grading a captured without-role run whose probe rows establish the role fails with the message naming the visible copy.
- The ai_dev description names both roles and reads identically in `plugins/ai_dev/.claude-plugin/plugin.json`, `plugins/ai_dev/.codex-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.agents/plugins/marketplace.json`.
- `plugins/ai_dev/README.md` and the root `README.md` list both roles, and the `## Signal per eval` table has one row per eval id. Every agent_spinner eval-count statement in the harness docs matches `jq '.evals | length' tests/agent_spinner/evals/evals.json`.
- Before the commit, a manual read of every changed shipped file and of this task's own diff finds no session, company, or project name, and no denylist is committed.
