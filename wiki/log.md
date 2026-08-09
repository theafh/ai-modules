# Wiki Log

> Chronological record of wiki changes. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`
> Actions: ingest, update, query, lint, create, archive, delete, audit, import, session-wrapup
> Entries: an operation that creates or updates wiki files appends one entry; an
> operation that changes no file appends none. Lint and audit runs are the
> exception — each records its outcome, including a zero-change one, as a
> process record.
> Body: list only files actually created or updated. Skip files that were
> inspected, considered, or deliberately left unchanged, and do not narrate
> decisions about what not to do. Aim for roughly 20 lines per entry.
> When this file exceeds 500 entries, rotate: rename to log-YYYY.md, start fresh.

## [2026-08-08] create | Wiki initialized

- Structure created with SCHEMA.md, index.md, log.md, raw/, entities/, concepts/, comparisons/, queries/, summaries/, procedures/

## [2026-08-08] update | Schema configured for the ai-modules domain

- SCHEMA.md: domain set to the repository's own knowledge plus the cross-harness research; tag taxonomy set to 21 tags across harnesses, artefacts, mechanisms, and meta

## [2026-08-08] create | Base repository knowledge

- summaries/ai-modules-repository.md
- concepts/plugin-packaging-and-versioning.md
- concepts/skill-family-architecture.md
- concepts/deployment-model.md
- index.md

## [2026-08-08] ingest | Harness research migrated out of the harness_portability skill

Facts moved from the shipped skill body into the wiki, leaving the rules in the
skill. Sources are provider documentation, loader source, and installed builds,
verified July and 7 August 2026 and cited per page.

- entities/anthropic-claude-code.md
- entities/openai-codex.md
- entities/sst-opencode.md
- entities/google-antigravity.md
- entities/cursor.md
- entities/github-copilot-vs-code.md
- concepts/claude-output-styles.md
- concepts/foreign-directory-adoption.md
- concepts/agent-definition-portability.md
- concepts/hook-surface-portability.md
- comparisons/system-prompt-substitution-across-harnesses.md
- index.md

## [2026-08-08] create | System prompt substitution experiment programme

- summaries/system-prompt-substitution-experiments.md
- index.md

## [2026-08-08] update | Antigravity gaps split out to keep the entity page scannable

- queries/antigravity-open-verification-gaps.md (created from the entity page's
  verification-gaps section, which now links to it)
- entities/google-antigravity.md
- entities/sst-opencode.md (bare-URL wording)
- index.md

## [2026-08-08] ingest | Output-style research read from the 7 and 8 August session transcripts

- concepts/output-style-delivery-design.md (source-directory decision, per-target
  delivery matrix, marked-block write, activation marker, scope rejections,
  Claude-first sequencing, and the superseded additive-semantics framing)
- concepts/hook-surface-portability.md (the concrete three-config plugin layout)
- entities/openai-codex.md (prompt subsections, off-path binary, matcher-group
  guidance, project-hook placement)
- entities/sst-opencode.md (no CLI on the machine checked)
- entities/cursor.md (the undocumented rules folder was empty when checked)
- summaries/system-prompt-substitution-experiments.md (reframed to whole-prompt
  rewrite, then before and after, then ablation)
- index.md

## [2026-08-08] session-wrapup | 2 new, 2 extended, 0 contested

- procedures/deciding-where-knowledge-belongs.md
- procedures/splitting-a-shipped-skill.md
- summaries/ai-modules-repository.md (guardrail-versus-wiki distinction sharpened
  to constrain versus inform, same audience)
- index.md (procedures section populated, total corrected to 20)

## [2026-08-08] update | Two inaccuracies in the repository description, plus the deploy script's status

- summaries/ai-modules-repository.md ("nothing here is an application" scoped to
  end-user applications; toolchain paragraph corrected against the charter's full
  dependency list rather than the instruction files' shorthand)
- concepts/deployment-model.md (what the script has become, the format-bridge
  test that keeps it a helper, and the install-path divergence risk)

## [2026-08-08] update | Audit pass: Codex delivery-route contradiction and four smaller repairs

Cross-checked every page against the task records, the deployment README, and the
code. The delivery-design table gave Codex a marked-block route the Codex task had
overruled in favour of the synthesized replacement; fixed against the task record
as the authoritative decision.

- concepts/output-style-delivery-design.md (Codex row corrected to the
  synthesized route, OpenCode row marked decision-open per its task, marked
  block rescoped to Antigravity with Codex named as the rejected taker)
- comparisons/system-prompt-substitution-across-harnesses.md (`.agents/rules/`
  removed from Antigravity's global-deploy cell; it is project scope)
- concepts/hook-surface-portability.md (harness coverage rescoped to worked-out
  contracts versus unfinished coverage)
- summaries/ai-modules-repository.md (Python-versus-shell claim scoped to the
  plugins tree with the deploy script named as the difference)
- entities/openai-codex.md (recovered the dropped fact that a relative path in
  a project configuration resolves against its own `.codex/` directory)

## [2026-08-09] update | Prior-value capture shipped, so five pages left the gap framing

The Claude output-style groundwork landed: a second discovery root at repo-root
`styles/`, a `style:<name>` configuration directive, and first-write prior capture
on the shared key-merge function with a restore on uninstall.

- concepts/deployment-model.md (discovery rewritten to two roots, `style:` added
  to the configuration directives, missing-prior section replaced by the
  recorded-prior restore with its legacy four-field and success-check provisions,
  and the Claude-only style type added to the open target-matrix holes)
- concepts/claude-output-styles.md (scope question settled for Claude at both
  scopes and left open for the three project-native harnesses; deployment-model
  link repointed at the shipped restore)
- concepts/output-style-delivery-design.md (Claude row marked as the only one
  built; why-Claude-went-first records that the shared-machinery bet paid out)
- summaries/system-prompt-substitution-experiments.md (experiment teardown now
  inherits the capture instead of waiting on it)
- summaries/ai-modules-repository.md (`styles/` added to the repo-root list)
- index.md (deployment-model summary line and date)

## [2026-08-09] lint | 0 blocking, 0 warn, 1 info

The one info is the over-threshold size of `entities/google-antigravity.md`.

## [2026-08-09] update | Pre-publish pass: one contradiction, one unsourced cap, two tag gaps, and the build fingerprints

Reviewed for publish safety and internal consistency. The activation
contradiction and the character cap were settled against
`antigravity.google/docs/rules-workflows`: the cap is stated for rules files
without exempting the global file, and the four activation modes are documented
for workspace rules only. Build numbers read off installed applications were
generalised to the date they were checked.

- comparisons/system-prompt-substitution-across-harnesses.md (Antigravity
  activation cell corrected from "Always On activation mode" to none, and the
  reach paragraph rewritten so the cap covers the global deposit)
- entities/google-antigravity.md (rules section rewritten so it sources the cap
  for both scopes and confines the activation modes to workspace rules)
- concepts/foreign-directory-adoption.md (`verification-gap` tag added)
- concepts/agent-definition-portability.md (`verification-gap` tag added)
- entities/anthropic-claude-code.md, concepts/claude-output-styles.md,
  entities/sst-opencode.md, entities/openai-codex.md (installed-build numbers
  replaced by the date checked)

## [2026-08-09] update | Antigravity page compacted rather than split

- entities/google-antigravity.md (overview scoped to what the repository deploys,
  the workspace-tree collision compacted onto the adoption page, sidecars reduced
  to the scope boundary)

## [2026-08-09] update | Single-owner pass on the duplicated harness facts

The rule applied throughout: the page that owns the subject keeps the perishable
detail, and a cross-cutting page keeps the consequence and links.

- entities/anthropic-claude-code.md (safe-mode annotation string and the
  style-collision rule handed to the styles page, consequences kept)
- summaries/system-prompt-substitution-experiments.md (Codex apparatus reduced to
  what the experiment needs, command and off-path caveat left to the entity page)
- procedures/deciding-where-knowledge-belongs.md (the duplication pitfall now
  covers page-to-page as well as home-to-home, and derivations get a filing type)

## [2026-08-09] session-wrapup | 1 new, 2 extended, 0 contested

A session applying the guardrail doc set to a Rust project produced the reasoning
behind a set of rules now filed against the `guardrail` family. The rules go to
the skill because they travel; the derivation lands here.

- concepts/guardrail-documents-as-rules.md (new: the lookup mechanism, optional
  adoption, the read-as-description misreading, the three paths by which a rule
  becomes true, why a rule carries nothing perishable, the guarding/describing
  split, and rule placement across the docs)
- summaries/ai-modules-repository.md (the harness-loads claim corrected to the
  lookup, and the contrast rewritten onto constrain-in-flight versus
  inform-on-research)
- index.md (new concept listed, total pages 20 to 21)

## [2026-08-09] audit | Pre-publish repair: framing, drifting numbers, confidence, hook state, and a log compaction

Repository going public, so the schema's purpose statement was rewritten and every
page re-read for content that decays or does not belong in a public repo. Line
counts, file sizes, token estimates, per-model prompt lengths, and version pins
restated away from their owning page were removed in favour of the property each
was standing in for. Confidence was re-rated against a new evidence rule and now
tracks each page's weakest load-bearing claim. Earlier log entries were compacted
in place, dropping narration of rejected alternatives and stale measurements.

- SCHEMA.md (domain rewritten as project memory for the agents working here, with
  the maintenance obligation, the division against guardrails and tasks, and the
  three exclusion classes; confidence given an evidence rule)
- concepts/hook-surface-portability.md (new section stating what ships and what
  the deploy actually routes per target, including Copilot's unfiltered deposit;
  open questions rewritten onto the three unsettled coverage decisions)
- concepts/deployment-model.md (hook-merge claim scoped to the targets a shipped
  file reaches, script size stated as a property)
- entities/openai-codex.md (per-model prompt lengths, model identifiers, and
  template filenames replaced by the read route and the re-derivation rule)
- entities/sst-opencode.md (vendor-prompt lengths and heading enumerations
  replaced by the two read routes and their costs; confidence raised to high)
- entities/cursor.md (confidence raised to high)
- concepts/foreign-directory-adoption.md (confidence lowered to medium, capping
  claim named; OpenCode version pin left to its owning page)
- concepts/agent-definition-portability.md (same, for the pending Antigravity
  tolerance classification)
- queries/antigravity-open-verification-gaps.md (confidence raised to high, with
  the caveat section splitting the report from the answers)
- comparisons/system-prompt-substitution-across-harnesses.md (Antigravity cap
  restatement replaced by consequence and link)
- concepts/output-style-delivery-design.md (cap number dropped from the table)
- concepts/claude-output-styles.md (loader byte limit dropped)
- concepts/skill-family-architecture.md (skill size stated as a property)
- concepts/plugin-packaging-and-versioning.md (open question rewritten onto the
  two distribution options)
- summaries/ai-modules-repository.md (line-count comparison stated as a property)
- summaries/system-prompt-substitution-experiments.md (prompt sizes dropped)
- log.md (entries compacted)
- raw/*/.gitkeep (five markers so the source tree survives a clone)
- index.md
