---
description: Give lint.py a per-finding acknowledge mechanism so accepted info-level findings stop re-surfacing every run and being re-justified in prose and the log.
scope: plugins/knowledge_management
created: 2026-05-28T20:05:29
updated: 2026-07-04T14:43:36
status: open
reported-by: Andreas Hoffmann
---

# Let the wiki owner acknowledge accepted info-level lint findings

## Goal

A wiki owner can mark a specific info-level lint finding as reviewed-and-accepted, after which it drops out of subsequent lint runs (or is clearly marked as acknowledged) instead of re-appearing every time. This ends the per-run loop where the agent re-reads the same accepted findings, writes a fresh justification paragraph, and records the same rationale in the log on every audit.

## Context

`lint.py` emits info-level findings for conditions that are often intentional and accepted by the wiki owner — `confidence: low` frontmatter, pages over the 200-line soft cap ([skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) `check_page_size`), and taxonomy tags defined but unused (`check_unused_tags`). These re-surface on every run because there is no way to acknowledge an individual finding. The only suppression today is the `--quiet` argparse flag, which hides **all** info indiscriminately — too blunt, so it goes unused, and instead each audit re-litigates the same accepted findings in prose and adds another near-identical log entry. The info count creeps upward across a session purely from this churn.

This is the *general* per-finding accept mechanism. A narrower, type-based mechanism for the specific case of expected page growth is being designed separately in [wiki_page-type-growth-and-anatomy.md](wiki_page-type-growth-and-anatomy.md) (growth-pattern declarations that make the linter defer size findings for backlog/synthesis pages). The boundary, decided: a declared growth pattern defers size findings for a whole page type, while the per-finding accept here covers an individual reviewed finding of any category, including a size finding on a `fixed`-growth page. A third mechanism sits beside both — the SCHEMA `## Lint` section's `Page-check exclusions:` bullet removes whole directories from the page walk rather than suppressing individual findings. Document all three boundaries together.

Storage has an established home: `lint.py` already scans the SCHEMA `## Lint` section fence-safe for labeled bullets (the `Page-check exclusions:` parse, `LINT_EXCLUDE_RE`), and SCHEMA.md carries no YAML frontmatter of its own — so a frontmatter-based acceptance store has nowhere to live, and the acceptance store follows the `## Lint` bullet pattern instead.

Files involved:

- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — finding emission and the main runner; the `--quiet` flag.
- [plugins/knowledge_management/skills/wiki/references/lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md) — document the accept mechanism.
- [plugins/knowledge_management/skills/wiki/references/template_schema.md](../plugins/knowledge_management/skills/wiki/references/template_schema.md) — the `## Lint` section where acceptances are declared and documented.
- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) and [agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md) — teach the accept workflow so the agent uses it instead of re-justifying in prose.

## Approach

1. **Store acceptances in the SCHEMA `## Lint` section.** One labeled bullet per accepted finding (e.g. `- Accepted finding: size — queries/foo.md`), keyed by check bucket plus wiki-root-relative path so each acceptance matches exactly one finding; grammar and fence-safe parsing mirror the `Page-check exclusions:` bullet. Acceptances stay reviewable in one place, and page bodies carry no marker comments.
2. **Honour acceptances in the runner.** When a finding matches an acceptance, drop it from the active count or move it to a clearly separated "acknowledged" section of the report so it stops inflating the live info count and stops prompting re-justification.
3. **Teach the workflow.** Update SKILL.md and the auto-shaper so that, when an info finding is intentional, the agent records the acceptance via this mechanism **once** — never by writing rationale prose into the page body (that prohibition is owned by [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md)) and never by appending a fresh log paragraph every run.
4. **Document** the mechanism and its boundaries with the growth-pattern deferral and the `Page-check exclusions:` walk exclusion in `lint_checks.md`.

## Acceptance

- A fixture info finding marked accepted via the `## Lint` acceptance bullet does not appear in the live finding count on the next run (or appears only under an "acknowledged" section).
- An *unaccepted* info finding still appears normally.
- The boundaries between this per-finding accept, the type-level growth-pattern deferral, and the directory-level `Page-check exclusions:` walk exclusion are documented; the mechanisms do not double-handle page-size findings.
- SKILL.md / auto-shaper instruct recording acceptance through this mechanism rather than prose or repeated log entries.
- `tests/wiki/run_all.sh` passes.
