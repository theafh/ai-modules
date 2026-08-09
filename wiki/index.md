# Wiki Index

> Content catalog. Every wiki page listed under its type with a one-line summary.
> Read this first to find relevant pages for any query.
> Last updated: 2026-08-09 | Total pages: 21

## Entities

<!-- Alphabetical within section -->

- [Anthropic Claude Code](entities/anthropic-claude-code.md) — configuration roots, agent frontmatter tolerance, hooks, safe mode, and the retired activation routes.
- [Cursor](entities/cursor.md) — rules as the whole instruction mechanism, agent fields, and the undocumented home-directory rules folder.
- [GitHub Copilot in VS Code](entities/github-copilot-vs-code.md) — instruction roots, adoption of the Claude tree, custom agents, and preview plugins.
- [Google Antigravity](entities/google-antigravity.md) — the `.agents/` workspace tree, per-class global roots, hook contract, tool vocabulary, and four open verification gaps.
- [OpenAI Codex](entities/openai-codex.md) — configuration layers, TOML agent roles, the single instructions slot, personalities, profiles, and hook trust.
- [SST OpenCode](entities/sst-opencode.md) — its own config tree, foreign-directory discovery, pass-through frontmatter, prompt assembly, and code-only hooks.

## Concepts

- [Agent definition portability](concepts/agent-definition-portability.md) — three tolerance categories, disjoint tool vocabularies, read-only levers, and when a generated variant is required.
- [Claude output styles](concepts/claude-output-styles.md) — the two-layer system prompt, the two delivery modes, activation, plugin bundling, and the strict four-key frontmatter.
- [Foreign directory adoption](concepts/foreign-directory-adoption.md) — which harnesses read another's config tree, why that is contamination rather than delivery, and the isolation switches.
- [Guardrail documents as normative rules](concepts/guardrail-documents-as-rules.md) — presence-gated lookup, optional adoption, the description misreading, the three paths to true, and the guarding/describing split.
- [Hook surface portability](concepts/hook-surface-portability.md) — three configuration schemas plus one that is code, three signalling contracts, additive layers, and what this repository ships and routes today.
- [Output style delivery design](concepts/output-style-delivery-design.md) — the decision record behind the `styles/` source, the per-target delivery matrix, the marked-block write, and the scope rejections.
- [Plugin packaging and versioning](concepts/plugin-packaging-and-versioning.md) — why two manifests, the lockstep version contract, where a missed bump surfaces, and the two distribution options.
- [Skill family architecture](concepts/skill-family-architecture.md) — naming by invocation mode, rules living once in the base skill, bundled scripts, and the cost of a large skill body.
- [The deployment model](concepts/deployment-model.md) — two discovery roots, per-tool configuration, generated variants, scope precedence, and the prior-value restore on uninstall.

## Comparisons

- [System prompt substitution across harnesses](comparisons/system-prompt-substitution-across-harnesses.md) — the native, synthesizable, and append-only tiers, what each global deploy must write, and the price of synthesis.

## Queries

- [What remains unverified about Google Antigravity?](queries/antigravity-open-verification-gaps.md) — the four open gaps, the evidence behind each, and which one gates a design decision.

## Summaries

- [System prompt substitution experiments](summaries/system-prompt-substitution-experiments.md) — an unrun programme testing this repository's authoring rules against vendor base prompts.
- [The ai-modules repository](summaries/ai-modules-repository.md) — what the repository is, what it ships, its toolchain and conventions, and where this wiki sits beside its other document sets.

## Procedures

- [Deciding where knowledge belongs](procedures/deciding-where-knowledge-belongs.md) — the three genres, their three homes, and the travels-or-not test that routes between them.
- [Splitting a shipped skill](procedures/splitting-a-shipped-skill.md) — move the reference material out, audit the split in three directions, and repair the inbound references.
