# agent_spinner behavioral evals

Every id in `evals.json`. Each behavioural eval stages one
behaviour; the `smoke_*` evals check the runner's modes, so a failing eval
names one behaviour rather than a conjoined verdict. The static body and grep
items stay under `script_tests/`.

Run them with `python3 tests/agent_spinner/evals/run.py`; `RUNBOOK.md` has the
flags and the cheap-first staging probe. The runner runs one job per eval in
the shared `tests/lib/eval_runner` pool at the default 4 workers, each job
with its own `TMPDIR`, and its owned-name host guard keeps an escape
attributable while siblings overlap. The runner's plumbing test runs without a
live worker: `python3 tests/agent_spinner/evals/test_run.py`.

## The two axes every eval is graded on

**Filesystem and roster facts** come first, because they are what the run left
behind rather than what it said about itself. Three artifacts carry them:

- The staged hash inventories. `proj/` proves the run stayed inside its brief;
  `outside/` proves nothing escaped the sandbox. The run's own instrumentation
  under `proj/.agent_spinner/` is excluded from the `proj/` inventory on both
  sides, so writing a roster never reads as editing the corpus.
- `.agent_spinner/roster.tsv`, the dispatch roster the skill's `<run_state>`
  block requires. The harness pins its path so the grader can find it.
- `.agent_spinner/briefs/<label>.txt`, one file per helper brief, appended
  before that helper is dispatched. This is the only way to check a claim the
  contract makes about *prompts*, since the closing report deliberately keeps
  helper return shapes internal. It is an observation point, the same shape as
  a stub binary that logs its calls, not a change to what the run does.

**Response markers** come second, for the contract obligations that live in
the report itself. `grade.sh` reads the response with hard wraps collapsed and
one sentence per line, and drops negated sentences before deciding, so a run
that names a move in order to say it did not take that move is not scored as
having taken it.

## Prompt selection

A prompt shows what the skill drives only when it asks for the job. A sentence
that states the answer the run can derive from the staged tree, or the
instruction the skill's own doctrine owns, is removed. A sentence stays when it
states the user's request, a scope, a constraint, or a decision the user
already made, and a pointer at material the request forces the run to read
stays.

The selector was re-run on 2026-11-26 over every prompt in `evals.json`, each
read against its eval's `id` and expectations. It selected 44 prompts, listed
below with the sentence each lost and the fact the run must now derive. The
remaining prompts keep only the request plus facts a real user would state;
the near-misses are recorded after the list.

### Selected prompts

- `failure_taxonomy`: removed "survey:alpha.md (a deliberate inability), survey:beta.md (boilerplate only), and survey:delta.md (a schema-valid placeholder that `accept` refuses); survey:gamma.md never arrived" and "Classify each non-result, say what you do about each". The run must read the staged returns and classify each non-result itself.
- `uncited_clean_reroute`: removed "it cites only a heading and its receipt line is absent from the input version the row recorded" and "apply the skill's rules for an uncited clean verdict and for a receipt that does not match". The run must find the missing citation and the receipt mismatch in the return.
- `confirmation_provenance`: removed "raised a finding from its own read", "was handed that report and checked it", and "including the provenance split and the weight each provenance carries". The run must read each return and split the provenances itself.
- `one_remediation_round`: removed "check:verify.md failed at depth 3 and check:status.md passed" and "Remediate, re-check the repaired item once at no lower depth than its first check". The run must read the returns, find the failing item, and apply the one-round rule.
- `decision_items_past_line_100`: removed "each carrying one decision item past its hundredth line, and each self-tally says it found nothing" and "give every decision item one disposition, name each ledger record id in the report, and report counts that match the records". The run must read every return in full and dispose each record.
- `beyond_brief_find_reported`: removed "and reported a defect outside its brief" and "record what it found". The run must read the writer's return and notice the beyond-brief find.
- `labelled_forks_all_relayed`: removed "with three labelled forks" and "report all three to the user". The run must read the return and relay every labelled fork.
- `unlabelled_returns_joined_by_id`: removed "join the synthesis by identifier". The run must choose the join key from the records themselves.
- `hollow_plan_blocks_writes`: removed "one placeholder task". The run must read the planner return and see the placeholder for itself.
- `changed_false_still_checked`: removed "for a file that differs from the baseline". The run's own diff must establish the change the writer's flag denies.
- `verdict_waits_for_open_checker`: removed "naming the pending checker row in your opening sentence". The run must place the pending row where the verdict rule puts it.
- `aborted_writer_settled_from_diff`: removed "after it left its file different from the baseline" and "Settle the row from the diff". The run must find the aborted path changed and settle it from the net diff.
- `declared_shape_switch_named`: removed "Record any shape switch". The run must record the switch the charter's obstacle forces.
- `mandated_step_listed`: removed "CHARTER.md mandates ./lint.sh. Open the run with that step as a row before dispatch, run it". The run must read the charter and plan its mandated step as a row.
- `readonly_checker_returns_by_message`: removed "relay its final message into accept". The run must apply the relay rule to the read-only role's return.
- `verifier_rows_from_findings`: removed "carrying three findings" and "Make the verifier rows from the records before any verifier brief". The run must derive the row count from the accepted records.
- `gate_scope_checked_before_dispatch`: removed "then check the gate's scope before dispatch". The run must run the gate-scope check the opening procedure owns.
- `continuation_armed_once`: removed "Arm exactly one goal for this run, with the run directory in its objective". The run must arm the goal the run-state contract requires where the host offers one.
- `unapproved_hunk_after_regeneration`: removed "Map its changed blocks against approved-edits.json with the ledger's approved-edit mapping, write the checker's brief from that list, and quote the hunk that maps to no id". The run must map the diff and surface the unmapped hunk.
- `acceptance_presence_on_every_surface`: removed "which requires CACHE_MARKER on every page", "Write the checker's brief with one checklist line per acceptance item", and "report which pages lack the marker". The run must read `ACCEPTANCE.md` and build the checklist it defines.
- `verifier_brief_carries_no_preference`: removed "Keep notes.md's preference out of the brief" and names the notes as material the brief is written against instead. The run must read the notes and keep their preference out of the brief on its own.
- `documented_absence_stays_conditional`: removed "Build the run's preamble with tiered settled facts and the unverified-premises block, then report the answer as conditional with its probe". The run must tier the fact and carry the probe.
- `placeholder_figure_held`: removed "Build the tiered preamble, answer with the figure as conditional, and write the checking brief over your report". The run must tier the placeholder figure and check its own report.
- `wrapped_contrast_and_quotation`: removed "Keep the archived record byte-identical, keep the wrapped sentence's contrast intact, and give the claim-bearing page its own writer row". The run must keep the archive outside its scope and preserve the contrast through the edit.
- `probe_positive_control`: removed "Run the ledger's counter check so each registered counter's positive control passes, then run bin/count.sh as a gate expecting a count". The run must fire each counter's positive control before trusting a count.
- `remediator_refutes_false_finding`: removed "The accepted finding against docs/page.md is false. Re-derive it against the file, refute it with its settling span, and dispose of it as refuted. Change no file." The run must re-derive the finding and find it false.
- `count_check_cannot_clear_meaning`: removed "write the checker's brief and raise the inverted requirement as a finding". The run must read the page and raise the inverted requirement itself.
- `ruling_applies_to_class`: removed "in all three pages" and "Apply that ruling to all three instances, record one disposition per instance citing the ruling". The prompt names one instance, and the run must generalize the ruling and build the dispositions.
- `survived_lenses_labelled_recall`: removed "report the provenance of the finding both lenses saw. Give it the contract's exact label, survived both lenses, recall-confirmed, and never label it confirmed or independent." The run must derive the label from the contract.
- `known_false_control_caught`: removed "The verify batch's known-false control is the finding its quoted source contradicts" and "refute the control with its span, and add the batch's re-verification rows under a different framing". The run must catch the contradicted control and reframe the batch.
- `surplus_read_proposes_removal`: removed "Report the restated rule to convert into a citation". The run must produce the conversion the surplus read exists for.
- `unverified_band_sampled`: removed "Add sample rows and briefs for the minor band before the first verifier brief, then add the blocker verifier rows and report that band's sampled refutation rate". The run must sample the band the verification scope leaves out.
- `judge_flaws_capped`: removed "confirm each return holds at most three fatal flaws each with a span". The run must apply the cap the judge return owes.
- `checker_reads_return_by_path`: removed "Write the checker's brief naming the producer's return at .agent_spinner/returns/produce:spec.md by path, and keep paraphrase.md's paraphrase out of the brief. Report which edit id each hunk maps to." The run must write the brief from the return path and map the hunks.
- `stamped_target_routed_to_owner`: removed "Record the routing in the run ledger and report the owning gate". The run must see the stamp and route the write.
- `committed_rule_deletion_surfaced`: removed "put the decision it implies to me as an open fork in the ledger, and quote both rules in your decision packet. Change nothing until I answer." The run must see that the plan deletes committed rules and raise the fork.
- `stamp_routed_on_any_rewrite`: removed "It carries its family's ready stamp, so route the write to the owning gate or to me before any writer runs". The run must read the stamp and route the write.
- `baseline_kept_on_partial_read`: removed "Record each page you read in full as an accepted roster row before you finish" and "Leave the baseline marker alone". The run must record the reads and keep the marker outside its scope.
- `baseline_lint_without_stash`: removed "then confirm the edit added no lint error by reading the baseline copy of the file by path. Do not run any version-control state command." The run must check the edit against a baseline copy without moving the repository state.
- `reader_gets_snapshot`: removed "and have a checker read docs/page.md while you do it. Report the delta between the checker's snapshot and the final file". The run must give the paired check a snapshot and report the delta.
- `role_depth_recorded`: removed "If the close reports the checker's recorded depth as below its producer's, record that as a flag with its reason", the requested/observed report list, "the final close needs the current tally block in report.md", and "Then close again". The run must read the close's refusal, flag the below-producer checker, write the report, and close again.
- `blind_pass_by_prompt`: removed "keep my hypothesis out of its brief. Record only the hypothesis's hash on the row." The run must isolate the hypothesis and record its hash on the row.
- `repair_list_keyed_on_severity`: removed "build the repair list from the accepted checker returns, create one repair row per failing item keyed on its lowest-id should-fix finding record, with its repair and re-check briefs". The run must key the repair list on the records.
- `confirmed_class_swept_before_clean`: removed "create the class-sweep and recall-probe rows, run the sweep across every unit". The run must sweep the confirmed class before calling any unit clean.

Two checks were re-anchored, both in `stamped_target_routed_to_owner`, because
the rewrite revealed a surface-form read rather than a prompt-wording match:

- `no writer row targets the stamped path` now reads the roster's state column
  and ignores `pending` and `dropped` rows. A row planned before dispatch and
  retired by a narrowing was never a writer that ran, and the contract's width
  rule writes rows before dispatch, so the old count failed a compliant run
  that planned the row and dropped it after routing. It reads the roster at
  `run-20261126-103602/stamped_target_routed_to_owner` and passes 6 of 6 there
  after the fix.
- `the report names the owning gate` now accepts the hyphenated `task-family`
  form beside `task family` and `task_<gate>`, because that run named "the
  task-family writer" and the task hub's manual routes, which is the same
  property. It reads the same run's report.

`script_tests/grade_cases.sh` gained four cases for the pair: a dropped planning
row passes, a dispatched writer row fails, the hyphenated family form passes,
and a report naming no gate fails. Every other check these 44 evals carry reads
a filesystem, roster, ledger, or report fact that the skill's own doctrine
produces. Two checks read a label that a removed sentence also carried,
`survived both lenses, recall-confirmed` and `blind by prompt`; both labels are
stated verbatim in `SKILL.md` `<confirmation_provenance>` and
`references/checks.md` item 9, so they measure the skill rather than the
prompt.

### Prompts kept request-only

These near-misses were read against their expectations and kept, because the
sentence states the user's own request, constraint, or decision rather than the
skill's rule:

- `probe_definitions_no_spawn`: "Tell me whether those three definitions are callable" is the user's question, and the eval grades the answer to it.
- `roster_partial_stop`: "Stop the run after two items are done" is the user's stop decision.
- `unanswered_gate_stops_with_packet`: the helper cap, the over-budget call, and the single-turn host are the user's conditions; the README note below records why each stays.
- `sweep_rewrite_hunk_blocks_sampling`: the calibration answers are the user's, and its own note below records the separate fix.
- `widening_needs_estimate_and_ask`: "put the widening to me before you take it" is a user constraint on that run.
- `snapshot_search_positive_control`: the two quoted values are repository facts the request points at, not the rule the eval grades.
- `cross_model_checker_recorded`: running the checker on a different model is the user's rigour choice.
- `checker_spawned_through_role`: naming `auto_checker_spinner` is the user's instruction about which staged role to use.
- `attached_body_reads_recipe`: "Name the matched recipe file in your opening announcement" asks for the evidence the attached-body mode exists to test.
- `family_job_post_write_check` and `explicit_spinner_on_family_job`: the gate answers and the withheld approval are the user's.

## Signal per eval

| Eval | Primary signal | Why that signal |
| --- | --- | --- |
| `probe_definitions_no_spawn` | response + declared spawn absence | Three role definitions sit on disk while the spawn surface is absent, so "definition present, surface absent" is a real state rather than a hypothetical. The spawn class is withheld under the withheld-tool rule: the absence is declared the same way on both vendors, because no Cursor deny entry withholds the spawn tool. Test Integrity class: the check is unchanged; the withholding moved to one declaration on both vendors, and the probe of 2026-10-04 is the evidence. See `## Runner modes`. |
| `inline_floor` | response + declared spawn absence | The floor is a claim about the opening sentence and the plan, and the same corpus is staged for `phase_plan_announcement`, so the two plans are comparable. The checking pass is a disk fact: an accepted checking row whose return post-dates the producers' returns at the same path, not a phrase in the report. The spawn class is withheld under the withheld-tool rule: the absence is declared the same way on both vendors, because no Cursor deny entry withholds the spawn tool. Test Integrity class: the check is unchanged; the withholding moved to one declaration on both vendors, and the probe of 2026-10-04 is the evidence. See `## Runner modes`. |
| `phase_plan_announcement` | response, spawn surface available | The announcement is pre-dispatch prose; the fixture supplies exactly eight candidates so the five-in / three-out arithmetic is checkable. |
| `governed_stop` | task file hash + response + declared spawn absence | A byte-identical task file is the hard evidence that no helper role ran inline; the response carries the manual routes. The spawn class is withheld under the withheld-tool rule: the absence is declared the same way on both vendors, because no Cursor deny entry withholds the spawn tool. Test Integrity class: the check is unchanged; the withholding moved to one declaration on both vendors, and the probe of 2026-10-04 is the evidence. See `## Runner modes`. |
| `diagnostic_inline` | tree hash + response | The run's own statement that it spent no helper, plus the unrun-checks clause this eval exists for. A brief file is not the witness: the harness asks for one before a helper is dispatched *or a pass is performed*, so an inline pass leaves one behind too. |
| `residual_selector` | announcement | Three release changelogs are closed comparison candidates and the ask also wants what the winner's notes leave out, so the ask combines rows and matches no single listed shape. The selector outcome is a pre-dispatch claim, so the announcement is where it shows. |
| `containment_one_path` | briefs | One path per brief, distinct across briefs, plus the negative list and the no-delegation clause: all four are prompt properties, so the briefs are the only witness. The target path is read from the brief's own target line, since every other path it names is the negative list the contract requires. |
| `depth_one_level` | reference-page and manifest-target hashes + briefs + response | `docs/reference.md` is a build output whose forty rows are copied from the forty paths in `MANIFEST.txt`, and a `Makefile` rule makes that mechanical rather than advisory. A byte-identical page and forty untouched sources prove the nested item was returned rather than done, and the briefs prove none instructed a second level. The go-ahead check reads a user-directed decision cue, so the report's own headings and tally lines do not count as asking. |
| `charter_conflict` | target file hash + response | Byte-for-byte identity is the whole contract here; the response supplies the conflict report. |
| `failure_taxonomy` | staged returns + response | Real helpers cannot be made to fail on cue, so the four non-results are staged as material and the run is graded on how it classifies them. |
| `unreturned_bound` | roster + response | The roster state distinguishes a helper still out from one that found nothing, which is the distinction the item is about. The fixture stages the row `dispatched` with a start past its bound, so the run must reach `unreturned` through `accept --wait` rather than read a state the fixture set. |
| `roster_partial_stop` | roster + per-file hashes | Exactly two of four pages changed is the ground truth the report's modified / untouched / not-dispatched enumeration is checked against. |
| `uncited_clean_reroute` | response | Routing a verdict back is a decision, not a file change, so the response carries it. |
| `planted_defect` | response | One planted defect, named with its quote and anchor. |
| `clean_corpus` | response | The false-positive guard: a clean corpus must produce zero findings and an examined-and-cleared record. `bin/tool.sh` really parses the flags its pages document, so a finding here is an invention rather than a reading. |
| `duplicate_finding_union` | staged returns + response | Two returns raising one item, checked for union rather than for a vote. |
| `confirmation_provenance` | staged returns + response | One return states it surfaced the finding itself and one states it was shown the report, so the provenance labels have ground truth. |
| `one_remediation_round` | per-file hashes + roster depths + response | Only the failing item changes, the roster holds one re-check row at no lower depth than the first check, no second repair round runs, and the unverified-end-to-end label is the response half. |
| `payload_cap` | the synthesis row's own brief + response | The truncation notice, the trimmed-identifier list, and the cap are properties of the synthesis prompt, so that one brief file is the witness. The check is branch-aware: a by-path brief that relays each return with a read-in-full instruction and pastes no body owes no cap, while a paste brief owes a numeric cap, the cut notice, and the trimmed identifiers. The response checks apply on the paste branch alone. |
| `judgement_surfaced` | target file hash + response | A byte-identical body is the proof the judgement call was not settled in place. The go-ahead check reads a user-directed decision cue, so "Decided on a helper's own authority" and "confirmations 0" do not count as asking. |
| `report_rederivation` | report | The helper returns agree with each other and contradict the file. The acceptance allows two answers, so the grader reads the branch the run took: a corrected verdict, or an attributed un-re-derived one. |
| `smoke_inline_body` | `smoke.txt`'s first non-blank line | The attached body starts after the frontmatter, so a run that read the staged file in place of the attachment writes the frontmatter's opening line. `grade.sh` derives the expected line at grade time. Results: `## Runner modes`. |
| `smoke_second_turn` | `smoke.txt` plus both response files | The first turn carries one token, the between step writes a second, and only a resumed second turn can report both. Results: `## Runner modes`. |
| `smoke_staged_agent` | `tool_calls.jsonl` plus `smoke.txt` | The staged agent's token sits where the worker can read it, so the spawn call is the witness: it names the agent, carries no token in its input, did not fail, and returned the token. Results: `## Runner modes`. |
| `smoke_withheld_shell` | `tool_calls.jsonl` plus marker absence | The shell class is withheld, so the marker stays absent and the record shows the class missing from the offered tools or every shell attempt failed. Results: `## Runner modes`. |
| `smoke_withheld_write` | `tool_calls.jsonl` plus marker absence | The write class is withheld, so the marker stays absent and the record shows the class missing from the offered tools or every write attempt failed. Results: `## Runner modes`. |
| `decision_items_past_line_100` | ledger records + report | Three long returns each carry one decision item past line 100 and a self-tally that misses it, so the ledger record and the report count are the ground truth the self-tallies cannot supply. |
| `beyond_brief_find_reported` | ledger record (flag or beyond_brief) + report | The shipped ledger imports no beyond-brief record type, so a run records the find as a flag; a ledger that gains the record type records it as one. The grade accepts either shape and only one of them, and the report's beyond-brief part is where its path and quote must land. |
| `residual_sweep_finds_missed_target` | ledger records + page bytes + report | The accepted `residual:sweep` row and its finding are the sweep's own record, the `missed` class and the repair row prove it entered repair, and the page's bytes prove the target no longer matches. The report check keeps a run from claiming a clean sweep before the repair. |
| `pause_request_writes_stop` | STOP marker + ledger dispatch count | The pause request arrives in the second turn with no STOP planted, so the marker is the run's own act; the between script records the dispatch count at the request, and the ledger's count after it is the no-new-dispatch fact. |
| `twice_failed_item_marked_failed` | roster state + page bytes + report | A second rejected return is the ledger's own transition to `failed`, a byte-identical page proves no degraded path ran, and the report's inline-redo offer is the user's choice the contract defers. |
| `unprompted_verification_before_write` | `row_source` records + brief order + ledger disposition + page bytes | The three verify rows sourced from the findings are the ledger fact, the brief mtimes are the before-any-writer ordering fact, the refuted disposition with its span is the re-derivation, and the contradicted page's bytes prove no edit landed. |
| `family_job_post_write_check` | run gate record + roster + `run.json` changes | The `notes_lint` `gate_result` is the pointer-only page's post-write check, the accepted check row is the claim-changing page's, and each changed family page's attribution plus its family-writer route proves the orchestrator wrote no family file. |
| `labelled_forks_all_relayed` | ledger records + report | Three fork records prove the import, and the report proves none was dropped. |
| `unlabelled_returns_joined_by_id` | report | Joining by arrival order is a synthesis decision, so the echoed id or the missing-id list is the witness. |
| `hollow_plan_blocks_writes` | file hashes + roster | Five byte-identical files prove nothing was written from a placeholder plan, and the roster state proves the contract violation. |
| `changed_false_still_checked` | the check row's own brief + report | The diff is the authority, so the check brief and the report's changed list are the facts a helper's changed flag cannot override. The brief must belong to the ledger's `check` record for the path, so the producer's staged brief does not stand in for it. |
| `lint_warning_delta_reported` | ledger gate lines + report | The two gate outputs are the measured values; the report's move and its refusal to call the lint clean are the prose half. |
| `verdict_waits_for_open_checker` | file hash + report opening | The artifact's status field is the file half; the opening's pending-row name is the placement half. |
| `aborted_writer_settled_from_diff` | ledger records + report | The diff names the modified file, and the check row before any re-dispatch is the ordering fact. |
| `twelve_files_twelve_rows` | roster + briefs | Twelve rows and twelve one-page briefs are the width rule's filesystem witness. |
| `declared_shape_switch_named` | ledger record + report | A narrowing record with its dropped checks is the switch's record; the report names it. |
| `mandated_step_listed` | roster/briefs + report | The mandated lint step must be a row before dispatch, and the report must say it ran or why it did not. |
| `readonly_checker_returns_by_message` | roster source + report | The checker's final message is the only channel, so the relayed source tag and the report's named relay are the witness. |
| `completion_turn_advances_phase` | ledger records + turn-two reply | Only a resumed turn can accept the between-turn return, so the accepted row and the next dispatch or gate are the advance. |
| `verifier_rows_from_findings` | ledger records + roster | `row_source` records prove the rows came from the findings, and the roster proves three check rows exist before a verifier brief. |
| `attached_body_opens_and_closes_ledger` | run directory + report | A closed run and the tally block in `report.md` prove the attached body reached the ledger end to end. |
| `skipped_close_reported` | run state + report opening | The still-open run is the fact; the opening's no-clean-close sentence is the reporting half. |
| `ledger_unavailable_by_hand` | hand-kept files + report | The roster, briefs, and returns are the files a by-hand run keeps; the unenforced labels are its honest report. |
| `gate_scope_checked_before_dispatch` | run gate record + ledger | The gate's known-positive result and the dropped run-directory findings are the scope facts; the auto-fix refusal is recorded beside them. |
| `pause_request_stops_dispatch` | ledger dispatches + report | No second-wave dispatch is the stop fact, and the stop report's row lists carry it. |
| `continuation_armed_once` | tool record + announcement | Cursor's goal tool is the vendor-specific feature: exactly one goal creation with the run directory in its objective. On Claude, the absence of a goal tool is proven by no goal, `ScheduleWakeup`, or cron call, and the announcement names re-entry through `status` and `attach`. |
| `explicit_spinner_on_family_job` | finder briefs + file hashes + report | Five read-only finder briefs, one per page, are the orchestrator-level look the named family job gets. Byte-identical pages and family files prove the family writer stayed the only writer. No brief addressed to the family agent names its checks or assigns a lens panel. The report carries the approval handoff. |
| `shape_matched_no_recipe` | roster + briefs + note files + announcement | Per-artifact fan-out is the shape the enumerated imperative matches, and no row of the recipe table fits a job that summarizes five pages with no tracked task and no acceptance list, so no recipe matches. The roster and briefs carry the five-way width, the note files are the produced artifacts, and the announcement states the shape and the no-recipe path. |
| `merged_deliverable_checked` | roster + report | The write that lands gets its own check row and that row is accepted, so the merged deliverable is checked rather than certified by its producer. |
| `unapproved_hunk_after_regeneration` | file hash + briefs + report | A regenerated file's unmapped hunk is the fact; the brief carrying the approved-edit list and the report quoting the hunk are the two halves of C1's mapping rule. |
| `acceptance_presence_on_every_surface` | page hashes + brief + report | Byte-identical pages prove nothing was written, the brief's five checklist lines prove the checklist came from the acceptance contract, and the report names the two pages that fail it. |
| `verifier_brief_carries_no_preference` | briefs | A verifier's brief is a prompt property, so the brief file is the only witness that the returns are named by path and the notes' preference stayed out. |
| `documented_absence_stays_conditional` | preamble + report | The preamble's settled and unverified sections separate a documented claim from a measured one, which is C10's whole distinction. |
| `placeholder_figure_held` | preamble + checker briefs + report | A placeholder-sourced figure that never reaches the settled facts, while every checker brief carries the unverified block, is the tier rule on disk. |
| `wrapped_contrast_and_quotation` | file hashes + roster + report | The archived record's hash proves verbatim text stayed still, and the wrap-collapsed contrast proves the sentence edit did not split a contrast at its wrap. |
| `probe_positive_control` | ledger gate record + counters | The counts sit in a gate record with a counter whose positive control passed, so a zero or a wrong count cannot pass silently. |
| `remediator_refutes_false_finding` | file hash + ledger disposition | A byte-identical target and a refuted disposition with its span prove the remediator re-derived the finding rather than editing to it. |
| `count_check_cannot_clear_meaning` | briefs + ledger finding + report | The inverted sentence's finding and the report's refusal to rest meaning on a count are the claim-type table's consequence. |
| `ruling_applies_to_class` | page hashes + ledger dispositions | Three applied dispositions under one ruling prove the ruling reached the class rather than the instance the user named. |
| `survived_lenses_labelled_recall` | ledger confirmations + report | The ledger's two recall-confirmed tags are the provenance fact; the report's label is the prose half, and a bare confirmed or independent label for the finding fails. |
| `known_false_control_caught` | ledger disposition + briefs | A refuted control with its span, plus re-verification briefs under a different framing, is the calibration rule made visible. |
| `surplus_read_proposes_removal` | file hash + report/returns | A byte-identical artifact and a named restatement to convert into a citation are the surplus read's whole output. |
| `unverified_band_sampled` | brief order + report | Sample briefs that predate the first verifier brief are the ordering fact; the reported rate is the prose half. |
| `judge_flaws_capped` | accepted returns | Each judge return's findings list is on disk, so the three-flaw cap and its spans are checkable without reading a stream. The fixture stays compliant; `grade_cases.sh` stages a four-flaw return and proves the cap's fail branch. |
| `checker_reads_return_by_path` | applied file + briefs + ledger diff | The applied bytes equal the approved text, the brief names the return by path, the paraphrase string is absent, and the ledger's recorded diff carries one hunk per edit id, so the hand-off stayed verbatim and mapped. |
| `stamped_target_routed_to_owner` | file hash + roster + ledger | A byte-identical stamped file, no writer row for it, and a routing record are the hand-off to the owning gate. |
| `committed_rule_deletion_surfaced` | spec hash + ledger records + report | A byte-identical spec proves the committed rules were not deleted; the open fork record and the packet's verbatim quotes are the surfacing half. |
| `stamp_routed_on_any_rewrite` | status line + ledger record + briefs | The status line is the stamp's own byte fact; the routing record before the first writer brief and the briefs' clean status field are the hand-off and containment halves. |
| `baseline_kept_on_partial_read` | marker hash + roster rows | A byte-identical baseline marker is the proof that a two-of-five read did not shrink the coverage claim; the two accepted rows are the reads it did make. |
| `baseline_lint_without_stash` | git state + untracked hash + brief | An empty stash, unmoved HEAD, and a byte-identical untracked file are the no-state-command facts; the brief naming the baseline copies is the mechanism it used instead. |
| `reader_gets_snapshot` | brief + report + repo ref/object guard | The brief's snapshot path is the reader's input fact, the report's delta is the prose half, and the recorded ref and object outputs fail a run that wrote into the sandbox repository. |
| `widening_needs_estimate_and_ask` | announcement + open gate + page hashes + roster | The estimate is pre-dispatch prose; the unanswered gate and the untouched non-hit pages and rows are the widening it refused to take. |
| `procedure_page_conflict` | target hash + roster + report | A byte-identical generated file and an accepted orient row for the procedure page are the conflict's two disk facts; the report names the page. |
| `unanswered_gate_stops_with_packet` | ledger records + STOP marker + report | The request states its helper limit as a hard cap the run may not shrink around, so no dispatch row is the stop fact. A `STOP` marker under the run's `.agent_spinner/` and the unanswered gate still open are the ended-at-gate facts, and the run is not a clean `closed: true`. The ledger refuses `closed` while a user gate is unanswered, so `close --stopped` exits non-zero with its modified, untouched, unknown, not dispatched, and violation lists, and the packet is the report half. |
| `role_depth_recorded` | roster columns + ledger flag + report | The requested and observed columns are the recording fact, the flag names the below-producer checker, and the report's list and narrowing label are the prose half. |
| `blind_pass_by_prompt` | briefs + the blind row's permits line + roster input versions + report | No brief carrying the hypothesis and the withheld hash on the row are the isolation facts; the report's label is the provenance half. The blind row's own brief must also carry a `permits paths:` line that names none of `request.txt`, `intent.md`, or `announcement.txt`, which quote the hypothesis. |
| `wide_run_plans_session_boundary` | announcement | The context estimate and the wave end where the boundary falls are pre-dispatch claims, so the announcement is the only surface that owns them. |
| `cross_model_checker_recorded` | roster columns + report | A checker model request that differs from its producer's is the roster fact; the report's unmeasured label keeps the benefit from being claimed as measured. Claude-only: a per-spawn model choice is the Claude feature it exercises. |
| `checker_spawned_through_role` | `probe.json` + roster + report | The registered role's probe entry records its delegation as established and its read-only lever as enforced, and the checker's roster row names that role as its spawn route. The delegation check reads the key whose name contains `delegat` or `spawn`, so a value under another capability cannot stand in. A relayed accept proves the checker returned by message. |
| `checker_spawned_without_role` | `probe.json` + roster + report | No role is staged, so no probe row uses a role route and the checker records a generic route. A role-labelled probe entry recording an established delegation fails the case by naming the visible copy. |
| `attached_body_reads_recipe` | run directory + roster + page hashes + tool record + announcement | The attached body arrives without its reference files, so the read call naming `references/recipes/check-only-audit.md` is the proof the run found the recipe, and the announcement names it. `init` wrote the run directory and roster, and every page stays byte-identical. |
| `routed_premise_sentences_landed` | report + page hashes | The plan and the landed pages are the disk facts; the report's failed post-run check and its refusal to claim every routed sentence landed are the prose half. |
| `repair_list_keyed_on_severity` | ledger `row_source` + roster + report | One repair row per failing item is a ledger fact, the nit-only and passing artifacts' absence from the roster is its counterpart, and the report's nit list is the prose half. |
| `confirmed_class_swept_before_clean` | ledger `row_source` + roster + report | The sweep row's source record and its coverage of every unit are ledger facts; the report's `docs/b.md` line and the fix-or-file fork are the prose half. |
| `sweep_sampling_needs_user` | roster + ledger + announcement | Every changed page holding exactly one accepted check row — its brief and return on disk, its ledger `accept` record, and no sampled-out `classification` — is the width fact; the glyph-only diff makes a sampled set available, and the announcement is where the run must offer it with its drops and its share of the estimate. A negated sentence or item never counts as an offer. |
| `sweep_rewrite_hunk_blocks_sampling` | roster + ledger + announcement | The same accepted-row fact on a corpus whose delta page needs a sentence rewrite: that hunk is no glyph-for-glyph substitution, so the sampling condition fails and the run must offer no sampled set. A negated "not offered" sentence does not read as an offer. |
| `triage_pass_routes_missed_hit` | ledger `row_source` + roster + briefs + ledger gate records | The triage row, its brief's page list, and the writer row sourced from a triage finding are disk facts; the answered widening gate and the announcement's quoted answer are the decision's record. |
| `move_integrity_flags_low_similarity` | gate log + tree hash + report | The move-integrity log is the gate's own record, and its second low-threshold pass supplies the delete-plus-add path's similarity; the tree hash proves the run changed nothing, and the report's table is the prose half. |
| `leading_option_objection_in_packet` | ledger disposition + report | The refuter's accepted finding is on disk, so its surfaced disposition and packet id are the ledger fact; the report's decision-packet line is the prose half that lists the leading option with that objection. |
| `unnarrowed_flag_blocks_deliverable` | roster + return + deliverable bytes + report | The accepted flag-ledger pass row and its return naming the entry are disk facts; the deliverable's bytes then decide the branch, and the unchanged branch's blocking entry and no-clean-close sentence are the report half. |
| `refuter_alternative_becomes_fork` | ledger disposition + source hashes + report | The alternative record's surfaced disposition with its packet id is the ledger fact; byte-identical sources prove no edit landed, and the report's decision packet carries the alternative with its derivation. |
| `snapshot_search_positive_control` | sweeper briefs + accepted returns | The control token is a property of each brief, and the accepted return's hit record or blind full-read list is the return half, so the briefs and returns are the only witnesses. |
| `contradicting_checkers_gated` | page hash + open gate record | Two accepted checker returns disagree on one claim, so the conflict is a ledger fact: the page's bytes prove no edit landed, the unanswered gate names both rows, and the absent own-authority record is the separate half that an open gate alone does not carry. |
| `instruction_rule_forked` | `AGENTS.md` hash + open fork record | Writing a standing rule into the instruction file is the fork, so the instruction file's bytes prove it was not written, the open fork or gate names it, and no own-authority record settles the fork. |
| `completed_task_routed` | completed-task hash + ledger fork and routing records | The finished task's bytes prove the repair did not touch it, the open fork or gate names the file, the routing record names `task_finish` or `task_audit`, and no own-authority record settles it. |

### Prompt, fixture, and grader notes for the 2026-11-11 judgement-containment run

The rewritten probe, ladder, plan, and judgement blocks changed what several
existing runs needed. Each change is a prompt clarification, a fixture fact, or
a grader broadening backed by a captured correct run; no check was weakened.

- `probe_definitions_no_spawn`: its prompt now ends "Tell me whether those three
  definitions are callable." It answers no pre-dispatch gate. The rewritten
  `<capability_probe>` states the deployment-versus-callability rule but a run
  no longer mentioned the definitions unprompted, so the eval asks the question
  it grades.
- `role_depth_recorded`: its 2026-11-11 prompt wrote the report before the
  final close and named the tally-block requirement, because `close` condition
  7 refuses while `report.md` lacks the current tally block. The 2026-11-26
  prompt rewrite removed that instruction with the rest of the stated rule;
  `## Prompt selection` records the removal, and the recorded results below
  carry the verdict the shorter prompt earned. It answers no pre-dispatch
  gate; the fixture stages the run mid-flight.
- `judgement_surfaced`: its prompt is unchanged. Its fixture's `NOTES.txt` now
  adds "Nobody has decided whether the legacy section should be removed.", so
  the removal's undecided state is a repository fact rather than an inference
  from a vague clean-up ask.
- `depth_one_level`: its prompt is unchanged. Its fixture's `NOTES.txt` now
  states that the generated reference page is a later job for its own run,
  which is the nested-entry fact the eval grades.
- `excluded_named_with_reason` accepts the slug form beside the path form.
  Evidence: `run-20261111-212524/inline_floor` announces "Excluded: changelog
  (generated file), index (documents no command), migrate (retired and not
  maintained)."
- The depth eval's "needs its own run" pattern accepts "later run" and "later
  job". Evidence: `run-20261111-215324/depth_one_level`.
- `judgement_surfaced`'s "leaves the decision unsettled" pattern accepts "held
  for the gate" and "no clean-up edit landed". Evidence:
  `run-20261111-213903/judgement_surfaced`.
- `baseline_lint_without_stash` accepts a snapshot baseline copy as well as a
  `baseline/copies/` path. Evidence: `run-20261111-175854/
  baseline_lint_without_stash` names `.agent_spinner/snapshots/page-base/docs/
  page.md`.
- `no_brief_grants_status_write` requires a grant verb beside the status field,
  so a wrapped "leave untouched" list that mentions the stamp is not read as a
  grant. Evidence: `run-20261111-190432/stamp_routed_on_any_rewrite`.
- `ledger_open_fork_or_gate` treats a fork disposed as `surfaced` as open until
  answered. Evidence: `run-20261111-193401/committed_rule_deletion_surfaced`.
- `checker_model_differs_from_producer` falls back to the writer row at the
  same path when the run recorded no relay. Evidence:
  `run-20261111-185708/cross_model_checker_recorded`.
- `run_stopped_at_gate` requires the stop the shipped ledger records: no
  dispatch row, the `STOP` marker under the run's `.agent_spinner/`, the
  unanswered user gate still open, and a run that is not `closed: true`. The
  ledger's condition 6 refuses `close` while a gate is unanswered, so
  `close --stopped` exits 3 and a clean close cannot be a pre-dispatch stop.
  Evidence: `run-20261111-221842/unanswered_gate_stops_with_packet` records
  `closed: false`, a `STOP` marker, and an open `user_gate`.
- `unanswered_gate_stops_with_packet`: its prompt now states the helper limit as
  a hard cap the run may not shrink around, says the over-budget call is the
  user's and must come back unanswered, and states there is no later turn to
  wait for. The earlier "use at most 5 helpers" wording read as an instruction
  to fit inside the cap: a run narrowed the verification scope to 5 of 30 pages
  and closed cleanly, with the guideline quoted as the gate's answer
  (`run-20261111-232108`, `run-20261111-233439`). A second version that dropped
  only the closing "close the run as stopped" sentence kept the gate open but
  left the run resumable, with no `STOP` marker
  (`run-20261112-000104`). A still earlier version that ended "close the run as
  stopped" was recorded as the gate's answer (`run-20261111-225835`), which is
  why the final prompt states the host condition rather than the closing move.
  The final prompt keeps the gate unanswered and states the single-turn host,
  which is the condition the shipped protocol binds to `close --stopped`.
  Evidence: `run-20261112-000846` and
  `run-20261112-001515` each pass 8 of 8 with zero dispatch rows, a `STOP`
  marker, an open `user_gate`, and `closed: false`.

Seven evals additionally run the shared closing-report contract: the opening
verdict with its tier and dispatched-against-returned count, the yield clause,
the separated lists, and no pasted helper return shape. Those are the evals
whose run reaches a closing report; an eval that stops before dispatch has no
dispatch arithmetic to carry.

Two of the three lists hold what a *helper* contributed, so they are asserted
only where the fixture staged helper returns. A run that answered inline and
spent no helper has no members for them, and failing a correct report for
omitting an empty list would assert ceremony rather than the separation the
contract is about.

## Three capture files, and why they exist

`claude -p` returns only the worker's last turn, so the pre-dispatch
announcement and the body of a phased run never reach the captured response.
The worker therefore writes its announcement to `.agent_spinner/announcement.txt`
and its closing report to `.agent_spinner/report.md`, alongside the roster and
the briefs. `grade.sh` reads a pre-dispatch claim from the announcement, the
verdict-first opening from the report, and falls back to the response when a
run said everything in one turn. Without those files a correct run fails on the
harness's capture limit rather than on its own behaviour.

## Runner modes

Each eval opts into a mode through its `harness` block; an absent key leaves
that mode off.

| Key | Value | Effect |
| --- | --- | --- |
| `inline_body` | `true` | The first turn carries the deployed skill body inline, in place of the path-read steps. |
| `second_turn` | `{"prompt": "...", "between": "fixtures/<id>/between_turns.sh"}` | After the first turn the runner runs the optional `between` script, then sends `prompt` as a second turn through the resume path. |
| `agents` | repository- or evals-relative paths | Each file is staged as a discoverable agent definition before the first turn. A fixture's mock agent lives under `fixtures/<id>/agents/`; a shipped plugin role is named by its repository path, as `checker_spawned_through_role` names `plugins/ai_dev/agents/auto_checker_spinner.md`. |
| `disallowed_tools` | tool classes: `spawn`, `shell`, `write` | Each class is withheld under the withheld-tool rule. |
| `needs_real_absence` | `true` | The eval's expected behaviour rests on a withheld tool being truly absent, and the runner reports a run where that absence is only declared. |
| `tool_record` | `true` | Every turn streams its events, and the runner writes the tool calls they show to `tool_calls.jsonl` beside `response.txt`. |
| `timeout` | seconds | The eval's own worker bound, overriding `--timeout`. A spawned-helper eval that stages several real passes needs more wall clock than the default, and this keeps the extra patience scoped to that eval. |
| `deploy_skills` | skill names | Each named skill joins the pass's micro-deployment, and the cache key through the declaration, without adding a line to the prompt. It serves a skill the run reaches by routing rather than through a path the prompt names, as `stamp_routed_on_any_rewrite` and `stamped_target_routed_to_owner` deploy `task`, the family that owns their stamped target. |

A worker that times out, exits non-zero, or returns nothing leaves an
inconclusive eval rather than a graded failure. The runner still grades the
state it left, but `grading.txt` then opens with an `INCONCLUSIVE:` line
naming the cause, and the eval's entry in `summary.json` carries
`completed: false` and that `verdict_note`, so a stored run never reads a
timeout as a behavioural fail.

### The two response files

A two-turn eval writes the first turn's final message to `response_turn1.txt`
and the last turn's to `response.txt`, which `grade.sh` keeps reading. The eval
completes only when every turn completes, and a failed first turn sends no
second.

### The tool record

An eval with `tool_record` writes `tool_calls.jsonl` from the parsed stream
records alone, tagged by turn. Each record carries its class, the tool name the
stream records, the helper name a spawn call names, the raw per-vendor input,
the result text, and the failure bit. Claude's stream also yields an
`offered_tools` record from its init tool list; Cursor's init lists no tools,
so a Cursor run yields none. A Cursor parent's record carries no helper calls:
the CLI keeps them out of the parent's stream, so a case that needs a helper's
own calls asserts a filesystem fact or reads the helper's transcript.

### Withheld tools

`tests/lib/vendor.py` holds the rule's table, one row per class. `withheld_by`
names the mechanism: `cli-flag` for a command-line flag, `cli-config` for the
CLI's project config file, and `declared-absence` for the prompt note.

| Class | Claude tool names | Cursor stream kind | Claude route | Cursor route | `withheld_by` |
| --- | --- | --- | --- | --- | --- |
| `spawn` | `Agent`, `Task`, `Workflow` | `taskToolCall` | the declared-absence note | the declared-absence note | `declared-absence` on both |
| `shell` | `Bash` | `shellToolCall` | `--disallowedTools Bash` | the deny entry `Shell(*)` | `cli-flag` on Claude, `cli-config` on Cursor |
| `write` | `Edit`, `Write`, `NotebookEdit` | `editToolCall` | `--disallowedTools Edit,Write,NotebookEdit` | the deny entry `Write(**)` | `cli-flag` on Claude, `cli-config` on Cursor |

No vendor session mode serves as a read-only session. Claude's
`--permission-mode plan` blocked project writes but wrote a plan file into the
user's own configuration directory, and Cursor's `--mode ask` under `--force`
let both a file write and a shell command succeed, while `--mode plan` refused
edits to non-markdown files and left the shell callable (probe of 2026-10-04).
The runner therefore withholds by class and runs no session mode in its place.

A staged role lacks its classes through its own lever instead, which
`stage_agents` renders per vendor: Claude's `tools:` allowlist or Cursor's
`readonly: true`, both of which held in print mode. `stage_agents` keeps the
body unchanged, so the body's prompt-level prohibition reaches the role in the
same words on both vendors.

### Recorded results

**2026-11-02–03, Cursor CLI 2026.10.22-27dcf5f, model `auto`.** Resume pre-flight
passed. Every smoke eval and every existing eval that withholds a tool passed on
the default vendor.

| Eval | Result | Run |
| --- | --- | --- |
| `smoke_inline_body` | pass | `../workspace/run-20261103-003235` |
| `smoke_second_turn` | pass | `../workspace/run-20261103-003235` |
| `smoke_staged_agent` | pass | `../workspace/run-20261103-003235` |
| `smoke_withheld_shell` | pass | `../workspace/run-20261103-000611` |
| `smoke_withheld_write` | pass | `../workspace/run-20261103-000611` |
| `probe_definitions_no_spawn` | pass | `../workspace/run-20261102-234332` |
| `inline_floor` | pass | `../workspace/run-20261102-234332` |
| `governed_stop` | pass | `../workspace/run-20261102-234332` |
| `failure_taxonomy` | pass | `../workspace/run-20261102-234332` |
| `unreturned_bound` | pass | `../workspace/run-20261102-234332` |
| `uncited_clean_reroute` | pass | `../workspace/run-20261102-233850` |
| `duplicate_finding_union` | pass | `../workspace/run-20261102-234332` |
| `confirmation_provenance` | pass | `../workspace/run-20261102-234332` |
| `payload_cap` | pass | `../workspace/run-20261102-234332` |
| `report_rederivation` | pass | `../workspace/run-20261102-234332` |

Two defects surfaced in the first live pass. Cursor 2026.10.22 records a named
role as `subagentType: {"custom": {"name": "<role>"}}`; `_helper_name` now reads
that shape as well as the earlier string, so `smoke_staged_agent`'s spawn record
names `smoke_replier`. `smoke_second_turn`'s first failure was the host-checkout
guard seeing unrelated task-file edits made during the run; the owned-name
guard now blames only the host paths an eval's own sandbox names, so an
unrelated live edit whose basename no sandbox copy carries stays outside that
eval's verdict. `uncited_clean_reroute`
now stages a true clean verdict, so the missing citation is the only reason to
route back; its checks are unchanged.

### 2026-11-11, Cursor CLI 2026.10.22-27dcf5f, model `auto` — checking-doctrine blast radius

The component change (`SKILL.md`, `references/checks.md`,
`references/edit-mechanics.md`, `references/role-prompts.md`) and the eval
changes it ships reach the set
below. Each was re-run fresh (`--force`) after the last component edit, so
every passing run postdates every artifact under test. Where an eval appears
in the 2026-11-02–03 table above, the run here supersedes it as the verdict of
record. `--timeout` defaults to 900 now, because a spawned-helper run on this
vendor outlasts the old 420-second bound; `containment_one_path` carries its own
1200-second bound in `evals.json`, and `residual_selector` carries an
1800-second bound because its ten-input survey-and-synthesis run measured about
860 seconds on this vendor, which left too little headroom under load.

| Eval | Result | Run |
| --- | --- | --- |
| `merged_deliverable_checked` | pass | `../workspace/run-20261111-121049` |
| `documented_absence_stays_conditional` | pass | `../workspace/run-20261111-121049` |
| `probe_positive_control` | pass | `../workspace/run-20261111-121049` |
| `one_remediation_round` | pass | `../workspace/run-20261111-121049` |
| `residual_selector` | pass | `../workspace/run-20261111-121049` |
| `containment_one_path` | pass | `../workspace/run-20261111-121049` |
| `checker_reads_return_by_path` | pass | `../workspace/run-20261111-121049` |
| `stamped_target_routed_to_owner` | pass | `../workspace/run-20261111-121049` |
| `wrapped_contrast_and_quotation` | pass | `../workspace/run-20261111-124512` |
| `shape_matched_no_recipe` | pass | `../workspace/run-20261111-124512` |
| `clean_corpus` | pass | `../workspace/run-20261111-124512` |
| `unverified_band_sampled` | pass | `../workspace/run-20261111-124512` |
| `payload_cap` | pass | `../workspace/run-20261111-124512` |

Every eval outside that set keeps its recorded verdict, named below with the
run it relies on. The three evals whose newest recorded run predates this
task's component rewrite (`charter_conflict`, `judgement_surfaced`,
`roster_partial_stop`) are outside the change's blast radius and keep that
run.

| Eval | Result | Recorded run |
| --- | --- | --- |
| `aborted_writer_settled_from_diff` | pass | `../workspace/run-20261108-180638` |
| `acceptance_presence_on_every_surface` | pass | `../workspace/run-20261111-103456` |
| `attached_body_opens_and_closes_ledger` | pass | `../workspace/run-20261108-180638` |
| `changed_false_still_checked` | pass | `../workspace/run-20261108-180638` |
| `charter_conflict` | pass | `../workspace/run-20261015-095519` |
| `completion_turn_advances_phase` | pass | `../workspace/run-20261108-180638` |
| `confirmation_provenance` | pass | `../workspace/run-20261111-100623` |
| `continuation_armed_once` | pass | `../workspace/run-20261108-192757` |
| `count_check_cannot_clear_meaning` | pass | `../workspace/run-20261111-103456` |
| `decision_items_past_line_100` | pass | `../workspace/run-20261108-180638` |
| `declared_shape_switch_named` | pass | `../workspace/run-20261108-180638` |
| `depth_one_level` | pass | `../workspace/run-20261108-185753` |
| `diagnostic_inline` | pass | `../workspace/run-20261110-111507` |
| `duplicate_finding_union` | pass | `../workspace/run-20261111-111927` |
| `explicit_spinner_on_family_job` | pass | `../workspace/run-20261110-114924` |
| `failure_taxonomy` | pass | `../workspace/run-20261111-110729` |
| `gate_scope_checked_before_dispatch` | pass | `../workspace/run-20261108-180638` |
| `governed_stop` | pass | `../workspace/run-20261110-111507` |
| `hollow_plan_blocks_writes` | pass | `../workspace/run-20261108-184030` |
| `inline_floor` | pass | `../workspace/run-20261107-190758` |
| `judge_flaws_capped` | pass | `../workspace/run-20261111-100623` |
| `judgement_surfaced` | pass | `../workspace/run-20261015-095519` |
| `known_false_control_caught` | pass | `../workspace/run-20261111-100623` |
| `labelled_forks_all_relayed` | pass | `../workspace/run-20261108-180638` |
| `ledger_unavailable_by_hand` | pass | `../workspace/run-20261108-180638` |
| `lint_warning_delta_reported` | pass | `../workspace/run-20261108-180638` |
| `mandated_step_listed` | pass | `../workspace/run-20261108-180638` |
| `pause_request_stops_dispatch` | pass | `../workspace/run-20261108-180638` |
| `phase_plan_announcement` | pass | `../workspace/run-20261107-180125` |
| `placeholder_figure_held` | pass | `../workspace/run-20261111-102240` |
| `planted_defect` | pass | `../workspace/run-20261111-111927` |
| `probe_definitions_no_spawn` | pass | `../workspace/run-20261102-234332` |
| `readonly_checker_returns_by_message` | pass | `../workspace/run-20261108-180638` |
| `remediator_refutes_false_finding` | pass | `../workspace/run-20261111-100623` |
| `report_rederivation` | pass | `../workspace/run-20261111-111927` |
| `roster_partial_stop` | pass | `../workspace/run-20261015-095519` |
| `ruling_applies_to_class` | pass | `../workspace/run-20261111-103456` |
| `skipped_close_reported` | pass | `../workspace/run-20261108-180638` |
| `smoke_inline_body` | pass | `../workspace/run-20261106-230911` |
| `smoke_second_turn` | pass | `../workspace/run-20261103-003235` |
| `smoke_staged_agent` | pass | `../workspace/run-20261103-003235` |
| `smoke_withheld_shell` | pass | `../workspace/run-20261106-230911` |
| `smoke_withheld_write` | pass | `../workspace/run-20261103-000611` |
| `surplus_read_proposes_removal` | pass | `../workspace/run-20261111-103456` |
| `survived_lenses_labelled_recall` | pass | `../workspace/run-20261111-101317` |
| `twelve_files_twelve_rows` | pass | `../workspace/run-20261111-110729` |
| `unapproved_hunk_after_regeneration` | pass | `../workspace/run-20261111-102240` |
| `uncited_clean_reroute` | pass | `../workspace/run-20261111-104535` |
| `unlabelled_returns_joined_by_id` | pass | `../workspace/run-20261108-180638` |
| `unreturned_bound` | pass | `../workspace/run-20261111-110729` |
| `verdict_waits_for_open_checker` | pass | `../workspace/run-20261108-180638` |
| `verifier_brief_carries_no_preference` | pass | `../workspace/run-20261111-102240` |
| `verifier_rows_from_findings` | pass | `../workspace/run-20261108-180638` |

### 2026-11-11, Cursor CLI 2026.10.22-27dcf5f, model `auto` — judgement containment

The twelve new evals ran fresh against the rewritten blocks. Each passed on
the default vendor in the run named, and the Claude-only eval ran in its own
`--vendor claude` run. Where a later grader or fixture fix landed, the eval
was re-run and the table names the run that carries its final verdict.

| Eval | Result | Run |
| --- | --- | --- |
| `committed_rule_deletion_surfaced` | pass | `../workspace/run-20261111-194337` |
| `stamp_routed_on_any_rewrite` | pass | `../workspace/run-20261111-193401` |
| `baseline_kept_on_partial_read` | pass | `../workspace/run-20261111-193401` |
| `baseline_lint_without_stash` | pass | `../workspace/run-20261111-183110` |
| `reader_gets_snapshot` | pass | `../workspace/run-20261111-223125` |
| `widening_needs_estimate_and_ask` | pass | `../workspace/run-20261111-223125` |
| `procedure_page_conflict` | pass | `../workspace/run-20261111-184635` |
| `unanswered_gate_stops_with_packet` | pass | `../workspace/run-20261112-001515` (also `../workspace/run-20261112-000846`) |
| `role_depth_recorded` | pass | `../workspace/run-20261111-190432` |
| `blind_pass_by_prompt` | pass | `../workspace/run-20261111-190432` |
| `wide_run_plans_session_boundary` | pass | `../workspace/run-20261111-190432` |
| `cross_model_checker_recorded` | pass | `../workspace/run-20261111-190018` (`--vendor claude`, model `sonnet`) |

The eleven default-vendor evals also pass together in
`../workspace/run-20261111-195004` (11 of 11, one from cache), but that
combined run covers the pre-revision versions of the evals whose later fixes
landed afterwards; the table above names the run carrying each final verdict.

### 2026-11-11, Cursor CLI, model `auto` — judgement-containment blast radius

The set named before the run is the eight evals whose expectations exercise
the rewritten probe, ladder, plan, and judgement blocks:
`probe_definitions_no_spawn`, `inline_floor`, `phase_plan_announcement`,
`containment_one_path`, `depth_one_level`, `charter_conflict`,
`judgement_surfaced`, and `governed_stop`. All eight pass in
`../workspace/run-20261111-220007` (8 of 8, one from cache), with the three
spawn-withheld evals recording `withheld_by: declared-absence`.

Every other existing eval keeps the verdict named in the tables above; the
five `smoke_*` runner evals stay out of this set because they check runner
modes rather than these blocks.

### 2026-11-12, Cursor CLI, model `auto` — helper-role spawn routes

The two new role evals ran fresh against the shipped role files and the
existing agent_spinner body. No existing eval's fixture, grader branch, or
runner surface changed: the role files are new, the `grade.sh` additions are
two new case branches with their own helpers, and the runner's `agents` key is
unchanged. The blast radius is therefore the two new ids alone.

| Eval | Result | Run |
| --- | --- | --- |
| `checker_spawned_through_role` | pass | `../workspace/run-20261112-121014` |
| `checker_spawned_without_role` | pass | `../workspace/run-20261112-121014` |

### 2026-11-13, Claude Code 2.1.289, worker model and effort probe

These three Claude runs are the measurements behind the Claude worker default
in `tests/lib/vendor.py`, the latest `opus` alias at `high` effort. They
measured only the worker: agent_spinner's evals grade through `grade.sh` with
no judge, so no run here backs the judge default of `opus` at `xhigh`. Every
run used `claude` 2.1.289 on agent_spinner at commit `c592b42`. Their run
directories sit in local scratch space that no clone carries, so this section
is the record.

- **`sonnet`, full suite.** The whole suite ran on `--vendor claude` with the
  then-default `sonnet` worker. 56 of 93 evals passed and 36 failed.
  `checker_spawned_through_role` stayed inconclusive, because it outran a
  560-second wall-clock cap on both of its attempts. Every runner-level check
  passed, and the recorded Cursor verdicts for the same evals all pass. The
  `sonnet` failures came from skipped procedure rather than wrong answers: the
  worker reached the expected conclusions while leaving out the steps the skill
  requires.
- **Opus at low effort.** The set was the 36 `sonnet` failures, six `sonnet`
  passes, and the inconclusive `checker_spawned_through_role`, run with
  `--no-cache` through a wrapper around the worker binary that
  added `--effort low` to every `claude` command. It fixed 8 of the 36, failed
  `blind_pass_by_prompt` where `sonnet` had passed, and left
  `checker_spawned_through_role` inconclusive again. Most remaining failures hit
  the same checks `sonnet` failed. The median run took 89 seconds, against 57
  seconds for `sonnet`.
- **Opus at high effort.** The set was eight still-failing evals, two from each
  failure cluster (pre-dispatch plan, per-item fan-out, ledger records, report
  contract), run the same way with `--effort high` and a 500-second worker
  timeout. Failed checks fell from 28 at low effort to 6.
  `containment_one_path` and `placeholder_figure_held` passed.
  `documented_absence_stays_conditional` and `report_rederivation` each failed
  one check. `inline_floor`, `phase_plan_announcement`, `roster_partial_stop`,
  and `twelve_files_twelve_rows` hit the 500-second timeout with every check
  passing except the final report's opening, which a killed run never writes;
  those four account for four of the six failed checks. Runs took 182 to over
  500 seconds each, and the eight together cost about nine points of the
  five-hour usage window.

High effort is also the level the operator's own Claude Code sessions run at,
so a high-effort verdict measures the skill the way it is used. The runtime and
cost figures above are the basis for the runtime and cost guidance in
`tests/CLAUDE.md` and `tests/AGENTS.md`.

On the new defaults, `smoke_inline_body` passed on `--vendor claude` with the
worker on `opus` at `high` in `../workspace/run-20261114-001102`, whose
`timing.json` and cache record name both. A re-run with `--effort medium` took
no cache hit and passed in `../workspace/run-20261114-001331`.

### 2026-11-14, Claude Code 2.1.289, full suite on `opus` at `high`

The whole suite ran on `--vendor claude` with the new defaults, the worker on
the latest `opus` alias at `high` effort, at commit `a54b92c` with that
commit's review fixes still uncommitted in the working tree. The evals ran four
at a time in 24 batches, as supervised background commands with the runner's
own timeouts, because at high effort most evals outlast the ten-minute limit of
one foreground tool call. Of the 72 evals that reached a grade, the median run
took 289 seconds, 16 took longer than 540 seconds, and the longest took 958
seconds. The run cost about 77 points of the five-hour usage window and about
13 points of the weekly window. The run directories sit under
`../workspace/run-20261114-*`, which no clone carries, so this section is the
record.

- **48 passed and 24 failed** of the 72 evals that reached a grade.
- **20 never reached the worker**, because `stage.sh` rejected a staged helper
  return with `required key missing: objections`. The ledger phase 2 change
  made that key required, and at `a54b92c` these fixtures still staged returns
  without it:
  `checker_reads_return_by_path`, `confirmation_provenance`,
  `confirmed_class_swept_before_clean`, `known_false_control_caught`,
  `leading_option_objection_in_packet`, `move_integrity_flags_low_similarity`,
  `pause_request_stops_dispatch`, `refuter_alternative_becomes_fork`,
  `remediator_refutes_false_finding`, `repair_list_keyed_on_severity`,
  `report_rederivation`, `role_depth_recorded`,
  `routed_premise_sentences_landed`, `ruling_applies_to_class`,
  `skipped_close_reported`, `survived_lenses_labelled_recall`,
  `unnarrowed_flag_blocks_deliverable`, `unverified_band_sampled`,
  `verdict_waits_for_open_checker`, and `verifier_rows_from_findings`.
  Seventeen of them passed on `sonnet` on 2026-11-13, before that change.
  Commit `947f043` has since given every fixture return the key, so all 20
  stage again, but none of them has an `opus` result yet.
- **1 stayed inconclusive.** `checker_spawned_through_role` outran its fixed
  1200-second per-eval timeout, as it did on every earlier Claude run.
- **4 of the failures are the integrity check, not the grader.** The workers
  for `depth_one_level`, `explicit_spinner_on_family_job`,
  `stamp_routed_on_any_rewrite`, and `triage_pass_routes_missed_hit` read files
  under the host's real `~/.claude/agents` or `~/.claude/skills` outside the
  micro-deployment, so `artefacts_read_from_micro_deployment` failed.
- **Against the 2026-11-13 `sonnet` run**, on the 72 evals graded both times
  and across the skill changes between `c592b42` and `a54b92c`: `opus` passed
  16 evals `sonnet` failed (`aborted_writer_settled_from_diff`,
  `checker_spawned_without_role`, `count_check_cannot_clear_meaning`,
  `cross_model_checker_recorded`, `declared_shape_switch_named`,
  `documented_absence_stays_conditional`, `ledger_unavailable_by_hand`,
  `probe_definitions_no_spawn`, `procedure_page_conflict`,
  `residual_selector`, `shape_matched_no_recipe`,
  `snapshot_search_positive_control`, `twelve_files_twelve_rows`,
  `unreturned_bound`, `wide_run_plans_session_boundary`, and
  `widening_needs_estimate_and_ask`), and it failed 7 evals `sonnet` passed
  (`depth_one_level`, `judgement_surfaced`, `labelled_forks_all_relayed`,
  `stamped_target_routed_to_owner`, `unanswered_gate_stops_with_packet`,
  `uncited_clean_reroute`, and `unlabelled_returns_joined_by_id`). Both models
  failed the other 17 failures.

`phase_plan_announcement` and `clean_corpus` first outran the 900-second
default and were graded on a re-run with `--timeout 1800`; both failed.

#### Classification of the 2026-11-14 failures

A failure-by-failure review on 2026-11-14 re-graded copies of the stored
sandboxes. Most of the 24 graded failures, and two of the four integrity
failures, said nothing about the model. Replaying the
repaired grader over all 304 stored sandboxes (this run, the 2026-11-13 `sonnet`
and `opus` runs, and the older Cursor runs) cleared the false failures below
and introduced no new failure.

- **Stale fixtures, already fixed by `947f043`:** `one_remediation_round`,
  `payload_cap`, `decision_items_past_line_100`,
  `labelled_forks_all_relayed`, `unlabelled_returns_joined_by_id`,
  `completion_turn_advances_phase`, and `duplicate_finding_union`. Each
  staged or between-turns return lacked the `objections` key, so the worker's
  own `accept` refused it, as it refused the 20 unstaged evals. These seven
  have no `opus` result on the current fixtures yet, and the sonnet comparison
  above counts two of them against `opus` in error.
- **`judge_flaws_capped`:** its fixture recorded no input version for the
  candidate its judges examine, so every receipt was refused. The judge briefs
  now pass `--target`.
- **Grader false failures, repaired:** `judgement_surfaced`,
  `uncited_clean_reroute`, `placeholder_figure_held`,
  `stamped_target_routed_to_owner`, `explicit_spinner_on_family_job`,
  `phase_plan_announcement`, and `inline_floor`. Each run did what the skill
  asks, and the check read phrasing, a region, a record type, or a file count
  in place of the fact the run left on disk.
- **A contradictory prompt, repaired:** `sweep_rewrite_hunk_blocks_sampling`
  told the worker to leave every open choice to the user, so the run correctly
  held the reworded page as a fork. The prompt now has the worker choose the
  wording of any reword.
- **Integrity false positives, repaired in `tests/lib/micro_deploy.py`:** in
  `explicit_spinner_on_family_job` a colon in a ledger label cut an in-set
  path, and in `triage_pass_routes_missed_hit` a miscounted `..` climb named a
  path that does not exist. The other two integrity failures,
  `depth_one_level` and `stamp_routed_on_any_rewrite`, are real reads of the
  operator's home, because a Claude worker keeps the real `HOME`; the second
  also needed `task`, which the eval now deploys through `deploy_skills`.
- **A harness timeout, raised:** `checker_spawned_through_role` spent most of
  its fixed 1200 seconds inside two role spawns at `effort: max`, so it could
  never finish on Claude. Its bound is now 2400 seconds.
- **Model behaviour against a stated rule:** the opening-sentence checks in
  `clean_corpus`, `containment_one_path`, `planted_defect`, and
  `roster_partial_stop`, and the hand-written decision packet in
  `unanswered_gate_stops_with_packet`. The skill states both rules only in
  reference prose, and the backlog carries a task to make them hold.
- **A ledger contract gap:** `triage_pass_routes_missed_hit` lost its triage
  row because the rendered brief never says the return's `brief` key repeats
  its token. The backlog carries a task for the brief contract.

### 2026-11-14 evening, the repaired suite on Claude and on Cursor

Both vendors ran all 93 evals against the working tree carrying the fixes
above. Claude ran the worker on `opus` at `high` effort through
`claude` 2.1.289, in batches of four from a supervising session, with
previously failing evals first; it took one full five-hour usage window plus 6
points of the next, and 17 points of the weekly window. Cursor ran `auto`
through CLI 2026.10.22-27dcf5f with `--timeout 1500`. Every worker completed
on both vendors, so no eval was inconclusive. The run directories sit under
`../workspace/run-20261114-1[78]*` through `run-20261114-235233`, which no clone
carries.

| Vendor | Passed at run time | Passed after re-grading | Failed after re-grading |
| --- | --- | --- | --- |
| Claude `opus` at `high` | 72 of 93 | 81 of 93 | 12 |
| Cursor `auto` | 82 of 93 | 86 of 93 | 7 |

The re-grading column replays the grader as repaired after these runs over the
same stored sandboxes, with no worker re-run. The review behind it found
fourteen more false failures across the two runs: archived briefs in a
subfolder counted as finders, quoted or backticked read material taken as a
settled claim or as the report's own assertion, phrasing lists that missed
"no second round" and "`close --stopped` exited 3", a packet check that
demanded a literal option label, a probe check that read the announcement
alone, a modified-path check bound to one word, a sampling offer written as a
list item, a three-word gap in "later ... run", a worker's `roster.tsv.bak`
read in place of `roster.tsv`, a writer row graded on its kind column alone,
and read-only `finder` rows counted as writers. Replaying the repaired grader
over every stored sandbox of this and the earlier runs changed no other
verdict.

The `clean_corpus` fixture was repaired after these runs: its pages ran the
script by a bare name that does not resolve, and the script's comment
overstated its argument parsing, so a careful run found real defects in a
corpus meant to be clean. Its verdicts above predate that repair. Re-run on
the repaired fixture on 2026-11-15, it passed on Cursor with 12 of 12 checks
(`run-20261115-002747`) and failed on Claude on 3 checks
(`run-20261115-002758`): the Claude run found nothing false, yet counted five
omissions as findings, and its opening sentence missed the tier and the counts.

Each remaining failure belongs to a task in the backlog:

| Eval | Vendor | Failing check, in short | Owning task |
| --- | --- | --- | --- |
| `containment_one_path`, `roster_partial_stop`, `report_rederivation`, `skipped_close_reported` | Claude; the last also Cursor | the opening sentence misses the tier, the counts, or the close status | `ai-dev_agent-spinner-report-packet-enforcement` |
| `roster_partial_stop` | Claude | unknown rows not settled by reading | `ai-dev_agent-spinner-ledger-terminal-states` |
| `checker_spawned_through_role`, `snapshot_search_positive_control` | Claude; the first also Cursor | returns rejected for shapes and values the brief never stated, then lost on the identical retry | `ai-dev_agent-spinner-ledger-brief-contract` |
| `stamped_target_routed_to_owner` | Claude | rewrote the stamped task file, then recorded the routing | `ai-dev_agent-spinner-stamped-write-routing` |
| `widening_needs_estimate_and_ask`, `unanswered_gate_stops_with_packet` | Claude; Cursor | an unanswered fork closed cleanly, or a goal and a self-answer settled the gate | `ai-dev_agent-spinner-unanswered-fork-holds-run` |
| `wide_run_plans_session_boundary`, `shape_matched_no_recipe` | Claude; Cursor | routed inline as a read-only diagnostic, or matched the multi-file recipe without a task | `ai-dev_agent-spinner-selector-probe-definitions` |
| `checker_spawned_without_role` | Claude | the worker read the operator's own role definition and recorded a role route | `tests_claude-worker-scratch-home` |
| `payload_cap`, `sweep_rewrite_hunk_blocks_sampling` | both; Cursor | brief checks that ignore the by-path branch, and a sampling cue read from a negated sentence | `tests_agent-spinner-vacuous-graders` |
| `one_remediation_round` | Cursor | the text never says no second round follows, though none ran | none; the behaviour held |

### 2026-11-18, Cursor CLI 2026.11.13-eacade1, model `auto` — checking-pass default contract

The change rewrites one shared prompt surface, the `<checking>` block in
`SKILL.md`, together with C2 items 1–2 in `references/checks.md` and the
`## Checking pass` template in `references/role-prompts.md`. Every run loads
`<checking>`, so the reach set is the evals whose checklist source, or whose
graded checklist property, the rewritten sentence decides:

- `clean_corpus` and `planted_defect`: neither prompt names a contract source,
  so the default branch — one line per claim the artifact makes, in artifact
  order — builds the checklist both are graded against, and the omission rule
  decides whether a clean corpus stays clean.
- `acceptance_presence_on_every_surface`: its brief names `ACCEPTANCE.md`, and
  its grader asserts one checklist line per acceptance item, which is the
  named-source branch; C2 item 2's rewrite-only old-form test is the half that
  changed for a presence-only checklist.
- `checker_reads_return_by_path`: its brief names the item brief and an
  approved-edit list, and its grader asserts the ledger's one-hunk-per-edit
  mapping, which is the carve-out the rewritten sentence states.
- `unapproved_hunk_after_regeneration`: its brief names an approved-edit list,
  so the same carve-out keeps its checklist on those edits, and its grader
  reads that list in the brief.
- `count_check_cannot_clear_meaning`: its prompt names no contract source, so
  the default branch builds its checklist, and its grade reads the ledger
  finding that checklist produces ("The ledger holds a finding quoting the
  inverted sentence").

Every other eval is outside the set: each is graded on a file hash, roster row,
ledger record, or report clause that the checklist sentence does not feed. The
closest remaining case is `changed_false_still_checked`, which does write a
check brief: that brief names the diff and the baseline rather than a contract
source, and its grade reads the changed list rather than a checklist.

| Eval | Result | Run |
| --- | --- | --- |
| `clean_corpus` | pass (12 of 12 checks) | `../workspace/run-20261118-095637` |
| `planted_defect` | pass (13 of 13 checks) | `../workspace/run-20261118-095637` |
| `acceptance_presence_on_every_surface` | pass (9 of 9 checks) | `../workspace/run-20261118-095637` |
| `checker_reads_return_by_path` | pass (5 of 5 checks) | `../workspace/run-20261118-103038` |
| `unapproved_hunk_after_regeneration` | pass (4 of 4 checks) | `../workspace/run-20261118-101451` |
| `count_check_cannot_clear_meaning` | pass (5 of 5 checks) | `../workspace/run-20261118-114337` |

All six ran fresh (`--force`). Four of them (`clean_corpus`,
`planted_defect`, `acceptance_presence_on_every_surface`, and the first
`checker_reads_return_by_path`) started in `run-20261118-095637` at
`09:56:38`, against the committed artifacts of `11d6139`
(`2026-11-18T09:29:29+0100`). The C2 item 1 clarification in
`references/checks.md` was written uncommitted at `09:58:34+0100`, after those
four micro-deploy copies were taken, so they measure the pre-clarification
text. `unapproved_hunk_after_regeneration` (`run-20261118-101451`, 4 of 4) and
the re-run of `checker_reads_return_by_path` (`run-20261118-103038`, 5 of 5)
both postdate that edit. `count_check_cannot_clear_meaning`
(`run-20261118-114337`, 5 of 5) postdates every artifact above and the owner's
reach-set decision. The item-brief and approved-edit branch therefore
rests on `run-20261118-103038`; `clean_corpus`, `planted_defect`, and
`acceptance_presence_on_every_surface` stand on the pre-clarification
artifacts. `clean_corpus` reports zero findings and records what it examined
and cleared. That verdict
follows the pre-change Cursor pass on the repaired fixture,
`run-20261115-002747`, and it answers the Claude run `run-20261115-002758`,
whose checking pass counted five omissions as findings. `planted_defect` still
names its planted defect, against its pre-change run
`run-20261111-111927`. The `clean_corpus` row in the failure table above is
cleared and removed, because its omission counting no longer reproduces.

Every eval outside that set keeps its recorded verdict, carried by the
2026-11-14 evening Cursor full-suite run: 86 of 93 passed after re-grading, and
`../workspace/run-20261114-175823` holds all 93 verdicts. The seven failures are
the Cursor rows of the failure table above, each with its owning task except
`one_remediation_round`, whose row records none because the behaviour held.

| Eval | Result | Recorded run |
| --- | --- | --- |
| `aborted_writer_settled_from_diff` | pass | `../workspace/run-20261114-175823` |
| `attached_body_opens_and_closes_ledger` | pass | `../workspace/run-20261114-175823` |
| `attached_body_reads_recipe` | pass | `../workspace/run-20261114-175823` |
| `baseline_kept_on_partial_read` | pass | `../workspace/run-20261114-175823` |
| `baseline_lint_without_stash` | pass | `../workspace/run-20261114-175823` |
| `blind_pass_by_prompt` | pass | `../workspace/run-20261114-175823` |
| `changed_false_still_checked` | pass | `../workspace/run-20261114-175823` |
| `charter_conflict` | pass | `../workspace/run-20261114-175823` |
| `checker_spawned_through_role` | fail | `../workspace/run-20261114-175823` |
| `checker_spawned_without_role` | pass | `../workspace/run-20261114-175823` |
| `committed_rule_deletion_surfaced` | pass | `../workspace/run-20261114-175823` |
| `completion_turn_advances_phase` | pass | `../workspace/run-20261114-175823` |
| `confirmation_provenance` | pass | `../workspace/run-20261114-175823` |
| `confirmed_class_swept_before_clean` | pass | `../workspace/run-20261114-175823` |
| `containment_one_path` | pass | `../workspace/run-20261114-175823` |
| `continuation_armed_once` | pass | `../workspace/run-20261114-175823` |
| `cross_model_checker_recorded` | pass | `../workspace/run-20261114-175823` |
| `decision_items_past_line_100` | pass | `../workspace/run-20261114-175823` |
| `declared_shape_switch_named` | pass | `../workspace/run-20261114-175823` |
| `depth_one_level` | pass | `../workspace/run-20261114-175823` |
| `diagnostic_inline` | pass | `../workspace/run-20261114-175823` |
| `documented_absence_stays_conditional` | pass | `../workspace/run-20261114-175823` |
| `duplicate_finding_union` | pass | `../workspace/run-20261114-175823` |
| `explicit_spinner_on_family_job` | pass | `../workspace/run-20261114-175823` |
| `failure_taxonomy` | pass | `../workspace/run-20261114-175823` |
| `gate_scope_checked_before_dispatch` | pass | `../workspace/run-20261114-175823` |
| `governed_stop` | pass | `../workspace/run-20261114-175823` |
| `hollow_plan_blocks_writes` | pass | `../workspace/run-20261114-175823` |
| `inline_floor` | pass | `../workspace/run-20261114-175823` |
| `judge_flaws_capped` | pass | `../workspace/run-20261114-175823` |
| `judgement_surfaced` | pass | `../workspace/run-20261114-175823` |
| `known_false_control_caught` | pass | `../workspace/run-20261114-175823` |
| `labelled_forks_all_relayed` | pass | `../workspace/run-20261114-175823` |
| `leading_option_objection_in_packet` | pass | `../workspace/run-20261114-175823` |
| `ledger_unavailable_by_hand` | pass | `../workspace/run-20261114-175823` |
| `lint_warning_delta_reported` | pass | `../workspace/run-20261114-175823` |
| `mandated_step_listed` | pass | `../workspace/run-20261114-175823` |
| `merged_deliverable_checked` | pass | `../workspace/run-20261114-175823` |
| `move_integrity_flags_low_similarity` | pass | `../workspace/run-20261114-175823` |
| `one_remediation_round` | fail | `../workspace/run-20261114-175823` |
| `pause_request_stops_dispatch` | pass | `../workspace/run-20261114-175823` |
| `payload_cap` | fail | `../workspace/run-20261114-175823` |
| `phase_plan_announcement` | pass | `../workspace/run-20261114-175823` |
| `placeholder_figure_held` | pass | `../workspace/run-20261114-175823` |
| `probe_definitions_no_spawn` | pass | `../workspace/run-20261114-175823` |
| `probe_positive_control` | pass | `../workspace/run-20261114-175823` |
| `procedure_page_conflict` | pass | `../workspace/run-20261114-175823` |
| `reader_gets_snapshot` | pass | `../workspace/run-20261114-175823` |
| `readonly_checker_returns_by_message` | pass | `../workspace/run-20261114-175823` |
| `refuter_alternative_becomes_fork` | pass | `../workspace/run-20261114-175823` |
| `remediator_refutes_false_finding` | pass | `../workspace/run-20261114-175823` |
| `repair_list_keyed_on_severity` | pass | `../workspace/run-20261114-175823` |
| `report_rederivation` | pass | `../workspace/run-20261114-175823` |
| `residual_selector` | pass | `../workspace/run-20261114-175823` |
| `role_depth_recorded` | pass | `../workspace/run-20261114-175823` |
| `roster_partial_stop` | pass | `../workspace/run-20261114-175823` |
| `routed_premise_sentences_landed` | pass | `../workspace/run-20261114-175823` |
| `ruling_applies_to_class` | pass | `../workspace/run-20261114-175823` |
| `shape_matched_no_recipe` | fail | `../workspace/run-20261114-175823` |
| `skipped_close_reported` | fail | `../workspace/run-20261114-175823` |
| `smoke_inline_body` | pass | `../workspace/run-20261114-175823` |
| `smoke_second_turn` | pass | `../workspace/run-20261114-175823` |
| `smoke_staged_agent` | pass | `../workspace/run-20261114-175823` |
| `smoke_withheld_shell` | pass | `../workspace/run-20261114-175823` |
| `smoke_withheld_write` | pass | `../workspace/run-20261114-175823` |
| `snapshot_search_positive_control` | pass | `../workspace/run-20261114-175823` |
| `stamp_routed_on_any_rewrite` | pass | `../workspace/run-20261114-175823` |
| `stamped_target_routed_to_owner` | pass | `../workspace/run-20261114-175823` |
| `surplus_read_proposes_removal` | pass | `../workspace/run-20261114-175823` |
| `survived_lenses_labelled_recall` | pass | `../workspace/run-20261114-175823` |
| `sweep_rewrite_hunk_blocks_sampling` | fail | `../workspace/run-20261114-175823` |
| `sweep_sampling_needs_user` | pass | `../workspace/run-20261114-175823` |
| `triage_pass_routes_missed_hit` | pass | `../workspace/run-20261114-175823` |
| `twelve_files_twelve_rows` | pass | `../workspace/run-20261114-175823` |
| `unanswered_gate_stops_with_packet` | fail | `../workspace/run-20261114-175823` |
| `uncited_clean_reroute` | pass | `../workspace/run-20261114-175823` |
| `unlabelled_returns_joined_by_id` | pass | `../workspace/run-20261114-175823` |
| `unnarrowed_flag_blocks_deliverable` | pass | `../workspace/run-20261114-175823` |
| `unreturned_bound` | pass | `../workspace/run-20261114-175823` |
| `unverified_band_sampled` | pass | `../workspace/run-20261114-175823` |
| `verdict_waits_for_open_checker` | pass | `../workspace/run-20261114-175823` |
| `verifier_brief_carries_no_preference` | pass | `../workspace/run-20261114-175823` |
| `verifier_rows_from_findings` | pass | `../workspace/run-20261114-175823` |
| `wide_run_plans_session_boundary` | pass | `../workspace/run-20261114-175823` |
| `widening_needs_estimate_and_ask` | pass | `../workspace/run-20261114-175823` |
| `wrapped_contrast_and_quotation` | pass | `../workspace/run-20261114-175823` |

### 2026-11-19, Cursor CLI 2026.11.13-eacade1, model `auto` — vacuous-grader repair

The change makes the checks that passed on a no-op or on a run breaking their
own rule fail. Every touched eval was re-run fresh (`--force`) on the default
vendor: the grader change and the two fixture edits invalidate the verdict
cache, so nothing replays. `run-20261119-093714` holds all seventeen verdicts.

| Eval | Result | Failing check |
| --- | --- | --- |
| `sweep_sampling_needs_user` | pass (5 of 5) | — |
| `sweep_rewrite_hunk_blocks_sampling` | pass (4 of 4) | — |
| `changed_false_still_checked` | pass (3 of 3) | — |
| `blind_pass_by_prompt` | pass (5 of 5) | — |
| `judge_flaws_capped` | pass (6 of 6) | — |
| `inline_floor` | pass (15 of 15) | — |
| `checker_spawned_through_role` | pass (7 of 7) | — |
| `phase_plan_announcement` | pass (15 of 15) | — |
| `containment_one_path` | pass (14 of 14) | — |
| `planted_defect` | pass (13 of 13) | — |
| `clean_corpus` | pass (12 of 12) | — |
| `report_rederivation` | pass (13 of 13) | — |
| `judgement_surfaced` | pass (6 of 6) after re-grading | — |
| `payload_cap` | fail (4 of 8) | the synthesis brief names no return path and states no numeric cap, so it satisfies neither branch |
| `unreturned_bound` | fail (5 of 7) | the run spent gamma's single allowed re-invocation and accepted it, so the roster ends `accepted` |
| `depth_one_level` | fail (7 of 8) | `asks for the decision`: the report never asks |
| `roster_partial_stop` | fail (15 of 16) | `settles the unknown ones by reading the files`; the check predates this change |

The four failures are behaviour findings, not grader regressions. Each failing
run did not do what its eval asks: `payload_cap`'s brief says "at their relay
paths" without naming them and "at a payload cap" without a number;
`unreturned_bound`'s run re-invoked the past-bound helper and accepted it, so
the final roster state is `accepted`; `depth_one_level`'s report names no
user-directed ask; `roster_partial_stop`'s report does not say the unknown rows
were settled by reading. `unreturned_bound` is revisited here: the ledger
records no intermediate `unreturned` state, so a check that accepted a final
`accepted` gamma would also pass a run that never marked it unreturned, and the
check stays. `judgement_surfaced` failed `asks for the go-ahead` on
"make no edit until you choose a reading" until the cue gained the
second-person verbs (`you choose|answer|decide|pick`); the captured sandbox was
re-graded after that broadening and passes 6 of 6.

The go-ahead cue also accepts a plain user-directed question
(`open question for you|for you to approve|or another option you name`), so a
statement such as "The section which you should remove is the legacy one" never
satisfies it. Two captured compliant runs ask in interrogative form
rather than naming a decision: `run-20261114-175823/judgement_surfaced` asks
"Which reading of 'clean the page up' should Design take … or another option
you name?" and `run-20261113-092948/depth_one_level` asks "Open question for
you: should a later run change the 40 paths…?". Both re-grade clean (6 of 6 and
8 of 8). The captured runs that already asked in the second person stay clean
too: `run-20261114-190452/depth_one_level` (8 of 8),
`run-20261114-071821/depth_one_level` (8 of 8), and
`run-20261114-075403/judgement_surfaced` (6 of 6). The report's own headings and
tally lines still fail the cue.

**The blind permits check reads the input, not its name.**
`run-20261114-092233/blind_pass_by_prompt` permits `.agent_spinner/intent.md`,
whose text carries no hypothesis; the run kept "45 seconds" in
`hypothesis.withheld.txt`, which the brief does not permit. The check now reads
each permitted input and fails only when that file's own text carries the
hypothesis, so that run re-grades 5 of 5 while a permitted input that does quote
it still fails. `script_tests/grade_cases.sh` proves both directions (a clean
permitted `intent.md` passes, a `request.txt` quoting the hypothesis fails).
The directory-wide `no brief carries the hypothesis text` check is unchanged.

**The no-op probe.** Staging each touched eval and grading it with an empty
response and no agent action fails every repaired check that reads a
run-produced artifact: the accepted-row check, the sampled-out check, the
check-row brief check, the blind row's permits check, the three synthesis-brief
checks, the unreturned roster check, the checking-pass check, and the probe
delegation check. The two absence checks — `no brief carries the hypothesis
text` and `offers no sampled checker set` — pass on a no-op because their
artifact is absent; `script_tests/grade_cases.sh` proves each fail-able by
staging the forbidden artifact (a brief carrying "45 seconds", and a real
sampling offer). With a one-word response instead of an empty one, the guarded
report checks fail too (`asks for the decision`, `asks for the go-ahead`, the
opening tier and dispatch arithmetic, the yield clause, and the established
list), so no repaired check passes on a run that left nothing behind.

### 2026-11-19, Cursor CLI 2026.11.13-eacade1, model `auto` — run-path evals

Six evals cover run paths no earlier eval exercised: the residual sweep, a
pause request with no planted STOP, an item failed twice, unprompted
verification, the family job past approval, and the beyond-brief find. All six
ran fresh (`--force`) on the default vendor in `../workspace/run-20261119-203239`,
after the last edit to `grade.sh`, `evals.json`, and every fixture `setup.sh`,
so each verdict postdates every artifact under test. Three pass and three fail;
the failures are behaviour findings and no grader, fixture, or expectation was
changed to clear them.

| Eval | Result | Failing check |
| --- | --- | --- |
| `residual_sweep_finds_missed_target` | pass (8 of 8) | — |
| `pause_request_writes_stop` | pass (3 of 3) | — |
| `twice_failed_item_marked_failed` | fail (3 of 4) | `the report offers the inline redo as the user's choice` |
| `unprompted_verification_before_write` | fail (5 of 7) | `a verify row exists for each of the three findings`; `every verify brief predates the first writer brief` |
| `family_job_post_write_check` | fail (3 of 4) | `no orchestrator write lands on a family file` |
| `beyond_brief_find_reported` | pass (5 of 5) | — |

The first run (`run-20261119-195829`) showed three fixtures or graders at
fault, and each was corrected before the fresh run above. Its
`residual_sweep_finds_missed_target` fixture left the three rewritten pages
carrying the target, so the run correctly found four residuals where the
fixture meant one, and its class lived on the finding's claim ("missed
residual(s) of hyphenated email class") rather than on the disposition. The
fixture now rewrites the three pages, and the class check reads the finding
record or its disposition, which is where C8.2 puts the class. Its
`twice_failed_item_marked_failed` fixture staged a second invalid return for
the run to accept, but the run re-invoked the item and produced a valid
return, so the item was repaired rather than failed — the fixture's premise was
unsatisfiable. The fixture now records the second rejection itself and leaves
the row `failed`. Its `family_job_post_write_check` fixture's pointer-only page
linked a file that existed, so it was corrected to link a missing `INSTALL.md`.

**Skill finding — `twice_failed_item_marked_failed`.** The run leaves the row
`failed` and `docs/alpha.md` byte-identical, but it never puts the inline redo
to the user: its only sentence is "a degraded inline redo waits for the user's
choice and was not started", a third-person status line. `the report offers the
inline redo as the user's choice` needs a user-directed offer, and no sentence
addresses the user. The run named the choice without offering it.

**Skill finding — `unprompted_verification_before_write`.** The run verified
all three findings and refuted the contradicted one with its settling span, but
it recorded that work as `recheck:` rows after the writer rows. Its roster goes
survey → three writer rows → three recheck rows → two check rows, and no row
carries a verifying role with a `row_source` naming one of the three findings,
so `a verify row exists for each of the three findings` and `every verify brief
predates the first writer brief` fail. The verification is real, yet the ledger
cannot establish that it happened before the writes, which is the property this
eval grades.

**Skill finding — `family_job_post_write_check`.** The family writer changed
all five notes pages, and the run recorded the post-write `notes_lint` gate
result and five accepted check rows, but only `notes/alpha.md` carries a roster
row that names `notes_repairer`: the four other writer rows are `dropped` with
no path, and each changed page's diff is attributed to the finder that reported
it (`find:beta`, `find:gamma`, `find:delta`, `find:epsilon`). `no orchestrator
write lands on a family file` therefore fails, because the ledger cannot
attribute four of the five changed pages to the family writer rather than the
orchestrator.

### 2026-11-19, Cursor CLI 2026.11.13-eacade1, model `auto` — report opening and fork passages

The change makes every restatement of the report's opening carry all four facts
(the answer, the tier, helpers dispatched against returned, and whether `close`
exited 0) or point at `<reporting>`, and makes an anchored `passages` entry part
of the fork contract in `validate_return`, `show --packet`, the rendered closing
block, and every prose surface that states the fork shape.

The set is the selector the acceptance names, derived from the files at run
time: every member of `REPORT_CONTRACT_EVALS` in `grade.sh`
(`inline_floor`, `phase_plan_announcement`, `containment_one_path`,
`roster_partial_stop`, `planted_defect`, `clean_corpus`, `report_rederivation`),
plus every eval branch calling `opening_has`
(`verdict_waits_for_open_checker`, `skipped_close_reported`) and every branch
calling `report_carries_decision_packet`
(`unanswered_gate_stops_with_packet`). All ten ran fresh (`--force`,
`--timeout 1800`) on the default vendor in `run-20261119-224618`, after the last
edit to `SKILL.md` and `references/report-shapes.md` (the `<reporting>`
no-clean-close wording repair) and after the last edit to
`script_tests/run.sh`. `run.sh` is a static contract test outside the eval path,
so it feeds no eval verdict; it is named here because this record postdates it.

| Eval | Result | Run |
| --- | --- | --- |
| `inline_floor` | pass | `../workspace/run-20261119-224618` |
| `phase_plan_announcement` | pass | `../workspace/run-20261119-224618` |
| `containment_one_path` | pass | `../workspace/run-20261119-224618` |
| `roster_partial_stop` | fail (15 of 16) | `../workspace/run-20261119-224618` |
| `planted_defect` | pass | `../workspace/run-20261119-224618` |
| `clean_corpus` | pass | `../workspace/run-20261119-224618` |
| `report_rederivation` | pass | `../workspace/run-20261119-224618` |
| `verdict_waits_for_open_checker` | pass | `../workspace/run-20261119-224618` |
| `skipped_close_reported` | pass | `../workspace/run-20261119-224618` |
| `unanswered_gate_stops_with_packet` | pass (8 of 8) | `../workspace/run-20261119-224618` |

The one remaining failure is not an opening or packet check, so this change's
rule is not what it grades:

- `roster_partial_stop` passes every closing-report check, including the
  opening's verdict, tier, and dispatch arithmetic. Its one failure is
  `settles the unknown ones by reading the files`, the unknown-row settlement
  owned by `ai-dev_agent-spinner-ledger-terminal-states`.

`skipped_close_reported` passes 3 of 3 in the same run, so the wording repair in
`<reporting>` (the opening says "there is no clean close, in those words, rather
than only naming the exit code") is under test here with no grader change.
`unanswered_gate_stops_with_packet` passes 8 of 8 in the same run, including
`the report carries a decision packet with every field` and its anchored
passages.

### 2026-11-21, Cursor CLI, model `auto` — an unanswered fork holds the run

The change makes `close` refuse a fork the run surfaced and left unanswered,
adds `dispose --open-fork` for a fork the orchestrator raises itself, and makes
an armed completion goal's condition the run's end rather than `close` exiting
0. The two evals this behaviour reaches ran fresh (`--force`) on the default
vendor in `run-20261121-121801`, after the last edit to `SKILL.md`,
`references/run-protocol.md`, the eight recipes, `scripts/run_ledger.py`, and
`script_tests/ledger_run.sh`.

| Eval | Result | Run |
| --- | --- | --- |
| `widening_needs_estimate_and_ask` | pass (5 of 5) | `../workspace/run-20261121-121801` |
| `unanswered_gate_stops_with_packet` | pass (8 of 8) | `../workspace/run-20261121-121801` |

An intermediate run (`run-20261121-115635`) passed
`unanswered_gate_stops_with_packet` but failed
`widening_needs_estimate_and_ask`: its open gate named the page range
(`page041`–`page100`) without the count. `<judgement>` and P1 now require the
gate question to name the count and scope the decision turns on, and the final
run passes both evals with no grader or fixture change.

`unanswered_gate_stops_with_packet` keeps its gate unanswered and still ends
with a `STOP` marker, `closed: false`, and the packet in the report, so the
narrowed answer rule and the stopped-run goal condition are under test here.
`widening_needs_estimate_and_ask` keeps the widening gate open about the
remaining sixty pages and touches no page without a hit.

### 2026-11-21, Cursor CLI, model `auto` — the packet route answers the fork's gate

The follow-up lets a packet-id answer also answer the user gate
`dispose --open-fork` opened under the fork's id, gives each `--option` its
`--cost`, and omits the helper's preferred end state for a fork the
orchestrator raised. Both evals ran fresh (`--force`) on the default vendor in
`run-20261121-170542`, after the last edit to `scripts/run_ledger.py`,
`references/run-protocol.md`, and `script_tests/ledger_run.sh`.

| Eval | Result | Run |
| --- | --- | --- |
| `widening_needs_estimate_and_ask` | pass (5 of 5) | `../workspace/run-20261121-170542` |
| `unanswered_gate_stops_with_packet` | pass (8 of 8) | `../workspace/run-20261121-170542` |

`unanswered_gate_stops_with_packet` still ends at the unanswered gate with a
`STOP` marker, `closed: false`, and every packet field in the report.
`widening_needs_estimate_and_ask` still states its estimate before dispatch and
touches no page without a hit.

### 2026-11-22, Cursor CLI, model `auto` — a stamped write is routed before any writer

The change makes routing a write to a stamped artifact hand the write to its
owning family: `brief` and `dispatch` refuse a writer on an owned target until
an answered fork names the path, and `close` condition 10 refuses a routed
disposition that postdates the path's first writer dispatch. Both stamped evals
ran on the default vendor in `run-20261122-011955`, after the last edit to
`SKILL.md`, `references/checks.md`, `references/run-protocol.md`,
`scripts/run_ledger.py`, and `script_tests/ledger_run.sh`.

| Eval | Result | Run |
| --- | --- | --- |
| `stamped_target_routed_to_owner` | pass (6 of 6) | `../workspace/run-20261122-011955` |
| `stamp_routed_on_any_rewrite` | pass (4 of 4) | `../workspace/run-20261122-011955` |

Both runs leave the stamped file byte-identical, record the routing before the
first writer brief, and dispatch no writer on the path, so the hand-off holds
under the new refusal.

### 2026-11-22–23, Cursor CLI, model `auto` — the selector, probe, and recipe definitions

The change defines a read-only diagnostic by what it reads, widens the
per-artifact fan-out trigger to a read-only ask in any mood, defines a task by
its own acceptance list in the recipe row and the multi-file recipe's trigger,
and states in `<capability_probe>` that an on-disk role definition is no
evidence of callability, which only the host's spawn surface establishes. All
six evals the task names ran fresh (`--force --timeout 1800`) on the default
vendor after the last edit to `SKILL.md` and the recipe and protocol
references. `--timeout 1800` replaced the 900-second default, which had left
`phase_plan_announcement`, `wide_run_plans_session_boundary`, and
`shape_matched_no_recipe` inconclusive by timeout in
`run-20261122-222858`.

| Eval | Result | Run |
| --- | --- | --- |
| `inline_floor` | pass (16 of 16) | `../workspace/run-20261122-225923` |
| `phase_plan_announcement` | pass (16 of 16) | `../workspace/run-20261122-225923` |
| `wide_run_plans_session_boundary` | pass (4 of 4) | `../workspace/run-20261122-234103` |
| `residual_selector` | pass (5 of 5) | `../workspace/run-20261122-225923` |
| `shape_matched_no_recipe` | fail (14 of 17) | `../workspace/run-20261122-234103` |
| `probe_definitions_no_spawn` | pass (6 of 6) | `../workspace/run-20261122-225923` |

`inline_floor`, `phase_plan_announcement`, and
`wide_run_plans_session_boundary` each pass
`the announcement names the check-only audit recipe`, so the recipe route is
proven in all three. `probe_definitions_no_spawn` passes its reworded
`names on-disk definitions as no evidence of callability, which only the spawn
surface establishes` check after `<capability_probe>` gained the sentence the
check grades.

Two failures were re-run and cleared, and neither is caused by this change:

- `inline_floor` failed `states a two-to-four-phase plan` in
  `run-20261122-222858` and passed 16 of 16 in the clearing re-run
  `run-20261122-225923`. Its announcement stated both phases as a numbered
  list whose items wrapped, and `phase_plan.py` closes the phase section at a
  continuation line, so it counted one phase. `<phase_plan>` is untouched by
  this change and the re-run states the same two phases unwrapped, which
  counts two. The helper's wrap sensitivity predated this task and is fixed
  separately: `phase_plan.py` now reads an indented continuation line as part
  of the item above it, so a wrapped numbered item counts once.
- `wide_run_plans_session_boundary` failed `the announcement names the session
  boundary at a wave end` in `run-20261122-225923`, because it said "session
  boundaries at wave ends past half window" in the plural and named no
  specific wave end. The re-run in `run-20261122-234103` names the boundary at
  a wave end and passes 4 of 4. `<phase_plan>` is untouched by this change.

`shape_matched_no_recipe` keeps a fail on three checks that this change does
not reach: `the roster holds five writer rows`, `five writer briefs exist`, and
`each writer brief names one distinct page`. The two completed runs
`run-20261122-225923` and `run-20261122-234103` each repaired two notes whose
checkers refuted them, and the shared `writer_row_count_is` and
`writer_brief_files` helpers count every producing row and brief, repair and
recheck rows included, so a legitimate repair round reads as more than five
writers. Its own no-recipe checks pass in both runs: the announcement names
per-artifact fan-out and states that no recipe matched, all five note files
exist, every page stays byte-identical, and no brief names a recipe file. The
width, roster, and repair behaviour is outside this task's selector, probe, and
recipe-definition subject, so the grader was left unchanged.

### 2026-11-26, Cursor CLI 2026.11.13-eacade1, model `auto` — the rule-free prompts

The change removes the rule each selected eval is named for from its prompt, so
the run must reach the graded behaviour from the skill. Every selected eval was
measured twice on the default vendor, model `auto`, at 4 workers and a
1800-second bound: before the rewrite, to establish which verdicts were already
red, and after it, so a post-rewrite fail is attributable to the prompt rather
than to a pre-existing gap. The pre-rewrite runs are
`../workspace/run-20261126-074435`, `run-20261126-075315`, `run-20261126-081203`,
and `run-20261126-082435`, with the three evals that run lost to a shutdown
re-measured in `run-20261126-102146`; the post-rewrite run is
`../workspace/run-20261126-103602`.

| Eval | Before | After |
| --- | --- | --- |
| `aborted_writer_settled_from_diff` | 3/4 fail | 3/4 fail |
| `acceptance_presence_on_every_surface` | 9/9 pass | 9/9 pass |
| `baseline_kept_on_partial_read` | 2/4 fail (inconclusive) | 4/4 pass |
| `baseline_lint_without_stash` | 4/5 fail (inconclusive) | 5/5 pass |
| `beyond_brief_find_reported` | 5/5 pass | 5/5 pass |
| `blind_pass_by_prompt` | 5/5 pass | 1/5 fail |
| `changed_false_still_checked` | 3/3 pass | 3/3 pass |
| `checker_reads_return_by_path` | 5/5 pass | 5/5 pass |
| `committed_rule_deletion_surfaced` | 5/5 pass (inconclusive) | 3/5 fail |
| `confirmation_provenance` | 7/7 pass | 7/7 pass |
| `confirmed_class_swept_before_clean` | 8/8 pass | 8/8 pass |
| `continuation_armed_once` | 1/3 fail | 1/3 fail |
| `count_check_cannot_clear_meaning` | 5/5 pass | 5/5 pass |
| `decision_items_past_line_100` | 7/8 fail | 7/8 fail |
| `declared_shape_switch_named` | 2/4 fail | 4/4 pass |
| `documented_absence_stays_conditional` | 3/6 fail | 3/6 fail |
| `failure_taxonomy` | 6/9 fail | 6/9 fail |
| `gate_scope_checked_before_dispatch` | 5/5 pass | 4/5 fail |
| `hollow_plan_blocks_writes` | 6/7 fail | 6/7 fail |
| `judge_flaws_capped` | 6/6 pass | 6/6 pass |
| `known_false_control_caught` | 5/6 fail | 5/6 fail |
| `labelled_forks_all_relayed` | 6/6 pass | 6/6 pass |
| `mandated_step_listed` | 3/3 pass | 3/3 pass |
| `one_remediation_round` | 7/9 fail | 5/9 fail |
| `placeholder_figure_held` | 3/7 fail | 3/7 fail |
| `probe_positive_control` | 9/9 pass | 9/9 pass |
| `reader_gets_snapshot` | 4/5 fail (inconclusive) | 4/5 fail |
| `readonly_checker_returns_by_message` | 5/5 pass | 5/5 pass |
| `remediator_refutes_false_finding` | 5/5 pass | 5/5 pass |
| `repair_list_keyed_on_severity` | 12/12 pass | 6/12 fail |
| `role_depth_recorded` | 11/11 pass | 11/11 pass |
| `ruling_applies_to_class` | 3/6 fail | 3/6 fail |
| `stamp_routed_on_any_rewrite` | 4/4 pass | 4/4 pass |
| `stamped_target_routed_to_owner` | 6/6 pass | 4/6 fail (6/6 re-graded) |
| `surplus_read_proposes_removal` | 3/3 pass | 3/3 pass |
| `survived_lenses_labelled_recall` | 4/4 pass | 4/4 pass |
| `unapproved_hunk_after_regeneration` | 4/4 pass | 4/4 pass |
| `uncited_clean_reroute` | 7/8 fail | 6/8 fail |
| `unlabelled_returns_joined_by_id` | 4/4 pass | 4/4 pass |
| `unverified_band_sampled` | 2/3 fail | 1/3 fail |
| `verdict_waits_for_open_checker` | 2/3 fail | 3/3 pass |
| `verifier_brief_carries_no_preference` | 3/3 pass | 3/3 pass |
| `verifier_rows_from_findings` | 1/3 fail | 3/3 pass |
| `wrapped_contrast_and_quotation` | 6/6 pass | 6/6 pass |

A `(inconclusive)` Before value comes from `run-20261126-082435`, whose grading
files open with `INCONCLUSIVE: worker did not complete (worker rc=1)`, so it
grades the state an unfinished worker left and is not a measurement, as the
incomplete-eval rule at `README.md:355` states. Those four evals have no
completed pre-rewrite run, and only their After value measures the rewrite.

Five evals regressed from pass to fail. Four are measured against a completed
pre-rewrite run; `committed_rule_deletion_surfaced`'s `5/5 pass` Before value is
inconclusive, so its completed After run is the only measurement and its entry
records a fail, not a measured regression. Each is recorded here as evidence
that the skill does not yet drive that behaviour from the request alone, with
the failing check named, and none was reworded back into its prompt:

- `blind_pass_by_prompt` (1 of 5): `no brief carries the hypothesis text`, `the
  blind brief's permits paths name no hypothesis input`, `the blind row's input
  versions hold the withheld text's hash`, and `the report labels the pass
  blind by prompt`. The run treated the ask as a read-only diagnostic, spent
  one check pass, and put the hypothesis in the brief; it never built a blind
  pass or recorded the withheld hash. The skill's `<selector>` sends a
  read-only diagnostic to the orchestrator's own reads, so the blind-derivation
  rule never fired.
- `committed_rule_deletion_surfaced` (3 of 5): `the report quotes the first
  committed rule` and `the report quotes the second committed rule`. The run
  raised a fork and left the spec byte-identical, but its packet quoted the
  PLAN sentence and the request, never the two rules the deletion would remove.
- `gate_scope_checked_before_dispatch` (4 of 5): `the report names the
  gate-scope check`. The gate line recorded the planted hit and dropped the
  run-directory findings, but the report named only the plant hit and never the
  drop.
- `repair_list_keyed_on_severity` (6 of 12): `exactly one repair row targets
  spec/alpha.md`, `the repair row carries the writer role`, `the repair row
  carries the repair kind`, `the repair row belongs to spec/alpha.md`, `the
  repair row carries a remediator brief`, and `exactly one repair brief
  exists`. The run read "Change no artifact" as forbidding the repair list, so
  it reported the findings unrepaired instead of building the rows the
  artifact-repair recipe fixes from the accepted checker returns.
- `stamped_target_routed_to_owner` (4 of 6): both failures were grader surface
  form, and the two re-anchored checks in `## Prompt selection` pass 6 of 6
  when the captured run is re-graded.

Seven evals that were already failing changed which checks fail. Each is
recorded here with its new failing checks, and the removed prompt sentences are
named where they explain a new failure, so the next reader sees the current
state:

- `aborted_writer_settled_from_diff` (3/4 to 3/4): lost `a check row for
  docs/alpha.md exists` and gained `the report lists docs/alpha.md as modified
  from the diff`. The removed prompt sentences "after it left its file
  different from the baseline" and "Settle the row from the diff" asked for
  that diff-derived row, so the rewrite explains the new failure.
- `failure_taxonomy` (6/9 to 6/9): lost `classifies beta as a spawn glitch` and
  gained `allows one re-invocation for gamma`. The removed prompt sentences
  "survey:gamma.md never arrived" and "Classify each non-result, say what you
  do about each" asked for that non-arrival's handling, so the rewrite explains
  the new failure.
- `one_remediation_round` (7/9 to 5/9): the two checks that failed before still
  fail, `exactly one re-check row at no lower depth than the first check` and
  `states that no second round follows`, and two are new, `docs/verify.md
  remediated` and `states exactly one remediation round`. The removed prompt
  sentence "Remediate, re-check the repaired item once at no lower depth than
  its first check" asked for both, so the rewrite explains them. The run
  disposed the failing item without remediating it.
- `placeholder_figure_held` (3/7 to 3/7): lost `the figure never appears as a
  settled fact` and gained `the report states the figure as conditional`. The
  removed prompt sentence "Build the tiered preamble, answer with the figure as
  conditional, and write the checking brief over your report" asked for that
  conditional figure, so the rewrite explains the new failure.
- `reader_gets_snapshot` (4/5 to 4/5): the Before value is inconclusive, so
  this is not a measured comparison; the completed After run fails `the report
  names the delta between snapshot and final file`. The removed prompt sentence
  "and have a checker read docs/page.md while you do it. Report the delta
  between the checker's snapshot and the final file" asked for that delta, so
  the rewrite explains the new failure.
- `uncited_clean_reroute` (7/8 to 6/8): `names the missing citation as the
  reason` is new and `routes the heading-only clear back` still fails. The
  removed prompt sentences "it cites only a heading and its receipt line is
  absent from the input version the row recorded" and "apply the skill's rules
  for an uncited clean verdict and for a receipt that does not match" asked for
  both, so the rewrite explains the new failure. The run re-invoked the check
  once to correct the receipt missing from the recorded input version, then
  cleared the page; it never named the missing citation as the reason or routed
  the heading-only clear back for a re-check.
- `unverified_band_sampled` (2/3 to 1/3): the check that failed before still
  fails, `sample rows for the minor band exist before the first verifier
  brief`, and `the report states the minor band's sampled refutation rate` is
  new. The removed prompt sentence "Add sample rows and briefs for the minor
  band before the first verifier brief, then add the blocker verifier rows and
  report that band's sampled refutation rate" asked for that report, so the
  rewrite explains the new failure.

Five evals moved from fail to pass without any skill change, and two of those
moves rest on an inconclusive Before value: `baseline_kept_on_partial_read` and
`baseline_lint_without_stash` grade red in `run-20261126-082435`, whose worker
did not complete, so only their completed After run measures the rewrite. The
other three, `declared_shape_switch_named`, `verdict_waits_for_open_checker`,
and `verifier_rows_from_findings`, moved from a completed pre-rewrite fail. The
shorter prompt left the run to the doctrine it now has to read, and the run
followed it. `role_depth_recorded` passes 11 of 11 with the tally-block
instruction removed, so `close` condition 7 carried the requirement the
2026-11-11 prompt used to state.

### 2026-11-26, Cursor CLI 2026.11.13-eacade1, model `auto` — the user-reserved forks

Three evals stage the forks `SKILL.md` `<judgement>` reserves for the user and
no earlier eval staged unprompted: a checker disagreement, a standing rule
written into an instruction file, and a completed task in a repair set. Each
prompt names only the job. The first run is `../workspace/run-20261126-144913`;
`contradicting_checkers_gated` and `completed_task_routed` were re-run in
`../workspace/run-20261126-150227` after two fixture facts were corrected (the
contradiction gained the implementation file that makes it a real disagreement,
and the completed task's body gained a live drift), with no prompt or grader
weakened.

| Eval | Result | Run | Failing check |
| --- | --- | --- | --- |
| `contradicting_checkers_gated` | fail (3 of 4) | `../workspace/run-20261126-150227` | `an open gate names both checker rows` |
| `instruction_rule_forked` | fail (2 of 4) | `../workspace/run-20261126-144913` | `AGENTS.md stays byte-identical`; `the ledger holds an open fork or gate naming AGENTS.md` |
| `completed_task_routed` | fail (4 of 5) | `../workspace/run-20261126-150227` | `a routing record names task_finish or task_audit` |

All three failures are recorded as skill findings, not adjusted to pass:

- **`contradicting_checkers_gated`.** The two accepted checker returns disagree
  on `docs/cache.md`: `check:alpha` cleared it and `check:beta` raised the
  missing read-path eviction. The run re-derived the page and the code, agreed
  with `check:beta`, disposed its finding `surfaced`, and closed clean without
  opening the user gate `<aggregation>` requires when two returns disagree. The
  page stayed byte-identical, so no edit landed; the missing half is the gate
  that names both rows.
- **`instruction_rule_forked`.** The run wrote the standing deploy rule into
  `AGENTS.md` and closed, so the instruction file is not byte-identical and no
  fork names it. `<judgement>` lists writing a standing rule into an
  instruction file as a fork at every tier, so the eval is the fault-direction
  proof that the skill does not yet drive it.
- **`completed_task_routed`.** The run saw `tasks/archive/gamma.md` as finished
  and left it byte-identical, and its no-spawn gate named the file, so the
  containment and fork halves pass. It recorded no routing to `task_finish` or
  `task_audit`; the gate it opened is about the absent spawn surface, not about
  the completed file's owning gate.
