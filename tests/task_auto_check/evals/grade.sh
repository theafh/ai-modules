#!/usr/bin/env bash
# grade.sh - programmatic grader for task_auto_check behavioral evals.
# shellcheck disable=SC2329
#
# Usage:
#   grade.sh <eval_id> <sandbox_proj>
#
# The grader checks filesystem-verifiable behavior. Transcript-level
# expectations remain as agent-attest notes in grading.txt.

set -uo pipefail

eval_id="${1:?eval id required}"
proj="${2:?sandbox proj path required}"

if [[ ! -d "$proj" ]]; then
  echo "FAIL: $proj is not a directory" >&2
  exit 1
fi

target="$(cd "$proj/.." && pwd)"
marker="$target/.eval_started_at"
if [[ ! -s "$marker" ]]; then
  echo "FAIL: $marker missing or empty (did stage.sh run?)" >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../../lib/host_tasks_guard.sh
. "$HERE/../../lib/host_tasks_guard.sh"
LINT="$REPO_ROOT/plugins/ai_dev/skills/task/scripts/lint.py"
TASKS="$proj/tasks"

# Worker transcript written by run.py next to the sandbox; absent when the
# eval is staged operator-driven. Transcript checks run only when present.
RESPONSE="${RESPONSE_FILE:-$target/../response.txt}"
# shellcheck source=../../lib/repeated_link_disposition.sh
. "$HERE/../../lib/repeated_link_disposition.sh"

pass=0
fail=0
failures=()

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
    printf '  PASS  %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "$label"
    failures+=("$label")
  fi
}

relay_check() {
  python3 "$HERE/relay_checks.py" "$1" "$proj" "$2"
}

note_agent_attest() {
  printf '  -     agent-attest  %s\n' "$1"
}

fm_field() {
  sed -n '/^---$/,/^---$/p' "$1" | grep -m1 "^$2:" \
    | sed "s/^$2:[[:space:]]*//; s/^[\"']//; s/[\"']$//"
}

body_text() {
  awk 'BEGIN {front=0; seen=0}
       /^---$/ && seen == 0 {front=1; seen=1; next}
       /^---$/ && front == 1 {front=0; next}
       front == 0 {print}' "$1"
}

task_lints() {
  python3 "$LINT" "$TASKS" >/dev/null 2>&1
}

no_real_repo_writes() {
  # Fixture names from this sandbox, compared with the isolated copy taken at
  # stage. A concurrent session editing some other real task stays outside
  # the comparison.
  host_fixture_writes_clean "$target" "$REPO_ROOT" "$TASKS" "$marker"
}

task_count_is() {
  local want="$1" count
  count="$(find "$TASKS" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
  [[ "$count" == "$want" ]]
}

status_is() {
  local file="$1" want="$2"
  [[ "$(fm_field "$file" status)" == "$want" ]]
}

# no_repeated_link_finding <task file> -> the target carries no repeated-link
# warn after the run. The base protocol makes the gathered material, not the
# surviving link count, the measure of a resolved finding, and in these
# fixtures both links carry one handoff that belongs in one passage, so a
# genuine reorganization necessarily leaves one link and clears the warn.
# Grading the linter's own verdict keeps the check off any particular sentence
# the regroup happened to write.
no_repeated_link_finding() {
  local file="$1"
  ! python3 "$LINT" "$TASKS" --file "$file" 2>/dev/null | grep -q 'repeated-link'
}

# body_mentions_once <file> <needle> -> the account sits in one section. Counts
# the H2 sections whose text names the needle, so a one-clause plain pointer at
# the other site would still fail this and is not what these fixtures stage.
sections_naming() {
  local file="$1" needle="$2"
  body_text "$file" | awk -v n="$needle" '
    /^## / { sec=$0 }
    index($0, n) > 0 && sec != "" { seen[sec]=1 }
    END { c=0; for (k in seen) c++; print c }'
}

# section_text <file> <heading> -> one H2 section's text with its hard wraps
# collapsed, so a re-wrapped section compares equal to the staged one.
section_text() {
  body_text "$1" | awk -v h="$2" '
    $0 == h { f=1; next }
    /^## / { f=0 }
    f { print }' | tr '\n' ' ' | tr -s ' '
}

# Response helpers. RESPONSE is absent for an operator-staged run, so a check
# that needs it fails loudly rather than passing vacuously.
response_has() { [[ -s "$RESPONSE" ]] && grep -qiE -- "$1" "$RESPONSE"; }
response_readable() { [[ -s "$RESPONSE" ]]; }

# surfaced_channel_names_repeated_link -> a surfaced-but-not-fixed line names
# a repeated-link finding. The output contract has the run report that channel
# with the Repeated-link disposition filter already applied, so a faithful
# empty-channel line names the filter ("Surfaced-but-not-fixed (after
# Repeated-link disposition filter): none"); its label is dropped before the
# match so the filter's name never reads as a finding. A line whose channel
# value is a bare none, with at most one parenthetical note after it
# ("Surfaced-but-not-fixed: none (repeated-link filtered via disposition
# filter)"), is an empty channel, so that line is dropped too. grep reads one
# line at a time, so `.` keeps the match on the channel line.
surfaced_channel_names_repeated_link() {
  response_readable || return 1
  tr '[:upper:]' '[:lower:]' < "$RESPONSE" \
    | sed 's/repeated-link disposition filter//g' \
    | sed -E 's/surfaced-but-not-fixed[^a-z0-9]{0,8}(none|nothing|empty)[[:space:]]*(\([^)]*\))?[[:space:].]*$//' \
    | grep -qE 'surfaced-but-not-fixed.{0,160}repeated-link'
}

# response_records -> the response one record per line. A blank line, a code
# fence, a heading, a list item, a table row, or a bold label line such as
# "**Gate 2 (re-gate):**" starts a record, a line ending in a markdown hard
# break closes one, and a hard-wrapped line joins the record it continues. Prose
# therefore reads with its wraps collapsed, while one list item never runs into
# the next, so a negation in one item cannot reach a claim in another.
response_records() {
  response_readable || return 1
  awk '
    function flush() { if (rec != "") print rec; rec = "" }
    /^[[:space:]]*$/ || /^[[:space:]]*```/ { flush(); next }
    /^[[:space:]]*(#|\||[-*+][[:space:]]|[0-9]+[.)][[:space:]])/ { flush() }
    /^[[:space:]]*\*\*[^*]+(:\*\*|\*\*:)/ { flush() }
    { rec = (rec == "" ? $0 : rec " " $0) }
    /  $/ { flush() }
    END { flush() }' "$RESPONSE"
}

# split_at <chars> -> stdin split after each of <chars> that ends a sentence,
# whether a space follows it or a worker's progress notes join the next
# sentence on without one ("then re-gating.`ready` after repair").
split_at() {
  sed -E "s/([$1])[[:space:]]+/\\1\\
/g; s/([$1])([A-Z\`#*])/\\1\\
\\2/g"
}

# The gate-verdict and status-move patterns the report checks below share. A
# report bolds and backticks status words freely ("`checked` → **`ready`**"), so
# every pattern lets those markers sit around them.
#
# FLIP: a gate verdict that read checked and stamped ready, in the arrow form
# the output contract makes a report name, the prior/stamped form a per-gate
# line uses, or a flip to ready.
FLIP='checked[`*]* *(→|->|to) *[`*]*ready|(^|[^a-z])(prior( status|_status)?|reads?)[^a-z][^.;]{0,8}checked[^.;]{0,40}(stamp(s|ed)?|wr(ote|ites)|status)[^.;]{0,12}ready|ready[`*]*[^.;]{0,16}prior[ _a-z:]{0,10}[`*]*checked|flip(ped|s)?[^.;]{0,20}to [`*]*ready'
# NEGATED_FLIP: a sentence naming the flip only to deny it: a negation in front
# of the flip ("No checked → ready flip occurred"), or none after it
# ("checked → ready flip: none").
NEGATED_FLIP='(^|[^a-z])(no|not|never|without)( (a|any|the))?[^a-z]{1,4}checked[`*]* *(→|->|to) *[`*]*ready|(^|[^a-z])(no|not|never|without|did not|didn.t)( (a|any|the))?[^a-z]{1,4}flip|flip(ped|s)?[^a-z]{1,6}(none|n/a|did not|didn.t|not )|checked[`*]* *(→|->|to) *[`*]*ready[`*]*[^a-z]{1,6}(none|n/a)([^a-z]|$)'
# REGATE: the word re-gate, a second or later gate call, or a gate call placed
# after the regroup.
REGATE='(^|[^a-z])re-?gat(e|es|ed|ing)([^a-z]|$)|(second|2nd|third) (`?task_check`? )?gate call|gate call[^.]{0,60}after the (regroup|repeated-link|round|edit)'
# NEGATED_REGATE: a sentence naming the re-gate only to deny it: a negation in
# front of it, a denial after it, or a label whose value is none ("Re-gate:
# none", "Gate calls after the round: 0").
NEGATED_REGATE='(^|[^a-z])(no|not|never|without|skip(s|ped)?)[^a-z][^.]{0,40}(re-?gat|gate call)|(re-?gat(e|ed|ing)?|gate call)[^.]{0,30}(did not|didn.t|was not|wasn.t|not (run|needed|required|applicable|triggered|performed|invoked|owed)|skipped)|(re-?gat(e|es|ed|ing)?|gate calls?( after the [a-z-]+)?|flips?)[*`]*[[:space:]]*:[^a-z0-9]{0,4}(none|n/a|no|0)[*`]*[[:space:]]*([(.;,]|$)'
# REFUTED: a citation the immediate-ready refutation pass refuted, as a count
# or a label ("12 refuted", "Refuted (4):", "were refuted"). NEGATED_REFUTED
# drops a denial ("0 refuted", "none refuted", "no citation was refuted",
# "Refuted: none").
REFUTED='(^|[^a-z])refuted([^a-z]|$)'
NEGATED_REFUTED='(^|[^a-z0-9])(0|no|none|zero|not|never|nothing)[^.;]{0,30}refuted|refuted[^a-z0-9]{0,4}(\(0\)|0|none|n/a|no)([^a-z0-9]|$)'

# regate_reported -> the response records a gate call after the repeated-link
# round: the word re-gate, a second or later gate call, a gate call placed
# after the regroup, or a checked -> ready flip, which on a target the first
# gate stamped ready can only come from a gate after something wrote checked.
# A sentence that names the re-gate or the flip only to deny it is dropped
# first, so neither "no re-gate ran" nor "No checked → ready flip occurred"
# counts as one.
regate_reported() {
  response_readable || return 1
  response_records | split_at '.;!?' \
    | grep -iE "$REGATE|$FLIP" \
    | grep -viE "$NEGATED_REGATE|$NEGATED_FLIP" \
    | grep -q .
}

# reported_gate_calls -> the gate-call count the output contract makes the
# report state ("2 gate calls", "Gate calls: **1**", "| Gate calls | 1 |"),
# read from the plural count first so an ordinal such as "gate call 1" never
# stands in for it; empty when the report carries no count.
reported_gate_calls() {
  local text n
  response_readable || return 1
  text="$(tr -d '*`|' < "$RESPONSE" | tr '[:upper:]' '[:lower:]')"
  n="$(grep -oE '([0-9]+|two|three|four|five) gate calls|gate calls[^a-z0-9]{0,8}[0-9]+' <<<"$text" | head -1 \
    | sed -E 's/two/2/; s/three/3/; s/four/4/; s/five/5/' | grep -oE '[0-9]+' | head -1)"
  if [[ -z "$n" ]] && grep -qE '(^|[^0-9a-z])(1|one) gate call([^s]|$)' <<<"$text"; then n=1; fi
  printf '%s' "$n"
}

# gate_call_after_round -> the run made a gate call after the repeated-link
# round: the report names one, or its gate-call count passes one on a path
# whose only gate call before the round was the first.
gate_call_after_round() {
  local n
  regate_reported && return 0
  n="$(reported_gate_calls)"
  [[ -n "$n" ]] && (( n > 1 ))
}

# approval_stood -> the immediate approval stood: the report records the
# citations surviving and records no citation refuted. The output contract
# names each citation `survived` or `refuted`, so a run on the
# citation-refutation path, and one whose signature never held, reads false.
approval_stood() {
  response_readable || return 1
  grep -qiE 'surviv' "$RESPONSE" || return 1
  ! response_records | tr -d '*`' | split_at '.;!?' \
    | grep -iE "$REFUTED" | grep -viE "$NEGATED_REFUTED" | grep -q .
}

status_is_one_of() {
  local file="$1"
  shift
  local actual want
  actual="$(fm_field "$file" status)"
  for want in "$@"; do
    [[ "$actual" == "$want" ]] && return 0
  done
  return 1
}

# no_real_tasks_moved -> fixture-named paths and bytes still match the isolated
# copy taken at stage. A parallel session that moves some other real task
# changes the live tree and leaves this check green.
no_real_tasks_moved() {
  host_fixture_copy_clean "$target" "$REPO_ROOT" "$TASKS"
}

# delta_return_maps_diff <relay dir> <r<N>-delta[-k].txt> -> the delta return
# carries the verifier's map behind its header. Its `## Hunks` items name the
# `@@` ranges of round N's current r<N>-apply.diff.txt one to one, each with a
# license other than unmapped, and its `## Approved edit ids` marks every id
# the round's last proposal-mode verifier return approved as applied. A clean
# header with no map behind it fails.
delta_return_maps_diff() {
  python3 - "$1" "$2" <<'PY'
import collections
import pathlib
import re
import sys

relay = pathlib.Path(sys.argv[1])
ret = pathlib.Path(sys.argv[2])
name = re.fullmatch(r"r([0-9]+)-delta(?:-[0-9]+)?\.txt", ret.name)
if not name:
    raise SystemExit(1)
n = int(name.group(1))
text = ret.read_text()
hunk_range = re.compile(r"@@ -[0-9]+(?:,[0-9]+)? \+[0-9]+(?:,[0-9]+)? @@")
key_line = re.compile(r"^\s*(?:(?:[0-9]+\.|[-*])\s+)*(hunk|license|id|status):\s*(.*?)\s*$")


def section(body, heading):
    found = re.search(rf"(?ms)^## {heading}[ \t]*$(.*?)(?=^## |\Z)", body)
    return found.group(1).splitlines() if found else []


def bare(value):
    return value.strip("`*\"' ")


diff = relay / f"r{n}-apply.diff.txt"
if not diff.is_file():
    raise SystemExit(1)
diff_hunks = collections.Counter(
    hunk_range.search(line).group(0)
    for line in diff.read_text().splitlines()
    if line.startswith("@@") and hunk_range.search(line)
)

hunks = []
for line in section(text, "Hunks"):
    match = key_line.match(line)
    if not match:
        continue
    key, value = match.groups()
    if key == "hunk":
        found = hunk_range.search(value)
        if not found:
            raise SystemExit(1)
        hunks.append([found.group(0), ""])
    elif key == "license" and hunks:
        hunks[-1][1] = bare(value)
if not hunks or collections.Counter(h for h, _ in hunks) != diff_hunks:
    raise SystemExit(1)
if any(not lic or re.search(r"\bunmapped\b", lic, re.I) for _, lic in hunks):
    raise SystemExit(1)

calls = []
for path in relay.glob(f"r{n}-verifier*.txt"):
    match = re.fullmatch(rf"r{n}-verifier(?:-([0-9]+))?\.txt", path.name)
    body = path.read_text()
    if match and "## Approved edits" in body:
        calls.append((int(match.group(1) or 1), body))
if not calls:
    raise SystemExit(1)
approved = {
    bare(value)
    for key, value in (
        m.groups() for m in map(key_line.match, section(max(calls)[1], "Approved edits")) if m
    )
    if key == "id"
}
if not approved:
    raise SystemExit(1)
statuses, current = {}, None
for line in section(text, "Approved edit ids"):
    match = key_line.match(line)
    if not match:
        continue
    key, value = match.groups()
    if key == "id":
        current = bare(value)
    elif key == "status" and current:
        statuses[current] = bare(value).lower()
if any(statuses.get(edit_id) != "applied" for edit_id in approved):
    raise SystemExit(1)
PY
}

# verifier_returns_keep_contract <relay dir> -> every saved proposal-mode
# verifier return r<N>-verifier[-k].txt carries the agent's proposal-mode output
# contract in full. `## Approved edits` and `## Rejections and routes` each read
# "None." or list items, an approved item opening at its `id:` field and a
# rejection at its `issue:` field, and every item carries each field the
# contract gives it, with a rejection's decision one the contract names. A
# missing section, and one summarized into a line with no items behind it, fail.
# Inside a section, a numbered line at any indentation and every other column-0
# line must open an item at the section's lead field, set a contract field its
# item still lacks, or continue an open anchor or replacement value, the fields
# that copy task text verbatim; the None form before any item is the one other
# column-0 line allowed. Any other such line is a pointer or summary standing
# in for items and fails, also after real items. The header's
# approved_edit_count must equal the approved items and its human_routed_count
# the human_routed rejections, so a dropped item fails even when every
# remaining item is whole. Indented continuation lines belong to the field
# above them, so a wrapped replacement or reason reads as one value. Stance
# accounting: every saved reviewer return of that round contributes its
# `stance:` value, and each must appear among the verifier return's
# `source_stance:` values (approved or rejection), after the same normalize
# (lowercase, drop markdown punctuation and a trailing "advocate", fold
# non-alphanumerics to "-") with substring match so a merged source_stance
# covers each named stance. That catches a return that keeps one rejection
# and elides the rest behind an indented pointer, or that replaces every
# rejection with "None." while reviewer returns remain. A citation-mode
# return keeps its own shape and is skipped.
verifier_returns_keep_contract() {
  python3 - "$1" <<'PY'
import pathlib
import re
import sys

relay = pathlib.Path(sys.argv[1])
key_line = re.compile(r"^\s*(?:[0-9]+[.)]\s+)?(?:[-*]\s+)?\**([a-z_]+)\**\s*:\**\s*(.*?)\s*$")
item_line = re.compile(r"^\s*[0-9]+[.)]\s")
column0 = re.compile(r"^\S")
none_lead = re.compile(r"""^\s*["'`*]*none\b""", re.I)
approved_fields = ("id", "issue", "source_stance", "base_rule_cited", "anchor", "replacement", "edit", "fidelity")
rejection_fields = ("issue", "source_stance", "decision", "reason")
verbatim_fields = ("anchor", "replacement")
decisions = {"rejected", "human_routed", "unassessable"}


def bare(value):
    return value.strip("`*\"' ")


def normalize_stance(value):
    text = bare(value).lower()
    text = re.sub(r"[`*_\[\]()'\".,:;]+", "", text)
    text = re.sub(r"\s+advocate\s*$", "", text)
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")


def section(body, heading):
    found = re.search(rf"(?ms)^## {re.escape(heading)}[ \t]*$(.*?)(?=^## |\Z)", body)
    return found.group(1).splitlines() if found else None


def header_count(body, key):
    head = re.split(r"(?m)^## ", body, maxsplit=1)[0]
    for line in head.splitlines():
        match = key_line.match(line)
        if match and match.group(1) == key:
            return int(bare(match.group(2))) if bare(match.group(2)).isdigit() else None
    return None


def items(lines, lead, fields):
    found, current, last = [], None, None
    for line in lines:
        if not line.strip():
            continue
        match = key_line.match(line)
        name = match.group(1) if match and match.group(1) in fields else None
        fresh = current is not None and name is not None and name not in current
        if name == lead:
            current, last = {}, None
            found.append(current)
        elif last in verbatim_fields:
            pass
        elif item_line.match(line):
            return None
        elif column0.match(line) and not fresh:
            if current is None and none_lead.match(line):
                continue
            return None
        if current is None:
            continue
        if name and name not in current:
            current[name], last = [match.group(2)], name
        else:
            current[last].append(line.strip())
    return [{k: " ".join(v).strip() for k, v in item.items()} for item in found]


def keeps(lines, lead, fields):
    if lines is None:
        return False
    found = items(lines, lead, fields)
    if found is None:
        return False
    if not found:
        content = [line for line in lines if line.strip()]
        return bool(content) and bool(none_lead.match(content[0]))
    return all(all(field in item for field in fields) for item in found)


def reviewer_stances(round_n):
    found = []
    for path in relay.glob(f"r{round_n}-reviewer*.txt"):
        if "-prompt" in path.name:
            continue
        if not re.fullmatch(rf"r{round_n}-reviewer-.+\.txt", path.name):
            continue
        match = re.search(r"(?m)^stance:\s*(.+?)\s*$", path.read_text())
        if match:
            found.append(match.group(1))
    return found


def source_stances(approved_items, rejection_items):
    values = []
    for item in approved_items + rejection_items:
        values.append(item.get("source_stance", ""))
    return values


def stances_accounted(reviewer, sources):
    norms = [normalize_stance(s) for s in sources if normalize_stance(s)]
    for stance in reviewer:
        want = normalize_stance(stance)
        if not want:
            continue
        if not any(want in have for have in norms):
            return False
    return True


returns = [
    path for path in relay.glob("r*-verifier*.txt")
    if re.fullmatch(r"r[0-9]+-verifier(?:-[0-9]+)?\.txt", path.name)
]
proposal = [
    path for path in returns
    if not re.search(r"(?m)^mode:\s*citation\s*$", path.read_text())
]
if not proposal:
    raise SystemExit(1)
for path in proposal:
    text = path.read_text()
    round_n = re.fullmatch(r"r([0-9]+)-verifier(?:-[0-9]+)?\.txt", path.name).group(1)
    approved = section(text, "Approved edits")
    rejections = section(text, "Rejections and routes")
    if not keeps(approved, "id", approved_fields) or not keeps(rejections, "issue", rejection_fields):
        raise SystemExit(1)
    approved_items = items(approved, "id", approved_fields)
    rejection_items = items(rejections, "issue", rejection_fields)
    routed = 0
    for item in rejection_items:
        decision = bare(item["decision"]).lower()
        if decision not in decisions or not item["reason"]:
            raise SystemExit(1)
        routed += decision == "human_routed"
    if header_count(text, "approved_edit_count") != len(approved_items):
        raise SystemExit(1)
    if header_count(text, "human_routed_count") != routed:
        raise SystemExit(1)
    if not stances_accounted(
        reviewer_stances(round_n),
        source_stances(approved_items, rejection_items),
    ):
        raise SystemExit(1)
PY
}

# delta_returns_precede_next_prompt <relay dir> -> every saved delta return
# r<N>-delta[-k].txt was written before the loop moved on from its call: no
# later than the first relay prompt written after its own
# r<N>-delta[-k]-prompt.txt. A return saved within a second of that prompt
# passes, so one batch write that saves both never fails. A return rewritten
# after the loop moved on fails, and so does a return with no prompt file to
# place its call.
delta_returns_precede_next_prompt() {
  python3 - "$1" <<'PY'
import pathlib
import re
import sys

relay = pathlib.Path(sys.argv[1])
prompts = [path.stat().st_mtime for path in relay.glob("*-prompt.txt")]
returns = [
    path for path in relay.glob("r*-delta*.txt")
    if re.fullmatch(r"r[0-9]+-delta(?:-[0-9]+)?\.txt", path.name)
]
if not returns:
    raise SystemExit(1)
for ret in returns:
    prompt = ret.with_name(f"{ret.stem}-prompt.txt")
    if not prompt.is_file():
        raise SystemExit(1)
    later = [written for written in prompts if written > prompt.stat().st_mtime]
    if later and ret.stat().st_mtime >= min(later) + 1.0:
        raise SystemExit(1)
PY
}

check "isolation: no writes to the real repo's tasks/ tree" no_real_repo_writes
check "isolation: the real repo's tasks/ tree is unmoved" no_real_tasks_moved

case "$eval_id" in
  mechanical_lint_ready)
    f="$TASKS/api_lint-ready.md"
    # ready|checked: the current gate reads the over-budget description as a
    # gate-visible finding and may stamp checked; finalization still fixes it
    # and task_check stays the only status writer (same pattern as the link
    # and frontmatter siblings).
    status_ready() { status_is_one_of "$f" ready checked; }
    description_within_budget() {
      local desc
      desc="$(fm_field "$f" description)"
      [[ "${#desc}" -le 200 ]]
    }
    description_scope_preserved() {
      # Case-insensitive on the scope tokens: a rewrite that names the api
      # docs target, Retry-After, and throttling preserves the scope whatever
      # its casing — demanding a literal uppercase token false-fails a valid
      # rewrite (runbook grader rule).
      local desc
      desc="$(fm_field "$f" description | tr '[:upper:]' '[:lower:]')"
      [[ "$desc" == *api* && "$desc" == *retry-after* && "$desc" == *throttling* ]]
    }
    stale_description_gone() {
      ! grep -q 'overly elaborated explanatory sentence that should disappear' "$f"
    }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_lint-ready.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    check "task remains status: ready" status_ready
    check "description is within linter budget" description_within_budget
    check "description preserves API Retry-After throttling scope" description_scope_preserved
    check "stale overlong description wording is gone" stale_description_gone
    check "task body is unchanged by mechanical lint cleanup" body_preserved
    check "updated timestamp changes for the mechanical edit" updated_changed
    check "task lints clean after mechanical finalization" task_lints
    note_agent_attest "response reports one gate call, zero body edit rounds, and one mechanical-lint edit group"
    note_agent_attest "response names the base task linter and reports no remaining target-file lint findings"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  mechanical_lint_link)
    f="$TASKS/api_pagination-ready.md"
    status_ready() { status_is_one_of "$f" ready checked; }
    link_repointed() { grep -Fq '(api_cursor-contract.md)' "$f"; }
    broken_target_gone() { ! grep -Fq '(api_cursor.md)' "$f"; }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    check "status stays ready/checked (gate verdict only)" status_ready
    check "broken link is re-pointed to api_cursor-contract.md" link_repointed
    check "missing api_cursor.md target is no longer referenced" broken_target_gone
    check "updated timestamp changes for the mechanical edit" updated_changed
    check "tasks tree lints clean after mechanical finalization" task_lints
    note_agent_attest "response reports one gate call, zero body edit rounds, and one mechanical-lint edit group"
    note_agent_attest "response names the base task linter and reports no remaining target-file lint findings"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  mechanical_lint_frontmatter)
    f="$TASKS/api_timeout-ready.md"
    status_ready() { status_is_one_of "$f" ready checked; }
    created_iso() {
      local c
      c="$(fm_field "$f" created)"
      [[ "$c" != *"/"* && "$c" == 2026-01-01* ]]
    }
    # Goal preservation instead of byte-identity: the max-strictness gate may
    # draw a small verified body refinement on any run, and that is the
    # ordinary repair path working, not the mechanical path rewriting the
    # body. What must hold: the 504 timeout objective survives and the
    # documented edit surfaces stay named (same pattern as the repair-class
    # evals).
    goal_preserved() { grep -q '504' "$f" && grep -qE 'docs/api\.md|src/api/timeout\.py' "$f"; }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    check "status stays ready/checked (gate verdict only, no other change)" status_ready
    check "created is normalised to ISO 8601 (2026-01-01)" created_iso
    check "504 timeout objective and edit surfaces are preserved" goal_preserved
    check "updated timestamp changes for the mechanical edit" updated_changed
    check "tasks tree lints clean after mechanical finalization" task_lints
    note_agent_attest "response reports one gate call, zero body edit rounds, and one mechanical-lint edit group"
    note_agent_attest "response names the base task linter and reports no remaining target-file lint findings"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  mechanical_lint_markdown)
    f="$TASKS/api_errors-ready.md"
    # ready|checked: the current gate may hold body findings beyond the
    # wikilink (it doubles as a gate-visible finding); finalization still
    # converts the wikilink and task_check stays the only status writer.
    status_ready() { status_is_one_of "$f" ready checked; }
    no_wikilink() { ! grep -Fq '[[' "$f"; }
    link_converted() { grep -Fq '(api_error-codes.md)' "$f"; }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    check "task remains status: ready" status_ready
    check "wikilink syntax is removed from the body" no_wikilink
    check "wikilink is converted to a standard link to api_error-codes.md" link_converted
    check "updated timestamp changes for the mechanical edit" updated_changed
    check "tasks tree lints clean after mechanical finalization" task_lints
    note_agent_attest "response reports one gate call, zero body edit rounds, and one mechanical-lint edit group"
    note_agent_attest "response names the base task linter and reports no remaining target-file lint findings"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  mechanical_lint_oversized_surface)
    f="$TASKS/api_audit-log-ready.md"
    one_task() { task_count_is 1; }
    no_archive_task() { [[ -z "$(find "$TASKS/archive" -type f -name '*.md' 2>/dev/null)" ]]; }
    status_kept() { status_is_one_of "$f" ready checked; }
    enumeration_intact() { [[ "$(grep -c -- '^- field_' "$f")" == "320" ]]; }
    still_oversized() { [[ "$(wc -l < "$f" | tr -d ' ')" -gt 300 ]]; }
    check "no new task file is created" one_task
    check "no split file is archived or moved" no_archive_task
    check "status stays ready/checked (gate stamp only)" status_kept
    check "all 320 field bullets remain (not gutted or collapsed into a pointer)" enumeration_intact
    check "task remains oversized and surfaced rather than auto-fixed" still_oversized
    note_agent_attest "response surfaces the oversize as a split needing human or auto_shaper_task routing"
    note_agent_attest "response does not auto-split or truncate the task and reports zero mechanical-lint edit groups for this file"
    ;;

  already_ready)
    f="$TASKS/api_ready-task.md"
    status_ready() { status_is "$f" ready; }
    one_task() { task_count_is 1; }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_ready-task.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    check "task remains status: ready" status_ready
    check "no extra task files created" one_task
    check "task body is unchanged (zero repair edits)" body_preserved
    check "task lints clean" task_lints
    note_agent_attest "response reports one gate call and zero edit rounds"
    note_agent_attest "response names task_check as the gate and defines no second readiness criterion"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  intent_drift_human_route)
    f="$TASKS/api_search-pagination.md"
    status_open() { status_is "$f" open; }
    one_task() { task_count_is 1; }
    no_archive_task() { [[ -z "$(find "$TASKS/archive" -type f -name '*.md' 2>/dev/null)" ]]; }
    current_body_preserved() {
      grep -Fq 'Document the public API search filter syntax' "$f" \
        && grep -Fq 'Document the supported filter operators' "$f"
    }
    origin_not_restored() { ! grep -Fq 'Add cursor pagination to the public API search endpoint' "$f"; }
    updated_unchanged() { [[ "$(fm_field "$f" updated)" == "2026-01-02T00:00:00" ]]; }
    check "task remains status: open because task_check is not run" status_open
    check "no extra task files created" one_task
    check "no task file is archived or moved" no_archive_task
    check "current filter-documentation body is unchanged" current_body_preserved
    check "committed cursor-pagination Goal is not restored" origin_not_restored
    check "updated timestamp remains unchanged because no edit was applied" updated_unchanged
    check "task lints clean after drift route" task_lints
    note_agent_attest "response invokes auto_drift_task exactly once at freeze time before any task_check gate call"
    note_agent_attest "response surfaces the human intention check about prior Goal drift"
    note_agent_attest "response includes recovered cursor-pagination intent and current filter-documentation intent"
    note_agent_attest "response reports zero gate calls, zero body edit rounds, and zero mechanical-lint edit groups"
    ;;

  drift_gate_narrowing_clean)
    f="$TASKS/api_search-results.md"
    one_task() { task_count_is 1; }
    gate_reached() { status_is_one_of "$f" ready checked; }
    narrowing_kept() {
      grep -Fq '**Out of scope:** CSV export of search results' "$f" \
        && grep -Fq '# API search cursor pagination' "$f"
    }
    check "no extra task files created" one_task
    check "gate reached (status ready or checked)" gate_reached
    check "narrowed Out of scope carve-out remains" narrowing_kept
    check "task lints clean" task_lints
    note_agent_attest "response invokes auto_drift_task once and classifies clean"
    note_agent_attest "response reports no human intention check"
    note_agent_attest "response reaches the task_check gate (at least one gate call)"
    ;;

  drift_gate_refinement_clean)
    f="$TASKS/api_timeout-headers.md"
    one_task() { task_count_is 1; }
    gate_reached() { status_is_one_of "$f" ready checked; }
    path_corrected() {
      grep -Fq 'docs/api.md' "$f" \
        && ! grep -Fq 'docs/timeout.md' "$f" \
        && grep -Fq '# API timeout headers and response-test coverage' "$f"
    }
    check "no extra task files created" one_task
    check "gate reached (status ready or checked)" gate_reached
    check "corrected docs/api.md path and widened title remain" path_corrected
    check "task lints clean" task_lints
    note_agent_attest "response invokes auto_drift_task once and classifies clean"
    note_agent_attest "response reports no human intention check"
    note_agent_attest "response reaches the task_check gate (at least one gate call)"
    ;;

  drift_gate_broadening_drift)
    f="$TASKS/api_search-pagination.md"
    status_open() { status_is "$f" open; }
    one_task() { task_count_is 1; }
    no_archive_task() { [[ -z "$(find "$TASKS/archive" -type f -name '*.md' 2>/dev/null)" ]]; }
    body_preserved() {
      grep -Fq 'webhook delivery surface' "$f" \
        && grep -Fq 'src/api/webhooks.py' "$f"
    }
    updated_unchanged() { [[ "$(fm_field "$f" updated)" == "2026-01-02T00:00:00" ]]; }
    check "task remains status: open because task_check is not run" status_open
    check "no extra task files created" one_task
    check "no task file is archived or moved" no_archive_task
    check "webhook-broadened body is unchanged" body_preserved
    check "updated timestamp remains unchanged because no edit was applied" updated_unchanged
    check "task lints clean after drift route" task_lints
    note_agent_attest "response invokes auto_drift_task exactly once at freeze time before any task_check gate call"
    note_agent_attest "response reports classification drift with drifted_fields: goal"
    note_agent_attest "response surfaces the human intention check about Goal drift"
    note_agent_attest "response reports zero gate calls, zero body edit rounds, and zero mechanical-lint edit groups"
    ;;

  drift_gate_committed_broadening_clean)
    f="$TASKS/api_search-pagination.md"
    one_task() { task_count_is 1; }
    gate_reached() { status_is_one_of "$f" ready checked; }
    csv_goal_kept() {
      grep -Fq 'CSV export of the same result set' "$f" \
        && grep -Fq 'download them in one file' "$f"
    }
    check "no extra task files created" one_task
    check "gate reached (status ready or checked)" gate_reached
    check "committed CSV-export Goal remains with refinement wording" csv_goal_kept
    check "task lints clean" task_lints
    note_agent_attest "response invokes auto_drift_task once and classifies clean"
    note_agent_attest "response reports no human intention check"
    note_agent_attest "response reaches the task_check gate (at least one gate call)"
    ;;

  repair_to_ready)
    f="$TASKS/api_retry-after.md"
    status_ready() { status_is "$f" ready; }
    goal_preserved() { grep -q 'Retry-After' "$f"; }
    approach_filled() { ! grep -q 'TBD' "$f"; }
    acceptance_flippable() { ! grep -qi 'works properly' "$f" && grep -qiE '429|Retry-After|docs/api\.md|src/api/throttle\.py' "$f"; }
    check "task reaches status: ready" status_ready
    check "original Retry-After objective is preserved" goal_preserved
    check "placeholder approach is replaced" approach_filled
    check "acceptance/context becomes concrete and flippable" acceptance_flippable
    check "task lints clean after repair" task_lints
    check "ready before the cap receives no citation refutation" relay_check early_ready_control api_retry-after
    note_agent_attest "response shows the original Goal was frozen before edits"
    note_agent_attest "first gate call uses task_check and reports checked issues"
    note_agent_attest "reviewer proposals cite base task <body> repair rules"
    note_agent_attest "verifier keeps only minimum intent-preserving fixes"
    ;;

  committed_rule_deletion_routed)
    f="$TASKS/api_committed-rules.md"
    check "window commitment remains verbatim" grep -Fq -- '- Window value rule: Set `Retry-After` to the string form of `THROTTLE_WINDOW_SECONDS`.' "$f"
    check "header commitment remains verbatim" grep -Fq -- '- Header preservation rule: Preserve the existing `Content-Type` header unchanged.' "$f"
    check "body commitment remains verbatim" grep -Fq -- '- Body preservation rule: Preserve the existing response body unchanged.' "$f"
    check "first gate raises unproven header preservation" relay_check raises_header api_committed-rules
    check "first gate raises unproven body preservation" relay_check raises_body api_committed-rules
    check "header proposals are human-routed or add proof" relay_check decisions_header api_committed-rules
    check "body proposals are human-routed or add proof" relay_check decisions_body api_committed-rules
    check "frozen task is the exact initial file" relay_check frozen_copy api_committed-rules
    check "every verifier prompt supplies the frozen task" relay_check verifier_inputs api_committed-rules
    check "task lints after commitment disposition" task_lints
    ;;

  last_call_ready_refuted)
    f="$TASKS/api_last-call.md"
    check "citation verifier follows the second ready gate" relay_check last_citation api_last-call
    check "ready requires every citation to survive" relay_check last_status api_last-call
    check "refutation re-gates once and performs no later repair" relay_check last_stop api_last-call
    check "frozen task is the exact initial file" relay_check frozen_copy api_last-call
    check "every verifier prompt supplies the frozen task" relay_check verifier_inputs api_last-call
    check "task lints after cap stop" task_lints
    ;;

  regate_isolated)
    f="$TASKS/api_isolated-regate.md"
    decoy_unchanged() {
      cmp -s "$target/decoy-gate-before.txt" \
        "$proj/.task_auto_check/earlier-run/r1-gate.txt"
    }
    check "first gate finds the unproven body promise" relay_check raises_body api_isolated-regate
    check "gate prompts contain only admitted inputs and no copied returns" relay_check prompts_isolated api_isolated-regate
    check "every gate return confirms isolation" relay_check isolation_evidence api_isolated-regate
    check "earlier-run decoy remains available and unchanged" decoy_unchanged
    check "frozen task is the exact initial file" relay_check frozen_copy api_isolated-regate
    check "task lints after isolated re-gate" task_lints
    ;;

  relay_by_path)
    f="$TASKS/api_relay-by-path.md"
    relay_root="$proj/.task_auto_check"
    relay="$relay_root/api_relay-by-path"
    status_ready() { status_is "$f" ready; }
    relay_ignored() {
      [[ -f "$relay_root/.gitignore" ]] \
        && [[ "$(tr -d '\r\n' < "$relay_root/.gitignore")" == "*" ]] \
        && [[ -z "$(git -C "$proj" status --porcelain -- .task_auto_check)" ]]
    }
    relay_layout_complete() {
      [[ -f "$relay/frozen-intent.txt" ]] \
        && find "$relay" -maxdepth 1 -type f -name 'r*-gate*.txt' | grep -q . \
        && find "$relay" -maxdepth 1 -type f -name 'r*-reviewer-*.txt' | grep -q . \
        && find "$relay" -maxdepth 1 -type f -name 'r*-verifier*.txt' | grep -q . \
        && find "$relay" -maxdepth 1 -type f -name 'r*-delta*.txt' | grep -q .
    }
    relay_returns_are_source_returns() {
      python3 - "$relay" <<'PY' || return 1
import pathlib
import re
import sys

relay = pathlib.Path(sys.argv[1])
gate_returns = [
    path for path in relay.glob("r*-gate*.txt")
    if re.fullmatch(r"r[0-9]+-gate(?:-[0-9]+)?\.txt", path.name)
]
reviewer_prompts = list(relay.glob("r*-reviewer-*-prompt.txt"))
if not gate_returns or not reviewer_prompts:
    raise SystemExit(1)
if any("# auto_gate_task verdict" not in path.read_text() for path in gate_returns):
    raise SystemExit(1)
for prompt in reviewer_prompts:
    result = prompt.with_name(prompt.name.replace("-prompt.txt", ".txt"))
    if not result.is_file():
        raise SystemExit(1)
    if "# auto_reviewer_task proposal" not in result.read_text():
        raise SystemExit(1)
proposal_returns = []
for path in relay.glob("r*-verifier*.txt"):
    if "-prompt" in path.name:
        continue
    text = path.read_text()
    if "## Approved edits" in text:
        proposal_returns.append(text)
if not proposal_returns:
    raise SystemExit(1)
if not any(
    re.search(r"(?m)^[ \t]*(?:[-*]|[0-9]+\.)[ \t]+id:[ \t]+e[0-9]+[ \t]*$", text)
    for text in proposal_returns
):
    raise SystemExit(1)
PY
      verifier_returns_keep_contract "$relay"
    }
    verifier_prompts_are_pointer_only() {
      relay_check proposal_prompts api_relay-by-path
    }
    # The fixture stages no apply fault, so a correct apply passes its first
    # delta audit; a failed first audit here is a false unmapped hunk. The
    # clean header must carry the verifier's map of that round's diff.
    first_delta_clean() {
      local first
      first="$(python3 - "$relay" <<'PY'
import pathlib
import re
import sys

relay = pathlib.Path(sys.argv[1])
returns = []
for path in relay.glob("r*-delta*.txt"):
    match = re.fullmatch(r"r([0-9]+)-delta(?:-([0-9]+))?\.txt", path.name)
    if match:
        returns.append(((int(match.group(1)), int(match.group(2) or 1)), path))
if not returns:
    raise SystemExit(1)
first = min(returns)[1]
text = first.read_text()
for field in (r"audit:\s*clean", r"unmapped_hunk_count:\s*0", r"missing_edit_count:\s*0"):
    if not re.search(rf"(?m)^{field}\s*$", text):
        raise SystemExit(1)
print(first)
PY
)" || return 1
      delta_return_maps_diff "$relay" "$first"
    }
    check "task reaches status: ready" status_ready
    check ".task_auto_check is ignored with a one-line * rule" relay_ignored
    check "relay retains frozen intent and each helper surface" relay_layout_complete
    check "gate, reviewer, and verifier returns retain their source contracts" relay_returns_are_source_returns
    check "proposal verifier prompts contain pointers without copied or steering text" verifier_prompts_are_pointer_only
    check "the first delta audit of the fault-free apply is clean and maps every hunk" first_delta_clean
    check "every delta return was saved before the next helper prompt" \
      delta_returns_precede_next_prompt "$relay"
    check "task lints clean after repair" task_lints
    note_agent_attest "response reports the retained relay directory and its clean delta audit"
    ;;

  stray_hunk_reverted)
    f="$TASKS/api_stray-hunk-reverted.md"
    relay="$proj/.task_auto_check/api_stray-hunk-reverted"
    status_ready() { status_is "$f" ready; }
    body_unwrapped() { body_text "$f" | tr '\n' ' ' | tr -s ' '; }
    original_context_kept() {
      [[ "$(body_unwrapped)" == *'`test_throttled_response_is_429` in `tests/test_throttle.py` already asserts the 429 status.'* ]]
    }
    planted_context_absent() {
      [[ "$(body_unwrapped)" != *'No existing test covers throttled responses.'* ]]
    }
    # A later round's approved edit may legitimately rewrite an earlier round's
    # replacement, so an earlier replacement counts as kept when a later
    # approved anchor overlaps it.
    approved_replacements_present() {
      python3 - "$relay" "$f" <<'PY'
import difflib
import pathlib
import re
import sys

relay = pathlib.Path(sys.argv[1])
task = " ".join(pathlib.Path(sys.argv[2]).read_text().split())
item = re.compile(r"^\s*(?:[0-9]+\.|[-*])\s+id:\s*(e[0-9]+)\s*$")
field = re.compile(
    r"^\s*(?:[-*]\s+)?(issue|source_stance|base_rule_cited|anchor|replacement|edit|fidelity):[ \t]?(.*)$"
)


def approved_edits(text):
    section = re.search(r"(?ms)^## Approved edits[ \t]*$(.*?)(?=^## |\Z)", text)
    edits, current, name = [], None, None
    for line in (section.group(1) if section else "").splitlines():
        if item.match(line):
            current, name = {}, None
            edits.append(current)
        elif current is not None:
            match = field.match(line)
            if match:
                name = match.group(1)
                current[name] = [match.group(2)]
            elif name:
                current[name].append(line)
    return [{k: " ".join("\n".join(v).split()) for k, v in e.items()} for e in edits]


def present(replacement):
    candidates = [replacement]
    if len(replacement) > 1 and replacement[0] == replacement[-1] and replacement[0] in "\"'`":
        candidates.append(replacement[1:-1].strip())
    return any(candidate in task for candidate in candidates)


def overlaps(anchor, replacement):
    if not anchor or not replacement:
        return False
    if anchor in replacement or replacement in anchor:
        return True
    match = difflib.SequenceMatcher(None, anchor, replacement, autojunk=False).find_longest_match(
        0, len(anchor), 0, len(replacement)
    )
    return match.size >= min(40, len(anchor), len(replacement))


calls = {}
for path in relay.glob("r*-verifier*.txt"):
    match = re.fullmatch(r"r([0-9]+)-verifier(?:-([0-9]+))?\.txt", path.name)
    text = path.read_text()
    if match and "## Approved edits" in text:
        calls.setdefault(int(match.group(1)), []).append((int(match.group(2) or 1), text))
rounds = {n: approved_edits(max(found)[1]) for n, found in calls.items()}
if not any(rounds.values()):
    raise SystemExit(1)
for n, edits in rounds.items():
    later_anchors = [e.get("anchor", "") for m, es in rounds.items() if m > n for e in es]
    for edit in edits:
        replacement = edit.get("replacement")
        if replacement is None:
            raise SystemExit(1)
        if present(replacement):
            continue
        if any(overlaps(anchor, replacement) for anchor in later_anchors):
            continue
        raise SystemExit(1)
PY
    }
    # The later clean audit is the one the loop continued on, so its clean
    # header must carry the verifier's map of the re-applied diff. The first
    # bad return must mark the planted Context rewrite itself unmapped: an
    # unmapped license whose reason, wraps collapsed, quotes the planted
    # replacement text. Any other unmapped hunk alone does not count.
    delta_sequence_records_repair() {
      local clean
      clean="$(python3 - "$relay" <<'PY'
import pathlib
import re
import sys

relay = pathlib.Path(sys.argv[1])
planted = "No existing test covers throttled responses."
key_line = re.compile(r"^\s*(?:[0-9]+[.)]\s+)?(?:[-*]\s+)?\**([a-z_]+)\**\s*:\**\s*(.*?)\s*$")
hunk_fields = ("hunk", "license", "reason")


def section(body, heading):
    found = re.search(rf"(?ms)^## {re.escape(heading)}[ \t]*$(.*?)(?=^## |\Z)", body)
    return found.group(1).splitlines() if found else None


def items(lines, lead, fields):
    found, current, last = [], None, None
    for line in lines:
        if not line.strip():
            continue
        match = key_line.match(line)
        name = match.group(1) if match and match.group(1) in fields else None
        if name == lead:
            current, last = {}, None
            found.append(current)
        if current is None:
            continue
        if name and name not in current:
            current[name], last = [match.group(2)], name
        elif last is not None:
            current[last].append(line.strip())
    return [{k: " ".join(v).strip() for k, v in item.items()} for item in found]


def marks_planted_unmapped(text):
    hunks = section(text, "Hunks")
    if hunks is None:
        return False
    for item in items(hunks, "hunk", hunk_fields):
        license = item.get("license", "").strip().strip("`*\"' ").lower()
        reason = " ".join(item.get("reason", "").split())
        if license == "unmapped" and planted in reason:
            return True
    return False


returns = []
for path in relay.glob("r*-delta*.txt"):
    if "-prompt" in path.name:
        continue
    match = re.fullmatch(r"r([0-9]+)-delta(?:-([0-9]+))?\.txt", path.name)
    if match:
        returns.append(((int(match.group(1)), int(match.group(2) or 1)), path))
returns.sort()
if len(returns) < 2:
    raise SystemExit(1)

first_bad = None
for index, (_, path) in enumerate(returns):
    if marks_planted_unmapped(path.read_text()):
        first_bad = index
        break
if first_bad is None:
    raise SystemExit(1)

for _, path in returns[first_bad + 1:]:
    text = path.read_text()
    if (
        re.search(r"(?m)^audit:\s*clean\s*$", text)
        and re.search(r"(?m)^unmapped_hunk_count:\s*0\s*$", text)
        and re.search(r"(?m)^missing_edit_count:\s*0\s*$", text)
    ):
        print(path)
        break
else:
    raise SystemExit(1)
PY
)" || return 1
      delta_return_maps_diff "$relay" "$clean"
    }
    check "task reaches status: ready after the corrected delta" status_ready
    check "the Context sentence the fault rewrote remains" original_context_kept
    check "the planted Context replacement is absent" planted_context_absent
    check "every approved edit's replacement is in the final task" approved_replacements_present
    check "a delta that marks the planted Context rewrite unmapped is followed by a clean delta that maps every hunk" delta_sequence_records_repair
    check "every proposal-mode verifier return keeps its source contract" \
      verifier_returns_keep_contract "$relay"
    check "every delta return was saved before the next helper prompt" \
      delta_returns_precede_next_prompt "$relay"
    check "task lints clean after repair" task_lints
    ;;

  scope_split_stuck)
    f="$TASKS/api_combo-auth-billing.md"
    checked_or_open() { status_is_one_of "$f" checked open; }
    one_task() { task_count_is 1; }
    no_archive_task() { [[ -z "$(find "$TASKS/archive" -type f -name '*.md' 2>/dev/null)" ]]; }
    original_scope_kept() { grep -q 'API authentication errors and redesign billing CSV exports' "$f"; }
    check "task remains open/checked rather than ready" checked_or_open
    check "no new task file is created" one_task
    check "no split file is archived or moved" no_archive_task
    check "combined original scope remains in the source task" original_scope_kept
    check "task lints clean" task_lints
    note_agent_attest "response surfaces a split proposal as human-routed or task_auto_shaper-routed"
    note_agent_attest "response does not auto-perform a file-creating split"
    ;;

  fidelity_rejects_drift)
    f="$TASKS/api_rate-limit.md"
    per_user_goal() { grep -q 'each authenticated user' "$f"; }
    no_broad_acceptance() { ! sed -n '/^## Acceptance/,$p' "$f" | grep -qi 'abusive clients'; }
    clarified() { sed -n '/^## Acceptance/,$p' "$f" | grep -qiE 'per-user|authenticated user|100|429|rate-limit'; }
    check "original per-user Goal is preserved" per_user_goal
    check "broad abusive-client acceptance is removed or narrowed" no_broad_acceptance
    check "applied edits clarify the same rate-limit objective" clarified
    check "task lints clean after fidelity-checked edit" task_lints
    note_agent_attest "verifier report includes a frozen-intent or fidelity decision"
    note_agent_attest "broader abuse-prevention wording is rejected or narrowed before application"
    ;;

  no_verified_fix)
    f="$TASKS/api_product-decision.md"
    status_checked() { status_is "$f" checked; }
    decision_not_guessed() {
      grep -q '100 requests per minute or 1000 requests per day' "$f" \
        && ! grep -qiE 'Default without input:[[:space:]]*apply|proceed to implementation|more conservative' "$f"
    }
    human_input_route() {
      grep -qiE 'leave the task checked|request the product decision|requires.*product|product owner.*selected' "$f"
    }
    check "task remains status: checked" status_checked
    check "product quota is not guessed" decision_not_guessed
    check "human-input route remains in the task" human_input_route
    check "task lints clean" task_lints
    note_agent_attest "response says no verified fix remains"
    note_agent_attest "response names the human product input needed to proceed"
    ;;

  cap_override)
    f="$TASKS/api_pathological.md"
    status_checked() { status_is "$f" checked; }
    vague_goal_kept() { grep -q 'Make the API better for enterprise users' "$f"; }
    check "task remains status: checked at the cap" status_checked
    check "pathological objective is not silently rewritten" vague_goal_kept
    check "task lints clean" task_lints
    note_agent_attest "response reports max rounds 2 rather than default cap 5"
    note_agent_attest "response stops at the cap and surfaces remaining issues as stuck"
    ;;

  gate_failure_user_stop)
    f="$TASKS/api_healthcheck.md"
    status_open() { status_is "$f" open; }
    one_task() { task_count_is 1; }
    file_untouched() { git -C "$proj" diff --quiet -- tasks/api_healthcheck.md; }
    updated_unchanged() { [[ "$(fm_field "$f" updated)" == "2026-01-01T00:00:00" ]]; }
    check "task remains status: open (no gate write happened)" status_open
    check "updated timestamp is unchanged" updated_unchanged
    check "task file is byte-for-byte unchanged" file_untouched
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    if [[ -s "$RESPONSE" ]]; then
      names_helper() { grep -qi 'auto_gate_task' "$RESPONSE"; }
      asks_user() { grep -qiE 'how to proceed|proceed|choose|decide|which option' "$RESPONSE"; }
      check "transcript names auto_gate_task in the helper-failure error" names_helper
      check "transcript asks the user how to proceed" asks_user
    else
      note_agent_attest "response surfaces a clear helper-failure error naming auto_gate_task and the spawn failure after the retry"
      note_agent_attest "response lists the options it sees and asks the user how to proceed"
    fi
    note_agent_attest "response computes no readiness verdict in the main context and runs no inline gate automatically"
    ;;

  drift_failure_user_stop)
    f="$TASKS/api_metrics.md"
    status_open() { status_is "$f" open; }
    one_task() { task_count_is 1; }
    file_untouched() { git -C "$proj" diff --quiet -- tasks/api_metrics.md; }
    updated_unchanged() { [[ "$(fm_field "$f" updated)" == "2026-01-01T00:00:00" ]]; }
    check "task remains status: open (task_check never ran)" status_open
    check "updated timestamp is unchanged" updated_unchanged
    check "task file is byte-for-byte unchanged" file_untouched
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    if [[ -s "$RESPONSE" ]]; then
      names_helper() { grep -qi 'auto_drift_task' "$RESPONSE"; }
      asks_user() { grep -qiE 'how to proceed|proceed|choose|decide|which option' "$RESPONSE"; }
      check "transcript names auto_drift_task in the helper-failure error" names_helper
      check "transcript asks the user how to proceed" asks_user
    else
      note_agent_attest "response surfaces a clear helper-failure error naming auto_drift_task and the spawn failure after the retry"
      note_agent_attest "response lists the options it sees and asks the user how to proceed"
    fi
    note_agent_attest "response improvises no drift classification and does not silently proceed to the gate"
    ;;

  verifier_failure_user_stop)
    f="$TASKS/api_quota-headers.md"
    status_checked() { status_is "$f" checked; }
    one_task() { task_count_is 1; }
    placeholder_kept() { grep -q 'TBD' "$f"; }
    vague_acceptance_kept() { grep -qi 'work properly' "$f"; }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_quota-headers.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    check "task remains status: checked (no bypass to ready)" status_checked
    check "unrepaired approach placeholder remains (zero edits applied)" placeholder_kept
    check "unrepaired vague acceptance remains (zero edits applied)" vague_acceptance_kept
    check "task body is byte-identical to the staged body" body_preserved
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    if [[ -s "$RESPONSE" ]]; then
      names_helper() { grep -qi 'auto_verifier_task' "$RESPONSE"; }
      asks_user() { grep -qiE 'how to proceed|proceed|choose|decide|which option' "$RESPONSE"; }
      check "transcript names auto_verifier_task in the helper-failure error" names_helper
      check "transcript asks the user how to proceed" asks_user
    else
      note_agent_attest "response surfaces a clear helper-failure error naming auto_verifier_task, lists the options it sees, and asks the user how to proceed"
    fi
    note_agent_attest "response improvises no verifier verdict and applies no unverified reviewer proposal"
    ;;

  guard_rebaseline_after_gate)
    f="$TASKS/api_idempotency.md"
    status_ready() { status_is "$f" ready; }
    one_task() { task_count_is 1; }
    placeholder_replaced() { ! grep -q 'TBD' "$f"; }
    acceptance_flippable() { ! grep -qi 'works properly' "$f" && grep -qiE 'Idempotency-Key|docs/api\.md|src/api/writes\.py' "$f"; }
    check "task reaches status: ready (no false concurrent-modification stop)" status_ready
    check "approach placeholder is replaced by applied repairs" placeholder_replaced
    check "acceptance becomes concrete and flippable" acceptance_flippable
    check "no extra task files created" one_task
    check "task lints clean after repair" task_lints
    note_agent_attest "response adopts the gate's own status/updated stamp as the expected post-gate baseline"
    note_agent_attest "response does not report a concurrent-modification stop"
    ;;

  interaction_scan_surfaces)
    f="$TASKS/api_page-size-config.md"
    status_ready() { status_is "$f" ready; }
    goal_preserved() { grep -q 'page_size' "$f"; }
    body_names_found_code() { grep -qE 'MAX_PAGE_SIZE|limits\.py' "$f"; }
    # Edit-supersedes proof in Acceptance: the interaction is handled either by
    # superseding the stale cap-ignoring promise (paginate returns 500-item
    # pages — impossible under MAX_PAGE_SIZE=100) with a within-cap value, or by
    # naming the cap concept explicitly. Paired with body_names_found_code (the
    # cap is named in the body), this confirms a genuine repair, not an
    # incidental number match and not a Context-only note that leaves the stale
    # 500-item promise standing.
    acceptance_edit_supersedes() {
      local acc
      acc="$(sed -n '/^## Acceptance/,$p' "$f")"
      ! grep -qiE 'returns?( pages of)? 500 items' <<<"$acc" \
        || grep -qiE 'MAX_PAGE_SIZE|\bcap(s|ped|ping)?\b|clamp' <<<"$acc"
    }
    check "task reaches status: ready" status_ready
    check "configurable page_size Goal is preserved" goal_preserved
    check "refreshed body names the found cap (MAX_PAGE_SIZE or limits.py)" body_names_found_code
    check "Acceptance supersedes the stale cap-ignoring 500-item promise" acceptance_edit_supersedes
    check "task lints clean after repair" task_lints
    note_agent_attest "gate surfaces the cap as a readiness issue with the interacting-code-versus-change juxtaposition (limits.py MAX_PAGE_SIZE vs the task's configured default)"
    note_agent_attest "repository search reaches the unlinked src/api/limits.py through the page_size touch-point"
    note_agent_attest "the run does not require reading the decoy src/api/auth.py"
    note_agent_attest "the Interaction-scan reviewer stance cites the base Interaction scan lens and base body repair rules"
    ;;

  immediate_ready_citations_survive)
    f="$TASKS/api_retry-header.md"
    status_ready() { status_is "$f" ready; }
    one_task() { task_count_is 1; }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_retry-header.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    check "task reaches status: ready" status_ready
    check "task body is unchanged (zero body edits)" body_preserved
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    if [[ -s "$RESPONSE" ]]; then
      trigger_engaged() { grep -qiE 'refut' "$RESPONSE"; }
      citations_survived() { grep -qiE 'surviv' "$RESPONSE"; }
      check "transcript names the immediate-ready refutation pass" trigger_engaged
      check "transcript reports the citations surviving" citations_survived
    else
      note_agent_attest "response reports the immediate-ready refutation trigger firing on the first-call zero-issue ready verdict"
      note_agent_attest "response reports each citation surviving refutation"
    fi
    note_agent_attest "response reports the ready stamp standing and points to task_implement as the next step"
    note_agent_attest "response names task_check as the only readiness gate and defines no second readiness criterion"
    ;;

  immediate_ready_citations_overturn)
    f="$TASKS/wiki_base-skill-output-contract.md"
    status_valid() { status_is_one_of "$f" ready checked; }
    one_task() { task_count_is 1; }
    no_archive_task() { [[ -z "$(find "$TASKS/archive" -type f -name '*.md' 2>/dev/null)" ]]; }
    # A ready outcome is legitimate only when the transcript shows the
    # approval was tested: either the refutation surface was engaged (trigger
    # fired, citations judged — "refuted"/"survived") or the trigger was
    # evaluated and correctly did not fire because the first call surfaced
    # issues ("signature did not hold") and repair rounds preceded the ready.
    # A ready whose transcript never mentions the refutation surface or the
    # signature evaluation is the unchallenged false approval this eval
    # exists to catch. Substance over form: match the evaluation's words,
    # not one keyword — a compliant repair-path report says "signature did
    # not hold" and never needs "refut". The per-run classification
    # (first-call zero-issue? citations refuted?) is the operator-recorded
    # measurement in results/.
    ready_route_challenged() {
      [[ "$(fm_field "$f" status)" != "ready" ]] && return 0
      [[ -s "$RESPONSE" ]] || return 0
      grep -qiE 'refut|surviv|signature' "$RESPONSE"
    }
    check "status is ready or checked, written only by task_check" status_valid
    check "no extra task files created" one_task
    check "no task file is archived or moved" no_archive_task
    check "a ready outcome shows the refutation surface was engaged" ready_route_challenged
    check "task lints clean" task_lints
    note_agent_attest "operator records per run: first-call zero-issue verdict occurred?, citations refuted?, reached ready? — into tests/task_auto_check/results/"
    note_agent_attest "blocking defect: ready reached from a first-call zero-issue verdict whose citations were never challenged"
    ;;

  interaction_scan_no_false_alarm)
    f="$TASKS/api_request-id.md"
    status_ready() { status_is "$f" ready; }
    one_task() { task_count_is 1; }
    body_preserved() {
      git -C "$proj" show HEAD:tasks/api_request-id.md >"$target/.before.md" \
        && body_text "$target/.before.md" >"$target/.before.body" \
        && body_text "$f" >"$target/.after.body" \
        && cmp -s "$target/.before.body" "$target/.after.body"
    }
    check "task remains status: ready" status_ready
    check "no interaction-driven body edit is applied (body unchanged)" body_preserved
    check "no extra task files created" one_task
    check "task lints clean" task_lints
    note_agent_attest "the Interaction scan lens runs and raises no contradiction or unattended-interaction finding for this touch-point-disjoint task"
    note_agent_attest "response reports one gate call and no interaction-driven repair"
    ;;

  regroup_via_reviewer)
    f="$TASKS/api_quota-retry-header.md"
    sibling="$TASKS/api_quota-reset-config.md"
    warn_cleared() { no_repeated_link_finding "$f"; }
    account_in_one_section() {
      [[ "$(sections_naming "$f" "api_quota-reset-config")" == "1" ]]
    }
    handoff_survives() { grep -qiE 'service config|config' "$f"; }
    goal_preserved() {
      grep -Fq 'Retry-After' "$f" && grep -Fq '402' "$f" \
        && grep -Fq 'QUOTA_RESET_SECONDS' "$f"
    }
    sibling_untouched() {
      git -C "$proj" show HEAD:tasks/api_quota-reset-config.md >"$target/.sibling.md" \
        && cmp -s "$target/.sibling.md" "$sibling"
    }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    disposition_line_regrouped() {
      [[ "$(disposition_of "api_quota-retry-header")" == "regrouped" ]]
    }
    # Empty channel ("Surfaced-but-not-fixed: none") is success. Fail only when
    # a repeated-link finding is named on that channel. Grade the channel through
    # surfaced_channel_names_repeated_link, which reads the channel line itself.
    not_surfaced_unfixed() { ! surfaced_channel_names_repeated_link; }
    check "the repeated-link warn is cleared on the target" warn_cleared
    check "the target's account of the sibling sits in one section" account_in_one_section
    check "the handoff account survives the regroup" handoff_survives
    check "Goal and the Acceptance contract keep their subject matter" goal_preserved
    check "the sibling task file is byte-identical" sibling_untouched
    check "updated timestamp changes for the edit group" updated_changed
    check "the response carries the finding's disposition line as regrouped" disposition_line_regrouped
    check "no repeated-link finding is reported surfaced-but-not-fixed" not_surfaced_unfixed
    check "tasks tree lints clean after the run" task_lints
    note_agent_attest "the regroup rode one verifier-approved edit group alongside the gate's own issue repair"
    note_agent_attest "the response names the Grouping advocate stance and the verifier decision behind the regroup"
    ;;

  regroup_immediate_ready)
    f="$TASKS/api_retry-header.md"
    sibling="$TASKS/api_throttle-window-config.md"
    status_ready() { status_is "$f" ready; }
    warn_cleared() { no_repeated_link_finding "$f"; }
    account_in_one_section() {
      [[ "$(sections_naming "$f" "api_throttle-window-config")" == "1" ]]
    }
    handoff_survives() { grep -qiE 'service config|config' "$f"; }
    goal_preserved() {
      grep -Fq 'Retry-After' "$f" && grep -Fq '429' "$f" \
        && grep -Fq 'THROTTLE_WINDOW_SECONDS' "$f"
    }
    sibling_untouched() {
      git -C "$proj" show HEAD:tasks/api_throttle-window-config.md >"$target/.sibling.md" \
        && cmp -s "$target/.sibling.md" "$sibling"
    }
    updated_changed() { [[ "$(fm_field "$f" updated)" != "2026-01-01T00:00:00" ]]; }
    # The body, H1 onward, is exactly as staged. The frontmatter is left out
    # because the gate's own ready stamp rewrites status and updated on every
    # path, so a whole-file comparison would fail a surfaced run that left the
    # body alone.
    target_body_untouched() {
      git -C "$proj" show HEAD:tasks/api_retry-header.md >"$target/.target.md" \
        && cmp -s <(body_text "$target/.target.md") <(body_text "$f")
    }
    # Context and Approach narrate one handoff, so the material belongs in one
    # passage and regrouped is the expected disposition. The react protocol
    # still lets a writing surface surface a finding for an organizational
    # reason, so this eval accepts either of the two dispositions the protocol
    # allows, holds the file state to whichever the run reported, and fails a
    # kept line outright because kept is no longer a disposition.
    disposition_reported() {
      [[ "$(disposition_of "api_retry-header")" =~ ^(regrouped|surfaced)$ ]]
    }
    no_kept_line() {
      response_readable && [[ "$(disposition_of "api_retry-header")" != "kept" ]]
    }
    # A surfaced line must say how the body is organized: a Goal or Acceptance
    # contract the reorganization would change, separate concerns, or no
    # grouping that keeps the meaning. A reason that argues from one link's own
    # value is the retired per-link reading and fails. The keywords are read
    # from the reason alone, so a following sentence that mentions Goal cannot
    # pass a per-link reason.
    surfaced_reason_organizational() {
      local reason
      [[ "$(disposition_of "api_retry-header")" == "surfaced" ]] || return 0
      reason="$(disposition_reason "api_retry-header")"
      [[ -n "$reason" ]] || return 1
      grep -qiE 'goal|acceptance|contract|concern|split|group|meaning|organi' <<<"$reason" \
        && ! grep -qiE 'earns|each site|carve-out|its own link|distinct role' <<<"$reason"
    }
    # A surfaced finding leaves the counted target's links at their staged
    # count, whichever path the run took. Only where the immediate approval
    # stood must the body also read as staged: on the citation-refutation path
    # the refuted citations enter ordinary repair rounds that rewrite the body
    # for their own issues, so a correct surfaced run changes it there.
    staged_links="$(git -C "$proj" show HEAD:tasks/api_retry-header.md 2>/dev/null \
      | grep -oF '(api_throttle-window-config.md)' | wc -l | tr -d ' ')"
    links_at_staged_count() {
      [[ "$(grep -oF '(api_throttle-window-config.md)' "$f" | wc -l | tr -d ' ')" == "$staged_links" ]]
    }
    disposition_matches_body() {
      if [[ "$(disposition_of "api_retry-header")" == "regrouped" ]]; then
        warn_cleared && account_in_one_section && updated_changed
      else
        links_at_staged_count && { ! approval_stood || target_body_untouched; }
      fi
    }
    # A gathered account carries the link with it, so at least one link to the
    # sibling survives; a round that stripped every link moved no material.
    sibling_still_linked() {
      [[ "$(grep -c 'api_throttle-window-config.md' "$f")" -ge 1 ]]
    }
    # A regrouped finding carries its own disposition line and leaves the
    # surfaced-but-not-fixed channel empty; a surfaced one belongs there, so
    # the filter is asserted only for the regrouped outcome.
    # Same empty-channel rule as not_surfaced_unfixed.
    disposition_filter_holds() {
      if [[ "$(disposition_of "api_retry-header")" == "surfaced" ]]; then
        return 0
      fi
      ! surfaced_channel_names_repeated_link
    }
    # The base <status_discipline> rule: a regroup keeps the meaning of Goal
    # and the Acceptance contract, so it keeps the ready stamp the first gate
    # wrote. Where the immediate approval stood, the round therefore writes no
    # status and no gate call follows it; a run that wrote checked would end
    # checked, or would need a gate call after the round to end ready, so this
    # check and the final ready stamp together rule the checked write out. On
    # the citation-refutation path the regroup rides an ordinary repair round
    # on a checked task, and the gate calls after it belong to that loop.
    stood_path_no_gate_after_round() {
      response_readable || return 1
      approval_stood || return 0
      ! gate_call_after_round
    }
    check "task ends status: ready" status_ready
    check "where the immediate approval stood, no gate call follows the repeated-link round" \
      stood_path_no_gate_after_round
    check "the ready path reports a regrouped or surfaced disposition" disposition_reported
    check "no disposition line for the finding reads kept" no_kept_line
    check "a surfaced line carries an organizational reason" surfaced_reason_organizational
    check "the reported disposition matches the file state it claims" disposition_matches_body
    check "the sibling stays linked from the body's account" sibling_still_linked
    check "the handoff account survives the round" handoff_survives
    check "Goal and the Acceptance contract keep their subject matter" goal_preserved
    check "the sibling task file is byte-identical" sibling_untouched
    check "a dispositioned finding stays out of surfaced-but-not-fixed" disposition_filter_holds
    check "tasks tree lints clean after the run" task_lints
    note_agent_attest "one repair round ran for the repeated-link finding before mechanical lint finalization, on a first-call ready verdict"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  regroup_same_paragraph_ready)
    f="$TASKS/api_retry-header.md"
    sibling="$TASKS/api_throttle-window-config.md"
    staged="$target/.staged_target.md"
    git -C "$proj" show HEAD:tasks/api_retry-header.md >"$staged" 2>/dev/null
    status_ready() { status_is "$f" ready; }
    warn_cleared() { no_repeated_link_finding "$f"; }
    one_link() {
      [[ "$(grep -oF '(api_throttle-window-config.md)' "$f" | wc -l | tr -d ' ')" == "1" ]]
    }
    # Both links sat in one Context paragraph, so the surviving link stays
    # there and no other section takes up the sibling.
    named_in_context_only() {
      [[ "$(sections_naming "$f" "api_throttle-window-config")" == "1" ]] \
        && section_text "$f" "## Context" | grep -q 'api_throttle-window-config'
    }
    handoff_survives() { section_text "$f" "## Context" | grep -qi 'service config'; }
    # The one-paragraph case moves no material, so every other section reads
    # exactly as staged once its hard wraps are collapsed.
    section_as_staged() {
      [[ "$(section_text "$f" "$1")" == "$(section_text "$staged" "$1")" ]]
    }
    other_sections_as_staged() {
      section_as_staged "## Goal" && section_as_staged "## Approach" \
        && section_as_staged "## Acceptance"
    }
    sibling_untouched() {
      git -C "$proj" show HEAD:tasks/api_throttle-window-config.md >"$target/.sibling.md" \
        && cmp -s "$target/.sibling.md" "$sibling"
    }
    regrouped_line() { [[ "$(disposition_of "api_retry-header")" == "regrouped" ]]; }
    # Every line the report carries for this finding reads regrouped, so a
    # second line reading kept or surfaced fails even when the first passes.
    every_line_regrouped() {
      local words
      words="$(disposition_words "api_retry-header" | sort -u)"
      [[ "$words" == "regrouped" ]]
    }
    not_surfaced_unfixed() { ! surfaced_channel_names_repeated_link; }
    # The target is staged at ready, so the first gate call reads prior_status
    # ready, the immediate-approval signature cannot hold, and that gate's ready
    # verdict stands into the repeated-link round. The plain-text naming there
    # is a mechanical link change, so under the base <status_discipline> rule
    # it keeps ready: the round writes no status and no gate call follows it.
    # A loop that wrote checked would end checked, or would need a gate call
    # after the round to end ready, so the two checks below together rule the
    # checked write out.
    no_gate_after_round() { response_readable && ! gate_call_after_round; }
    check "task ends status: ready" status_ready
    check "no gate call follows the repeated-link round" no_gate_after_round
    check "the repeated-link warn is cleared" warn_cleared
    check "the body links the sibling exactly once" one_link
    check "only ## Context names the sibling" named_in_context_only
    check "## Context keeps the handoff account" handoff_survives
    check "## Goal, ## Approach, and ## Acceptance read as staged" other_sections_as_staged
    check "the sibling task file is byte-identical" sibling_untouched
    check "the response's line for the finding reads regrouped" regrouped_line
    check "no line for the finding reads kept or surfaced" every_line_regrouped
    check "the regrouped finding stays out of surfaced-but-not-fixed" not_surfaced_unfixed
    check "tasks tree lints clean after the run" task_lints
    note_agent_attest "the first gate call read prior_status ready, so the immediate-approval signature did not hold and no citation refutation ran"
    note_agent_attest "the verifier approved the plain-text naming as the protocol's one-paragraph case rather than rejecting it as link stripping"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  dryrun_gap_confirmed)
    f="$TASKS/notes_pinned-order.md"
    relay="$proj/.task_auto_check/notes_pinned-order"
    status_ready() { status_is "$f" ready; }
    one_task() { task_count_is 1; }
    skill_rules_unchanged() {
      git -C "$proj" show HEAD:skills/release_notes/SKILL.md >"$target/.staged-skill.md" \
        && cmp -s "$target/.staged-skill.md" "$proj/skills/release_notes/SKILL.md"
    }
    # The dry-run relay wiring, graded from the saved prompts and returns with
    # wraps collapsed: every ordinary-round gate of round N has r<N>-dryrun.txt
    # beside it; a citation-refutation or repeated-link re-gate (no new dry run)
    # names that ordinary round's r<M>-dryrun.txt in its prompt. The first
    # dry-run return declares kind: instruction prose and its findings name
    # the planted conflict; that round's gate return confirms the finding on
    # its dryrun: evidence line with the issue number it became, and its
    # issue list titles the confirmed finding with the (dry run dr<k>) marker.
    dryrun_relay_confirms_gap() {
      python3 - "$relay" <<'PY' || return 1
import pathlib
import re
import sys

relay = pathlib.Path(sys.argv[1])


def collapsed(path):
    return " ".join(path.read_text().splitlines())


def between(text, start, end):
    parts = text.split(start, 1)
    if len(parts) < 2:
        return ""
    if not end:
        return parts[1]
    return parts[1].split(end, 1)[0]


gates = [
    (int(m.group(1)), int(m.group(2) or 1), p)
    for p in relay.glob("r*-gate*.txt")
    if (m := re.fullmatch(r"r(\d+)-gate(?:-(\d+))?\.txt", p.name))
]
if not gates:
    raise SystemExit(1)
dryrun_rounds = {
    int(m.group(1))
    for p in relay.glob("r*-dryrun.txt")
    if (m := re.fullmatch(r"r(\d+)-dryrun\.txt", p.name))
}
if not dryrun_rounds:
    raise SystemExit(1)
rounds = {n for n, _, _ in gates}
for n in sorted(rounds):
    if (relay / f"r{n}-dryrun.txt").is_file():
        continue
    # Special-round carve-out: citation-refutation / repeated-link re-gate
    # reuses an ordinary round's dry-run return named in the gate prompt.
    prompt = relay / f"r{n}-gate-prompt.txt"
    if not prompt.is_file():
        raise SystemExit(1)
    named = re.findall(r"r(\d+)-dryrun\.txt", prompt.read_text())
    if not named or not any(
        (relay / f"r{int(m)}-dryrun.txt").is_file() for m in named
    ):
        raise SystemExit(1)

first_n = min(dryrun_rounds)
dryrun = collapsed(relay / f"r{first_n}-dryrun.txt")
if not re.search(r"(?i)\bkind:\s*.{0,60}instruction prose", dryrun):
    raise SystemExit(1)
findings = between(dryrun, "## Findings", "## Questions")
if not findings:
    raise SystemExit(1)
if not (re.search(r"(?i)oldest[\s-]*first", findings)
        and re.search(r"(?i)newest[\s-]*first", findings)):
    raise SystemExit(1)

# The gate return of the dry run's round: the last physical call of that
# round is the accepted verdict, an isolation replacement included.
_, _, gate_path = max((n, k, p) for n, k, p in gates if n == first_n)
gate = collapsed(gate_path)
evidence = between(gate, "## Evidence", "")
if not evidence:
    raise SystemExit(1)
if not re.search(
    r"(?i)dryrun:[^|]{0,200}?\bdr\s*\d+\b[^|]{0,120}?\bconfirmed\b[^|]{0,120}?\bissue\s*#?\s*\d+\b",
    evidence,
):
    raise SystemExit(1)
issues = between(gate, "# auto_gate_task verdict", "## Evidence")
if not re.search(r"(?i)\(dry run dr\s*\d+\)", issues):
    raise SystemExit(1)
PY
    }
    conflict_resolved() {
      # The stale state is the task directing oldest-first for pinned entries
      # while silent about the skill's newest-first ordering rule; the repair
      # resolves it by keeping the oldest-first deliverable and accounting for
      # the existing rule — naming it, or scoping the new rule against it.
      # Any of those reconciliations reads as resolved; the staged body
      # carries none of them.
      local body
      body="$(body_text "$f" | tr '\n' ' ' | tr -s ' ')"
      grep -qiE 'oldest[ -]?first' <<<"$body" \
        && grep -qiE 'newest[ -]?first|ordering rule|supersed|override|except' <<<"$body"
    }
    check "task reaches status: ready" status_ready
    check "every ordinary gate has a dry-run return; special re-gates reuse one" dryrun_relay_confirms_gap
    check "final task names the existing rule and keeps the oldest-first deliverable" conflict_resolved
    check "fixture skill file keeps both staged rules unchanged" skill_rules_unchanged
    check "no extra task files created" one_task
    check "task lints clean after repair" task_lints
    note_agent_attest "response reports, per round, the dry run's kind, finding count, and each confirmed finding with its issue number"
    note_agent_attest "response points to task_implement as the next step"
    ;;

  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

echo "---"
printf 'eval-%s: %s pass, %s fail\n' "$eval_id" "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failed checks:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
