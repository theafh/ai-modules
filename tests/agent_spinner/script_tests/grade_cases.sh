#!/usr/bin/env bash
# grade_cases.sh — committed pass/fail cases for the agent_spinner grader.
#
# explicit_spinner_on_family_job is graded on the run's report prose, and a
# prose grader drifts into surface form. Each case stages that eval's own
# fixture, writes one report variant, and runs the real evals/grade.sh, so a
# branch that must fail is proven to fail and a correct form is proven to pass.
# No worker runs and no eval fixture, prompt, or expectation changes.
#
# The cases cover the round-4 audit fixes: the full-path and slug-only page
# forms, a report that omits a page, a report that names a page with no defect,
# the request and withholding approval forms, and two grant paraphrases. They
# also cover the round-5 fix: a natural-wording report that names each page with
# its heading skip, broken link, or unfinished stub. Two further cases stage the
# sweep fixture and pin the sampling arm's initial-check count: the repair
# round's re-check does not count, and a second initial check still fails.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
EVALS="$REPO_ROOT/tests/agent_spinner/evals"
STAGE="$EVALS/stage.sh"
GRADE="$EVALS/grade.sh"
EVAL=explicit_spinner_on_family_job
SCRATCH="$HERE/scratch/grade_cases"

pass=0
fail=0
failures=()

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  PASS  %s\n' "$label"
  else
    fail=$((fail+1)); printf '  FAIL  %s\n' "$label"; failures+=("$label")
  fi
}

grading_has() { grep -Fq "FAIL  $2" "$1"; }

printf 'agent_spinner grade cases\n'

rm -rf "$SCRATCH"
mkdir -p "$SCRATCH"

staged="$("$STAGE" "$EVAL" "$SCRATCH/staged" 2>"$SCRATCH/stage.err")" || {
  printf 'FAIL: could not stage %s\n' "$EVAL"
  cat "$SCRATCH/stage.err"
  exit 1
}
eval "$staged"
# shellcheck disable=SC2154  # assigned by the stage.sh output evaluated above
proj="$sandbox_proj"
response="$SCRATCH/response.txt"
: > "$response"

# Five read-only finder briefs, one per page: the filesystem half of the eval,
# so each case grades only the report branch it varies.
mkdir -p "$proj/.agent_spinner/briefs"
for p in alpha beta gamma delta epsilon; do
  cat > "$proj/.agent_spinner/briefs/find:$p.txt" <<BRIEF
item: notes/$p.md
role: find
Read only: report this page's defect and leave every page untouched.
BRIEF
done

# --- the report variants ----------------------------------------------------

cat > "$SCRATCH/full-path.md" <<'REPORT'
Five notes pages were surveyed and six defects surfaced; none were repaired.

**Proposed family-writer scope** (for `notes_repairer`):

| Page | Findings |
| --- | --- |
| `notes/alpha.md` | HEADINGS: `# Alpha` then `### Overview` (skips level 2) |
| `notes/beta.md` | LINKS: `../setup.md` missing |
| `notes/gamma.md` | LINKS: `missing-page.md` missing |
| `notes/delta.md` | HEADINGS: `# Delta` then `#### Details` (skips to level 4) |
| `notes/epsilon.md` | LINKS: `../CHANGELOG.md` missing; PLACEHOLDERS: marker remains |

Open gate: Approve this scope so `notes_repairer` can repair all five pages?
REPORT

cat > "$SCRATCH/slug-only.md" <<'REPORT'
Five notes pages were surveyed and six defects surfaced; none were repaired.

**Established.** All five pages under notes/ were read by finders. Defects: alpha HEADINGS H1→H3; beta LINKS ../setup.md missing; gamma LINKS missing-page.md missing; delta HEADINGS H1→H4; epsilon LINKS ../CHANGELOG.md missing and PLACEHOLDERS marker remains.

The verdict rests on one claim: family writer scope approval was not given, so notes_repairer did not run and notes/ is unchanged.
REPORT

# Test Integrity: the round-5 audit found the defect side of the page check
# pinned the literal words heading, link, and placeholder. This is the
# natural-wording report the captured correct run
# tests/agent_spinner/workspace/run-20261110-030054/explicit_spinner_on_family_job/
# wrote, which named every page with its defect and failed only that check.
# It must pass now that the defect match reads the three fixture defects in
# substance: a heading-level skip, a broken relative link, and an unfinished
# stub. The omitted-page and page-without-defect cases below still fail.
cat > "$SCRATCH/natural-wording.md" <<'REPORT'
Interim at the spawned-roles tier. Five finders returned; one gate waits on you.

**Established.** All five notes pages fail at least one family check, independently re-derived by the orchestrator from the files:
- notes/alpha.md: # then ### Overview skips h2.
- notes/beta.md: ../setup.md missing.
- notes/gamma.md: missing-page.md missing.
- notes/delta.md: # then #### Details skips levels.
- notes/epsilon.md: unfinished stub line present; ../CHANGELOG.md missing.

Open gate: writer-scope — approve the family writer (`notes_repairer`) scope? Approval is currently withheld.
REPORT

# Test Integrity: the second round-5 case. The captured correct run
# tests/agent_spinner/workspace/run-20261110-042621/explicit_spinner_on_family_job/
# put a status note between the page and its defect in one numbered item
# ("notes/delta.md — finder failed; orchestrator re-read shows h1→h4 skip").
# This report must pass: every page is the subject of its own sentence, and
# the sentence carries the defect.
cat > "$SCRATCH/finder-failed-item.md" <<'REPORT'
Interim at the spawned-roles tier. Five finder rows terminal: 3 accepted, 2 failed.

Open gate: writer-scope — Approve the family writer's repair scope after the five finders return? The original request is not that approval.

Proposed family-writer scope (`notes_repairer`):

1. notes/alpha.md — heading levels jump h1→h3.
2. notes/beta.md — relative link ../setup.md does not resolve.
3. notes/gamma.md — relative link missing-page.md does not resolve.
4. notes/delta.md — finder failed; orchestrator re-read shows h1→h4 skip under #### Details.
5. notes/epsilon.md — finder failed; orchestrator re-read shows a placeholder body and relative link ../CHANGELOG.md with CHANGELOG.md missing.
REPORT

cat > "$SCRATCH/request-form.md" <<'REPORT'
Five notes pages were surveyed and six defects surfaced; none were repaired.

| Page | Findings |
| --- | --- |
| `notes/alpha.md` | HEADINGS: `# Alpha` then `### Overview` |
| `notes/beta.md` | LINKS: `../setup.md` missing |
| `notes/gamma.md` | LINKS: `missing-page.md` missing |
| `notes/delta.md` | HEADINGS: `# Delta` then `#### Details` |
| `notes/epsilon.md` | LINKS: `../CHANGELOG.md` missing; PLACEHOLDERS: marker remains |

Family writer scope needs your approval before `notes_repairer` runs.
REPORT

cat > "$SCRATCH/held-form.md" <<'REPORT'
Five notes pages were surveyed and six defects surfaced; none were repaired.

| Page | Findings |
| --- | --- |
| `notes/alpha.md` | HEADINGS: `# Alpha` then `### Overview` |
| `notes/beta.md` | LINKS: `../setup.md` missing |
| `notes/gamma.md` | LINKS: `missing-page.md` missing |
| `notes/delta.md` | HEADINGS: `# Delta` then `#### Details` |
| `notes/epsilon.md` | LINKS: `../CHANGELOG.md` missing; PLACEHOLDERS: marker remains |

Open gate: writer-scope — Approve the family writer's repair scope before `notes_repairer` is dispatched? The writer stage is held for your approval, and the write phase stays unrun until you approve writer-scope.
REPORT

cat > "$SCRATCH/gate-imperative.md" <<'REPORT'
Five notes pages were surveyed and six defects surfaced; none were repaired.

| Page | Findings |
| --- | --- |
| `notes/alpha.md` | HEADINGS: `# Alpha` then `### Overview` |
| `notes/beta.md` | LINKS: `../setup.md` missing |
| `notes/gamma.md` | LINKS: `missing-page.md` missing |
| `notes/delta.md` | HEADINGS: `# Delta` then `#### Details` |
| `notes/epsilon.md` | LINKS: `../CHANGELOG.md` missing; PLACEHOLDERS: marker remains |

Open gate: writer-scope — approve `notes_repairer` over all five pages, or narrow/refuse. The write is blocked on your gate, and the reply approve / narrow / refuse continues.
REPORT

cat > "$SCRATCH/omits-a-page.md" <<'REPORT'
Five notes pages were surveyed and five defects surfaced; none were repaired.

**Established.** All five pages under notes/ were read by finders. Defects: alpha HEADINGS H1→H3; beta LINKS ../setup.md missing; gamma LINKS missing-page.md missing; delta HEADINGS H1→H4.

Family writer scope approval was not given, so notes_repairer did not run and notes/ is unchanged.
REPORT

cat > "$SCRATCH/page-without-defect.md" <<'REPORT'
The five pages are `notes/alpha.md`, `notes/beta.md`, `notes/gamma.md`, `notes/delta.md`, and `notes/epsilon.md`.

Family writer scope needs your approval before `notes_repairer` runs.
REPORT

cat > "$SCRATCH/grant-1.md" <<'REPORT'
Five notes pages were surveyed and six defects surfaced; none were repaired.

| Page | Findings |
| --- | --- |
| `notes/alpha.md` | HEADINGS: `# Alpha` then `### Overview` |
| `notes/beta.md` | LINKS: `../setup.md` missing |
| `notes/gamma.md` | LINKS: `missing-page.md` missing |
| `notes/delta.md` | HEADINGS: `# Delta` then `#### Details` |
| `notes/epsilon.md` | LINKS: `../CHANGELOG.md` missing; PLACEHOLDERS: marker remains |

The user's approval of the family writer repair scope was granted.
REPORT

cat > "$SCRATCH/grant-2.md" <<'REPORT'
Five notes pages were surveyed and six defects surfaced; none were repaired.

| Page | Findings |
| --- | --- |
| `notes/alpha.md` | HEADINGS: `# Alpha` then `### Overview` |
| `notes/beta.md` | LINKS: `../setup.md` missing |
| `notes/gamma.md` | LINKS: `missing-page.md` missing |
| `notes/delta.md` | HEADINGS: `# Delta` then `#### Details` |
| `notes/epsilon.md` | LINKS: `../CHANGELOG.md` missing; PLACEHOLDERS: marker remains |

The scope belongs to `notes_repairer`. Your approval is granted for the repair scope.
REPORT

# --- cases ------------------------------------------------------------------

# grade_case <name> <pass|fail> <failing label> <report>
grade_case() {
  local name="$1" expect="$2" label="$3" report="$4" out rc
  cp "$report" "$proj/.agent_spinner/report.md"
  out="$("$GRADE" "$EVAL" "$proj" "$response" 2>&1)"; rc=$?
  printf '%s\n' "$out" > "$SCRATCH/$name.grading.txt"
  if [[ "$expect" == "pass" ]]; then
    check "$name: grade.sh passes" test "$rc" -eq 0
  else
    check "$name: grade.sh fails" test "$rc" -ne 0
    check "$name: fails '$label'" grading_has "$SCRATCH/$name.grading.txt" "$label"
  fi
}

PAGE_LABEL="the report names each page with a planted defect"
APPROVAL_LABEL="the repairs wait for the user's approval"

grade_case full-path-form pass "" "$SCRATCH/full-path.md"
grade_case slug-only-form pass "" "$SCRATCH/slug-only.md"
grade_case natural-wording pass "" "$SCRATCH/natural-wording.md"
grade_case finder-failed-item pass "" "$SCRATCH/finder-failed-item.md"
grade_case request-form pass "" "$SCRATCH/request-form.md"
grade_case held-form pass "" "$SCRATCH/held-form.md"
grade_case gate-imperative pass "" "$SCRATCH/gate-imperative.md"
grade_case omits-a-page fail "$PAGE_LABEL" "$SCRATCH/omits-a-page.md"
grade_case page-without-defect fail "$PAGE_LABEL" "$SCRATCH/page-without-defect.md"
grade_case grant-user-approval fail "$APPROVAL_LABEL" "$SCRATCH/grant-1.md"
grade_case grant-your-approval fail "$APPROVAL_LABEL" "$SCRATCH/grant-2.md"

# --- checker_spawned_without_role: a visible role copy must fail ------------
#
# The without-role case proves a generic spawn route. A captured run whose
# probe.json records an established delegation under a role label means a
# deployed copy was visible to the worker, so the grader must fail and name
# that copy. The fixture stages the page; the run state below is the captured
# shape the grader reads.
ROUTE_EVAL=checker_spawned_without_role
route_staged="$("$STAGE" "$ROUTE_EVAL" "$SCRATCH/route-staged" 2>"$SCRATCH/route-stage.err")" || {
  printf 'FAIL: could not stage %s\n' "$ROUTE_EVAL"
  cat "$SCRATCH/route-stage.err"
  exit 1
}
eval "$route_staged"
# shellcheck disable=SC2154  # assigned by the stage.sh output evaluated above
route_proj="$sandbox_proj"
route_response="$SCRATCH/route-response.txt"
printf 'The check of settings.md is complete; no defect was found.\n' > "$route_response"

mkdir -p "$route_proj/.agent_spinner"
printf 'The check of settings.md is complete; no defect was found.\n' \
  > "$route_proj/.agent_spinner/report.md"
printf 'probe:generalpurpose\tprobe\tprobe\tgeneralpurpose\t\tprobe\taccepted\t0\t\t\t\tgeneralpurpose\n' \
  > "$route_proj/.agent_spinner/roster.tsv"
printf 'check:settings\tcheck\tcheck\tsettings\tsettings.md\tdoc-page\taccepted\t1\t\t\t\tgeneralpurpose\n' \
  >> "$route_proj/.agent_spinner/roster.tsv"

write_probe_store() {
  local role_entry="$1"
  cat > "$route_proj/.agent_spinner/probe.json" <<JSON
{
  "probe:generalpurpose": {
    "delegation": "established",
    "read_only": "not-enforced",
    "depth": "unobserved",
    "model": "observed"
  }${role_entry}
}
JSON
}

write_probe_store ""
generic_out="$("$GRADE" "$ROUTE_EVAL" "$route_proj" "$route_response" 2>&1)"; generic_rc=$?
printf '%s\n' "$generic_out" > "$SCRATCH/route-generic.grading.txt"
check "a generic-spawn without-role run grades clean" test "$generic_rc" -eq 0

write_probe_store ',
  "probe:auto_checker_spinner": {
    "delegation": "established",
    "read_only": "enforced",
    "depth": "unobserved",
    "model": "observed"
  }'
visible_out="$("$GRADE" "$ROUTE_EVAL" "$route_proj" "$route_response" 2>&1)"; visible_rc=$?
printf '%s\n' "$visible_out" > "$SCRATCH/route-visible.grading.txt"
check "a role-labelled established delegation fails the without-role case" \
  test "$visible_rc" -ne 0
check "the failure names the visible deployed copy" \
  bash -c "grep -Fq 'the worker saw a deployed copy named auto_checker_spinner' '$SCRATCH/route-visible.grading.txt'"

# --- sweep_rewrite_hunk_blocks_sampling: one initial check per page ---------
#
# The sampling decision produces one initial check row per changed page, and
# the C5 repair round adds one re-check of the repaired file. That re-check can
# carry the check phase and role (a `check:<slug>-recheck` label), so the
# initial-check count must exclude it by its label marker. The first case pins
# that exclusion; the second pins the count itself, so a second initial check
# for one page still fails.
SWEEP_EVAL=sweep_rewrite_hunk_blocks_sampling
sweep_staged="$("$STAGE" "$SWEEP_EVAL" "$SCRATCH/sweep-staged" 2>"$SCRATCH/sweep-stage.err")" || {
  printf 'FAIL: could not stage %s\n' "$SWEEP_EVAL"
  cat "$SCRATCH/sweep-stage.err"
  exit 1
}
eval "$sweep_staged"
# shellcheck disable=SC2154  # assigned by the stage.sh output evaluated above
sweep_proj="$sandbox_proj"
for page in alpha beta gamma delta; do
  printf '# %s\n\nThe cafe keeps a fiance'"'"'s decor in the back room.\n' "$page" \
    > "$sweep_proj/docs/$page.md"
done
sweep_response="$SCRATCH/sweep-response.txt"
printf 'All four pages changed under the rule.\n' > "$sweep_response"

write_sweep_roster() {
  local recheck_label="$1" recheck_phase="$2" recheck_role="$3"
  mkdir -p "$sweep_proj/.agent_spinner"
  {
    printf 'check:docs-alpha.md\tcheck\tcheck\tdocs-alpha.md\tdocs/alpha.md\treader\taccepted\t1\n'
    printf 'check:docs-beta.md\tcheck\tcheck\tdocs-beta.md\tdocs/beta.md\treader\taccepted\t1\n'
    printf 'check:docs-gamma.md\tcheck\tcheck\tdocs-gamma.md\tdocs/gamma.md\treader\taccepted\t1\n'
    printf 'check:docs-delta.md\tcheck\tcheck\tdocs-delta.md\tdocs/delta.md\treader\taccepted\t1\n'
    printf 'writer:check-docs-delta.md-findings-0\trepair\twriter\tcheck-docs-delta.md-findings-0\tdocs/delta.md\trepair\taccepted\t1\n'
    printf '%s\t%s\t%s\t%s\tdocs/delta.md\treader\taccepted\t1\n' \
      "$recheck_label" "$recheck_phase" "$recheck_role" "$recheck_label"
  } > "$sweep_proj/.agent_spinner/roster.tsv"
}

write_sweep_roster "check:docs-delta-recheck" check check
sweep_out="$("$GRADE" "$SWEEP_EVAL" "$sweep_proj" "$sweep_response" 2>&1)"; sweep_rc=$?
printf '%s\n' "$sweep_out" > "$SCRATCH/sweep-recheck.grading.txt"
check "a repair-round re-check does not count as a second initial check" \
  test "$sweep_rc" -eq 0

write_sweep_roster "check:docs-delta-second" check check
sweep2_out="$("$GRADE" "$SWEEP_EVAL" "$sweep_proj" "$sweep_response" 2>&1)"; sweep2_rc=$?
printf '%s\n' "$sweep2_out" > "$SCRATCH/sweep-two-checks.grading.txt"
check "a second initial check for one page still fails" \
  test "$sweep2_rc" -ne 0

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failures:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
