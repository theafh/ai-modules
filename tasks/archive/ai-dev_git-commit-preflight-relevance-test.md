---
description: git_commit's pre-flight gate gains a path-relevance test for obligations, mirrors it into manual_fallback, ships skip/run evals — so commits skip gates that prove nothing on the touched paths.
scope: plugins/ai_dev/skills/git_commit
created: 2026-09-01T12:03:24
updated: 2026-09-01T22:21:17
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Apply a relevance test in git_commit's pre-flight gate, sync manual_fallback, and ship eval coverage

## Goal

`git_commit`'s `<prepare_worktree>` gate decides whether each discovered obligation runs by testing whether this commit's changed paths intersect the subject matter that obligation governs, in place of satisfying every rule it finds. An obligation whose domain the change never touches is skipped and the skip is stated, a relevant one still runs, and an obligation whose domain cannot be determined runs as well. The user-visible outcome: committing a change that implicates none of a repository's slow gates stops blocking on a suite that checks nothing the commit touched, while every obligation that does bear on the change is still honored.

## Context

The gate lives in `plugins/ai_dev/skills/git_commit/SKILL.md` as `<prepare_worktree>`, the first child of `<primary_workflow>`, holding the ordered children `<discover>`, `<satisfy>`, and `<confirm>`. It shipped through [the pre-flight obligations task](ai-dev_git-commit-preflight-obligations.md) to stop agent-directed obligations being silently skipped, the observed failure being a run that committed a skill edit without its required lockstep version bumps because no workflow step ever surfaced the rule. That no-skip guarantee is the property this task keeps intact while adding the filter.

Two wordings inside the gate make the model run everything it discovers. `<discover>` asks for "every agent-directed rule that bears on this commit" with no clause about what actually changed, so a standing rule phrased as running a suite before every commit reads as bearing on every commit unconditionally. `<satisfy>` then says "Check-only obligations may also run here to expose a failing gate before context work begins", which names an upside and no cost, so a check-only obligation reads as endorsed rather than weighed. In a repository whose suite runs for minutes, the result is a commit stalled on a suite that exercises nothing the change touched, at a moment that is often just the checkpoint before further work.

The only distinction the gate draws today is tree-mutating against check-only, and that distinction governs ordering relative to `<gather_context>` rather than whether an obligation is worth running at all. Relevance is the missing axis, and it is domain intersection rather than file type: a markdown lint over a documentation-only change is relevant and must still run, while a compiled-language format pass over that same change is not.

`references/manual_fallback.md` mirrors the gate under the heading "Pre-flight ordering before context capture", carrying the same tree-mutating against check-only split and the same "check-only obligations may run here to expose a failure early" sentence, so the two files move together.

The gate runs before `prepare_commit_context.sh`, so the changed path set is not yet captured at the moment the relevance test needs it. `<consume_context>`'s `<hard_rules>` bans re-deriving the commit context with `git diff`, `git status`, or `git log`, and already carves out one narrow exception for the drift-detection status read, spelling out why that carve-out and the ban read as one consistent rule. The relevance test needs the same kind of narrow, path-names-only read, so that ban needs the same reconciliation.

`tests/git_commit/evals/evals.json` covers the message contract, the commit-all default, the large-changeset path, the script-failure fallback, and both drift branches. No scenario exercises the pre-flight gate at all, so this behaviour arrives with its own coverage.

## Approach

Insert the relevance test between discovering an obligation and satisfying it, rewriting `<discover>`, `<satisfy>`, and `<confirm>` in place so one canonical statement of each rule remains.

Keep discovery broad. The gate still finds every agent-directed rule the harness surfaces, and the reworded `<discover>` says that finding a rule is not yet a commitment to run it, leaving the run-or-skip call to the test.

Define the test as domain intersection. Read the obligation to determine the subject matter it governs, meaning the paths, file types, or artefacts it checks or rewrites, and compare that against the paths this commit changes. Run the obligation when the two intersect and skip it when they do not. Anchor the rule to that intersection rather than to any prose-against-source or file-type taxonomy, so a markdown lint over a documentation-only change still runs while a language- or asset-specific gate over that same change does not.

Reword `<confirm>` so it confirms each obligation the relevance test chose to run is settled before `<gather_context>`, preserving the no-skip guarantee for obligations that ran or could not be classified.

Apply the test to every discovered obligation, tree-mutating and check-only alike, and narrow the existing tree-mutating against check-only split to the one job it already does well: ordering the relevant obligations relative to `<gather_context>`, with the tree-mutating ones settled before context capture.

Name where the changed path set comes from. The gate reads it at pre-flight time with a path-names-only `git status --short --untracked-files=all` before `prepare_commit_context.sh` runs — the same flags the drift guard and bundled scripts already use — and `<consume_context>`'s `<hard_rules>` passage is reworded to cover this second narrow read exactly as it already covers the drift-detection one, so the ban and its carve-outs stay a single consistent rule.

Preserve the no-skip guarantee on both sides of the new filter. A relevant obligation still runs, and an obligation whose governed subject matter the model cannot determine runs rather than being skipped, following the same no-miss-over-no-sweep tiebreaker `<commit_scope>` already applies to the drift guard. Make each skip visible: the gate states which obligation it skipped and on what grounds, so a wrong skip is correctable in the moment.

Replace the permissive sentence about check-only obligations with one that weighs both sides, keeping the upside it already names and adding the cost of spending commit time on a check that exercises nothing the change touched.

Mirror every one of these changes — including the `<confirm>` checkpoint — into the pre-flight section of `references/manual_fallback.md`, keeping one canonical statement of the ordering and the relevance test across the two files.

Confine the edit surface to `<prepare_worktree>` (including `<discover>`, `<satisfy>`, and `<confirm>`), the `<hard_rules>` ban's wording, and the manual fallback's pre-flight section, leaving the drift guard, its `--accept-drift` path, the commit-all default, and the commit-message policy exactly as they stand. Keep the gate repository- and harness-agnostic, describing rule sources generically as it does today.

Ship the coverage with the change: two scenarios in the `evals/` harness per standing repo rules. Each fixture plants agent-directed obligations through a sandbox `AGENTS.md` standing rule and a helper script that writes an observable marker under `.eval/markers/` when the obligation runs; `grade.sh` asserts marker presence or absence on the post-run sandbox.

Wire each new scenario through `tests/git_commit/evals/stage.sh`, `grade.sh`, `evals.json`, `run.py` (`DEFAULT_IDS`), and `evals/README.md` (layout tree and fixtures list), matching the existing eval 1–7 pattern.

**Out of scope:** Enumerating or executing any specific repository's lint, format, test, or version-bump logic, which the gate keeps delegating to the repository. Running or pre-empting command-triggered git and harness hooks, which stay with the commit command that fires them. Backfilling eval coverage for the parts of `<prepare_worktree>` this change leaves untouched, beyond the two scenarios that prove the relevance test.

## Acceptance

- `<prepare_worktree>` carries a relevance test that decides whether each discovered obligation runs, stated as an intersection between the paths this commit changes and the subject matter the obligation governs. Reading the block shows the test keyed on that intersection rather than on a file-type taxonomy.
- The test governs tree-mutating and check-only obligations alike, and the block's tree-mutating against check-only split now governs only ordering relative to `<gather_context>`. Reading the block shows both statements and no passage claiming that split decides whether an obligation runs.
- The sentence "Check-only obligations may also run here to expose a failing gate before context work begins" is gone from `SKILL.md`, superseded by one canonical statement naming both the upside and the cost of running a check the change does not implicate. Grepping `SKILL.md` for the old sentence returns nothing.
- `<discover>` no longer reads as a commitment to satisfy everything it finds: reading `<discover>` and `<satisfy>` together gives one consistent statement that discovery is broad and the relevance test decides what runs.
- Grepping `SKILL.md` for "Confirm each discovered tree-mutating obligation" returns nothing, and reading `<confirm>` shows the checkpoint applies to obligations the relevance test chose to run.
- `<prepare_worktree>` names how it obtains the changed path set before `prepare_commit_context.sh` runs — `git status --short --untracked-files=all` — and `<consume_context>`'s `<hard_rules>` passage is rewritten to cover that read alongside the drift-detection one. No passage in `SKILL.md` forbids the read the gate now performs, and one canonical statement of the ban and its carve-outs remains.
- The gate states that an obligation whose changed-set intersection cannot be determined runs rather than being skipped, and that each skipped obligation is reported together with the grounds for the skip. Reading the block shows both.
- The "Pre-flight ordering before context capture" section of `references/manual_fallback.md` carries the same relevance test, the sentence "check-only obligations may run here to expose a failure early" is superseded there, and no statement in the section contradicts `SKILL.md`. Grepping the file for the old sentence returns nothing.
- Grepping `references/manual_fallback.md` for "satisfy every discovered tree-mutating obligation" returns nothing, and the pre-flight section's confirm wording matches `SKILL.md`'s `<confirm>` checkpoint.
- Reading `<detect_drift>`, `<execute_commit>`, `<commit_scope>`, and `<message_policy>` in `plugins/ai_dev/skills/git_commit/SKILL.md` shows each block unchanged in substance; the only edits outside `<prepare_worktree>` are to `<consume_context>`'s `<hard_rules>`.
- Reading `<prepare_worktree>` and the `Pre-flight ordering before context capture` section of `references/manual_fallback.md` shows obligation discovery phrased with generic rule-source wording and names no harness-specific standing-doc filename. Grepping both passages for `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, and `.cursor/rules` returns nothing.
- The skip scenario's fixture plants an agent-directed obligation via sandbox `AGENTS.md` and a marker script whose subject matter the staged change does not touch. `grade.sh` for that eval passes when the commit lands, the marker file for that obligation is absent under `.eval/markers/`, and an agent-attest line records that the skill skipped the obligation and stated the grounds.
- The run scenario's fixture plants an agent-directed obligation whose subject matter the staged change touches. `grade.sh` for that eval passes when the obligation's marker is present under `.eval/markers/` before the commit completes and the commit lands.
- `tests/git_commit/evals/stage.sh`, `grade.sh`, `evals.json`, `run.py` (`DEFAULT_IDS`), and `evals/README.md` each gain matching arms for both new scenarios; running `grade.sh` for each new eval id against a correctly staged fixture exits 0 on every programmatic check.
