---
description: Drop the CODEOWNERS condition from git_review's reviewer-side edit gate, leaving fork status and push permission, since code ownership gates review rather than write access.
scope: plugins/ai_dev/skills
created: 2026-09-06T14:09:28
updated: 2026-09-06T14:09:28
status: open
reported-by: Andreas Hoffmann
---

# Drop the CODEOWNERS condition from git_review's edit gate

## Goal

The reviewer-side edit gate in the `git_review` skill names exactly two
conditions before a reviewer-side fix touches a file: whether the remote is a
fork, and whether the authenticated user can push to it. Both answer whether a
push can land. The third condition, a `CODEOWNERS` entry assigning the changed
path to somebody else, comes out, and no reference to that file remains anywhere
in the skill.

The user-visible outcome: asking `git_review` to fix a defect in a repository
the user can push to no longer refuses the edit because a code-ownership entry
covers the path, and no run spends a three-location file search that answers
"absent" in a repository that carries no such file. A repository that genuinely
reserves paths for their owners states that in its standing rules, which the
skill already reads through `<gather_from_the_repository>`.

## Context

The condition lives in the `git_review` skill body under the
`<reviewer_side_edits>` block, spread across four tags: the paragraph inside
`<check_authority_before_touching_a_file>` that names all three conditions, the
whole `<find_codeowners>` tag holding the three-location search, the
`<read_the_three_conditions_separately>` tag, and a closing clause in
`<decline_out_loud>`. The gate already names the repository's standing
instructions as an evidence source beside the file, and that half stays.

Three findings motivate the removal.

**Code ownership carries no write authority.** Git never reads a `CODEOWNERS`
file. GitHub reads it to auto-request reviews when a pull request opens, and
under a "Require review from Code Owners" branch protection it holds the *merge*
until any one owner approves. Committing, pushing, and branching stay open to
anyone with write access. Source: GitHub documentation, "About code owners",
checked 2026-09-06. The current rule states that each condition "blocks on its
own", so an ownership entry alone refuses an edit the user is entitled to make,
and a repository whose file is a single catch-all owner line refuses every
reviewer-side fix in it.

**The merge-side effect already reaches the report.** The skill's
`<merge_signals>` reads the review decision and the branch rulesets, and an
outstanding code-owner approval surfaces through the review decision without the
file being read. The skill's own `<policy_is_context>` then classes required
approvals and branch-protection policy as context beside the closing verdict
rather than a blocker, which the current gate contradicts by treating the same
policy as a hard refusal.

**Naming the owner at fix time adds little.** Code owners are requested when the
pull request opens, so a reviewer fixing a file already inside the diff pulls in
no owner who was not already asked.

Removing the condition also restores the placement rule the `guardrail` skill
states, that a rule is stated once in its general form. Reading the repository's
standing rules is that general form, and hardcoding one forge configuration file
into an authority gate is a narrow restatement of it.

The task that shipped this skill,
[ai-dev_git-review-skill.md](ai-dev_git-review-skill.md), is the co-edit
candidate here, because its Acceptance carries a reviewer-edit item naming
`CODEOWNERS`. That task is already `implemented`, and its Acceptance is the
record of what shipped rather than a live rule governing future work, so this
task leaves it unchanged and lets this file carry the removal.

## Approach

Rewrite the four affected passages in the `git_review` skill body in place so
that two conditions remain and one canonical statement of the gate survives.
Rewrite the paragraph in `<check_authority_before_touching_a_file>` to establish
fork status and push permission before the first edit, keeping its existing
point that the standing instructions answer this without the forge layer, so an
absent or unreadable `gh` leaves the check owed rather than waived. Delete the
`<find_codeowners>` tag whole. Rewrite
`<read_the_three_conditions_separately>` to the two remaining conditions,
renaming the tag to match its new content and keeping its point that each
condition blocks on its own and a clear answer to one leaves the other open.
Drop the trailing `CODEOWNERS` clause from `<decline_out_loud>` while keeping
the rule that a decline is spoken plainly and names the blocking condition.

Update the `git_review` harness to match. In `evals/evals.json`, rewrite eval
47's `expected_output` and the expectation reading "The response names the
CODEOWNERS entry or the fork status as the reason it did not edit." so it names
the fork status or the repository's standing rule. In `evals/README.md`, rewrite
the `reviewer_edit_blocked` table row and the matching scenario description to
the same wording. In the `reviewer_edit` fixture's setup script, rewrite the
header comment that reads "no CODEOWNERS entry over the changed path" so it
describes a writable, non-fork repository.

The `reviewer_edit_blocked` fixture keeps blocking without any change to what it
asserts, because it already sets `maintainerCanModify` to false on a
cross-repository pull request and plants a standing instruction reserving the
owned paths. Rewrite that planted instruction so it reserves the path on its own
terms rather than by pointing at the `CODEOWNERS` file, and drop the
`.github/CODEOWNERS` heredoc the fixture writes, so the scenario proves the two
surviving conditions rather than the removed one.

**Out of scope:** teaching `git_review` to report code ownership as review-routing
context in its report body, which is a separate behaviour with its own eval and
belongs in its own task if it is ever wanted.

## Acceptance

- A search for `CODEOWNERS` across the `git_review` skill directory, covering
  its `SKILL.md`, `references/`, and `scripts/`, returns no match.
- The skill body carries no `<find_codeowners>` tag, and the reviewer-side edit
  gate names fork status and push permission as its conditions.
- The gate still names the repository's standing instructions as an evidence
  source that answers the check without the forge layer.
- `<decline_out_loud>` still requires a spoken decline naming the blocking
  condition and the party who can make the change.
- The `reviewer_edit_blocked` fixture writes no `.github/CODEOWNERS` file, still
  serves `maintainerCanModify` false on a cross-repository pull request, and
  still plants a standing instruction reserving the changed path.
- Eval 47 passes on a fresh run: the sandbox copy of the changed module is
  byte-identical to its committed state, `git status` reports a clean tree, the
  response names the fork status or the standing rule as the blocking condition,
  and the response still reports the divide-by-zero defect and proposes a fix.
- Evals 45, 46, and 48 pass on the same run, so the unblocked reviewer-edit path
  and its `git_commit` handoff are unchanged by the edit.
- A search for `CODEOWNERS` across the `git_review` harness returns matches only
  where the harness deliberately keeps the term, and every remaining match is
  accounted for in the run report.
