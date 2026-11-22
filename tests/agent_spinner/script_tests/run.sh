#!/usr/bin/env bash
# script_tests/run.sh — static contract checks for agent_spinner.
#
# agent_spinner ships one bundled program, scripts/run_ledger.py, so this
# surface covers the filesystem and grep acceptance items: frontmatter and the
# description check, one block per named contract, the six shape tags and their four
# elements, the per-harness-fact greps that must stay empty, the reference set,
# the ledger's stdlib-only and read-only-git contract, the trigger eval set,
# and registration lockstep.
#
# The behavioural items live in evals/, driven by evals/run.py. The ledger's
# own scenarios live in script_tests/ledger_run.sh.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_dev/skills/agent_spinner"
SKILL="$SKILL_DIR/SKILL.md"
REFS="$SKILL_DIR/references"
CHECKS="$REFS/checks.md"
ROLE_PROMPTS="$REFS/role-prompts.md"
SCRIPTS="$SKILL_DIR/scripts"
LEDGER="$SCRIPTS/run_ledger.py"
AGENTS_DIR="$REPO_ROOT/plugins/ai_dev/agents"
CHECKER_ROLE="$AGENTS_DIR/auto_checker_spinner.md"
WRITER_ROLE="$AGENTS_DIR/auto_writer_spinner.md"
PSEUDO_XML_LINTER="$REPO_ROOT/plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py"
SCRATCH="$HERE/scratch"
TRIGGERS="$REPO_ROOT/tests/trigger_evals/agent_spinner.json"

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

file_has() { grep -Eq "$2" "$1"; }

# section_has <file> <tag> <pattern> — match inside one pseudo-XML block, so a
# pin proves the rule landed in the section that owns it.
section_block() {
  awk -v tag="$2" '
    index($0, "<" tag ">") { inside = 1 }
    inside                 { print }
    index($0, "</" tag ">") { inside = 0 }
  ' "$1"
}

section_has() { section_block "$1" "$2" | grep -Eq "$3"; }

# collapsed_has <pattern> — read a block on stdin and collapse the line breaks
# a paragraph wraps at, so a pin matches the prose phrase rather than one
# particular wrap.
collapsed_has() {
  tr '\n' ' ' | tr -s '[:space:]' ' ' | grep -Eq "$1"
}

section_has_collapsed() { section_block "$1" "$2" | collapsed_has "$3"; }

# heading_block <file> <heading> — one `## heading` section up to the next
# heading, so a pin reads the template that owns the rule.
heading_block() {
  awk -v h="## $2" '
    $0 == h                { inside = 1; next }
    inside && /^## /       { inside = 0 }
    inside                 { print }
  ' "$1"
}

heading_block_has_collapsed() { heading_block "$1" "$2" | collapsed_has "$3"; }

# checks_c2_block <checks.md> — the C2 section alone.
checks_c2_block() {
  awk '
    /^## C2\. /                                { inside = 1 }
    inside && /^## C[0-9]+\. / && !/^## C2\. / { inside = 0 }
    inside                                     { print }
  ' "$1"
}

c2_has_collapsed() { checks_c2_block "$1" | collapsed_has "$2"; }

# c2_item <checks.md> <number> — one numbered step of C2, so a pin reads the
# item that owns the rule rather than the whole check.
c2_item() {
  awk -v n="$2" '
    /^## C2\. /                    { inside = 1; next }
    inside && /^## C[0-9]+\. /     { inside = 0 }
    inside && $0 ~ ("^" n "\\.")   { item = 1; print; next }
    inside && item && /^[0-9]+\./  { item = 0 }
    inside && item                 { print }
  ' "$1"
}

c2_item_has() { c2_item "$1" "$2" | grep -Eq "$3"; }
c2_item_has_collapsed() { c2_item "$1" "$2" | collapsed_has "$3"; }

description_under() {
  python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
fm = re.search(r"^---\n(.*?)\n---", text, re.S).group(1)
desc = re.search(r"^description: (.*?)(?=\n[a-z-]+:)", fm, re.S | re.M).group(1).strip()
sys.exit(0 if len(desc) < int(sys.argv[2]) else 1)
PY
}

description_has() {
  python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
fm = re.search(r"^---\n(.*?)\n---", text, re.S).group(1)
desc = re.search(r"^description: (.*?)(?=\n[a-z-]+:)", fm, re.S | re.M).group(1)
sys.exit(0 if re.search(sys.argv[2], desc, re.I) else 1)
PY
}

# tree_lacks <dir> <pattern> — the grep acceptance items, which pass by
# returning nothing across the skill and its references alike.
tree_lacks() { ! grep -REiq "$2" "$1"; }

# product_hits_cite_portability <dir> — every line naming a target product
# also names harness_portability. Zero product hits satisfies it vacuously,
# which is the shape the skill actually ships in.
product_hits_cite_portability() {
  local dir="$1" hits
  hits="$(grep -REin 'claude|codex|cursor|antigravity|opencode|copilot|gemini|anthropic|openai' "$dir" || true)"
  [[ -z "$hits" ]] && return 0
  ! printf '%s\n' "$hits" | grep -qv 'harness_portability'
}

not() { ! "$@"; }

# --- helper role definitions ------------------------------------------------
#
# The two generic roles are prose-only bodies whose first line reads the brief
# the orchestrator rendered. They carry no agent_spinner doctrine of their own,
# so these checks pin their frontmatter levers and their exact body.

CHECKER_BODY="Read the brief file your prompt names, in full, and follow it.
Work read-only: change no file, and run no command that writes, even where a shell stays callable.
Return exactly as that brief's closing block says.
If that file is missing or unreadable, reply with one line naming its path, and stop."
WRITER_BODY="Read the brief file your prompt names, in full, and follow it.
Return exactly as that brief's closing block says.
If that file is missing or unreadable, reply with one line naming its path, and stop."

# role_name_matches_stem <file> — the frontmatter name equals the file stem and
# carries the owner-approved spinner token, not the derived agent token.
role_name_matches_stem() {
  local file="$1" stem name
  stem="$(basename "$file" .md)"
  name="$(sed -n 's/^name:[[:space:]]*//p' "$file" | head -1)"
  [[ "$name" == "$stem" ]] && [[ "$name" =~ ^auto_(checker|writer)_spinner$ ]]
}

# role_body_is <file> <expected-body> — the body's non-blank lines are exactly
# the sentences the role owns, in order.
role_body_is() {
  local file="$1" expected="$2" got
  got="$(awk 'BEGIN { fm = 0; body = 0 }
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; body = 1; next }
    body && NF { print }' "$file")"
  [[ "$got" == "$expected" ]]
}

# checker_readonly_lever <file> — readonly: true plus a tools list of read and
# search tools only.
checker_readonly_lever() {
  local file="$1" tools
  grep -qx 'readonly: true' "$file" || return 1
  tools="$(sed -n 's/^tools:[[:space:]]*//p' "$file" | head -1)"
  [[ -n "$tools" ]] || return 1
  printf '%s\n' "$tools" | grep -Eiq '\b(Read|Grep|Glob)\b' || return 1
  ! printf '%s\n' "$tools" | grep -Eiq '\b(Write|Edit|MultiEdit|NotebookEdit|Bash|Shell|Task|WebFetch)\b'
}

writer_has_no_readonly_lever() {
  ! grep -Eq '^readonly:[[:space:]]*true' "$1"
}

writer_has_no_tools_or_effort() {
  ! grep -Eq '^(tools|effort|model_reasoning_effort):' "$1"
}

# role_lint_clean_file <file>... — the pseudo-XML linter reports no issue. Its
# exit status stays 0 for warnings, so the check reads the reported issues.
role_lint_clean_file() {
  local out
  out="$(python3 "$PSEUDO_XML_LINTER" "$@" 2>&1)" || return 1
  ! printf '%s\n' "$out" | grep -Eq 'Issues: [1-9]|^[[:space:]]*! '
}

# start_here_first_step_is_status <skill.md> — the new opening block's first
# numbered step must run the ledger's status, so an open run is found before
# anything else happens.
start_here_first_step_is_status() {
  awk '/^<start_here>/{inside=1} inside{print} /^<\/start_here>/{inside=0}' "$1" \
    | grep -Eq '^1\..*`status`'
}

# ledger_paths_qualified <skill_dir> — every mention of run_ledger.py in
# SKILL.md or references/ must be the skill-relative form. A bare
# `scripts/run_ledger.py` resolves against the working root, not the skill, and
# finds the wrong file or nothing.
ledger_paths_qualified() {
  local dir="$1" total qualified
  total="$(grep -Ro 'run_ledger\.py' "$dir/SKILL.md" "$dir/references" 2>/dev/null | wc -l | tr -d ' ')"
  qualified="$(grep -Ro '<skill dir>/scripts/run_ledger\.py' "$dir/SKILL.md" "$dir/references" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$total" -eq "$qualified" ]]
}

scripts_exactly_ledger() {
  [[ -d "$1" ]] && [[ "$(ls -1A "$1")" == "run_ledger.py" ]]
}

# selector_recipe_rows_match <skill.md> <recipes dir> — the selector's recipe
# table names each recipe file once, every named file exists under the recipes
# directory, and every *.md there has exactly one row. An empty table with no
# recipes directory passes, which is the state until the recipe tasks land.
selector_recipe_rows_match() {
  local skill="$1" dir="$2" name f count uniq
  local -a files=()
  local cells
  # Start at the line-start opening tag so the inline `<selector>` citation in
  # <start_here> stays out of the scan.
  cells="$(awk '
    /^<selector>$/ { inside = 1 }
    inside { print }
    /^<\/selector>$/ { inside = 0 }
  ' "$skill" | awk -F'|' '
    /^[[:space:]]*\|/ {
      cell = $3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
      if (cell == "" || cell ~ /^-+$/ || cell ~ /Recipe in/) next
      print cell
    }')"
  if [[ -n "$cells" ]]; then
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      files+=("$name")
    done < <(printf '%s\n' "$cells" | grep -oE '`[^`]+\.md`' | tr -d '`')
  fi
  if (( ${#files[@]} > 0 )); then
    uniq="$(printf '%s\n' "${files[@]}" | sort -u | grep -c .)"
    [[ "$uniq" -eq "${#files[@]}" ]] || return 1
    for name in "${files[@]}"; do
      [[ -f "$dir/$name" ]] || return 1
    done
  fi
  if [[ -d "$dir" ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      count=0
      if (( ${#files[@]} > 0 )); then
        for name in "${files[@]}"; do
          [[ "$name" == "$f" ]] && count=$((count + 1))
        done
      fi
      [[ "$count" -eq 1 ]] || return 1
    done < <(find "$dir" -maxdepth 1 -type f -name '*.md' -exec basename {} \; 2>/dev/null)
  fi
  return 0
}

# checks_sections_in_order <checks.md> — the ten C1..C10 headings, in order,
# each one exactly once, so a missing or reordered check fails.
checks_sections_in_order() {
  local file="$1" seq
  [[ -f "$file" ]] || return 1
  seq="$(grep -E '^## C[0-9]+\. ' "$file" \
    | sed -E 's/^## C([0-9]+)\..*/\1/' | tr '\n' ' ')"
  [[ "$seq" == "1 2 3 4 5 6 7 8 9 10 " ]]
}

# role_prompt_headings_present <role-prompts.md> — the four kept pass
# templates plus the four added ones and the access and closing blocks.
role_prompt_headings_present() {
  local file="$1" heading
  [[ -f "$file" ]] || return 1
  for heading in \
    'Producing pass' 'Lens pass' 'Checking pass' 'Synthesis pass' \
    'Remediation pass' 'Critic pass' 'Judge pass' 'Validator pass' \
    'Access block' 'Closing block'; do
    grep -qx "## $heading" "$file" || return 1
  done
}

# closing_block_checklist_fields <role-prompts.md> — the closing block's
# `checklist` entry names exactly `verdict` and `span`, the two fields the
# ledger's rendered block and validate_return use, and names no `n`.
closing_block_checklist_fields() {
  local file="$1" fields tokens
  [[ -f "$file" ]] || return 1
  fields="$(awk '
    /^## Closing block$/ { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$file" | tr '\n' ' ' | sed -n 's/.*`checklist` with \([^;]*\);.*/\1/p')"
  [[ -n "$fields" ]] || return 1
  tokens="$(printf '%s\n' "$fields" | sed 's/([^)]*)//g' | grep -oE '`[^`]+`' | tr -d '`' | sort -u | tr '\n' ' ')"
  [[ "$tokens" == "span verdict " ]] || return 1
  ! printf '%s\n' "$fields" | grep -Eq '`n`'
}

# closing_block_forks_fields <role-prompts.md> — the closing block's `forks`
# entry names `issue`, `options`, `preferred`, and `passages`, the four fields
# the ledger's rendered block and validate_return use.
closing_block_forks_fields() {
  local file="$1" fields
  [[ -f "$file" ]] || return 1
  fields="$(awk '
    /^## Closing block$/ { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$file" | tr '\n' ' ' | sed -n 's/.*`forks` with \([^;]*\);.*/\1/p')"
  [[ -n "$fields" ]] || return 1
  for field in issue options preferred passages; do
    printf '%s\n' "$fields" | grep -q "\`$field\`" || return 1
  done
}

# opening_sentence_sites_ok <skill dir> — every passage in SKILL.md and
# references/ that contains the phrase "opening sentence" carries all four
# report facts (the tokens `answer`, `tier`, `dispatched`, `returned`, and
# `exited`), or the literal `<reporting>` pointer, or is the pre-dispatch
# announcement — the `<degradation>` block or the Probe step of
# degradation-examples.md — naming the tier and none of answer, dispatched, or
# exited. It prints each matched site by file and line, so a site added later
# shows up as a named failure rather than being skipped.
opening_sentence_sites_ok() {
  python3 - "$1" <<'PY'
import os
import re
import sys

root = sys.argv[1]
files = [os.path.join(root, "SKILL.md")]
refs = os.path.join(root, "references")
for dirpath, _, names in os.walk(refs):
    for name in names:
        if name.endswith(".md"):
            files.append(os.path.join(dirpath, name))
files.sort()

PARAGRAPH = re.compile(r"(?:[^\n]|\n(?!\s*\n))+")
FACTS = ("answer", "tier", "dispatched", "returned", "exited")


def paragraphs(text):
    for match in PARAGRAPH.finditer(text):
        chunk = match.group(0)
        if chunk.strip():
            yield text.count("\n", 0, match.start()) + 1, chunk


def block_paragraphs(text, tag):
    body = re.search(r"^<%s>\n(.*?)^</%s>" % (tag, tag), text, re.M | re.S)
    if not body:
        return set()
    return {chunk.strip() for _, chunk in paragraphs(body.group(1))}


failures = []
sites = 0
for path in files:
    rel = os.path.relpath(path, root)
    text = open(path, encoding="utf-8").read()
    announcement = set()
    if rel == "SKILL.md":
        announcement = block_paragraphs(text, "degradation")
    elif rel == os.path.join("references", "degradation-examples.md"):
        announcement = {
            chunk.strip()
            for _, chunk in paragraphs(text)
            if re.match(r"^\s*[0-9]+\.\s+\*\*Probe\.\*\*", chunk)
        }
    for line, chunk in paragraphs(text):
        low = chunk.lower()
        if "opening sentence" not in low:
            continue
        sites += 1
        stripped = chunk.strip()
        phrase = " ".join(stripped.split())
        index = phrase.lower().find("opening sentence")
        phrase = phrase[max(0, index - 20):index + 40]
        carries = all(token in low for token in FACTS)
        pointer = "<reporting>" in chunk
        tier_only = (
            stripped in announcement
            and any(token in low for token in ("tier", "inline floor", "spawned roles"))
            and not any(token in low for token in ("answer", "dispatched", "exited"))
        )
        if carries or pointer or tier_only:
            print("  site %s:%d \"%s\" ok" % (rel, line, phrase))
        else:
            print(
                "  site %s:%d \"%s\" carries none of the four facts, no "
                "<reporting> pointer, and is no tier-only announcement"
                % (rel, line, phrase)
            )
            failures.append("%s:%d" % (rel, line))
if not sites:
    print("  no passage carries the phrase 'opening sentence'")
    failures.append("no site")
sys.exit(1 if failures else 0)
PY
}

# p6_check_carries_opening_facts <run-protocol.md> — P6's self-check names all
# four report facts in the opening sentence.
p6_check_carries_opening_facts() {
  python3 - "$1" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"^\*\*Checks\.\*\* Every finding.*?(?=\n\n)", text, re.M | re.S)
if not match:
    sys.exit(1)
low = match.group(0).lower()
sys.exit(0 if all(t in low for t in ("answer", "tier", "dispatched", "returned", "exited")) else 1)
PY
}

# stop_template_first_sentence_facts <report-shapes.md> — every stop-report
# template opens with one sentence carrying the answer, the tier, helpers
# dispatched against returned, and the close exit.
stop_template_first_sentence_facts() {
  python3 - "$1" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
sentences = []
for block in re.findall(r"```text\n(.*?)```", text, re.S):
    stripped = block.strip()
    if not stripped.startswith("Stopped"):
        continue
    sentences.append(re.split(r"(?<=\.)\s", stripped, maxsplit=1)[0].lower())
if not sentences:
    sys.exit(1)
need = ("dispatched", "returned", "exited")
ok = all(
    all(token in sentence for token in need)
    and re.search(r"tier|inline floor|spawned roles", sentence)
    and re.search(r"answer|stopped|verdict", sentence)
    for sentence in sentences
)
sys.exit(0 if ok else 1)
PY
}

# degradation_states_tier_only <skill.md> — the <degradation> block states the
# tier for the pre-dispatch announcement, and names no close exit, no
# dispatched-against-returned count, and no answer.
degradation_states_tier_only() {
  python3 - "$1" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"^<degradation>\n(.*?)^</degradation>", text, re.M | re.S)
if not match:
    sys.exit(1)
low = match.group(1).lower()
tier = any(token in low for token in ("tier", "inline floor", "spawned roles"))
banned = any(token in low for token in ("answer", "dispatched", "exited"))
sys.exit(0 if tier and not banned else 1)
PY
}

# fork_contract_requires_passages <run-protocol.md> — P3's fork rejection
# bullet and the `forks` bullet of `### Return contract` each require an
# anchored `passages` entry, neither states it as optional, and the pre-change
# sentence is gone.
fork_contract_requires_passages() {
  python3 - "$1" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
p3 = re.search(r"^- A fork that is not an object.*?(?=\n- |\n\n)", text, re.M | re.S)
contract = re.search(r"^- `forks` is a list.*?(?=\n- |\n\n)", text, re.M | re.S)
if not p3 or not contract:
    sys.exit(1)
problems = []
for name, match in (
    ("P3 fork rejection bullet", p3),
    ("Return-contract forks bullet", contract),
):
    entry = match.group(0)
    if "`passages`" not in entry:
        problems.append("%s names no `passages`" % name)
    if "`anchor`" not in entry:
        problems.append("%s names no `anchor`" % name)
    if re.search(r"may also carry|optional", entry, re.I):
        problems.append("%s states `passages` as optional" % name)
if "A fork may also carry `passages`" in text:
    problems.append("the pre-change optional sentence survives")
for line in problems:
    sys.stderr.write(line + "\n")
sys.exit(1 if problems else 0)
PY
}

# references_cite_no_step_number <references dir> — a run-protocol step is
# cited by its P label alone, never by a step number that a later edit to
# run-protocol.md can renumber out from under it.
references_cite_no_step_number() {
  ! grep -REq 'P[1-6] step [0-9]' "$1"
}

# aggregation_block <skill.md> — the <aggregation> block alone, so a pin reads
# the section that owns the rule rather than the whole body.
aggregation_block() {
  awk '
    /^<aggregation>$/ { inside = 1 }
    inside            { print }
    /^<\/aggregation>$/ { inside = 0 }
  ' "$1"
}

# aggregation_show_list_correct <skill.md> — the block's `show` read set names
# `alternatives` among the record types the ledger imports, names the
# `dispose --flag` channel that marks a roster row for condition 9, and carries
# none of the retired show targets (`contradictions`) that the ledger imports no
# record type for. `beyond-brief finds` is a real record type now, so it stays
# out of the retired list.
aggregation_show_list_correct() {
  local block clause
  block="$(aggregation_block "$1")"
  [[ -n "$block" ]] || return 1
  # The first sentence that sends the orchestrator through `show`, so
  # `alternatives` has to sit in the read set itself rather than anywhere in
  # the block.
  clause="$(printf '%s\n' "$block" | tr '\n' ' ' | grep -Eo '`show`[^.]*' | sed -n '1p' || true)"
  printf '%s\n' "$clause" | grep -Eq 'alternatives' \
    && printf '%s\n' "$block" | grep -Eq '`dispose --flag' \
    && ! printf '%s\n' "$block" | grep -Eqi 'contradictions'
}

# checking_omission_route <skill.md> — a missing claim is recorded as a dropped
# suspicion, and the completeness critic is named as the route only when the
# request asks what is missing.
checking_omission_route() {
  section_has_collapsed "$1" checking 'recorded as a dropped suspicion' \
    && section_has "$1" checking '`<completeness_critic>`'
}

# old_checking_sentence_absent <skill.md> — the pre-default <checking> sentence
# built every checklist from the acceptance contract, with no fallback.
old_checking_sentence_absent() {
  ! grep -Fq "Build the checklist from the artifact's acceptance contract, one line per item" "$1"
}

# c2_renderer_scoped <checks.md> — the `brief --acceptance` renderer applies
# only where the brief names an acceptance source, since `--acceptance` is
# optional.
c2_renderer_scoped() {
  c2_item_has_collapsed "$1" 1 'When the brief names an acceptance source, copy the checklist verbatim' \
    && c2_item_has "$1" 1 'brief --acceptance PATH\[#Heading\]'
}

# c2_source_branch_scoped <checks.md> — a brief naming the item brief or an
# approved-edit list and no acceptance list copies its checklist from that
# source, and the `brief --acceptance` renderer stays on the acceptance-list
# case alone.
c2_source_branch_scoped() {
  c2_item_has_collapsed "$1" 1 'When the brief names the item brief or an approved-edit list and no acceptance list, copy the checklist from that source' \
    && c2_item_has_collapsed "$1" 1 'keep the `brief --acceptance` renderer for the acceptance-list case alone'
}

# c2_rewrite_pairing <checks.md> — the old-form test is paired with the
# presence test on a rewrite item alone.
c2_rewrite_pairing() {
  c2_item_has_collapsed "$1" 2 'Give a rewrite item the old-form test' \
    && c2_item_has_collapsed "$1" 2 'old form is absent where the required new form lands'
}

oldest_python3() {
  {
    type -a -p python3 2>/dev/null || true
    command -v python3 2>/dev/null || true
    for candidate in /usr/bin/python3 /bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3; do
      if [ -x "$candidate" ]; then
        printf '%s\n' "$candidate"
      fi
    done
  } | while IFS= read -r candidate; do
    if [ -x "$candidate" ]; then
      version="$("$candidate" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)" || continue
      printf '%s %s\n' "$version" "$candidate"
    fi
  done | sort -t. -k1,1n -k2,2n -k3,3n | head -1 | cut -d' ' -f2-
}

oldest_python_help() {
  oldest="$(oldest_python3)"
  [[ -n "$oldest" ]] || return 1
  "$oldest" -B "$LEDGER" --help >/dev/null 2>&1
}

# shellcheck source=../../lib/plugin_version.sh
. "$HERE/../../lib/plugin_version.sh"

printf 'agent_spinner script_tests\n'

# --- frontmatter and description -------------------------------------------
check "SKILL.md exists" test -f "$SKILL"
check "frontmatter name: agent_spinner" file_has "$SKILL" '^name: agent_spinner$'
# Test Integrity: a grader fix. The skill must carry a semantic version, and a
# literal pin breaks on every commit-time bump (the reason
# tests/lib/plugin_version.sh gives against literal pins), so the check
# asserts the shape.
check "frontmatter version is semver" file_has "$SKILL" '^version: [0-9]+\.[0-9]+\.[0-9]+$'
check "H1 matches the frontmatter name" file_has "$SKILL" '^# agent_spinner$'
# A per-skill conservative bound under the harness's 1536-character
# truncation limit (skill_doctor's skillListingMaxDescChars).
check "description under the 1500-character per-skill bound (1536 truncation limit)" description_under "$SKILL" 1500

for word in orchestrat fan-out verif parallel; do
  check "description carries the '$word' trigger word" \
    description_has "$SKILL" "$word"
done
check "description routes task requests to the task_* family" \
  description_has "$SKILL" 'task_\*'
check "description routes wiki requests to wiki_fix" \
  description_has "$SKILL" 'wiki_fix'

# --- one block per named contract -------------------------------------------
CONTRACTS=(
  invocation_boundary capability_probe degradation selector shapes width
  phase_plan run_economy coverage_tradeoff containment delegation_depth
  prompt_assembly checking confirmation_provenance helper_failure remediation
  run_state aggregation reporting judgement
)
for tag in "${CONTRACTS[@]}"; do
  check "block <$tag> present" file_has "$SKILL" "<$tag>"
done

# --- the ledger doctrine's opening block ------------------------------------
check "<start_here> block present" file_has "$SKILL" '^<start_here>$'
check "<start_here> first numbered step runs the ledger's status" \
  start_here_first_step_is_status "$SKILL"
check "<start_here> sits directly after </role>" \
  bash -c "awk 'BEGIN{seen=0} /^<\\/role>/{getline; if (\$0 == \"\") {getline}; print; exit}' '$SKILL' | grep -qx '<start_here>'"
check "every run_ledger.py path is skill-relative" \
  ledger_paths_qualified "$SKILL_DIR"

# --- <aggregation>'s `show` read set ----------------------------------------
check "<aggregation> show read set matches the ledger's imported record types" \
  aggregation_show_list_correct "$SKILL"

# --- the report's opening and the fork's passages ---------------------------
check "<reporting> states the four opening facts" \
  section_has_collapsed "$SKILL" reporting 'The opening sentence gives the answer, the tier, helpers dispatched against returned, and whether `close` exited 0'
printf '\nopening-sentence sites (four facts, a <reporting> pointer, or the tier-only announcement):\n'
opening_sentence_sites_ok "$SKILL_DIR" || true
check "every passage naming the opening sentence carries the four facts, a <reporting> pointer, or the tier-only announcement" \
  opening_sentence_sites_ok "$SKILL_DIR"
check "P6's self-check carries all four opening facts" \
  p6_check_carries_opening_facts "$REFS/run-protocol.md"
check "the stop template's first sentence carries all four opening facts" \
  stop_template_first_sentence_facts "$REFS/report-shapes.md"
check "<degradation> states the tier for the pre-dispatch announcement alone" \
  degradation_states_tier_only "$SKILL"
check "the fork contract requires an anchored passages entry on every surface" \
  fork_contract_requires_passages "$REFS/run-protocol.md"
check "role-prompts.md closing block names the fork passages field" \
  closing_block_forks_fields "$REFS/role-prompts.md"

# --- the six shapes, each with its four elements ----------------------------
SHAPES=(
  per_artifact_fan_out lens_panel paired_refute_check
  judge_panel completeness_critic single_writer_validator
)
for shape in "${SHAPES[@]}"; do
  check "shape <$shape> present" file_has "$SKILL" "<$shape>"
  for element in Trigger Width 'Prompt skeleton' Return; do
    check "shape <$shape> states its $element" \
      section_has "$SKILL" "$shape" "\\*\\*$element\\*\\*"
  done
done
check "the six shapes sit inside <shapes>" \
  bash -c "awk '/<shapes>/,/<\\/shapes>/' '$SKILL' | grep -c '<per_artifact_fan_out>\\|<lens_panel>\\|<paired_refute_check>\\|<judge_panel>\\|<completeness_critic>\\|<single_writer_validator>' | grep -q '^6$'"

# --- capability probe -------------------------------------------------------
check "capability_probe names the delegation surface" \
  section_has "$SKILL" capability_probe 'delegation surface'
check "capability_probe names a read-only lever" \
  section_has "$SKILL" capability_probe 'read-only lever'
check "capability_probe names a depth or effort control" \
  section_has "$SKILL" capability_probe 'depth or effort control'
check "capability_probe names concurrency" \
  section_has "$SKILL" capability_probe 'two helpers run at once'
check "capability_probe defines a registered role through the host's spawn surface" \
  section_has_collapsed "$SKILL" capability_probe 'one the host.s spawn surface lists or accepts by name'
check "capability_probe forbids searching home or configuration directories for definition files" section_has_collapsed "$SKILL" capability_probe 'never (searches|reads|looks)[^.]{0,60}(home|configuration)'
check "capability_probe resolves an unestablished capability to absent" \
  section_has "$SKILL" capability_probe 'resists establishment to absent'

# --- degradation, selector, width, depth ------------------------------------
check "degradation names the inline floor" \
  section_has "$SKILL" degradation 'Inline floor'
check "degradation honours a governing stop-and-ask boundary" \
  section_has "$SKILL" degradation 'stop-and-ask boundary'
check "degradation claims no wall-clock benefit" \
  section_has "$SKILL" degradation 'no wall-clock benefit'
check "selector carries the residual smallest-covering rule" \
  section_has "$SKILL" selector 'smallest shape that covers it'
check "selector defines a read-only diagnostic by what it reads" section_has_collapsed "$SKILL" selector 'one artifact or one mechanism, answered from the orchestrator'
check "width derives breadth from the written-out list" \
  section_has "$SKILL" width 'never a round number'
check "delegation_depth holds the run to one level" \
  section_has "$SKILL" delegation_depth 'delegates no part of it'

# --- the grep items that must stay empty ------------------------------------
check "no per-harness frontmatter keys or tool identifiers" \
  tree_lacks "$SKILL_DIR" '^[[:space:]]*(tools|allowed-?tools|disallowed-?tools|subagent_type|argument-hint|disable-model-invocation|reasoningEffort)[[:space:]]*:|Task\(|Bash\(|WebFetch|str_replace|apply_patch'
check "no harness agent directory paths" \
  tree_lacks "$SKILL_DIR" '\.claude/|\.codex/|\.cursor/|\.opencode/|\.agents/|\.github/'
check "no sandbox mode values" \
  tree_lacks "$SKILL_DIR" 'bypassPermissions|acceptEdits|danger-full-access|workspace-write|--permission-mode|dangerously-skip'
check "every target product name cites harness_portability" \
  product_hits_cite_portability "$SKILL_DIR"
check "no instruction to write a global rules or agent-config file" \
  tree_lacks "$SKILL_DIR" 'AGENTS\.md|CLAUDE\.md|GEMINI\.md|cursorrules|settings\.json|global (rules|instructions)|standing-instructions file'

# --- the advisory direction stays one-way -----------------------------------
check "no agent definition cites agent_spinner" \
  tree_lacks "$REPO_ROOT/plugins/ai_dev/agents" 'agent_spinner'
check "task_auto_check does not cite agent_spinner" \
  tree_lacks "$REPO_ROOT/plugins/ai_dev/skills/task_auto_check" 'agent_spinner'
check "task_fix does not cite agent_spinner" \
  tree_lacks "$REPO_ROOT/plugins/ai_dev/skills/task_fix" 'agent_spinner'
check "knowledge_management does not cite agent_spinner" \
  tree_lacks "$REPO_ROOT/plugins/knowledge_management" 'agent_spinner'
check "the skill bundles no agent definitions" \
  bash -c "[[ ! -d '$SKILL_DIR/agents' ]]"
# Test Integrity: superseded behaviour. The archived agent_spinner task's
# "ships no bundled scripts" decision was reversed by the owner on 2026-10-03,
# recorded in tasks/ai-dev_agent-spinner-run-ledger.md and in the archived
# ai-dev_agent-spinner-skill.md. These checks pin the bundled ledger instead.
check "scripts/ holds exactly run_ledger.py" scripts_exactly_ledger "$SCRIPTS"
check "run_ledger.py imports only the standard library" \
  python3 "$HERE/import_check.py" "$LEDGER"
check "run_ledger.py answers --help under the oldest python3" oldest_python_help
check "run_ledger.py runs no state-changing git subcommand" \
  python3 "$HERE/git_guard.py" "$LEDGER"

# The same assertions fail on a scratch copy holding one violation, so a green
# run proves the check can fail rather than passing vacuously.
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/extra-scripts"
cp "$LEDGER" "$SCRATCH/extra-scripts/run_ledger.py"
touch "$SCRATCH/extra-scripts/extra.py"
check "the scripts check fails on an extra file" not scripts_exactly_ledger "$SCRATCH/extra-scripts"

cp "$LEDGER" "$SCRATCH/third_party.py"
printf '\nimport requests\n' >> "$SCRATCH/third_party.py"
check "the import check fails on a third-party import" \
  not python3 "$HERE/import_check.py" "$SCRATCH/third_party.py"

cp "$LEDGER" "$SCRATCH/newer_syntax.py"
printf '\nmatch 1:\n    case 1:\n        pass\n' >> "$SCRATCH/newer_syntax.py"
oldest="$(oldest_python3)"
check "the oldest python3 rejects newer syntax" \
  not bash -c "'$oldest' -B -m py_compile '$SCRATCH/newer_syntax.py'"

cp "$LEDGER" "$SCRATCH/stateful_git.py"
printf '\ndef _stateful(root):\n    return subprocess.run(["git", "-C", root, "add", "."])\n' >> "$SCRATCH/stateful_git.py"
check "the git guard fails on a state-changing git call" \
  not python3 "$HERE/git_guard.py" "$SCRATCH/stateful_git.py"

cp "$LEDGER" "$SCRATCH/stateful_helper.py"
printf '\ndef _stateful(root):\n    return git(["commit", "-m", "x"], root)\n' >> "$SCRATCH/stateful_helper.py"
check "the git guard fails on a state-changing call through the git helper" \
  not python3 "$HERE/git_guard.py" "$SCRATCH/stateful_helper.py"

# The two ledger-doctrine checks must fail on a scratch copy holding one
# violation, so a green run proves they can fail rather than passing vacuously.
mkdir -p "$SCRATCH/no-status"
cp "$SKILL" "$SCRATCH/no-status/SKILL.md"
python3 - "$SCRATCH/no-status/SKILL.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("1. Run the ledger's `status`.", "1. Run the ledger's `attach`.", 1)
open(path, "w").write(text)
PY
check "the start_here check fails when its first step lacks status" \
  not start_here_first_step_is_status "$SCRATCH/no-status/SKILL.md"

mkdir -p "$SCRATCH/bare-path/references"
cp "$SKILL" "$SCRATCH/bare-path/SKILL.md"
printf 'Run `python3 scripts/run_ledger.py status` first.\n' \
  > "$SCRATCH/bare-path/references/probe.md"
check "the bare-path check fails on a bare scripts/run_ledger.py" \
  not ledger_paths_qualified "$SCRATCH/bare-path"

# The aggregation check must fail on the retired show sentence, so a green run
# proves it can fail rather than passing vacuously.
mkdir -p "$SCRATCH/old-aggregation"
cp "$SKILL" "$SCRATCH/old-aggregation/SKILL.md"
python3 - "$SCRATCH/old-aggregation/SKILL.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
old_block = """<aggregation>
Merge cited findings, never count agreement. The ledger imports every return in full. Read through `show`, in full, every record that needs your judgement: forks, decide-class findings, contradictions, beyond-brief finds, incidents, and own-authority calls. Dispose of the rest by id pattern, and never read a return through slices or keyword searches. Give each record one disposition: applied, refuted with its reason, surfaced to the user, or deferred with a durable pointer. Two helpers raising the same item is shared priors, so union the proposals and check each. Join by the echoed identifier and stop the merge when one is missing. Every number the report states comes from the ledger. Cap any payload pasted downstream at a stated size, tell that pass its material may be cut and that load-bearing detail gets re-read from the source, and list every trimmed identifier.
</aggregation>"""
text, n = re.subn(r"<aggregation>.*?</aggregation>", lambda _: old_block, text, count=1, flags=re.S)
if n != 1:
    raise SystemExit("aggregation block not found")
open(path, "w").write(text)
PY
check "the aggregation check fails on the old show sentence" \
  not aggregation_show_list_correct "$SCRATCH/old-aggregation/SKILL.md"

# The one-to-one recipe check must fail on both violation shapes, so a green
# run proves it can fail rather than passing vacuously.
mkdir -p "$SCRATCH/recipe-missing/references/recipes"
cp "$SKILL" "$SCRATCH/recipe-missing/SKILL.md"
python3 - "$SCRATCH/recipe-missing/SKILL.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("| --- | --- |\n", "| --- | --- |\n| an ask | `missing.md` |\n", 1)
open(path, "w").write(text)
PY
check "the one-to-one check fails on a table naming a missing recipe file" \
  not selector_recipe_rows_match "$SCRATCH/recipe-missing/SKILL.md" "$SCRATCH/recipe-missing/references/recipes"

mkdir -p "$SCRATCH/recipe-orphan/references/recipes"
cp "$SKILL" "$SCRATCH/recipe-orphan/SKILL.md"
printf '# orphan recipe\n' > "$SCRATCH/recipe-orphan/references/recipes/orphan.md"
check "the one-to-one check fails on a recipe file with no row" \
  not selector_recipe_rows_match "$SCRATCH/recipe-orphan/SKILL.md" "$SCRATCH/recipe-orphan/references/recipes"

# --- the two generic helper roles -------------------------------------------
check "auto_checker_spinner role file exists" test -f "$CHECKER_ROLE"
check "auto_writer_spinner role file exists" test -f "$WRITER_ROLE"
check "auto_checker_spinner name matches its file stem and the spinner token" \
  role_name_matches_stem "$CHECKER_ROLE"
check "auto_writer_spinner name matches its file stem and the spinner token" \
  role_name_matches_stem "$WRITER_ROLE"
check "auto_checker_spinner body is exactly its four sentences" \
  role_body_is "$CHECKER_ROLE" "$CHECKER_BODY"
check "auto_writer_spinner body is exactly its three sentences" \
  role_body_is "$WRITER_ROLE" "$WRITER_BODY"
check "auto_checker_spinner carries readonly: true and read/search tools only" \
  checker_readonly_lever "$CHECKER_ROLE"
check "auto_checker_spinner carries model: inherit" \
  file_has "$CHECKER_ROLE" '^model: inherit$'
check "auto_checker_spinner pins effort: max" \
  file_has "$CHECKER_ROLE" '^effort: max$'
check "auto_checker_spinner pins model_reasoning_effort: xhigh" \
  file_has "$CHECKER_ROLE" '^model_reasoning_effort: xhigh$'
check "auto_writer_spinner carries model: inherit" \
  file_has "$WRITER_ROLE" '^model: inherit$'
check "auto_writer_spinner carries no readonly: true" \
  writer_has_no_readonly_lever "$WRITER_ROLE"
check "auto_writer_spinner carries no tools or effort key" \
  writer_has_no_tools_or_effort "$WRITER_ROLE"
check "the pseudo-XML linter reports no issue on either role file" \
  role_lint_clean_file "$CHECKER_ROLE" "$WRITER_ROLE"

# Each role check must fail on a scratch copy holding one violation, so a
# green run proves the check can fail rather than passing vacuously.
ROLE_SCRATCH="$SCRATCH/roles"
mkdir -p "$ROLE_SCRATCH"

cp "$CHECKER_ROLE" "$ROLE_SCRATCH/auto_checker_spinner.md"
python3 - "$ROLE_SCRATCH/auto_checker_spinner.md" <<'PY'
import sys
path = sys.argv[1]
lines = [line for line in open(path) if line.rstrip("\n") != "readonly: true"]
open(path, "w").writelines(lines)
PY
check "the read-only check fails without readonly: true" \
  not checker_readonly_lever "$ROLE_SCRATCH/auto_checker_spinner.md"

cp "$CHECKER_ROLE" "$ROLE_SCRATCH/checker-shell-tool.md"
python3 - "$ROLE_SCRATCH/checker-shell-tool.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("tools: Read, Grep, Glob", "tools: Read, Grep, Glob, Bash", 1)
open(path, "w").write(text)
PY
check "the read-only check fails when the tools list names a shell tool" \
  not checker_readonly_lever "$ROLE_SCRATCH/checker-shell-tool.md"

cp "$CHECKER_ROLE" "$ROLE_SCRATCH/auto_checker_agent.md"
python3 - "$ROLE_SCRATCH/auto_checker_agent.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace("name: auto_checker_spinner", "name: auto_checker_agent", 1)
open(path, "w").write(text)
PY
check "the role-name check fails on the derived agent token" \
  not role_name_matches_stem "$ROLE_SCRATCH/auto_checker_agent.md"

cp "$WRITER_ROLE" "$ROLE_SCRATCH/writer-wrong-first-line.md"
python3 - "$ROLE_SCRATCH/writer-wrong-first-line.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace(
    "Read the brief file your prompt names, in full, and follow it.",
    "Read the brief when convenient.", 1)
open(path, "w").write(text)
PY
check "the body check fails when the first line differs" \
  not role_body_is "$ROLE_SCRATCH/writer-wrong-first-line.md" "$WRITER_BODY"

cp "$WRITER_ROLE" "$ROLE_SCRATCH/writer-no-h1-optout.md"
python3 - "$ROLE_SCRATCH/writer-no-h1-optout.md" <<'PY'
import sys
path = sys.argv[1]
lines = [line for line in open(path) if "lint: allow-no-h1" not in line]
open(path, "w").writelines(lines)
PY
check "the pseudo-XML check fails on a role body with no H1 opt-out" \
  not role_lint_clean_file "$ROLE_SCRATCH/writer-no-h1-optout.md"

# --- a scratch project-dir deploy writes each role per target ---------------
#
# The scratch HOME and deploy log keep the user's harness directories and the
# checkout's deploy log untouched, the way tests/deployment stages its own
# project directory. Each checker copy carries the read-only mapping its
# target's agent row in deployment/README.md names.
DEPLOY_PROJECT="$SCRATCH/deploy/project"
DEPLOY_HOME="$SCRATCH/deploy/home"
DEPLOY_LOG="$SCRATCH/deploy/deployed.log"
mkdir -p "$DEPLOY_PROJECT" "$DEPLOY_HOME"

deploy_agents_to_scratch() {
  HOME="$DEPLOY_HOME" DEPLOYED_ARTIFACTS_LOG="$DEPLOY_LOG" \
    /bin/bash "$REPO_ROOT/deployment/deployment.sh" \
    --project-dir "$DEPLOY_PROJECT" --type agent >/dev/null 2>&1
}

check "a scratch project-dir deploy of the agent type succeeds" \
  deploy_agents_to_scratch

deploy_copy_has() { [[ -f "$1" ]] && grep -Eq "$2" "$1"; }
deploy_copy_lacks() { [[ -f "$1" ]] && ! grep -Eq "$2" "$1"; }

check "the deploy writes the VS Code checker copy with readonly: true" \
  deploy_copy_has "$DEPLOY_PROJECT/.github/agents/auto_checker_spinner.agent.md" '^readonly: true$'
check "the deploy writes the Cursor checker copy with readonly: true" \
  deploy_copy_has "$DEPLOY_PROJECT/.cursor/agents/auto_checker_spinner.md" '^readonly: true$'
check "the deploy writes the Claude checker copy with readonly: true" \
  deploy_copy_has "$DEPLOY_PROJECT/.claude/agents/auto_checker_spinner.md" '^readonly: true$'
check "the deploy writes the Codex checker copy with sandbox_mode read-only" \
  deploy_copy_has "$DEPLOY_PROJECT/.codex/agents/auto_checker_spinner.toml" '^sandbox_mode = "read-only"$'
check "the deploy writes the Antigravity checker copy with commandExecutionPolicy off" \
  deploy_copy_has "$DEPLOY_PROJECT/.agents/agents/auto_checker_spinner.md" '^commandExecutionPolicy: off$'
check "the deploy writes the OpenCode checker copy with an edit deny" \
  bash -c "grep -Eq '^  - action: edit$' '$DEPLOY_PROJECT/.opencode/agents/auto_checker_spinner.md' && grep -Eq '^    effect: deny$' '$DEPLOY_PROJECT/.opencode/agents/auto_checker_spinner.md'"

check "the deploy writes the VS Code writer copy without a read-only lever" \
  deploy_copy_lacks "$DEPLOY_PROJECT/.github/agents/auto_writer_spinner.agent.md" '^readonly:'
check "the deploy writes the Cursor writer copy without a read-only lever" \
  deploy_copy_lacks "$DEPLOY_PROJECT/.cursor/agents/auto_writer_spinner.md" '^readonly:'
check "the deploy writes the Claude writer copy without a read-only lever" \
  deploy_copy_lacks "$DEPLOY_PROJECT/.claude/agents/auto_writer_spinner.md" '^readonly:'
check "the deploy writes the Codex writer copy without a read-only sandbox" \
  deploy_copy_lacks "$DEPLOY_PROJECT/.codex/agents/auto_writer_spinner.toml" '^sandbox_mode = "read-only"$'
check "the deploy writes the Antigravity writer copy without a read-only policy" \
  deploy_copy_lacks "$DEPLOY_PROJECT/.agents/agents/auto_writer_spinner.md" '^commandExecutionPolicy: off$'
check "the deploy writes the OpenCode writer copy" \
  test -f "$DEPLOY_PROJECT/.opencode/agents/auto_writer_spinner.md"

# The four reference checks must fail on a scratch copy holding one violation,
# so a green run proves each can fail rather than passing vacuously.
mkdir -p "$SCRATCH/refs-missing-c7"
cp -R "$REFS/." "$SCRATCH/refs-missing-c7/"
python3 - "$SCRATCH/refs-missing-c7/checks.md" <<'PY'
import sys
path = sys.argv[1]
lines = [line for line in open(path) if not line.startswith("## C7. ")]
open(path, "w").writelines(lines)
PY
check "the C1-to-C10 check fails on a missing C7 heading" \
  not checks_sections_in_order "$SCRATCH/refs-missing-c7/checks.md"

mkdir -p "$SCRATCH/refs-missing-judge"
cp -R "$REFS/." "$SCRATCH/refs-missing-judge/"
python3 - "$SCRATCH/refs-missing-judge/role-prompts.md" <<'PY'
import sys
path = sys.argv[1]
lines = [line for line in open(path) if line.rstrip("\n") != "## Judge pass"]
open(path, "w").writelines(lines)
PY
check "the role-heading check fails on a missing judge template" \
  not role_prompt_headings_present "$SCRATCH/refs-missing-judge/role-prompts.md"

mkdir -p "$SCRATCH/refs-closing-checklist"
cp -R "$REFS/." "$SCRATCH/refs-closing-checklist/"
python3 - "$SCRATCH/refs-closing-checklist/role-prompts.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "`checklist` with `verdict` (`pass` or\n`fail`) and `span`"
new = "`checklist` with `n`, `verdict` (`pass` or\n`fail`), and `span`"
if old not in text:
    raise SystemExit("closing-block checklist entry not found")
open(path, "w").write(text.replace(old, new, 1))
PY
check "the closing-block checklist check fails when the entry names n" \
  not closing_block_checklist_fields "$SCRATCH/refs-closing-checklist/role-prompts.md"

mkdir -p "$SCRATCH/refs-step-number"
cp -R "$REFS/." "$SCRATCH/refs-step-number/"
printf '\nSee P3 step 2 for the return rules.\n' \
  >> "$SCRATCH/refs-step-number/checks.md"
check "the step-number check fails on a numbered run-protocol citation" \
  not references_cite_no_step_number "$SCRATCH/refs-step-number"

mkdir -p "$SCRATCH/refs-no-edit-mechanics"
cp -R "$REFS/." "$SCRATCH/refs-no-edit-mechanics/"
rm -f "$SCRATCH/refs-no-edit-mechanics/edit-mechanics.md"
check "the edit-mechanics check fails when the file is absent" \
  not test -f "$SCRATCH/refs-no-edit-mechanics/edit-mechanics.md"

# --- references -------------------------------------------------------------
check "references/run-protocol.md exists" test -f "$REFS/run-protocol.md"
check "references/checks.md exists" test -f "$REFS/checks.md"
check "references/checks.md holds the ten C1-to-C10 headings in order" \
  checks_sections_in_order "$REFS/checks.md"
check "references/edit-mechanics.md exists" test -f "$REFS/edit-mechanics.md"
check "role-prompts.md carries the four kept, four added, and two block headings" \
  role_prompt_headings_present "$REFS/role-prompts.md"
check "role-prompts.md closing block names only the rendered checklist fields" \
  closing_block_checklist_fields "$REFS/role-prompts.md"
check "no file under references/ cites a run-protocol step by number" \
  references_cite_no_step_number "$REFS"
check "references/role-prompts.md exists" test -f "$REFS/role-prompts.md"
check "references/report-shapes.md exists" test -f "$REFS/report-shapes.md"
check "references/degradation-examples.md exists" test -f "$REFS/degradation-examples.md"
check "references/variants.md exists" test -f "$REFS/variants.md"
for part in 'P1, open the run' 'P2, render every brief from files' \
  'P3, return files and the acceptance gate' \
  'P4, completion, waves, stop, and resume' 'P5, keep shared state still' \
  'P6, the findings ledger, decision packets, and the report'; do
  check "run-protocol.md carries the $part section" \
    file_has "$REFS/run-protocol.md" "^## $part$"
done
check "run-protocol.md carries the capability tier table" \
  file_has "$REFS/run-protocol.md" '^## Capability tier table$'
check "run-protocol.md carries the run-directory section" \
  file_has "$REFS/run-protocol.md" '^## Run directory$'
check "run-protocol.md carries the ledger-floor section" \
  file_has "$REFS/run-protocol.md" '^## Ledger floor$'
check "run-protocol.md carries the command reference" \
  file_has "$REFS/run-protocol.md" '^## Command reference$'
for role in 'Producing pass' 'Lens pass' 'Checking pass' 'Synthesis pass'; do
  check "role-prompts.md carries the $role template" \
    file_has "$REFS/role-prompts.md" "^## $role$"
done
check "variants.md carries the information-isolation variant" \
  file_has "$REFS/variants.md" 'Information isolation between concurrent helpers'
check "variants.md carries the replicated-draw variant" \
  file_has "$REFS/variants.md" 'Replicated draws returned unreduced'
check "variants.md carries the blind-derivation variant" \
  file_has "$REFS/variants.md" '^## Blind derivation$'
check "variants.md carries the balanced-challenge variant" \
  file_has "$REFS/variants.md" '^## Balanced challenge$'
check "variants.md carries the calibration-controls variant" \
  file_has "$REFS/variants.md" '^## Calibration controls$'
check "variants.md carries the hypothesis-readings variant" \
  file_has "$REFS/variants.md" '^## Splitting a hypothesis into its readings$'
check "variants.md carries the blind-by-prompt phrase" \
  file_has "$REFS/variants.md" 'blind by prompt'
check "selector recipe rows match references/recipes/ one to one" \
  selector_recipe_rows_match "$SKILL" "$REFS/recipes"
check "multi-file trigger defines a task by its own acceptance list" section_has_collapsed "$REFS/recipes/multi-file-task.md" trigger 'tracked item that carries its own acceptance list'

# Every recipe file under references/recipes/ carries one outer tag named after
# its file stem, the thirteen field tags in order, two to four numbered phases,
# and the shared lines each field must hold. A recipe with a repair round, one
# whose <orchestrator_gates> carries the C5 label, also carries the three
# repair-round lines. The loop passes when no recipe file exists, so it holds at
# every commit and covers the recipe files other tasks ship.

RECIPE_FIELDS=(
  trigger ledger_steps phases width roles_and_returns adversarial_checks
  orchestrator_gates failure_handling stop_and_ask report cost_profile
  tier_notes post_run_checks
)
RECIPE_SHARED_LINES=(
  'trigger|applies only after the selector matched that shape'
  'width|spans sessions at wave ends'
  'roles_and_returns|`accept --stdin`, never through a shell'
  'orchestrator_gates|These orchestrator steps run in this order'
  'failure_handling|accepts every pending return before it continues'
  'stop_and_ask|A request answers a fork only where it decides that fork in so many words; a request asking for the decision to come back leaves the fork for the user'
  'cost_profile|coverage by construction, a review of every landed write, and baseline-differential gates'
)
RECIPE_REPAIR_LINES=(
  'orchestrator_gates|re-enters the write phase and the checking phase that reads the repaired diff'
  'report|re-checked once, recall-limited, and unverified end to end'
  'post_run_checks|exactly one re-check row, at no lower depth than its first check'
)

record_result() {
  if [[ "$1" == pass ]]; then
    pass=$((pass+1)); printf '  PASS  %s\n' "$2"
  else
    fail=$((fail+1)); printf '  FAIL  %s\n' "$2"; failures+=("$2")
  fi
}

# recipe_file_checks <file> — prints one "status<TAB>label" line per property,
# with every shared phrase matched as a fixed string over its field's text and
# line breaks collapsed to single spaces.
recipe_file_checks() {
  python3 - "$1" "${RECIPE_FIELDS[@]}" "--" "${RECIPE_SHARED_LINES[@]}" \
    "--" "${RECIPE_REPAIR_LINES[@]}" <<'PY'
import os, re, sys

path = sys.argv[1]
args = sys.argv[2:]
first = args.index("--")
fields = args[:first]
rest = args[first + 1:]
second = rest.index("--")
shared = rest[:second]
repair = rest[second + 1:]

name = os.path.basename(path)
stem = name[:-3].replace("-", "_")
text = open(path, encoding="utf-8").read()
results = []


def emit(ok, label):
    results.append(("pass" if ok else "fail", label))


def block(outer, field):
    tag = "<%s>" % field
    if tag not in outer:
        return ""
    start = outer.index(tag) + len(tag)
    end = outer.find("</%s>" % field, start)
    return outer[start:end] if end != -1 else outer[start:]


def collapse(value):
    return re.sub(r"\s+", " ", value).strip()


outer_open = "<%s>" % stem
outer_close = "</%s>" % stem
emit(outer_open in text and outer_close in text,
     "%s opens the outer tag <%s>" % (name, stem))
if outer_open in text and outer_close in text:
    start = text.index(outer_open) + len(outer_open)
    outer = text[start:text.index(outer_close, start)]
else:
    outer = ""

positions = []
for field in fields:
    idx = outer.find("<%s>" % field)
    emit(idx != -1, "%s <%s> present" % (name, field))
    positions.append(idx)
emit(all(idx != -1 for idx in positions)
     and positions == sorted(positions),
     "%s field tags appear in the required order" % name)

phases = block(outer, "phases")
numbered = len(re.findall(r"^[ \t]*[0-9]+\.[ \t]+\S", phases, re.M))
emit(2 <= numbered <= 4,
     "%s <phases> holds two to four numbered phases (found %d)"
     % (name, numbered))

for entry in shared:
    field, phrase = entry.split("|", 1)
    emit(phrase in collapse(block(outer, field)),
         "%s <%s> carries '%s'" % (name, field, phrase))

if "C5" in block(outer, "orchestrator_gates"):
    for entry in repair:
        field, phrase = entry.split("|", 1)
        emit(phrase in collapse(block(outer, field)),
             "%s <%s> carries the repair-round line '%s'"
             % (name, field, phrase))

for status, label in results:
    print("%s\t%s" % (status, label))
PY
}

if [[ -d "$REFS/recipes" ]]; then
  while IFS= read -r recipe; do
    [[ -n "$recipe" ]] || continue
    while IFS=$'\t' read -r status label; do
      [[ -n "$status" ]] || continue
      record_result "$status" "$label"
    done < <(recipe_file_checks "$recipe")
  done < <(find "$REFS/recipes" -maxdepth 1 -type f -name '*.md' | sort)
fi
check "every template opens with an action rather than a prohibition" \
  python3 -c "
import re, sys
t = open('$REFS/role-prompts.md').read()
blocks = re.findall(r'\`\`\`text\n(.*?)\`\`\`', t, re.S)
sys.exit(0 if blocks and all(
    re.match(r'(Read|Write|Open|Start|Run|List|Check|Return)\b',
             next(l for l in b.splitlines() if l.strip()))
    for b in blocks) else 1)
"
check "no template claims precedence over the surrounding conversation" \
  tree_lacks "$REFS" 'takes? precedence|override[s]? (any|all|the)|ignore (all |any )?(previous|prior|earlier)|supersede[s]? (any|all)|regardless of (any|all)|highest authority'

# --- the checking pass's default contract -----------------------------------
#
# <checking> and C2 name the contract a checking brief builds its checklist
# from: the acceptance contract where the brief names one of C1 step 4's three
# sources (the item brief, an approved-edit list, an acceptance list), and
# otherwise one line per claim the artifact makes, in artifact order. A missing
# claim is a completeness finding only when the request asks what is missing,
# so a checking pass over an accurate corpus reports zero findings.

check "<checking> takes the default contract, one line per claim in artifact order" \
  section_has_collapsed "$SKILL" checking 'one line per claim the artifact makes, in artifact order'
check "<checking> keys the default on a brief naming none of the three contract sources" \
  section_has_collapsed "$SKILL" checking 'A brief naming none of those three sources takes the default contract'
check "<checking> records a missing claim as a dropped suspicion and names the completeness critic" \
  checking_omission_route "$SKILL"
check "the old <checking> acceptance-contract sentence is absent" \
  old_checking_sentence_absent "$SKILL"
check "C2 takes the same default contract, one line per claim in artifact order" \
  c2_has_collapsed "$CHECKS" 'one line per claim the artifact makes, in artifact order'
check "C2 item 1 scopes the brief --acceptance renderer to a brief naming an acceptance source" \
  c2_renderer_scoped "$CHECKS"
check "C2 item 1 copies the checklist from the item brief or approved-edit list and keeps the renderer on the acceptance-list case alone" \
  c2_source_branch_scoped "$CHECKS"
check "C2 item 2 gives the old-form test to rewrite items alone" \
  c2_rewrite_pairing "$CHECKS"
check "the Checking pass template names what its checklist is built from" \
  heading_block_has_collapsed "$ROLE_PROMPTS" 'Checking pass' 'Where it names none, hold one line per claim the artifact makes, in artifact order'

# Each check fails on a scratch copy carrying the pre-change form, so a green
# run proves it can fail rather than passing vacuously.
CC_SCRATCH="$SCRATCH/check-contract"
mkdir -p "$CC_SCRATCH"

cp "$SKILL" "$CC_SCRATCH/no-claim-unit.md"
python3 - "$CC_SCRATCH/no-claim-unit.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "one line per claim the artifact makes, in artifact order"
if old not in text:
    raise SystemExit("claim-unit sentence not found")
open(path, "w").write(text.replace(old, "one line per item", 1))
PY
check "the claim-unit check fails on a checklist with no claim unit or order" \
  not section_has_collapsed "$CC_SCRATCH/no-claim-unit.md" checking 'one line per claim the artifact makes, in artifact order'

cp "$SKILL" "$CC_SCRATCH/no-source-key.md"
python3 - "$CC_SCRATCH/no-source-key.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "A brief naming none of those three sources takes the default contract"
if old not in text:
    raise SystemExit("source-key sentence not found")
open(path, "w").write(text.replace(old, "A brief naming no source takes the default contract", 1))
PY
check "the source-key check fails on a default contract not keyed on the three sources" \
  not section_has_collapsed "$CC_SCRATCH/no-source-key.md" checking 'A brief naming none of those three sources takes the default contract'

cp "$SKILL" "$CC_SCRATCH/no-dropped-suspicion.md"
python3 - "$CC_SCRATCH/no-dropped-suspicion.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "recorded as a dropped suspicion"
if old not in text:
    raise SystemExit("dropped-suspicion sentence not found")
open(path, "w").write(text.replace(old, "recorded as a finding", 1))
PY
check "the omission check fails when a missing claim is recorded as a finding" \
  not checking_omission_route "$CC_SCRATCH/no-dropped-suspicion.md"

cp "$SKILL" "$CC_SCRATCH/old-checking-sentence.md"
printf '\nBuild the checklist from the artifact'"'"'s acceptance contract, one line per item, testing the required form present and the old form absent.\n' \
  >> "$CC_SCRATCH/old-checking-sentence.md"
check "the old-sentence check fails on the pre-default sentence" \
  not old_checking_sentence_absent "$CC_SCRATCH/old-checking-sentence.md"

cp "$CHECKS" "$CC_SCRATCH/c2-no-claim-unit.md"
python3 - "$CC_SCRATCH/c2-no-claim-unit.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text, n = re.subn(r"one line per claim the artifact makes,\s+in artifact\s+order",
                  "one line per item", text, count=1)
if n != 1:
    raise SystemExit("C2 claim-unit sentence not found")
open(path, "w").write(text)
PY
check "the C2 claim-unit check fails on a checklist with no claim unit or order" \
  not c2_has_collapsed "$CC_SCRATCH/c2-no-claim-unit.md" 'one line per claim the artifact makes, in artifact order'

cp "$CHECKS" "$CC_SCRATCH/c2-unscoped-renderer.md"
python3 - "$CC_SCRATCH/c2-unscoped-renderer.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text, n = re.subn(r"When the brief names an\s+acceptance source",
                  "When the brief names a contract", text, count=1)
if n != 1:
    raise SystemExit("renderer scope sentence not found")
open(path, "w").write(text)
PY
check "the renderer check fails on an unscoped brief --acceptance sentence" \
  not c2_renderer_scoped "$CC_SCRATCH/c2-unscoped-renderer.md"

cp "$CHECKS" "$CC_SCRATCH/c2-no-source-branch.md"
python3 - "$CC_SCRATCH/c2-no-source-branch.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text, n = re.subn(
    r"When the brief names the item brief or an approved-edit list\s+and no acceptance list,.*?acceptance-list\s+case alone\.\s*",
    "", text, count=1, flags=re.S)
if n != 1:
    raise SystemExit("item-brief branch sentence not found")
open(path, "w").write(text)
PY
check "the source-branch check fails when the item-brief and approved-edit-list branch is removed" \
  not c2_source_branch_scoped "$CC_SCRATCH/c2-no-source-branch.md"

cp "$CHECKS" "$CC_SCRATCH/c2-old-form-every-item.md"
python3 - "$CC_SCRATCH/c2-old-form-every-item.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text, n = re.subn(r"Give a rewrite item the old-form test",
                  "Give each item the old-form test", text, count=1)
if n != 1:
    raise SystemExit("rewrite-item sentence not found")
open(path, "w").write(text)
PY
check "the rewrite-pairing check fails when the old-form test reaches every item" \
  not c2_rewrite_pairing "$CC_SCRATCH/c2-old-form-every-item.md"

cp "$ROLE_PROMPTS" "$CC_SCRATCH/bare-checking-template.md"
python3 - "$CC_SCRATCH/bare-checking-template.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text, n = re.subn(
    r"Build the checklist from the brief's acceptance contract where it names one of.*?sends it to a completeness critic\.\n\n",
    "", text, count=1, flags=re.S)
if n != 1:
    raise SystemExit("checking-template contract sentence not found")
open(path, "w").write(text)
PY
check "the template check fails on the bare 1. [check one] list" \
  not heading_block_has_collapsed "$CC_SCRATCH/bare-checking-template.md" 'Checking pass' 'Where it names none, hold one line per claim the artifact makes, in artifact order'

# --- the opening rule and the fork passage rule -----------------------------
#
# Each check fails on a scratch copy carrying the pre-change form, so a green
# run proves it can fail rather than passing vacuously.

OPEN_SCRATCH="$SCRATCH/opening"
mkdir -p "$OPEN_SCRATCH/references"
cp "$SKILL" "$OPEN_SCRATCH/SKILL.md"
cp -R "$REFS/." "$OPEN_SCRATCH/references/"
printf '\nThe opening sentence names the tier alone.\n' \
  >> "$OPEN_SCRATCH/references/probe.md"
check "the opening-sentence sweep fails on a one-fact restatement" \
  not opening_sentence_sites_ok "$OPEN_SCRATCH"

cp "$REFS/run-protocol.md" "$SCRATCH/p6-no-facts.md"
python3 - "$SCRATCH/p6-no-facts.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "The opening sentence carries the\nanswer, the tier, helpers dispatched against returned, and whether `close`\nexited 0."
new = "The opening sentence states whether `close`\nexited 0."
if old not in text:
    raise SystemExit("P6 check sentence not found")
open(path, "w").write(text.replace(old, new, 1))
PY
check "the P6 fact check fails on a close-status-only self-check" \
  not p6_check_carries_opening_facts "$SCRATCH/p6-no-facts.md"

cp "$REFS/report-shapes.md" "$SCRATCH/stop-no-facts.md"
python3 - "$SCRATCH/stop-no-facts.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "2 returned, and `close --stopped` exited 3"
new = "2 returned. `close --stopped` exited 3"
if old not in text:
    raise SystemExit("stop template sentence not found")
open(path, "w").write(text.replace(old, new, 1))
PY
check "the stop-template check fails when the exit moves to a second sentence" \
  not stop_template_first_sentence_facts "$SCRATCH/stop-no-facts.md"

cp "$SKILL" "$SCRATCH/degradation-with-close.md"
python3 - "$SCRATCH/degradation-with-close.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
old = "State the tier the run reaches in the announcement before the first helper:"
new = "State the tier the run reaches in the announcement before the first helper, and whether `close` exited 0:"
if old not in text:
    raise SystemExit("degradation sentence not found")
open(path, "w").write(text.replace(old, new, 1))
PY
check "the degradation check fails when it names a close exit" \
  not degradation_states_tier_only "$SCRATCH/degradation-with-close.md"

cp "$REFS/run-protocol.md" "$SCRATCH/forks-optional.md"
python3 - "$SCRATCH/forks-optional.md" <<'PY'
import re
import sys
path = sys.argv[1]
text = open(path).read()
text, n = re.subn(
    r"  `preferred`, and `passages`\. Each option object carries.*?orchestrator silently editing a stamp another family owns\.",
    "  `preferred`. A fork may also carry `passages`, a list of objects each holding\n  `text` and `anchor`. A fork whose change touches a stamped or marked path\n  carries `path`, the path the fork names; that field clears condition 10 for\n  the path it names, so the owning gate is handed the choice rather than the\n  orchestrator silently editing a stamp another family owns.",
    text, count=1, flags=re.S)
if n != 1:
    raise SystemExit("forks bullet not found")
open(path, "w").write(text)
PY
check "the fork-contract check fails on the optional-passages sentence" \
  not fork_contract_requires_passages "$SCRATCH/forks-optional.md"

cp "$ROLE_PROMPTS" "$SCRATCH/closing-no-passages.md"
python3 - "$SCRATCH/closing-no-passages.md" <<'PY'
import re
import sys
path = sys.argv[1]
text = open(path).read()
text, n = re.subn(
    r"`preferred`, and\n`passages` \(one or more objects, each with `text` and `anchor`, naming verbatim\neach passage the fork touches\)",
    "and `preferred`",
    text, count=1)
if n != 1:
    raise SystemExit("closing-block forks clause not found")
open(path, "w").write(text)
PY
check "the closing-block forks check fails when passages is dropped" \
  not closing_block_forks_fields "$SCRATCH/closing-no-passages.md"

# --- eval harness -----------------------------------------------------------
# The eval runner's stage() raises on a stage.sh that fails, and on one that
# exits 0 without naming a sandbox project, before any worker could start.
check "the eval runner's stage() raises on a failed or empty stage" \
  python3 "$REPO_ROOT/tests/lib/check_stage_guard.py" \
  "$REPO_ROOT/tests/agent_spinner/evals"

# --- trigger evals ----------------------------------------------------------
check "trigger eval set exists" test -f "$TRIGGERS"
check "trigger eval set is valid JSON" jq empty "$TRIGGERS"
check "trigger set carries should_trigger true queries" \
  bash -c "jq -e 'map(select(.should_trigger == true)) | length >= 5' '$TRIGGERS'"
check "trigger set carries should_trigger false queries" \
  bash -c "jq -e 'map(select(.should_trigger == false)) | length >= 5' '$TRIGGERS'"
for territory in 'task_check\|readiness' 'backlog' 'wiki' 'pull request' 'guardrail' 'harness\|Codex'; do
  check "trigger set draws a negative from $territory territory" \
    bash -c "jq -r '.[] | select(.should_trigger == false) | .query' '$TRIGGERS' | grep -qi '$territory'"
done

# --- registration -----------------------------------------------------------
check "listed in .claude-plugin/plugin.json description" \
  file_has "$REPO_ROOT/plugins/ai_dev/.claude-plugin/plugin.json" 'agent_spinner'
check "listed in .codex-plugin/plugin.json description" \
  file_has "$REPO_ROOT/plugins/ai_dev/.codex-plugin/plugin.json" 'agent_spinner'
check "listed in the Claude marketplace registration" \
  file_has "$REPO_ROOT/.claude-plugin/marketplace.json" 'agent_spinner'
check "listed in the Codex marketplace registration" \
  file_has "$REPO_ROOT/.agents/plugins/marketplace.json" 'agent_spinner'
check "listed in the plugin README" \
  file_has "$REPO_ROOT/plugins/ai_dev/README.md" 'agent_spinner'
check "listed in the root README layout tree" \
  bash -c "grep -Eq '── agent_spinner/' '$REPO_ROOT/README.md'"
check "listed in the root README skill list" \
  bash -c "grep -Eq '\\*\\*agent_spinner\\*\\*' '$REPO_ROOT/README.md'"
check "the wiki concept page points at the skill" \
  file_has "$REPO_ROOT/wiki/concepts/agent-delegated-automation.md" 'agent_spinner'
check_plugin_version_lockstep ai_dev

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failures:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
