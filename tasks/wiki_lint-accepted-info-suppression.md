---
description: Give lint.py a per-finding acknowledge mechanism so accepted info-level findings stop re-surfacing every run and being re-justified in prose and the log.
scope: plugins/knowledge_management
created: 2026-05-28T20:05:29
updated: 2026-05-28T20:05:29
status: open
---

# Let the wiki owner acknowledge accepted info-level lint findings

## Goal

A wiki owner can mark a specific info-level lint finding as reviewed-and-accepted, after which it drops out of subsequent lint runs (or is clearly marked as acknowledged) instead of re-appearing every time. This ends the per-run loop where the agent re-reads the same accepted findings, writes a fresh justification paragraph, and records the same rationale in the log on every audit.

## Context

`lint.py` emits info-level findings for conditions that are often intentional and accepted by the wiki owner — `confidence: low` frontmatter, pages over the 200-line soft cap ([skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) `check_page_size`), and taxonomy tags defined but unused (`check_unused_tags`). These re-surface on every run because there is no way to acknowledge an individual finding. The only suppression today is `--quiet` (argparse around line 1204), which hides **all** info indiscriminately — too blunt, so it goes unused, and instead each audit re-litigates the same accepted findings in prose and adds another near-identical log entry. The info count creeps upward across a session purely from this churn.

This is the *general* per-finding accept mechanism. A narrower, type-based mechanism for the specific case of expected page growth is being designed separately in [wiki_page-type-growth-and-anatomy.md](wiki_page-type-growth-and-anatomy.md) (a `growth:` declaration per page type that makes the linter defer size findings for backlog/synthesis pages). **Reconcile the two so they do not become competing mechanisms**: the `growth:` declaration handles "this page type is expected to grow"; this task handles "I have reviewed *this specific* finding and accept it" for any info category. Decide whether size acceptance flows through `growth:` (type-level) or through the per-finding accept here (instance-level), and document the boundary.

Files involved:

- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — finding emission and the main runner; `--quiet` (~1204).
- [plugins/knowledge_management/skills/wiki/references/lint_checks.md](../plugins/knowledge_management/skills/wiki/references/lint_checks.md) — document the accept mechanism.
- Target-wiki `SCHEMA.md` template inside the wiki skill bundle, if acceptances are stored there.
- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) and [agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — teach the accept workflow so the agent uses it instead of re-justifying in prose.

## Approach

1. **Pick a storage mechanism for acceptances.** Options, in rough order of preference:
   - An `accepted` list in `SCHEMA.md` frontmatter keyed by `(check, path)` or a stable finding id, reviewed in one place.
   - A page-level marker comment (e.g. `<!-- lint: accept size -->` / `<!-- lint: accept confidence -->`) for findings that are inherently per-page.
   Choose one (or a small combination) and define a stable finding identity so an acceptance keys to the right finding.
2. **Honour acceptances in the runner.** When a finding matches an acceptance, drop it from the active count or move it to a clearly separated "acknowledged" section of the report so it stops inflating the live info count and stops prompting re-justification.
3. **Teach the workflow.** Update SKILL.md and the auto-shaper so that, when an info finding is intentional, the agent records the acceptance via this mechanism **once** — never by writing rationale prose into the page body (that prohibition is owned by [wiki_meta-prose-in-page-bodies.md](wiki_meta-prose-in-page-bodies.md)) and never by appending a fresh log paragraph every run.
4. **Document** the mechanism and its boundary with `growth:` in `lint_checks.md`.

Bump the skill / agent / plugin versions per the one-bump-per-commit rule at commit time.

## Acceptance

- A fixture info finding marked accepted via the chosen mechanism does not appear in the live finding count on the next run (or appears only under an "acknowledged" section).
- An *unaccepted* info finding still appears normally.
- The boundary between this per-finding accept and the type-level `growth:` deferral is documented; the two do not double-handle page-size findings.
- SKILL.md / auto-shaper instruct recording acceptance through this mechanism rather than prose or repeated log entries.
- `make lint` clean; `tests/wiki/run_all.sh` passes.
