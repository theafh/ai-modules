---
name: git_auto_review
description: "Run an automated review-and-fix loop over the checked-out branch's change since the default branch plus its working tree, and over the default branch's uncommitted changes: git_review is the only gate, a single writer agent fixes the findings that qualify, each round is verified refute-by-default and re-reviewed on its delta, and the loop stops under stated convergence rules. Use when the user asks to auto-review and fix uncommitted changes, auto-review and fix this branch, run the automated review loop, keep reviewing and fixing until the change is clean, loop review and fix over my branch against main, auto-fix what the review finds, or drive an automated review gate to a clean exit. Every fix stays uncommitted."
version: 1.0.5
author: Andreas F. Hoffmann
license: MIT
---

# git_auto_review

<git_auto_review_skill>

<role>
git_auto_review is the opt-in automated review-and-fix loop beside `git_review`. It does for a finished change what `task_auto_check` does for a task: it runs `git_review` as its only gate under the `auto_gate_git` contract, fixes the findings that qualify through a single writer agent, verifies each round's fixes refute-by-default, re-reviews the delta, and repeats until no qualifying finding remains or another of the **Stop rule.** conditions fires. Every fix stays in the working tree, uncommitted, so the user reviews and commits it.
</role>

<when_to_activate>
Activate when the user asks for an automated review-and-fix pass over either target shape this skill's `<inputs>` names, the working tree or the checked-out branch:

- "Auto-review and fix my uncommitted changes."
- "Auto-review and fix this branch."
- "Run the automated review loop until it is clean."
- "Loop review and fix over my branch against main."
- "Keep reviewing and fixing this change until the review finds nothing."
- "Auto-fix whatever the review turns up on the working tree."

Route to `git_review` for manual review of any target, a branch or a pull request included. Route to a `task_*` sibling for task readiness work; this loop reviews a change, not a task file.
</when_to_activate>

<authority>
`git_review` owns the review criteria, the report headings, the `verified` / `inferred` labels, and the `<tags>` set. This skill keeps all of them as written and adds no rival review standard; `<convergence>` only decides which of that gate's findings qualify for an automated fix and how every other finding is reported. The base `task` skill owns the `<update>` workflow, and its `<status_discipline>` rule owns the status, that the user applies when the run leaves pending decisions for a task file.
</authority>

<path_resolution>
Bundled scripts live in `scripts/` next to this `SKILL.md`. Resolve each script's absolute path by combining the directory of this `SKILL.md` with `scripts/<script-name>` and invoke that absolute path. Resolve `git_review` as a same-plugin sibling skill under the skills-tree sibling form `git_review/`, whose first path component is that sibling's directory name under `skills/` and never a repository-root `plugins/<plugin>/skills/...` browse path. Resolve the three helper agents `auto_gate_git`, `auto_fixer_git`, and `auto_verifier_git` by their published names through the harness's normal agent mechanism; when the harness exposes only file paths, those agents live in the same plugin at `../../agents/` relative to this skill directory.
</path_resolution>

<inputs>
The run accepts one target and three optional prompt inputs.

- **Target.** The run has two target shapes. On the default branch the target is that branch's uncommitted change, reported under two lane labels: the `working-tree lane`, holding the staged, the unstaged, and the untracked changes, and the `local-commits lane`, holding the local commits ahead of the upstream. On any other checked-out branch the target is that branch's change: the commits from the merge base of the remote-tracking default ref and `HEAD` up to `HEAD`, plus the working tree, meaning the staged, the unstaged, and the untracked changes. The branch target's base is the `<remote>/<default>` ref `<orient>` resolves, read without a fetch, so the gate's `--no-fetch` requirement holds. Every fix lands in the working tree, uncommitted, and the branch's commits and ref stay as they are. Both lane labels are the step strings `collect_uncommitted` writes in `git_review`'s `scripts/collect_review_evidence.sh` (`working-tree lane:` and `local-commits lane:`), reused as this loop's `lane` vocabulary.
- **An optional named target**, written anywhere in the prompt as the literal phrase `branch <ref>` or `pull request <ref>`, matched case-insensitively. `<ref>` is a branch name in the shapes `git_review`'s `<accepted_forms>` accepts (a bare name or the `<remote>/<branch>` form) or a pull-request URL or number, and it counts as a named target only when it resolves to an existing branch or pull request. A pull-request ref resolves to its head branch through the same `<pull_request>` route `git_review` uses. `<orient>` accepts the named target when it is the checked-out branch and declines otherwise.
- **An optional task file path** that anchors scope, read by `<convergence>`'s **Scope anchor.** and by **Decisions.**. A task path that does not resolve to a readable regular file, with a relative value resolved against the repository root, is reported by `scripts/run_relay.sh` and the run stops under `<agent_failure_policy>`'s `helper-script` class at init, so no relay state is created for it.
- **An optional round-cap override**, written anywhere in the prompt as the literal phrase `round cap <N>`, matched case-insensitively, where `<N>` is a positive integer. Absent the phrase the run proceeds with the **Stop rule.**'s default cap. A phrase whose integer is zero, negative, or non-numeric is not an override: the run reports that the phrase is not an override and proceeds with the default cap.

The invoking harness may also supply environment notes describing a staged helper condition. Those notes are the harness's fixture seam; apply them exactly as written and follow `<agent_failure_policy>` from there.
</inputs>

<loop_policy>

<single_gate>
`git_review` is the only review gate. The loop invokes it through `auto_gate_git` and consumes that agent's structured verdict; it computes no second review score, re-derives no finding, and overrides no gate label.
</single_gate>

<lane_classification>
**Lane classification.** When `auto_gate_git` builds the structured verdict, every finding's `location` is `path:start` or `path:start-end`, 1-based inclusive. The coordinate convention, stated once here: `location` carries working-tree line numbers when the cited lines exist in the working-tree file the fixer edits, so `location`, the fixer's anchor, and the **Stop rule.**'s authored-hunk parse share those lines; it still reads `path:start` or `path:start-end` with index-world line numbers when the finding has no working-tree counterpart. The sole signal that a finding is not a working-tree line is its `lane` value `local-commits lane`; `location` carries no mark field. `auto_gate_git`'s `<output_contract>` template stays as that agent states it.

Walk the cases below in order. Cases 1 through 3 and 6 through 10 are terminal: the first matching terminal case sets that finding's location handling, its `lane`, and its fix disposition. Cases 4 and 5 are location rewrites only: when one matches, rewrite `location` as it states and continue the same ordered walk from case 6, so a later terminal case assigns `lane` and disposition. When none of cases 6 through 9 match, case 10 is the terminal case.

1. **`(staged)` scan-locus.** The report cites a `path:line` hit carrying the `(staged)` suffix that `git_review`'s `<evidence_set>` appends for the index line of content only the index holds. Keep the cited index-world `path:start` or `path:start-end` with no mark field, assign `lane` `local-commits lane`, list the finding as a follow-up task proposal, and make no fix.
2. **`### staged` lines absent.** The citation comes from the `### staged` section of `worktree_diff.txt` (the `git diff --cached` hunk numbering, distinct from the scan-locus suffix) and its added lines no longer appear in the working-tree file at that path. Apply the same disposition as case 1.
3. **`### staged` duplicated, no index-aligned hit.** The same `### staged` citation whose added lines leave several content matches in the working-tree file and none at the cited index-world numbers. Keep the cited location, assign `lane` `local-commits lane`, list the finding as a follow-up task proposal, and make no fix.
4. **`### staged` re-cite to working tree.** The same `### staged` citation whose added lines still appear in the working-tree file. Match those lines there and number `location` from the match; when they appear more than once, anchor the occurrence at the cited index-world numbers. This case rewrites `location` to that working-tree `path:start` or `path:start-end`, assigns no `lane`, and continues the ordered walk from case 6 using the rewritten location.
5. **Branch-range re-cite to working tree.** A citation from the branch-mode `full_diff.txt` whose added lines appear in the working-tree file at that path. Match those lines there and renumber `location` from the match; when they appear more than once, anchor the occurrence at the cited `HEAD`-side numbers. This case rewrites `location` to that working-tree `path:start` or `path:start-end`, assigns no `lane`, and continues the ordered walk from case 6 using the rewritten location. A citation whose added lines no longer appear in the working tree falls through to case 10 and is listed with no fix.
6. **`### unstaged` membership.** The path and range fall inside a `### unstaged` hunk at the working-tree lines the location names. Assign `lane` `working-tree lane`.
7. **`### untracked` membership.** The path falls in a `### untracked` section, read as that whole file's single hunk numbered from its first line, because `write_untracked_diffs` writes `+`-prefixed lines with no `@@` header. Assign `lane` `working-tree lane`.
8. **`### staged` membership.** The path and range fall inside a `### staged` hunk under the working-tree added-lines match of case 4, so a staged-then-edited change classifies by content rather than by coincident numbers. Assign `lane` `working-tree lane`.
9. **Clean tracked-file membership.** The path is tracked in the working tree and the cited lines exist there, with no `### staged`, `### unstaged`, or `### untracked` hunk covering them. Assign `lane` `working-tree lane`, so a finding the **Scope anchor.** admits outside the diff, including a task-file-anchored finding on an unmodified tracked file and a finding in a local commit or a branch commit whose file the working tree still carries, stays fixable.
10. **Catch-all.** Every other finding. Assign `lane` `local-commits lane`, which borrows `collect_uncommitted`'s `local-commits lane:` step string as vocabulary only and asserts no working-tree location and never that the finding concerns a local commit, and make no fix under the non-qualifying classification `<convergence>` states.

`auto_gate_git` loads this block and applies it as written when it assigns each finding's `lane` and `location`; its agent file carries no second copy of these cases.
</lane_classification>

<convergence>
<qualification>
A finding qualifies for an automated fix, and is a qualifying finding for the **Stop rule.** and for `auto_verifier_git` triage, only when all four conditions hold: its `tag` permits qualification, it meets the **Scope anchor.**, it carries `lane` `working-tree lane` under `<lane_classification>`, and it is not held under **Decisions.**. The gate verdict's `non_blocking` field is reporting-only: it carries `git_review`'s non-blocking mark through the structured verdict and does not enter the qualification conjunction.

**Tag permit.** On round 1's first review the tag is `none`; on a delta re-review the qualifying tag values are `open`, `open and not acknowledged`, `regressed`, and `new`, each still subject to the other three conditions above. A `closed` finding and a `settled by a decision` finding never qualify and receive no fix.

Every gate-listed finding that does not qualify is classified once here and rendered on the two surfaces each already holds. The run lists the finding with its `lane` and no fix, naming it a follow-up task proposal where it is a pre-existing issue or a scope extension under the **Scope anchor.**, a lane-excluded finding under `<lane_classification>`, or a tag-excluded finding, meaning `closed` or `settled by a decision`, under this paragraph's tag permit. The first rendering surface is the gate's `git_review` report, which keeps the finding under its heading; that heading's presence follows `<first_review_presence>` and `<delta_presence>` as written. This reporting obligation overrides `git_review`'s `<non_findings>`, `<lint_baseline>`, and `<only_what_is_open>` suppression rules inside `auto_gate_git`'s composition of that gate report, so a non-qualifying finding this classification keeps stays present under its heading there. The second surface is `report.txt` under `<relay>`, which carries that finding as its one line and remains only the loop's terminal surface, distinct from the gate report and not itself the subject of those `git_review` suppression rules.
</qualification>

<scope_anchor>
**Scope anchor.** A finding meets the Scope anchor when it concerns lines the change added or modified, or behaviour the change's intent covers, read from the anchoring task file's `## Goal` and `## Acceptance` when a task file is given.

A reproduction `auto_fixer_git` adds is not part of the change under review: a file reproduction lives at a path of its own that its `ledger.txt` line names and that no path under review shares, and the gate and the verifier label a location as reproduction lines when its path matches a path named in `ledger.txt`. A finding whose location sits only in reproduction lines therefore never meets the Scope anchor; it is listed in the report and receives no fix. The reproduction's own correctness is enforced by the **Regression ledger.** restore-and-retry, not by gate qualification.

A pre-existing issue and a scope extension go to the report as follow-up task proposals.
</scope_anchor>

<regression_ledger>
**Regression ledger.** The ledger is `ledger.txt` in the run's relay directory, one reproduction per line, each line the reproduction's path, a tab, then the command that runs it, so the path the **Scope anchor.** matches a finding's location against is a named field. A bundled script, `scripts/run_ledger.sh`, runs each line's command field in order and reports each line's 1-based number with its pass or fail; it exits 0 on an all-passing ledger and on an empty ledger, and exits non-zero naming the 1-based number of the first failing entry.

The orchestrator runs `scripts/run_ledger.sh` after every fix round. A failing line restores the round's pre-fix state and repeats the round once with the failing line named to the fixer; a second failure restores the pre-fix state and the **Stop rule.**'s second-ledger-failure condition stops the run.
</regression_ledger>

<decisions>
**Decisions.** Every entry under `Decisions the implementer must make before fixing`, and every finding whose fix depends on one, goes to the user and receives no fix. When a task file anchors the run, the run only threads that wording out: `report.txt` carries the wording and the pending decisions under `<relay>`, and the base `task` skill's `<update>` workflow, with `<status_discipline>` deciding the status, is the change the user applies after the stop. No agent in the run writes outside the working tree and the relay.
</decisions>

<stop_rule>
**Stop rule.** A round is one gate cycle: the unit the round cap, the consecutive-round stop, and the authored-hunk append all count. The round lifecycle runs in this order.

1. **Open.** One `auto_gate_git` call: the first review on round 1, then each delta re-review.
2. **Decision-pending early close.** When the gate return carries any entry under `Decisions the implementer must make before fixing`, or any finding held under **Decisions.**, the round closes on the stop condition "a decision is pending" without invoking triage, `auto_fixer_git`, the ledger check, or `<audit_delta>`, including when other findings would otherwise qualify for an automated fix.
3. **Empty-qualifying early close.** When Open's verdict carries no qualifying finding, the round closes on the stop condition "no qualifying finding remains" without invoking triage, `auto_fixer_git`, the ledger check, or `<audit_delta>`. Triage never runs on an empty qualifying set.
4. **Triage.** `auto_verifier_git` triage of that verdict, reached only when the qualifying set is non-empty and step 2 did not close the round.
5. **Empty-approved early close.** When triage of a non-empty qualifying set returns an empty approved set, the round closes on that stop condition without invoking `auto_fixer_git`, the ledger check, or `<audit_delta>`.
6. **Self-written early close.** When this round's qualifying findings are a non-empty set, every one of them sits in loop-authored code under case 6 of the Close cases below, and the immediately preceding round also met that same condition, the round closes on the stop condition "two consecutive rounds whose qualifying findings all sit in code the loop wrote in an earlier round" without invoking `auto_fixer_git`, the ledger check, or `<audit_delta>`.
7. **CHARTER-refusal early close.** When `CHARTER.md` exists and the orchestrator's CHARTER-before-write validation refuses the approved set under `<charter_before_write>`, after that set is known and before any `auto_fixer_git` spawn, the round closes on that stop condition without invoking `auto_fixer_git`, the ledger check, or `<audit_delta>`. `report.txt` follows the charter-set-refused reporting `<relay>` states.
8. **Snapshot.** When none of steps 2, 3, 5, 6, or 7 closed the round, `scripts/run_snapshot.sh` writes the round's pre-fix artefacts, and the round-1 baseline pair when that pair is absent, after Open's gate return is in place and before the first `auto_fixer_git` invocation. An early-close round invokes neither `scripts/run_snapshot.sh` nor a rewrite of those artefacts.
9. **Fix.** `auto_fixer_git`'s fix, skipped when step 2, 3, 5, 6, or 7 closed the round.
10. **Ledger check.** The **Regression ledger.** check, with its own one restore-and-retry.
11. **Audit delta.** `<audit_delta>`, with its own one restore-and-retry.
12. **Close.** The point the loop returns to the gate for the next round or stops. When this round reached step 9 and steps 10 and 11 both succeeded with the round's writes still landed, meaning no Restore undid them, the orchestrator rewrites `authored.txt` under the stem directory per the Close cases below. When a Restore undoes the round's writes, or when an early close skipped step 9, `authored.txt` stays unchanged. After Close, before the next Open, the run evaluates the round-cap stop: every completed gate cycle counts toward the cap, steps 2, 3, 5, 6, and 7 included; when the completed-round count has reached the cap, the run stops under the round-cap condition without opening another round.

A restore-and-retry stays inside its round and never starts or counts a new one. "fix round" and the ledger's "repeats the round once" name this same unit. The run stops when any of these conditions holds:

- no qualifying finding remains;
- after `auto_verifier_git` triage of a non-empty qualifying set, the approved set is empty;
- a decision is pending;
- a cap of 5 rounds unless overridden, evaluated after Close before the next Open as step 12 states;
- two consecutive rounds whose qualifying findings all sit in code the loop wrote in an earlier round;
- a helper failure under `<agent_failure_policy>`;
- a second **Regression ledger.** failure after that rule's one restore-and-retry;
- a second `<audit_delta>` unmapped-hunk result after its one restore-and-retry;
- `<concurrent_modification_guard>` finds the working tree diverging from that round's pre-fix snapshot for a reason other than this run's fixer;
- the CHARTER-before-write validation refuses a write a qualifying finding's `Fix:` requires, so the refused path holds no write from this run.

The Close cases for the `authored.txt` rewrite and the self-written stop:

1. **Entry shape.** One entry per line; each line is the greppable `path:start` or `path:start-end` form `<lane_classification>` already settles, 1-based inclusive, naming the path and the line range `auto_fixer_git` changed on that path in whole-file coordinates on the working-tree file the gate numbers `location` against.
2. **Re-anchor.** A hunk an earlier round recorded is re-derived at its current lines when a later round's fix shifts them.
3. **Derivation.** Diff the run's authored baseline against the current working tree; take each changed path plus the line ranges that diff marks on the current file, so `authored.txt` holds the loop's cumulative authored changes at their current whole-file lines.
4. **Baseline versus per-round snapshot.** The authored baseline is the round-1 pre-fix copy kept as `baseline.patch` and `baseline.untracked.tar` under the stem. It is distinct from the per-round `pre-fix.patch` and `pre-fix.untracked.tar` that `scripts/run_snapshot.sh` writes and rewrites each round that reaches step 8, and the per-round writer never writes over the baseline pair.
5. **Materialize and diff.** The temporary directory is a copy of `HEAD` with `baseline.patch` applied and `baseline.untracked.tar` extracted; `diff -ruN -U0` against the working tree yields each changed path, fixer-added and fixer-deleted paths included because they are present on only one side, and each hunk's line range on the current working-tree file.
6. **Self-written stop.** Parse each gate finding's `location` for a path and a line or line range. The finding sits in loop-authored code when that path matches an entry's path and the parsed line or range intersects that entry's range. The stop rule reads only `authored.txt`.
</stop_rule>
</convergence>

<relay>
Files live under `.git_auto_review/<run-stem>/` at the repository root the toplevel `git rev-parse --show-toplevel` reports, so every relay path resolves from that one root. Derive `<run-stem>` as the optional task file's basename without its extension when that path is given, and use `default` when it is omitted; a task path that does not resolve is rejected and the run stops under `<agent_failure_policy>`'s `helper-script` class at init, as the `<inputs>` task-path bullet states.

After `<orient>` accepts the branch, and only then, `scripts/run_relay.sh` creates `.git_auto_review/.gitignore` containing the sole line `*`, creating the `.git_auto_review/` directory as part of that write, creates the stem directory, and clears everything an earlier run left there. A gate return for any round is pre-seeded deliberately, so the run's invoker stages one marked pair per pre-seeded round, `gate-r<round>.txt` plus that round's marker file `gate-r<round>.preseed` beside it, an empty file whose presence alone marks the pair, created by the harness rather than by the gate, before the run starts. The initialise step's clear preserves every marked per-round pair, keyed by its `gate-r<round>.txt`, while removing every other file an earlier run left there. The initialise step then writes an empty `ledger.txt` under the stem, zero reproduction lines, so that path exists before any fixer append.

Each relay file holds exactly one round's record, all under the stem directory:

```text
.git_auto_review/<run-stem>/
  gate-r<round>.txt          that round's gate return, consumed verbatim
  gate-r<round>.preseed      empty marker: presence selects the pair
  gate-r<round>-prompt.txt   the prompt text the round composed
  fixer-r<round>.txt         prompt-plus-return pairs, in invocation order
  verifier-r<round>.txt      triage then delta prompt-plus-return pairs
  round-r<round>.diff.txt    the round's fixer-write diff, diff -U0
  ledger.txt                 the regression ledger
  report.txt                 the run's report
  pre-fix.patch              per-round captured tracked changes
  pre-fix.untracked.tar      per-round captured untracked files
  baseline.patch             round-1 baseline pair, written once
  baseline.untracked.tar     round-1 baseline pair, written once
  authored.txt               cumulative authored hunks, current lines
```

`gate-r<round>.txt` holds that round's gate return, consumed verbatim as the gate return in place of a gate invocation only when `gate-r<round>.preseed` is present beside it at the round's start. A `gate-r1.txt` an earlier run left with no marker is cleared, and the round invokes the gate.

`fixer-r<round>.txt` holds the round's `auto_fixer_git` records in invocation order, each one prompt-plus-return pair, its prompt followed by its return, so a retry's additional invocation appends its pair after the prior pair in that same file. `verifier-r<round>.txt` holds the round's `auto_verifier_git` records in invocation order: the triage invocation's prompt-plus-return followed by each delta invocation's prompt-plus-return, its prompt followed by its return in each case, so a retry's second delta invocation appends after the first.

`round-r<round>.diff.txt` holds the round's fixer-write diff. The orchestrator writes it after the round's `auto_fixer_git` writes and before the verifier's delta invocation, as a zero-context unified diff (`diff -U0`) of the round's pre-fix snapshot against the current working tree, so each hunk is one contiguous changed region.

The gate prompt the round composes is persisted beside that round's gate record as `gate-r<round>-prompt.txt`, holding the prompt text the round composed, whether that round invoked `auto_gate_git` or consumed a pre-seeded return.

`ledger.txt` holds the run's regression ledger under **Regression ledger.**, and each of the gate and verifier prompts names it among its inputs so both apply the reproduction-line exclusion **Scope anchor.** defines.

`report.txt`, written under the stem directory at each stop and reprinted to the caller, is the run's report: the loop's own terminal answer, distinct from the `git_review` report the gate return carries. It carries, in order: a stop line naming the **Stop rule.** condition that ended the run; then one line per finding the run did not fix, carrying its id, heading, location, lane, and either its follow-up task proposal or non-qualifying class under `<convergence>`'s once-stated classification, or the class `triage-not-approved` with the reason `auto_verifier_git` returned for that finding under its triage `<output_contract>`, or the class `charter-set-refused` for each finding of an approved set the CHARTER-before-write validation refused; then the pending decisions, with the wording each records into a supplied task file.

Every "the report lists", "the report names", and "the report carries" in this skill reads `report.txt`.
</relay>

<verification_standard>
Verification runs through `auto_verifier_git`, refute-by-default, in two modes. Triage mode judges each qualifying finding of the round's gate verdict: it approves a finding only when the fix the finding's `Fix:` names is real, minimum, scope-anchored, and safe, and returns `not-approved` with a reason otherwise. Delta mode judges the round's fixer-write diff.

The run applies only the approved set, and it applies no fix at all when the approved set is empty.
</verification_standard>

<audit_delta>
After every fix round, write `round-r<round>.diff.txt` under `<relay>` and invoke `auto_verifier_git` in delta mode. When the verifier marks any hunk `unmapped`, restore the round's pre-fix state, retry the fixer once over the approved findings with the unmapped hunks named, and on a second unmapped result restore the pre-fix state and stop under the **Stop rule.**'s second-unmapped-hunk condition.
</audit_delta>

<concurrent_modification_guard>
Each round's baseline is that round's pre-fix snapshot: the tracked patch plus the untracked-file copy the Restore procedure uses, whose enumeration follows the snapshot's own (`git status --porcelain --untracked-files=all`, ignored paths excluded), so the guard and the Restore procedure read one path set.

Check the baseline before every `auto_fixer_git` invocation in the round. The **Stop rule.**'s concurrent-modification condition fires only when the working tree diverges from that snapshot for a reason other than this run's fixer.

Two path sets are outside the guard. The gate's evidence scratch, which `git_review` writes outside the reviewed tree, and the run's ignored relay directory never fire the guard, and a restore never deletes a run file.

After every `auto_fixer_git` write in the round, the orchestrator runs the **Regression ledger.** check first, then `<audit_delta>`. **Regression ledger.** and `<audit_delta>` each keep their own one restore-and-retry, so a round may invoke `auto_fixer_git` once for the initial fix and once more per failure class that authorizes a retry. Every invocation receives the round's full approved finding set together with the named failure that class raises, the failing ledger line for a **Regression ledger.** retry and the unmapped hunks for an `<audit_delta>` retry, so a retry re-applies the round's other approved fixes after the restore rather than leaving them unlanded.
</concurrent_modification_guard>

<agent_failure_policy>
A helper failure stops the run, with no retry. A helper failure is one of five classes:

1. the helper fails to spawn;
2. the helper dies mid-run;
3. the helper returns a contract-violating return, one whose `<output_contract>` section arrives summarized or missing, the pre-seeded `gate-r1.txt` return the `stops_on_helper_failure` eval stages included;
4. the helper declares an inability, with settled detection: a completed return whose `<output_contract>` field list is present and complete and that contains, as its own line, the literal marker `helper_result: unable`, optionally followed on that same line by a tab and a reason. That marker is the sole accepted inability signal, so a complete return without it is a normal verdict, and a return whose field list is summarized or missing stays the contract-violating class even when the marker or other inability prose appears;
5. a bundled helper script this skill ships exits non-zero. The class's signals are `scripts/run_relay.sh` at init, `scripts/run_snapshot.sh` at the Snapshot step, and `scripts/run_restore.sh` when it cannot reproduce the captured state. `scripts/run_ledger.sh` stays outside this class because its non-zero exit has its own move under **Regression ledger.**.

Each class carries one label for the stop line, in this order: `spawn-failure`, `mid-run-death`, `contract-violating`, `declared-inability`, `helper-script`. The run stops with no unverified helper text applied, and `report.txt`'s stop line names the class by that label. A stop that lands before the round's first `auto_fixer_git` write leaves the working tree at its pre-run state, and a later one runs the round's Restore first, so no half-fixed tree remains, except when the failing helper is `scripts/run_restore.sh` itself: there Restore cannot have run, so the run leaves the working tree at the state that failed restore produced and makes no further working-tree write.
</agent_failure_policy>

<loop_bounds>
The **Stop rule.** owns the round cap and every stop condition; this block points at that rule by name and restates none of them.
</loop_bounds>

<snapshots>
Save each round's pre-fix state as two files under the stem directory, written by `scripts/run_snapshot.sh` at the Snapshot step, once the round's gate return is in place and before the first `auto_fixer_git` invocation in the round, and only when that step runs. The writer rewrites them for each round that reaches Snapshot.

- `pre-fix.patch` holds the patch of the round's tracked changes with the index and the worktree read together, produced by `git diff HEAD --binary --no-color --no-ext-diff`, so a staged change and a staged-then-edited change both round trip.
- `pre-fix.untracked.tar` holds a copy of the untracked files present before the fix, enumerated with `git status --porcelain --untracked-files=all` with ignored paths excluded.

On round 1 alone the writer also writes the baseline pair `baseline.patch` and `baseline.untracked.tar`, the run's start-state snapshot the **Stop rule.** diffs `authored.txt` against, only when that pair is absent, and it never rewrites that pair.

**Restore.** The procedure every restore-and-retry in this skill runs returns the working tree to the captured state solely from those two per-round files, never touching committed history. Reset every tracked path's working-tree content to `HEAD` with `git restore --source=HEAD --worktree -- .`, which leaves the index untouched, and remove a working-tree file the index knows and `HEAD` does not. Then apply `pre-fix.patch` forward into the working tree alone, never with `--index` or `--cached`, so the captured worktree content the patch's postimage holds becomes the working-tree state again, while the index keeps the content it held at capture, and skip the apply when the patch is empty. Copy each file in `pre-fix.untracked.tar` back over its working-tree path, and delete the untracked files the fixer added that the copy does not contain. `scripts/run_restore.sh` carries out this procedure and exits non-zero when it cannot reproduce the captured state.
</snapshots>

<charter_before_write>
When `CHARTER.md` exists at the repository root, the orchestrator validates each approved finding's `Fix:` paths against that file's boundaries and invariants before the first `auto_fixer_git` spawn for that finding set. When any path in that set crosses a boundary, the orchestrator refuses the entire approved set without spawning `auto_fixer_git`, so every approved finding in that set, the crossing member and every non-crossing member alike, holds no write from this run. `report.txt`'s stop line names the CHARTER-before-write condition, and `report.txt` lists each finding of that refused approved set on its own line with the class `charter-set-refused`, which is distinct from a helper failure under `<agent_failure_policy>`.
</charter_before_write>

</loop_policy>

<workflow>

<orient>
Resolve the default branch by reading the remote `HEAD` symref `refs/remotes/<remote>/HEAD` for the remote the checked-out branch's upstream names, `origin` when it names none, and fall back to the `HEAD branch:` line of `git remote show <remote>` when that symref is absent. Both routes advertise a head without moving a ref, so the gate's `--no-fetch` requirement holds.

When neither route yields a default branch, abort the run.

Read the checked-out branch with `git symbolic-ref --short HEAD`. Decline the run in two cases: when that command fails because `HEAD` is detached, and when the `<inputs>` named-target input names a branch or pull request other than the checked-out branch, recognized only through that input's literal phrase and never from a bare mention of the words "branch" or "pull request"; a decline on the named target names `git_checkout` as the skill that puts the repository on it. Otherwise accept the run: the default branch takes the default-branch target, and any other checked-out branch takes the branch target.

Abort and decline are the same terminal move: report the condition and stop there, before any gate call, with no working-tree write and no relay or evidence-scratch artefact created.
</orient>

<initialise>
Read the optional task file path and the optional round-cap override from the prompt per `<inputs>`, reporting a phrase whose integer is not a positive integer and proceeding with the default cap, and stopping under `<agent_failure_policy>`'s `helper-script` class when the task path does not resolve as that bullet states. Create the relay directory and its `.gitignore`, and clear the stem's leftovers while preserving every marked pre-seeded round pair, through `scripts/run_relay.sh` per `<relay>`. Write the empty `ledger.txt`.

When `scripts/run_relay.sh` exits non-zero, the run stops under `<agent_failure_policy>` at that point and makes no relay write of its own: no `.git_auto_review` directory, no `.gitignore`, and no `ledger.txt`, so a run that dies at init leaves the repository exactly as it found it. The stop line this run reprints names the class by its literal label `helper-script`, the same label `<agent_failure_policy>` assigns that class.
</initialise>

<round_driver>
Drive rounds until the **Stop rule.** ends the run. Each round composes the `auto_gate_git` prompt for its target, persists it as `gate-r<round>-prompt.txt`, and either invokes `auto_gate_git` or consumes the marked pre-seeded return as written. Round 1 is a first review; from round 2 the prompt names the prior round's gate return path as the prior findings set and directs a `<re_review>` / `<tags>` pass under `git_review`, with the same target shape as round 1 and no edit to `git_review`.

Then walk the **Stop rule.** steps in order: early-close checks, Snapshot, the approved fix through `auto_fixer_git`, the ledger check, `<audit_delta>`, and Close with its `authored.txt` rewrite.
</round_driver>

<report>
Write `report.txt` under the stem directory per `<relay>` and reprint it to the caller as the run's answer. When the run stopped before any relay directory existed, because `scripts/run_relay.sh` failed at init, reprint the report to the caller as the run's answer instead of writing `report.txt`, since no stem directory exists to write it into.
</report>

</workflow>

<output_contract>
The run's deliverable is `report.txt`, written to the relay and reprinted to the caller. It does not itself produce a `git_review` report; the gate report lives inside the consumed gate return, which `report.txt` references through its finding lines.
</output_contract>

<family>
`git_auto_review` sits beside `git_review` and mirrors `task_auto_check`'s loop shape for a change rather than a task. Each does one job and points at the next:

- `git_review` reviews a change and reports under its headings, manually.
- `task_auto_check` drives one task to readiness.
- `task_auto_implement` runs implement, audit, and finish for one task.
- `git_auto_review` runs the automated review-and-fix loop for a finished change **(this skill)**.

It reviews; committing, pushing, and review-comment publication stay with the user and the `git_*` siblings.
</family>

</git_auto_review_skill>
