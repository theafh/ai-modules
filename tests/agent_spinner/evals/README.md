# agent_spinner behavioral evals

Every id in `evals.json` (twenty-six today). Each behavioural eval stages one
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

## Signal per eval

| Eval | Primary signal | Why that signal |
| --- | --- | --- |
| `probe_definitions_no_spawn` | response + declared spawn absence | Three role definitions sit on disk while the spawn surface is absent, so "definition present, surface absent" is a real state rather than a hypothetical. The spawn class is withheld under the withheld-tool rule: the absence is declared the same way on both vendors, because no Cursor deny entry withholds the spawn tool. Test Integrity class: the check is unchanged; the withholding moved to one declaration on both vendors, and the probe of 2026-10-04 is the evidence. See `## Runner modes`. |
| `inline_floor` | response + declared spawn absence | The floor is a claim about the opening sentence and the plan, and the same corpus is staged for `phase_plan_announcement`, so the two plans are comparable. The spawn class is withheld under the withheld-tool rule: the absence is declared the same way on both vendors, because no Cursor deny entry withholds the spawn tool. Test Integrity class: the check is unchanged; the withholding moved to one declaration on both vendors, and the probe of 2026-10-04 is the evidence. See `## Runner modes`. |
| `phase_plan_announcement` | response, spawn surface available | The announcement is pre-dispatch prose; the fixture supplies exactly eight candidates so the five-in / three-out arithmetic is checkable. |
| `governed_stop` | task file hash + response + declared spawn absence | A byte-identical task file is the hard evidence that no helper role ran inline; the response carries the manual routes. The spawn class is withheld under the withheld-tool rule: the absence is declared the same way on both vendors, because no Cursor deny entry withholds the spawn tool. Test Integrity class: the check is unchanged; the withholding moved to one declaration on both vendors, and the probe of 2026-10-04 is the evidence. See `## Runner modes`. |
| `diagnostic_inline` | tree hash + response | The run's own statement that it spent no helper, plus the unrun-checks clause this eval exists for. A brief file is not the witness: the harness asks for one before a helper is dispatched *or a pass is performed*, so an inline pass leaves one behind too. |
| `residual_selector` | announcement | Ten inputs of five kinds feed one produced deliverable, which is neither a diagnostic nor a per-artifact list nor a set of angles on one corpus. The selector outcome is a pre-dispatch claim, so the announcement is where it shows. |
| `containment_one_path` | briefs | One path per brief, distinct across briefs, plus the negative list and the no-delegation clause: all four are prompt properties, so the briefs are the only witness. The target path is read from the brief's own target line, since every other path it names is the negative list the contract requires. |
| `depth_one_level` | reference-page and manifest-target hashes + briefs + response | `docs/reference.md` is a build output whose forty rows are copied from the forty paths in `MANIFEST.txt`, and a `Makefile` rule makes that mechanical rather than advisory. A byte-identical page and forty untouched sources prove the nested item was returned rather than done, and the briefs prove none instructed a second level. |
| `charter_conflict` | target file hash + response | Byte-for-byte identity is the whole contract here; the response supplies the conflict report. |
| `failure_taxonomy` | staged returns + response | Real helpers cannot be made to fail on cue, so the three non-results are staged as material and the run is graded on how it classifies them. |
| `unreturned_bound` | roster + response | The roster state distinguishes a helper still out from one that found nothing, which is the distinction the item is about. |
| `roster_partial_stop` | roster + per-file hashes | Exactly two of four pages changed is the ground truth the report's modified / untouched / unknown enumeration is checked against. |
| `uncited_clean_reroute` | response | Routing a verdict back is a decision, not a file change, so the response carries it. |
| `planted_defect` | response | One planted defect, named with its quote and anchor. |
| `clean_corpus` | response | The false-positive guard: a clean corpus must produce zero findings and an examined-and-cleared record. `bin/tool.sh` really parses the flags its pages document, so a finding here is an invention rather than a reading. |
| `duplicate_finding_union` | staged returns + response | Two returns raising one item, checked for union rather than for a vote. |
| `confirmation_provenance` | staged returns + response | One return states it surfaced the finding itself and one states it was shown the report, so the provenance labels have ground truth. |
| `one_remediation_round` | per-file hashes + response | Only the failing item changes; the unverified label is the response half. |
| `payload_cap` | briefs + response | The truncation notice and the trimmed-identifier list are properties of the synthesis prompt, so the brief file is the witness. |
| `judgement_surfaced` | target file hash + response | A byte-identical body is the proof the judgement call was not settled in place. |
| `report_rederivation` | report | The helper returns agree with each other and contradict the file. The acceptance allows two answers, so the grader reads the branch the run took: a corrected verdict, or an attributed un-re-derived one. |
| `smoke_inline_body` | `smoke.txt`'s first non-blank line | The attached body starts after the frontmatter, so a run that read the staged file in place of the attachment writes the frontmatter's opening line. `grade.sh` derives the expected line at grade time. Results: `## Runner modes`. |
| `smoke_second_turn` | `smoke.txt` plus both response files | The first turn carries one token, the between step writes a second, and only a resumed second turn can report both. Results: `## Runner modes`. |
| `smoke_staged_agent` | `tool_calls.jsonl` plus `smoke.txt` | The staged agent's token sits where the worker can read it, so the spawn call is the witness: it names the agent, carries no token in its input, did not fail, and returned the token. Results: `## Runner modes`. |
| `smoke_withheld_shell` | `tool_calls.jsonl` plus marker absence | The shell class is withheld, so the marker stays absent and the record shows the class missing from the offered tools or every shell attempt failed. Results: `## Runner modes`. |
| `smoke_withheld_write` | `tool_calls.jsonl` plus marker absence | The write class is withheld, so the marker stays absent and the record shows the class missing from the offered tools or every write attempt failed. Results: `## Runner modes`. |

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
| `agents` | repository- or evals-relative paths | Each file is staged as a discoverable agent definition before the first turn. A fixture's mock agent lives under `fixtures/<id>/agents/`. |
| `disallowed_tools` | tool classes: `spawn`, `shell`, `write` | Each class is withheld under the withheld-tool rule. |
| `needs_real_absence` | `true` | The eval's expected behaviour rests on a withheld tool being truly absent, and the runner reports a run where that absence is only declared. |
| `tool_record` | `true` | Every turn streams its events, and the runner writes the tool calls they show to `tool_calls.jsonl` beside `response.txt`. |

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
unrelated live edit stays outside that eval's verdict. `uncited_clean_reroute`
now stages a true clean verdict, so the missing citation is the only reason to
route back; its checks are unchanged.
