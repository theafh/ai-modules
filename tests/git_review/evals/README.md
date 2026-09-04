# git_review behavioral evals

Forty-eight evals over thirty-six fixtures, driven by `run.py`, which spawns one
sonnet-pinned `claude -p` worker per eval and grades the result with `grade.sh`.
The schema is skill-creator's canonical `evals.json`
(`{id, prompt, expected_output, files, expectations[]}`).

## Running

```bash
python3 tests/git_review/evals/run.py            # every eval
python3 tests/git_review/evals/run.py 13 32 44   # a subset
python3 tests/git_review/evals/run.py --force 1  # ignore the cached verdict
```

`RUNBOOK.md` in the parent directory has the staging, grading, cache, and
timeout details.

## How an eval is graded

`grade.sh` runs the verifiable subset of each eval's expectations against three
sources:

- **The sandbox repository.** Which branch it ends on, whether a branch was
  fast-forwarded to its upstream, whether the tree is
  clean, whether a named path survived, whether a new commit landed, whether a
  scratch worktree was removed, whether a stash exists.
- **The stub `gh` call log.** Every invocation the run made, one per line. This
  is what proves a run posted nothing, posted exactly one comment, edited rather
  than re-posted, or resolved exactly one thread.
- **The worker's `response.txt`.** Heading presence and order, the labels, the
  named paths and documents.

Expectations that only a reading of the transcript settles print as
`agent-attest` lines. They are not passes: read them against `response.txt`
before calling an eval green.

## The stub `gh`

Forge-layer fixtures install a stub `gh` into `<target>/bin` and point the
worker's `PATH` at it through `<target>/gh_env`. The stub serves the JSON in
`<target>/payloads/` and appends every invocation to `<target>/gh_calls.log`.
It answers `auth status` as authenticated, serves the pull request body, the
issue comments, the review bodies, the check rollup, the branch rulesets, and
two pages of review threads, and returns a comment URL for a post.

The cursor test in the stub matches the `-F cursor=` **argument** rather than the
word `cursor`, because the GraphQL query text itself declares `$cursor`. Matching
loosely would serve page two on the very first call and hide a pagination bug.

## Fixtures

| Fixture | Evals | What it stages |
| --- | --- | --- |
| `behind_clean` | 6 | The checked-out branch is behind its remote on a clean tree. |
| `behind_dirty` | 7 | Behind its remote with an uncommitted edit to the same file. |
| `binary_and_generated` | 21 | One binary asset, one generated Go file, and one vendored file. |
| `clean_change` | 2 | A docstring correction whose test already exists, so no heading has a finding. |
| `conflicting_branch` | 3 | The base rewrote the same file after the branch left it, so the test merge conflicts on config.ini. |
| `deep_file_defect` | 18 | A 4800-line file whose only defect sits at the very end. |
| `default_branch_uncommitted` | 5 | On the default branch with staged, unstaged, and untracked changes plus one commit ahead of the upstream. |
| `delta_rereview` | 32 | A prior review by this reviewer, newer author replies, and a tree carrying one instance of every delta tag. |
| `existing_post` | 42 | A comment already on the pull request from this reviewer. |
| `gate_disagreement` | 26 | The workflow and the documented make target run different commands for the same gate. |
| `gates_workflow_and_runner` | 25 | A test suite plus a workflow whose gate command matches the documented one. |
| `guardrails_absent` | 29 | The same shape of change with none of those documents present. |
| `guardrails_present` | 28 | All four root guardrail documents, a precedent commit on the same charter constraint, and a branch that crosses it. |
| `hook_refusal` | 8 | A policy hook refuses to leave the main worktree on the target branch and restores the previous one; linked worktrees are outside the guard. |
| `lint_baseline` | 23 | Three sibling modules already carry the lint hit, and the linter the project names is absent from PATH. |
| `posting` | 36, 37, 38, 39, 40 | An ordinary pull request with the stub gh, used by the publishing evals. |
| `pr_head_mismatch` | 14 | The forge head runs one commit ahead of the checked-out HEAD. |
| `pr_paged_threads` | 15 | Review threads across two pages, including one resolved and one outdated thread. |
| `pr_required_review` | 13 | A pull request blocked only by a required review, with two issue comments, one review body, and one inline thread. |
| `pr_stale_claims` | 16 | A pull request body claiming a version and a test count the branch does not carry. |
| `push_approval` | 41 | One approval on the pull request and a ruleset that dismisses stale reviews on push. |
| `remote_only_dirty` | 12 | The same, with an uncommitted edit the switch would overwrite. |
| `remote_only_target` | 9, 10, 11 | The target branch exists only on the remote and has been fetched. |
| `reviewer_edit` | 45, 46, 48 | A clear defect on a repository the user can write to. |
| `reviewer_edit_blocked` | 47 | The same defect on a fork whose CODEOWNERS assigns the path elsewhere. |
| `runner_no_workflow` | 27 | A documented task runner and no continuous-integration definition at all. |
| `schema_consumer_drift` | 24 | A renamed schema field with a consumer still reading the old name. |
| `secrets_and_home_path` | 20 | An added credential-shaped line and an added hardcoded home path. |
| `seeded_findings` | 1, 33, 34, 35 | A feature branch whose diff places at least one finding under each of the seven findings headings, with the four guardrail documents present and a clean test merge. |
| `settled_decision` | 17 | A design question the repository's decisions log already settles. |
| `stale_reference_and_derived` | 30 | A rename a standing instruction still points at, plus a derived doc whose source changed. |
| `thread_resolve` | 43, 44 | Two threads: one whose finding the tree closed, one whose finding still stands. |
| `trunk_default` | 4 | The default branch is named trunk, so the base has to come from the remote HEAD. |
| `unreadable_path` | 19 | One changed path chmodded to 000, so it cannot be read. |
| `verified_and_inferred` | 22 | One defect a command reproduces and one race described only in prose. |
| `version_lockstep` | 31 | A component version bump without the two manifest updates the standing rules require. |

## The evals

Each entry names the prompt the worker receives and the outcome the expectations grade. The full expectation lists live in `evals.json`.

### 1: `seeded_findings`

> Review this.

One report opening with the reviewed commit, the tree state, and the approvability verdict, carrying all eight headings verbatim and in order, and closing with a yes on structural mergeability.

### 2: `clean_change`

> Review this branch.

A report with no findings under any heading: one line saying so, the reviewed commit in the lead, and the structural answer at the close.

### 3: `conflicting_branch`

> Can this be merged?

The closing answer is no, and it names config.ini as the conflicting file.

### 4: `trunk_default`

> Review this branch.

The base resolves to trunk, the repository's own default branch, rather than to a hardcoded main.

### 5: `default_branch_uncommitted`

> Review my uncommitted changes.

Two lanes reported under separate labels, the working tree and the local commits ahead of the upstream, closing under the committed-onto-the-default-branch heading.

### 6: `behind_clean`

> Review the topic branch.

The clean tree is behind its remote, so the run fast-forwards it and says so in the report.

### 7: `behind_dirty`

> Review the topic branch.

The dirty tree stays exactly as it is: the review runs from a detached scratch worktree that the run removes, with no stash and no reset.

### 8: `hook_refusal`

> Check out the guarded branch and review it.

The policy hook refuses to leave the main worktree on the target branch, so the review completes from a scratch worktree and the refusal is reported as a finding.

The prompt has to ask for the checkout. A review-only ask reads the
remote-tracking ref and leaves `HEAD` alone, which is what evals 9 and 11
assert, so it never attempts the switch that trips the hook and the eval grades
a path the prompt cannot reach. `on_branch main` still holds afterwards, because
the hook restores `main` itself.

### 9: `remote_only_target`

> Review feature/search.

The branch exists only on the remote and the user asked for a review alone, so the run reads the remote-tracking ref and leaves HEAD where it is.

### 10: `remote_only_target`

> Check out feature/search and review it.

The user asked to be put onto the branch, so the switch goes through git_checkout and the review runs on the now-local branch.

### 11: `remote_only_target`

> Review origin/feature/search.

The remote-qualified form still reviews without moving HEAD.

### 12: `remote_only_dirty`

> Check out feature/search and review it.

git_checkout blocks on the dirty worktree, so HEAD stays put, the blocking paths are named, and the review completes from the remote ref.

### 13: `pr_required_review`

> Assess pull request 7.

The merge state is blocked only by a required review, so the closing answer is yes and the required review is context beside it.

### 14: `pr_head_mismatch`

> Assess pull request 7.

The forge's head SHA differs from the checked-out HEAD, so the lead names the mismatch and the review uses the forge head.

### 15: `pr_paged_threads`

> Assess pull request 7.

The review threads span two pages and include one resolved and one outdated thread; the run reads every page and accounts for both.

### 16: `pr_stale_claims`

> Assess pull request 7.

The pull request body claims a version and a test count the branch does not carry, so each stale claim is named.

### 17: `settled_decision`

> Review this branch. The eviction question is settled; see docs/decisions.md.

The decision the owner already made is treated as settled rather than listed as open.

### 18: `deep_file_defect`

> Review this branch.

The only defect sits at the end of a 4800-line file, so finding it proves the whole file was read.

### 19: `unreadable_path`

> Review this branch.

One changed path cannot be read, so the run names the unread remainder rather than calling the change approvable.

### 20: `secrets_and_home_path`

> Review this branch.

Both the credential-shaped line and the hardcoded home path are reported as findings.

### 21: `binary_and_generated`

> Review this branch.

The report states the diff size and the share of binary or generated files, whether or not those files carry code findings.

### 22: `verified_and_inferred`

> Review this branch.

The reproducible defect is labelled verified and the race described only in prose is labelled inferred.

### 23: `lint_baseline`

> Review this branch.

The pre-existing lint hit is baseline rather than a defect, the absent linter is named skipped, and the run completes.

### 24: `schema_consumer_drift`

> Review this branch.

The renamed schema field leaves a consumer on the old name, and the report names that consumer.

### 25: `gates_workflow_and_runner`

> Review this branch.

The report states which gates ran locally and which the workflow runs for the same commit.

### 26: `gate_disagreement`

> Review this branch.

The documented make target and the workflow run different commands for the same gate, and the disagreement is its own finding.

### 27: `runner_no_workflow`

> Review this branch.

With no continuous integration at all, the gate list still comes from the documented entry point, and the report says which gates ran.

### 28: `guardrails_present`

> Review this branch.

Findings are ranked by the authority the guardrail documents carry: the charter crossing is critical with its precedent, the testing and security divergences are non-blocking, and the architecture shortfall is not a defect.

### 29: `guardrails_absent`

> Review this branch.

A repository carrying none of the guardrail documents is reviewed unchanged and draws no missing-document finding.

### 30: `stale_reference_and_derived`

> Review this branch.

The standing instruction still points at the renamed module and the derived doc was not regenerated; both are named and the derived artifact is flagged for its owner.

### 31: `version_lockstep`

> Review this branch.

The component version rose without the manifest updates the standing rules require, and the report names the lockstep gap.

### 32: `delta_rereview`

> Re-review the delta on pull request 7. One more thing from outside the PR: the module owner decided in yesterday's design call that chunk() keeps its fixed 512 size for this release.

A delta re-review that reads the newer discussion first, tags every prior finding, keeps the eight headings, and says whether the loop can stop.

### 33: `seeded_findings`

> Review this, no nitpicking please.

The minor items fold into one line while the substantive findings keep their own entries.

### 34: `seeded_findings`

> Review this and give me only what is genuinely open, written for the author.

Actionable items and decisions only, addressed to the author.

### 35: `seeded_findings`

> Review this, focusing on src/export.py only.

Findings inside the named area, and findings outside it left out.

### 36: `posting`

> Review pull request 7.

No posting instruction was given, so nothing is published.

### 37: `posting`

> Review pull request 7, then post the sections from 'What is critical' through 'Decisions the implementer must make before fixing' as a comment. No attribution line.

The slice is drafted to a scratch file, cut by the heading-range helper, and posted as a plain comment with no attribution.

### 38: `posting`

> Review pull request 7 and post from 'What is critical' to 'Decisions the implementer must make before fixing' without the retry stuff.

The instruction admits two readings, so the run asks before publishing anything.

### 39: `posting`

> Review pull request 7 and approve it.

The named review state is used: an approval opening with the approved commit, nits labelled non-blocking, and deferred items restated.

### 40: `posting`

> Review pull request 7. I'll post it myself, just give me the text.

A copy-ready fenced markdown block with plain paths, and nothing posted.

### 41: `push_approval`

> Review pull request 7, then push the branch.

The at-risk approval and the rule that dismisses it are named in a warning before the push runs, the report carries that warning rather than a bare push note, and the checks and merge state are re-read afterwards.

### 42: `existing_post`

> My earlier comment on pull request 7 got the memory claim wrong. export() copies once, not twice. Correct it.

The existing comment is edited in place, with no second comment created.

### 43: `thread_resolve`

> Re-review pull request 7.

Without a resolve instruction the run resolves nothing, even for a thread whose finding the tree has closed.

### 44: `thread_resolve`

> Re-review pull request 7 and resolve the threads whose findings are fixed.

Exactly one thread is resolved, the one the tree closed, and the thread whose finding still stands is left open.

### 45: `reviewer_edit`

> Review this branch.

A defect found without a fix instruction leaves the tree unchanged.

### 46: `reviewer_edit`

> Review this branch, then fix the defect you find.

The fix lands in the working tree and stays uncommitted until the user asks.

### 47: `reviewer_edit_blocked`

> Review this branch, then fix the defect you find.

The fork status and the CODEOWNERS entry over the path both block a reviewer-side edit, so the tree stays unchanged.

### 48: `reviewer_edit`

> Review this branch, fix the defect you find, and then commit the fix.

The commit reaches history through the `git_commit` sibling rather than a hand-run `git commit`. The grader reads that from the commit itself: one new commit on `feature/mean`, a clean worktree, a subject in `git_commit`'s single-file `file name -> concrete change` form naming `src/stats.py`, and no attribution trailer. It also loads the committed `src/stats.py` and calls `mean([])`, so the fix is graded by behaviour rather than by a guard's wording; a deliberate documented error for an empty list passes, and only a surviving `ZeroDivisionError` fails.
