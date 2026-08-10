# Wiki Index

> Content catalog. Every wiki page listed under its type with a one-line summary.
> Read this first to find relevant pages for any query.
> Last updated: 2026-08-10 | Total pages: 27

## Entities

<!-- Alphabetical within section -->

- [Anthropic Claude Code](entities/anthropic-claude-code.md) — configuration roots, agent frontmatter tolerance, hooks, safe mode, and the retired activation routes.
- [Cursor](entities/cursor.md) — rules as the whole instruction mechanism, agent fields, and the undocumented home-directory rules folder.
- [GitHub Copilot in VS Code](entities/github-copilot-vs-code.md) — one user root shared with the CLI, instruction roots, the preview hook contract, deep adoption of the Claude tree, custom agents, and preview plugins.
- [Google Antigravity](entities/google-antigravity.md) — the `.agents/` workspace tree, skills and subagents, the hook contract and its SDK second surface, rules and workflows, and four open verification gaps.
- [OpenAI Codex](entities/openai-codex.md) — configuration layers, TOML agent roles, the single instructions slot, personalities, profiles, and hook trust.
- [SST OpenCode](entities/sst-opencode.md) — its own config tree, foreign-directory discovery, pass-through frontmatter, prompt assembly, and code-only hooks.

## Concepts

- [Agent definition portability](concepts/agent-definition-portability.md) — three tolerance categories, disjoint tool vocabularies, read-only levers, and when a generated variant is required.
- [Antigravity global configuration roots](concepts/antigravity-global-roots.md) — the two artefact classes that split across its three products, what that costs a global deploy, and the output tree that is not a root.
- [Antigravity tool vocabulary](concepts/antigravity-tool-vocabulary.md) — the two incomplete name lists, the missing canonical registry, and why a wrong name hangs instead of failing.
- [Claude output styles](concepts/claude-output-styles.md) — the two-layer system prompt, the two delivery modes, activation, plugin bundling, and the strict four-key frontmatter.
- [Foreign directory adoption](concepts/foreign-directory-adoption.md) — which harnesses read another's config tree, why that is contamination rather than delivery, and the isolation switches.
- [Guardrail documents as normative rules](concepts/guardrail-documents-as-rules.md) — presence-gated lookup, optional adoption, the description misreading, the three paths to true, and the guarding/describing split.
- [Hook surface portability](concepts/hook-surface-portability.md) — four configuration schemas plus one that is code, four signalling contracts, additive layers, and what this repository ships and routes today.
- [Output style delivery design](concepts/output-style-delivery-design.md) — the decision record behind the `styles/` source, the per-target delivery matrix, the marked-block write, and the scope rejections.
- [Plugin packaging and versioning](concepts/plugin-packaging-and-versioning.md) — why two manifests, the lockstep version contract, where a missed bump surfaces, and the two distribution options.
- [Skill family architecture](concepts/skill-family-architecture.md) — naming by invocation mode, rules living once in the base skill, bundled scripts, the cost of a large skill body, and the checker that reads those rules rather than restating them.
- [The deployment model](concepts/deployment-model.md) — two discovery roots, per-tool configuration, generated variants, scope precedence, and the prior-value restore on uninstall.
- [Verification surfaces for a shipped skill](concepts/verification-surfaces.md) — script tests against behavioral evals, harnesses that never ship, the pinned model under test, and trigger coverage as its own question.

## Comparisons

- [System prompt substitution across harnesses](comparisons/system-prompt-substitution-across-harnesses.md) — the native, synthesizable, and append-only tiers, what each global deploy must write, and the price of synthesis.

## Queries

- [What remains unverified about Google Antigravity?](queries/antigravity-open-verification-gaps.md) — the four open gaps, the evidence behind each, and which one gates a design decision.

## Summaries

- [System prompt substitution experiments](summaries/system-prompt-substitution-experiments.md) — an unrun programme testing this repository's authoring rules against vendor base prompts.
- [The ai-modules repository](summaries/ai-modules-repository.md) — what the repository is, what it ships, its toolchain and conventions, and where this wiki sits beside its other document sets.

## Procedures

- [Deciding where knowledge belongs](procedures/deciding-where-knowledge-belongs.md) — the three genres, their three homes, and the travels-or-not test that routes between them.
- [Isolating Cursor from foreign harness config](procedures/isolating-cursor-from-foreign-config.md) — the one settings toggle, how to confirm it in the state database, and what it takes away with the skills.
- [Isolating OpenCode from foreign harness config](procedures/isolating-opencode-from-foreign-config.md) — picking the narrowest variable, and the three placements that reach a GUI application when a shell profile cannot.
- [Isolating VS Code from foreign harness config](procedures/isolating-vs-code-from-foreign-config.md) — per-path location maps, the agent switch, and the separate lever for the aggregated session list.
- [Splitting a shipped skill](procedures/splitting-a-shipped-skill.md) — move the reference material out, audit the split in three directions, and repair the inbound references.
