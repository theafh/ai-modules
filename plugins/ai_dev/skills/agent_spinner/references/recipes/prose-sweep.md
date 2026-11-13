# J2. Meaning-preserving prose sweep

<prose_sweep>

<trigger>
It runs under per-artifact fan-out and applies only after the selector matched that shape.

The ask applies one style or wording rule in place across a document tree, keeping meaning, requirement strength, and length. Requirement strength is the force of words such as must and should. Typical rules remove dashes, lighten jargon, rewrite contrastive negation, or split long sentences. These signals mark the ask: a style file, many prose files, lines a linter or parser reads, graders that match corpus literals, and hard-wrapped prose. Corpus literals are exact strings from the files that a test grader looks for.
</trigger>

<ledger_steps>
Open the run with `init` over the in-scope list, with each exclusion and its reason, the named gates, each linter in its check mode, one `triage:missed-scan` unit registered only when the request asks for the triage pass, read at `init` through `--request` before the plan exists and whose row runs that pass, and one `residual:sweep` unit, always registered, whose row runs the residual sweep. The two units carry distinct item names, `missed-scan` and `sweep`, because `init` refuses two units whose items share one case-folded slug, and every later mention of the triage unit uses its label `triage:missed-scan`. A sweep whose request does not ask for the triage pass therefore opens no triage row and still reaches a clean `close`.

Register each counter as a `NAME=CONTROL_MARKER` entry through `init --counter`, its pattern the ledger's fixed control string alone, so `diff --count` validates the ledger's own control and passes. Take the target-class pattern from a file and count it per file in Python, with no shell-quoted alternation, and take as its known positive the target instance the **Scout** step plants, counted with the target-class pattern in Python and recorded before any target-class zero count (C4).

Run the linter and the build through `gate --on-baseline`, each with the expectation its baseline run meets (C4). An expectation names the result a gate run should show. That expectation is `exit0` where the baseline run exits 0, and `nonempty` where it already reports findings, so the gate line reports the difference. Each gate that counts runs with `--expect count`.

Each wave runs `diff --count`, then `diff --add-checks`, then the checker wave. Every changed path the sample leaves out keeps the `check:<slug>` row that `--add-checks` made, and the run closes that row with `accept check:<slug> --stdin --classify 'sampled out; per-file gates cover it'`, so the sample stands as a recorded narrowing rather than an open row.

`rows --phase repair --role writer --from-records '<checker row>:findings:*'` creates one repair row per accepted checker finding record. Then the run issues one `rows --phase repair --role writer --from-records '<residual row>:findings:<n>'` call per residual finding record, and it skips every record whose path already holds a repair row, because `--from-records` matches records by id alone and takes no path filter. A path that carries both a checker finding and a residual finding therefore keeps the repair row the checker call made, and its per-record residual call is the one the run skips. Each repair brief passes `--kind repair --target <path>`, so a path is repaired once.
</ledger_steps>

<phases>
1. **Rewrite**: a writer rewrites each roster file, wave by wave. It reads no earlier helper return, and once the first wave has set them it also reads the ruling table and the calibration pairs, which the **Calibration** step sets.
2. **Check**: a checker reads each changed file's diff against the baseline, with its Rewrite return verbatim.
</phases>

<width>
Writers take one file each, W per wave, where W is the wave size the plan sets. Give every changed file one checker by default. A rule that rewrites a sentence to remove a mark bears on meaning, like any rewording. A sampled checker set is possible only while every hunk the rule makes is a glyph-for-glyph substitution, as each wave's diff shows, and the run re-checks that condition on every wave's diff rather than once at calibration. Such a substitution swaps one character for another and leaves the rest of the text as it was. A wave whose diff breaks the condition gives every changed file in that wave a checker, and the run puts that widening to the user, since it restores the checks the sample dropped. The sample then covers a fixed share of the files, every file whose fidelity gates moved, and every file with a flagged call, and the gates still cover every file (C1). Every changed file the sample leaves out closes its `check:<slug>` row with the classification the ledger steps give, so the sample stands as a recorded narrowing rather than an open row. The fidelity gates are the per-file counts under **Gates beside the steps**, and a flagged call is a borderline call the writer flagged. Where a gate this recipe relies on is unavailable, give every changed file its checker, or ask the user (C4). Spend checkers where meaning can move, no shallower than their writers (C7). Choose a checker role whose contract is review, and require a cited span per checklist line. When the user tightens the rule within the session, keep the pre-session baseline fixed. In that case, also prefer one composite pass per file that carries every rule still in force, and send files touched twice to the checker first.

A cheaper triage pass may take the rows the scan did not hit, where the request asks for it. Its widening still goes to the user. The scan is the scout's count of targets per file, and the rows it did not hit are the files where it found no target. The triage helper runs at a lighter model or effort. Its brief names each in-scope file the scan did not hit, one section per file, and the helper returns one finding per file where it found a missed target, carrying that file's `path` and a claim that lists every target the scan missed there with its quote and anchor. Once the user approves the widening, `rows --phase rewrite --role writer --from-records 'triage:missed-scan:findings:*'` creates one Rewrite-phase row per such file with role writer, so each file with a missed target gets a writer. That call creates the row even where the in-scope list already holds a row for the file, and the run dispatches the new row as that file's writer and closes the earlier row with `accept <label> --stdin --classify 'superseded by the triage row'`. Record the approval as an answered user gate through `dispose --open-gate` and `dispose --gate`, and quote the request's answer in the announcement, so the widening stands as a recorded decision.

A run whose context estimate crosses half the host's window spans sessions at wave ends (P1).
</width>

<roles_and_returns>
Writers write their return files.

The writer brief carries the rules file, the preserve list, the ruling table, and the calibration pairs verbatim. The preserve list names text the writer leaves exactly as it stands. The brief also carries its kind note, one path, a negative list, and its own scratch directory under the run directory. The kind note says how this class of text may change, and the negative list names the files the writer leaves untouched: the other roster paths and the log, schema, and generated files.

The writer returns its label and path and the diffstat measured by the named command. It adds counts in the template's unit with the method used, two to four before-and-after pairs, borderline calls tagged by ruling class, beyond-brief defects with path, line, and quote, incidents it broke and repaired, and doubts.

Each edit spans the whole sentence across line breaks, and then the writer reflows the paragraph and re-reads it. Replacement tables keyed on single lines serve pointer-class text only, meaning paths, identifiers, link targets, and slugs (`references/edit-mechanics.md`).

The checker returns a verdict per hunk (kept, narrowed, lost, inverted, or garbled) with the old and new text, and it records each file with a non-kept hunk as one finding whose claim lists those hunks. It also returns a `checklist` entry per checklist line, each with verdict `pass` or `fail` and its citing span, and the number of hunks it examined.

Each return carries every key `accept` validates: `label`, `brief`, `status`, `verdict`, `examined`, `checklist`, `findings`, `forks`, `objections`, `beyond_brief`, `incidents`, `own_authority`, `alternatives`, `brief_corrections`, `dropped_suspicions`, and `notes`. Each finding carries `claim`, `severity`, `quote`, `anchor`, and `path`, with `path` naming the file the finding concerns and its severity drawn from the run's severity ladder, which `init --severity` sets when the recipe's classes differ from the default `blocker`/`major`/`minor`.

A role barred from file writes returns in its final message, which you relay verbatim to `accept --stdin`, never through a shell (P3).
</roles_and_returns>

<adversarial_checks>
The checker opens from the position that the rewrite lost or changed meaning, and it names the cost: a missed loss leaves a wrong page that others will cite. It reads the rules file byte for byte, the writer's return verbatim, and the diff against the baseline. Its closed checklist has lines for forbidden marks under the writers' exclusions; modal and requirement strength; numbers, literals, and attributions; and each removed clause's claim still made somewhere. Further lines cover orphaned continuation lines and lost antecedents, such as a pronoun whose noun was cut; headings that still name their sections; lengthening and markup; and one line per call the writer flagged. A pass cites a hunk per line, and a pass with no hunk count goes back for re-checking. Afterwards, prove that the check phase changed nothing (P5).
</adversarial_checks>

<orchestrator_gates>
These orchestrator steps run in this order, and the announcement lists them as checks. Its first step runs the gate-scope check from run-protocol.md's run-directory section before dispatch. A report step builds the report from the ledger after a clean `close` (P6).

1. **Scout**, before the first wave: list the candidate universe, every file the rule could reach, with the in-scope list and each exclusion's reason. Confirm that in-scope plus excluded equals the universe. Register the target counter as `CONTROL_MARKER` through `init --counter` and fire it first on a known positive through `diff --count`, which validates the ledger's own control. Then take the target-class pattern from a file, plant a known target instance in a scratch file under the run directory and outside the in-scope list, so neither the residual sweep nor the universe count ever sees it, count that instance with the target-class pattern in Python, and record the hit before counting targets per file, so no target-class zero counts until its known positive is found (C4). That recorded hit is the known positive the per-file target counts and the residual sweep rely on. Read every machine-parsed file with the tool that parses it, and write a kind note for each load-bearing line, one that a parser, linter, or grader reads. The preserve list takes those notes, inline code, and text an agent must emit verbatim. List the link sites that point at headings the sweep may change, run the gate-scope check, and record the baseline (P1).
2. **Calibration**, on the first wave: the first wave pilots three to five structurally different files. Cluster every hard construct into named classes, with one ruling per class in a ruling table. For a rule that needs judgement on each instance, show the user eight to ten before-and-after pairs, the cut-and-keep ratio, and the bar. For such a rule, send later waves only after the user confirms. Put these to the user, each with its share of the estimate and a cheaper alternative: strictness, scope categories, depth, borderline classes, and every widening past the files the scan hit. Put a sampled checker set, where Width allows one, to the user here, with the checks it drops and its share of the estimate. Use it only on the user's word. A triage widening the request already answers is recorded as an answered user gate, with the request's answer quoted in the announcement.
3. **Per-wave gates**: run the per-file gates on every file the wave changed (C4). A wave whose diff breaks the glyph-for-glyph condition gives every changed file in that wave a checker, and the run puts that widening to the user, since it restores the checks a sample dropped.
4. **Residual sweep**, after the last wave: count the target class over every in-scope file, edited or not, with the writers' exclusions, then dispatch the `residual:sweep` row. A residual is a target still present after the rewrite. That row's accepted return carries one finding per file that still holds a residual, its `path` naming that file and its claim listing every residual in it, and the run classes each residual as kept, citing its rule or class, or as missed, and greps each ruling class for uniformity (C8).
5. **Repair round**: missed residuals and every hunk the checker judged other than kept go to one writer per file. A repaired in-scope file the rewrite never changed enters the changed set here with no `check:<slug>` row, so after the repair writers return the run runs `diff --add-checks` and dispatches a checker for every row that call adds, accepting each return before the closing differentials. Every changed path then holds an accepted `check:<slug>` row when the closing audit runs.
6. **Closing differentials**: run the whole-tree lint and build differentials, the net-diff audit as `diff --add-checks`, and the tree guard (C4, P5). `--add-checks` re-attaches each changed path's `check:<slug>` row to the change list `diff` rewrites, so the closing audit leaves the check mapping `close` reads intact. A differential compares a gate's final run with its baseline run.
7. **Report**: the report step that the shared lines describe.

Gates beside the steps. Per file, the gates count modal and requirement words, hedges, numbers, link targets, quoted strings, contrast markers, and character growth, baseline against working copy. Each count is judged against the direction the rule explains. The wrap-seam detector finds sentences an edit split or joined at a line wrap. The linter runs per file and over the whole tree, and the build runs too, each with its expectation (C4). Every link is checked against each heading anchor the sweep changed. Totals come from the diff, with the self-reported sum shown beside them.

The one repair round (C5) re-enters the write phase and the checking phase that reads the repaired diff, as `<phases>` names them, for the failing rows.
</orchestrator_gates>

<failure_handling>
A writer that was killed, aborted, or ran past its bound after it may have written leaves its path unknown. Settle that path from the diff and send it to the checker. After a resume, the check set is every path the diff shows changed. An incident that appears in a helper's narration but is missing from its return is a contract violation.

At a turn end with rows out, send the interim report. Any later turn runs `status`, then `attach` when a run is open, and accepts every pending return before it continues (P4).
</failure_handling>

<stop_and_ask>
Settle forks, the calibration bar, and every widening on the first wave, before any later wave goes out. Before dispatch, route every write to a stamped artifact to its owning family's gate or to the user, whatever the write changes (C9). A conflict between the user's exclusions and the repository's bookkeeping rules goes to the user.

Ask about scope and the estimate before dispatch, with the estimate beside any size guideline the host or user states, and ask before any widening past the enumerated list. An answer the request states is the user's answer. On a host with no later turn, an unanswered gate ends the run with its decision packet (P1). Create the stop file with `stop` the moment a pause request arrives, before any question (P4).
</stop_and_ask>

<report>
The report gives measured totals from the diff, with the residual count before and after the repair round. It lists each ruling class with its count, the borderline calls for review, and every beyond-brief defect. It tallies checker verdicts by hunk class and gives every gate delta with its expectation. It names every unavailable gate as a narrowing and states yield as cost per changed file. It names the sampled checker set as a narrowing with the checks it drops.

Report each repaired item as re-checked once, recall-limited, and unverified end to end, or as failed after repair (C5).
</report>

<cost_profile>
Keep these whatever else is cut: coverage by construction, a review of every landed write, and baseline-differential gates. Offer each cut only as a narrowing the user chooses, with the checks it drops. Estimate the cost as rows per phase, times the per-row cost the pilot measured, plus the checking share.

The cuts are a sampled checker set, where Width allows one, and the triage pass. Cutting the triage pass leaves the targets the scan missed unfound. The checking share buys meaning checks only through a review-capable checker that cites a span per checklist line.
</cost_profile>

<tier_notes>
Inline floor: each file's write, gates, and check run before the next brief. Batch delivery: one batch holds a wave's writers and the next holds its checkers, the gates close the wave, and a row that returns late is marked as over its bound (P4). Notice delivery: a file's checker goes out once its writer's return is accepted and its diff is non-empty. Where the notice carries no result, batch the checkers (P3), and poll the last Check wave inside the turn (P4).
</tier_notes>

<post_run_checks>
The rows created from the in-scope list cover every in-scope file, and in-scope plus excluded equals the universe. The changed set is a subset of the roster, every changed file has an accepted `check:<slug>` row, and every file the width rule names has a checker row. Every in-scope file has a residual entry, and every class grep is uniform. HEAD and the stash list match the baseline, and every total in the report comes from the diff.

Each repaired item has exactly one re-check row, at no lower depth than its first check.
</post_run_checks>

</prose_sweep>
