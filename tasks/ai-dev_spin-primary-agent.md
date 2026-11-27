---
description: "Trial the inline spin primary agent on three delegation jobs, then promote it into the ai_dev plugin as a primary agent if it holds the agent_spinner contract, or defer it with the failures recorded."
scope: plugins/ai_dev
created: 2026-11-27T09:00:44Z
updated: 2026-11-27T09:00:44Z
status: open
reported-by: Andreas Hoffmann
---

# Trial and promote the spin primary agent

## Goal

The `spin` primary agent earns a place in the `ai_dev` plugin, or the trial records why it does not. The trial runs the inline copy on three delegation jobs and checks whether it loads `agent_spinner` before the first helper, runs the probe and ledger, routes checks through `auto_checker_spinner`, and closes the run. When it holds, `plugins/ai_dev/agents/spin.md` ships as a `mode: primary` agent beside Build and Plan; when it does not, the trial record names the failures and the promotion waits.

## Context

- A trial copy of the agent lives in the global OpenCode agents directory. It is a `mode: primary` agent with a system prompt that requires `agent_spinner` before any delegation, a `subagent` allow rule, and `steps: 200`. It appears in the same agent picker as Build and Plan and is not the default.
- OpenCode treats Build and Plan as built-in primary agents, not as a hard-coded mode list. A custom primary agent is the supported extension point: `mode: primary`, an optional `system` prompt, `permissions`, and `steps`. The docs' Agents page and the config schema's `Config.AgentEncoded` define the shape.
- The user wants to try the agent before enforcing it with a prompt hook or moving it into the plugin. This task is the promotion decision after that trial, not the hook.
- The plugin already ships agents under `plugins/ai_dev/agents/`; adding one follows the repo's versioning rules: the component ships at `1.0.0`, the carrying plugin advances its minor component, and both plugin manifests and both marketplace registrations move in lockstep.
- The trial's proof surface is a tracked record, not a gitignored eval run. `tests/agent_spinner/RUNBOOK.md` already holds recorded measurements and is the natural home.

## Approach

1. Run the inline `spin` agent on three jobs: a per-artifact fan-out audit, a serial implement/audit loop over one task, and a read-only corpus sweep. For each, record whether it loaded `agent_spinner` before the first spawn, ran `init --probe`, wrote a phase plan, routed checks through `auto_checker_spinner`, and reached a clean `close`.
2. Record the three runs in `tests/agent_spinner/RUNBOOK.md` under a `## Spin agent trial` heading: date, model, job, the five checks, and the outcome. Name each failure with the session id or the ledger state that shows it.
3. When at least two of the three runs hold all five checks, add `plugins/ai_dev/agents/spin.md` with `mode: primary`, the system prompt from the trial copy, and the same permissions. Add the agent to `plugins/ai_dev/README.md`'s agent list, bump the plugin's minor version in both `plugin.json` files and both marketplace registrations, and ship the agent at `1.0.0`.
4. When fewer than two runs hold, leave the inline copy in place, record the failures, and hand the task to `task_finish` as `deferred` with the trial record as the reason. Do not add a prompt hook; the hook is a later decision.
5. Run `make lint` after the edit and, when the plugin version moves, `make test` for the deterministic gate.

**Out of scope:** a prompt hook or any harness-level enforcement; the user is trialling the agent first. Also out of scope: making `spin` the default agent, which would over-trigger on every prompt.

## Acceptance

- `tests/agent_spinner/RUNBOOK.md` carries a `## Spin agent trial` section with three runs, each naming the five checks and the outcome.
- When promoted, `plugins/ai_dev/agents/spin.md` exists with `mode: primary`, the agent appears in `plugins/ai_dev/README.md`, both plugin manifests and both marketplace registrations carry the bumped version, and `make lint` passes.
- When deferred, the task is archived as `deferred` and the RUNBOOK section names the failing checks and the session or ledger evidence for each.
- `make test` passes after the change.
