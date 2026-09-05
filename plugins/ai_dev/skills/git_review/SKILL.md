---
name: git_review
description: "Review the changes the user names and answer two questions kept apart: could they be approved in general, and can they be structurally merged as they are. The target is a pull request by URL or number, a branch by name or already checked out, or the default branch's uncommitted changes and unpushed commits. The report opens with the reviewed commit, tree state, and approvability verdict, works through fixed headings, and closes with a yes or no on structural mergeability. Use when the user asks to review this branch, assess the pull request, give a full assessment, say whether this can be merged, review my uncommitted changes, re-review the delta since last time, or post the review as a comment on the PR. Publishing to the pull request, resolving a review thread, and editing the branch each wait for an explicit request in the current turn. Checkout, commit, and branch cleanup stay with git_checkout, git_commit, and git_refresh, and approving or merging stays with the PR's owners."
version: 1.0.1
author: Andreas F. Hoffmann
license: MIT
---
# git_review

<git_review_skill>
  <objective>Produce one review report for the changes the user pointed at, opening with the reviewed commit and a verdict on approvability in general and closing with a yes or no on structural mergeability, so the user can decide whether the change goes in.</objective>
  <command_intent>resolve the target, pin the reviewed commit, collect the git and forge evidence into a scratch directory, read every changed line, judge each finding against the criteria the repository declares, and report under the fixed headings</command_intent>

  <two_verdicts>
    <approvable_in_general>Judge substance: what the change does, what it breaks, what it leaves undone. This verdict answers whether a reviewer could sign the change off.</approvable_in_general>
    <structurally_mergeable>Judge the branch's own properties: a conflict-free test merge against the base, the ahead and behind counts, and the status of the continuous-integration checks. This verdict answers whether git and the forge would take the merge.</structurally_mergeable>
    <policy_is_context>Report required approvals, review decisions, and other branch-protection policy as context beside the closing answer rather than inside it. The user is producing the very review such a policy waits for, so a missing approval leaves the structural answer untouched.</policy_is_context>
  </two_verdicts>

  <path_resolution>
    Bundled scripts live in `scripts/` next to this `SKILL.md`. Resolve each script's absolute path by combining the directory of this `SKILL.md` with `scripts/<script-name>` and invoke the absolute path. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed. Open `references/manual_fallback.md` only after a script exits non-zero for a missing-file or environment reason after that retry.
  </path_resolution>

  <primary_workflow>
    <resolve_target>
      <accepted_forms>Accept a pull request URL or number, a bare branch name, the remote-qualified `<remote>/<branch>` form, or nothing at all.</accepted_forms>
      <no_argument>With nothing given, review the checked-out branch against the repository's default branch. When the checked-out branch is the default branch itself, review the uncommitted changes, meaning the staged, the unstaged, and the untracked ones, together with the local commits ahead of the upstream, and report those two lanes under separate labels.</no_argument>
      <pull_request>Resolve a pull request to its head and base branches through `<forge_layer>`.</pull_request>
      <branch_the_user_wants_checked_out>Hand the switch to the `git_checkout` sibling when the user names a branch that is not checked out and asks to be put onto it. When that sibling surfaces a dirty-worktree block, leave `HEAD` where it is, name the blocking paths it reported, and finish the review from the remote-tracking ref inside the detached scratch worktree `<pin_commit>` already uses.</branch_the_user_wants_checked_out>
      <branch_for_review_only>Read the branch from its remote-tracking ref and leave `HEAD` where it is when the user asks only for the review.</branch_for_review_only>
      <base_branch>Take the base from the pull request when there is one, and otherwise detect the default branch from the remote `HEAD` the way `git_refresh` does, so no branch name is hardcoded.</base_branch>
    </resolve_target>

    <pin_commit>
      <fetch_first>Fetch the base and head refs before any diff runs. A stale local base inflates the diff and a stale local head reviews the wrong code.</fetch_first>
      <compare_heads>Compare the checked-out `HEAD` with the remote head, and for a pull request with the forge's head commit as well. Read `head_sync.txt` from the collected evidence for the git side of that comparison: its `head_vs_upstream` line reports `in sync`, `behind N`, `ahead N`, or `diverged`, and a pull request adds `headRefOid` from `<forge_layer>`. Name any mismatch in the report lead and review the forge head.</compare_heads>
      <fast_forward_when_clean>Fast-forward `HEAD` and say so when it is behind on a clean tree. A `head_vs_upstream` of `behind N` on a clean worktree is exactly that case, so act on it rather than reviewing the stale local commit.</fast_forward_when_clean>
      <scratch_worktree>Review the remote ref from a detached scratch worktree, and remove that worktree when the run ends, whenever the tree is dirty, the local branch has diverged, or a repository hook refuses the checkout. Run every command that needs files inside that worktree.</scratch_worktree>
      <hook_refusal_is_a_finding>Report a hook that refuses the checkout as a finding and review from the scratch worktree. Leave the hook in force rather than bypassing it.</hook_refusal_is_a_finding>
      <leave_the_tree_alone>Use no stash, reset, or checkout-discard on the user's tree on any path. Reproducing a defect under `<reproduce>` counts here too: run the code from a copy outside the repository, and suppress the byproducts a run leaves behind, such as compiled bytecode, caches, and build output, so the tree the report calls clean actually is. Reach for the interpreter's own switch where there is one, such as `python3 -B` or `PYTHONDONTWRITEBYTECODE=1`, then read `git status --porcelain --untracked-files=all` once the reproduction has run and remove whatever the run itself created.</leave_the_tree_alone>
      <anchor_the_report>Open the report with the reviewed commit and the tree state the run left behind, so a later delta run has its anchor.</anchor_the_report>
    </pin_commit>

    <git_layer>
      <collect>Invoke `scripts/collect_review_evidence.sh` to write the git evidence, and the forge evidence when it is reachable, into a scratch directory of plain files with a `manifest.txt`. Read those files rather than issuing the underlying commands one at a time.</collect>
      <evidence_set>The collected set covers the head against its own upstream in `head_sync.txt`, which is what `<compare_heads>` and `<fast_forward_when_clean>` decide on and is separate from the base comparison; the merge base with the ahead and behind counts; the three-dot diff stat and name-status with rename detection; the commit list with full messages both without merges and along the first parent, so in-branch merges from the base stay visible and the branch's own contribution stays separate from what the base already holds; a removed-hunks view for the retirement heading; the base-side content of deleted files and prior versions through `git show`; a `git merge-tree` test merge naming any conflicting file; a scan for credential patterns and hardcoded home paths; and the diff size with the share of binary and generated files.</evidence_set>
      <claims_against_the_tree>Check the version and manifest lockstep the repository's own rules require, and check the pull request body against the branch for version and test-count claims. Name each stale claim.</claims_against_the_tree>
      <documentation_findings>Two documentation findings carry their own weight. A standing instruction or document that still references a file this change deleted or renamed misdirects every later reader, so report it rather than treating it as merely stale. A derived artifact whose source this change edited goes to the report flagged for regeneration by its owner rather than repaired inside the review.</documentation_findings>
      <lint_baseline>Judge a lint hit against the repository-wide baseline before calling it a defect: a hit the tree already carried outside this diff is baseline, not a finding against this change.</lint_baseline>
    </git_layer>

    <forge_layer>
      <availability>Read the forge layer when `gh` is installed and authenticated and the remote is a GitHub repository. Review from git alone otherwise, and name the forge layer as unavailable in the report lead. A remote on any other host takes the git-only path as a first-class route rather than a degraded one.</availability>
      <discussion>Read the pull request body, the review bodies, the issue comments, and the inline review threads through the paginated review-thread connection, which is the one forge surface carrying each thread's resolved and outdated state. Report each with its count, so "no comments" is proven rather than assumed.</discussion>
      <pagination>Page past the first page of the threads and past the first page of the comments inside each thread.</pagination>
      <keep_resolved_and_outdated>Keep the resolved threads and the outdated threads rather than filtering them away, and account for every thread the connection returned. A thread resolved with no matching change in the tree is exactly what a delta tag reads. A thread goes outdated when the lines it was anchored to moved, which says nothing about whether its finding was addressed, so check an outdated thread against the current tree and report where its finding now stands rather than treating the outdated flag as closure.</keep_resolved_and_outdated>
      <merge_signals>Read the checks, the mergeable state with its reason, the review decision, and the branch rulesets when they are readable.</merge_signals>
    </forge_layer>

    <external_context>Read an external record the user names, such as a chat thread, a wiki page, or a ticket, before the assessment, and treat it as a set of claims to verify. A decision the owner has already made is settled and stays out of the open-decisions heading.</external_context>

    <review_criteria>
      <gather_from_the_repository>Gather the criteria from the repository rather than from a fixed checklist: the standing repo rules, plus the root guardrail documents when the repository carries them. Read each behind a `test -f` presence gate, so a repository carrying none is reviewed unchanged and draws no missing-document finding.</gather_from_the_repository>
      <rank_by_authority>Rank what those documents say by the authority hierarchy the `guardrail` skill defines, so each finding's severity rests on a declared source rather than on the reviewer's taste.</rank_by_authority>
      <charter_is_critical>A change crossing a `CHARTER.md` boundary belongs under the critical heading.</charter_is_critical>
      <testing_and_security>A divergence from `TESTING.md` or `SECURITY.md` is reported for the user to weigh, carrying its non-blocking label.</testing_and_security>
      <architecture_is_descriptive>`ARCHITECTURE.md` and its peers supply descriptive context. Code short of a declared direction is unmet work rather than a defect.</architecture_is_descriptive>
      <cite_and_locate>Cite the governing document by name in every finding resting on one, and locate the nearest precedent in the repository's history beside it. Read the precedent from `precedent/by_guardrail.txt`, which lists the prior commits whose messages cite each guardrail document, and `precedent/by_path.txt`, which lists what touched each changed path before this branch. Name the commit and what it did about the same constraint. Say that no precedent exists where the search returns none, rather than leaving the second half of this rule unanswered.</cite_and_locate>
    </review_criteria>

    <verify_rather_than_read>
      <build_the_gate_list>Build the gate list from two sources and reconcile them: the continuous-integration workflow definition, which names the suites, validators, linters, and commit-message checks that run and the range each covers, and the project's documented local entry points, meaning its task-runner targets and the commands the standing repo rules name. A repository with no continuous integration still yields a gate list from the second source alone.</build_the_gate_list>
      <report_the_disagreement>Report a disagreement between those two sources as its own finding, whether they disagree on a gate or on the command that runs it, since a contributor who runs the documented command passes a check the merge then fails.</report_the_disagreement>
      <run_the_gates>Run those gates the way the repository runs them. State which of them ran locally and which only the forge's check run covered for the same commit. Name a missing hook runtime or absent linter as skipped and continue the run.</run_the_gates>
      <reproduce>
        Reproduce a suspected bug with concrete inputs before reporting it, and label each finding `verified` or `inferred`. The label records what this run did rather than how sure it feels. `verified` belongs to a finding whose failure the run actually produced, with the command and its output standing as the evidence. `inferred` belongs to every finding that rests on reading the code, however plainly the code reads and however firmly a comment or docstring admits the defect. A defect needing concurrency, a clock, a network peer, or a production data shape to show itself lands on `inferred`, and saying so is the accurate report rather than the weaker one.
      </reproduce>
      <treat_claims_as_input>Treat every claim in a pull request body, a commit message, or an author reply as an input to verify against the tree. Count a decision as open only after the discussion and the linked records have been read.</treat_claims_as_input>
    </verify_rather_than_read>

    <scale_the_reading>
      <small_diff>Read a small diff directly.</small_diff>
      <large_diff>For a large diff, read each changed file sequentially in order with the question list in `references/review_questions.md`: read the whole file, sample nothing, and trust no comment or docstring.</large_diff>
      <unread_remainder>Name what was not read instead of calling a change approvable while changed lines remain unread.</unread_remainder>
    </scale_the_reading>

    <report>
      <lead>Open with the reviewed commit, the tree state left behind, and the verdict on approvability in general with the shortest path to yes. Name the forge layer as unavailable here when it is. State the diff size and the share of binary and generated files from `size_profile.txt`, whether or not those files carry findings, so the reader knows how much of the diff was reviewable code.</lead>
      <headings>Use these headings in this order: What the changes do and implement; What it retires; What of the existing workflow changes; What is critical; Bugs it may introduce; What should be fixed though it is not a clear bug; Decisions the implementer must make before fixing; Can it be structurally merged as it is. The structural question is the last section of the report and closes it, so the open decisions come before it even when the structural answer is already settled.</headings>
      <first_review_presence>On a first review, omit a findings section that has no findings, and say in one line when every findings section is empty.</first_review_presence>
      <delta_presence>On a delta re-review, keep all eight headings in that order as tag homes even where a heading holds no remaining finding.</delta_presence>
      <finding_shape>Each finding names its location in a form the destination renders, quotes or reproduces the evidence, states the consequence, proposes the fix, and names who decides. Findings under the critical heading come from `<review_criteria>`; every other finding carries a non-blocking label.</finding_shape>
      <decision_shape>Phrase each decision as a choice between named options with a suggested default.</decision_shape>
      <closing_answer>Answer the closing question yes or no from the test merge, the ahead and behind counts, and the checks. Mention required approvals and other protection policy as context outside that answer.</closing_answer>
      <uncommitted_variant>For the uncommitted-changes target, the closing heading reads `Can they be committed onto the default branch as they are`, judged by the same gates. The verbatim eight headings apply to branch and pull-request runs.</uncommitted_variant>
      <affirmative_voice>State what is true and what the fix is, rather than listing what is absent.</affirmative_voice>
      <the_report_is_the_whole_answer>The report is the answer, whatever later stage the run ends on. A run that goes on to publish, to edit the branch, to push, or to re-read the forge afterwards carries the full report into its answer and lets that stage's own note join it at the end. Answering with the note alone drops the deliverable, and it drops every warning and finding the report was carrying.</the_report_is_the_whole_answer>
      <draft_the_report_to_a_file>Write the finished report to `report.md` inside the evidence directory `<collect>` used, and do it before running any stage that changes something outside this run: publishing to the pull request, resolving a thread, editing the branch, committing, pushing, or the post-push re-read. Answer with that file's content and let the stage's own note follow it. This is what makes the rule above a step rather than something to carry: the report is on disk before the side effect happens, so the answer afterwards reads a file out instead of rebuilding a report from a run that has moved on to its last command.</draft_the_report_to_a_file>
    </report>

    <re_review>
      <trigger>Treat the target as reviewed before when an anchor commit in this conversation or a prior post by the user on the pull request shows a previous review.</trigger>
      <read_the_new_discussion_first>Read every comment and review body newer than the reviewer's last post before assessing anything, then fetch the new commits and review the delta under the same headings.</read_the_new_discussion_first>
      <tags>Tag each prior finding as closed, open, open and not acknowledged, settled by a decision, regressed, or new.</tags>
      <verify_claimed_fixes>Verify each claimed fix against the tree rather than against the reply that claims it.</verify_claimed_fixes>
      <separate_the_classes>Separate code changes from prose concessions, and the author's defects from the reviewer's own scope calls.</separate_the_classes>
      <dispositions>Leave out an item the author declined or deferred with a stated reason. Keep an item routed to someone but unanswered open. Fold in a decision the user relays from outside the pull request.</dispositions>
      <can_the_loop_stop>Say plainly whether the review loop can stop.</can_the_loop_stop>
    </re_review>

    <scope_modifiers>
      <focus_area>Report findings inside the area the user named and leave the ones outside it out.</focus_area>
      <no_nitpicking>Fold minor items into one line.</no_nitpicking>
      <only_what_is_open>Emit actionable items and decisions only, written from the reviewer toward the author.</only_what_is_open>
      <evidence_unchanged>Each modifier reshapes the report and leaves the evidence gathered by the earlier stages exactly as it is.</evidence_unchanged>
    </scope_modifiers>
  </primary_workflow>

  <publishing>
    <explicit_request_only>Publish to the pull request, and resolve a review thread, only when the user asks in the current turn.</explicit_request_only>

    <resolve_the_instruction_before_publishing>
      Run this gate after `<explicit_request_only>` is satisfied and before any other publishing step. An explicit ask to post settles *whether* to publish; it does not settle *what*. Restate the posting instruction as the exact set of headings and the exact edits to their content, and check that restatement against the sentence the user wrote.
      <two_instructions_in_one_sentence>A posting instruction that carries a scope clause and a content clause is two instructions, and the second does not narrow the first on its own. "Post from A to B without the retry stuff" can mean the A-to-B range with the retry item removed, or a narrower range that stops short of it. Reaching for either reading silently is the failure this gate exists to prevent.</two_instructions_in_one_sentence>
      <ask_and_wait>Ask which reading is meant, name both readings in the question, and publish nothing until the user answers. A run that publishes on the reading it preferred has taken the user's decision, and a post is visible to the author the moment it lands.</ask_and_wait>
      <proceed_when_single>Proceed without asking when the instruction admits one reading. This gate covers genuine ambiguity, not every posting request.</proceed_when_single>
    </resolve_the_instruction_before_publishing>

    <draft_first>Publish from the `report.md` draft that `<draft_the_report_to_a_file>` already wrote, so the chat report and the post share that one source.</draft_first>
    <slice_by_heading>Extract a requested slice with `scripts/extract_heading_range.sh`, inclusive of both named headings, so the headings in the chat report and in the post stay identical and a range resolves exactly.</slice_by_heading>
    <wording_constraints>Apply the wording constraints the user gave: state what is true and the fix, write in the reviewer's voice toward the author, include an attribution line only when asked, and convert file links to plain paths or to permalinks pinned to the reviewed commit.</wording_constraints>
    <slice_preamble>Prefix a slice with one line naming the reviewed commit, and disclose any text added beyond the slice.</slice_preamble>
    <default_post_shape>Post as a plain pull request comment under the authenticated `gh` user by default, because a comment stays editable. Use one of the formal review states, meaning comment, request changes, or approve, only when the user names it. An approval opens with the approved commit, labels the nits non-blocking, and restates the deferred items.</default_post_shape>
    <verify_the_post>Verify the post through the API and report its URL.</verify_the_post>
    <corrections_in_place>
      Edit the existing post in place on a correction rather than adding a second one, and correct an earlier wrong statement publicly in the same place it was made.
      <match_the_id_to_the_route>Editing a comment has three routes, and each takes its own identifier. `gh pr comment --edit-last` needs none. The GraphQL `updateIssueComment` mutation takes the node id, which `gh pr view --json comments` returns in each comment's `id` field with an `IC_` prefix. The REST route, `gh api repos/{owner}/{repo}/issues/comments/<id> --method PATCH`, takes the numeric id, which the same comment's `url` carries in its `#issuecomment-<n>` fragment. Read the id that belongs to the route you take, because the forge answers a node id in the REST path with a 404.</match_the_id_to_the_route>
    </corrections_in_place>
    <resolve_threads>Resolve a review thread only when the user asks and the re-review confirmed that thread's finding closed in the tree. Leave open every thread whose finding still stands.</resolve_threads>
    <copy_ready_block>Offer a copy-ready fenced markdown block with plain paths when the user prefers to post by hand.</copy_ready_block>
    <push_warning>Warn when a push to the branch will dismiss an existing approval, and emit that warning before the push runs. Name the approval at risk, its reviewer, and the rule that dismisses it, and carry the warning in the report per `<the_report_is_the_whole_answer>` rather than only in the reasoning that produced it.</push_warning>
    <address_the_human>Frame a hypothesis about the author's environment as a check for them to run, and address the author rather than instructing another party's agent.</address_the_human>
  </publishing>

  <reviewer_side_edits>
    <gate>Fix a flagged defect on the branch only when the user asks in the current turn, and after checking write permission, code ownership, and fork status. The ask and the authority are two separate conditions, and the ask is the one already satisfied whenever this gate runs, so it never carries the decision on its own.</gate>
    <check_authority_before_touching_a_file>
      Establish all three before the first edit, not after it: whether the remote is a fork, whether the authenticated user can push to it, and whether a `CODEOWNERS` entry assigns the changed path to somebody else. The standing instructions and `CODEOWNERS` in the tree answer this without the forge layer, so an unreadable or absent `gh` leaves the check owed rather than waived.
      <find_codeowners>Look in every place the file lives before reporting it absent. GitHub honours `CODEOWNERS` at the repository root, under `.github/`, and under `docs/`, so read all three and search the tree for the name beside them. `.github/CODEOWNERS` is the common choice, so a check of the root alone reports "no CODEOWNERS file" over a repository that has one and hands the edit an authority it was never granted.</find_codeowners>
      <read_the_three_conditions_separately>Each condition blocks on its own, and a clear answer to one leaves the others open. A note that the user pushes to their own fork grants access to that fork and says nothing about the paths `CODEOWNERS` assigns, and `maintainerCanModify` reading false on a cross-repository pull request bars the edit whoever owns the fork. Answer all three and let any one of them decline the edit.</read_the_three_conditions_separately>
    </check_authority_before_touching_a_file>
    <decline_out_loud>Leave the tree untouched when any of the three blocks the edit, and say plainly that the edit was declined, which condition blocked it, and who can make the change. Report the defect and propose the fix as normal. Naming a fork or a `CODEOWNERS` file elsewhere in the report is not this statement.</decline_out_loud>
    <leave_uncommitted>Leave the tree uncommitted until the user asks to commit, and make that commit through the `git_commit` sibling. Say in the report that the change is sitting uncommitted, and name the files it touched, so the user reads what the tree is holding and what committing it would take in.</leave_uncommitted>
    <push_on_instruction>Push only when told, and warn before the push runs when it will dismiss an existing approval, per `<push_warning>`.</push_on_instruction>
    <re_read_after_a_push>
      Read the checks, the mergeable state, and the review decision again once the push has landed, and report those post-push values as what they are. A push can reset all three, so the values read before it describe a commit the branch has left behind.
      <report_what_the_re_read_returned>State the check states, the merge state, and the review decision as they read after the push, so the report carries the outcome rather than the expectation. A run that names what the ruleset implies without issuing the read has predicted the state instead of observing it, and the prediction is what a stale check would have contradicted.</report_what_the_re_read_returned>
      <the_note_joins_the_report>This re-read is the last step a push run takes, and its values are a closing note on the report rather than a replacement for it. Read the `report.md` draft back out and put this note after it, per `<draft_the_report_to_a_file>`.</the_note_joins_the_report>
    </re_read_after_a_push>
  </reviewer_side_edits>

  <boundary>
    <checkout_belongs_to_git_checkout>Putting the repository onto a branch belongs to `git_checkout`, which this skill invokes.</checkout_belongs_to_git_checkout>
    <commits_belong_to_git_commit>Creating commits belongs to `git_commit`. This skill commits nothing itself.</commits_belong_to_git_commit>
    <merge_belongs_to_the_author>Merging the pull request stays the author's step.</merge_belongs_to_the_author>
    <review_state_needs_an_ask>Approving the pull request or requesting changes waits for an ask that names that state.</review_state_needs_an_ask>
    <github_only_forge>The forge layer covers GitHub through `gh`. Every other remote takes the git-only path.</github_only_forge>
    <cleanup_belongs_to_git_refresh>Pruning and deleting branches after the merge belongs to `git_refresh`.</cleanup_belongs_to_git_refresh>
  </boundary>

  <fallback_on_script_failure>
    <reference>Open `references/manual_fallback.md` after a bundled script fails for a missing-file or environment reason and one re-resolved retry also fails.</reference>
    <return>Recover only the failed step manually, then return to the primary workflow for the remaining stages.</return>
  </fallback_on_script_failure>

  <output_contract>
    <the_report_is_the_deliverable>Produce one review report. The `<report>` stage owns its shape end to end: the lead, the heading set and order, which sections a first review omits and a delta keeps, the finding and decision shapes, the labels, the closing answer, and the uncommitted-changes variant.</the_report_is_the_deliverable>
    <template>Fill `references/report_template.md`, which carries the heading skeleton and one worked example of each shape `<report>` specifies.</template>
    <one_home_per_rule>Every rule above is stated once, in the stage that applies it. This block points at those stages rather than restating them, because a second copy of a rule drifts from the first and a report then conforms to whichever copy was read.</one_home_per_rule>
  </output_contract>
</git_review_skill>
