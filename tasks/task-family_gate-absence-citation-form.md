---
description: "Give auto_gate_task a citation form for a content-lens item cleared because something is absent, which the citation verifier can keep, so a clean task can pass the immediate-ready refutation."
scope: plugins/ai_dev/agents
created: 2026-11-15T10:49:59Z
updated: 2026-11-17T10:06:07Z
status: open
reported-by: Andreas Hoffmann
---

# Give the gate a citation form for absence claims the verifier can keep

## Goal

When `auto_gate_task` clears a content-lens item because the task body holds no instance of what the lens looks for, its `## Checklist` line cites the sections it read in full and names what it looked for. `auto_verifier_task`'s citation mode keeps that claim when the named sections, read in place, hold no instance, and refutes it when they hold one or name fewer sections than the item covers. A task that is clean on first read can then pass `task_auto_check`'s immediate-ready refutation.

## Context

All agent paths are under `plugins/ai_dev/agents/`.

- **The gate can cite only a span.** The `## Checklist` template in `auto_gate_task.md` gives a cleared content-lens line one form: `clean — cited: <artifact read> :: "<verbatim span that settled the item>"`. Its walk rule keeps "the citation to that pointer plus the span it turns on" and adds that existence checks "never on their own clear the content lens".
- **The verifier refutes existence spans.** The citation-mode rule in `auto_verifier_task.md` refutes a claim whose span "establishes only an existence fact for an item the gate's own contract holds that existence checks cannot clear".
- **Absence claims have no span.** Several base `<readiness_checklist>` lenses in `plugins/ai_dev/skills/task/SKILL.md` clear only when the body lacks something, such as **Restated standing rules**, **Rule-waiving exclusions**, and **Sensitive or user-specific detail**. No single verbatim span shows that something is absent, so the gate cites a span that exists, and the verifier refutes it under the rule above.
- **Evidence.** Runs of `immediate_ready_citations_survive` on both vendors on 2026-11-15 show the gap:
  - A Cursor run refuted 8 citations.
  - After the fixture fix, a later Cursor run still refuted the three absence lenses above. Their spans were a `CLAUDE.md` line, the `## Approach` heading, and the Goal sentence, and each refutation reason says the span shows only that something exists.
  - A Claude run, on the fixed fixture, refuted the same three lenses. Its spans were the `CLAUDE.md` line "run the bundled task linter after edits", an Approach sentence about editing `build_throttle_response()`, and the `reported-by` frontmatter field, and its reasons say the first two show only that something exists and the third lies outside the body the item judges.
- **Where citations came from.** [The gate-evidence task](archive/task-family_gate-evidence-and-refutation.md) introduced the citation on every cleared line and the existence rule. This task adds the absence form that task left out.

[The return-layout task](archive/task-family_gate-verifier-return-layout.md) edits the same two agents' output contracts, so land this task after it.

## Approach

1. In `auto_gate_task.md`, add a second cleared form to the content-lens line of the `## Checklist` template for an item cleared on absence: the task path, the section headings read in full, and what the gate looked for and did not find, as in `clean — absent: tasks/<file>.md :: ## Goal … ## Acceptance :: no **Out of scope:** entry`. Rewrite the walk rule's citation sentence in place, so a presence claim keeps the span form and an absence claim takes the new form, covering every section the lens judges.
2. In `auto_verifier_task.md`, rewrite the citation-mode rule in place so it judges an absence citation by reading the named sections in place. It keeps the claim when they hold no instance of what the claim names and refutes it when they hold one or omit a section the lens covers. The existence-fact refutation stays for span citations.
3. In scenario s15 of `tests/task_auto_check/script_tests/run.sh`, add `assert_contains` pins for the new template form and both rewritten rule sentences, and an `assert_not_contains` pin for each sentence they replace.

## Acceptance

1. `auto_gate_task.md`'s template and walk rule carry the absence form beside the span form, and `auto_verifier_task.md`'s citation-mode rule judges it as Approach step 2 describes.
2. `bash tests/task_auto_check/run_all.sh` passes, including the new pins.
3. `immediate_ready_citations_survive` runs on the default vendor, every citation survives, and the verdict is recorded in `tests/task_auto_check/evals/README.md`. If a citation is still refuted, the record names its item and reason, and the task stays open.
