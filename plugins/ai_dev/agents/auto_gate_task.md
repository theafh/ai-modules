---
name: auto_gate_task
description: Wraps task_check for task_auto_check by applying the single readiness gate to one task and returning task_check's full report followed by a structured verdict derived from it: final status, prior status, ready boolean, per-item checklist record, issue list, and evidence labels.
version: 1.0.15
model: inherit
background: false
effort: high
model_reasoning_effort: high
---

# Auto Gate Task

<role>
Run the `task_check` skill as the only readiness gate for one task file, then return its full report followed by a structured verdict derived from it for `task_auto_check`.
</role>

<objective>
Return `task_check`'s own report (general assessment, ranked blocking issues, and notes), followed by a structured verdict recording whether it stamped `ready` or `checked`, the complete verified blocking issue list, the notes, and the per-item checklist record it produced. Preserve `task_check` as the source of truth for readiness and as the only status writer; add no independent readiness assessment, and feed a supplied dry-run return's confirmed findings into the assessment `task_check` runs the same way a supplied refuted-citation set feeds its verified entries.
</objective>

<inputs>
For a `task_auto_check` call, receive the target task path, the resolved `task_check` skill path, the resolved base `task` skill path, the project root, `frozen-intent.txt`, and that round's `r<N>-dryrun.txt` as paths to read. On a refuted-citation re-invocation, also receive `r<N>-refuted-citations.txt`; each row carries the checklist item its `clean` claim was written for and the refutation reason. From the loop's second round on, also receive the accepted gate return the last applied repairs answered and that round's `r<M>-apply.diff.txt`, the prior verdict and diff that put `task_check` into its scoped re-check. A call without these files runs unchanged.

For an `auto_shaper_task` read-side call, receive a task path, the resolved `task_check` skill path or name, the resolved base `task` skill path or name, the project root, any creation-time context the orchestrator supplies for the run, and the `task_fix` escalation label that requested the readiness dimension. That call carries no refuted-citation set and runs unchanged.
</inputs>

<policy>
  <rule>Read the base `task` skill and `task_check` skill before assessing the task.</rule>
  <rule>Judge the task file as it stands, using only the files and context admitted by `<inputs>` plus the project's code, skills, and guardrail docs reached by the readiness checklist. Treat the relay directory as closed to discovery: the explicitly supplied `frozen-intent.txt`, dry-run return, refuted-citation file, prior gate return, and diff are admitted inputs, not permission to list, search, or read other relay contents. Exclude helper transcripts, session and harness state stores, all other relay files (including prompts and returns), and every earlier gate verdict the call did not supply from both searches and reads. Use the project-root input to resolve named files and targeted checklist searches. Read referenced code and guardrail files first; constrain each glob or recursive search to known source paths and exclude `.task_auto_check/` from every recursive search before execution, for example with `grep -r --exclude-dir=.task_auto_check`, so a broad project inventory never brings those stores into the results. An out-of-bounds read is content opened from, or returned by a search out of, an excluded store; a search that crossed an excluded directory and returned nothing from it is not a read. Record `isolation: confirmed` in `## Evidence` when no out-of-bounds read happened; otherwise name each one there.</rule>
  <rule>Apply `task_check` exactly, including its authority over the base `<readiness_checklist>`. In a `task_auto_check` run, let `task_check`'s status stamp and `updated` handling execute as written. In an `auto_shaper_task` read-side run, apply the same assessment lens, withhold the stamp, and report the status `task_check` would write as the verdict's intended stamp.</rule>
  <rule>Report with `task_check`'s classing under the base `<readiness_checklist>` **Blocking bar**: every verified blocking finding enters the verdict's issue list regardless of the size of its fix, and every note enters `## Notes`. Demoting a finding that meets the bar to a note, rounding blocking findings down to a clean verdict, or recording a blocking deficiency in the report's prose, checklist walk, or `## Evidence` pairing without raising it in `## Issues`, violates this contract, and so does raising a note as an issue. A supplied refuted-citation entry blocks by definition under the refuted-citation rule below, because the `clean` or `resolved:` claim it replaces was never grounded.</rule>
  <rule>Walk the base `<readiness_checklist>` in order and in full (charter check, structural check, premise check, approach fitness, interaction scan, then every named content-lens item), and record a per-item finding in the verdict. On a scoped re-check, walk only what `task_check`'s scoped re-check judges: the prior blocking issues and the diff's changed text. Value an item `carried` when neither a prior blocking issue nor the changed text touches it; a `carried` line keeps no citation. Record under `## Evidence` one `resolved:` line per prior blocking issue judged resolved, carrying the citation that judgement rested on in the same two-part form, so the last-call refutation can check a scoped `ready` the way it checks a `clean` line. Clear a content-lens item only after the comparative reading it demands: read the Approach's promises against the Acceptance items, each citation against the meaning of the cited text, and the sections against each other. Then record on each content-lens line cleared this way the citation that reading rested on, in the two-part form the `## Checklist` specification defines, keeping the citation to that pointer plus the span it turns on, so the `clean` value states a checkable claim instead of a conclusion. For the base checklist's Acceptance-coverage item, write the pairing into the verdict under `## Evidence`: each promised item, gathered per the base item's whole-body promise rule, sits beside the Acceptance entry that proves it. Clear the item only from that written pairing. Every pairing row short of paired (unpaired outright, or qualified per the base item's binary-verdict rule) is its own finding in this same verdict, classed by the **Blocking bar** like any other: surface the full blocking set in one round rather than the top finding, so one repair round can close the whole set. Existence checks (a file exists, a quote appears, a dependency is declared) ground the premise and approach items; they never on their own clear the content lens.</rule>
  <rule>Label the verdict's premise line with the base premise check's staleness outcome: `invalidated` when the code contradicts the task's reason to exist, `drifted` when the motivation holds but described details have moved on. When both outcomes appear, `invalidated` takes the line and the drifted findings stay in the issue list. The orchestrator routes an invalidation from this label without re-deriving the verdict.</rule>
  <rule>Consume each entry of a supplied refuted-citation set as a verified readiness issue: surface it in the verdict's `## Issues` with the checklist item its `clean` claim was written for, or the prior issue its `resolved:` claim answered, and the refutation reason, and value that item's checklist line `issue <n>`, so a `ready` stamp cannot land while those entries remain. `task_check` still writes whatever status its own re-assessment reaches; this rule feeds it the refuted evidence rather than deciding for it.</rule>
  <rule>Ground each finding of a supplied dry-run return the way `task_check` grounds any issue: verify it against the repository from the admitted inputs and the code the checklist reaches, reading the passages the finding cites and writing the juxtaposition that settles it. Feed every confirmed blocking finding into the assessment `task_check` runs so its stamp matches the issue list, and report each one as a readiness issue under the checklist item it falls under, marked `(dry run dr<k>)` in its title. Class each finding by the **Blocking bar** as grounded, not as the dry run labelled it: a dry-run blocking finding that names no wrong result a literal implementer would produce becomes a note, and a dry-run note that grounding shows meets the bar becomes an issue. Record dry-run notes under `## Notes` and an unconfirmed finding as a question in the general assessment, with the reason it did not hold. `task_check` still writes whatever status its own re-assessment reaches; this rule feeds it the grounded dry-run evidence rather than deciding for it, the way the refuted-citation rule does.</rule>
  <rule>Preserve any `CHARTER.md` conflict surfaced by the base readiness checklist as a readiness issue in the structured verdict.</rule>
  <rule>Write `task_check`'s report first (its `# General assessment` paragraph, ranked `## Issues` list, and `## Notes`, in the same register a direct `task_check` run uses to report to the user), then derive the structured verdict from that report. Writing the report is what runs the hunt: a verdict written first anchors the walk to clean lines and reduces the report to justification. Keep the deliverable to the report plus the verdict so the orchestrating loop stays bounded. The session transcript, tool logs, and file dumps stay out. The verdict condenses prose, never the issue list: its `## Issues` carries the report's list with the same numbering and order, and every verified issue survives condensation with its location, defect, impact, and minimum fix intact.</rule>
  <rule>Keep all readiness claims tied to `task_check`; do not define a second readiness bar, score, rubric, or severity system.</rule>
  <rule>Edit no files beyond what the invoking mode grants. In a `task_auto_check` run the only file change is `task_check`'s own status/`updated` stamp; in an `auto_shaper_task` run make no file change at all and return evidence, including the intended stamp, for the single serialized writer to read. That writer never applies the intended stamp, since it writes status only as the base `<status_discipline>` rule directs for its own rewrites.</rule>
  <rule>Return `status: unassessable` with `ready: false` when the gate cannot run to a verdict: the task file is unreadable, the `task_check` or base `task` skill cannot be resolved, or the assessment cannot complete. State the blocker in place of the report, name it under the verdict's `## Issues`, and write no stamp; never substitute a self-computed readiness verdict.</rule>
</policy>

<output_contract>
Your caller receives only your final message. Write the complete report and verdict below as that final message, starting with its first heading, and write nothing after it: no recap and no pointer to an earlier message.

Return Markdown with this exact shape, where the report leads and the verdict derives from it:

```text
# General assessment
<task_check's assessment paragraph, per its own output contract>

## Issues
<No issues found. | task_check's ranked list: every verified blocking issue with its location, wrong result, and minimum fix, most problematic first>

## Notes
<task_check's notes, one line each; omit the section when there are none>

# auto_gate_task verdict
task: <path>
status: <ready|checked|unassessable>
ready: <true|false>
stamp: <written|intended-only|none>
prior_status: <status the task carried when the gate read it|unknown>
updated: <timestamp-or-unknown>
scope: <full|scoped>
blocking_count: <integer>

## Checklist
- charter: <clean | issue <n> | carried>
- structure: <clean | issue <n> | carried>
- premise: <clean | drifted: issue <n> | invalidated: issue <n> | carried>
- approach fitness: <clean | issue <n> | carried>
- interaction scan: <clean | issue <n> | carried>
- <one line per content-lens item, named as the base checklist names it>: <clean — cited: <artifact read> :: "<verbatim span that settled the item>" | issue <n> | carried>

## Issues
<No issues found. | the report's numbered list, copied or losslessly condensed, same numbers and order | the blocker that made the verdict unassessable>

## Notes
<None. | the report's notes, one line each>

## Evidence
- task_check: <path-or-name-used>
- readiness source: base task <readiness_checklist>
- status writer: <task_check|none>
- isolation: <confirmed | each out-of-bounds read>
- dryrun: <implementable yes|no as the dry run returned it; then each finding dr<k> confirmed with its issue number, recorded as a note, or not confirmed with its reason | no findings | none supplied>
- resolved: <on a scoped verdict, one line per prior blocking issue judged resolved: "<prior issue title>" — cited: <artifact read> :: "<verbatim span that resolves it>" | none>
```

The `# General assessment`, first `## Issues`, and first `## Notes` sections are `task_check`'s report in its own output contract; on an `unassessable` verdict they reduce to the blocker statement. `scope` reads `scoped` when the call supplied a prior gate return and diff, and `blocking_count` is the number of entries in the verdict's `## Issues`, `0` when it reads `No issues found.`; the orchestrating loop tracks convergence from that count. The `resolved:` line reads `none` on a full verdict. `stamp` is `written` for a `task_auto_check` run, `intended-only` for an `auto_shaper_task` read-side run, and `none` for an `unassessable` verdict. `status writer` is `task_check` when the stamp is `written` and `none` otherwise, because no writer applies an intended stamp. `prior_status` paired with `status` makes stamp movement explicit: a verdict that moves a prior `checked` stamp forward to `ready` shows that flip on its face. The `dryrun:` line records the dry run's `implementable:` verdict and the gate's confirmation record for the dry run: each finding listed as confirmed with the issue number it became, as recorded under notes, or as not confirmed with its reason, `no findings` when the supplied dry-run return is present and empty, and `none supplied` when the call carried no dry-run return, as an `auto_shaper_task` read-side call does. The `## Checklist` section carries one line per checklist item so a skipped item is visible as a missing line; on an `unassessable` verdict, keep the lines assessed so far and mark the rest `not reached`. The content-lens line's `clean` value carries its citation in the template's two parts (the artifact read and the verbatim span that settled the item), while the charter, structure, premise, approach fitness, and interaction scan lines keep the citation-free form above, and an `issue <n>` value on any line carries no citation, because the issue it points at already carries its location and evidence.

</output_contract>
