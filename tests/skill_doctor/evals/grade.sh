#!/usr/bin/env bash
# grade.sh — programmatic grader for skill_doctor behavioral evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_repo> [response_file]
#
# Two surfaces are checkable without a model:
#   * filesystem state — every staged SKILL.md is byte-identical after the
#     run, which is the whole check-only contract;
#   * the response text — whether the resolved target set the skill named
#     matches the expected one, and whether discovery safety came first.
#
# Prints PASS/FAIL per check and exits 0 only if every check passed.

set -uo pipefail

eval_id="${1:?eval id required}"
repo="${2:?sandbox repo path required}"
response="${3:-}"

target="$(cd "$repo/.." && pwd)"
manifest="$target/.eval_checksums"

if [[ ! -s "$manifest" ]]; then
  echo "FAIL: $manifest is missing or empty (did stage.sh run?)" >&2
  exit 1
fi

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

# Case-insensitive whole-word search over the captured response.
said() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -qiE "(^|[^A-Za-z0-9_])$1([^A-Za-z0-9_]|$)" "$response"
}

# The body of one report section: every line after the first heading whose
# text matches the pattern, up to the next heading. The output contract orders
# the three severity tiers as sections, so a tier assertion reads the section
# that owns it rather than scanning the whole response — a line-wise scan also
# reaches the verification summary, where a count row legitimately names
# several tiers at once. Recognizes a markdown heading and a bold-label line,
# since both spellings appear in real reports.
section_body() {
  local pattern="$1"
  [[ -n "$response" && -f "$response" ]] || return 1
  awk -v pat="$pattern" '
    function is_boundary(line) {
      if (line ~ /^#+[ \t]/) return 1
      # A bold label opens a section only when it names one. Each finding
      # carries its own bold lead-in ("**`alpha_widget` — `version:`
      # absent**"), so treating every bold line as a boundary would end the
      # section at its first finding and read the body as empty.
      if (line ~ /^\*\*[^*]+\*\*[ \t]*$/ && \
          tolower(line) ~ /blocking|warning|info|verification|summary/) return 1
      return 0
    }
    {
      if (is_boundary($0)) {
        if (inside) exit
        if (tolower($0) ~ pat) { inside = 1; next }
      }
      if (inside) print
    }
  ' "$response"
}

# Skill names this helper may be asked about. The scan below keys on every
# occurrence of the name in the response, so a fixture named after an ordinary
# English word matches report prose that has nothing to do with the skill: a
# run that correctly said "`other` was excluded" still failed on a later
# sentence reading "no basis to prefer one over the other". Fixtures therefore
# carry invented snake_case names, and this list makes a lapse fail loudly
# instead of flaking.
ENGLISH_WORD_TOKENS='other|others|another|all|any|none|one|some|each|every|both|same|rest|this|that|it|test|main|core|base|common|extra|misc'

# A correct run may name an excluded skill while explaining the exclusion, so
# "absent" is too strict: require that every line mentioning it marks it as
# excluded. A bare mention inside the resolved set still fails.
excluded_properly() {
  [[ -n "$response" && -f "$response" ]] || return 1
  if printf '%s' "$1" | grep -qixE "$ENGLISH_WORD_TOKENS"; then
    printf 'GRADER BUG: excluded_properly("%s") keys on an ordinary English word; rename the fixture skill to an invented snake_case name\n' \
      "$1" >&2
    return 1
  fi
  local hits
  hits=$(grep -iE "(^|[^A-Za-z0-9_])$1([^A-Za-z0-9_]|$)" "$response" || true)
  [[ -z "$hits" ]] && return 0
  ! printf '%s\n' "$hits" \
    | grep -qivE 'exclud|outside|not part|not in|omit|skip|beyond|unrelated'
}

# A remedy-free typographic-punctuation warning invites a transliteration, so a
# run that lands on "replace the em dash with `--`" has kept the clause break
# the finding asked it to split. Naming that substitution is still correct when
# the run names it to reject it, so mirror excluded_properly: collect every line
# that pairs a substituting verb with a hyphen target, and require each one to
# carry a rejecting marker.
no_hyphen_substitution() {
  [[ -n "$response" && -f "$response" ]] || return 1
  local hits
  hits=$(grep -iE \
    '(replac|substitut|swap|convert)[a-z]*[^.]{0,60}(with|for|by|into|to)[^.]{0,40}(hyphen|--)' \
    "$response" || true)
  [[ -z "$hits" ]] && return 0
  ! printf '%s\n' "$hits" \
    | grep -qivE "don't|do not|never|avoid|rather than|no fix|not a fix|fixes nothing|keeps the same|counts as no"
}

# Discovery safety has to run before the instruction-quality pass.
#
# Report *text* order cannot carry this: the skill's output contract orders the
# report by severity (blocking, then warnings, then the verification summary),
# so a registration warning legitimately precedes any mention of discovery
# safety. The verification summary is where execution order is observable, so
# key on the command name there instead of on prose anywhere in the report.
discovery_first() {
  [[ -n "$response" && -f "$response" ]] || return 1
  # Naming the command is the proof the check actually ran.
  grep -qiE 'discovery_safety\.py' "$response" || return 1

  local summary disc instr
  summary=$(sed -n '/[Vv]erification summary/,$p' "$response")
  [[ -n "$summary" ]] || return 0
  disc=$(printf '%s\n' "$summary" \
    | grep -niE 'discovery_safety\.py|discovery safety' | head -1 | cut -d: -f1)
  [[ -n "$disc" ]] || return 1
  instr=$(printf '%s\n' "$summary" \
    | grep -niE 'instruction[ -]quality' | head -1 | cut -d: -f1)
  [[ -z "$instr" ]] && return 0
  (( disc < instr ))
}

# The output contract says a clean run writes exactly `No blocking issues.`, so
# grade the literal case-sensitively with -F. A run that found real blocking
# faults cannot contain the string, and a run that paraphrased it ("nothing
# blocking here") has drifted off the contract even when its judgement was right.
clean_blocking_verdict() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -qF 'No blocking issues.' "$response"
}

# The summary earns its place by naming what actually ran, so a bare heading
# fails: require at least one real command token underneath it.
has_verification_summary() {
  [[ -n "$response" && -f "$response" ]] || return 1
  local summary
  summary=$(sed -n '/[Vv]erification summary/,$p' "$response")
  [[ -n "$summary" ]] || return 1
  # The command set is whatever the checked repo defines, so accept the two
  # bundled scripts plus the discovered entry-point shapes a repo may expose.
  printf '%s\n' "$summary" \
    | grep -qiE 'resolve_scope\.py|discovery_safety\.py|lint_pseudo_xml|jq |mise |pre-commit |make '
}

# --- Checks derived from the checked repo rather than from this one -----------
# Each helper below grades one half of the portability contract: a requirement
# whose subject the staged repo never adopted draws no finding, and a check the
# staged repo does define gets named with the command it ran under.

names_root_skills_layout() {
  [[ -n "$response" && -f "$response" ]] || return 1
  # The layout the walk resolved has to reach the reader, and the run must not
  # report the plugin layout as absent — the fixture ships no plugins/ tree and
  # that is not a fault.
  grep -qiE 'repo_skills|repo-root skills|skills/ (tree|layout)|root-level skills' \
    "$response" || return 1
  ! grep -qiE '(absent|missing|no)[^.]{0,40}plugins/\*/skills' "$response"
}

registration_not_applicable() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -qiE 'not applicable|n/?a\b|does not apply|no such surface' "$response"
}

# A run that reports the surface as not applicable may still name the file it
# looked for, so key on the claim rather than on the filename: every line
# pairing a manifest or marketplace file with missing-language must also carry
# the not-applicable framing.
no_missing_registration_file_claim() {
  [[ -n "$response" && -f "$response" ]] || return 1
  local hits
  hits=$(grep -iE '(plugin\.json|marketplace\.json|README\.md)' "$response" \
    | grep -iE 'missing|absent|lacks|not found|should (have|carry)|needs' || true)
  [[ -z "$hits" ]] && return 0
  ! printf '%s\n' "$hits" \
    | grep -qivE 'not applicable|n/?a|does not apply|no convention|never adopted|no such convention'
}

no_unstated_convention_finding() {
  [[ -n "$response" && -f "$response" ]] || return 1
  local hits
  hits=$(grep -iE 'h1|heading|readme[- ]listing|alignment|aligned' "$response" \
    | grep -iE 'finding|blocking|warning|mismatch|violat|should|must' || true)
  [[ -z "$hits" ]] && return 0
  ! printf '%s\n' "$hits" \
    | grep -qivE 'not applicable|n/?a|does not apply|no convention|never adopted|no such convention|no finding|clean|states no'
}

version_reported_as_info() {
  [[ -n "$response" && -f "$response" ]] || return 1
  # Tier membership is a property of the section a finding sits in, so read
  # the two sections rather than scanning the response line by line. The
  # line-wise form failed a correct report: a verification-summary row reading
  # "0 blocking, 0 warnings, 2 info (version absent for each)" states the tier
  # split accurately while putting `blocking` and `version` on one line.
  section_body 'info' | grep -qiE 'version' || return 1
  ! section_body 'blocking' | grep -qiE 'version'
}

version_rule_absence_stated() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -qiE 'no version rule|state[s]? no version|no such rule|carr(y|ies) no version|convention' \
    "$response"
}

names_mise_lint_command() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -qiE 'mise (run )?lint' "$response"
}

names_pre_commit_command() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -qiE 'pre-commit run' "$response"
}

# The staged repo defines a mise task and pre-commit hooks and nothing else, so
# a run that reports having run this repository's own gates has carried a
# convention across from the wrong tree. Naming one to rule it out is fine.
no_foreign_entry_point() {
  [[ -n "$response" && -f "$response" ]] || return 1
  local hits
  hits=$(grep -iE 'make (lint|deploy|fix)|deployment\.sh|markdownlint|--dry-run' \
    "$response" || true)
  [[ -z "$hits" ]] && return 0
  ! printf '%s\n' "$hits" \
    | grep -qivE 'no |not |none|absent|does not|lacks|never|instead of|rather than|this repo does'
}

# A check that could not run is only useful with its reason attached, so every
# skip line has to carry one. No skips at all passes too.
skips_carry_reasons() {
  [[ -n "$response" && -f "$response" ]] || return 1
  local hits
  hits=$(grep -iE 'skipped|could not run|did not run|unavailable|not run' "$response" || true)
  [[ -z "$hits" ]] && return 0
  ! printf '%s\n' "$hits" \
    | grep -qivE 'because|since|reason|no |not installed|absent|unavailable|does not|missing|—|:'
}

resolution_failure_reported() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -qiE 'not found|no such skill|no skill named|could not resolve|did not resolve|does not exist|unresolved|resolution failed' \
    "$response"
}

asks_the_user() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -qiE '(which|what)[^.]{0,80}\?|did you mean|let me know which|tell me which' "$response"
}

# A halted run reports the resolution failure and asks; it does not emit the
# report. Both the clean-path literal and a findings section header are proof it
# went ahead on a target set it chose for itself.
no_substituted_findings() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -qF 'No blocking issues.' "$response" && return 1
  ! grep -qiE '^[[:space:]]*[#*_[:space:]]*(blocking issues|warnings)[[:space:]]*:?[*_[:space:]]*$' \
    "$response"
}

# --- Universal: the check-only contract --------------------------------------

check "sandbox SKILL.md files unchanged" shasum -a 256 -c --status "$manifest"

# --- Per-eval expectations ---------------------------------------------------

case "$eval_id" in
  scope_hub_family)
    check "names the hub demo"                    said "demo"
    check "names the prefix sibling demo_alpha"   said "demo_alpha"
    check "names the family-block shared_linter"  said "shared_linter"
    check "excludes the out-of-family lone_gizmo"  excluded_properly "lone_gizmo"
    check "discovery safety precedes later passes" discovery_first
    ;;
  scope_prefix_only)
    check "names wiki"          said "wiki"
    check "names wiki_import"   said "wiki_import"
    check "names wiki_wrapup"   said "wiki_wrapup"
    check "excludes spr"        excluded_properly "spr"
    check "discovery safety precedes later passes" discovery_first
    ;;
  discovery_risky_sibling)
    check "flags the risky skill"            said "risky"
    check "cites discovery-safety evidence"  bash -c \
      "grep -qiE 'workflow|punctuation' '$response'"
    check "proposes no hyphen substitution for the em dash" no_hyphen_substitution
    check "discovery safety precedes later passes" discovery_first
    ;;
  scope_single_skill_clean)
    check "names the target alpha_widget"          said "alpha_widget"
    check "excludes the sibling alpha_gadget"      excluded_properly "alpha_gadget"
    check "excludes the other plugin beta_sprocket" excluded_properly "beta_sprocket"
    check "reaches the clean blocking verdict"     clean_blocking_verdict
    check "carries a verification summary"         has_verification_summary
    check "discovery safety precedes later passes" discovery_first
    ;;
  scope_whole_repo)
    check "names alpha_widget"    said "alpha_widget"
    check "names alpha_gadget"    said "alpha_gadget"
    check "names beta_sprocket"   said "beta_sprocket"
    check "discovery safety precedes later passes" discovery_first
    ;;
  scope_unresolvable_selector)
    check "names the unresolved selector omega_flange" said "omega_flange"
    check "reports the resolution failure"             resolution_failure_reported
    check "names a nearest candidate"                  bash -c \
      "grep -qiE 'alpha_widget|alpha_gadget|beta_sprocket' '$response'"
    check "asks which skill the user meant"            asks_the_user
    check "reports no findings pass on a substituted set" no_substituted_findings
    ;;
  registration_no_manifest)
    check "names the resolved repo-root skills layout"  names_root_skills_layout
    check "names both staged skills"                    bash -c \
      "grep -qiE 'alpha_widget' '$response' && grep -qiE 'beta_sprocket' '$response'"
    check "reports registration as not applicable"      registration_not_applicable
    check "claims no missing manifest or marketplace"   no_missing_registration_file_claim
    check "emits no alignment or README-listing finding" no_unstated_convention_finding
    check "reports the absent version at info"          version_reported_as_info
    check "says the rule files state no version rule"   version_rule_absence_stated
    check "reaches the clean blocking verdict"          clean_blocking_verdict
    check "discovery safety precedes later passes"      discovery_first
    ;;
  verification_repo_checks)
    check "names the mise lint task command"            names_mise_lint_command
    check "names the pre-commit command"                names_pre_commit_command
    check "reaches for no entry point this repo lacks"  no_foreign_entry_point
    check "carries a verification summary"              has_verification_summary
    check "names every unrunnable check with a reason"  skips_carry_reasons
    check "discovery safety precedes later passes"      discovery_first
    ;;
  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf '  failed: %s\n' "${failures[*]}"
  exit 1
fi
exit 0
