# J3. Multi-file task implementation

<multi_file_task>

<trigger>
It runs under per-artifact fan-out and applies only after the selector matched that shape.

The ask implements one task whose change spans many files, verified against the task's written acceptance list. The change is often a mechanical rename plus a semantic rewrite per surface, where a surface is one file or block the change reaches. The implementation skill keeps the task's lifecycle (stamp, audit, close-out), and this recipe governs the helpers inside that run.
</trigger>

<ledger_steps>
Copy the acceptance list verbatim into a file in the run directory, and name that file by path in every checker brief. Pass the semantic roster, built from the task's own selectors, to `init`. The semantic roster lists the files that need a semantic rewrite, and a selector is the glob or label the task uses to pick its files. Register the ladder the roles use with `--severity` at `init` whenever it differs from the default, and render that ladder into every brief's invariant preamble.

Run `snapshot` after the mechanical pass and again before the check phase, then run `diff --add-checks`, which creates one `check:<slug>` row for every changed path in the semantic and mechanical sets. Name each checker's snapshot copy and its per-file diff under `diffs/` in its brief. Record the full named gate suite at the baseline through `gate --on-baseline`, and run it again after Check against that record.

`rows --phase repair --role writer --from-records '<checker row>:findings:*'` creates the repair rows from the accepted checker finding records, one row per finding record. Each repair brief passes `--kind repair --target <path>`.

Hand the implemented stamp to the implementation skill's own step after `close` shows every checker row terminal, meaning in a final state such as accepted or failed.
</ledger_steps>

<phases>
1. **Weigh**: two or three lens designers compare the change with its alternatives over `snapshot --base`. This phase runs only when the task adds a public surface or rules out a competing mechanism. The designers read no earlier return. Each returns a verdict on the planned change and, per alternative, why it wins or loses, its cost, and its coverage regression, meaning the coverage it would lose.
2. **Write**: a writer rewrites each semantic roster row and reads no earlier helper return. Claim-class occurrences go to these writers: quotations, commands pinned to an older commit, historical narration, and every hard-wrapped sentence the change touches. Pointers are paths, identifiers, link targets, and slugs, and every other occurrence is claim-class and changes only through a writer.
3. **Check**: a checker reads each written file against the acceptance list, with the writer's return, the file's snapshot copy, and its per-file diff, while the orchestrator holds its own writes (C1, C2, P5).
</phases>

<width>
Write gets one writer per semantic row. Checkers cover every written semantic file plus a fixed sample of the mechanical set, the files the mechanical pass changed, and the gates cover the mechanical set in full. Every mechanical-set file outside that sample closes its `check:<slug>` row with `accept check:<slug> --stdin --classify 'sampled out; per-file gates cover it'`, so the sample stays a recorded narrowing and `close` finds no open row. The declared shape binds, so the run keeps the shape it announced. A switch of shape is a ledger event naming the checks it drops, and a switch that drops a check waits for the user.

A run whose context estimate crosses half the host's window spans sessions at wave ends (P1).
</width>

<roles_and_returns>
Writers write their return files.

The writer returns its label and path, the disposition applied, before-and-after pairs, each claim-class occurrence it kept verbatim with its reason, brief corrections, incidents, and doubts. A brief correction is a place where the writer found its brief wrong.

The checker runs at or above the writers' depth. It returns a `checklist` entry per acceptance line, each with verdict `pass` or `fail` and its citing span, where `met` maps to `pass` and `partly` and `unmet` each map to `fail` with a finding. It also returns unrequested changes, missing changes, narrowed wording, and anything beyond the checklist.

Each return carries every key `accept` validates: `label`, `brief`, `status`, `verdict`, `examined`, `checklist`, `findings`, `forks`, `beyond_brief`, `incidents`, `own_authority`, `alternatives`, `brief_corrections`, `dropped_suspicions`, and `notes`, with its doubts as `notes`. Each finding carries `claim`, `severity`, `quote`, and `anchor`, with its severity drawn from the run's severity ladder, which `init --severity` sets when the recipe's classes differ from the default `blocker`/`major`/`minor`.

A role barred from file writes returns in its final message, which you relay verbatim to `accept --stdin`, never through a shell (P3).
</roles_and_returns>

<adversarial_checks>
The checklist copies the acceptance contract, one line per item. Every rewrite item pairs "the old form is absent" with "the required new form is present on every surface the item governs" (C2). The checker reads the acceptance file by path, because a spawned helper receives only its prompt. Two standing lines come from the diff: unrequested changes and missing requested ones. The orchestrator's own writes, such as log appends and link repoints, get their own check rows (C1), and the verdict waits for a pass other than the orchestrator's. The Weigh designers work blind, without sight of the planned change, and the report labels them blind by prompt (C2).
</adversarial_checks>

<orchestrator_gates>
These orchestrator steps run in this order, and the announcement lists them as checks. Its first step runs the gate-scope check from run-protocol.md's run-directory section before dispatch. A report step builds the report from the ledger after a clean `close` (P6).

1. **Orient and baseline**, before Weigh: read the implementation skill and every skill that owns an artifact class the change touches, such as a knowledge base whose source records carry hashes. Run the dependency gate, which checks that the task's prerequisites have shipped. Honour the branch and charter rules, record the baseline, and run every named gate at the baseline with full output (P1, C4). Run the gate-scope check before dispatch.
2. **Mechanical pass by script**, before Write: apply moves and exact replacements to pointer-class occurrences only, meaning paths, identifiers, link targets, and slugs, verify by search, and record the result with `snapshot`.
3. **Named gate suite**, after Check: run the full suite against the baseline with warnings included, then these gates (C4). Move integrity lists every moved path with its rename status and similarity, as git reports them, and an add-plus-delete pair or a similarity below the plan's threshold is a finding. Git reports a similarity only for a rename it detects, so for a delete-plus-add pair the gate keeps the default pass's delete-and-add status and reports beside it the similarity index a second `git diff -M1% --summary` pass measures. The gate writes its table to `gates/move-integrity.txt` under the run directory, so the report and the log carry the same rows. Every quoted anchor and pinned command still resolves. After every append-only write, the line count grew by exactly the entry and the diff only adds lines. Wrap width holds on prose. Each capture hash on a source record goes to its owning family's gate by name, or to the user as a fork where no family owns the record. Every sample states its size, and no sample filter uses the producer's own replacement vocabulary.
4. **Repair round**, after the gates: the repair rows the ledger steps create run as one writer per finding record, and the run holds any repair the user has not approved.
5. **Verdict and hand-off**: issue the verdict only after every checker row has closed, then make the stamp hand-off that **Ledger steps.** names.
6. **Report**: the report step that the shared lines describe.

The one repair round (C5) re-enters the write phase and the checking phase that reads the repaired diff, as `<phases>` names them, for the failing rows.
</orchestrator_gates>

<failure_handling>
A checker still out keeps the verdict pending. End the turn only with the interim report. It names each open row with its bound deadline, and it marks that checker's rows producer-checked with refutation pending, meaning only the writer has checked them so far. After re-entry, merge, re-derive, and repair before issuing the verdict (P4).

At a turn end with rows out, send the interim report. Any later turn runs `status`, then `attach` when a run is open, and accepts every pending return before it continues (P4).
</failure_handling>

<stop_and_ask>
Ask before building when Weigh finds a cheaper or safer alternative, and show its cost. Surface any acceptance item that cannot pass as written, and keep its check as written until the user rules. Treat a rewrite of a verbatim record, such as a quotation or an archived file, as a fork, and hold a shape switch that drops a check for the user.

Ask about scope and the estimate before dispatch, with the estimate beside any size guideline the host or user states, and ask before any widening past the enumerated list. An answer the request states is the user's answer. On a host with no later turn, an unanswered gate ends the run with its decision packet (P1). Create the stop file with `stop` the moment a pause request arrives, before any question (P4).
</stop_and_ask>

<report>
The report carries an acceptance table in which each row cites its checker or gate row, with rows marked pending while checkers are out. It carries the move-integrity table and each linter's baseline, final, and delta counts. It closes with the three buckets and yield. The three buckets are what the run established, what a helper found beyond its brief, and what a helper decided on its own authority.

Report each repaired item as re-checked once, recall-limited, and unverified end to end, or as failed after repair (C5).
</report>

<cost_profile>
Keep these whatever else is cut: coverage by construction, a review of every landed write, and baseline-differential gates. Offer each cut only as a narrowing the user chooses, with the checks it drops. Estimate the cost as rows per phase, times the per-row cost the pilot measured, plus the checking share.

The cuts are the third Weigh lens and the checkers' sample of the mechanical set. Each cut drops one independent look.
</cost_profile>

<tier_notes>
Inline floor: write and check run back to back from their snapshot copies, and the report labels the check recall-limited. Batch delivery: writers go out in one batch and checkers in the next. Notice delivery: the verdict waits for every checker row, and the orchestrator holds its writes or collects them as a delta with its own check. Poll the final checker wave inside the turn with `accept --wait` (P4).
</tier_notes>

<post_run_checks>
Writers equal the semantic roster, and the stamp hand-off follows a clean `close`. Every acceptance row cites a row, the move table exists, and every linter has baseline, final, and delta lines. The tree guard shows no stash, reset, or bulk staging during the run, and the run wrote no ref or object into the repository.

Each repaired item has exactly one re-check row, at no lower depth than its first check.
</post_run_checks>

</multi_file_task>
