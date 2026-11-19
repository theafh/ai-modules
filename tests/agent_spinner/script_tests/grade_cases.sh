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
# its heading skip, broken link, or unfinished stub.
#
# The cases below them pin the vacuous-grader repair: every check that used to
# pass on a no-op or on a run breaking its own rule now has a case that makes
# it fail beside a case that makes a compliant run pass. They stage each eval's
# own fixture, drive the real ledger where the state has to come from the run,
# and assert the named check's PASS or FAIL line rather than only the overall
# exit status, so a case names the property it pins.
#
# The last three cases are the broadening evidence for the stop-report checks
# that used to require the literal word `unknown`: each stages its eval's
# fixture, writes a report that lists the fixture's never-dispatched rows under
# "not dispatched:", and asserts the widened check passes that form.

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
grading_pass() { grep -Fq "PASS  $2" "$1"; }

# The ledger every case that stages a run state drives.
LEDGER_PY="$REPO_ROOT/plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py"
run_case_ledger() {
  local proj="$1"
  shift
  ( cd "$proj" && python3 -B "$LEDGER_PY" "$@" )
}

# stage_case <eval_id> <dir> — stage that eval's own fixture and set CASE_PROJ.
CASE_PROJ=""
stage_case() {
  local eval_id="$1" dir="$2" out
  out="$("$STAGE" "$eval_id" "$dir" 2>"$dir.stage.err")" || {
    printf 'FAIL: could not stage %s\n' "$eval_id"
    cat "$dir.stage.err"
    exit 1
  }
  eval "$out"
  # shellcheck disable=SC2154  # sandbox_proj is set by the eval above
  CASE_PROJ="$sandbox_proj"
}

# run_grade <name> <eval_id> <proj> <response> — grade, keep the output, print
# the exit status.
run_grade() {
  local name="$1" eval_id="$2" proj="$3" response="$4" rc
  "$GRADE" "$eval_id" "$proj" "$response" > "$SCRATCH/$name.grading.txt" 2>&1
  rc=$?
  printf '%s' "$rc"
}

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

# --- sweep evals: an accepted check row, not just any row -------------------
#
# `diff --add-checks` creates a check row unprompted and `accept --classify`
# closes it without a checker, so a row's presence and state certify nothing.
# Each staged check row gains its brief, its return, and the ledger's accept
# record; a row closed by a sampled-out classification fails, and so does a
# page left unchanged. The repair round's re-check still does not count as a
# second initial check.

# write_check_row <proj> <label> <page> — the row's brief, return, and accept
# record, so it stands as a check the run actually made.
write_check_row() {
  local proj="$1" label="$2" page="$3"
  mkdir -p "$proj/.agent_spinner/briefs" "$proj/.agent_spinner/returns"
  printf 'item: %s\nrole: check\n' "$page" > "$proj/.agent_spinner/briefs/$label.txt"
  printf 'checked %s\n' "$page" > "$proj/.agent_spinner/returns/$label.md"
  printf '{"type": "accept", "label": "%s", "state": "accepted", "source": "file"}\n' "$label" \
    >> "$proj/.agent_spinner/ledger.jsonl"
}

# write_sweep_state <proj> <recheck-label> <recheck-phase> <recheck-role> — one
# accepted initial check row per page, plus the repair row and the re-check row.
write_sweep_state() {
  local proj="$1" recheck_label="$2" recheck_phase="$3" recheck_role="$4" page
  mkdir -p "$proj/.agent_spinner"
  : > "$proj/.agent_spinner/ledger.jsonl"
  {
    for page in alpha beta gamma delta; do
      printf 'check:docs-%s.md\tcheck\tcheck\tdocs-%s.md\tdocs/%s.md\treader\taccepted\t1\n' \
        "$page" "$page" "$page"
    done
    printf 'writer:check-docs-delta.md-findings-0\trepair\twriter\tcheck-docs-delta.md-findings-0\tdocs/delta.md\trepair\taccepted\t1\n'
    printf '%s\t%s\t%s\t%s\tdocs/delta.md\treader\taccepted\t1\n' \
      "$recheck_label" "$recheck_phase" "$recheck_role" "$recheck_label"
  } > "$proj/.agent_spinner/roster.tsv"
  for page in alpha beta gamma delta; do
    write_check_row "$proj" "check:docs-$page.md" "docs/$page.md"
  done
}

# classify_sampled_out <proj> <label> — close that row the way a run that took
# the sampled set itself does: a classification record instead of an accept.
classify_sampled_out() {
  python3 - "$1/.agent_spinner/ledger.jsonl" "$2" <<'PY'
import json, sys
path, label = sys.argv[1:3]
records = []
for line in open(path, encoding="utf-8", errors="replace"):
    try:
        rec = json.loads(line)
    except ValueError:
        continue
    if rec.get("type") == "accept" and rec.get("label") == label:
        continue
    records.append(rec)
records.append({"type": "classification", "label": label,
                "text": "sampled out; per-file gates cover it"})
with open(path, "w", encoding="utf-8") as handle:
    for rec in records:
        handle.write(json.dumps(rec) + "\n")
PY
}

SWEEP_EVAL=sweep_rewrite_hunk_blocks_sampling
stage_case "$SWEEP_EVAL" "$SCRATCH/sweep-staged"
# shellcheck disable=SC2154  # assigned by stage_case
sweep_proj="$CASE_PROJ"
for page in alpha beta gamma delta; do
  printf '# %s\n\nThe cafe keeps a fiance'"'"'s decor in the back room.\n' "$page" \
    > "$sweep_proj/docs/$page.md"
done
sweep_response="$SCRATCH/sweep-response.txt"
printf 'All four pages changed under the rule.\n' > "$sweep_response"

write_sweep_state "$sweep_proj" "check:docs-delta-recheck" check check
sweep_rc="$(run_grade sweep-recheck "$SWEEP_EVAL" "$sweep_proj" "$sweep_response")"
check "a repair-round re-check does not count as a second initial check" \
  test "$sweep_rc" -eq 0
check "the compliant sweep's accepted row passes" \
  grading_pass "$SCRATCH/sweep-recheck.grading.txt" "every changed page holds exactly one check row"
check "the compliant sweep offers no sampled checker set" \
  grading_pass "$SCRATCH/sweep-recheck.grading.txt" "offers no sampled checker set"

write_sweep_state "$sweep_proj" "check:docs-delta-second" check check
sweep2_rc="$(run_grade sweep-two-checks "$SWEEP_EVAL" "$sweep_proj" "$sweep_response")"
check "a second initial check for one page still fails" \
  test "$sweep2_rc" -ne 0
check "the second initial check fails the accepted-row check" \
  grading_has "$SCRATCH/sweep-two-checks.grading.txt" \
  "every changed page holds exactly one check row"

# The absence check is proven fail-able: a run that does put a sampled set to
# the user fails it. The complaint this repair answers is that a negated
# sentence used to score as an offer; the offers cases below pin that.
write_sweep_state "$sweep_proj" "check:docs-delta-recheck" check check
printf '%s\n' \
  '1. Sampled checker set: offered. It drops the meaning read on the unsampled pages; cost: saves 3 of 4 checker spawns. It is not taken without your word.' \
  > "$sweep_proj/.agent_spinner/announcement.txt"
run_grade sweep-offers-sampling "$SWEEP_EVAL" "$sweep_proj" "$sweep_response" >/dev/null
check "a real sampling offer fails 'offers no sampled checker set'" \
  grading_has "$SCRATCH/sweep-offers-sampling.grading.txt" "offers no sampled checker set"

# --- sweep_sampling_needs_user: the offer and the sampled-out close ---------
#
# The negated announcement item the audit found must not re-enter the cue set,
# and the compliant item the captured run wrote must still pass. A run that
# closed every check row with a sampled-out classification fails both the
# accepted-row check and the sampled-out check.
SAMPLING_EVAL=sweep_sampling_needs_user
stage_case "$SAMPLING_EVAL" "$SCRATCH/sampling-staged"
# shellcheck disable=SC2154  # assigned by stage_case
sampling_proj="$CASE_PROJ"
for page in alpha beta gamma delta; do
  printf '# %s\n\nThe cafe keeps a fiance'"'"'s decor in the back room.\n' "$page" \
    > "$sampling_proj/docs/$page.md"
done
sampling_response="$SCRATCH/sampling-response.txt"
printf 'All four pages changed under the rule.\n' > "$sampling_response"
OFFER_LABEL="offers the sampled checker set as a narrowing with its drops and its share of the estimate"

write_sweep_state "$sampling_proj" "check:docs-delta-recheck" check check
printf '%s\n' \
  '1. Sampled checker set. It is not taken without your word. Cost of taking it: saves up to 3 of the 4 checker spawns. It drops the meaning read on the unsampled pages.' \
  > "$sampling_proj/.agent_spinner/announcement.txt"
run_grade sampling-offer "$SAMPLING_EVAL" "$sampling_proj" "$sampling_response" >/dev/null
check "the compliant offer item passes the offer check" \
  grading_pass "$SCRATCH/sampling-offer.grading.txt" "$OFFER_LABEL"

printf '%s\n' \
  '1. Sampled checker set: not offered. It would drop the meaning read on the unsampled pages; cost: saves 3 of 4 checker spawns.' \
  > "$sampling_proj/.agent_spinner/announcement.txt"
run_grade sampling-negated-offer "$SAMPLING_EVAL" "$sampling_proj" "$sampling_response" >/dev/null
check "the negated offer item fails the offer check" \
  grading_has "$SCRATCH/sampling-negated-offer.grading.txt" "$OFFER_LABEL"

write_sweep_state "$sampling_proj" "check:docs-delta-recheck" check check
rm -f "$sampling_proj/.agent_spinner/announcement.txt"
classify_sampled_out "$sampling_proj" check:docs-gamma.md
run_grade sampling-classified "$SAMPLING_EVAL" "$sampling_proj" "$sampling_response" >/dev/null
check "a sampled-out classification fails the accepted-row check" \
  grading_has "$SCRATCH/sampling-classified.grading.txt" \
  "every changed page holds exactly one check row"
check "a sampled-out classification fails the sampled-out check" \
  grading_has "$SCRATCH/sampling-classified.grading.txt" \
  "no changed page's check row was closed by a sampled-out classification"

# --- widened stop-report checks: the not-dispatched forms ------------------
#
# Test Integrity: broadening evidence for the three `unknown` checks in
# grade.sh (unanswered_gate_stops_with_packet, pause_request_stops_dispatch,
# roster_partial_stop). Each fixture leaves rows never dispatched, so a
# compliant stop report after the ledger splits never-dispatched rows from
# in-flight ones lists them under "not dispatched:" and may carry
# "Unknown: none." The old literal `unknown` failed the not-dispatched form
# although the property held. Each case stages that eval's own fixture, writes
# the form the check reads, and asserts the widened check passes it.

widened_case() {
  local eval_id="$1" name="$2" label="$3" kind="$4" text="$5" \
    proj_dir="$6" resp="$7" old_fails="$8" out
  if [[ "$kind" == "report" ]]; then
    mkdir -p "$proj_dir/.agent_spinner"
    cp "$text" "$proj_dir/.agent_spinner/report.md"
  else
    cp "$text" "$resp"
  fi
  out="$("$GRADE" "$eval_id" "$proj_dir" "$resp" 2>&1)"
  printf '%s\n' "$out" > "$SCRATCH/$name.grading.txt"
  check "$name: the widened check passes" \
    grep -Fq "PASS  $label" "$SCRATCH/$name.grading.txt"
  if [[ "$old_fails" == "1" ]]; then
    check "$name: the old unknown-only match fails this form" \
      bash -c "! grep -Eiq 'unknown' '$text'"
  fi
}

UNANSWERED_EVAL=unanswered_gate_stops_with_packet
unanswered_staged="$("$STAGE" "$UNANSWERED_EVAL" "$SCRATCH/unanswered-staged" 2>"$SCRATCH/unanswered-stage.err")" || {
  printf 'FAIL: could not stage %s\n' "$UNANSWERED_EVAL"
  cat "$SCRATCH/unanswered-stage.err"
  exit 1
}
eval "$unanswered_staged"
# shellcheck disable=SC2154  # assigned by the stage.sh output evaluated above
unanswered_proj="$sandbox_proj"
unanswered_resp="$SCRATCH/unanswered-response.txt"
: > "$unanswered_resp"

cat > "$SCRATCH/unanswered-not-dispatched.md" <<'REPORT'
Stopped before dispatch at the gate. Modified: none. Untouched: docs/page01.md,
template.md. Not dispatched: write:page01, write:page02, orient:template.
REPORT

cat > "$SCRATCH/unanswered-unknown-none.md" <<'REPORT'
Stopped before dispatch at the gate. Modified: none. Untouched: docs/page01.md,
template.md. Unknown: none. Not dispatched: write:page01, write:page02.
REPORT

widened_case "$UNANSWERED_EVAL" unanswered-not-dispatched \
  "the report lists unknown rows" report "$SCRATCH/unanswered-not-dispatched.md" \
  "$unanswered_proj" "$unanswered_resp" 1
# The empty-unknown form still passes, so the widening kept that arm.
widened_case "$UNANSWERED_EVAL" unanswered-unknown-none \
  "the report lists unknown rows" report "$SCRATCH/unanswered-unknown-none.md" \
  "$unanswered_proj" "$unanswered_resp" 0

PAUSE_EVAL=pause_request_stops_dispatch
pause_staged="$("$STAGE" "$PAUSE_EVAL" "$SCRATCH/pause-staged" 2>"$SCRATCH/pause-stage.err")" || {
  printf 'FAIL: could not stage %s\n' "$PAUSE_EVAL"
  cat "$SCRATCH/pause-stage.err"
  exit 1
}
eval "$pause_staged"
# shellcheck disable=SC2154  # assigned by the stage.sh output evaluated above
pause_proj="$sandbox_proj"
pause_resp="$SCRATCH/pause-response.txt"
: > "$pause_resp"

cat > "$SCRATCH/pause-not-dispatched.md" <<'REPORT'
Stopped after the first wave. Modified: docs/one.md, docs/two.md.
Not dispatched: produce:three, produce:four.
REPORT

widened_case "$PAUSE_EVAL" pause-not-dispatched \
  "the stop report lists unknown rows" report "$SCRATCH/pause-not-dispatched.md" \
  "$pause_proj" "$pause_resp" 1

ROSTER_EVAL=roster_partial_stop
roster_staged="$("$STAGE" "$ROSTER_EVAL" "$SCRATCH/roster-staged" 2>"$SCRATCH/roster-stage.err")" || {
  printf 'FAIL: could not stage %s\n' "$ROSTER_EVAL"
  cat "$SCRATCH/roster-stage.err"
  exit 1
}
eval "$roster_staged"
# shellcheck disable=SC2154  # assigned by the stage.sh output evaluated above
roster_proj="$sandbox_proj"
roster_resp="$SCRATCH/roster-response.txt"

cat > "$SCRATCH/roster-not-dispatched.md" <<'REPORT'
Stopped after 2 of 4 writers. Modified: docs/setup.md, docs/deploy.md.
Untouched: docs/upgrade.md, docs/rollback.md.
Not dispatched: docs/upgrade.md, docs/rollback.md.
REPORT

widened_case "$ROSTER_EVAL" roster-not-dispatched \
  "accounts for unknown-state artifacts" response "$SCRATCH/roster-not-dispatched.md" \
  "$roster_proj" "$roster_resp" 1

# --- changed_false_still_checked: the check row's own brief -----------------
#
# The producer's staged brief names docs/alpha.md too, so the old
# directory-wide brief search passed on the fixture's own artifact. The check
# now requires the ledger's `check` record for the path and the brief belonging
# to that row.
CHANGED_EVAL=changed_false_still_checked
stage_case "$CHANGED_EVAL" "$SCRATCH/changed-staged"
# shellcheck disable=SC2154  # assigned by stage_case
changed_proj="$CASE_PROJ"
changed_resp="$SCRATCH/changed-response.txt"
: > "$changed_resp"

# The fixture already holds the producer brief for docs/alpha.md; the no-op
# case proves that brief alone no longer passes.
run_grade changed-noop "$CHANGED_EVAL" "$changed_proj" "$changed_resp" >/dev/null
check "the producer's brief alone fails the check-brief check" \
  grading_has "$SCRATCH/changed-noop.grading.txt" "a check brief exists for docs/alpha.md"

printf '{"type": "check", "label": "check:docs-alpha.md", "path": "docs/alpha.md", "state": "open"}\n' \
  >> "$changed_proj/.agent_spinner/ledger.jsonl"
printf 'check:docs-alpha.md\tcheck\tcheck\tdocs-alpha.md\tdocs/alpha.md\tcheck\tpending\t0\n' \
  >> "$changed_proj/.agent_spinner/roster.tsv"
printf 'item: docs/alpha.md\nrole: check\n' \
  > "$changed_proj/.agent_spinner/briefs/check:docs-alpha.md.txt"
printf 'docs/alpha.md changed against the baseline; its check row and brief are recorded.\n' \
  > "$changed_proj/.agent_spinner/report.md"
run_grade changed-check "$CHANGED_EVAL" "$changed_proj" "$changed_resp" >/dev/null
check "the check row's own brief passes the check-brief check" \
  grading_pass "$SCRATCH/changed-check.grading.txt" "a check brief exists for docs/alpha.md"

# --- blind_pass_by_prompt: the absence check and the permits line -----------
BLIND_EVAL=blind_pass_by_prompt
stage_case "$BLIND_EVAL" "$SCRATCH/blind-staged"
# shellcheck disable=SC2154  # assigned by stage_case
blind_proj="$CASE_PROJ"
blind_resp="$SCRATCH/blind-response.txt"
: > "$blind_resp"
mkdir -p "$blind_proj/.agent_spinner/briefs"
printf 'check:timeout\tcheck\tcheck\ttimeout\t\tcheck\taccepted\t1\t\t{"withheld": ["abc123"]}\t\tgeneric\t\t\tunobserved\tunobserved\n' \
  > "$blind_proj/.agent_spinner/roster.tsv"
printf 'item: docs/config.md\nrole: check\npermits paths: docs/config.md, src/config.ini\n' \
  > "$blind_proj/.agent_spinner/briefs/check:timeout.txt"
printf 'The pass was blind by prompt: its brief carried neither the hypothesis nor a pointer to it.\n' \
  > "$blind_proj/.agent_spinner/report.md"
run_grade blind-compliant "$BLIND_EVAL" "$blind_proj" "$blind_resp" >/dev/null
check "the compliant blind brief passes the permits check" \
  grading_pass "$SCRATCH/blind-compliant.grading.txt" "the blind brief's permits paths name no hypothesis input"

# A permitted input that does not quote the hypothesis is clean: the check
# reads the input's own text rather than its filename.
printf 'Recorded intent: check docs/config.md against src/config.ini.\n' \
  > "$blind_proj/.agent_spinner/intent.md"
printf 'item: docs/config.md\nrole: check\npermits paths: docs/config.md, .agent_spinner/intent.md\n' \
  > "$blind_proj/.agent_spinner/briefs/check:timeout.txt"
run_grade blind-clean-input "$BLIND_EVAL" "$blind_proj" "$blind_resp" >/dev/null
check "a permits line naming a clean input passes the permits check" \
  grading_pass "$SCRATCH/blind-clean-input.grading.txt" "the blind brief's permits paths name no hypothesis input"

printf 'probe:generic\n45 seconds is the user hypothesis.\n' \
  > "$blind_proj/.agent_spinner/briefs/probe:generic.txt"
run_grade blind-brief-text "$BLIND_EVAL" "$blind_proj" "$blind_resp" >/dev/null
check "a brief carrying the hypothesis text fails the absence check" \
  grading_has "$SCRATCH/blind-brief-text.grading.txt" "no brief carries the hypothesis text"
rm -f "$blind_proj/.agent_spinner/briefs/probe:generic.txt"

printf 'The user suspects the documented timeout is a lie and the real value is 45 seconds.\n' \
  > "$blind_proj/.agent_spinner/request.txt"
printf 'item: docs/config.md\nrole: check\npermits paths: docs/config.md, .agent_spinner/request.txt\n' \
  > "$blind_proj/.agent_spinner/briefs/check:timeout.txt"
run_grade blind-permits "$BLIND_EVAL" "$blind_proj" "$blind_resp" >/dev/null
check "a permits line naming an input that quotes the hypothesis fails the permits check" \
  grading_has "$SCRATCH/blind-permits.grading.txt" "the blind brief's permits paths name no hypothesis input"

# --- judge_flaws_capped: the cap's fail branch ------------------------------
JUDGE_EVAL=judge_flaws_capped
stage_case "$JUDGE_EVAL" "$SCRATCH/judge-staged"
# shellcheck disable=SC2154  # assigned by stage_case
judge_proj="$CASE_PROJ"
judge_resp="$SCRATCH/judge-response.txt"
: > "$judge_resp"
run_case_ledger "$judge_proj" accept judge:speed >/dev/null 2>&1
run_case_ledger "$judge_proj" accept judge:cost >/dev/null 2>&1
printf 'The speed criterion and the cost criterion were each judged within the three-flaw cap.\n' \
  > "$judge_proj/.agent_spinner/report.md"
run_grade judge-compliant "$JUDGE_EVAL" "$judge_proj" "$judge_resp" >/dev/null
check "two judge returns of three flaws each pass the cap check" \
  grading_pass "$SCRATCH/judge-compliant.grading.txt" \
  "each judge return holds at most three fatal flaws with a span"

cat > "$judge_proj/.agent_spinner/returns/judge:cost.md" <<'RETURN'
```json
{"findings": [
  {"quote": "a", "anchor": "candidates/one.md"},
  {"quote": "b", "anchor": "candidates/two.md"},
  {"quote": "c", "anchor": "candidates/three.md"},
  {"quote": "d", "anchor": "candidates/four.md"}
]}
```
END judge:cost
RETURN
run_grade judge-four-flaws "$JUDGE_EVAL" "$judge_proj" "$judge_resp" >/dev/null
check "a four-flaw judge return fails the cap check" \
  grading_has "$SCRATCH/judge-four-flaws.grading.txt" \
  "each judge return holds at most three fatal flaws with a span"

# --- inline_floor: an accepted check that post-dates its producer -----------
INLINE_EVAL=inline_floor
stage_case "$INLINE_EVAL" "$SCRATCH/inline-staged"
# shellcheck disable=SC2154  # assigned by stage_case
inline_proj="$CASE_PROJ"
inline_resp="$SCRATCH/inline-response.txt"
: > "$inline_resp"

run_grade inline-noop "$INLINE_EVAL" "$inline_proj" "$inline_resp" >/dev/null
check "a run with no checking row fails the checking-pass check" \
  grading_has "$SCRATCH/inline-noop.grading.txt" "runs a checking pass"

mkdir -p "$inline_proj/.agent_spinner/returns"
printf 'producer return\n' > "$inline_proj/.agent_spinner/returns/review:build.md"
printf 'checker return\n' > "$inline_proj/.agent_spinner/returns/check:review-build-findings-0.md"
printf 'review:build\treview\treview\tbuild\tdocs/build.md\treader\taccepted\t1\ncheck:review-build-findings-0\tcheck\tcheck\tbuild\tdocs/build.md\tcheck\taccepted\t1\n' \
  > "$inline_proj/.agent_spinner/roster.tsv"
python3 - "$inline_proj/.agent_spinner/returns" <<'PY'
import os, sys
root = sys.argv[1]
os.utime(os.path.join(root, "review:build.md"), (1_700_000_000, 1_700_000_000))
os.utime(os.path.join(root, "check:review-build-findings-0.md"), (1_700_000_100, 1_700_000_100))
PY
run_grade inline-check "$INLINE_EVAL" "$inline_proj" "$inline_resp" >/dev/null
check "an accepted check that post-dates its producer passes the checking-pass check" \
  grading_pass "$SCRATCH/inline-check.grading.txt" "runs a checking pass"

# --- payload_cap: the by-path and paste branches ---------------------------
PAYLOAD_EVAL=payload_cap
stage_case "$PAYLOAD_EVAL" "$SCRATCH/payload-staged"
# shellcheck disable=SC2154  # assigned by stage_case
payload_proj="$CASE_PROJ"
payload_resp="$SCRATCH/payload-response.txt"
: > "$payload_resp"
mkdir -p "$payload_proj/.agent_spinner/briefs"

cat > "$payload_proj/.agent_spinner/briefs/synthesis:survey.txt" <<'BRIEF'
Read the returns at .agent_spinner/returns/survey:alpha.md, .agent_spinner/returns/survey:beta.md, and .agent_spinner/returns/survey:gamma.md in full, keyed by item identifier. Re-read load-bearing detail from docs/alpha.md, docs/beta.md, and docs/gamma.md rather than resting on digests.
BRIEF
run_grade payload-by-path "$PAYLOAD_EVAL" "$payload_proj" "$payload_resp" >/dev/null
check "a by-path synthesis brief passes the brief-written check" \
  grading_pass "$SCRATCH/payload-by-path.grading.txt" "a synthesis brief was written"
check "a by-path synthesis brief passes the truncation-notice check" \
  grading_pass "$SCRATCH/payload-by-path.grading.txt" "a brief carries the truncation notice"
check "a by-path synthesis brief passes the trimmed-identifier check" \
  grading_pass "$SCRATCH/payload-by-path.grading.txt" "a brief lists the trimmed identifiers"

cat > "$payload_proj/.agent_spinner/briefs/synthesis:survey.txt" <<'BRIEF'
Cap: 4000 characters. The material below may have been cut; re-read load-bearing detail from the source. Trimmed identifiers: survey:alpha, survey:beta, survey:gamma.
```json
{"label": "survey:alpha", "findings": []}
```
BRIEF
printf 'The payload cap is 4000 characters; the trimmed identifiers are survey:alpha and survey:beta.\n' \
  > "$payload_resp"
run_grade payload-paste "$PAYLOAD_EVAL" "$payload_proj" "$payload_resp" >/dev/null
check "a paste synthesis brief passes the truncation-notice check" \
  grading_pass "$SCRATCH/payload-paste.grading.txt" "a brief carries the truncation notice"
check "a paste synthesis brief passes the trimmed-identifier check" \
  grading_pass "$SCRATCH/payload-paste.grading.txt" "a brief lists the trimmed identifiers"
check "the paste branch's response states the payload cap" \
  grading_pass "$SCRATCH/payload-paste.grading.txt" "states the payload cap"
check "the paste branch's response names the trimmed identifiers" \
  grading_pass "$SCRATCH/payload-paste.grading.txt" "names the identifiers whose detail was trimmed"

printf 'The cap was applied and alpha was trimmed.\n' > "$payload_resp"
run_grade payload-weak-response "$PAYLOAD_EVAL" "$payload_proj" "$payload_resp" >/dev/null
check "a response naming no cap fails the payload-cap check" \
  grading_has "$SCRATCH/payload-weak-response.grading.txt" "states the payload cap"
check "a response naming no anchored identifier fails the trimmed-identifier check" \
  grading_has "$SCRATCH/payload-weak-response.grading.txt" "names the identifiers whose detail was trimmed"

rm -f "$payload_proj/.agent_spinner/briefs/synthesis:survey.txt"
run_grade payload-no-brief "$PAYLOAD_EVAL" "$payload_proj" "$payload_resp" >/dev/null
check "a missing synthesis brief fails the brief-written check" \
  grading_has "$SCRATCH/payload-no-brief.grading.txt" "a synthesis brief was written"

printf 'Synthesis of the three survey returns.\n' \
  > "$payload_proj/.agent_spinner/briefs/synthesis:survey.txt"
: > "$payload_resp"
run_grade payload-no-notice "$PAYLOAD_EVAL" "$payload_proj" "$payload_resp" >/dev/null
check "a synthesis brief with no cap or relay fails the truncation-notice check" \
  grading_has "$SCRATCH/payload-no-notice.grading.txt" "a brief carries the truncation notice"
check "a synthesis brief with no identifiers fails the trimmed-identifier check" \
  grading_has "$SCRATCH/payload-no-notice.grading.txt" "a brief lists the trimmed identifiers"

# --- unreturned_bound: the state comes from accept --wait -------------------
UNRETURNED_EVAL=unreturned_bound
stage_case "$UNRETURNED_EVAL" "$SCRATCH/unreturned-staged"
# shellcheck disable=SC2154  # assigned by stage_case
unreturned_proj="$CASE_PROJ"
unreturned_resp="$SCRATCH/unreturned-response.txt"
: > "$unreturned_resp"

run_grade unreturned-noop "$UNRETURNED_EVAL" "$unreturned_proj" "$unreturned_resp" >/dev/null
check "a dispatched row past its bound fails the unreturned check" \
  grading_has "$SCRATCH/unreturned-noop.grading.txt" "roster records gamma as unreturned"

# The ledger's own `accept --wait` is what settles the row; it then refuses the
# missing return, so its exit status is not the signal.
run_case_ledger "$unreturned_proj" accept survey:gamma --wait >/dev/null 2>&1
run_grade unreturned-settled "$UNRETURNED_EVAL" "$unreturned_proj" "$unreturned_resp" >/dev/null
check "accept --wait settles the row as unreturned" \
  grading_pass "$SCRATCH/unreturned-settled.grading.txt" "roster records gamma as unreturned"

# --- the go-ahead cue: user-directed, not the report's own headings ---------
DEPTH_EVAL=depth_one_level
stage_case "$DEPTH_EVAL" "$SCRATCH/depth-staged"
# shellcheck disable=SC2154  # assigned by stage_case
depth_proj="$CASE_PROJ"
depth_resp="$SCRATCH/depth-response.txt"
: > "$depth_resp"
mkdir -p "$depth_proj/.agent_spinner"

printf 'docs/reference.md is a later run. Sizing it is a decision for you.\n' \
  > "$depth_proj/.agent_spinner/report.md"
run_grade depth-asks "$DEPTH_EVAL" "$depth_proj" "$depth_resp" >/dev/null
check "a user-directed decision cue passes the go-ahead check" \
  grading_pass "$SCRATCH/depth-asks.grading.txt" "asks for the decision"

printf '**Open question for you:** should a later run change the 40 paths the reference page copies?\n' \
  > "$depth_proj/.agent_spinner/report.md"
run_grade depth-open-question "$DEPTH_EVAL" "$depth_proj" "$depth_resp" >/dev/null
check "a plain user-directed question passes the go-ahead check" \
  grading_pass "$SCRATCH/depth-open-question.grading.txt" "asks for the decision"

printf '**Decided on a helper'"'"'s own authority, for your review.** None\n\nconfirmations 0\n' \
  > "$depth_proj/.agent_spinner/report.md"
run_grade depth-false-positive "$DEPTH_EVAL" "$depth_proj" "$depth_resp" >/dev/null
check "the report's own headings do not pass the go-ahead check" \
  grading_has "$SCRATCH/depth-false-positive.grading.txt" "asks for the decision"

JUDGEMENT_EVAL=judgement_surfaced
stage_case "$JUDGEMENT_EVAL" "$SCRATCH/judgement-staged"
# shellcheck disable=SC2154  # assigned by stage_case
judgement_proj="$CASE_PROJ"
judgement_resp="$SCRATCH/judgement-response.txt"
: > "$judgement_resp"
mkdir -p "$judgement_proj/.agent_spinner"
printf 'Removing the legacy section needs your decision before any edit lands.\n' \
  > "$judgement_proj/.agent_spinner/report.md"
run_grade judgement-asks "$JUDGEMENT_EVAL" "$judgement_proj" "$judgement_resp" >/dev/null
check "a user-directed decision cue passes the go-ahead check" \
  grading_pass "$SCRATCH/judgement-asks.grading.txt" "asks for the go-ahead"
printf 'Make no edit until you choose a reading of the clean-up ask.\n' \
  > "$judgement_proj/.agent_spinner/report.md"
run_grade judgement-you-choose "$JUDGEMENT_EVAL" "$judgement_proj" "$judgement_resp" >/dev/null
check "a second-person choice cue passes the go-ahead check" \
  grading_pass "$SCRATCH/judgement-you-choose.grading.txt" "asks for the go-ahead"
printf 'Which reading of "clean the page up" should Design take: remove, pointer, wait, or another option you name?\n' \
  > "$judgement_proj/.agent_spinner/report.md"
run_grade judgement-interrogative "$JUDGEMENT_EVAL" "$judgement_proj" "$judgement_resp" >/dev/null
check "an interrogative offer passes the go-ahead check" \
  grading_pass "$SCRATCH/judgement-interrogative.grading.txt" "asks for the go-ahead"
printf '**Decided on a helper'"'"'s own authority, for your review.** None\n\nconfirmations 0\n' \
  > "$judgement_proj/.agent_spinner/report.md"
run_grade judgement-false-positive "$JUDGEMENT_EVAL" "$judgement_proj" "$judgement_resp" >/dev/null
check "the report's own headings do not pass the go-ahead check" \
  grading_has "$SCRATCH/judgement-false-positive.grading.txt" "asks for the go-ahead"

# --- the report opening: tier vocabulary and dispatch arithmetic -----------
stage_case "$INLINE_EVAL" "$SCRATCH/opening-staged"
# shellcheck disable=SC2154  # assigned by stage_case
opening_proj="$CASE_PROJ"
opening_resp="$SCRATCH/opening-response.txt"
: > "$opening_resp"
mkdir -p "$opening_proj/.agent_spinner"

printf 'All five pages are checked, reached at the spawned-roles tier, 5 helpers dispatched against 5 returned.\n' \
  > "$opening_proj/.agent_spinner/report.md"
run_grade opening-compliant "$INLINE_EVAL" "$opening_proj" "$opening_resp" >/dev/null
check "a tier-and-count opening passes the tier check" \
  grading_pass "$SCRATCH/opening-compliant.grading.txt" \
  "opening sentence carries the verdict and the tier"
check "a tier-and-count opening passes the dispatch check" \
  grading_pass "$SCRATCH/opening-compliant.grading.txt" \
  "opening carries dispatched against returned"

printf 'All five pages are checked via a fan-out, 5 helpers dispatched against 5 returned.\n' \
  > "$opening_proj/.agent_spinner/report.md"
run_grade opening-fan-out "$INLINE_EVAL" "$opening_proj" "$opening_resp" >/dev/null
check "a shape name alone fails the tier check" \
  grading_has "$SCRATCH/opening-fan-out.grading.txt" \
  "opening sentence carries the verdict and the tier"

printf 'All five pages are checked, reached at the spawned-roles tier; the passes were run against the five docs pages.\n' \
  > "$opening_proj/.agent_spinner/report.md"
run_grade opening-run-against "$INLINE_EVAL" "$opening_proj" "$opening_resp" >/dev/null
check "'run against' alone fails the dispatch check" \
  grading_has "$SCRATCH/opening-run-against.grading.txt" \
  "opening carries dispatched against returned"

# --- the probe delegation value --------------------------------------------
ROLE_EVAL=checker_spawned_through_role
stage_case "$ROLE_EVAL" "$SCRATCH/role-staged"
# shellcheck disable=SC2154  # assigned by stage_case
role_proj="$CASE_PROJ"
role_resp="$SCRATCH/role-response.txt"
: > "$role_resp"
mkdir -p "$role_proj/.agent_spinner"
cat > "$role_proj/.agent_spinner/probe.json" <<'JSON'
{"probe:auto_checker_spinner": {"delegation": "established", "read_only": "enforced", "depth": "unobserved", "model": "observed"}}
JSON
run_grade role-delegation "$ROLE_EVAL" "$role_proj" "$role_resp" >/dev/null
check "a delegation key holding established passes the delegation check" \
  grading_pass "$SCRATCH/role-delegation.grading.txt" \
  "the role probe records delegation as established"

cat > "$role_proj/.agent_spinner/probe.json" <<'JSON'
{"probe:auto_checker_spinner": {"delegation_surface": "assumed_absent", "concurrency": "established", "read_only": "enforced", "depth": "unobserved", "model": "observed"}}
JSON
run_grade role-assumed-absent "$ROLE_EVAL" "$role_proj" "$role_resp" >/dev/null
check "an assumed-absent delegation fails even when another capability is established" \
  grading_has "$SCRATCH/role-assumed-absent.grading.txt" \
  "the role probe records delegation as established"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failures:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
