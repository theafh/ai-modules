---
description: Run the delegation probes on Codex and OpenCode, record them in harness_portability and the wiki, add eval vendors where a headless CLI allows, and run the agent_spinner suite there.
scope: plugins/ai_dev/skills/harness_portability
created: 2026-10-03T15:54:08
updated: 2026-10-04T15:20:11
status: deferred
reported-by: Andreas Hoffmann
---

# Probe Codex and OpenCode delegation, add their eval vendors, and run the agent_spinner suite on them

## Goal

Codex and OpenCode get the same delegation record that Cursor and Claude Code get. Every probe in harness_portability's delegation reference runs on each of them, together with five probes these hosts raise, and each result lands in `references/delegation-surfaces.md` and the wiki with its date, build, and source kind.

Each host whose headless CLI can run an eval worker gets a vendor entry in `tests/lib/vendor.py`, offered to agent_spinner's eval runner. The agent_spinner suite then runs there once, and its result is recorded on the host's wiki page. A host without such a CLI is recorded with that gap and what would close it.

## Context

- **Deferred on 2026-10-04.** The owner set the rule that no task exists to probe how a host behaves, and agent_spinner spawns helpers only as sub-agents. Probe runs on 2026-10-04 settled the Codex questions instead, and the wiki and the delegation-surfaces task now carry Codex's sub-agent facts. Running the eval suite on Codex through `codex exec` was this task's remaining purpose, so it stays parked unless the owner wants Codex as a third test vendor. OpenCode had no command-line tool installed.
- **Codex, read on 2026-10-04.** `codex-cli 0.160.0` ships inside the ChatGPT desktop application bundle at `Contents/Resources/codex-cli/bin/codex` and resolves on no PATH. `wiki/entities/openai-codex.md` still gives the bundle location read on 13 August 2026, `Contents/Resources/codex`, which no longer holds a binary. The help text of `codex exec`, the non-interactive mode, lists:
  - the `resume`, `fork`, and `review` subcommands;
  - `-m`/`--model`, `-p`/`--profile`, `-c key=value` overrides, and `--enable`/`--disable` feature switches;
  - `-s`/`--sandbox` with `read-only`, `workspace-write`, and `danger-full-access`, plus `--dangerously-bypass-approvals-and-sandbox`;
  - `-C`/`--cd`, `--add-dir`, `--worktree`, `--skip-git-repo-check`, `--ephemeral`, and `--ignore-user-config`;
  - `--output-schema <FILE>`, `--json` for JSONL events, and `-o`/`--output-last-message <FILE>`.

  These rest on the help text alone.
- **OpenCode, read on 2026-10-04.** The desktop application 1.18.34 is installed. No `opencode` command resolves on PATH, and the application bundle holds no standalone CLI executable.
- **Documented starting points, unverified on this machine.** `wiki/entities/openai-codex.md` records that Codex registers spawnable roles only from TOML files, whose optional keys include `model`, `model_reasoning_effort`, and `sandbox_mode`, and that it has no per-agent tool allowlist. `wiki/entities/sst-opencode.md` records that OpenCode takes a per-agent `model` and a `permission` object whose `edit` key gates every file write. It forwards unrecognised frontmatter to the provider as model options, and its before-hook misses tool calls that task-tool subagents make.
- **The vendor layer today.** `tests/lib/vendor.py` defines `VENDORS`, `_CONFIGS`, `_VENDOR_ROOTS`, and `CLAUDE_ONLY`, and `require_vendor_allowed` rejects only `cursor` for a Claude-only harness. `worker_env`, `build_print_cmd`, `preflight_auth`, and `stage_skill_tree` each branch per vendor, and `tests/lib/test_vendor.py` unit-tests the module. The vendor matrix lives in `tests/CLAUDE.md` and `tests/AGENTS.md`, which change in lockstep, and `tests/README.md` names the vendors under "## Vendor switch". TESTING.md's vendor rule picks the worker for behavioural evals, and this task adds vendors without changing that rule.
- **Decision this task implements.** On 2026-10-03 the owner approved proof on each target host, with every per-harness fact kept in harness_portability and the wiki. The approved program names Codex and OpenCode as the two remaining hosts.
- **Prerequisites.** [The delegation-surfaces task](ai-dev_harness-portability-delegation-surfaces.md) creates `references/delegation-surfaces.md`, its host-section layout, and its `## Probe log`, whose headings this task runs on each new host. [The runner-modes task](tests_agent-spinner-runner-modes.md) adds the vendor layer's session helper, the resume branch of `build_print_cmd`, and `stage_agents`. It also adds agent_spinner's resume pre-flight, the `withheld_by` record with its `cli-flag`, `cli-config`, and `declared-absence` values, and the "Second turn", "Staged agents", and "Withheld tools" rows of the vendor tables. This task extends each of those to each new vendor.

## Approach

### Probes

Run the probes through each host's headless CLI. A probe that concerns interactive behaviour, such as completion re-invocation, runs in the host's interactive session when one is available, and otherwise records interactive mode as unverified. Where a host's CLI is still missing at implementation time, ask the user whether to install it before probing that host. If it stays missing, record each probe as unverified for that host, with the missing CLI as what would settle it.

For each host, run every probe under `## Probe log` in `references/delegation-surfaces.md` by the method and the pass observation that heading states. The withheld-delegation probe tries two routes on each new host. It tries a CLI flag that withholds the spawn tool. It also tries a deny entry in the CLI's permission configuration, staged in a scratch sandbox. Record the outcome of each route. Add these five probes as new headings in the probe log, each stating its method and pass observation and naming the hosts it ran on:

- **Return files under the host sandbox.** A helper writes a return file inside the workspace, once under the host's default sandbox mode and once under its read-only mode. Record whether each file appears.
- **Batch semantics.** The parent sends several spawns in one message. Record whether they run concurrently and return together inside the turn.
- **Completion re-invocation.** A background helper finishes after the parent's turn ends. Record whether its completion re-invokes the parent and whether the notice carries the result.
- **Skill-relative script path.** A skill staged in a scratch project's skill root runs its bundled script by a path built from the loaded SKILL.md's directory, under the host's sandbox. Use agent_spinner's `scripts/run_ledger.py --help` where that script exists, and the task skill's `scripts/lint.py --help` otherwise.
- **Role registration and read-only lever.** A role written in the host's native format registers and is callable by name. Record whether its read-only lever blocks writes through both the edit tool and the shell, judged as the read-only lever enforcement heading judges a lever.

Add `## Codex` and `## OpenCode` to the reference, each opening with its builds and holding the same six subsections as the existing host sections. Record each fact with its date, build, and source kind, and state each print-mode CLI entry's documentation gap. Carry host measurements only as the delivery property, whether a notice carries the result, the context window, the context-fill and fixed-load figures, and the largest observed batch.

### Vendor entries

A host qualifies when its headless CLI runs one worker non-interactively, with no approval prompt, inside a given workspace, on a stated model, and prints the worker's final message to standard output. `codex exec` is the candidate today, and OpenCode qualifies once its headless CLI is installed. For each qualifying host, extend `tests/lib/vendor.py`:

- Add the host to `VENDORS` and `_CONFIGS`, naming its worker model by an alias rather than a dated id, per the model policy in `tests/CLAUDE.md`.
- Resolve its binary by feature detection: PATH first, then the location its desktop application ships it in, per harness_portability's rule on a binary that sits off the executable path inside an application bundle. The `--worker-bin` override keeps working.
- Give `build_print_cmd`, `worker_env`, `preflight_auth`, and the session helper a branch whose flags come from the installed help text and a live preflight run, the resumed turn included.
- Give `stage_skill_tree` the host's project skill root and `stage_agents` its agent registration root. Where the host reads agents in a format other than Markdown, `stage_agents` writes a generated variant, per harness_portability's rule on generated variants.
- Make `require_vendor_allowed` reject every vendor other than `claude` for a Claude-only harness.
- Offer a new vendor only to a runner proven on it. A runner opts in through the vendor layer, for example by naming its extra vendors when it adds the vendor arguments. agent_spinner's runner opts in, and every other runner keeps rejecting the new vendor before it starts a worker, with a message naming the vendor.

Add unit checks to `tests/lib/test_vendor.py` for each new vendor: its config defaults, its first-turn and resumed-turn commands, its staging roots, its rejection by a Claude-only harness, and its rejection by a runner that has not opted in. Add the vendor's column to the matrices in `tests/CLAUDE.md` and `tests/AGENTS.md` in one change, filling every row the runner-modes task added, and name the vendor under "## Vendor switch" in `tests/README.md`.

### The agent_spinner runner and suite

Run agent_spinner's resume pre-flight once on each new vendor, and record its date, CLI version, and result in the `## Runner modes` section of `tests/agent_spinner/evals/README.md`. Give the runner's withheld-tool branch a case for each new vendor, following the owner's 2026-10-04 decision that tests run the same way on every vendor. Where the host's withheld-delegation probe found a CLI flag that withholds the tool, pass it on every turn and record `withheld_by` as `cli-flag`. Where that probe found a permission-configuration deny that withholds the tool, stage that configuration inside the eval sandbox and record `cli-config`. Where the probe shows the CLI can withhold the tool neither way, the eval runs identically on every vendor with the absence declared in the prompt, records `declared-absence`, and the gap goes into harness_portability's delegation reference. A mode the host cannot support is recorded in the same section as unsupported for that vendor, citing the probe result that shows why.

Run the full agent_spinner suite once per new vendor with `python3 tests/agent_spinner/evals/run.py --vendor <name>`. The recorded run is the deliverable, whatever its pass rate. Through the wiki skill family, record it on the host's entity page: the date, the CLI build, the worker model, the passed and failed eval ids, and one class per failure. The classes are host capability absent, runner mode unsupported, and skill defect. File one task through the task family for each skill defect.

### The wiki

Through the wiki skill family, record the probe results on `wiki/entities/openai-codex.md` and `wiki/entities/sst-opencode.md`, each with its date, build, and source kind. Rewrite the Codex page's passage on where the binary ships so it states the current location with its date.

**Out of scope:**

- Installing a missing host or CLI, which stays with the user.
- Probing Google Antigravity or GitHub Copilot in VS Code, since the approved program covers Codex and OpenCode.
- Fixing a skill defect that an eval run surfaces.
- Proving other skills' eval suites on the new vendors.
- Trigger evals on the new vendors, which [the Cursor trigger-evals task](tests_trigger-evals-cursor-vendor.md) owns.

## Acceptance

- `references/delegation-surfaces.md` holds `## Codex` and `## OpenCode`, each opening with its builds and holding the six host subsections.
- Every heading under `## Probe log` records Codex and OpenCode as established, absent, or unverified, with the build and the date, and each unverified result names what would settle it.
- The probe log holds the five new headings Approach names, each stating its method and pass observation and holding results for the hosts it ran on.
- A read of the reference and the touched wiki pages finds no session count, per-session latency, writer count, or single-output size.
- The Codex and OpenCode wiki pages carry the probe results with dates, builds, and source kinds, written through the wiki skill family. The Codex page states the binary's current location with its date, and no passage there still presents the old location as current.
- For each new vendor, `python3 tests/lib/test_vendor.py` passes with the new checks, and each new check fails on a scratch copy of `vendor.py` with that vendor's branch removed.
- For each new vendor, agent_spinner's runner accepts `--vendor <name>`, and a runner that has not opted in, such as `tests/git_commit/evals/run.py`, rejects it before any worker starts, naming the vendor.
- For each new vendor, `preflight_auth` passes against a live login, and the vendor matrices in `tests/CLAUDE.md` and `tests/AGENTS.md` carry an identical column for it with every row filled, which `tests/README.md` names under "## Vendor switch".
- The `## Runner modes` section of `tests/agent_spinner/evals/README.md` records each new vendor's resume pre-flight with its date, CLI version, and result, and names each mode that vendor cannot support with the probe result that shows why.
- A run of an eval that withholds a tool on each new vendor records `withheld_by` as `cli-flag`, `cli-config`, or `declared-absence`, matching that host's withheld-delegation probe result. A `declared-absence` result has its gap recorded in `references/delegation-surfaces.md`.
- The agent_spinner suite ran once on each new vendor. The host's wiki page records the date, the build, the worker model, the passed and failed eval ids, and each failure's class, and each skill-defect failure has its own task file in `tasks/`.
- A host without a qualifying headless CLI has no vendor entry, and its reference section and wiki page state the gap and what would close it.
- Before commit, a manual read of every changed shipped file, every changed wiki page, and this task's own diff finds no session, company, or project name, and no denylist is committed.
