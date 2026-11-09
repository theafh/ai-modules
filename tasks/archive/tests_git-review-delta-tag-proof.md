---
description: Rework the git_review delta_rereview fixture and eval 32 so each prior finding has one evidence home, no tree comment states a tag, and the grader checks the full tag set.
scope: tests/git_review
created: 2026-10-02T08:23:20Z
updated: 2026-10-03T16:19:48Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Make the git_review delta eval prove every re-review tag

## Goal

Eval 32 in the `git_review` harness proves that a delta re-review tags every prior finding from the closed vocabulary the skill's `<re_review>` block names in `<tags>`: closed, open, open and not acknowledged, settled by a decision, regressed, and new. Each prior finding or Delta-eval unit has one unambiguous evidence home in the `delta_rereview` fixture, the tree the run reviews carries no comment that states a tag, and `grade.sh` checks every tag the expectations name. The user-visible outcome: a run that derives each tag from the evidence passes, and a run that copies comments, drops a closed finding, or misreads a regression fails.

## Context

The fixture is `tests/git_review/evals/fixtures/delta_rereview/setup.sh`. Eval 32 lives in `tests/git_review/evals/evals.json`, and its grading is the `32)` case in `tests/git_review/evals/grade.sh`. Three properties of the current fixture let the eval pass or fail for reasons unrelated to tagging:

- The follow-up `src/export.py` states each answer in its own comments, for example `# f1 closed: the handle is closed now.`, `# f2 still open: the author's reply claims this was fixed; it was not.`, `# f6 regressed:`, `# f3 acknowledged and still unfixed:`, `# f4 declined with a reason:`, and the `flush()` docstring line `New in this round:`. A run that copies these comments scores the same as one that checks each claim against the tree, which is the behaviour the skill's `<verify_claimed_fixes>` requires.
- The prior review body in the staged `reviews.json` lists f6 under `## What is critical` as "destination reaches open() without passing paths.sanitize", while the first-round `export()` already calls `open(sanitize(destination), "w")`. That makes "open" as defensible as "regressed" for f6.
- The decision the user relays in the eval prompt settles the chunk size, which is also f3, the acknowledged-but-unfixed finding. The expectations then say both "The chunk-size finding (f3) is tagged open and acknowledged." and that the relayed decision settles f3. "open and acknowledged" sits outside the closed vocabulary, and no expectation or check covers "open and not acknowledged".

An audit on 2026-10-01 sampled eval 32 twice: one run never tagged f1 closed, and the other tagged f6 "open". Every earlier recorded run had passed. A post-fix re-audit on 2026-10-02 still saw f1 covered only as a descriptive "addressing f1" fact under What the changes do and implement, with no `closed` tag under its original heading — the skill's `<descriptive_sections>` pull. The skill's `<tags>` rule now keeps the tag under the original heading even when a descriptive section states the same change; this fixture rewrite remains required so each prior finding or Delta-eval unit has one unambiguous evidence home and the grader can check the full set.

The harness runner is already vendor-aware (`tests/git_review/evals/run.py` via `tests/lib/vendor.py`). Fresh proof runs use `--vendor cursor` per `TESTING.md`.

## Approach

Rewrite the fixture so each unit the Acceptance bullet labeled `Delta eval:` in [ai-dev_git-review-skill.md](ai-dev_git-review-skill.md) enumerates has one unambiguous evidence home (a prior finding, a new helper, or a prose concession), and each tag follows from the evidence alone:

- f1 is fixed in the tree, so it reads closed.
- f2 is claimed fixed in an author reply while the tree still carries it, so it reads open.
- A new prior finding f7 names the no-delimiter join `str(rows[i]) + str(rows[i + 1])` that both rounds still write; the author acknowledges it in a comment, for example "fair, will fix in the next push", and the tree leaves that join unchanged, so it reads open.
- f9 stays routed to the security owner, who never answered, so it reads open and not acknowledged.
- f4 is declined with a stated reason, so the re-review leaves it out.
- f5 is settled by the decisions log, so it reads settled by a decision.
- f3, the chunk size, is settled by the decision the user relays in the eval prompt, so it also reads settled by a decision.
- The prior review records f6 as closed in that round, because the first-round `export()` already routes `destination` through `sanitize()`, and the follow-up drops that call, so f6 reads regressed.
- `flush()` arrives in the follow-up, so it reads new.

Rewrite the follow-up `src/export.py` so the code alone carries each state: delete every comment and docstring line that names a finding id or a tag, keep only the `# TODO: ... sanitize ...` line, and delete the surrounding framing comments that carry the stems `concession` or `acknowledg`. Rewrite the prior review body in the staged `reviews.json` so f6 reads as closed in that round, and add f7 naming that no-delimiter write. Retarget the staged `comments.json` author acknowledgment onto f7 only: carry one acknowledgment of f7 and remove the existing author comment that acknowledges f3 as still unfixed.

Rewrite the eval 32 expectations in `evals.json` to the mapping above: replace the "tagged open and acknowledged" line with the f3 settled-by-a-decision line, add one line for f7 as open, and replace the existing "The security question routed to the owner (f9) stays open…" line with open and not acknowledged for f9. Extend the `32)` case in `grade.sh` so every tag the expectations name has a check. Because `finding_title_matches` keeps only bold titles that match each successive case-insensitive substring pattern, the plain-`open` check requires a title that matches `open` and does not match `not acknowledged`, and the `open and not acknowledged` check is a separate title match on `not acknowledged`. Rewrite the eval 32 entry and the `delta_rereview` fixture row in `tests/git_review/evals/README.md` in place to match.

## Acceptance

- A case-insensitive search of the staged follow-up `src/export.py` for the finding ids `f1` through `f9` and for the stems `closed`, `regressed`, `acknowledg`, `declined`, `concession`, and `New in this round` returns no match.
- The staged follow-up `src/export.py` still contains a `# TODO:` line naming sanitize, and the eval 32 expectations in `evals.json` still carry a line that the TODO about sanitize is separated as a prose concession rather than counted as a fix.
- The staged prior review body records f6 as closed in that round, and the staged first-round `src/export.py` calls `sanitize()`.
- The staged prior review body in `reviews.json` includes f7 naming the no-delimiter join, both the staged first-round and follow-up `src/export.py` still concatenate with `str(rows[i]) + str(rows[i + 1])`, and the staged `comments.json` carries an author acknowledgment of f7 and no author acknowledgment of f3 as still unfixed.
- The eval 32 expectations in `evals.json` name one Approach disposition per mapping unit as Approach lists — a tag, leave-out, or the new `flush()` finding tagged `new` — including f4 left out, and contain no "open and acknowledged" line.
- The eval 32 entry and the `delta_rereview` fixture row in `tests/git_review/evals/README.md` are each rewritten in place so the single remaining description at each site matches the tag mapping Approach lists.
- The `32)` case in `grade.sh` checks the closed, open, regressed, settled, new, and not-acknowledged tags, where the open check passes only on a title that matches `open` and does not match `not acknowledged`. After `bash tests/git_review/evals/stage.sh 32 <target>`, grading that sandbox with `grade.sh 32 <sandbox_repo> <response>` against two hand-authored `response.txt` shapes fails as follows: a response that is otherwise complete but has its `not acknowledged` text removed fails the not-acknowledged check, and a response whose only open-family title carries `open and not acknowledged` fails the plain-open check.
- Eval 32 passes on one fresh `python3 tests/git_review/evals/run.py --vendor cursor 32` run. When that run fails, its `grading.txt` names the missing tag, and the fix lands in the fixture or the skill rather than in a looser check, per `## Test Integrity` in `TESTING.md`. A further `--force` resample runs only when that first run failed and the tree under test changed.
