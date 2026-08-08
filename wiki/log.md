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

- Domain: [to be configured in SCHEMA.md]
- Structure created with SCHEMA.md, index.md, log.md, raw/, entities/, concepts/, comparisons/, queries/, summaries/, procedures/

## [2026-08-08] update | Schema configured for the ai-modules domain

- SCHEMA.md: domain set to the repository's own knowledge plus the cross-harness research, with the travels-or-not test for what stays out; tag taxonomy set to 21 tags across harnesses, artefacts, mechanisms, and meta

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

The earlier migration worked from the skill body alone, so the decision record
behind the six output-style tasks was missing. Read from the session transcripts
and filed.

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

The session's own durable output was the routing rule for where knowledge goes
and the method for splitting an artefact without losing any, neither of which was
on a page. `procedures/` was empty, and the index page count had gone stale.

- procedures/deciding-where-knowledge-belongs.md
- procedures/splitting-a-shipped-skill.md
- summaries/ai-modules-repository.md (sharpened the guardrail-versus-wiki
  distinction to constrain versus inform, same audience)
- index.md (procedures section populated, total corrected to 20)

## [2026-08-08] update | Two inaccuracies in the repository description, plus the deploy script's status

Challenged on whether the description is accurate about the deploy script.
Checked against the code: it is 1,911 lines, 40 functions, and three generators.

- summaries/ai-modules-repository.md ("nothing here is an application" was
  imprecise and is now scoped to end-user applications; the toolchain paragraph
  repeated the instruction files' shorthand instead of the charter's full
  dependency list, and Python carries more executable lines than shell)
- concepts/deployment-model.md (what the script has become, the format-bridge
  test that keeps it a helper, and the install-path divergence risk)

## [2026-08-08] update | Audit pass: Codex delivery-route contradiction and four smaller repairs

Cross-checked every page against the task records, the deployment README, and
the measured code. One genuine contradiction: the delivery-design table gave
Codex the marked-block route the session had explicitly overruled in favour of
the synthesized `model_instructions_file` replacement, contradicting both the
Codex task and the page's own exception paragraph. Fixed against the task record
as the authoritative decision; no contested flag, since this was an authoring
error rather than a source conflict.

- concepts/output-style-delivery-design.md (Codex row corrected to the
  synthesized route, OpenCode row marked decision-open per its task, marked
  block rescoped to Antigravity with Codex named as the rejected taker)
- comparisons/system-prompt-substitution-across-harnesses.md (`.agents/rules/`
  removed from Antigravity's global-deploy cell; it is project scope)
- concepts/hook-surface-portability.md ("four of the six implement hooks"
  contradicted the deploy script, which already writes Cursor and Copilot hook
  files; rescoped to worked-out contracts versus unfinished coverage)
- summaries/ai-modules-repository.md (Python-versus-shell line-count claim was
  false repo-wide; scoped to the plugins tree with the deploy script named as
  the difference)
- entities/openai-codex.md (recovered the dropped fact that a relative path in
  a project configuration resolves against its own `.codex/` directory)
