# Wiki Index

> Content catalog. Every wiki page listed under its type with a one-line summary.
> Read this first to find relevant pages for any query.
> Last updated: 2026-11-21 | Total pages: 39

## Entities

<!-- Alphabetical within section -->

- [Anthropic Claude Code](entities/anthropic-claude-code.md): configuration roots and settings precedence for Claude Code, the standing-instruction pair and its ancestor walk, agent frontmatter tolerance, the file-read guard, hooks, safe mode, and retired surfaces.
- [Cursor](entities/cursor.md): rules and agent surfaces for Cursor, deployed skills shadowing staged copies, Task helper delegation and its return and transcript channels, the goal tools, and the print-mode CLI's shell and stream events.
- [GitHub Copilot in VS Code](entities/github-copilot-vs-code.md): one user root shared with the CLI, instruction roots, the preview hook contract, deep adoption of the Claude tree, custom agents with effort only as a global setting, and preview plugins.
- [Google Antigravity](entities/google-antigravity.md): the `.agents/` workspace tree, skills and subagents, the hook contract and its SDK second surface, rules and workflows, and four open verification gaps.
- [OpenAI Codex](entities/openai-codex.md): config layers and project trust, the off-PATH CLI binary, TOML agent roles, sub-agent and goal tools, codex exec, the single instructions slot, and hook trust.
- [SST OpenCode](entities/sst-opencode.md): config tree, foreign-directory discovery, the V1-to-V2 frontmatter boundary, a `permissions` list whose `shell` replaced `bash`, helper model inheritance, prompt assembly, and code-only hooks.

## Concepts

- [Agent definition portability](concepts/agent-definition-portability.md): three frontmatter tolerance categories, disjoint tool vocabularies, the read-only role and session levers with their observed reach, and when a generated variant is required.
- [Agent-delegated automation](concepts/agent-delegated-automation.md): how the repo runs whole-artifact jobs through front-end skills and spawned agents: read fan-out, one serialized writer, refute-by-default checks, frozen intent, human-routed forks, and the shipped agent_spinner form.
- [Antigravity global configuration roots](concepts/antigravity-global-roots.md): the two artefact classes that split across its three products, what that costs a global deploy, and the output tree that is not a root.
- [Antigravity tool vocabulary](concepts/antigravity-tool-vocabulary.md): the two incomplete name lists, the missing canonical registry, and why a wrong name may hang instead of failing.
- [Claude Code delegation surfaces](concepts/claude-delegation-surfaces.md): how Claude Code's Workflow, Agent, shell, and print-mode CLI surfaces delegated to helpers in 2026 probes, with the pool ceiling, schema-bound returns, resume and stop, and the CLI flags and stream events.
- [Claude output style selection](concepts/claude-output-style-selection.md): how the outputStyle key is chosen: its precedence, headless project selection, interactive routes that all write local scope, next-message switching, the retired and restored command, and the desktop route.
- [Claude output styles](concepts/claude-output-styles.md): the two-layer system prompt and the append flag beside it, the two delivery modes, file locations, plugin bundling, and the four-key frontmatter the loader checks without enforcing.
- [Foreign directory adoption](concepts/foreign-directory-adoption.md): which harnesses read another's config tree, why that is contamination rather than delivery, and the isolation switches.
- [Guardrail documents as normative rules](concepts/guardrail-documents-as-rules.md): presence-gated lookup, optional adoption, the description misreading, the three paths to true, and the guarding, describing, and directing registers.
- [Hook delivery design](concepts/hook-delivery-design.md): the shared-script layout, the uneven per-target deploy routing with its entry-grain hook merge, the foreign hook files Copilot parses, and the decision to deliver Copilot natively.
- [Hook surface portability](concepts/hook-surface-portability.md): four configuration schemas plus one that is code, four signalling contracts, additive layers, and guarantees that vary with the interception point.
- [Instruction-defect classes](concepts/instruction-defect-classes.md): three instruction defects that pass review and fail at runtime (reach, disposition, intra-file contradiction) and the measured limit where repair must give way to a mechanism.
- [Interpreter and tool-path portability](concepts/interpreter-and-tool-path-portability.md): the interpreter floor for bundled scripts and agent-run snippets: stock macOS bash 3.2.57, python3 3.9.6, the login-shell PATH trap, the constructs that fail, and zsh pitfalls.
- [Orchestration failure families](concepts/orchestration-failure-families.md): the run evidence behind agent_spinner's recipes: 23 failure families with counts and base rates, 16 cases, per-recipe family sets, and the families each protocol step answers.
- [Output style delivery design](concepts/output-style-delivery-design.md): the decision record behind the `styles/` source, the per-target delivery matrix including Cursor's project-only `.mdc` write, the marked-block write, and the scope rejections.
- [OpenCode plugin loading](concepts/opencode-plugin-loading.md): how OpenCode 2 loads a plugin from a directory or the plugins array, why options arrive only through the array, and why a deployed package needs no node_modules.
- [Request concurrency queue](concepts/request-concurrency-queue.md): the OpenCode 2 admission scheduler: one process-wide per-provider gate over concurrency, token budget, context, and a circuit breaker, its config precedence and reload registry, and the status bar over a shared RPC.
- [Plugin packaging and versioning](concepts/plugin-packaging-and-versioning.md): why two manifests, the lockstep version contract, where a missed bump surfaces, and the two distribution options.
- [Skill family architecture](concepts/skill-family-architecture.md): how a skill family names members by invocation mode, keeps family rules once in the base skill, bundles scripts, and is audited by a checker whose severity lines come from the harness.
- [Skill load paths](concepts/skill-load-paths.md): what makes a skill load and route on Claude Code and Codex, read out of installed builds and confirmed for a Codex project skill by a live probe, and which repository rules are convention rather than harness constraint.
- [Task lifecycle and status rules](concepts/task-lifecycle-and-status-rules.md): the task_* family's lifecycle: who writes each status, when ready returns to checked, task_implement's admission and done-gate, re-audit re-open, follow-up limits, and archive rules.
- [The deployment model](concepts/deployment-model.md): three discovery roots, per-tool configuration, generated variants, scope precedence, the log-driven update replay, scope-limited uninstall, the prior-value restore on uninstall, and the entry-grain hook merge beside it.
- [Verification surfaces for a shipped skill](concepts/verification-surfaces.md): how a shipped skill is verified: script tests as the default, opt-in behavioral evals, committed but undeployed harnesses, pinned model and effort, isolated workers, trigger coverage, and grader design.

## Comparisons

- [System prompt substitution across harnesses](comparisons/system-prompt-substitution-across-harnesses.md): the native, synthesizable, and append-only tiers, what each global deploy must write including Cursor's project-only file path, and the price of synthesis.

## Queries

- [What remains unverified about Google Antigravity?](queries/antigravity-open-verification-gaps.md): the four open gaps, the evidence behind each, and which one gates a design decision.

## Summaries

- [System prompt substitution experiments](summaries/system-prompt-substitution-experiments.md): an unrun programme testing this repository's authoring rules against vendor base prompts.
- [The ai-modules repository](summaries/ai-modules-repository.md): what the repository is, what it ships, its toolchain and conventions, and where this wiki sits beside its other document sets.

## Procedures

- [Deciding where knowledge belongs](procedures/deciding-where-knowledge-belongs.md): the three genres, their homes, and the travels-or-not test that routes between them.
- [Isolating Cursor from foreign harness config](procedures/isolating-cursor-from-foreign-config.md): the one settings toggle, how to confirm it in the state database, and what it takes away with the skills.
- [Isolating OpenCode from foreign harness config](procedures/isolating-opencode-from-foreign-config.md): picking the narrowest variable, and the three placements that reach a GUI application when a shell profile cannot.
- [Install a local OpenCode plugin](procedures/install-a-local-opencode-plugin.md): deploying a plugin package into the OpenCode plugin discovery root, the config-file channel a deployed directory needs, the restart requirement, and the manual `.ts` entry fallback.
- [Isolating VS Code from foreign harness config](procedures/isolating-vs-code-from-foreign-config.md): per-path location maps, the agent switch, and the separate lever for the aggregated session list.
- [Splitting a shipped skill](procedures/splitting-a-shipped-skill.md): move the reference material out, audit the split in three directions, and repair the inbound references.
