# task_auto_check behavioral evals

These eval definitions cover the model-mediated behavior of
`task_auto_check`. They use the same Pattern A convention as the other
newer harnesses in this repo: `evals.json` carries prompts and
expectations, and `fixtures/*/setup.sh` stages sandboxes for an agent to
run in.

The deterministic `script_tests/` surface verifies static packaging and
registration. These evals verify loop behavior when a worker actually
loads the skill and operates on staged tasks.

```bash
python3 tests/task_auto_check/evals/run.py
python3 tests/task_auto_check/evals/run.py already_ready repair_to_ready
```

The runner captures each worker transcript and deterministic grade under
`../workspace/run-*/<eval-id>/`.

## Frozen commitments and isolated gates

| Eval | Evidence graded |
| :--- | :--- |
| `committed_rule_deletion_routed` | All frozen rules remain verbatim; gate issues name both unproven preservation promises; verifier records route deletions or add proof |
| `last_call_ready_refuted` | The second gate reaches ready under max rounds 2, followed by citation verification; a refutation receives one re-gate and no body repair |
| `regate_isolated` | A decoy earlier verdict cannot hide the planted proof gap; gate prompts contain only admitted inputs and every gate confirms isolation |
| `repair_to_ready` | A ready before the cap has no citation-mode relay return |

`relay_checks.py` grades these saved prompt and return files. Its deterministic
self-tests exercise passing evidence and mutations that violate each property.
The runner derives `DEFAULT_IDS` from `evals.json`, so new entries join the
ordinary suite automatically.

## Recorded results

### 2026-11-25: Cursor `auto`, the fourth ordinary-path kind and the routed-repair scope

The five evals ran twice each on the default vendor with `--force`, one at a
time, so each is a fresh measurement rather than a replayed cached verdict:

```bash
python3 tests/task_auto_check/evals/run.py repair_to_ready --force
python3 tests/task_auto_check/evals/run.py relay_by_path --force
python3 tests/task_auto_check/evals/run.py guard_rebaseline_after_gate --force
python3 tests/task_auto_check/evals/run.py committed_rule_deletion_routed --force
python3 tests/task_auto_check/evals/run.py fidelity_rejects_drift --force
```

| Eval | Run 1 | Run 2 | Verdict |
| :--- | :--- | :--- | :--- |
| `repair_to_ready` | `../workspace/run-20261124-183211-28317` | `../workspace/run-20261124-185151-98259` | both pass 8/8; the vague item is replaced |
| `relay_by_path` | `../workspace/run-20261124-190855-41232` | `../workspace/run-20261124-192916-89422` | both pass 12/12; the vague item is replaced |
| `guard_rebaseline_after_gate` | `../workspace/run-20261124-194858-36452` | `../workspace/run-20261124-201041-87385` | both pass 7/7; the vague item is replaced |
| `committed_rule_deletion_routed` | `../workspace/run-20261124-203406-42096` | `../workspace/run-20261124-204914-77857` | both pass 12/12; all three rules stay verbatim and the verifier adds acceptance proof |
| `fidelity_rejects_drift` | `../workspace/run-20261124-224559-5545` | `../workspace/run-20261125-004309-47069` | both pass 6/6; the frozen abuse line stays and is routed |

The 2026-11-15 baseline row had `repair_to_ready` passing,
`relay_by_path` and `guard_rebaseline_after_gate` failing, and both routing
evals passing. The three replacement evals now pass, and the two routing evals
keep their outcome under the stricter grader.

The unchanged `no_verified_fix` eval also ran once on the default vendor with
`--force` and passes 6/6 (`../workspace/run-20261125-011303-33085`), so the
routed-only-round no-verified-fix stop keeps its existing "no verified fix"
report and `checked` status.

**Replacement pairings.** Each replacement's `reason:` carries the written
pairing of every promise the frozen item made to its replacement check:

- `repair_to_ready` (`run-20261124-183211-28317`): Goal/`Retry-After` handling →
  the `Retry-After` header assertion, and Approach delay-seconds
  `THROTTLE_WINDOW_SECONDS` → the same header's value.
  (`run-20261124-185151-98259`): Goal → the header/value assertion, and the
  Approach test and docs rewrites → the same bullet's fail-today clause.
- `relay_by_path` (`run-20261124-190855-41232`): Goal → the header on
  `build_throttle_response`, the Approach test update → bullet 2, and the
  Approach docs rewrite → bullet 3. (`run-20261124-192916-89422`): Goal → the
  header/value assertion, and the Approach test update → the same assertion.
- `guard_rebaseline_after_gate` (`run-20261124-194858-36452`): Goal
  reject-on-reuse → the `tests/test_writes.py` flip check, and the Approach
  `409`/same-key promises → the same bullet.
  (`run-20261124-201041-87385`): Goal reject-on-reuse → the first bullet, and
  the Approach no-header create path → the second bullet.
- `committed_rule_deletion_routed` (both runs): the verifier approves one
  Acceptance edit that adds proof for the `Content-Type` and body preservation
  promises; the window, header, and body rules stay verbatim.
- `fidelity_rejects_drift` (both runs): the abuse line is kept standing and the
  additive bullets pair Goal 100/min per authenticated user, the 429 JSON
  envelope, and cross-user isolation.

**Routed decisions.** `fidelity_rejects_drift` keeps
`- The API is protected from abusive clients.` verbatim and records it as a
`human_routed` decision in the last proposal-mode verifier return, because the
item promises more than the per-user quota Goal. No measured run replaces a
real commitment, and no measured run removes or narrows a frozen commitment
without a `human_routed` decision; the one intermediate run that did is named
under development runs below.

**Development runs and grader fixes.** One intermediate `fidelity_rejects_drift`
run (`../workspace/run-20261124-180841-29114`) replaced
`- The API is protected from abusive clients.` with quota checks without a
`human_routed` decision. That failure drove the rule that an item promising
more than the Goal stays on the user route and that its deletion is routed
while the additive proof is approved; the final two runs keep the line and
route it. Earlier `--force` runs of the same evals also exposed three
environment or grader problems rather than skill behavior, and are not counted
as measurements. A stale full-checkout copy under the system
temporary directory (`gapchk.*/tests/task_auto_check/evals/...`) made one
`relay_by_path` worker read a harness copy; the copy was deleted. Two Cursor
runs read paths inside the checkout and failed the isolation check; the
behavioral grade itself was 6/6 on the `fidelity_rejects_drift` one. The
`fidelity_rejects_drift` grader also read a fenced `affected_passages` value
that carried `## Context` and `## Acceptance` headings as ending the
`Rejections and routes` section; `relay_checks.section()` now skips fenced
blocks, a script test pins the shape, and
`run-20261124-224559-5545` was re-graded with the fixed grader to the 6/6
verdict recorded above.

### 2026-11-24: Claude `opus` at `high` effort, the gate pages an oversized skill read and keeps isolation

`immediate_ready_citations_survive` ran on Claude with
`python3 tests/task_auto_check/evals/run.py immediate_ready_citations_survive --vendor claude --force`
after the gate gained the paged-read clause and the persisted-copy exclusion. The
run passes 7 of 9 grader checks and fails 2 (`../workspace/run-20261124-101535-43514`),
and the isolation fix holds inside that failure.

| Check | Result |
| :--- | :--- |
| Task reaches `ready` | PASS, and the real repo's `tasks/` tree is unmoved |
| Task body unchanged | FAIL: the loop took one body-edit round |
| Every citation survives | FAIL: four citations refuted, so `r2-refuted-citations.txt` exists |
| Gate isolation | Every gate return (`r1-gate.txt`, `r2-gate.txt`, `r3-gate.txt`) writes `isolation: confirmed`, and no relay file names a read under `tool-results/` |

The gate's `r1-gate.txt` search-mechanisms line records the read this change
targets: "The base skill was read from its own path in `sed -n` pages, and the
persisted oversized-output copy was never opened." The run's only `tool-results`
mention sits in the runner's transcript metadata, not in a gate return or prompt.

The four refutations are a citation-strength gap, not the archived
absence-citation gap the acceptance permits: that form shipped on 2026-11-22 and
is exercised here, so the residual cause is how strong each quoted span is. Two
are presence citations that quote one `## Acceptance` entry, and the third quotes
a `## Context` premise statement, so each proves an existence fact the verifier
will not accept for Contradictions, Acceptance coverage, or Append-framed
artifact edits. The fourth is an absence citation over the full covered set,
correctly refuted because `## Context` writes an exhaustive "only" snapshot of
the response's headers. The record leaves these as the open cause.
[The absence-citation task](../../../tasks/archive/task-family_gate-absence-citation-form.md)
owns the citation form and is finished, so this record keeps the residual cause
visible rather than re-opening it.

### 2026-11-22: Cursor `auto`, absence citations survive the immediate-ready refutation

`immediate_ready_citations_survive` ran on the default vendor with
`python3 tests/task_auto_check/evals/run.py immediate_ready_citations_survive --force`
after the gate gained the absence citation form. The run passes 9 of 9 grader
checks (`../workspace/run-20261122-132805-27122`).

| Eval | Run | Verdict | Citation evidence |
| :--- | :--- | :--- | :--- |
| `immediate_ready_citations_survive` | `../workspace/run-20261122-132805-27122` | passes, 9/9 | The first gate call moves `open` → `ready` with zero issues. Twelve content lenses clear on absence and two on spans. The citation-mode verifier returns `survived_count: 14`, `refuted_count: 0`, and the `ready` stamp stands. |

The first run that day (`../workspace/run-20261122-131012-17316`) failed for a
reason outside this change: the gate found a docs-entry applicability issue on
the same fixture, repaired it, and reached `ready` on a scoped second round, so
neither citation-refutation trigger fired and no citation was refuted. The
re-run above took the first-call route the eval targets.

### 2026-11-18: Cursor `auto`, the disposition line on the ordinary repair path

Both evals ran twice on the default vendor with
`python3 tests/task_auto_check/evals/run.py regroup_immediate_ready --force` and
`python3 tests/task_auto_check/evals/run.py regroup_via_reviewer --force`,
measured against the 2026-11-15 Cursor row, where `regroup_immediate_ready`
passes and `regroup_via_reviewer` carries no failure row. The
`<output_contract>` edit-group bullet now closes an edit group that answers a
lint-originated `repeated-link` finding with that finding's disposition line,
so a regroup landing in an ordinary repair round still prints it.

| Eval | Run | Path the regroup took | Verdict | Disposition check(s) |
| :--- | :--- | :--- | :--- | :--- |
| `regroup_immediate_ready` | `../workspace/run-20261118-220012-8368` | Gate repeated-link repair round (r3) after a first-call `ready` and a refuted-citation re-gate that kept it | passes, 14/14 | "the ready path reports a regrouped or surfaced disposition": PASS; "the reported disposition matches the file state it claims": PASS |
| `regroup_immediate_ready` | `../workspace/run-20261118-221513-80201` | Gate repeated-link repair round (r3) after a first-call `ready` and a refuted-citation re-gate that kept it | passes, 14/14 | "the ready path reports a regrouped or surfaced disposition": PASS; "the reported disposition matches the file state it claims": PASS |
| `regroup_via_reviewer` | `../workspace/run-20261118-223550-61115` | Ordinary repair round (r2), after a refuted-citation re-gate moved `ready` to `checked` | passes, 11/11 | `disposition_line_regrouped`: PASS |
| `regroup_via_reviewer` | `../workspace/run-20261118-230501-45689` | Ordinary repair round (r2), after a refuted-citation re-gate moved `ready` to `checked` | passes, 11/11 | `disposition_line_regrouped`: PASS |

Both `regroup_via_reviewer` runs landed the regroup in an ordinary repair round,
which is the path this change repairs: each response carries
`repeated-link: api_quota-retry-header.md -> api_quota-reset-config.md, linked
from Context, Approach, regrouped`. The two `regroup_immediate_ready` runs kept
the regroup on the gate repeated-link round, so they confirm the line survives
there and add no ordinary-round evidence; the discriminating proof for that path
is the rewritten `<output_contract>` bullet and its script pin in scenario s15.
The 2026-11-15 Claude misses came from the ordinary repair path, so a Claude run
that confirms the fix remains the operator's call.

### 2026-11-17: Cursor `auto`, the gate and verifier return layout

The three evals the return-layout change names ran on the default vendor with
`python3 tests/task_auto_check/evals/run.py relay_by_path stray_hunk_reverted regate_isolated --force`.

| Eval | Verdict | Evidence |
| :--- | :--- | :--- |
| `relay_by_path` | passes | `../workspace/run-20261117-235012-36891`: all 11 checks pass, including the source-contract check and the settled isolation shape |
| `stray_hunk_reverted` | passes | `../workspace/run-20261117-223821-43956`: all 11 checks pass, including `verifier_returns_keep_contract` and the settled isolation shape |
| `regate_isolated` | passes | `../workspace/run-20261117-223821-43956`: all 9 checks pass, including both isolation checks |

Every gate return in the three runs writes `isolation: confirmed` and nothing
else, so the search audit stays on its own `search mechanisms:` line. Every
proposal-mode verifier return in those runs passes `verifier_returns_keep_contract`,
which accepts the approved edit's `reason:` field. The helper also reads a fenced
value as the block's content, which the `run-20261117-223821-43956` returns
exercise; the `relay_by_path` return under `run-20261117-235012-36891` writes its
values with a trailing pipe and indented lines instead.

`relay_by_path`'s first run (`../workspace/run-20261117-223821-43956`) failed the
source-contract check: the verifier fenced its values with an info string
(three backticks followed by `text`), and the helper then read only a bare
fence. The helper now accepts the info string, and the re-run passes.

### 2026-11-15: Cursor `auto` and Claude `opus` at `high` effort

On each eval's latest run, re-graded with the current graders, Cursor passes 29 of the 33 evals and Claude passes 28. Each remaining failure has an open task. The first full suites passed 21 of 33 on Cursor (`../workspace/run-20261115-020037-15631`) and 19 of 33 on Claude (`run-20261115-025041-38226` through `run-20261115-090126-14852`). Most of the difference came from grader and fixture defects that both runs exposed.

| Eval | Cursor | Claude | Cause | Task |
| --- | --- | --- | --- | --- |
| `immediate_ready_citations_survive` | fails | fails | The verifier refutes every citation that clears a lens judged by absence. On Claude the re-gate also read the base skill back from Claude Code's `tool-results` store and stopped as a helper failure | [absence citations](../../../tasks/archive/task-family_gate-absence-citation-form.md), [paged reads](../../../tasks/archive/task-family_gate-paged-reads-of-large-files.md) |
| `scope_split_stuck` | passes | passes | Both vendors block the independent-items bundle by definition under the **Blocking bar** and route the split to the user | [independent items](../../../tasks/archive/task-family_independent-items-split-blocks.md) |
| `regroup_immediate_ready` | passes | fails | When an ordinary repair round lands the regroup, Claude's report drops the `repeated-link:` disposition line | [disposition line](../../../tasks/archive/task-family_auto-check-disposition-line-every-path.md) (archived) |
| `relay_by_path` | fails | fails | Cursor stopped human-routed on a frozen Acceptance item no check can prove. Claude's verifier return breaks the source-contract layout check | [frozen Acceptance](../../../tasks/task-family_auto-check-uncheckable-frozen-acceptance.md), [return layout](../../../tasks/archive/task-family_gate-verifier-return-layout.md) |
| `stray_hunk_reverted` | passes | fails | Claude's proposal-mode verifier return breaks the layout check | [return layout](../../../tasks/archive/task-family_gate-verifier-return-layout.md) |
| `repair_to_ready` | passes | fails | Claude cannot replace a frozen Acceptance item that names no checkable result | [frozen Acceptance](../../../tasks/task-family_auto-check-uncheckable-frozen-acceptance.md) |
| `guard_rebaseline_after_gate` | fails | passes | Cursor routed the same kind of frozen item to the user and stopped at `checked` | [frozen Acceptance](../../../tasks/task-family_auto-check-uncheckable-frozen-acceptance.md) |
| `regroup_same_paragraph_ready` | fails | passes | Cursor's worker passed all 14 grader checks but read the checkout's `evals.json` | [harness copies](../../../tasks/archive/tests_harness-copy-read-check.md) |

A 2026-11-20 Claude re-run (`../workspace/run-20261120-211544-96726`) moved `scope_split_stuck` to passes: its first gate return records the Scope sizing / Focus issue on the independent-items bundle and routes the split to the user.

The runs exposed these grader and fixture defects, which are now repaired:

- **The gate's isolation line.** `isolation:` reads exactly `confirmed` or one `out-of-bounds read: <artifact read> — via <mechanism>` entry per read, and the search audit has its own `search mechanisms:` line, so `isolation_shape` rejects a mechanism list that rides the isolation value while `relay_checks.py` keeps reading the leading token. `prompts_isolated` also admits a moved sandbox root named in the prompt's own task path, and the `immediate_ready_citations_overturn` arm accepts a ready route that the citation pass challenged.
- **Premise stops by accident.** `scope_split_stuck`, `fidelity_rejects_drift`, and the three `drift_gate_*_clean` fixtures named source files they never staged, so a gate could stop on an invalidated premise. They now stage those files.
- **The `Retry-After` value.** The three immediate-ready fixtures left open whether the header holds an integer or a string. The two regroup fixtures needed three more passes, because each gate found a new gap in the target's test. The sibling task now keeps `THROTTLE_WINDOW_SECONDS` a module-level int. The test uses pytest's `monkeypatch` to set the window to `120` and expects the header `"120"`, and the project stages a root `conftest.py` so a bare `pytest` run imports `src`.
- **Timeouts.** `no_verified_fix` was killed at 2306 seconds while it composed its report, so the slow evals now carry 3600-second bounds in `evals.json`.

Cursor's workers on these evals often search outside the sandbox for the fixtures and grader. Five Cursor passes failed `checkout_unread` on 2026-11-15. Two of them first read leftover checkout copies in the system temp folder, and a sixth pass read those copies without reaching the checkout, so no read check failed it. The leftover copies were deleted, and [the harness-copy task](../../../tasks/archive/tests_harness-copy-read-check.md) adds the check for copies outside the checkout.
