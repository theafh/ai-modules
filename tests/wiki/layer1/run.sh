#!/usr/bin/env bash
# Layer 1 tests for the wiki skill's bundled scripts.
#
# Each scenario stages a fake HOME tree under tests/wiki/layer1/scratch/<id>/,
# runs discover_wiki.sh / init_wiki.sh / lint.py with HOME and CWD pointed at
# that tree, and asserts stdout + exit code match expected.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WIKI_SKILL="$REPO_ROOT/plugins/knowledge_management/skills/wiki"
DISCOVER="$WIKI_SKILL/scripts/discover_wiki.sh"
INIT="$WIKI_SKILL/scripts/init_wiki.sh"
LINT="$WIKI_SKILL/scripts/lint.py"
SHA256="$WIKI_SKILL/scripts/compute_sha256.py"
AGENT_CONTRACT="$SCRIPT_DIR/agent_contract.py"
FILE_ACCESS_CONTRACT="$SCRIPT_DIR/file_access_contract.py"
HUB_OUTPUT_CONTRACT="$SCRIPT_DIR/hub_output_contract.py"

SCRATCH="$SCRIPT_DIR/scratch"
FIXTURES="$SCRIPT_DIR/fixtures"
RESULTS="$SCRIPT_DIR/../results/layer1.log"

PASS=0
FAIL=0
FAILED_IDS=()

mkdir -p "$SCRATCH"
mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

log()   { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }
indent() { sed 's/^/    /' | tee -a "$RESULTS" >&2; }

# fresh_scratch <id> -> echoes the scratch HOME path
fresh_scratch() {
    local id=$1
    local home="$SCRATCH/$id/HOME"
    rm -rf "${SCRATCH:?}/${id:?}"
    mkdir -p "$home"
    printf '%s' "$home"
}

# mark_wiki <dir> [marker_count] -> make <dir> a directory discover_wiki.sh
# recognises as a wiki: it exists and carries the marker files the predicate
# counts (basename must also contain "wiki"). discover requires >=2 of
# SCHEMA.md / index.md / log.md; default writes all three. Pass a count of 2
# to test the boundary, 1 to stage a sub-threshold (non-)wiki.
mark_wiki() {
    local dir=$1 count=${2:-3}
    mkdir -p "$dir"
    local markers=(SCHEMA.md index.md log.md)
    local i
    for ((i = 0; i < count && i < 3; i++)); do
        : > "$dir/${markers[$i]}"
    done
}

# run_discover <home> <cwd> [extra_args...] -> echoes "<exit>|<stdout>"
run_discover() {
    local home=$1 cwd=$2
    shift 2
    local out rc
    out=$(cd "$cwd" && HOME="$home" "$DISCOVER" "$@" 2>/dev/null) && rc=0 || rc=$?
    printf '%s|%s' "$rc" "$out"
}

# ---------------------------------------------------------------------------
# Discovery-parity helpers.
#
# lint.py:discover_wiki() is documented to "Mirror scripts/discover_wiki.sh".
# The two implementations are kept in sync by hand. These helpers run both
# against the same fixture and reduce their output to a single canonical
# decision string so a parity scenario can assert byte-equality.
#
# Contract: parity is checked against `discover_wiki.sh --check` (not the
# bare invocation), because lint.py's discover_wiki always requires the
# resolved path to exist on disk — the same contract `--check` enforces in
# bash. Without `--check`, the bash script auto-resolves to a not-yet-
# existing $HOME/wiki when every level is opted out; that's the discovery-
# layer contract, but it's deliberately stricter on the lint side.
#
# Canonical decision forms (both implementations):
#   OK:<path>           auto-resolved, path exists on disk
#   MISSING:<path>      auto-resolved, path absent (bash --check exits 1;
#                       lint.py raises SystemExit "wiki not found at ...")
#   ASK:c1;c2;...       ambiguous — candidate list joined with ';', in walk
#                       order, each prefixed AVAILABLE:/EXISTING:. Both sides
#                       exit 2 (bash on stdout; lint.py on stderr).
# ---------------------------------------------------------------------------

# discover_bash_check <home> <cwd> -> echoes the canonical decision.
discover_bash_check() {
    local home=$1 cwd=$2 out rc joined
    out=$(cd "$cwd" && HOME="$home" "$DISCOVER" --check 2>/dev/null) && rc=0 || rc=$?
    case "$rc" in
        0) printf 'OK:%s' "$out" ;;
        1) printf 'MISSING:%s' "$out" ;;
        2)
            joined=$(printf '%s' "$out" | tr '\n' ';' | sed 's/;$//')
            printf 'ASK:%s' "$joined"
            ;;
        *) printf 'ERROR:rc=%s,out=%s' "$rc" "$out" ;;
    esac
}

# discover_py <home> <cwd> -> echoes the canonical decision via lint.py.
# Imports lint.discover_wiki() directly so the test exercises the exact
# function lint.py runs in production — no surrogate.
discover_py() {
    local home=$1 cwd=$2
    PY_HOME="$home" PY_CWD="$cwd" PY_SCRIPTS="$WIKI_SKILL/scripts" \
        python3 - <<'PYEOF' 2>/dev/null
import io
import os
import sys

sys.path.insert(0, os.environ["PY_SCRIPTS"])
os.environ["HOME"] = os.environ["PY_HOME"]
os.chdir(os.environ["PY_CWD"])

from lint import discover_wiki

# discover_wiki prints the undecided candidate listing to stderr and exits 2.
# Capture stderr in-process so this probe can reconstruct the ASK candidate
# list, matching discover_wiki.sh --check's exit-2 stdout.
captured = io.StringIO()
real_stderr = sys.stderr
sys.stderr = captured
try:
    p = discover_wiki(None)
    sys.stderr = real_stderr
    print(f"OK:{p}")
except SystemExit as exc:
    sys.stderr = real_stderr
    code = exc.code
    if isinstance(code, int) and code == 2:
        # Undecided: stderr carried "  available: <path>" / "  existing:
        # <path>" lines. Reproduce bash's AVAILABLE:/EXISTING: shape.
        cands = []
        for line in captured.getvalue().splitlines():
            line = line.strip()
            if line.startswith("available: "):
                cands.append("AVAILABLE:" + line[len("available: "):])
            elif line.startswith("existing: "):
                cands.append("EXISTING:" + line[len("existing: "):])
        print("ASK:" + ";".join(cands))
    else:
        # Non-2 exits carry a string message (sys.exit("...")).
        msg = str(code)
        if msg.startswith("wiki not found at "):
            # "wiki not found at <path>; init it before linting"
            path = msg[len("wiki not found at "):].split(";", 1)[0].strip()
            print(f"MISSING:{path}")
        elif msg.startswith("wiki path does not exist:"):
            # only reachable when an explicit path arg is passed; not used
            # by these parity tests but listed for completeness.
            print(f"INVALID_PATH:{msg[len('wiki path does not exist:'):].strip()}")
        else:
            print(f"ERROR:{msg}")
PYEOF
}

# assert_discover_parity <home> <cwd> [label]
# Runs both discover implementations against the same fixture, reduces each
# to its canonical decision, and asserts byte-equality. The bash side is
# always run with --check (see contract note above).
assert_discover_parity() {
    local home=$1 cwd=$2 label=${3:-parity}
    local bash_dec py_dec
    bash_dec=$(discover_bash_check "$home" "$cwd")
    py_dec=$(discover_py "$home" "$cwd")
    if [[ "$bash_dec" == "$py_dec" ]]; then
        return 0
    fi
    log "    [$label diff: discover_wiki.sh --check vs lint.py:discover_wiki]"
    log "      bash:   $bash_dec"
    log "      python: $py_dec"
    return 1
}

assert_eq() {
    local label=$1 actual=$2 expected=$3
    if [[ "$actual" == "$expected" ]]; then
        return 0
    fi
    log "    [diff: $label]"
    log "      expected: $(printf '%q' "$expected")"
    log "      actual:   $(printf '%q' "$actual")"
    return 1
}

# scenario <id> <description> <body...>
# body is a function name. we run it; on any false return, the scenario fails.
scenario() {
    local id=$1 desc=$2 body=$3
    log ""
    log "=== $id  $desc ==="
    if "$body"; then
        PASS=$((PASS+1))
        log "  PASS"
    else
        FAIL=$((FAIL+1))
        FAILED_IDS+=("$id")
        log "  FAIL"
    fi
}

###############################################################################
# Discovery scenarios
###############################################################################

# D1: CWD inside HOME, no wiki and no .no_wiki anywhere on the ladder.
#     Expected: exit 2 with AVAILABLE for CWD and HOME.
d1_no_wiki_no_marker() {
    local home; home=$(fresh_scratch d1)
    mkdir -p "$home/proj"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*}
    local out=${ret#*|}
    local expected_out
    expected_out="AVAILABLE:$home/proj
AVAILABLE:$home"
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "$expected_out" || ok=false
    $ok
}

# D2: .no_wiki at CWD, no wiki at HOME, nothing else.
#     Walk: skip CWD; HOME has neither -> AVAILABLE:HOME.
#     Expected: exit 2, single AVAILABLE:HOME candidate.
d2_marker_at_cwd_no_home_wiki() {
    local home; home=$(fresh_scratch d2)
    mkdir -p "$home/proj"
    : > "$home/proj/.no_wiki"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "AVAILABLE:$home" || ok=false
    $ok
}

# D3: .no_wiki at CWD, recognised wiki/ at HOME -> auto-resolve to HOME/wiki.
d3_marker_at_cwd_wiki_at_home() {
    local home; home=$(fresh_scratch d3)
    mkdir -p "$home/proj"; mark_wiki "$home/wiki"
    : > "$home/proj/.no_wiki"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "stdout" "$out" "$home/wiki" || ok=false
    $ok
}

# D4: every ladder level opted out via .no_wiki -> auto-resolve to $HOME/wiki
#     (the explicit "use the global wiki" chain).
d4_all_levels_opted_out() {
    local home; home=$(fresh_scratch d4)
    mkdir -p "$home/proj"
    : > "$home/proj/.no_wiki"
    : > "$home/.no_wiki"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "stdout" "$out" "$home/wiki" || ok=false
    $ok
}

# D5: recognised wiki/ child at CWD -> auto-resolve to CWD/wiki.
d5_existing_wiki_at_cwd() {
    local home; home=$(fresh_scratch d5)
    mkdir -p "$home/proj"; mark_wiki "$home/proj/wiki"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "stdout" "$out" "$home/proj/wiki" || ok=false
    $ok
}

# D6: "Common case worth calling out" — CWD has no wiki and no .no_wiki, but
#     a parent has wiki/. Must NOT auto-resolve; must ask.
d6_upstream_wiki_cwd_undecided() {
    local home; home=$(fresh_scratch d6)
    mkdir -p "$home/proj"; mark_wiki "$home/wiki"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*} out=${ret#*|}
    local expected_out
    expected_out="AVAILABLE:$home/proj
EXISTING:$home/wiki"
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "$expected_out" || ok=false
    $ok
}

# D7: walk-up disabled (CWD outside HOME), no wiki, no marker at CWD.
#     Expected: exit 2 with AVAILABLE:CWD and AVAILABLE:HOME.
d7_outside_home_no_state() {
    local home; home=$(fresh_scratch d7)
    local out_dir="$SCRATCH/d7/outside"
    mkdir -p "$out_dir"
    local ret; ret=$(run_discover "$home" "$out_dir")
    local rc=${ret%%|*} out=${ret#*|}
    local expected_out
    expected_out="AVAILABLE:$out_dir
AVAILABLE:$home"
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "$expected_out" || ok=false
    $ok
}

# D8: walk-up disabled, CWD has a recognised wiki/ child -> resolve to CWD/wiki.
d8_outside_home_with_local_wiki() {
    local home; home=$(fresh_scratch d8)
    local out_dir="$SCRATCH/d8/outside"
    mkdir -p "$out_dir"; mark_wiki "$out_dir/wiki"
    local ret; ret=$(run_discover "$home" "$out_dir")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "stdout" "$out" "$out_dir/wiki" || ok=false
    $ok
}

# D9: walk-up disabled, CWD has .no_wiki -> auto-resolve to HOME/wiki.
d9_outside_home_with_marker() {
    local home; home=$(fresh_scratch d9)
    local out_dir="$SCRATCH/d9/outside"
    mkdir -p "$out_dir"
    : > "$out_dir/.no_wiki"
    local ret; ret=$(run_discover "$home" "$out_dir")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "stdout" "$out" "$home/wiki" || ok=false
    $ok
}

# D10: multi-level walk-up where the only existing wiki is at HOME.
#      Three intermediate AVAILABLE candidates are listed before EXISTING.
d10_multi_level_walk_up() {
    local home; home=$(fresh_scratch d10)
    mkdir -p "$home/work/proj/sub"; mark_wiki "$home/wiki"
    local ret; ret=$(run_discover "$home" "$home/work/proj/sub")
    local rc=${ret%%|*} out=${ret#*|}
    local expected_out
    expected_out="AVAILABLE:$home/work/proj/sub
AVAILABLE:$home/work/proj
AVAILABLE:$home/work
EXISTING:$home/wiki"
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "$expected_out" || ok=false
    $ok
}

# D11: --check option fails when auto-resolved path does not yet exist on disk.
#      Setup: every level opted out -> auto = $HOME/wiki, but $HOME/wiki
#      doesn't exist. Without --check exit 0; with --check exit 1.
d11_check_flag_missing_dir() {
    local home; home=$(fresh_scratch d11)
    mkdir -p "$home/proj"
    : > "$home/proj/.no_wiki"
    : > "$home/.no_wiki"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "no-flag exit" "$rc" "0" || ok=false
    assert_eq "no-flag stdout" "$out" "$home/wiki" || ok=false
    ret=$(run_discover "$home" "$home/proj" --check)
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "--check exit" "$rc" "1" || ok=false
    assert_eq "--check stdout" "$out" "$home/wiki" || ok=false
    $ok
}

# D12: `.no_wiki` at the wiki dir itself (retired-in-place).
#      Setup: HOME/wiki/ is fully markered but carries .no_wiki. Walk from
#      HOME/proj. .no_wiki overrides the predicate, so HOME/wiki is dropped:
#      proj -> AVAILABLE:proj, HOME has no recognised wiki -> AVAILABLE:HOME.
#      This is the retire-in-place contract — discovery no longer adopts a
#      wiki dir that has opted out, matching init_wiki.sh's refusal.
d12_retired_wiki_marker() {
    local home; home=$(fresh_scratch d12)
    mark_wiki "$home/wiki"; mkdir -p "$home/proj"
    : > "$home/wiki/.no_wiki"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*} out=${ret#*|}
    local expected_out
    expected_out="AVAILABLE:$home/proj
AVAILABLE:$home"
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "$expected_out" || ok=false
    $ok
}

# D13: CWD is itself a recognised wiki named "wiki" -> short-circuit resolve.
d13_cwd_is_markered_wiki() {
    local home; home=$(fresh_scratch d13)
    mark_wiki "$home/proj/wiki"
    local ret; ret=$(run_discover "$home" "$home/proj/wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "stdout" "$out" "$home/proj/wiki" || ok=false
    $ok
}

# D14: CWD is a topic-named recognised wiki (basename merely contains "wiki").
d14_cwd_is_topic_named_wiki() {
    local home; home=$(fresh_scratch d14)
    mark_wiki "$home/ml-wiki"
    local ret; ret=$(run_discover "$home" "$home/ml-wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "stdout" "$out" "$home/ml-wiki" || ok=false
    $ok
}

# D15: CWD is a dir literally named "wiki" but WITHOUT markers -> not adopted;
#      must ask (the false-positive the old exact-name probe had).
d15_cwd_markerless_wiki_not_adopted() {
    local home; home=$(fresh_scratch d15)
    mkdir -p "$home/bare/wiki"
    local ret; ret=$(run_discover "$home" "$home/bare/wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local expected_out
    expected_out="AVAILABLE:$home/bare/wiki
AVAILABLE:$home/bare
AVAILABLE:$home"
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "$expected_out" || ok=false
    $ok
}

# D16: parent of a topic-named recognised wiki -> auto-resolve to that child,
#      mirroring how a child named "wiki" resolves.
d16_parent_of_topic_named_wiki_resolves() {
    local home; home=$(fresh_scratch d16)
    mkdir -p "$home/proj"; mark_wiki "$home/proj/research-wiki"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "stdout" "$out" "$home/proj/research-wiki" || ok=false
    $ok
}

# D17: a SUBDIRECTORY of a wiki is not itself a valid wiki location -> must ask
#      (does not silently adopt the enclosing wiki). The enclosing wiki is
#      surfaced as EXISTING, but candidates[0] is AVAILABLE so it stops.
d17_subdir_of_wiki_asks() {
    local home; home=$(fresh_scratch d17)
    mark_wiki "$home/ml-wiki"; mkdir -p "$home/ml-wiki/entities"
    local ret; ret=$(run_discover "$home" "$home/ml-wiki/entities")
    local rc=${ret%%|*} out=${ret#*|}
    local expected_out
    expected_out="AVAILABLE:$home/ml-wiki/entities
AVAILABLE:$home/ml-wiki
EXISTING:$home/ml-wiki"
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "$expected_out" || ok=false
    $ok
}

# D18: 2-of-3 marker boundary — exactly two markers is recognised; one is not.
d18_marker_count_boundary() {
    local home; home=$(fresh_scratch d18)
    mkdir -p "$home/two"; mark_wiki "$home/two/mywiki" 2
    local ret; ret=$(run_discover "$home" "$home/two")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "2-marker exit" "$rc" "0" || ok=false
    assert_eq "2-marker stdout" "$out" "$home/two/mywiki" || ok=false
    mkdir -p "$home/one"; mark_wiki "$home/one/mywiki" 1
    ret=$(run_discover "$home" "$home/one")
    rc=${ret%%|*}
    assert_eq "1-marker exit (not recognised, asks)" "$rc" "2" || ok=false
    $ok
}

# D19: .no_wiki at CWD overrides the predicate even on a fully-markered wiki
#      -> the short-circuit is suppressed and CWD is skipped on the walk.
d19_no_wiki_at_cwd_overrides() {
    local home; home=$(fresh_scratch d19)
    mark_wiki "$home/retired-wiki"; : > "$home/retired-wiki/.no_wiki"
    local ret; ret=$(run_discover "$home" "$home/retired-wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "AVAILABLE:$home" || ok=false
    $ok
}

# D20: a fully-markered directory whose basename lacks "wiki" is NOT adopted —
#      the name half of the predicate is load-bearing (not structure-only
#      detection). HOME/notes carries all three markers but no "wiki" in the
#      name, so the walk from HOME/proj passes it over: AVAILABLE:proj then
#      AVAILABLE:HOME, never EXISTING:notes.
d20_markered_nonwiki_name_not_adopted() {
    local home; home=$(fresh_scratch d20)
    mkdir -p "$home/proj"; mark_wiki "$home/notes"
    local ret; ret=$(run_discover "$home" "$home/proj")
    local rc=${ret%%|*} out=${ret#*|}
    local expected_out
    expected_out="AVAILABLE:$home/proj
AVAILABLE:$home"
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_eq "stdout" "$out" "$expected_out" || ok=false
    $ok
}

# D21: a chosen wiki path handed back positionally answers for itself —
#      exit 0 with the canonical path, no walk-up. Covers both supported
#      positional shapes (WIKI_PATH and WIKI_PATH --check) and a relative
#      argument, which comes back canonicalized.
d21_positional_wiki_path() {
    local home; home=$(fresh_scratch d21)
    mark_wiki "$home/wiki"; mkdir -p "$home/proj"
    local ok=true
    local ret rc out
    ret=$(run_discover "$home" "$home/proj" "$home/wiki")
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "abs exit" "$rc" "0" || ok=false
    assert_eq "abs stdout" "$out" "$home/wiki" || ok=false
    ret=$(run_discover "$home" "$home/proj" "$home/wiki" --check)
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "--check exit" "$rc" "0" || ok=false
    assert_eq "--check stdout" "$out" "$home/wiki" || ok=false
    # Relative argument, resolved from CWD and printed canonically.
    ret=$(run_discover "$home" "$home" wiki)
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "relative exit" "$rc" "0" || ok=false
    assert_eq "relative stdout" "$out" "$home/wiki" || ok=false
    $ok
}

# D22: an AVAILABLE: choice — an existing directory that is NOT a wiki —
#      also resolves positionally, in both shapes. The wiki predicate is
#      deliberately not applied to a handed-back path, so the level the user
#      picked from an exit-2 list works as the chosen location.
d22_positional_non_wiki_path() {
    local home; home=$(fresh_scratch d22)
    mkdir -p "$home/proj"
    local ok=true
    local ret rc out
    ret=$(run_discover "$home" "$home/proj" "$home/proj")
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "plain exit" "$rc" "0" || ok=false
    assert_eq "plain stdout" "$out" "$home/proj" || ok=false
    ret=$(run_discover "$home" "$home/proj" "$home/proj" --check)
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "--check exit" "$rc" "0" || ok=false
    assert_eq "--check stdout" "$out" "$home/proj" || ok=false
    $ok
}

# D23: a positional path that does not exist exits 1 with nothing on stdout,
#      in both shapes — the same contract lint.py applies to its positional
#      wiki_path, and distinct from the exit-2 ambiguity signal.
d23_positional_missing_path() {
    local home; home=$(fresh_scratch d23)
    mkdir -p "$home/proj"
    local ok=true
    local ret rc out
    ret=$(run_discover "$home" "$home/proj" "$home/nope")
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "plain exit" "$rc" "1" || ok=false
    assert_eq "plain stdout" "$out" "" || ok=false
    ret=$(run_discover "$home" "$home/proj" "$home/nope" --check)
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "--check exit" "$rc" "1" || ok=false
    assert_eq "--check stdout" "$out" "" || ok=false
    $ok
}

# D24: usage errors exit 3, never 2. A caller that reads exit 2 as
#      "candidates on stdout" would otherwise take a malformed invocation
#      for an empty candidate list, so every unsupported shape gets its own
#      code and writes nothing to stdout.
d24_usage_error_exits_three() {
    local home; home=$(fresh_scratch d24)
    mkdir -p "$home/proj"
    local ok=true
    local ret rc out
    ret=$(run_discover "$home" "$home/proj" --bogus)
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "unknown flag exit" "$rc" "3" || ok=false
    assert_eq "unknown flag stdout" "$out" "" || ok=false
    # Flag-first is not one of the four supported shapes.
    ret=$(run_discover "$home" "$home/proj" --check "$home/proj")
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "flag-first exit" "$rc" "3" || ok=false
    assert_eq "flag-first stdout" "$out" "" || ok=false
    ret=$(run_discover "$home" "$home/proj" "$home/proj" --check extra)
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "too-many-args exit" "$rc" "3" || ok=false
    assert_eq "too-many-args stdout" "$out" "" || ok=false
    $ok
}

# D25: a dot-named directory satisfying the predicate is passed over. The
#      `*/` glob never sees it, lint.py's mirror skips it too, and the page
#      walk already excludes hidden directories — so `.a-wiki` loses to the
#      visible `b-wiki`, and a level holding only `.only-wiki` stays an
#      AVAILABLE creation candidate.
d25_dot_named_wiki_skipped() {
    local home; home=$(fresh_scratch d25)
    mkdir -p "$home/proj"
    mark_wiki "$home/proj/.a-wiki"; mark_wiki "$home/proj/b-wiki"
    local ok=true
    local ret rc out
    ret=$(run_discover "$home" "$home/proj")
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "visible-sibling exit" "$rc" "0" || ok=false
    assert_eq "visible-sibling stdout" "$out" "$home/proj/b-wiki" || ok=false
    # Dot-named wiki alone: nothing visible to adopt at that level.
    local home2; home2=$(fresh_scratch d25b)
    mkdir -p "$home2/proj"; mark_wiki "$home2/proj/.only-wiki"
    ret=$(run_discover "$home2" "$home2/proj")
    rc=${ret%%|*}; out=${ret#*|}
    local expected_out
    expected_out="AVAILABLE:$home2/proj
AVAILABLE:$home2"
    assert_eq "dot-only exit" "$rc" "2" || ok=false
    assert_eq "dot-only stdout" "$out" "$expected_out" || ok=false
    $ok
}

###############################################################################
# Discovery-parity scenarios
#
# Each dp* scenario re-stages the same fixture shape as the matching d*
# scenario above, then asserts discover_wiki.sh --check and lint.py's
# discover_wiki() agree on a single canonical decision. The d* scenarios
# pin the bash side against an explicit expected output; the dp* scenarios
# pin the two implementations against each other. Both must pass: drift in
# either implementation surfaces as a failure in one or both sets.
#
# Why both? The d* scenarios alone would let bash and Python drift together
# (a refactor that "fixes" one and silently changes the other) — the
# parity check is the regression net for that class of drift.
###############################################################################

dp1_parity_no_wiki_no_marker() {
    local home; home=$(fresh_scratch dp1)
    mkdir -p "$home/proj"
    assert_discover_parity "$home" "$home/proj" "dp1"
}

dp2_parity_marker_at_cwd_no_home_wiki() {
    local home; home=$(fresh_scratch dp2)
    mkdir -p "$home/proj"
    : > "$home/proj/.no_wiki"
    assert_discover_parity "$home" "$home/proj" "dp2"
}

dp3_parity_marker_at_cwd_wiki_at_home() {
    local home; home=$(fresh_scratch dp3)
    mkdir -p "$home/proj"; mark_wiki "$home/wiki"
    : > "$home/proj/.no_wiki"
    assert_discover_parity "$home" "$home/proj" "dp3"
}

# dp4: every level opted out, no wiki on disk. Bash --check exits 1 with
# stdout $HOME/wiki; Python raises SystemExit "wiki not found at ...; init
# it before linting". Both reduce to MISSING:$HOME/wiki — the parity test
# pins exactly that semantic equivalence.
dp4_parity_all_levels_opted_out_missing_home_wiki() {
    local home; home=$(fresh_scratch dp4)
    mkdir -p "$home/proj"
    : > "$home/proj/.no_wiki"
    : > "$home/.no_wiki"
    assert_discover_parity "$home" "$home/proj" "dp4"
}

# dp4b: same opted-out chain, but $HOME/wiki exists on disk. Now both
# implementations auto-resolve cleanly — OK:$HOME/wiki on both sides.
dp4b_parity_all_levels_opted_out_with_home_wiki() {
    local home; home=$(fresh_scratch dp4b)
    mkdir -p "$home/proj" "$home/wiki"
    : > "$home/proj/.no_wiki"
    : > "$home/.no_wiki"
    assert_discover_parity "$home" "$home/proj" "dp4b"
}

dp5_parity_existing_wiki_at_cwd() {
    local home; home=$(fresh_scratch dp5)
    mkdir -p "$home/proj"; mark_wiki "$home/proj/wiki"
    assert_discover_parity "$home" "$home/proj" "dp5"
}

dp6_parity_upstream_wiki_cwd_undecided() {
    local home; home=$(fresh_scratch dp6)
    mkdir -p "$home/proj"; mark_wiki "$home/wiki"
    assert_discover_parity "$home" "$home/proj" "dp6"
}

dp7_parity_outside_home_no_state() {
    local home; home=$(fresh_scratch dp7)
    local out_dir="$SCRATCH/dp7/outside"
    mkdir -p "$out_dir"
    assert_discover_parity "$home" "$out_dir" "dp7"
}

dp8_parity_outside_home_with_local_wiki() {
    local home; home=$(fresh_scratch dp8)
    local out_dir="$SCRATCH/dp8/outside"
    mkdir -p "$out_dir"; mark_wiki "$out_dir/wiki"
    assert_discover_parity "$home" "$out_dir" "dp8"
}

dp9_parity_outside_home_with_marker() {
    local home; home=$(fresh_scratch dp9)
    local out_dir="$SCRATCH/dp9/outside"
    mkdir -p "$out_dir" "$home/wiki"
    : > "$out_dir/.no_wiki"
    assert_discover_parity "$home" "$out_dir" "dp9"
}

# dp9b: same as dp9 but $HOME/wiki absent. The bash auto-resolves to a
# non-existent $HOME/wiki (--check exit 1, MISSING); Python raises the same
# "wiki not found at ..." SystemExit. Parity pins the divergence on the
# bash *without --check* side from leaking into the lint contract.
dp9b_parity_outside_home_with_marker_missing_home_wiki() {
    local home; home=$(fresh_scratch dp9b)
    local out_dir="$SCRATCH/dp9b/outside"
    mkdir -p "$out_dir"
    : > "$out_dir/.no_wiki"
    assert_discover_parity "$home" "$out_dir" "dp9b"
}

dp10_parity_multi_level_walk_up() {
    local home; home=$(fresh_scratch dp10)
    mkdir -p "$home/work/proj/sub"; mark_wiki "$home/wiki"
    assert_discover_parity "$home" "$home/work/proj/sub" "dp10"
}

# dp11 has no direct equivalent: d11 tests the bash --check flag itself
# (no-flag vs --check). The parity contract always uses --check (since
# lint.py mirrors that semantics), so the --check vs no-check axis is
# bash-only and not a parity question. Covered by dp4 / dp4b instead.

dp12_parity_retired_wiki_marker() {
    local home; home=$(fresh_scratch dp12)
    mark_wiki "$home/wiki"; mkdir -p "$home/proj"
    : > "$home/wiki/.no_wiki"
    assert_discover_parity "$home" "$home/proj" "dp12"
}

dp13_parity_cwd_is_markered_wiki() {
    local home; home=$(fresh_scratch dp13)
    mark_wiki "$home/proj/wiki"
    assert_discover_parity "$home" "$home/proj/wiki" "dp13"
}

dp14_parity_cwd_is_topic_named_wiki() {
    local home; home=$(fresh_scratch dp14)
    mark_wiki "$home/ml-wiki"
    assert_discover_parity "$home" "$home/ml-wiki" "dp14"
}

dp15_parity_cwd_markerless_wiki() {
    local home; home=$(fresh_scratch dp15)
    mkdir -p "$home/bare/wiki"
    assert_discover_parity "$home" "$home/bare/wiki" "dp15"
}

dp16_parity_parent_of_topic_named_wiki() {
    local home; home=$(fresh_scratch dp16)
    mkdir -p "$home/proj"; mark_wiki "$home/proj/research-wiki"
    assert_discover_parity "$home" "$home/proj" "dp16"
}

dp17_parity_subdir_of_wiki() {
    local home; home=$(fresh_scratch dp17)
    mark_wiki "$home/ml-wiki"; mkdir -p "$home/ml-wiki/entities"
    assert_discover_parity "$home" "$home/ml-wiki/entities" "dp17"
}

dp18_parity_marker_count_boundary() {
    local home; home=$(fresh_scratch dp18)
    mkdir -p "$home/two"; mark_wiki "$home/two/mywiki" 2
    assert_discover_parity "$home" "$home/two" "dp18"
}

dp19_parity_no_wiki_at_cwd_overrides() {
    local home; home=$(fresh_scratch dp19)
    mark_wiki "$home/retired-wiki"; : > "$home/retired-wiki/.no_wiki"
    assert_discover_parity "$home" "$home/retired-wiki" "dp19"
}

dp20_parity_markered_nonwiki_name() {
    local home; home=$(fresh_scratch dp20)
    mkdir -p "$home/proj"; mark_wiki "$home/notes"
    assert_discover_parity "$home" "$home/proj" "dp20"
}

# The dot-directory cases are where the two implementations used to split:
# bash globbed with `*/` and never saw a dot-named child, while lint.py
# iterated the whole directory and sorted dot names first. Both now skip
# them, so these two fixtures must produce one decision.
dp21_parity_dot_named_wiki_beside_visible() {
    local home; home=$(fresh_scratch dp21)
    mkdir -p "$home/proj"
    mark_wiki "$home/proj/.a-wiki"; mark_wiki "$home/proj/b-wiki"
    assert_discover_parity "$home" "$home/proj" "dp21"
}

dp22_parity_dot_named_wiki_only() {
    local home; home=$(fresh_scratch dp22)
    mkdir -p "$home/proj"; mark_wiki "$home/proj/.only-wiki"
    assert_discover_parity "$home" "$home/proj" "dp22"
}

###############################################################################
# Init scenarios
###############################################################################

# I1: init at a fresh path -> creates SCHEMA, index, log, and dir tree.
i1_init_fresh() {
    local home; home=$(fresh_scratch i1)
    local target="$home/proj/wiki"
    mkdir -p "$target"
    "$INIT" "$target" >/dev/null 2>&1 || { log "    init exited non-zero unexpectedly"; return 1; }
    local ok=true
    for f in SCHEMA.md index.md log.md; do
        [[ -f "$target/$f" ]] || { log "    missing $f"; ok=false; }
    done
    for d in raw/articles raw/papers raw/meetings raw/notes raw/assets entities concepts comparisons queries summaries procedures; do
        [[ -d "$target/$d" ]] || { log "    missing dir $d"; ok=false; }
    done
    $ok
}

# I2: init refuses to overwrite an existing wiki (SCHEMA.md present).
i2_init_refuses_existing_wiki() {
    local home; home=$(fresh_scratch i2)
    local target="$home/proj/wiki"
    mkdir -p "$target"
    : > "$target/SCHEMA.md"
    if "$INIT" "$target" >/dev/null 2>&1; then
        log "    init unexpectedly succeeded over an existing SCHEMA.md"
        return 1
    fi
    return 0
}

# I3: init refuses when the target itself carries a .no_wiki marker.
i3_init_refuses_no_wiki_marker() {
    local home; home=$(fresh_scratch i3)
    local target="$home/proj/wiki"
    mkdir -p "$target"
    : > "$target/.no_wiki"
    local out
    out=$("$INIT" "$target" 2>&1) && rc=0 || rc=$?
    if [[ $rc -eq 0 ]]; then
        log "    init unexpectedly succeeded despite .no_wiki marker"
        return 1
    fi
    if ! grep -q ".no_wiki" <<<"$out"; then
        log "    error message did not mention .no_wiki: $out"
        return 1
    fi
    return 0
}

# I4: init prints help with no args and exits 2.
i4_init_no_args_help() {
    local out rc
    out=$("$INIT" 2>&1) && rc=0 || rc=$?
    [[ $rc -eq 2 ]] || { log "    expected exit 2, got $rc"; return 1; }
    grep -q "init_wiki.sh" <<<"$out" || { log "    help text missing"; return 1; }
    return 0
}

###############################################################################
# Lint scenarios
###############################################################################

# Helpers for lint scenarios — keep each fixture tight.

# Stage a fresh wiki under <home>/wiki and echo the path.
stage_fresh_wiki() {
    local id=$1
    local home; home=$(fresh_scratch "$id")
    local target="$home/wiki"
    mkdir -p "$target"
    "$INIT" "$target" >/dev/null 2>&1
    printf '%s' "$target"
}

# Stage a wiki inside a throwaway git repo so source_path repo-boundary checks
# have a controlled repo root. The scratch tree itself lives inside the
# ai-modules repo, so without this the detected repo would be ai-modules and the
# escape/allow cases would be untestable. The repo root is the wiki's parent
# dir (<home>/repo); echoes the wiki path (<home>/repo/wiki).
stage_fresh_wiki_in_repo() {
    local id=$1
    local home; home=$(fresh_scratch "$id")
    local repo="$home/repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    local target="$repo/wiki"
    "$INIT" "$target" >/dev/null 2>&1
    printf '%s' "$target"
}

# Write a minimally-valid concept page that lints cleanly on its own.
# No outbound links — scenarios that need cross-references add them explicitly,
# so a single-page fixture doesn't trip the broken-link blocking check.
# Args: <wiki> <slug>
write_valid_concept_page() {
    local wiki=$1 slug=$2
    cat > "$wiki/concepts/$slug.md" <<EOF
---
title: $slug
created: 2026-05-01
updated: 2026-05-01
type: concept
tags: [model]
sources: []
confidence: medium
---

# $slug

Placeholder for $slug used by the lint regression harness.
EOF
}

# Add a "- [slug](concepts/slug.md) — summary" entry under "## Concepts" in index.md.
add_index_entry_concept() {
    local wiki=$1 slug=$2
    python3 - "$wiki/index.md" "$slug" <<'PY'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
slug = sys.argv[2]
text = idx.read_text()
marker = "## Concepts\n"
entry = f"- [{slug}](concepts/{slug}.md) — placeholder\n"
out = text.replace(marker, marker + "\n" + entry, 1)
idx.write_text(out)
PY
}

# Customize the fresh wiki's SCHEMA.md with a real, unfenced tag taxonomy so
# taxonomy-dependent checks have live config to work against. The template
# ships its example taxonomy fenced (documentation, not live config, per the
# lint hardening), so a scenario that needs a live taxonomy defines one here.
# Inserts a canonical "- Domain: <tags>" bullet under the "## Tag Taxonomy"
# heading; `model` is included so write_valid_concept_page's tag validates.
customize_taxonomy() {
    local wiki=$1 tags=${2:-model, architecture, benchmark, training}
    python3 - "$wiki/SCHEMA.md" "$tags" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
marker = "## Tag Taxonomy\n"
bullet = f"\n- Domain: {sys.argv[2]}\n"
p.write_text(text.replace(marker, marker + bullet, 1))
PY
}

# Write a raw source sidecar that lints cleanly: a remote source_url plus the
# ingested/sha256 metadata the raw-frontmatter check expects.
# Args: <wiki> <kind> <slug>
write_clean_raw_source() {
    local wiki=$1 kind=$2 slug=$3
    mkdir -p "$wiki/raw/$kind"
    cat > "$wiki/raw/$kind/$slug.md" <<EOF
---
source_url: https://example.com/$slug
ingested: 2026-05-01
sha256: placeholder
---

$slug source body.
EOF
    python3 "$SHA256" "$wiki/raw/$kind/$slug.md" >/dev/null 2>&1
}

# Write a minimally-valid typed page at <type>s/<slug>.md. Pass an empty
# sources_line to omit the key entirely, or a full line such as
# "sources: [raw/articles/alpha.md]" to carry one.
# Args: <wiki> <type> <slug> [sources_line]
write_typed_page() {
    local wiki=$1 type=$2 slug=$3 sources_line=${4-}
    local dir
    case "$type" in
        entity) dir=entities ;;
        concept) dir=concepts ;;
        comparison) dir=comparisons ;;
        query) dir=queries ;;
        summary) dir=summaries ;;
        procedure) dir=procedures ;;
        *) log "    [unknown page type: $type]"; return 1 ;;
    esac
    mkdir -p "$wiki/$dir"
    {
        printf '%s\n' '---'
        printf 'title: %s\n' "$slug"
        printf '%s\n' 'created: 2026-05-01'
        printf '%s\n' 'updated: 2026-05-01'
        printf 'type: %s\n' "$type"
        printf '%s\n' 'tags: [model]'
        if [[ -n "$sources_line" ]]; then
            printf '%s\n' "$sources_line"
        fi
        printf '%s\n' 'confidence: high'
        printf '%s\n' '---'
        printf '\n# %s\n\n' "$slug"
        printf 'Placeholder for %s used by the citation-consistency harness.\n' "$slug"
    } > "$wiki/$dir/$slug.md"
}

# Append an index.md link to a page in any type folder.
# Args: <wiki> <folder> <slug>
add_index_entry_for() {
    local wiki=$1 folder=$2 slug=$3
    printf '\n- [%s](%s/%s.md) — placeholder\n' "$slug" "$folder" "$slug" >> "$wiki/index.md"
}

# Run lint and echo "<exit>|<stdout>".
run_lint() {
    local wiki=$1
    shift
    local out rc
    out=$(python3 "$LINT" "$wiki" "$@" 2>&1) && rc=0 || rc=$?
    printf '%s|%s' "$rc" "$out"
}

# Assert lint output contains a specific category at the right severity.
# Args: <label> <output> <severity_label e.g. blocking|warn|info> <category>
assert_lint_finding() {
    local label=$1 out=$2 sev=$3 cat=$4
    if printf '%s' "$out" | grep -Eq "^[[:space:]]*\[${sev}[[:space:]]*\][[:space:]]+${cat}[[:space:]]"; then
        return 0
    fi
    log "    [missing finding: $label — expected [$sev] $cat]"
    printf '%s\n' "$out" | indent
    return 1
}

# Assert lint output does not contain a finding for the given category.
assert_no_lint_category() {
    local label=$1 out=$2 cat=$3
    if printf '%s' "$out" | grep -Eq "^[[:space:]]*\[[^]]+\][[:space:]]+${cat}[[:space:]]"; then
        log "    [unexpected finding: $label — category $cat]"
        printf '%s\n' "$out" | indent
        return 1
    fi
    return 0
}

# Assert a finding of <category> at <severity> is emitted for a specific file
# (matched by a path substring). Scopes an assertion to one sidecar/page when a
# fixture stages several. Args: <label> <output> <severity> <category> <file>
assert_finding_for_file() {
    local label=$1 out=$2 sev=$3 cat=$4 file=$5
    if printf '%s' "$out" \
        | grep -E "^[[:space:]]*\[${sev}[[:space:]]*\][[:space:]]+${cat}[[:space:]]" \
        | grep -qF "$file"; then
        return 0
    fi
    log "    [missing finding: $label — expected [$sev] $cat for $file]"
    printf '%s\n' "$out" | indent
    return 1
}

# Assert NO finding of <category> is emitted for a specific file, at any
# severity. Args: <label> <output> <category> <file>
assert_no_finding_for_file() {
    local label=$1 out=$2 cat=$3 file=$4
    if printf '%s' "$out" \
        | grep -E "^[[:space:]]*\[[^]]+\][[:space:]]+${cat}[[:space:]]" \
        | grep -qF "$file"; then
        log "    [unexpected finding: $label — $cat for $file]"
        printf '%s\n' "$out" | indent
        return 1
    fi
    return 0
}

# Assert the raw-origin warn for <file> carries the computed rewrite suffix
# `-> <rewrite>` — the linter resolved the file:///bare-path source_url against
# the repo root and named the exact source_path to write. Args: <label> <output>
# <file> <rewrite>
assert_origin_rewrite() {
    local label=$1 out=$2 file=$3 rewrite=$4
    if printf '%s' "$out" \
        | grep -E "^[[:space:]]*\[warn[[:space:]]*\][[:space:]]+raw-origin\b" \
        | grep -F "$file" \
        | grep -qF -e "-> $rewrite"; then
        return 0
    fi
    log "    [missing rewrite: $label — expected raw-origin warn for $file to carry -> $rewrite]"
    printf '%s\n' "$out" | indent
    return 1
}

# Assert the raw-origin warn for <file> carries NO computed `-> ` rewrite suffix
# — the source_url named no in-repo file, or the wiki is not in a git repo, so
# the redirect stays plain. Args: <label> <output> <file>
assert_no_origin_rewrite() {
    local label=$1 out=$2 file=$3
    if printf '%s' "$out" \
        | grep -E "^[[:space:]]*\[warn[[:space:]]*\][[:space:]]+raw-origin\b" \
        | grep -F "$file" \
        | grep -qF -e " -> "; then
        log "    [unexpected rewrite: $label — raw-origin warn for $file carried a -> suffix]"
        printf '%s\n' "$out" | indent
        return 1
    fi
    return 0
}

# L1: lint a freshly-initialized wiki in --quiet mode -> exits 0.
l1_lint_fresh_wiki() {
    local home; home=$(fresh_scratch l1)
    local target="$home/wiki"
    mkdir -p "$target"
    "$INIT" "$target" >/dev/null 2>&1 || { log "    init failed"; return 1; }
    local out rc
    out=$(python3 "$LINT" "$target" --quiet 2>&1) && rc=0 || rc=$?
    if [[ $rc -ne 0 ]]; then
        log "    lint exited $rc on a fresh wiki"
        printf '%s\n' "$out" | indent
        return 1
    fi
    return 0
}

# L2: lint a wiki with no SCHEMA.md -> blocking exit.
l2_lint_no_schema() {
    local home; home=$(fresh_scratch l2)
    local target="$home/wiki"
    mkdir -p "$target"
    "$INIT" "$target" >/dev/null 2>&1 || { log "    init failed"; return 1; }
    rm "$target/SCHEMA.md"
    local rc
    python3 "$LINT" "$target" --quiet >/dev/null 2>&1 && rc=0 || rc=$?
    if [[ $rc -eq 0 ]]; then
        log "    lint passed on a wiki without SCHEMA.md"
        return 1
    fi
    return 0
}

# L3: lint a wiki with no index.md -> blocking exit.
l3_lint_no_index() {
    local home; home=$(fresh_scratch l3)
    local target="$home/wiki"
    mkdir -p "$target"
    "$INIT" "$target" >/dev/null 2>&1 || { log "    init failed"; return 1; }
    rm "$target/index.md"
    local rc
    python3 "$LINT" "$target" --quiet >/dev/null 2>&1 && rc=0 || rc=$?
    if [[ $rc -eq 0 ]]; then
        log "    lint passed on a wiki without index.md"
        return 1
    fi
    return 0
}

# L4: broken markdown link to a .md file -> blocking, exit 1.
l4_lint_broken_link() {
    local wiki; wiki=$(stage_fresh_wiki l4)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    # widget.md links to companion.md (does not exist) and to a nonexistent path.
    cat >> "$wiki/concepts/widget.md" <<'EOF'

See [missing target](concepts/does-not-exist.md).
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_lint_finding "broken-link blocking" "$out" blocking "broken-link" || ok=false
    $ok
}

# L5: orphan page (no inbound link) -> warn, exit 0.
l5_lint_orphan_page() {
    local wiki; wiki=$(stage_fresh_wiki l5)
    # widget links to companion (companion gets an inbound link). Nothing links
    # to widget, so widget is the orphan.
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    write_valid_concept_page "$wiki" companion
    add_index_entry_concept "$wiki" companion
    printf '\nSee [companion](companion.md).\n' >> "$wiki/concepts/widget.md"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "orphan warn" "$out" warn "orphan" || ok=false
    $ok
}

# L6: [[wikilink]] outside fenced code blocks -> warn.
l6_lint_wikilink_syntax() {
    local wiki; wiki=$(stage_fresh_wiki l6)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    write_valid_concept_page "$wiki" companion
    add_index_entry_concept "$wiki" companion
    # Inject a [[…]] reference in widget.md body.
    printf '\nSee [[companion]] for context.\n' >> "$wiki/concepts/widget.md"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "wikilink warn" "$out" warn "wikilink" || ok=false
    $ok
}

# L7: page not referenced in index.md -> warn.
l7_lint_page_missing_from_index() {
    local wiki; wiki=$(stage_fresh_wiki l7)
    write_valid_concept_page "$wiki" widget
    # Deliberately skip add_index_entry_concept.
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "index warn" "$out" warn "index" || ok=false
    $ok
}

# L8: tag not in SCHEMA.md taxonomy -> warn.
l8_lint_off_taxonomy_tag() {
    local wiki; wiki=$(stage_fresh_wiki l8)
    customize_taxonomy "$wiki"   # define a live taxonomy (template example is fenced)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    # Replace the tags line with a tag that's not in the defined taxonomy.
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("tags: [model]", "tags: [imaginary-not-in-taxonomy]"))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "tag warn" "$out" warn "tag" || ok=false
    $ok
}

# L9: raw file sha256 mismatch -> drift warn.
l9_lint_raw_source_drift() {
    local wiki; wiki=$(stage_fresh_wiki l9)
    local raw="$wiki/raw/notes/probe.md"
    cat > "$raw" <<'EOF'
---
source_url: https://example.com/probe
ingested: 2026-05-01
sha256: 0000000000000000000000000000000000000000000000000000000000000000
---

Original body content.
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "drift warn" "$out" warn "drift" || ok=false
    $ok
}

# L10: SCHEMA.md prelude (H1 + attribution paragraph) drift -> boilerplate warn.
l10_lint_boilerplate_mismatch() {
    local wiki; wiki=$(stage_fresh_wiki l10)
    # Rewrite the H1 + conventions blockquote (everything above the first `##`).
    # The log.md preamble is the one defended VERBATIM_SLOT: its exact wording is
    # the format documentation every entry is written against. The SCHEMA.md
    # attribution paragraph is deliberately not a slot — L52 covers that.
    python3 - "$wiki/log.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
i = text.find("\n## ")
rest = text[i:] if i != -1 else ""
p.write_text("# Custom Log Title\n\n> House conventions instead.\n" + rest)
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "boilerplate warn" "$out" warn "boilerplate" || ok=false
    $ok
}

# L11: undeclared custom frontmatter field -> warn.
l11_lint_undeclared_custom_field() {
    local wiki; wiki=$(stage_fresh_wiki l11)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    # Inject a custom key that's not declared in SCHEMA.md.
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("confidence: medium\n", "confidence: medium\nstatus: draft\n"))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "custom-field warn" "$out" warn "custom-field" || ok=false
    $ok
}

# L12: stale page (updated > 90d older than newest cited source's ingested) -> warn.
l12_lint_stale_page() {
    local wiki; wiki=$(stage_fresh_wiki l12)
    # Stage a raw source dated today, then a page updated 2020-01-01 that cites it.
    local today; today=$(date -u +%Y-%m-%d)
    mkdir -p "$wiki/raw/notes"
    cat > "$wiki/raw/notes/fresh.md" <<EOF
---
source_url: https://example.com/fresh
ingested: $today
sha256: $(printf 'hello\n' | shasum -a 256 | awk '{print $1}')
---

hello
EOF
    # Compute the right hash for the raw file via the canonical script so the
    # drift check doesn't co-fire and muddy the assertion.
    python3 "$WIKI_SKILL/scripts/compute_sha256.py" "$wiki/raw/notes/fresh.md" >/dev/null 2>&1
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace("updated: 2026-05-01", "updated: 2020-01-01")
text = text.replace("sources: []", "sources: [raw/notes/fresh.md]")
p.write_text(text)
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "stale info" "$out" info "stale" || ok=false
    $ok
}

# L13: oversized page (>200 lines) -> info.
l13_lint_oversized_page() {
    local wiki; wiki=$(stage_fresh_wiki l13)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    # Append 220 lines of body content.
    python3 -c "
import pathlib
p = pathlib.Path('$wiki/concepts/widget.md')
p.write_text(p.read_text() + '\n' + '\n'.join(f'Line {i}.' for i in range(220)) + '\n')
"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "size info" "$out" info "size" || ok=false
    $ok
}

# L14: taxonomy-style drift in SCHEMA.md -> info.
l14_lint_taxonomy_style_drift() {
    local wiki; wiki=$(stage_fresh_wiki l14)
    # The template ships its example taxonomy fenced (documentation, not live
    # config), so inject a live but non-canonical (emphasized-label) bullet
    # under the heading to trip the taxonomy-style check.
    python3 - "$wiki/SCHEMA.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
marker = "## Tag Taxonomy\n"
p.write_text(text.replace(marker, marker + "\n- **Models:** model, architecture\n", 1))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "taxonomy-style info" "$out" info "taxonomy-style" || ok=false
    $ok
}

# L15: markdown style nit (trailing punctuation in header) -> info md-style.
l15_lint_markdown_style_nit() {
    local wiki; wiki=$(stage_fresh_wiki l15)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    # Append a header with trailing punctuation.
    printf '\n## Related:\n\nMore notes.\n' >> "$wiki/concepts/widget.md"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "md-style info" "$out" info "md-style" || ok=false
    $ok
}

# L16: sources: frontmatter entry that doesn't resolve on disk -> blocking.
l16_lint_broken_source_path() {
    local wiki; wiki=$(stage_fresh_wiki l16)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    # Rewrite sources: to point at a path that doesn't exist under raw/.
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace(
    "sources: []",
    "sources: [raw/articles/does-not-exist.md]",
))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_lint_finding "broken-source blocking" "$out" blocking "broken-source" || ok=false
    $ok
}

# L17: deprecated body `## Sources` H2 section -> info.
l17_lint_sources_section() {
    local wiki; wiki=$(stage_fresh_wiki l17)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    # Append a bottom-of-page Sources collection — the deprecated convention.
    cat >> "$wiki/concepts/widget.md" <<'EOF'

## Sources

- raw/articles/some-paper.md
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "sources-section info" "$out" info "sources-section" || ok=false
    $ok
}

# L18: footnote `[^name]` reference and definition in body -> warn.
l18_lint_footnote_syntax() {
    local wiki; wiki=$(stage_fresh_wiki l18)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    # Insert a footnote reference in prose and a definition at the bottom.
    cat >> "$wiki/concepts/widget.md" <<'EOF'

Widgets are well-studied.[^smith2024]

[^smith2024]: raw/articles/some-paper.md
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "footnote warn" "$out" warn "footnote" || ok=false
    $ok
}

# L19: inline path-link attribution across three sources -> no footnote finding.
l19_lint_inline_path_links_are_not_footnotes() {
    local wiki; wiki=$(stage_fresh_wiki l19)
    write_valid_concept_page "$wiki" synthesis
    add_index_entry_concept "$wiki" synthesis
    mkdir -p "$wiki/raw/articles"
    for slug in alpha beta gamma; do
        cat > "$wiki/raw/articles/$slug.md" <<EOF
---
source_url: https://example.com/$slug
ingested: 2026-05-01
---

$slug source body.
EOF
    done
    python3 - "$wiki/concepts/synthesis.md" <<'PY'
import pathlib
import sys

page = pathlib.Path(sys.argv[1])
text = page.read_text()
text = text.replace(
    "sources: []",
    "sources: [raw/articles/alpha.md, raw/articles/beta.md, raw/articles/gamma.md]",
)
text += """

The synthesized claim draws on alpha ([alpha](../raw/articles/alpha.md)),
beta ([beta](../raw/articles/beta.md)), and gamma
([gamma](../raw/articles/gamma.md)).
"""
page.write_text(text)
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "inline path-link attribution" "$out" "footnote" || ok=false
    $ok
}

# L20: lint.py with no path argument in an ambiguous location -> discovery is
#      undecided. Exit 2 (distinct from blocking exit 1), and the hint names
#      the positional argument rather than the nonexistent --wiki-path flag.
l20_lint_undecided_hint() {
    local home; home=$(fresh_scratch l20)
    mkdir -p "$home/proj"   # no recognised wiki on the ladder -> undecided
    local out rc
    out=$(cd "$home/proj" && HOME="$home" python3 "$LINT" --quiet 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    if ! grep -q "positional argument" <<<"$out"; then
        log "    undecided hint did not name the positional argument"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    if grep -q -- "--wiki-path" <<<"$out"; then
        log "    stale --wiki-path hint still present"
        ok=false
    fi
    $ok
}

# L21: absolute `sources:` entry (even one that exists) -> blocking broken-source.
# Points sources: at an ABSOLUTE path to a file that DOES exist (the wiki's own
# SCHEMA.md). Python's join lets an absolute entry override `wiki /` and resolve,
# so the old check passed it; the portable-path rule must block it for being
# absolute, independent of on-disk existence.
l21_lint_absolute_sources_entry() {
    local wiki; wiki=$(stage_fresh_wiki l21)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    python3 - "$wiki/concepts/widget.md" "$wiki/SCHEMA.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
abs_src = str(pathlib.Path(sys.argv[2]).resolve())
p.write_text(p.read_text().replace("sources: []", f"sources: [{abs_src}]"))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_lint_finding "absolute sources blocking" "$out" blocking "broken-source" || ok=false
    $ok
}

# L22: raw sidecar with an absolute `source_path:` -> blocking raw-source-path.
l22_lint_raw_source_path_absolute() {
    local wiki; wiki=$(stage_fresh_wiki l22)
    cat > "$wiki/raw/meetings/bad.md" <<'EOF'
---
source_path: /Users/someone/logs/session.md
ingested: 2026-05-01
---

Local file on the author's workstation; excerpt below.
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_lint_finding "absolute source_path blocking" "$out" blocking "raw-source-path" || ok=false
    $ok
}

# L23: a repo-relative resolvable `source_path:` and a prose-only out-of-repo
# sidecar (no path at all) both pass -> no raw-source-path finding.
l23_lint_source_path_portable_ok() {
    local wiki; wiki=$(stage_fresh_wiki l23)
    cat > "$wiki/raw/notes/in-repo.md" <<'EOF'
---
source_path: SCHEMA.md
ingested: 2026-05-01
---

In-repo source mirror.
EOF
    cat > "$wiki/raw/meetings/out-of-repo.md" <<'EOF'
---
ingested: 2026-05-01
---

Local file on the author's workstation; relevant content excerpted below.
EOF
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_no_lint_category "portable source_path clean" "$out" "raw-source-path" || ok=false
    $ok
}

# L24: raw sidecar with a RELATIVE `source_path:` that escapes the git repo
# (../..) -> blocking raw-source-path. A relative path is not enough; it must
# stay inside the repo to be portable, matching the sibling sources: escape rule.
l24_lint_raw_source_path_escape() {
    local wiki; wiki=$(stage_fresh_wiki_in_repo l24)   # wiki is <repo>/wiki
    # ../../ from <repo>/wiki lands above <repo>, escaping the repo entirely.
    cat > "$wiki/raw/notes/escape.md" <<'EOF'
---
source_path: ../../outside-repo.md
ingested: 2026-05-01
---

Relative, but escapes the repo — must not pass.
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_lint_finding "escaping source_path blocking" "$out" blocking "raw-source-path" || ok=false
    $ok
}

# L25: relative `sources:` entry that escapes the raw/ tree (concepts/other.md)
# -> blocking broken-source (the Approach-named escape fixture).
l25_lint_sources_escape_raw() {
    local wiki; wiki=$(stage_fresh_wiki l25)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("sources: []", "sources: [concepts/other.md]"))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_lint_finding "escaping sources blocking" "$out" blocking "broken-source" || ok=false
    $ok
}

# L26: a RELATIVE `source_path:` that leaves the wiki dir but stays inside the
# repo (../shared/spec.md) -> clean. The repo is the portability boundary, not
# the wiki, so an in-repo source outside the wiki directory is allowed.
l26_lint_source_path_in_repo_outside_wiki() {
    local wiki; wiki=$(stage_fresh_wiki_in_repo l26)
    local repo="${wiki%/wiki}"
    mkdir -p "$repo/shared"
    printf 'in-repo source outside the wiki dir\n' > "$repo/shared/spec.md"
    cat > "$wiki/raw/notes/mirror.md" <<'EOF'
---
source_path: ../shared/spec.md
ingested: 2026-05-01
---

Sidecar for an in-repo source that lives outside the wiki directory.
EOF
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_no_lint_category "in-repo outside-wiki source_path clean" "$out" "raw-source-path" || ok=false
    $ok
}

# L27: a wiki NOT inside any git repo is local-only — it ships nowhere, so
# source_path is unconstrained and the portability check is skipped entirely.
# Staged via mktemp OUTSIDE the ai-modules tree so no `.git` ancestor exists;
# an absolute source_path (which blocks inside a repo) is clean here.
l27_lint_non_repo_wiki_unrestricted() {
    local base; base=$(mktemp -d)
    local wiki="$base/wiki"
    "$INIT" "$wiki" >/dev/null 2>&1
    if git -C "$wiki" rev-parse --show-toplevel >/dev/null 2>&1; then
        log "    [skip l27: mktemp dir is unexpectedly inside a git repo]"
        rm -rf "$base"; return 0
    fi
    cat > "$wiki/raw/notes/local.md" <<'EOF'
---
source_path: /Users/someone/logs/session.md
ingested: 2026-05-01
---

Absolute path — valid for a local-only wiki that never ships.
EOF
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_no_lint_category "non-repo wiki source_path unrestricted" "$out" "raw-source-path" || ok=false
    rm -rf "$base"
    $ok
}

# L28: block-style `tags:`/`sources:` validate exactly like inline lists.
# Before the parser learned block lists, an indented `- item` list parsed as an
# empty string and every consumer validated nothing; now the off-taxonomy tag
# and both bad sources fire as they would inline. (Inline parity is covered by
# l8/l16/l21/l25, which share the same downstream consumers.)
l28_lint_block_style_frontmatter() {
    local wiki; wiki=$(stage_fresh_wiki l28)
    customize_taxonomy "$wiki"   # live taxonomy so the off-taxonomy tag fires
    cat > "$wiki/concepts/widget.md" <<'EOF'
---
title: widget
created: 2026-05-01
updated: 2026-05-01
type: concept
tags:
  - imaginary-not-in-taxonomy
sources:
  - raw/articles/missing.md
  - /abs/outside.md
confidence: medium
---

# widget

Block-style frontmatter fixture.
EOF
    add_index_entry_concept "$wiki" widget
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_lint_finding "block-list off-taxonomy tag" "$out" warn "tag" || ok=false
    assert_lint_finding "block-list broken-source" "$out" blocking "broken-source" || ok=false
    $ok
}

# L29: a required list field whose block content the parser cannot read (a
# nested mapping rather than `- item` lines) parses to empty and trips the
# frontmatter belt warn.
l29_lint_frontmatter_unreadable_block() {
    local wiki; wiki=$(stage_fresh_wiki l29)
    cat > "$wiki/concepts/widget.md" <<'EOF'
---
title: widget
created: 2026-05-01
updated: 2026-05-01
type: concept
tags:
  domain: ai
sources: []
confidence: medium
---

# widget

Belt fixture: tags block the parser cannot read as a list.
EOF
    add_index_entry_concept "$wiki" widget
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "frontmatter belt warn" "$out" warn "frontmatter" || ok=false
    $ok
}

# L30: broken links inside a fence and inline code do NOT block; a genuine
# broken link outside code still blocks; and an inbound link that sits inside a
# fence is not counted, so its target is reported as an orphan. target links
# back to widget with a real link so widget is not an orphan — isolating the
# fenced-inbound case to target alone.
l30_lint_link_code_fence_handling() {
    local wiki; wiki=$(stage_fresh_wiki l30)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    write_valid_concept_page "$wiki" target
    add_index_entry_concept "$wiki" target
    printf '\nSee [widget](widget.md).\n' >> "$wiki/concepts/target.md"
    cat >> "$wiki/concepts/widget.md" <<'EOF'

```markdown
See [fenced example](concepts/does-not-exist-fenced.md) and [target](target.md).
```

Inline: `[inline example](concepts/does-not-exist-inline.md)`.

A genuinely [broken link](concepts/does-not-exist-real.md) outside code.
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_lint_finding "real broken link blocks" "$out" blocking "broken-link" || ok=false
    if printf '%s' "$out" | grep -qE "does-not-exist-(fenced|inline)"; then
        log "    [fenced/inline example link wrongly flagged as broken]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    if ! printf '%s' "$out" | grep -E "\borphan\b" | grep -q "concepts/target.md"; then
        log "    [target not reported as orphan — fenced inbound link wrongly counted?]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    $ok
}

# L31: a freshly-initialized wiki carries the fenced example taxonomy, which is
# documentation, not live config — so no example-tag findings, and the "no Tag
# Taxonomy section" schema warn fires until a real taxonomy is defined. A
# customized (unfenced) taxonomy is read again and the schema warn clears.
l31_lint_fresh_wiki_taxonomy_absent() {
    local wiki; wiki=$(stage_fresh_wiki l31)
    local ret; ret=$(run_lint "$wiki")   # no --quiet: info findings are visible
    local out=${ret#*|}
    local ok=true
    assert_no_lint_category "no example-tag findings on fresh wiki" "$out" "tag" || ok=false
    assert_lint_finding "no-taxonomy warn" "$out" warn "schema" || ok=false
    customize_taxonomy "$wiki"
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_lint_category "customized taxonomy read (schema warn clears)" "$out" "schema" || ok=false
    $ok
}

# L32: index membership matches on resolved link targets, not substring, so an
# unlisted page (alignment.md) whose name is a substring of a listed one
# (misalignment.md) is flagged; and a dangling index entry pointing at a
# nonexistent page is flagged in the new direction.
l32_lint_index_membership_and_dangling() {
    local wiki; wiki=$(stage_fresh_wiki l32)
    write_valid_concept_page "$wiki" misalignment
    add_index_entry_concept "$wiki" misalignment
    write_valid_concept_page "$wiki" alignment   # deliberately NOT listed
    python3 - "$wiki/index.md" <<'PY'
import sys, pathlib
idx = pathlib.Path(sys.argv[1])
marker = "## Concepts\n"
entry = "- [ghost](concepts/ghost.md) — nonexistent\n"
idx.write_text(idx.read_text().replace(marker, marker + "\n" + entry, 1))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    if ! printf '%s' "$out" | grep -E "\bindex\b" | grep -q "concepts/alignment.md"; then
        log "    [alignment.md not flagged as unlisted — substring match still in play?]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    if ! printf '%s' "$out" | grep -E "\bindex\b" | grep -q "ghost.md"; then
        log "    [dangling index entry (ghost.md) not flagged]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    $ok
}

# L33: the drift message names the wiki-root-relative path (not a bare
# basename), and the path it quotes runs from the wiki root and refreshes the
# hash. (scripts/ in the message is skill-relative and unchanged; defect 5 is
# the PATH ARG.)
l33_lint_drift_message_wiki_relative_path() {
    local wiki; wiki=$(stage_fresh_wiki l33)
    mkdir -p "$wiki/raw/notes"
    cat > "$wiki/raw/notes/probe.md" <<'EOF'
---
source_url: https://example.com/probe
ingested: 2026-05-01
sha256: 0000000000000000000000000000000000000000000000000000000000000000
---

Body content that does not match the recorded hash.
EOF
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_lint_finding "drift warn" "$out" warn "drift" || ok=false
    if ! printf '%s' "$out" | grep -qE "compute_sha256\.py raw/notes/probe\.md"; then
        log "    [drift message did not name the wiki-relative path]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    local quoted_path
    quoted_path=$(printf '%s' "$out" | grep -oE "compute_sha256\.py [^\` ]+" | head -1 | awk '{print $2}')
    assert_eq "quoted path is wiki-relative" "$quoted_path" "raw/notes/probe.md" || ok=false
    local cmd_rc
    (cd "$wiki" && python3 "$SHA256" "$quoted_path" >/dev/null 2>&1) && cmd_rc=0 || cmd_rc=$?
    assert_eq "quoted command exit" "$cmd_rc" "0" || ok=false
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_lint_category "drift cleared after refresh" "$out" "drift" || ok=false
    $ok
}

# L34: an absolute body-link target that resolves on THIS machine still blocks
# (it dangles on every clone); the same link rewritten relative passes.
l34_lint_absolute_body_link() {
    local wiki; wiki=$(stage_fresh_wiki l34)
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    write_valid_concept_page "$wiki" target
    add_index_entry_concept "$wiki" target
    local abs_target
    abs_target=$(python3 -c "import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())" "$wiki/concepts/target.md")
    printf '\nSee [target](%s).\n' "$abs_target" >> "$wiki/concepts/widget.md"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_lint_finding "absolute body link blocks" "$out" blocking "broken-link" || ok=false
    python3 - "$wiki/concepts/widget.md" "$abs_target" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace(f"[target]({sys.argv[2]})", "[target](target.md)"))
PY
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_lint_category "relative link passes" "$out" "broken-link" || ok=false
    $ok
}

# L35: a raw sidecar outside raw/assets/ missing ingested+sha256 is flagged
# (warn); a raw/assets/ companion with no frontmatter is exempt; stamping the
# fields clears the finding.
l35_lint_raw_frontmatter_presence() {
    local wiki; wiki=$(stage_fresh_wiki l35)
    cat > "$wiki/raw/notes/bare.md" <<'EOF'
---
source_url: https://example.com/x
---

Raw body without ingested or sha256.
EOF
    printf 'binary-ish companion, no frontmatter\n' > "$wiki/raw/assets/diagram.md"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_lint_finding "raw missing metadata" "$out" warn "raw-frontmatter" || ok=false
    if printf '%s' "$out" | grep -E "raw-frontmatter" | grep -q "assets/diagram"; then
        log "    [raw/assets file wrongly flagged for missing frontmatter]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    cat > "$wiki/raw/notes/bare.md" <<'EOF'
---
source_url: https://example.com/x
ingested: 2026-05-01
---

Raw body without ingested or sha256.
EOF
    python3 "$SHA256" "$wiki/raw/notes/bare.md" >/dev/null 2>&1
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_lint_category "raw-frontmatter clears after fix" "$out" "raw-frontmatter" || ok=false
    $ok
}

# L36: origin-field value forms (gap 1) fire everywhere, including a wiki NOT
# inside a git repo (where check_source_path_portable is skipped). A file:// or
# bare-path source_url, a remote-URL source_path, and a both-fields sidecar each
# warn raw-origin; a genuine remote source_url and a plain relative source_path
# do not. Staged via mktemp OUTSIDE the ai-modules tree so no `.git` ancestor
# exists — proving the check does not depend on the wiki living in a repo. With
# no repo to resolve against, the file:///bare-path redirects carry no computed
# `-> ` rewrite suffix (that is exercised in-repo by l40).
l36_lint_raw_origin_forms_non_repo() {
    local base; base=$(mktemp -d)
    local wiki="$base/wiki"
    "$INIT" "$wiki" >/dev/null 2>&1
    if git -C "$wiki" rev-parse --show-toplevel >/dev/null 2>&1; then
        log "    [skip l36: mktemp dir is unexpectedly inside a git repo]"
        rm -rf "$base"; return 0
    fi
    cat > "$wiki/raw/notes/url-fileurl.md" <<'EOF'
---
source_url: file:///tmp/x.md
ingested: 2026-05-01
---
body
EOF
    cat > "$wiki/raw/notes/url-barepath.md" <<'EOF'
---
source_url: some/relative/path.md
ingested: 2026-05-01
---
body
EOF
    cat > "$wiki/raw/articles/url-remote.md" <<'EOF'
---
source_url: https://example.com/x
ingested: 2026-05-01
---
body
EOF
    cat > "$wiki/raw/notes/path-url.md" <<'EOF'
---
source_path: https://example.com/x
ingested: 2026-05-01
---
body
EOF
    cat > "$wiki/raw/notes/path-plain.md" <<'EOF'
---
source_path: SCHEMA.md
ingested: 2026-05-01
---
body
EOF
    cat > "$wiki/raw/notes/both.md" <<'EOF'
---
source_url: https://example.com/x
source_path: SCHEMA.md
ingested: 2026-05-01
---
body
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit (all warns, none blocking)" "$rc" "0" || ok=false
    assert_finding_for_file "file:// source_url"   "$out" warn raw-origin "url-fileurl.md"  || ok=false
    assert_finding_for_file "bare-path source_url" "$out" warn raw-origin "url-barepath.md" || ok=false
    assert_no_finding_for_file "remote source_url ok" "$out" raw-origin "url-remote.md" || ok=false
    assert_finding_for_file "URL in source_path"   "$out" warn raw-origin "path-url.md"    || ok=false
    assert_no_finding_for_file "plain source_path ok" "$out" raw-origin "path-plain.md" || ok=false
    assert_finding_for_file "both fields"          "$out" warn raw-origin "both.md"        || ok=false
    # Non-repo wiki: `_git_repo_root` is None, so the file:///bare-path redirects
    # carry no computed `-> ` rewrite suffix (nothing to resolve against).
    assert_no_origin_rewrite "file:// non-repo no rewrite"   "$out" "url-fileurl.md"  || ok=false
    assert_no_origin_rewrite "bare-path non-repo no rewrite" "$out" "url-barepath.md" || ok=false
    rm -rf "$base"
    $ok
}

# L37: in a wiki that IS inside a git repo, a URL-valued source_path yields the
# single redirecting raw-origin warn (gap 1 carve-out) — NOT a duplicate
# alongside a blocking raw-source-path "does not resolve" error.
# check_source_path_portable yields the remote-scheme case to
# check_raw_origin_form.
l37_lint_url_source_path_single_finding_in_repo() {
    local wiki; wiki=$(stage_fresh_wiki_in_repo l37)
    cat > "$wiki/raw/notes/url-in-path.md" <<'EOF'
---
source_path: https://example.com/x
ingested: 2026-05-01
---
body
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit (warn, not blocking)" "$rc" "0" || ok=false
    assert_finding_for_file "redirect warn" "$out" warn raw-origin "url-in-path.md" || ok=false
    assert_no_finding_for_file "no duplicate raw-source-path" "$out" raw-source-path "url-in-path.md" || ok=false
    $ok
}

# L38: an absolute source_path that resolves to an in-repo file (gap 6) is a
# safe-auto-fix WARN carrying the computed repo-relative rewrite, not a block.
# The existing outside-repo absolute case (l22) stays blocking.
l38_lint_abs_source_path_in_repo_warns_with_rewrite() {
    local wiki; wiki=$(stage_fresh_wiki_in_repo l38)
    local repo="${wiki%/wiki}"
    mkdir -p "$repo/shared"
    printf 'in-repo spec body\n' > "$repo/shared/spec.md"
    local abs_spec
    abs_spec=$(python3 -c "import pathlib,sys;print(pathlib.Path(sys.argv[1]).resolve())" "$repo/shared/spec.md")
    cat > "$wiki/raw/notes/absin.md" <<EOF
---
source_path: $abs_spec
ingested: 2026-05-01
---
body
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit (warn, not blocking)" "$rc" "0" || ok=false
    assert_finding_for_file "in-repo absolute warn" "$out" warn raw-source-path "absin.md" || ok=false
    # The warn message carries the computed repo-relative rewrite (relative to
    # the wiki root): ../shared/spec.md.
    if ! printf '%s' "$out" | grep -F "raw-source-path" | grep -qF "../shared/spec.md"; then
        log "    [warn message did not carry the repo-relative rewrite ../shared/spec.md]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    $ok
}

# L39: an absolute sources: entry that resolves inside the wiki's raw/ tree
# (gap 6) is a safe-auto-fix WARN carrying its raw/…-relative rewrite, not a
# block. The existing outside-raw/ absolute case (l21) stays blocking.
l39_lint_abs_sources_in_raw_warns_with_rewrite() {
    local wiki; wiki=$(stage_fresh_wiki l39)
    cat > "$wiki/raw/articles/real.md" <<'EOF'
---
source_url: https://example.com/real
ingested: 2026-05-01
---

real source body.
EOF
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    python3 - "$wiki/concepts/widget.md" "$wiki/raw/articles/real.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
abs_src = str(pathlib.Path(sys.argv[2]).resolve())
p.write_text(p.read_text().replace("sources: []", f"sources: [{abs_src}]"))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit (warn, not blocking)" "$rc" "0" || ok=false
    assert_finding_for_file "in-raw absolute warn" "$out" warn broken-source "widget.md" || ok=false
    if ! printf '%s' "$out" | grep -F "broken-source" | grep -qF "raw/articles/real.md"; then
        log "    [warn message did not carry the raw/…-relative rewrite raw/articles/real.md]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    $ok
}

# L40: a `file://`/bare-path `source_url:` whose value names an in-repo target
# one directory OUTSIDE the wiki (the pre-split migration shape
# `sources/earlier-versions/foo.md`, a repo-root sibling of the wiki) is
# resolved against the REPO ROOT, and the raw-origin warn carries the computed
# wiki-root-relative rewrite `-> ../sources/earlier-versions/foo.md`. This proves
# the anchor is the repo root, not the wiki root: a wiki-root join would miss the
# file and, if forced, re-emit the lint-failing `sources/…`. A value resolving to
# no in-repo file, and an out-of-repo target, each warn with NO computed `-> `
# suffix (the out-of-repo case routes to the excerpt rule). The absolute-path
# sibling of this safe-fix is l38; the non-repo no-suffix case is l36.
l40_lint_raw_origin_fileurl_in_repo_rewrite() {
    local wiki; wiki=$(stage_fresh_wiki_in_repo l40)
    local repo="${wiki%/wiki}"
    mkdir -p "$repo/sources/earlier-versions"
    printf 'legacy pre-split source carried into a code repo\n' > "$repo/sources/earlier-versions/foo.md"
    # (a) anchorless file:// naming a repo-root sibling one dir outside the wiki
    cat > "$wiki/raw/notes/fileurl-inrepo.md" <<'EOF'
---
source_url: file://sources/earlier-versions/foo.md
ingested: 2026-05-01
---
body
EOF
    # (b) anchorless bare-path naming the same repo-root sibling
    cat > "$wiki/raw/notes/barepath-inrepo.md" <<'EOF'
---
source_url: sources/earlier-versions/foo.md
ingested: 2026-05-01
---
body
EOF
    # (c) bare-path naming a non-existent in-repo file -> no computed rewrite
    cat > "$wiki/raw/notes/noresolve.md" <<'EOF'
---
source_url: sources/does-not-exist.md
ingested: 2026-05-01
---
body
EOF
    # (d) out-of-repo file:// -> no computed rewrite; still routes to excerpt rule
    cat > "$wiki/raw/notes/outofrepo.md" <<'EOF'
---
source_url: file:///tmp/not-in-repo.md
ingested: 2026-05-01
---
body
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit (all warns, none blocking)" "$rc" "0" || ok=false
    assert_finding_for_file "file:// in-repo warn"   "$out" warn raw-origin "fileurl-inrepo.md"  || ok=false
    assert_finding_for_file "bare-path in-repo warn" "$out" warn raw-origin "barepath-inrepo.md" || ok=false
    # (a)+(b): the warn carries the repo-root-resolved, wiki-root-relative rewrite.
    assert_origin_rewrite "file:// carries rewrite"   "$out" "fileurl-inrepo.md"  "../sources/earlier-versions/foo.md" || ok=false
    assert_origin_rewrite "bare-path carries rewrite" "$out" "barepath-inrepo.md" "../sources/earlier-versions/foo.md" || ok=false
    # (c)+(d): the warn fires but carries no computed `-> ` suffix.
    assert_no_origin_rewrite "no-resolve has no rewrite"  "$out" "noresolve.md" || ok=false
    assert_no_origin_rewrite "out-of-repo has no rewrite" "$out" "outofrepo.md" || ok=false
    $ok
}

###############################################################################
# Accepted-finding scenarios (per-finding info-level acceptance store)
###############################################################################

# Replace the live `- Accepted finding:` bullets in SCHEMA.md with the given
# payloads — one argument per bullet, each without the `- Accepted finding: `
# label. `## Lint` is the template's last section, so an appended bullet lands
# inside it and unfenced, which is what makes it live config. Pass no payload to
# clear the store. Use add_fenced_accept_bullet for the documentation-only form.
set_accept_bullets() {
    local wiki=$1
    shift
    python3 - "$wiki/SCHEMA.md" "$@" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
kept = [ln for ln in p.read_text().splitlines() if not ln.startswith("- Accepted finding:")]
while kept and kept[-1] == "":
    kept.pop()
if sys.argv[2:]:
    kept.append("")
    kept.extend(f"- Accepted finding: {payload}" for payload in sys.argv[2:])
p.write_text("\n".join(kept) + "\n")
PY
}

# Append an acceptance bullet inside a fenced block in SCHEMA.md — the shape a
# wiki uses to document the mechanism. The linter must read it as documentation,
# never as a live acceptance.
add_fenced_accept_bullet() {
    local wiki=$1 payload=$2
    printf '\n```text\n- Accepted finding: %s\n```\n' "$payload" >> "$wiki/SCHEMA.md"
}

# Append body lines until a page passes the 200-line soft cap, so `check_page_size`
# emits its `size` info finding. Args: <page> [line_count]
grow_page_past_soft_cap() {
    local page=$1 count=${2:-220}
    python3 - "$page" "$count" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text() + "\n" + "\n".join(f"Line {i}." for i in range(int(sys.argv[2]))) + "\n")
PY
}

# Append <count> `## [date]` entries to log.md so `check_log_rotation` fires
# (its threshold is 500 entries). The filler index continues from the entries
# already in the file, so a second call adds fresh headings instead of repeating
# the first call's and tripping `check_log_heading_uniqueness`.
# Args: <wiki> <count>
append_log_entries() {
    local wiki=$1 count=$2
    python3 - "$wiki/log.md" "$count" <<'APPENDLOG'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
start = sum(1 for line in text.splitlines() if line.startswith("## ["))
entries = "".join(
    f"\n## [2026-01-01] lint | filler {i}\n\n- filler entry {i}\n"
    for i in range(start, start + int(sys.argv[2]))
)
p.write_text(text + entries)
APPENDLOG
}

# Echo the N from the report's `total: N  (...)` line — the live finding count,
# which an accepted finding must leave.
lint_total() {
    printf '%s\n' "$1" | sed -n 's/^total: \([0-9]*\).*/\1/p' | head -1
}

# Assert a live finding line — a `[severity]` bucket line, never an `(accepted)`
# context line — exists for <file> carrying <message substring>. Message-scoped,
# so a scenario can pin one of several findings a page emits in one category.
# Args: <label> <output> <file> <message substring>
assert_live_message() {
    local label=$1 out=$2 file=$3 msg=$4
    if printf '%s' "$out" | grep -E "^[[:space:]]*\[[a-z]+[[:space:]]*\]" \
        | grep -F "$file" | grep -qF "$msg"; then
        return 0
    fi
    log "    [missing live finding: $label — expected $file carrying '$msg']"
    printf '%s\n' "$out" | indent
    return 1
}

# Assert NO live finding line for <file> carries <message substring>.
# Args: <label> <output> <file> <message substring>
assert_no_live_message() {
    local label=$1 out=$2 file=$3 msg=$4
    if printf '%s' "$out" | grep -E "^[[:space:]]*\[[a-z]+[[:space:]]*\]" \
        | grep -F "$file" | grep -qF "$msg"; then
        log "    [unexpected live finding: $label — $file still carries '$msg']"
        printf '%s\n' "$out" | indent
        return 1
    fi
    return 0
}

# Assert the acknowledged section lists an accepted finding of <category> for
# <file>. The section is context only: it carries no `[severity]` bracket, so it
# never reads as a finding that still wants action.
# Args: <label> <output> <category> <file>
assert_acknowledged() {
    local label=$1 out=$2 cat=$3 file=$4
    local ok=true
    printf '%s' "$out" | grep -Eq "^ACKNOWLEDGED \([0-9]+\)" || ok=false
    printf '%s' "$out" | grep -E "^[[:space:]]*\(accepted\)[[:space:]]+${cat}[[:space:]]" \
        | grep -qF "$file" || ok=false
    if $ok; then
        return 0
    fi
    log "    [missing acknowledgement: $label — expected an (accepted) $cat line for $file under ACKNOWLEDGED]"
    printf '%s\n' "$out" | indent
    return 1
}

# Assert the report carries no acknowledged section at all.
assert_no_acknowledged_section() {
    local label=$1 out=$2
    if printf '%s' "$out" | grep -q "^ACKNOWLEDGED"; then
        log "    [unexpected acknowledged section: $label]"
        printf '%s\n' "$out" | indent
        return 1
    fi
    return 0
}

# Assert a page body carries no acceptance marker — the store lives in
# SCHEMA.md's `## Lint` section alone. Args: <label> <page>
assert_no_body_acceptance_marker() {
    local label=$1 page=$2
    if grep -qiE "accepted finding|lint-accept|lint:ignore|noqa" "$page"; then
        log "    [page body carries an acceptance marker: $label — $page]"
        grep -niE "accepted finding|lint-accept|lint:ignore|noqa" "$page" | indent
        return 1
    fi
    return 0
}

# L41: an info finding accepted on a live `## Lint` bullet leaves the live report
# and the live count, its unaccepted sibling still appears normally, and the
# acceptance is stored in SCHEMA.md alone — the accepted page body carries no marker.
l41_lint_accepted_info_leaves_live_report() {
    local wiki; wiki=$(stage_fresh_wiki l41)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    write_valid_concept_page "$wiki" gadget
    add_index_entry_concept "$wiki" widget
    add_index_entry_concept "$wiki" gadget
    grow_page_past_soft_cap "$wiki/concepts/widget.md"
    grow_page_past_soft_cap "$wiki/concepts/gadget.md"

    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    local before; before=$(lint_total "$out")
    assert_finding_for_file "baseline size on widget" "$out" info size "concepts/widget.md" || ok=false
    assert_finding_for_file "baseline size on gadget" "$out" info size "concepts/gadget.md" || ok=false

    set_accept_bullets "$wiki" "size — concepts/widget.md"
    ret=$(run_lint "$wiki"); out=${ret#*|}
    local after; after=$(lint_total "$out")
    assert_eq "live total drops by exactly the accepted finding" "$after" "$((before - 1))" || ok=false
    assert_no_finding_for_file "accepted size left the live report" "$out" size "concepts/widget.md" || ok=false
    assert_finding_for_file "unaccepted size still live" "$out" info size "concepts/gadget.md" || ok=false
    assert_acknowledged "accepted size listed as context only" "$out" size "concepts/widget.md" || ok=false
    assert_no_body_acceptance_marker "accepted page body" "$wiki/concepts/widget.md" || ok=false
    $ok
}

# L42: acceptance reaches info findings alone. One page carries a `quality` warn
# (contested) and a `quality` info (confidence: low); each gets an acceptance
# bullet matching its text exactly, and only the info one leaves the live report.
l42_lint_acceptance_never_suppresses_non_info() {
    local wiki; wiki=$(stage_fresh_wiki l42)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("confidence: medium", "confidence: low\ncontested: true"))
PY
    set_accept_bullets "$wiki" \
        "quality — concepts/widget.md — contested: true — reconcile or document the dispute" \
        "quality — concepts/widget.md — confidence: low — corroborate or note why"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_live_message "contested warn stays live" "$out" "concepts/widget.md" "contested: true" || ok=false
    assert_no_live_message "low-confidence info accepted" "$out" "concepts/widget.md" "confidence: low" || ok=false
    assert_acknowledged "low-confidence info listed as context" "$out" quality "concepts/widget.md" || ok=false
    $ok
}

# L43: an acceptance bullet inside a fenced example is documentation. The finding
# stays live and no acknowledged section appears (fence-safe parse).
l43_lint_fenced_acceptance_is_documentation() {
    local wiki; wiki=$(stage_fresh_wiki l43)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    grow_page_past_soft_cap "$wiki/concepts/widget.md"
    add_fenced_accept_bullet "$wiki" "size — concepts/widget.md"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_finding_for_file "fenced acceptance suppresses nothing" "$out" info size "concepts/widget.md" || ok=false
    assert_no_acknowledged_section "no acknowledgement from a fenced bullet" "$out" || ok=false
    $ok
}

# L44: two line-less info findings share a path and differ only in message (two
# taxonomy tags nothing uses). A three-field acceptance whose discriminator equals
# one finding's message exactly accepts that one and leaves the sibling live.
l44_lint_discriminator_selects_one_of_two() {
    local wiki; wiki=$(stage_fresh_wiki l44)
    python3 - "$wiki/SCHEMA.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
marker = "## Tag Taxonomy\n"
p.write_text(p.read_text().replace(marker, marker + "\n- Domain: model, ghosttag, spooktag\n", 1))
PY
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    set_accept_bullets "$wiki" \
        "tag — SCHEMA.md — tag 'ghosttag' defined in taxonomy but unused on any page"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_no_live_message "accepted unused tag left the live report" "$out" "SCHEMA.md" "'ghosttag'" || ok=false
    assert_live_message "sibling unused tag still live" "$out" "SCHEMA.md" "'spooktag'" || ok=false
    assert_acknowledged "accepted unused tag listed as context" "$out" tag "SCHEMA.md" || ok=false
    $ok
}

# L45: the two-field (path-only) form keys on no message, so a `size` or `stale`
# acceptance keeps matching after that finding's volatile counter or date
# substring changes. `log` is deliberately absent: rotation is a warn/blocking
# finding cleared by rotating the log, never by acceptance (see L76/L77).
l45_lint_two_field_survives_volatile_message() {
    local wiki; wiki=$(stage_fresh_wiki l45)
    customize_taxonomy "$wiki"
    # size: an oversized page.
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    grow_page_past_soft_cap "$wiki/concepts/widget.md"
    # stale: a page whose `updated` trails its cited source's `ingested` by >90d.
    mkdir -p "$wiki/raw/notes"
    cat > "$wiki/raw/notes/fresh.md" <<'EOF'
---
source_url: https://example.com/fresh
ingested: 2026-04-01
sha256: placeholder
---

hello
EOF
    python3 "$WIKI_SKILL/scripts/compute_sha256.py" "$wiki/raw/notes/fresh.md" >/dev/null 2>&1
    write_valid_concept_page "$wiki" gadget
    add_index_entry_concept "$wiki" gadget
    python3 - "$wiki/concepts/gadget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text().replace("updated: 2026-05-01", "updated: 2020-01-01")
p.write_text(t.replace("sources: []", "sources: [raw/notes/fresh.md]"))
PY

    set_accept_bullets "$wiki" \
        "size — concepts/widget.md" \
        "stale — concepts/gadget.md"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_no_finding_for_file "size accepted" "$out" size "concepts/widget.md" || ok=false
    assert_no_finding_for_file "stale accepted" "$out" stale "concepts/gadget.md" || ok=false

    # Move every volatile substring: more lines, a later `updated`.
    grow_page_past_soft_cap "$wiki/concepts/widget.md" 40
    python3 - "$wiki/concepts/gadget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("updated: 2020-01-01", "updated: 2021-06-15"))
PY
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_finding_for_file "size still accepted after line count changed" "$out" size "concepts/widget.md" || ok=false
    assert_no_finding_for_file "stale still accepted after dates changed" "$out" stale "concepts/gadget.md" || ok=false
    $ok
}

# L75: the hub entry-anchor recipe (`grep -n '^## \[' … | tail -30`, then a
# bounded Read from the earliest offset) returns a 20-to-30 entry slice even
# when the log is far past the fixed `tail -n 350` size it replaces. The bound
# is stated in entries, not lines, so a fixed line count is what must fail.
l75_entry_aware_log_read_bounds_slice() {
    local wiki; wiki=$(stage_fresh_wiki l75)
    customize_taxonomy "$wiki"
    append_log_entries "$wiki" 520
    local total; total=$(grep -c '^## \[' "$wiki/log.md")
    local ok=true
    if [[ $total -le 350 ]]; then
        log "    [fixture too small: $total entries, expected well over 350]"
        ok=false
    fi

    # The recipe: entry anchors for the last 30 entries, then a bounded read
    # from the earliest needed anchor, stopping at the entry count the bound
    # targets rather than running to EOF. The fixture writes 4 lines per entry,
    # so 30 entries is 120 lines; the bound is entry-based, not line-based.
    local anchors; anchors=$(grep -n '^## \[' "$wiki/log.md" | tail -30)
    local anchor_count; anchor_count=$(printf '%s\n' "$anchors" | grep -c '^[0-9]*:')
    assert_eq "anchor count" "$anchor_count" "30" || ok=false

    local offset; offset=$(printf '%s\n' "$anchors" | head -1 | cut -d: -f1)
    local slice; slice=$(sed -n "${offset},$((offset + 119))p" "$wiki/log.md")
    local slice_headings; slice_headings=$(printf '%s\n' "$slice" | grep -c '^## \[')

    if [[ $slice_headings -lt 20 || $slice_headings -gt 30 ]]; then
        log "    [slice out of bounds: $slice_headings entries, expected 20-30]"
        ok=false
    fi
    # The slice is genuinely bounded: it is a strict subset of the log.
    if [[ $slice_headings -ge $total ]]; then
        log "    [slice not bounded: $slice_headings of $total entries]"
        ok=false
    fi

    # The discriminating check: the retired fixed line count (`tail -n 350`)
    # must land outside the 20-to-30 entry window on this fixture. Without this
    # the scenario cannot tell an entry-aware read from a line-count read.
    local fixed; fixed=$(tail -n 350 "$wiki/log.md")
    local fixed_headings; fixed_headings=$(printf '%s\n' "$fixed" | grep -c '^## \[')
    if [[ $fixed_headings -ge 20 && $fixed_headings -le 30 ]]; then
        log "    [fixture does not discriminate: tail -n 350 yields $fixed_headings entries, inside 20-30]"
        ok=false
    fi
    $ok
}

# L76: a log past 500 entries reports a warn rotation finding, and the
# two-field acceptance path cannot suppress it — rotation is the only repair.
l76_lint_log_rotation_warn_past_500() {
    local wiki; wiki=$(stage_fresh_wiki l76)
    customize_taxonomy "$wiki"
    append_log_entries "$wiki" 520
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit stays 0 on a warn" "$rc" "0" || ok=false
    assert_lint_finding "rotation warn past 500" "$out" warn "log" || ok=false

    # `log` must stay out of the two-field whitelist. This is asserted on the
    # constant directly: `Acceptance.matches` returns early on severity, so a
    # re-added `log` would not surface through any acceptance-path assertion
    # below — those prove the severity tier, not the whitelist membership.
    local whitelisted
    whitelisted=$(python3 - "$LINT" <<'PY'
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).parent))
import lint
print("yes" if "log" in lint.TWO_FIELD_CATEGORIES else "no")
PY
)
    assert_eq "log is not a two-field category" "$whitelisted" "no" || ok=false

    set_accept_bullets "$wiki" "log — log.md"
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_lint_finding "warn survives acceptance" "$out" warn "log" || ok=false
    assert_no_acknowledged_section "rotation warn is not acknowledged" "$out" || ok=false
    $ok
}

# L77: a log past 1000 entries escalates the rotation finding to blocking, which
# exits 1, and acceptance cannot suppress it either.
l77_lint_log_rotation_blocking_past_1000() {
    local wiki; wiki=$(stage_fresh_wiki l77)
    customize_taxonomy "$wiki"
    append_log_entries "$wiki" 1010
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 on blocking" "$rc" "1" || ok=false
    assert_lint_finding "rotation blocking past 1000" "$out" blocking "log" || ok=false

    # The same direct constant pin as l76: the blocking tier cannot surface a
    # re-added `log` through the acceptance path either.
    local whitelisted
    whitelisted=$(python3 - "$LINT" <<'PY'
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).parent))
import lint
print("yes" if "log" in lint.TWO_FIELD_CATEGORIES else "no")
PY
)
    assert_eq "log is not a two-field category" "$whitelisted" "no" || ok=false

    set_accept_bullets "$wiki" "log — log.md"
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_lint_finding "blocking survives acceptance" "$out" blocking "log" || ok=false
    $ok
}

# L46: a single-emit line-less finding outside the two-field whitelist needs the
# three-field form. The two-field bullet matches nothing, an exact discriminator
# accepts the finding, and a differing discriminator leaves it live.
l46_lint_non_whitelisted_needs_three_field() {
    local wiki; wiki=$(stage_fresh_wiki l46)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    # Strip the trailing newline: the page's only md-style finding, line-less.
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().rstrip("\n"))
PY
    local msg="file does not end with a newline"
    local ok=true

    set_accept_bullets "$wiki" "md-style — concepts/widget.md"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    assert_live_message "two-field outside the whitelist matches nothing" "$out" "concepts/widget.md" "$msg" || ok=false
    assert_no_acknowledged_section "no acknowledgement from a too-coarse bullet" "$out" || ok=false

    set_accept_bullets "$wiki" "md-style — concepts/widget.md — $msg"
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_live_message "exact three-field discriminator accepts" "$out" "concepts/widget.md" "$msg" || ok=false
    assert_acknowledged "accepted md-style listed as context" "$out" md-style "concepts/widget.md" || ok=false

    set_accept_bullets "$wiki" "md-style — concepts/widget.md — file ends with multiple blank lines"
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_live_message "differing discriminator leaves the finding live" "$out" "concepts/widget.md" "$msg" || ok=false
    $ok
}

# L47: the discriminator is the whole remainder after the path, so a message
# carrying its own em dash matches when quoted in full and not when truncated at
# that em dash — which is what the left-anchored parse buys.
l47_lint_em_dash_discriminator_matches_whole_message() {
    local wiki; wiki=$(stage_fresh_wiki l47)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("confidence: medium", "confidence: low"))
PY
    local msg="confidence: low — corroborate or note why"
    local ok=true

    set_accept_bullets "$wiki" "quality — concepts/widget.md — confidence: low"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    assert_live_message "truncated discriminator leaves the finding live" "$out" "concepts/widget.md" "$msg" || ok=false

    set_accept_bullets "$wiki" "quality — concepts/widget.md — $msg"
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_live_message "em-dash-bearing message accepted in full" "$out" "concepts/widget.md" "$msg" || ok=false
    assert_acknowledged "accepted quality listed as context" "$out" quality "concepts/widget.md" || ok=false
    $ok
}

# L48: two line-bearing findings share a path and a message, so only the
# four-field form can pin one. The three-field bullet leaves both live; the
# four-field bullet accepts its own line and leaves the sibling live.
l48_lint_four_field_pins_one_line() {
    local wiki; wiki=$(stage_fresh_wiki l48)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    printf '\n* first\n* second\n' >> "$wiki/concepts/widget.md"
    local msg="use '-' for unordered list bullets (not * or +)"
    local ok=true

    set_accept_bullets "$wiki" "md-style — concepts/widget.md — $msg"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local nums; nums=$(printf '%s\n' "$out" | grep -F "$msg" | grep -F "concepts/widget.md" \
        | sed -E 's/.*widget\.md:([0-9]+).*/\1/' | sort -n)
    assert_eq "three-field leaves both line-bearing findings live" \
        "$(printf '%s\n' "$nums" | grep -c .)" "2" || ok=false
    local first; first=$(printf '%s\n' "$nums" | head -1)
    local last;  last=$(printf '%s\n' "$nums" | tail -1)

    set_accept_bullets "$wiki" "md-style — concepts/widget.md — $first — $msg"
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_live_message "four-field accepts its own line" "$out" "concepts/widget.md:$first" "$msg" || ok=false
    assert_live_message "sibling line stays live" "$out" "concepts/widget.md:$last" "$msg" || ok=false
    $ok
}

# L49: `sources:` is optional. A page citing no captured raw source carries no
# `sources:` key at all and draws no frontmatter or custom-field finding. A
# present-but-non-resolving entry still blocks — L16 covers that side.
l49_lint_sources_key_optional() {
    local wiki; wiki=$(stage_fresh_wiki l49)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
assert "sources: []\n" in text, "fixture page has no sources key to drop"
p.write_text(text.replace("sources: []\n", "", 1))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "no frontmatter finding without sources" "$out" "frontmatter" || ok=false
    assert_no_lint_category "no custom-field finding without sources" "$out" "custom-field" || ok=false
    $ok
}

# L50: optional `checked:`. A page carrying a well-formed value and a page
# omitting the field both lint clean; a malformed value draws the date-format
# warn on that page alone.
l50_lint_checked_field_optional_and_validated() {
    local wiki; wiki=$(stage_fresh_wiki l50)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    write_valid_concept_page "$wiki" gadget
    add_index_entry_concept "$wiki" gadget
    # widget carries `checked`; gadget carries none.
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
assert "confidence: medium\n" in text
p.write_text(text.replace("confidence: medium\n", "confidence: medium\nchecked: 2026-05-02\n", 1))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "no frontmatter finding for checked/no-checked pair" "$out" "frontmatter" || ok=false
    assert_no_lint_category "checked is canonical, not a custom field" "$out" "custom-field" || ok=false
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("checked: 2026-05-02", "checked: 05/02/2026", 1))
PY
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_finding_for_file "malformed checked warn" "$out" warn "frontmatter" "concepts/widget.md" || ok=false
    $ok
}

# L51: a wiki scaffolded from the shipped template, with only the domain and the
# tag taxonomy filled in, keeps the attribution paragraph and lints with zero
# blocking and zero warn findings.
l51_lint_customized_fresh_wiki_clean() {
    local wiki; wiki=$(stage_fresh_wiki l51)
    customize_taxonomy "$wiki"
    python3 - "$wiki/SCHEMA.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
old = '[What this wiki covers \u2014 e.g., "AI/ML research", "personal health", "startup intelligence"]'
assert old in text, "domain placeholder not found"
p.write_text(text.replace(old, "Widget engineering practice.", 1))
PY
    local ok=true
    grep -qF 'managed by the `wiki` skill' "$wiki/SCHEMA.md" \
        || { log "    attribution paragraph missing from the scaffolded SCHEMA.md"; ok=false; }
    local ret; ret=$(run_lint "$wiki" --quiet)
    local rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit" "$rc" "0" || ok=false
    if ! grep -q "^clean " <<<"$out"; then
        log "    expected zero blocking and zero warn findings"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    $ok
}

# L52: the SCHEMA.md attribution paragraph ships with every scaffolded wiki but
# is no longer a defended slot, so an owner who deletes it draws no
# `boilerplate` finding. The log.md preamble slot still fires — see L10.
l52_lint_schema_attribution_deletable() {
    local wiki; wiki=$(stage_fresh_wiki l52)
    python3 - "$wiki/SCHEMA.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
lines = p.read_text().splitlines(keepends=True)
hits = [n for n, ln in enumerate(lines) if "managed by the `wiki` skill" in ln]
assert len(hits) == 1, f"expected one attribution line, found {len(hits)}"
n = hits[0]
# Drop the paragraph and the blank line that followed it, so the deletion
# leaves no double-blank md-style nit behind.
end = n + 2 if n + 1 < len(lines) and lines[n + 1].strip() == "" else n + 1
p.write_text("".join(lines[:n] + lines[end:]))
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "no boilerplate finding for a deleted attribution" "$out" "boilerplate" || ok=false
    $ok
}

# L53: a wiki still carrying the pre-rework SCHEMA.md, with a page written under
# the pre-rework contract (`sources: []`, no `checked`), draws no blocking
# finding — an existing wiki converges through audit and repair rather than
# through a migration sweep.
l53_lint_pre_rework_schema_no_blocking() {
    local wiki; wiki=$(stage_fresh_wiki l53)
    cp "$FIXTURES/schema_pre_rework.md" "$wiki/SCHEMA.md"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "no frontmatter finding on a pre-rework page" "$out" "frontmatter" || ok=false
    assert_no_lint_category "no boilerplate finding on a pre-rework SCHEMA" "$out" "boilerplate" || ok=false
    $ok
}

# Count the live finding lines the report emits for <category>, at any severity.
# `log-heading` emits one finding per duplicate group rather than one per path,
# so its scenarios assert an exact count instead of mere presence.
lint_category_count() {
    printf '%s\n' "$1" | grep -Ec "^[[:space:]]*\[[a-z]+[[:space:]]*\][[:space:]]+$2\b" || true
}

# Rewrite log.md's entry headings, keeping the canonical preamble byte-intact so
# the boilerplate warn stays out of the way. Args: <wiki> <heading-line>...
set_log_entries() {
    local wiki=$1; shift
    python3 - "$wiki/log.md" "$@" <<'SETLOG'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
i = text.find("\n## ")
preamble = (text[:i] if i != -1 else text).rstrip("\n") + "\n"
entries = "".join(
    f"\n{heading}\n\n- concepts/page-{n}.md: recorded\n"
    for n, heading in enumerate(sys.argv[2:])
)
p.write_text(preamble + entries)
SETLOG
}

# Rewrite log.md's entries from `heading|||bullet|||bullet…` specs, keeping the
# canonical preamble byte-intact so the boilerplate warn stays out of the way.
# The first field of each spec is the entry heading and every later field is one
# body bullet, written verbatim after a `- ` marker, so a scenario controls the
# exact bullet subject the log-scope check reads. Args: <wiki> <spec>...
set_log_entries_with_bullets() {
    local wiki=$1; shift
    python3 - "$wiki/log.md" "$@" <<'SETLOGB'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
i = text.find("\n## ")
preamble = (text[:i] if i != -1 else text).rstrip("\n") + "\n"
out = []
for spec in sys.argv[2:]:
    heading, *bullets = spec.split("|||")
    body = "\n".join(f"- {b}" for b in bullets)
    out.append(f"\n{heading}\n\n{body}\n")
p.write_text(preamble + "".join(out))
SETLOGB
}

# L54: two byte-identical `## [` headings in log.md -> exactly one info
#      `log-heading` finding. Lint only surfaces the collision: the exit code is
#      unchanged and the fixture bytes are untouched, because repairing an entry
#      already written is an operator-requested move, never a lint side effect.
l54_lint_duplicate_log_heading() {
    local wiki; wiki=$(stage_fresh_wiki l54)
    set_log_entries "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized" \
        "## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested" \
        "## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested"
    local before; before=$(shasum -a 256 "$wiki/log.md" | awk '{print $1}')
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local after; after=$(shasum -a 256 "$wiki/log.md" | awk '{print $1}')
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "log-heading info" "$out" info "log-heading" || ok=false
    assert_eq "one finding per duplicate group" "$(lint_category_count "$out" log-heading)" "1" || ok=false
    assert_eq "log.md bytes unchanged by lint" "$after" "$before" || ok=false
    $ok
}

# L55: unique legacy date-only headings -> no `log-heading` finding at all. The
#      check fires on an actual duplicate, never on the absence of `HH:MM`, so a
#      date-only entry that predates the timestamped format stays clean and is
#      never flagged for its format.
l55_lint_unique_date_only_log_headings() {
    local wiki; wiki=$(stage_fresh_wiki l55)
    set_log_entries "$wiki" \
        "## [2026-06-18] create | Wiki initialized" \
        "## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested" \
        "## [2026-06-18] session-wrapup | 1 new, 0 extended, 0 contested" \
        "## [2026-06-19] lint | 0 blocking, 0 warn, 0 info"
    local before; before=$(shasum -a 256 "$wiki/log.md" | awk '{print $1}')
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local after; after=$(shasum -a 256 "$wiki/log.md" | awk '{print $1}')
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "no log-heading finding on unique headings" "$out" "log-heading" || ok=false
    assert_eq "zero log-heading findings" "$(lint_category_count "$out" log-heading)" "0" || ok=false
    # No sibling check grew into heading-format conformance either: nothing in
    # the report asks a date-only entry for a timestamp.
    if printf '%s' "$out" | grep -Eq "^[[:space:]]*\[[a-z]+[[:space:]]*\].*log\.md.*(HH:MM|timestamp)"; then
        log "    [unexpected finding: a date-only heading was flagged for its format]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    assert_eq "log.md bytes unchanged by lint" "$after" "$before" || ok=false
    $ok
}

# L56: every separator and every outside-the-wiki resolution class in one
#      fixture. Four bullets, one per separator (`:`, ` — `, ` – `, ` | `), whose
#      subjects are respectively an absolute path, a `~`-expanded path, an
#      existing repo file outside the wiki (the repo-root join branch), and a
#      `..` escape from the wiki root. All four must land in the single
#      aggregated info `log-scope` finding, and lint must leave the log's bytes
#      alone — repairing a written entry is the owner's editorial call.
l56_lint_log_scope_outside_wiki_subjects() {
    local wiki; wiki=$(stage_fresh_wiki_in_repo l56)
    local repo; repo=$(dirname "$wiki")
    mkdir -p "$repo/tooling" "$repo/../outside"
    printf 'build\n' > "$repo/tooling/build.sh"
    set_log_entries_with_bullets "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized|||concepts/alpha.md: recorded" \
        "## [2026-06-19 10:00] update | outside subjects|||/etc/hosts: edited by hand|||~/scratch/notes.md — jotted down|||tooling/build.sh – bumped the flags|||../outside/thing.md | rewrote the wrapper"
    local before; before=$(shasum -a 256 "$wiki/log.md" | awk '{print $1}')
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local after; after=$(shasum -a 256 "$wiki/log.md" | awk '{print $1}')
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "log-scope info" "$out" info "log-scope" || ok=false
    assert_eq "one aggregated finding" "$(lint_category_count "$out" log-scope)" "1" || ok=false
    assert_live_message "all four bullets counted" "$out" "log.md" "4 entry bullets" || ok=false
    assert_live_message "absolute subject named" "$out" "log.md" "/etc/hosts" || ok=false
    # shellcheck disable=SC2088  # literal expected output, not a path to expand
    assert_live_message "tilde subject named" "$out" "log.md" "~/scratch/notes.md" || ok=false
    assert_live_message "repo-root subject named" "$out" "log.md" "tooling/build.sh" || ok=false
    assert_eq "log.md bytes unchanged by lint" "$after" "$before" || ok=false
    $ok
}

# L57: the aggregated `log-scope` finding is accepted through the two-field
#      (path-only) form, then a further violation changes the volatile count in
#      `Issue.message`. The acceptance keys on the path alone, so it keeps
#      matching across that churn — which is what `log-scope` membership in
#      TWO_FIELD_CATEGORIES buys.
l57_lint_log_scope_two_field_survives_volatile_count() {
    local wiki; wiki=$(stage_fresh_wiki l57)
    set_log_entries_with_bullets "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized|||concepts/alpha.md: recorded" \
        "## [2026-06-19 10:00] update | outside subjects|||/etc/hosts: edited|||/etc/services: edited"
    # Baseline: the finding is live and its message carries the count of 2.
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_lint_finding "live before acceptance" "$out" info "log-scope" || ok=false
    assert_live_message "count before acceptance" "$out" "log.md" "2 entry bullets" || ok=false
    set_accept_bullets "$wiki" "log-scope — log.md"
    ret=$(run_lint "$wiki")
    out=${ret#*|}
    assert_no_lint_category "accepted before the count moved" "$out" "log-scope" || ok=false
    assert_acknowledged "two-field acceptance matched" "$out" "log-scope" "log.md" || ok=false
    # A third outside subject moves the count substring the message embeds.
    printf '\n## [2026-06-20 11:00] update | one more\n\n- /etc/passwd: edited\n' >> "$wiki/log.md"
    ret=$(run_lint "$wiki")
    out=${ret#*|}
    assert_no_lint_category "still accepted after the count moved" "$out" "log-scope" || ok=false
    assert_acknowledged "acceptance survives the volatile count" "$out" "log-scope" "log.md" || ok=false
    if ! printf '%s' "$out" | grep -F "(accepted)" | grep -qF "3 entry bullets"; then
        log "    [count substring did not move: expected an accepted line naming 3 entry bullets]"
        printf '%s\n' "$out" | indent
        ok=false
    fi
    $ok
}

# L58: the subject position is the whole discriminator. A bullet about a wiki
#      page that cites an outside path mid-bullet as the source of its claim is
#      legitimate provenance and must stay clean, even though the same path
#      standing as the subject would fire.
l58_lint_log_scope_mid_bullet_citation_is_provenance() {
    local wiki; wiki=$(stage_fresh_wiki_in_repo l58)
    local repo; repo=$(dirname "$wiki")
    mkdir -p "$repo/tooling"
    printf 'build\n' > "$repo/tooling/build.sh"
    set_log_entries_with_bullets "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized|||concepts/alpha.md: recorded" \
        "## [2026-06-19 10:00] update | provenance cited mid-bullet|||concepts/beta.md: recorded the flag defaults, drawn from tooling/build.sh|||concepts/gamma.md — claim traced to /etc/hosts and ~/scratch/notes.md"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "mid-bullet citation is not a subject" "$out" "log-scope" || ok=false
    assert_eq "zero log-scope findings" "$(lint_category_count "$out" log-scope)" "0" || ok=false
    $ok
}

# L59: violations spread across several entries aggregate into ONE finding that
#      names the count, rather than one finding per bullet, so a wiki carrying
#      historical violations gets a signal instead of a swamped report.
l59_lint_log_scope_aggregates_across_entries() {
    local wiki; wiki=$(stage_fresh_wiki l59)
    set_log_entries_with_bullets "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized|||concepts/alpha.md: recorded" \
        "## [2026-06-19 10:00] update | first|||/etc/hosts: edited|||concepts/beta.md: recorded" \
        "## [2026-06-20 10:00] update | second|||/etc/services: edited" \
        "## [2026-06-21 10:00] update | third|||/etc/passwd: edited|||/etc/group: edited"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "one finding, not one per bullet" "$(lint_category_count "$out" log-scope)" "1" || ok=false
    assert_live_message "count names every violating bullet" "$out" "log.md" "4 entry bullets" || ok=false
    $ok
}

# L60: fence-safe. The only outside-the-wiki subject sits inside a fenced block,
#      where it is documentation rather than a live entry bullet, so nothing
#      fires — matching the fence handling in every other section reader.
l60_lint_log_scope_fenced_block_is_documentation() {
    local wiki; wiki=$(stage_fresh_wiki l60)
    set_log_entries_with_bullets "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized|||concepts/alpha.md: recorded" \
        "## [2026-06-19 10:00] update | documented shape|||concepts/beta.md: recorded"
    cat >> "$wiki/log.md" <<'FENCED'

```text
- /etc/hosts: edited by hand
- ../outside/thing.md | rewrote
```
FENCED
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "fenced bullets are documentation" "$out" "log-scope" || ok=false
    assert_eq "zero log-scope findings" "$(lint_category_count "$out" log-scope)" "0" || ok=false
    $ok
}

# L61: a non-path subject — the lint outcome line every audit writes — stays
#      clean. `Outcome` carries no `/` and no dotted extension, so it is not a
#      path token and the check never reaches resolution.
l61_lint_log_scope_non_path_subject() {
    local wiki; wiki=$(stage_fresh_wiki l61)
    set_log_entries_with_bullets "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized|||concepts/alpha.md: recorded" \
        "## [2026-06-19 10:00] lint | 0 blocking, 0 warn, 0 info|||Outcome: lint passed with 0 errors|||Lint clean across the vault"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "non-path subject stays clean" "$out" "log-scope" || ok=false
    assert_eq "zero log-scope findings" "$(lint_category_count "$out" log-scope)" "0" || ok=false
    $ok
}

# L62: the whole-subject path-token rule. The scaffold's own seed bullet is
#      prose that embeds a pile of path substrings (`SCHEMA.md`, `index.md`,
#      `raw/`, the type directories) inside one remainder with no separator, so
#      the subject is the full prose line and is not a path token.
l62_lint_log_scope_scaffold_seed_prose_subject() {
    local wiki; wiki=$(stage_fresh_wiki l62)
    set_log_entries_with_bullets "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized|||Domain: widget delivery|||Structure created with SCHEMA.md, index.md, log.md, raw/, entities/, concepts/, comparisons/, queries/, summaries/, procedures/"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "prose embedding paths is not a path token" "$out" "log-scope" || ok=false
    assert_eq "zero log-scope findings" "$(lint_category_count "$out" log-scope)" "0" || ok=false
    $ok
}

# L63: the check draws a path boundary, not a missing-file one. A path-shaped
#      subject that joins under the wiki root stays clean even when no such file
#      exists on disk, so an entry naming a page later archived or renamed is
#      never re-flagged. Existence discriminates the repo-root branch alone.
l63_lint_log_scope_absent_wiki_file_is_clean() {
    local wiki; wiki=$(stage_fresh_wiki_in_repo l63)
    set_log_entries_with_bullets "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized|||concepts/alpha.md: recorded" \
        "## [2026-06-19 10:00] archive | retired a page|||concepts/never-existed.md: archived|||summaries/gone.md — removed"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "absent wiki file is not outside the wiki" "$out" "log-scope" || ok=false
    assert_eq "zero log-scope findings" "$(lint_category_count "$out" log-scope)" "0" || ok=false
    $ok
}

# L64: markdown decoration around a whole subject is decoration, not part of the
#      path. A backticked and a bold-wrapped outside-the-wiki subject both fire,
#      because a log bullet commonly writes its path decorated — while a real
#      filename that merely opens with one of those characters keeps its name.
#      The `_config.yml` subject is the discriminating half: `config.yml` exists
#      at the repo root and `_config.yml` does not, so stripping that leading
#      underscore would turn a clean wiki-relative subject into a third finding.
l64_lint_log_scope_decorated_path_subject() {
    local wiki; wiki=$(stage_fresh_wiki_in_repo l64)
    local repo; repo=$(dirname "$wiki")
    mkdir -p "$repo/tooling"
    printf 'build\n' > "$repo/tooling/build.sh"
    printf 'x\n' > "$repo/config.yml"
    set_log_entries_with_bullets "$wiki" \
        "## [2026-06-18 09:14] create | Wiki initialized|||concepts/alpha.md: recorded" \
        "## [2026-06-19 10:00] update | decorated subjects|||\`/etc/hosts\`: edited by hand|||**tooling/build.sh**: bumped the flags|||_config.yml: a wiki file whose name opens with an underscore"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "log-scope info" "$out" info "log-scope" || ok=false
    assert_eq "one aggregated finding" "$(lint_category_count "$out" log-scope)" "1" || ok=false
    assert_live_message "both decorated subjects counted" "$out" "log.md" "2 entry bullets" || ok=false
    assert_live_message "backticks stripped" "$out" "log.md" "/etc/hosts" || ok=false
    assert_live_message "bold markers stripped" "$out" "log.md" "tooling/build.sh" || ok=false
    assert_no_live_message "leading underscore kept, so the subject stays wiki-relative" \
        "$out" "log.md" "_config.yml" || ok=false
    $ok
}

###############################################################################
# Locked-slot classify / declare scenarios (sanctioned template deviations)
###############################################################################

# Exact VerbatimSlot.label for the production log.md preamble slot.
LOG_SLOT_LABEL='log.md preamble (H1 plus blockquote above first `##`)'

# Insert an owner line into the log.md preamble (before the first `##` heading)
# so the region is insert-only relative to the canonical template.
# Args: <wiki> <line text without trailing newline>
add_log_preamble_owner_line() {
    local wiki=$1 line=$2
    python3 - "$wiki/log.md" "$line" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
line = sys.argv[2]
text = p.read_text()
out = []
inserted = False
for ln in text.splitlines(keepends=True):
    if not inserted and ln.startswith("## "):
        out.append(line + "\n")
        inserted = True
    out.append(ln)
p.write_text("".join(out))
PY
}

# Rewrite the log.md preamble to a delete/replace divergence (canonical lines gone).
# Args: <wiki>
rewrite_log_preamble_divergence() {
    local wiki=$1
    python3 - "$wiki/log.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
i = text.find("\n## ")
rest = text[i:] if i != -1 else ""
p.write_text("# Custom Log Title\n\n> House conventions instead.\n" + rest)
PY
}

# Replace live `- Declared boilerplate:` bullets. Pass no payload to clear.
# Args: <wiki> [payload without the label prefix]...
set_declare_bullets() {
    local wiki=$1
    shift
    python3 - "$wiki/SCHEMA.md" "$@" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
kept = [ln for ln in p.read_text().splitlines() if not ln.startswith("- Declared boilerplate:")]
while kept and kept[-1] == "":
    kept.pop()
if sys.argv[2:]:
    kept.append("")
    kept.extend(f"- Declared boilerplate: {payload}" for payload in sys.argv[2:])
p.write_text("\n".join(kept) + "\n")
PY
}

# Append a Declared boilerplate bullet inside a fence (documentation only).
add_fenced_declare_bullet() {
    local wiki=$1 payload=$2
    printf '\n```text\n- Declared boilerplate: %s\n```\n' "$payload" >> "$wiki/SCHEMA.md"
}

# Assert ACKNOWLEDGED lists a marker for category/file.
# Args: <label> <output> <marker> <category> <file>
assert_acknowledged_marker() {
    local label=$1 out=$2 marker=$3 cat=$4 file=$5
    local ok=true
    printf '%s' "$out" | grep -Eq "^ACKNOWLEDGED \([0-9]+\)" || ok=false
    printf '%s' "$out" | grep -F "accepted findings, locked-slot extensions, declared boilerplate" >/dev/null || ok=false
    printf '%s' "$out" | grep -E "^[[:space:]]*\(${marker}\)[[:space:]]+${cat}[[:space:]]" \
        | grep -qF "$file" || ok=false
    if $ok; then
        return 0
    fi
    log "    [missing acknowledgement: $label — expected ($marker) $cat for $file under ACKNOWLEDGED]"
    printf '%s\n' "$out" | indent
    return 1
}

# Assert live totals carry zero findings of the named severity label in the summary.
# Args: <label> <output> <severity word e.g. warn>
assert_live_severity_count() {
    local label=$1 out=$2 sev=$3 expected=$4
    local actual
    actual=$(printf '%s\n' "$out" | sed -n "s/^total: .*(\(.*\))/\1/p" | head -1 \
        | grep -oE "[0-9]+ ${sev}" | awk '{print $1}')
    actual=${actual:-0}
    assert_eq "$label" "$actual" "$expected"
}

# L65: insert-only locked-slot addition is an acknowledged extension, not a restore warn.
l65_lint_insert_only_extension_acknowledged() {
    local wiki; wiki=$(stage_fresh_wiki l65)
    customize_taxonomy "$wiki"
    add_log_preamble_owner_line "$wiki" \
        "> Local: this vault names the tenant alongside every rollout entry."
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "no live boilerplate warn" "$out" "boilerplate" || ok=false
    assert_acknowledged_marker "extension listed" "$out" extension boilerplate "log.md" || ok=false
    assert_live_severity_count "zero live warn from boilerplate" "$out" warn "0" || ok=false
    printf '%s' "$out" | grep -q "restore the region verbatim" && {
        log "    [unexpected restore instruction on insert-only extension]"
        ok=false
    }
    $ok
}

# L66: Accepted-finding suppressions still use the (accepted) marker.
l66_lint_accepted_marker_parameterized() {
    local wiki; wiki=$(stage_fresh_wiki l66)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    grow_page_past_soft_cap "$wiki/concepts/widget.md"
    set_accept_bullets "$wiki" "size — concepts/widget.md"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_acknowledged_marker "accepted marker" "$out" accepted size "concepts/widget.md" || ok=false
    printf '%s' "$out" | grep -E '\(extension\)|\(declared\)' | grep -q size && {
        log "    [size acceptance used wrong marker]"
        ok=false
    }
    $ok
}

# L67: delete/replace of canonical locked-slot text still warns with both remedies.
l67_lint_delete_replace_still_warns() {
    local wiki; wiki=$(stage_fresh_wiki l67)
    customize_taxonomy "$wiki"
    rewrite_log_preamble_divergence "$wiki"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "boilerplate warn" "$out" warn "boilerplate" || ok=false
    printf '%s' "$out" | grep -q "restore the region verbatim" || ok=false
    printf '%s' "$out" | grep -q "update the template if the change is intentional" || ok=false
    $ok
}

# L68: matching Declared boilerplate honour — no live warn, (declared) on ACKNOWLEDGED.
l68_lint_declared_boilerplate_honoured() {
    local wiki; wiki=$(stage_fresh_wiki l68)
    customize_taxonomy "$wiki"
    rewrite_log_preamble_divergence "$wiki"
    set_declare_bullets "$wiki" \
        "${LOG_SLOT_LABEL} — local house conventions for this vault"
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "declared suppresses live warn" "$out" "boilerplate" || ok=false
    assert_acknowledged_marker "declared listed" "$out" declared boilerplate "log.md" || ok=false
    printf '%s' "$out" | grep -q "local house conventions for this vault" || ok=false
    printf '%s' "$out" | grep -q "restore the region verbatim" && ok=false
    assert_live_severity_count "zero live warn" "$out" warn "0" || ok=false
    $ok
}

# L69: same delete/replace without declaration still warns with both remedies.
l69_lint_undeclared_delete_replace_warns() {
    local wiki; wiki=$(stage_fresh_wiki l69)
    customize_taxonomy "$wiki"
    rewrite_log_preamble_divergence "$wiki"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_lint_finding "boilerplate warn" "$out" warn "boilerplate" || ok=false
    printf '%s' "$out" | grep -q "restore the region verbatim" || ok=false
    printf '%s' "$out" | grep -q "update the template if the change is intentional" || ok=false
    $ok
}

# L70: fenced Declared boilerplate is documentation — warn still fires.
l70_lint_fenced_declare_is_documentation() {
    local wiki; wiki=$(stage_fresh_wiki l70)
    customize_taxonomy "$wiki"
    rewrite_log_preamble_divergence "$wiki"
    add_fenced_declare_bullet "$wiki" \
        "${LOG_SLOT_LABEL} — local house conventions for this vault"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_lint_finding "fenced declaration suppresses nothing" "$out" warn "boilerplate" || ok=false
    printf '%s' "$out" | grep -qE '\(declared\)' && {
        log "    [unexpected declared acknowledgement from fenced bullet]"
        ok=false
    }
    $ok
}

# L71: unmatched Declared boilerplate label → live info on SCHEMA.md, not ACKNOWLEDGED.
l71_lint_unmatched_declare_is_live_info() {
    local wiki; wiki=$(stage_fresh_wiki l71)
    customize_taxonomy "$wiki"
    rewrite_log_preamble_divergence "$wiki"
    set_declare_bullets "$wiki" \
        "nonexistent slot label — should not suppress"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_lint_finding "undeclared divergence still warns" "$out" warn "boilerplate" || ok=false
    assert_finding_for_file "unmatched label info" "$out" info boilerplate "SCHEMA.md" || ok=false
    printf '%s' "$out" | grep -q "nonexistent slot label" || ok=false
    printf '%s' "$out" | grep -E '\(declared\)' | grep -q "SCHEMA.md" && {
        log "    [unmatched declare wrongly acknowledged]"
        ok=false
    }
    $ok
}

# L72: per-slot isolation with a temporary second VerbatimSlot (torn down after).
l72_lint_declared_per_slot_isolation() {
    local wiki; wiki=$(stage_fresh_wiki l72)
    customize_taxonomy "$wiki"
    rewrite_log_preamble_divergence "$wiki"
    # Drift SCHEMA.md prelude so a temporary second slot would warn when undeclared.
    python3 - "$wiki/SCHEMA.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
i = text.find("\n## ")
rest = text[i:] if i != -1 else ""
p.write_text("# Custom Schema Title\n\nCustom attribution.\n" + rest)
PY
    set_declare_bullets "$wiki" \
        "SCHEMA.md test-only prelude — intentional schema prelude rewrite"
    local out
    out=$(python3 - "$LINT" "$wiki" <<'PY'
import importlib.util, sys
from pathlib import Path

lint_path = Path(sys.argv[1])
wiki = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("lint", lint_path)
lint = importlib.util.module_from_spec(spec)
sys.modules["lint"] = lint
spec.loader.exec_module(lint)

test_slot = lint.VerbatimSlot(
    wiki_file="SCHEMA.md",
    template_file="template_schema.md",
    label="SCHEMA.md test-only prelude",
)
old = lint.VERBATIM_SLOTS
lint.VERBATIM_SLOTS = old + (test_slot,)
try:
    live, ack = lint.check_verbatim_boilerplate(wiki)
finally:
    lint.VERBATIM_SLOTS = old

print(lint.render_report(wiki, live, quiet=False, acknowledged=list(ack)))
PY
)
    local ok=true
    # Declared SCHEMA test slot → no live warn for SCHEMA.md boilerplate
    printf '%s' "$out" | grep -E '^[[:space:]]*\[warn[[:space:]]*\][[:space:]]+boilerplate[[:space:]]' \
        | grep -qF "SCHEMA.md" && {
        log "    [declared test slot still warned]"
        ok=false
    }
    # Undeclared log slot → live warn with both remedies
    printf '%s' "$out" | grep -E '^[[:space:]]*\[warn[[:space:]]*\][[:space:]]+boilerplate[[:space:]]' \
        | grep -qF "log.md" || {
        log "    [undeclared log slot missing warn]"
        ok=false
    }
    printf '%s' "$out" | grep -q "restore the region verbatim" || ok=false
    printf '%s' "$out" | grep -q "update the template if the change is intentional" || ok=false
    assert_acknowledged_marker "declared SCHEMA slot" "$out" declared boilerplate "SCHEMA.md" || ok=false
    $ok
}

# L73: body carrying a meta-prose / lint-sanction phrase -> info meta-prose.
l73_lint_meta_prose_phrase() {
    local wiki; wiki=$(stage_fresh_wiki l73)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    write_valid_concept_page "$wiki" companion
    add_index_entry_concept "$wiki" companion
    # Cross-link so neither page is an orphan; keep the meta phrase in body.
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "Placeholder for widget used by the lint regression harness.",
    "Placeholder for widget used by the lint regression harness.\n\n"
    "Page size note: this backlog is sanctioned past the 200-line lint threshold.\n\n"
    "See also [companion](companion.md).",
)
p.write_text(text)
PY
    python3 - "$wiki/concepts/companion.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "Placeholder for companion used by the lint regression harness.",
    "Placeholder for companion used by the lint regression harness.\n\n"
    "See also [widget](widget.md).",
)
p.write_text(text)
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "meta-prose info" "$out" info "meta-prose" || ok=false
    assert_finding_for_file "phrase on widget" "$out" info "meta-prose" "concepts/widget.md" || ok=false
    $ok
}

# L74: non-synthesis page whose lead paragraph exceeds two sentences -> info.
l74_lint_meta_prose_long_lead() {
    local wiki; wiki=$(stage_fresh_wiki l74)
    customize_taxonomy "$wiki"
    write_valid_concept_page "$wiki" widget
    add_index_entry_concept "$wiki" widget
    write_valid_concept_page "$wiki" companion
    add_index_entry_concept "$wiki" companion
    python3 - "$wiki/concepts/widget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
# Three-sentence lead before any H2; no banned phrase, so only the lead heuristic fires.
lead = (
    "This page covers the widget default. It also records the migration "
    "path from the legacy renderer. A third sentence keeps the lead over "
    "the two-sentence limit."
)
text = text.replace(
    "Placeholder for widget used by the lint regression harness.",
    lead + "\n\nSee also [companion](companion.md).",
)
p.write_text(text)
PY
    python3 - "$wiki/concepts/companion.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = text.replace(
    "Placeholder for companion used by the lint regression harness.",
    "Placeholder for companion used by the lint regression harness.\n\n"
    "See also [widget](widget.md).",
)
p.write_text(text)
PY
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_lint_finding "meta-prose lead info" "$out" info "meta-prose" || ok=false
    assert_finding_for_file "long lead on widget" "$out" info "meta-prose" "concepts/widget.md" || ok=false
    # Phrase heuristic must stay quiet on this fixture.
    if printf '%s' "$out" | grep -F "meta-prose phrase" >/dev/null; then
        log "    [unexpected phrase finding on lead-only fixture]"
        ok=false
    fi
    $ok
}

# L78: a summary page declares two sources but cites only one inline -> info
# `citation` naming the uncited entry, never the pinned-but-undeclared side.
l78_lint_citation_declared_never_cited() {
    local wiki; wiki=$(stage_fresh_wiki l78)
    customize_taxonomy "$wiki" model
    write_clean_raw_source "$wiki" articles alpha
    write_clean_raw_source "$wiki" articles beta
    write_typed_page "$wiki" summary citation-declared \
        "sources: [raw/articles/alpha.md, raw/articles/beta.md]"
    cat >> "$wiki/summaries/citation-declared.md" <<'EOF'

Alpha grounds this claim ([alpha](../raw/articles/alpha.md)).
EOF
    add_index_entry_for "$wiki" summaries citation-declared
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_finding_for_file "declared-not-cited info" "$out" info citation "summaries/citation-declared.md" || ok=false
    assert_live_message "declared-not-cited message" "$out" "summaries/citation-declared.md" "declared but never cited inline" || ok=false
    assert_live_message "uncited source named" "$out" "summaries/citation-declared.md" "raw/articles/beta.md" || ok=false
    assert_no_live_message "no pinned-undeclared finding" "$out" "summaries/citation-declared.md" 'cited inline but missing from `sources:`' || ok=false
    $ok
}

# L79: a query page cites a raw source inline while carrying no `sources:` key
# -> info `citation` naming the pinned-but-undeclared source, never the
# declared-but-never-cited side.
l79_lint_citation_cited_but_undeclared() {
    local wiki; wiki=$(stage_fresh_wiki l79)
    customize_taxonomy "$wiki" model
    write_clean_raw_source "$wiki" articles alpha
    write_typed_page "$wiki" query citation-pinned
    cat >> "$wiki/queries/citation-pinned.md" <<'EOF'

The answer rests on alpha ([alpha](../raw/articles/alpha.md)).
EOF
    add_index_entry_for "$wiki" queries citation-pinned
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_finding_for_file "pinned-undeclared info" "$out" info citation "queries/citation-pinned.md" || ok=false
    assert_live_message "pinned-undeclared message" "$out" "queries/citation-pinned.md" 'cited inline but missing from `sources:`' || ok=false
    assert_live_message "undeclared source named" "$out" "queries/citation-pinned.md" "raw/articles/alpha.md" || ok=false
    assert_no_live_message "no declared-not-cited finding" "$out" "queries/citation-pinned.md" "declared but never cited inline" || ok=false
    $ok
}

# L80: a comparison page carries no local `.md` inline links -> the zero-links
# info backstop. An external URL and an image do not clear it, because the
# primitive drops both.
l80_lint_citation_zero_inline_links() {
    local wiki; wiki=$(stage_fresh_wiki l80)
    customize_taxonomy "$wiki" model
    write_typed_page "$wiki" comparison citation-unlinked
    cat >> "$wiki/comparisons/citation-unlinked.md" <<'EOF'

The comparison draws on external material ([example](https://example.com/compare)).
![diagram](diagram.png)
EOF
    add_index_entry_for "$wiki" comparisons citation-unlinked
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_finding_for_file "zero-links info" "$out" info citation "comparisons/citation-unlinked.md" || ok=false
    assert_live_message "zero-links message" "$out" "comparisons/citation-unlinked.md" "no local \`.md\` inline links" || ok=false
    assert_no_live_message "no declared-not-cited finding" "$out" "comparisons/citation-unlinked.md" "declared but never cited inline" || ok=false
    assert_no_live_message "no pinned-undeclared finding" "$out" "comparisons/citation-unlinked.md" 'cited inline but missing from `sources:`' || ok=false
    $ok
}

# L81: true negative. Every `sources:` entry has a matching inline raw link and
# every inline raw link is declared -> none of the new findings.
l81_lint_citation_channels_agree() {
    local wiki; wiki=$(stage_fresh_wiki l81)
    customize_taxonomy "$wiki" model
    write_clean_raw_source "$wiki" articles alpha
    write_clean_raw_source "$wiki" articles beta
    write_typed_page "$wiki" summary citation-agree \
        "sources: [raw/articles/alpha.md, raw/articles/beta.md]"
    cat >> "$wiki/summaries/citation-agree.md" <<'EOF'

Alpha grounds the first claim ([alpha](../raw/articles/alpha.md)).
Beta grounds the second ([beta](../raw/articles/beta.md)).
EOF
    add_index_entry_for "$wiki" summaries citation-agree
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "channels agree" "$out" "citation" || ok=false
    $ok
}

# L82: the page-citing false positive guard. A query page that omits `sources:`
# and cites only another wiki page draws no citation finding, because the check
# never demands that raw links exist. A sibling carrying an empty `sources: []`
# list is the same empty inventory and stays clean too.
l82_lint_citation_page_citing_query_clean() {
    local wiki; wiki=$(stage_fresh_wiki l82)
    customize_taxonomy "$wiki" model
    write_valid_concept_page "$wiki" companion
    add_index_entry_concept "$wiki" companion
    write_typed_page "$wiki" query citation-page-citing
    cat >> "$wiki/queries/citation-page-citing.md" <<'EOF'

The answer is assembled from [companion](../concepts/companion.md).
EOF
    add_index_entry_for "$wiki" queries citation-page-citing
    write_typed_page "$wiki" query citation-empty-inventory "sources: []"
    cat >> "$wiki/queries/citation-empty-inventory.md" <<'EOF'

This answer also draws on [companion](../concepts/companion.md).
EOF
    add_index_entry_for "$wiki" queries citation-empty-inventory
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "page-citing query stays clean" "$out" "citation" || ok=false
    $ok
}

# L83: `strip_code` preprocessing. The declared raw path appears only inside a
# fenced example and inline code, so it stays absent from the inline-citation
# set: the declared-but-never-cited finding fires for it, no pinned-undeclared
# finding fires, and the live non-raw prose link keeps the zero-links backstop
# quiet.
l83_lint_citation_code_examples_not_citations() {
    local wiki; wiki=$(stage_fresh_wiki l83)
    customize_taxonomy "$wiki" model
    write_clean_raw_source "$wiki" articles example
    write_valid_concept_page "$wiki" companion
    add_index_entry_concept "$wiki" companion
    write_typed_page "$wiki" summary citation-example \
        "sources: [raw/articles/example.md]"
    cat >> "$wiki/summaries/citation-example.md" <<'EOF'

Background: [companion](../concepts/companion.md).

```markdown
Example citation: [example](../raw/articles/example.md).
```

Inline example: `[example](../raw/articles/example.md)`.
EOF
    add_index_entry_for "$wiki" summaries citation-example
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_finding_for_file "code-example declared-not-cited" "$out" info citation "summaries/citation-example.md" || ok=false
    assert_live_message "declared example source named" "$out" "summaries/citation-example.md" "declared but never cited inline" || ok=false
    assert_live_message "declared example path named" "$out" "summaries/citation-example.md" "raw/articles/example.md" || ok=false
    assert_no_live_message "code example is not a citation" "$out" "summaries/citation-example.md" 'cited inline but missing from `sources:`' || ok=false
    assert_no_live_message "live prose link clears zero-links" "$out" "summaries/citation-example.md" "no local \`.md\` inline links" || ok=false
    $ok
}

# L84: the synthesis-type gate is exactly {summary, query, comparison}. Entity,
# concept, and procedure pages with a decorative sources entry and no inline
# links draw none of the new findings, and the constant itself pins the set.
l84_lint_citation_synthesis_type_gate() {
    local wiki; wiki=$(stage_fresh_wiki l84)
    customize_taxonomy "$wiki" model
    write_clean_raw_source "$wiki" articles alpha
    local ptype slug
    for ptype in entity concept procedure; do
        slug="out-of-scope-$ptype"
        write_typed_page "$wiki" "$ptype" "$slug" "sources: [raw/articles/alpha.md]"
        case "$ptype" in
            entity) add_index_entry_for "$wiki" entities "$slug" ;;
            concept) add_index_entry_for "$wiki" concepts "$slug" ;;
            procedure) add_index_entry_for "$wiki" procedures "$slug" ;;
        esac
    done
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_no_lint_category "non-synthesis types out of scope" "$out" "citation" || ok=false
    local gate
    gate=$(python3 - "$LINT" <<'PY'
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(sys.argv[1]).parent))
import lint

print(",".join(sorted(lint.SYNTHESIS_TYPES)))
PY
)
    assert_eq "synthesis-type gate" "$gate" "comparison,query,summary" || ok=false
    $ok
}

# L85: a wiki tripping only the three new findings stays info-only and exits 0.
# The summary declares an uncited source, the query pins an undeclared one, and
# the comparison carries no local `.md` links — exactly three findings, no warn,
# no blocking.
l85_lint_citation_findings_are_info_only() {
    local wiki; wiki=$(stage_fresh_wiki l85)
    customize_taxonomy "$wiki" model
    write_clean_raw_source "$wiki" articles alpha
    write_clean_raw_source "$wiki" articles beta
    write_clean_raw_source "$wiki" articles gamma
    write_valid_concept_page "$wiki" companion
    add_index_entry_concept "$wiki" companion
    write_typed_page "$wiki" summary citation-all-summary \
        "sources: [raw/articles/alpha.md, raw/articles/beta.md]"
    cat >> "$wiki/summaries/citation-all-summary.md" <<'EOF'

Alpha grounds this claim ([alpha](../raw/articles/alpha.md)).
The overview also relies on [companion](../concepts/companion.md).
EOF
    write_typed_page "$wiki" query citation-all-query
    cat >> "$wiki/queries/citation-all-query.md" <<'EOF'

The answer rests on gamma ([gamma](../raw/articles/gamma.md)).
EOF
    write_typed_page "$wiki" comparison citation-all-comparison
    cat >> "$wiki/comparisons/citation-all-comparison.md" <<'EOF'

No local citations appear on this page.
EOF
    add_index_entry_for "$wiki" summaries citation-all-summary
    add_index_entry_for "$wiki" queries citation-all-query
    add_index_entry_for "$wiki" comparisons citation-all-comparison
    cat >> "$wiki/concepts/companion.md" <<'EOF'

See [the summary](../summaries/citation-all-summary.md),
[the query](../queries/citation-all-query.md), and
[the comparison](../comparisons/citation-all-comparison.md).
EOF
    local ret; ret=$(run_lint "$wiki")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit (info only)" "$rc" "0" || ok=false
    assert_eq "total findings" "$(lint_total "$out")" "3" || ok=false
    assert_live_severity_count "three info findings" "$out" info "3" || ok=false
    assert_live_severity_count "no warn findings" "$out" warn "0" || ok=false
    assert_live_severity_count "no blocking findings" "$out" blocking "0" || ok=false
    assert_live_message "declared-not-cited on summary" "$out" "summaries/citation-all-summary.md" "declared but never cited inline" || ok=false
    assert_live_message "pinned-undeclared on query" "$out" "queries/citation-all-query.md" 'cited inline but missing from `sources:`' || ok=false
    assert_live_message "zero-links on comparison" "$out" "comparisons/citation-all-comparison.md" "no local \`.md\` inline links" || ok=false
    $ok
}

###############################################################################
# compute_sha256.py scenarios
###############################################################################

# Stage a raw file under <wiki>/raw/notes/probe.md with the given recorded sha256
# and body content. Echoes the absolute path to the file. Caller controls drift.
stage_raw_probe() {
    local wiki=$1 recorded=$2 body=$3
    mkdir -p "$wiki/raw/notes"
    local f="$wiki/raw/notes/probe.md"
    cat > "$f" <<EOF
---
source_url: file:///tmp/probe.md
ingested: 2026-05-01
sha256: $recorded
---
$body
EOF
    printf '%s' "$f"
}

# Read the recorded sha256 line from a raw file. Echoes the hex value.
read_recorded_sha256() {
    grep -E '^sha256:' "$1" | head -1 | awk '{print $2}'
}

# Compute the body-only sha256 the way the script does — everything after
# the closing `---` line on a line of its own. Echoes the hex value.
compute_body_sha256() {
    python3 - "$1" <<'PY'
import sys, hashlib, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
i = text.find("\n---\n", 4)
body = text[i + 5:] if i != -1 else text
print(hashlib.sha256(body.encode("utf-8")).hexdigest())
PY
}

# S1: missing sha256 line -> inserted, exit 0, line present afterwards.
s1_sha256_insert_missing() {
    local wiki; wiki=$(stage_fresh_wiki s1)
    mkdir -p "$wiki/raw/notes"
    local f="$wiki/raw/notes/probe.md"
    cat > "$f" <<'EOF'
---
source_url: file:///tmp/probe.md
ingested: 2026-05-01
---
some body text
EOF
    local out rc
    out=$(python3 "$SHA256" "$f" 2>&1) && rc=0 || rc=$?
    local expected; expected=$(compute_body_sha256 "$f")
    local recorded; recorded=$(read_recorded_sha256 "$f")
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    grep -qE '^  insert\b' <<<"$out" || { log "    expected an 'insert' action in output"; ok=false; }
    assert_eq "recorded matches body sha256" "$recorded" "$expected" || ok=false
    $ok
}

# S2: recorded sha256 already correct -> unchanged, exit 0, file untouched.
s2_sha256_unchanged_when_correct() {
    local wiki; wiki=$(stage_fresh_wiki s2)
    local f; f=$(stage_raw_probe "$wiki" "placeholder" "stable body")
    # First-pass: compute correct value via the canonical script.
    python3 "$SHA256" "$f" >/dev/null 2>&1
    local before; before=$(read_recorded_sha256 "$f")
    # Second-pass: should report unchanged.
    local out rc
    out=$(python3 "$SHA256" "$f" 2>&1) && rc=0 || rc=$?
    local after; after=$(read_recorded_sha256 "$f")
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    grep -qE '^  ok\b' <<<"$out" || { log "    expected an 'ok' action in output"; ok=false; }
    assert_eq "recorded sha unchanged across runs" "$after" "$before" || ok=false
    $ok
}

# S3: recorded sha256 drifted -> updated, exit 0, file content matches body.
s3_sha256_update_on_drift() {
    local wiki; wiki=$(stage_fresh_wiki s3)
    local bogus="0000000000000000000000000000000000000000000000000000000000000000"
    local f; f=$(stage_raw_probe "$wiki" "$bogus" "drift body")
    local expected; expected=$(compute_body_sha256 "$f")
    local out rc
    out=$(python3 "$SHA256" "$f" 2>&1) && rc=0 || rc=$?
    local recorded; recorded=$(read_recorded_sha256 "$f")
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    grep -qE '^  update\b' <<<"$out" || { log "    expected an 'update' action in output"; ok=false; }
    assert_eq "recorded matches body sha256 post-update" "$recorded" "$expected" || ok=false
    [[ "$recorded" != "$bogus" ]] || { log "    bogus value survived"; ok=false; }
    $ok
}

# S4: file lacks a frontmatter block at all -> skip, exit 0, file untouched.
s4_sha256_no_frontmatter_skip() {
    local wiki; wiki=$(stage_fresh_wiki s4)
    mkdir -p "$wiki/raw/notes"
    local f="$wiki/raw/notes/plain.md"
    printf 'just a body, no frontmatter\n' > "$f"
    local before; before=$(cat "$f")
    local out rc
    out=$(python3 "$SHA256" "$f" 2>&1) && rc=0 || rc=$?
    local after; after=$(cat "$f")
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    grep -qE '^  skip\b' <<<"$out" || { log "    expected a 'skip' action in output"; ok=false; }
    assert_eq "file body untouched" "$after" "$before" || ok=false
    $ok
}

# S5: --check on a drifted file -> exit 1, no edits, "would change" reported.
s5_sha256_check_flags_drift() {
    local wiki; wiki=$(stage_fresh_wiki s5)
    local bogus="1111111111111111111111111111111111111111111111111111111111111111"
    local f; f=$(stage_raw_probe "$wiki" "$bogus" "stable body")
    local before; before=$(cat "$f")
    local out rc
    out=$(python3 "$SHA256" "$f" --check 2>&1) && rc=0 || rc=$?
    local after; after=$(cat "$f")
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    grep -qE '^check: [1-9]' <<<"$out" || { log "    expected check summary to show >=1 would change"; ok=false; }
    assert_eq "file untouched in --check" "$after" "$before" || ok=false
    $ok
}

# S6: --check on a clean file -> exit 0.
s6_sha256_check_clean() {
    local wiki; wiki=$(stage_fresh_wiki s6)
    local f; f=$(stage_raw_probe "$wiki" "placeholder" "stable body")
    python3 "$SHA256" "$f" >/dev/null 2>&1   # first pass writes the right hash
    local rc
    python3 "$SHA256" "$f" --check >/dev/null 2>&1 && rc=0 || rc=$?
    assert_eq "exit" "$rc" "0"
}

# S7: directory argument recurses into raw/ subtrees.
s7_sha256_directory_recurses() {
    local wiki; wiki=$(stage_fresh_wiki s7)
    stage_raw_probe "$wiki" "placeholder" "first body" >/dev/null
    mkdir -p "$wiki/raw/papers"
    cat > "$wiki/raw/papers/second.md" <<'EOF'
---
source_url: file:///tmp/second.md
ingested: 2026-05-01
sha256: 2222222222222222222222222222222222222222222222222222222222222222
---
second body
EOF
    local out rc
    out=$(python3 "$SHA256" "$wiki/raw" 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    grep -qE 'probe\.md'   <<<"$out" || { log "    probe.md not visited"; ok=false; }
    grep -qE 'second\.md'  <<<"$out" || { log "    second.md not visited"; ok=false; }
    $ok
}

###############################################################################
# Agent prompt contract scenarios
###############################################################################

a1_auto_shaper_fidelity_safe_token_cost_contract() {
    python3 "$AGENT_CONTRACT"
}

a2_wiki_file_access_contract() {
    python3 "$FILE_ACCESS_CONTRACT"
}

a3_wiki_hub_output_contract() {
    python3 "$HUB_OUTPUT_CONTRACT"
}

# c1: the hub's page-update and log-entry rules stay stated, the durable
# behaviour the two retired wiki reproductions checked.
c1_wiki_log_and_updated_contract() {
    local ok=true hub="$WIKI_SKILL/SKILL.md"
    grep -Fq -- '**Updating existing pages**: always bump the `updated` date.' "$hub" \
        || { log "    the hub no longer bumps updated on an edited page"; ok=false; }
    grep -Fq -- 'files actually created or updated' "$hub" \
        || { log "    the hub no longer lists the changed files in the log entry"; ok=false; }
    $ok
}

# c2: the auto_shaper_wiki rotation move keeps its tracked probe, its guarded
# plain-mv fallback, its no-clobber refusal, and the live preamble, and the
# four move cases behave as the block states.
c2_rotation_move_contract() {
    local ok=true agent="$REPO_ROOT/plugins/knowledge_management/agents/auto_shaper_wiki.md"
    local work="$SCRATCH/rotation_contract"
    rm -rf "$work"
    mkdir -p "$work"
    local block="$work/rotation_block.txt"
    awk '/^[[:space:]]*<fix_log_rotation>[[:space:]]*$/{on=1} on{print} /^[[:space:]]*<\/fix_log_rotation>[[:space:]]*$/{exit}' \
        "$agent" > "$block"
    [[ -s "$block" ]] || { log "    no <fix_log_rotation> block"; return 1; }

    grep -Fq -- 'git ls-files --error-unmatch' "$block" \
        || { log "    the rotation move states no tracked probe"; ok=false; }
    grep -Fq -- 'git mv' "$block" \
        || { log "    the rotation move no longer names git mv"; ok=false; }
    grep -Fq -- 'mv -n' "$block" \
        || { log "    the fallback move states no no-clobber flag"; ok=false; }
    grep -Fq -- '[ -e "$archive" ]' "$block" \
        || { log "    the fallback move states no occupied-destination guard"; ok=false; }
    grep -Fq -- 'live `log.md`' "$block" \
        || { log "    the rotation move does not name the live preamble"; ok=false; }

    rotate() {
        local wiki=$1 archive=$2 branch
        if (cd "$wiki" && git ls-files --error-unmatch log.md >/dev/null 2>&1); then
            branch="git mv"
            (cd "$wiki" && git mv log.md "$archive") || return 1
        else
            branch="mv"
            (
                cd "$wiki" || exit 1
                if [ -e "$archive" ]; then exit 1; fi
                mv -n log.md "$archive"
            ) || return 1
        fi
        printf '%s' "$branch"
    }

    stage_wiki() {
        local dir=$1
        mkdir -p "$dir"
        printf '## [2026-01-01 00:00] note | a\n' > "$dir/log.md"
    }

    local plain="$work/plain" untracked="$work/untracked" tracked="$work/tracked"
    local occupied_plain="$work/occupied-plain" occupied_tracked="$work/occupied-tracked"
    local branch

    stage_wiki "$plain"
    branch=$(rotate "$plain" log-2026.md) || { log "    rotation failed off-git"; ok=false; }
    [[ "$branch" == "mv" && -f "$plain/log-2026.md" && ! -e "$plain/log.md" ]] \
        || { log "    the non-git wiki did not rotate with plain mv"; ok=false; }

    stage_wiki "$untracked"
    (
        set -e
        cd "$untracked"
        git init --quiet --initial-branch=main
        git config user.name "Harness"
        git config user.email "harness@example.test"
        printf 'base\n' > tracked.txt
        git add tracked.txt
        git commit --quiet -m "base"
    ) || { log "    cannot stage the untracked-log repository"; ok=false; }
    branch=$(rotate "$untracked" log-2026.md) || { log "    rotation failed on an untracked log"; ok=false; }
    [[ "$branch" == "mv" && -f "$untracked/log-2026.md" ]] \
        || { log "    an untracked log did not rotate with plain mv"; ok=false; }

    stage_wiki "$tracked"
    (
        set -e
        cd "$tracked"
        git init --quiet --initial-branch=main
        git config user.name "Harness"
        git config user.email "harness@example.test"
        git add log.md
        git commit --quiet -m "base"
    ) || { log "    cannot stage the tracked-log repository"; ok=false; }
    branch=$(rotate "$tracked" log-2026.md) || { log "    rotation failed on a tracked log"; ok=false; }
    (cd "$tracked" && git status --porcelain | grep -Fq 'R  log.md -> log-2026.md') \
        || { log "    git did not record the tracked move as a rename"; ok=false; }

    stage_wiki "$occupied_plain"
    printf '## [2025-01-01 00:00] note | older\n' > "$occupied_plain/log-2026.md"
    if branch=$(rotate "$occupied_plain" log-2026.md); then
        log "    the plain-mv fallback replaced an occupied archive"
        ok=false
    fi
    grep -Fq 'older' "$occupied_plain/log-2026.md" \
        || { log "    the fallback destroyed the occupied archive"; ok=false; }
    [[ -f "$occupied_plain/log.md" ]] \
        || { log "    the fallback removed the log it refused to move"; ok=false; }

    stage_wiki "$occupied_tracked"
    printf '## [2025-01-01 00:00] note | older\n' > "$occupied_tracked/log-2026.md"
    (
        set -e
        cd "$occupied_tracked"
        git init --quiet --initial-branch=main
        git config user.name "Harness"
        git config user.email "harness@example.test"
        git add log.md log-2026.md
        git commit --quiet -m "base"
    ) || { log "    cannot stage the occupied-archive repository"; ok=false; }
    if branch=$(rotate "$occupied_tracked" log-2026.md); then
        log "    the git-mv route replaced an occupied archive"
        ok=false
    fi
    grep -Fq 'older' "$occupied_tracked/log-2026.md" \
        || { log "    git mv destroyed the occupied archive"; ok=false; }
    [[ -f "$occupied_tracked/log.md" ]] \
        || { log "    git mv removed the log it refused to move"; ok=false; }
    $ok
}

# c3: the citation finding's report-only disposition is stated once in
# <fix_moves>, the superseded two-carve-outs wording is gone, and
# <compile_issue_list> emits `report only` with no body edit.
c3_citation_report_only_contract() {
    local ok=true agent="$REPO_ROOT/plugins/knowledge_management/agents/auto_shaper_wiki.md"
    local work="$SCRATCH/citation_contract"
    rm -rf "$work"
    mkdir -p "$work"
    local moves="$work/fix_moves.txt" compile="$work/compile_issue_list.txt"
    awk '/<fix_moves>/{on=1} on{print} /<\/fix_moves>/{on=0}' \
        "$agent" > "$moves"
    awk '/<compile_issue_list>/{on=1} on{print} /<\/compile_issue_list>/{exit}' \
        "$agent" > "$compile"
    [[ -s "$moves" ]] || { log "    no <fix_moves> block"; return 1; }
    [[ -s "$compile" ]] || { log "    no <compile_issue_list> block"; return 1; }
    local moves_flat compile_flat
    moves_flat=$(tr '\n' ' ' < "$moves" | tr -s ' ')
    compile_flat=$(tr '\n' ' ' < "$compile" | tr -s ' ')

    printf '%s' "$moves_flat" | grep -Fq -- 'report-only disposition' \
        || { log "    citation is not named a report-only disposition"; ok=false; }
    printf '%s' "$moves_flat" | grep -Fq -- 'name each one in the final report' \
        || { log "    final-report naming of each citation finding is missing"; ok=false; }
    printf '%s' "$moves_flat" | grep -Fq -- '`report only` in the `<compile_issue_list>` `->` column' \
        || { log "    fix_moves does not route citation to report only"; ok=false; }
    printf '%s' "$moves_flat" | grep -Fq -- 'apply no body edit' \
        || { log "    fix_moves does not state the no-body-edit posture"; ok=false; }
    printf '%s' "$moves_flat" | grep -Fq -- 'Two carve-outs' \
        && { log "    superseded two-carve-outs wording remains"; ok=false; }

    printf '%s' "$compile_flat" | grep -Fq -- 'A `citation` finding' \
        || { log "    compile_issue_list does not name a citation finding"; ok=false; }
    printf '%s' "$compile_flat" | grep -Fq -- '`report only` in the `->` column' \
        || { log "    compile_issue_list does not emit report only"; ok=false; }
    printf '%s' "$compile_flat" | grep -Fq -- 'applies no body edit' \
        || { log "    compile_issue_list does not state the no-body-edit posture"; ok=false; }
    $ok
}

###############################################################################
# Run all scenarios
###############################################################################

scenario d1  "no wiki and no marker on the ladder"           d1_no_wiki_no_marker
scenario d2  "marker at CWD, no wiki at HOME"                d2_marker_at_cwd_no_home_wiki
scenario d3  "marker at CWD, wiki at HOME"                   d3_marker_at_cwd_wiki_at_home
scenario d4  "every ladder level opted out"                  d4_all_levels_opted_out
scenario d5  "existing wiki at CWD"                          d5_existing_wiki_at_cwd
scenario d6  "upstream wiki, CWD undecided (must ask)"       d6_upstream_wiki_cwd_undecided
scenario d7  "outside HOME, no state"                        d7_outside_home_no_state
scenario d8  "outside HOME, local wiki"                      d8_outside_home_with_local_wiki
scenario d9  "outside HOME, marker only"                     d9_outside_home_with_marker
scenario d10 "multi-level walk-up to HOME wiki"              d10_multi_level_walk_up
scenario d11 "--check on missing auto-resolved path"         d11_check_flag_missing_dir
scenario d12 "retired wiki dir (.no_wiki inside wiki/)"      d12_retired_wiki_marker
scenario d13 "CWD is a markered wiki (short-circuit)"        d13_cwd_is_markered_wiki
scenario d14 "CWD is a topic-named markered wiki"            d14_cwd_is_topic_named_wiki
scenario d15 "CWD markerless 'wiki' not adopted"             d15_cwd_markerless_wiki_not_adopted
scenario d16 "parent of topic-named wiki resolves"           d16_parent_of_topic_named_wiki_resolves
scenario d17 "subdirectory of a wiki asks"                   d17_subdir_of_wiki_asks
scenario d18 "marker-count boundary (2 yes, 1 no)"           d18_marker_count_boundary
scenario d19 ".no_wiki at CWD overrides predicate"           d19_no_wiki_at_cwd_overrides
scenario d20 "markered dir w/o 'wiki' in name not adopted"   d20_markered_nonwiki_name_not_adopted
scenario d21 "positional wiki path resolves itself"          d21_positional_wiki_path
scenario d22 "positional non-wiki path"                      d22_positional_non_wiki_path
scenario d23 "positional missing path exits 1"               d23_positional_missing_path
scenario d24 "usage error exits 3, not 2"                    d24_usage_error_exits_three
scenario d25 "dot-named wiki skipped in child scan"          d25_dot_named_wiki_skipped

scenario dp1  "parity: no wiki and no marker on the ladder"           dp1_parity_no_wiki_no_marker
scenario dp2  "parity: marker at CWD, no wiki at HOME"                dp2_parity_marker_at_cwd_no_home_wiki
scenario dp3  "parity: marker at CWD, wiki at HOME"                   dp3_parity_marker_at_cwd_wiki_at_home
scenario dp4  "parity: every level opted out, no HOME wiki on disk"   dp4_parity_all_levels_opted_out_missing_home_wiki
scenario dp4b "parity: every level opted out, HOME wiki on disk"      dp4b_parity_all_levels_opted_out_with_home_wiki
scenario dp5  "parity: existing wiki at CWD"                          dp5_parity_existing_wiki_at_cwd
scenario dp6  "parity: upstream wiki, CWD undecided (must ask)"       dp6_parity_upstream_wiki_cwd_undecided
scenario dp7  "parity: outside HOME, no state"                        dp7_parity_outside_home_no_state
scenario dp8  "parity: outside HOME, local wiki"                      dp8_parity_outside_home_with_local_wiki
scenario dp9  "parity: outside HOME, marker only, HOME wiki on disk"  dp9_parity_outside_home_with_marker
scenario dp9b "parity: outside HOME, marker only, no HOME wiki"       dp9b_parity_outside_home_with_marker_missing_home_wiki
scenario dp10 "parity: multi-level walk-up to HOME wiki"              dp10_parity_multi_level_walk_up
scenario dp12 "parity: retired wiki dir (.no_wiki inside wiki/)"      dp12_parity_retired_wiki_marker
scenario dp13 "parity: CWD is a markered wiki"                       dp13_parity_cwd_is_markered_wiki
scenario dp14 "parity: CWD is a topic-named markered wiki"           dp14_parity_cwd_is_topic_named_wiki
scenario dp15 "parity: CWD markerless 'wiki'"                        dp15_parity_cwd_markerless_wiki
scenario dp16 "parity: parent of topic-named wiki"                   dp16_parity_parent_of_topic_named_wiki
scenario dp17 "parity: subdirectory of a wiki"                       dp17_parity_subdir_of_wiki
scenario dp18 "parity: marker-count boundary"                       dp18_parity_marker_count_boundary
scenario dp19 "parity: .no_wiki at CWD overrides"                   dp19_parity_no_wiki_at_cwd_overrides
scenario dp20 "parity: markered dir w/o 'wiki' in name"             dp20_parity_markered_nonwiki_name
scenario dp21 "parity: dot-named wiki beside a visible one"         dp21_parity_dot_named_wiki_beside_visible
scenario dp22 "parity: dot-named wiki only"                         dp22_parity_dot_named_wiki_only

scenario i1  "init creates fresh wiki structure"             i1_init_fresh
scenario i2  "init refuses over existing SCHEMA.md"          i2_init_refuses_existing_wiki
scenario i3  "init refuses with .no_wiki marker"             i3_init_refuses_no_wiki_marker
scenario i4  "init prints help with no args"                 i4_init_no_args_help

scenario l1  "lint fresh wiki passes (--quiet)"              l1_lint_fresh_wiki
scenario l2  "lint blocks on missing SCHEMA.md"              l2_lint_no_schema
scenario l3  "lint blocks on missing index.md"               l3_lint_no_index
scenario l4  "lint blocks on broken md link"                 l4_lint_broken_link
scenario l5  "lint warns on orphan page"                     l5_lint_orphan_page
scenario l6  "lint warns on [[wikilink]] outside code"       l6_lint_wikilink_syntax
scenario l7  "lint warns on page missing from index"         l7_lint_page_missing_from_index
scenario l8  "lint warns on off-taxonomy tag"                l8_lint_off_taxonomy_tag
scenario l9  "lint warns on raw source sha256 drift"         l9_lint_raw_source_drift
scenario l10 "lint warns on log.md preamble drift"           l10_lint_boilerplate_mismatch
scenario l11 "lint warns on undeclared custom field"         l11_lint_undeclared_custom_field
scenario l12 "lint flags stale page (>90d older) as info"   l12_lint_stale_page
scenario l13 "lint flags oversized page as info"             l13_lint_oversized_page
scenario l14 "lint flags taxonomy-style drift as info"       l14_lint_taxonomy_style_drift
scenario l15 "lint flags markdown style nit as info"         l15_lint_markdown_style_nit
scenario l16 "lint blocks on broken sources frontmatter"     l16_lint_broken_source_path
scenario l17 "lint flags deprecated body Sources section"    l17_lint_sources_section
scenario l18 "lint warns on [^name] footnote syntax"         l18_lint_footnote_syntax
scenario l19 "lint accepts inline source path links"         l19_lint_inline_path_links_are_not_footnotes
scenario l20 "lint undecided -> exit 2 + positional hint"    l20_lint_undecided_hint
scenario l21 "lint blocks absolute sources entry"            l21_lint_absolute_sources_entry
scenario l22 "lint blocks absolute raw source_path"          l22_lint_raw_source_path_absolute
scenario l23 "lint accepts portable/absent source_path"      l23_lint_source_path_portable_ok
scenario l24 "lint blocks repo-escaping raw source_path"     l24_lint_raw_source_path_escape
scenario l25 "lint blocks raw-escaping sources entry"        l25_lint_sources_escape_raw
scenario l26 "lint accepts in-repo outside-wiki source_path" l26_lint_source_path_in_repo_outside_wiki
scenario l27 "lint skips source_path for non-repo wiki"      l27_lint_non_repo_wiki_unrestricted
scenario l28 "lint reads block-style tags/sources lists"     l28_lint_block_style_frontmatter
scenario l29 "lint belt-warns unreadable list block"         l29_lint_frontmatter_unreadable_block
scenario l30 "lint skips fenced/inline-code links"           l30_lint_link_code_fence_handling
scenario l31 "lint treats fresh example taxonomy as absent"  l31_lint_fresh_wiki_taxonomy_absent
scenario l32 "lint index membership (path) + dangling"       l32_lint_index_membership_and_dangling
scenario l33 "lint drift names wiki-relative fix path"       l33_lint_drift_message_wiki_relative_path
scenario l34 "lint blocks absolute body link"                l34_lint_absolute_body_link
scenario l35 "lint warns raw missing ingested/sha256"        l35_lint_raw_frontmatter_presence
scenario l36 "lint warns origin-field forms (non-repo)"      l36_lint_raw_origin_forms_non_repo
scenario l37 "lint single warn for URL-valued source_path"   l37_lint_url_source_path_single_finding_in_repo
scenario l38 "lint warns in-repo absolute source_path"       l38_lint_abs_source_path_in_repo_warns_with_rewrite
scenario l39 "lint warns in-raw absolute sources entry"      l39_lint_abs_sources_in_raw_warns_with_rewrite
scenario l40 "lint raw-origin file:// in-repo rewrite"       l40_lint_raw_origin_fileurl_in_repo_rewrite
scenario l41 "lint accepted info leaves live report"         l41_lint_accepted_info_leaves_live_report
scenario l42 "lint acceptance never suppresses non-info"    l42_lint_acceptance_never_suppresses_non_info
scenario l43 "lint fenced acceptance is documentation"      l43_lint_fenced_acceptance_is_documentation
scenario l44 "lint discriminator selects one of two"        l44_lint_discriminator_selects_one_of_two
scenario l45 "lint two-field survives volatile message"     l45_lint_two_field_survives_volatile_message
scenario l46 "lint non-whitelisted needs three-field"       l46_lint_non_whitelisted_needs_three_field
scenario l47 "lint em-dash discriminator matches in full"   l47_lint_em_dash_discriminator_matches_whole_message
scenario l48 "lint four-field pins one line"                l48_lint_four_field_pins_one_line
scenario l49 "lint accepts a page with no sources key"      l49_lint_sources_key_optional
scenario l50 "lint validates optional checked field"        l50_lint_checked_field_optional_and_validated
scenario l51 "lint clean on domain+taxonomy-only wiki"      l51_lint_customized_fresh_wiki_clean
scenario l52 "lint allows deleted SCHEMA attribution"       l52_lint_schema_attribution_deletable
scenario l53 "lint no blocking on pre-rework SCHEMA"        l53_lint_pre_rework_schema_no_blocking
scenario l54 "lint flags duplicate log heading as info"      l54_lint_duplicate_log_heading
scenario l55 "lint clean on unique date-only headings"       l55_lint_unique_date_only_log_headings
scenario l56 "lint flags outside-wiki log subjects"       l56_lint_log_scope_outside_wiki_subjects
scenario l57 "lint log-scope two-field survives count"   l57_lint_log_scope_two_field_survives_volatile_count
scenario l58 "lint mid-bullet citation is provenance"    l58_lint_log_scope_mid_bullet_citation_is_provenance
scenario l59 "lint aggregates log-scope across entries"  l59_lint_log_scope_aggregates_across_entries
scenario l60 "lint log-scope skips fenced bullets"       l60_lint_log_scope_fenced_block_is_documentation
scenario l61 "lint clean on non-path log subject"        l61_lint_log_scope_non_path_subject
scenario l62 "lint clean on scaffold seed prose subject" l62_lint_log_scope_scaffold_seed_prose_subject
scenario l63 "lint clean on absent wiki-file subject"    l63_lint_log_scope_absent_wiki_file_is_clean
scenario l64 "lint reads a decorated path subject"        l64_lint_log_scope_decorated_path_subject
scenario l65 "lint insert-only extension acknowledged"   l65_lint_insert_only_extension_acknowledged
scenario l66 "lint accepted marker stays parameterized"  l66_lint_accepted_marker_parameterized
scenario l67 "lint delete/replace still warns"           l67_lint_delete_replace_still_warns
scenario l68 "lint declared boilerplate honoured"        l68_lint_declared_boilerplate_honoured
scenario l69 "lint undeclared delete/replace warns"      l69_lint_undeclared_delete_replace_warns
scenario l70 "lint fenced declare is documentation"      l70_lint_fenced_declare_is_documentation
scenario l71 "lint unmatched declare is live info"       l71_lint_unmatched_declare_is_live_info
scenario l72 "lint declared per-slot isolation"          l72_lint_declared_per_slot_isolation
scenario l73 "lint flags meta-prose phrase as info"      l73_lint_meta_prose_phrase
scenario l74 "lint flags long lead paragraph as info"    l74_lint_meta_prose_long_lead
scenario l75 "entry-aware log read bounds the slice"     l75_entry_aware_log_read_bounds_slice
scenario l76 "log rotation warns past 500 entries"       l76_lint_log_rotation_warn_past_500
scenario l77 "log rotation blocks past 1000 entries"       l77_lint_log_rotation_blocking_past_1000
scenario l78 "lint citation declared but never cited"       l78_lint_citation_declared_never_cited
scenario l79 "lint citation cited but undeclared"           l79_lint_citation_cited_but_undeclared
scenario l80 "lint citation zero inline links backstop"     l80_lint_citation_zero_inline_links
scenario l81 "lint citation channels agree (true negative)" l81_lint_citation_channels_agree
scenario l82 "lint citation page-citing query stays clean"  l82_lint_citation_page_citing_query_clean
scenario l83 "lint citation ignores code examples"          l83_lint_citation_code_examples_not_citations
scenario l84 "lint citation synthesis-type gate"            l84_lint_citation_synthesis_type_gate
scenario l85 "lint citation findings stay info-only"        l85_lint_citation_findings_are_info_only

scenario a1  "auto_shaper fidelity-safe token-cost contract" a1_auto_shaper_fidelity_safe_token_cost_contract
scenario a2  "wiki file-access guidance contract"          a2_wiki_file_access_contract
scenario a3  "wiki hub output contract"                    a3_wiki_hub_output_contract
scenario c1  "wiki page-update and log-entry contract"      c1_wiki_log_and_updated_contract
scenario c2  "auto_shaper rotation move contract"            c2_rotation_move_contract
scenario c3  "auto_shaper citation report-only contract"     c3_citation_report_only_contract

scenario s1  "compute_sha256 inserts missing sha line"        s1_sha256_insert_missing
scenario s2  "compute_sha256 unchanged when correct"          s2_sha256_unchanged_when_correct
scenario s3  "compute_sha256 updates on drift"                s3_sha256_update_on_drift
scenario s4  "compute_sha256 skips when no frontmatter"       s4_sha256_no_frontmatter_skip
scenario s5  "compute_sha256 --check flags drift exit 1"      s5_sha256_check_flags_drift
scenario s6  "compute_sha256 --check clean exits 0"           s6_sha256_check_clean
scenario s7  "compute_sha256 recurses into a directory"       s7_sha256_directory_recurses

# G1: layer2/grade.py fails a run whose only pass delivered nothing. An empty
# response.txt is the inert-worker case; a grader that exits 0 there would let
# run.py's aggregate path treat a silent pass as a clean run.
g1_grade_empty_delivery_exits_nonzero() {
    local home run pass rc
    home=$(fresh_scratch g1)
    run="$home/run"
    pass="$run/L2-1/pass-1"
    mkdir -p "$pass"
    : > "$pass/response.txt"
    python3 "$SCRIPT_DIR/../layer2/grade.py" "$run" >/dev/null 2>&1 && rc=0 || rc=$?
    if [[ "$rc" -eq 1 ]]; then
        return 0
    fi
    log "    layer2 grade.py exited $rc on a run holding one empty response.txt"
    log "    expected exit 1 for a graded failure; exit 2 means a broken grader"
    return 1
}

# G2: layer2/aggregate.py names the baseline it compared against, states that
# baseline's shape, and warns when the baseline covered fewer scenarios than
# the current run. The warning is informational: only assertion/scenario
# regressions drive the exit status, so a narrowed compare still exits 0 and a
# real regression still exits 1. A baseline that covers every scenario compares
# without the warning and records narrowed: false.
g2_aggregate_names_baseline_and_warns_on_narrowing() {
    local home run prev out rc full
    home=$(fresh_scratch g2)
    run="$home/run-current"
    prev="$home/run-prior-debug/benchmark.json"
    mkdir -p "$run/L2-1/pass-1" "$run/L2-2/pass-1" "$(dirname "$prev")"
    python3 - "$run" "$prev" <<'PY'
import json
import pathlib
import sys

run = pathlib.Path(sys.argv[1])
prev = pathlib.Path(sys.argv[2])


def write_pass(scenario_id, passed):
    pass_dir = run / scenario_id / "pass-1"
    pass_dir.mkdir(parents=True, exist_ok=True)
    (pass_dir / "grading.json").write_text(json.dumps({
        "pass_rate": 1.0 if passed else 0.0,
        "passed": passed,
        "expectations": [{"text": "assertion", "passed": passed}],
    }))
    (pass_dir / "timing.json").write_text(json.dumps({
        "duration_ms": 1000,
        "total_tokens": 10,
    }))


write_pass("L2-1", True)
write_pass("L2-2", True)
prev.write_text(json.dumps({
    "run_id": "run-prior-debug",
    "scenarios": [{
        "scenario_id": "L2-1",
        "all_passes_clean": True,
        "per_assertion": {
            "assertion": {"pass_rate": 1.0, "passes": 1, "total": 1},
        },
    }],
}))
PY

    out=$(python3 "$SCRIPT_DIR/../layer2/aggregate.py" "$run" --previous "$prev" 2>&1) && rc=0 || rc=$?
    assert_eq "narrowing compare exits 0" "$rc" "0" || { log "$out"; return 1; }
    for needle in \
        "Baseline: run-prior-debug" \
        "1 scenario(s): L2-1" \
        "COMPARE WARNING" \
        "not covered by the baseline: L2-2"
    do
        if [[ "$out" != *"$needle"* ]]; then
            log "    compare output missing: $needle"
            log "$out"
            return 1
        fi
    done

    # Flip one pass to failing: the same narrowing warning prints, and the
    # regression still drives exit status.
    python3 - "$run" <<'PY'
import json
import pathlib
import sys

grading = pathlib.Path(sys.argv[1]) / "L2-1" / "pass-1" / "grading.json"
data = json.loads(grading.read_text())
data.update({
    "pass_rate": 0.0,
    "passed": False,
    "expectations": [{"text": "assertion", "passed": False}],
})
grading.write_text(json.dumps(data))
PY
    out=$(python3 "$SCRIPT_DIR/../layer2/aggregate.py" "$run" --previous "$prev" 2>&1) && rc=0 || rc=$?
    assert_eq "regression compare exits 1" "$rc" "1" || { log "$out"; return 1; }
    for needle in "COMPARE WARNING" "REGRESSIONS DETECTED"
    do
        if [[ "$out" != *"$needle"* ]]; then
            log "    compare output missing: $needle"
            log "$out"
            return 1
        fi
    done

    # Full coverage: restore the clean pass, then compare against a baseline
    # holding both scenarios. No narrowing warning prints and benchmark.json
    # records the comparison as not narrowed.
    python3 - "$run" <<'PY'
import json
import pathlib
import sys

grading = pathlib.Path(sys.argv[1]) / "L2-1" / "pass-1" / "grading.json"
data = json.loads(grading.read_text())
data.update({
    "pass_rate": 1.0,
    "passed": True,
    "expectations": [{"text": "assertion", "passed": True}],
})
grading.write_text(json.dumps(data))
PY
    full="$home/run-prior-full/benchmark.json"
    mkdir -p "$(dirname "$full")"
    python3 - "$full" <<'PY'
import json
import pathlib
import sys


def scenario(scenario_id):
    return {
        "scenario_id": scenario_id,
        "all_passes_clean": True,
        "per_assertion": {
            "assertion": {"pass_rate": 1.0, "passes": 1, "total": 1},
        },
    }


pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "run_id": "run-prior-full",
    "scenarios": [scenario("L2-1"), scenario("L2-2")],
}))
PY

    out=$(python3 "$SCRIPT_DIR/../layer2/aggregate.py" "$run" --previous "$full" 2>&1) && rc=0 || rc=$?
    assert_eq "full-coverage compare exits 0" "$rc" "0" || { log "$out"; return 1; }
    if [[ "$out" == *"COMPARE WARNING"* ]]; then
        log "    full-coverage compare printed COMPARE WARNING"
        log "$out"
        return 1
    fi
    if ! python3 - "$run/benchmark.json" <<'PY'
import json
import pathlib
import sys

baseline = json.loads(pathlib.Path(sys.argv[1]).read_text()).get("baseline") or {}
sys.exit(0 if baseline.get("narrowed") is False else 1)
PY
    then
        log "    benchmark.json baseline.narrowed is not false"
        return 1
    fi
    return 0
}

# G3: layer2/grade.py's `sub_agent_report_relayed` assertion has three
# outcomes, each pinned here against the grader's own `check()`:
#   (a) PASS when the captured report is contained in the response after
#       whitespace collapse, even when the two wrap their lines differently;
#   (b) FAIL with a message naming the first omitted span when the response
#       paraphrases the report instead of relaying it;
#   (c) FAIL with the exact evidence `no sub-agent report captured` when the
#       pass captured no report at all.
# `check()` is imported directly so this stays a deterministic data-transform
# test with no worker: the ctx carries exactly the keys the grader builds.
g3_grade_sub_agent_report_relayed_outcomes() {
    local home rc
    home=$(fresh_scratch g3)
    python3 - "$SCRIPT_DIR/../layer2/grade.py" "$home" <<'PY' && rc=0 || rc=$?
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("wiki_layer2_grade", sys.argv[1])
grade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(grade)

sandbox = pathlib.Path(sys.argv[2])
assertion = {"id": "A7", "type": "sub_agent_report_relayed"}
report = (
    "Audit report\n\n"
    "### 1. Discovery\n\n"
    "- Exit code: `0`\n"
    "- Resolved wiki: `HOME/proj/wiki`\n\n"
    "### 2. Lint\n\n"
    "- Blocking findings: 0\n"
    "- Warnings: 1 (orphan page `entities/transformer.md`)\n"
)


def ctx(sub_agent_report, response):
    return {
        "report": {},
        "sandbox": sandbox,
        "sandbox_root": sandbox,
        "response": response,
        "sub_agent_report": sub_agent_report,
    }


failures = []

# (a) Relayed verbatim, wrapped differently from the captured report.
response_relayed = (
    "Here is the agent's report verbatim:\n\n"
    "Audit report\n\n"
    "### 1.\n"
    "Discovery\n\n"
    "- Exit code: `0`\n"
    "- Resolved wiki:\n"
    "  `HOME/proj/wiki`\n\n"
    "### 2. Lint\n\n"
    "- Blocking findings: 0\n"
    "- Warnings: 1\n"
    "  (orphan page `entities/transformer.md`)\n\n"
    "End of report."
)
passed, evidence = grade.check(assertion, ctx(report, response_relayed))
if not passed:
    failures.append(f"(a) relayed report did not pass: {evidence}")

# (b) Paraphrased instead of relayed: FAIL, naming the first omitted span.
response_paraphrased = (
    "The audit came back clean: discovery exited 0 and the wiki resolved to "
    "HOME/proj/wiki, with no blocking lint findings and one orphan-page warning."
)
passed, evidence = grade.check(assertion, ctx(report, response_paraphrased))
if passed:
    failures.append("(b) paraphrased response unexpectedly passed")
elif "first omitted span:" not in evidence:
    failures.append(f"(b) failure did not name an omitted span: {evidence}")
elif "Audit report" not in evidence:
    failures.append(f"(b) omitted span did not quote the report: {evidence}")

# (c) No capture: FAIL with the named evidence.
passed, evidence = grade.check(assertion, ctx("", response_relayed))
if passed:
    failures.append("(c) empty capture unexpectedly passed")
elif evidence != "no sub-agent report captured":
    failures.append(f"(c) evidence is not the named no-capture text: {evidence}")

if failures:
    for line in failures:
        print(f"    {line}", file=sys.stderr)
    sys.exit(1)
PY
    if [[ "$rc" -ne 0 ]]; then
        log "    layer2 grade.py check() did not match the three expected outcomes"
        return 1
    fi
    return 0
}

# G4: layer2/grade.py records the remediation mechanism a report declares,
# and aggregate.py carries it into the benchmark per pass and the markdown
# report. The task's measurement records script-vs-hand-edit on every pass.
g4_grade_records_remediation_mechanism() {
    local home run pass
    home=$(fresh_scratch g4)
    run="$home/run"
    pass="$run/AS-14/pass-1"
    mkdir -p "$pass"
    cat > "$pass/report.md" <<'EOF'
==== TEST REPORT ====
discovery_invoked: yes
discovery_exit: 0
discovery_resolved_path: /tmp/wiki
ambiguity_presented_to_user: no
init_invoked: no
init_target: n/a
files_created: none
files_modified: none
linted: yes
lint_findings: 0 blocking, 0 warn, 0 info
log_preamble_units_ensured: yes
remediation_mechanism: script
final_action_summary: ran the bundled convergence script
==== END REPORT ====
EOF
    : > "$pass/response.txt"
    printf '%s\n' '{"claude_rc": 0, "duration_ms": 1, "total_tokens": 1}' > "$pass/timing.json"
    python3 "$SCRIPT_DIR/../layer2/grade.py" "$run" >/dev/null 2>&1 || true
    if ! python3 - "$pass/grading.json" <<'PY'
import json
import sys

grading = json.load(open(sys.argv[1]))
assert grading.get("remediation_mechanism") == "script", grading.get(
    "remediation_mechanism"
)
PY
    then
        log "    [grading.json did not record remediation_mechanism: script]"
        return 1
    fi
    python3 "$SCRIPT_DIR/../layer2/aggregate.py" "$run" >/dev/null 2>&1 || true
    if ! python3 - "$run/benchmark.json" "$run/benchmark.md" <<'PY'
import json
import pathlib
import sys

benchmark = json.load(open(sys.argv[1]))
per_pass = benchmark["scenarios"][0]["per_pass"][0]
assert per_pass.get("remediation_mechanism") == "script", per_pass
markdown = pathlib.Path(sys.argv[2]).read_text()
assert "Remediation mechanism per pass" in markdown, "section missing"
assert "| AS-14 | pass-1 | script |" in markdown, markdown
PY
    then
        log "    [benchmark did not carry the per-pass remediation mechanism]"
        return 1
    fi
    return 0
}

scenario g1  "layer2 grade fails an empty-delivery pass"      g1_grade_empty_delivery_exits_nonzero
scenario g2  "layer2 compare names baseline and warns"        g2_aggregate_names_baseline_and_warns_on_narrowing
scenario g3  "layer2 report-relay assertion has three outcomes" g3_grade_sub_agent_report_relayed_outcomes
scenario g4  "layer2 records per-pass remediation mechanism"   g4_grade_records_remediation_mechanism

###############################################################################
# merge_log_preamble.py scenarios
#
# The convergence script owns the canonical unit identity table. These
# fixtures exercise each distribution case and guard from the task:
#   insert a missing labeled unit, refresh a drifted labeled unit, refresh a
#   drifted unlabeled unit, refresh through a prior alias, owner-line
#   preservation as an invariant, the ambiguous near-match refusal, duplicate
#   and template/table refusals, idempotence, byte-identical entries below the
#   preamble, and the live-boilerplate-warn path.
###############################################################################

MERGE="$WIKI_SKILL/scripts/merge_log_preamble.py"
TEMPLATE_LOG="$WIKI_SKILL/references/template_log.md"

# _merge_preamble <log.md> <template> <spec>...
# Rewrite log.md's preamble from the canonical template, applying one fixture
# mutation per spec, and leave the entries below untouched.
# Specs: drop-group|||<Label>, drop-line|||<stem>,
#        reword-group|||<Label>|||<text>, reword-line|||<stem>|||<text>,
#        add-owner|||<text>                      (blockquote, appended at end)
#        add-owner-after|||<anchor>|||<text>     (blockquote, no blank)
#        add-blank-owner-after|||<anchor>|||<text> (blank, then blockquote)
#        add-plain|||<text>                      (plain line, appended at end)
#        add-plain-after|||<anchor>|||<text>     (plain line, no blank)
#        add-blank-plain-after|||<anchor>|||<text> (blank, then plain line)
#        insert-in-group|||<Label>|||<text>       (line inserted inside a unit)
_merge_preamble() {
    python3 - "$@" <<'PREAMBLEPY'
import re
import sys
import pathlib

log = pathlib.Path(sys.argv[1])
template = pathlib.Path(sys.argv[2])
specs = sys.argv[3:]

LABEL_RE = re.compile(r"^> ([A-Z][A-Za-z]*): ")
UNLABELED_STEMS = ("Chronological record", "When this file exceeds")


def preamble_of(text):
    i = text.find("\n## ")
    return (text[:i] if i != -1 else text).rstrip("\n") + "\n"


def is_boundary(line):
    return bool(LABEL_RE.match(line)) or any(
        line.startswith("> " + stem) for stem in UNLABELED_STEMS
    )


canonical = preamble_of(template.read_text()).splitlines()
first = next(n for n, ln in enumerate(canonical) if is_boundary(ln))
header, body = canonical[:first], canonical[first:]

units = []
for line in body:
    if is_boundary(line) or not units:
        units.append([line])
    else:
        units[-1].append(line)


def find(pred):
    for n, unit in enumerate(units):
        if pred(unit[0]):
            return n
    raise SystemExit(f"fixture error: no preamble unit matched in {template}")


def insert_after(anchor, inserted):
    position = find(lambda ln, a=anchor: ln.startswith(a)) + 1
    units[position:position] = inserted


for spec in specs:
    op, *args = spec.split("|||")
    if op == "drop-group":
        del units[find(lambda ln, a=args[0]: ln.startswith(f"> {a}: "))]
    elif op == "drop-line":
        del units[find(lambda ln, a=args[0]: ln.startswith(f"> {a}"))]
    elif op == "reword-group":
        units[find(lambda ln, a=args[0]: ln.startswith(f"> {a}: "))] = [
            f"> {args[0]}: {args[1]}"
        ]
    elif op == "reword-line":
        units[find(lambda ln, a=args[0]: ln.startswith(f"> {a}"))] = [f"> {args[1]}"]
    elif op == "add-owner":
        units.append([f"> {args[0]}"])
    elif op == "add-owner-after":
        insert_after(args[0], [[f"> {args[1]}"]])
    elif op == "add-blank-owner-after":
        insert_after(args[0], [[""], [f"> {args[1]}"]])
    elif op == "add-plain":
        units.append([args[0]])
    elif op == "add-plain-after":
        insert_after(args[0], [[args[1]]])
    elif op == "add-blank-plain-after":
        insert_after(args[0], [[""], [args[1]]])
    elif op == "insert-in-group":
        units[find(lambda ln, a=args[0]: ln.startswith(f"> {a}: "))].insert(
            1, args[1]
        )
    else:
        raise SystemExit(f"fixture error: unknown preamble op {op!r}")

rebuilt = "\n".join(header + [ln for unit in units for ln in unit]) + "\n"
existing = log.read_text()
i = existing.find("\n## ")
log.write_text(rebuilt + (existing[i:] if i != -1 else ""))
PREAMBLEPY
}

# _merge_fixture <id> <spec>... -> echoes the staged log.md path.
_merge_fixture() {
    local id=$1
    shift
    local home; home=$(fresh_scratch "$id")
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    _merge_preamble "$log" "$TEMPLATE_LOG" "$@"
    printf '%s' "$log"
}

# run_merge <log> -> echoes "<exit>|<stdout+stderr>".
run_merge() {
    local log=$1 out rc
    out=$(python3 "$MERGE" "$log" 2>&1) && rc=0 || rc=$?
    printf '%s|%s' "$rc" "$out"
}

# _merge_invariants <before> <after> <template>
# Asserts the task's cross-fixture invariant without going through the merge
# script's parser or classifier:
#   * every line the fixture added to the template preamble (a line-level
#     difflib insert) survives byte-identical and in order;
#   * every canonical template unit appears exactly once as a contiguous block
#     in the output preamble, so a refresh cannot leave a stale duplicate;
#   * every output preamble line is either a canonical template line or a line
#     the fixture inserted, so a stale canonical line replaced into the output
#     cannot pass;
#   * everything from the first `##` heading onward is byte-identical.
# Owner lines are derived from the template diff, not from the script's
# `_parse_region`/`_resolve`, so a parser blind spot cannot hide a deletion.
_merge_invariants() {
    python3 - "$@" <<'INVARIANTPY'
import difflib
import pathlib
import re
import sys

before = pathlib.Path(sys.argv[1]).read_text()
after = pathlib.Path(sys.argv[2]).read_text()
template = pathlib.Path(sys.argv[3]).read_text()

LABEL_RE = re.compile(r"^> ([A-Z][A-Za-z0-9_-]*): ")
UNLABELED_STEMS = ("Chronological record", "When this file exceeds")


def split_at(text):
    i = text.find("\n## ")
    if i == -1:
        return text.splitlines(), ""
    return text[:i].splitlines(), text[i:]


def is_boundary(line):
    return bool(LABEL_RE.match(line)) or any(
        line.startswith("> " + stem) for stem in UNLABELED_STEMS
    )


tpl_lines, _ = split_at(template)
before_lines, before_tail = split_at(before)
after_lines, after_tail = split_at(after)

start = next(
    (n for n, line in enumerate(tpl_lines) if is_boundary(line)),
    len(tpl_lines),
)
template_units = []
for line in tpl_lines[start:]:
    if is_boundary(line) or not template_units:
        template_units.append([line])
    else:
        template_units[-1].append(line)

fails = []

# Owner lines: the lines the fixture inserted relative to the canonical
# template. Replacements and deletions are canonical drift, not owner content.
owner_lines = []
for tag, _i1, _i2, j1, j2 in difflib.SequenceMatcher(
    None, tpl_lines, before_lines, autojunk=False
).get_opcodes():
    if tag == "insert":
        owner_lines.extend(before_lines[j1:j2])

cursor = 0
for line in owner_lines:
    while cursor < len(after_lines) and after_lines[cursor] != line:
        cursor += 1
    if cursor >= len(after_lines):
        fails.append(f"owner line missing or changed: {line!r}")
        break
    cursor += 1

# Every output line must be a canonical template line, a line the fixture
# inserted relative to the template, or a line from a fixture unit that carries
# no canonical anchor. A stale canonical line that survived a refresh belongs
# to a canonical unit on the fixture side, so it is in none of those sets and
# this check fails — the defect an insert/deletion-only invariant cannot see.
def anchor_key(line):
    match = LABEL_RE.match(line)
    if match:
        return ("label", f"{match.group(1)}:")
    for stem in UNLABELED_STEMS:
        if line.startswith("> " + stem):
            return ("stem", stem)
    return None


template_line_set = set(tpl_lines)
inserted_line_set = set(owner_lines)
template_anchor_keys = {anchor_key(unit[0]) for unit in template_units}
# Optional extra anchor tokens name canonical units a fixture ships under a
# prior alias (m4's template rename), so the alias unit stays canonical rather
# than being mistaken for owner content.
for token in sys.argv[4:]:
    template_anchor_keys.add(("label", token))
before_start = next(
    (n for n, line in enumerate(before_lines) if is_boundary(line)),
    len(before_lines),
)
before_units = []
for line in before_lines[before_start:]:
    if is_boundary(line) or not before_units:
        before_units.append([line])
    else:
        before_units[-1].append(line)

owner_unit_lines = []
for unit in before_units:
    key = anchor_key(unit[0])
    if key is None or key not in template_anchor_keys:
        owner_unit_lines.extend(unit)

allowed_lines = template_line_set | inserted_line_set | set(owner_unit_lines)
for line in after_lines:
    if line in allowed_lines:
        continue
    fails.append(
        "output carries a line that is neither canonical template text nor "
        f"owner content (stale canonical wording?): {line!r}"
    )
    break

for line in owner_unit_lines:
    if line in inserted_line_set or line in after_lines:
        continue
    fails.append(f"owner unit line missing from the output: {line!r}")
    break


# Canonical template lines must appear exactly once and in order. Owner lines
# may sit between them (a mid-unit owner insert), so a contiguous block is too
# strict; each line's occurrence count plus an in-order walk over the whole
# preamble still catches a stale duplicate or a reordering.
for unit in template_units:
    for line in unit:
        seen = sum(1 for candidate in after_lines if candidate == line)
        if seen != 1:
            fails.append(
                f"canonical template line {line!r} appears {seen} times"
            )
            break

cursor = 0
for unit in template_units:
    for line in unit:
        while cursor < len(after_lines) and after_lines[cursor] != line:
            cursor += 1
        if cursor >= len(after_lines):
            fails.append(
                f"canonical template line {line!r} missing or out of order"
            )
            break
        cursor += 1
    else:
        continue
    break

if before_tail != after_tail:
    fails.append("entries below the preamble are not byte-identical")

if fails:
    for line in fails:
        print(f"    {line}", file=sys.stderr)
    sys.exit(1)
print("invariants OK")
INVARIANTPY
}

# m1: insert a missing labeled unit at its canonical position.
m1_insert_missing_labeled() {
    local log; log=$(_merge_fixture m1 "drop-group|||Scope")
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    if ! grep -q '^> Scope: an entry records changes to this wiki, and only those\. Name the files$' "$log"; then
        log "    [missing inserted Scope group]"; ok=false
    fi
    # Scope sits between Repair and Body, its canonical position.
    python3 - "$log" <<'PY' || ok=false
import sys, pathlib
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
pos = {ln.split(':',1)[0]: n for n, ln in enumerate(lines) if ln.startswith('> ') and ':' in ln}
if not (pos['> Repair'] < pos['> Scope'] < pos['> Body']):
    print(f"    [Scope not at canonical position: {pos}]", file=sys.stderr)
    sys.exit(1)
PY
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    $ok
}

# m2: refresh a drifted labeled unit in place.
m2_refresh_drifted_labeled() {
    local log; log=$(_merge_fixture m2 \
        "reword-group|||Entries|||every operation that creates or updates wiki files appends one entry.")
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    grep -q '^> Entries: an operation that creates or updates wiki files appends one entry; an$' "$log" \
        || { log "    [Entries not refreshed to template text]"; ok=false; }
    if grep -q '^> Entries: every operation that creates' "$log"; then
        log "    [stale Entries wording survives]"; ok=false
    fi
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    $ok
}

# m3: refresh a drifted unlabeled unit through its committed stem.
m3_refresh_drifted_unlabeled() {
    local log; log=$(_merge_fixture m3 \
        "reword-line|||Chronological record|||Chronological record of changes to this wiki.")
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    grep -q '^> Chronological record of wiki changes\. Append-only\.$' "$log" \
        || { log "    [unlabeled opener not refreshed]"; ok=false; }
    if grep -q '^> Chronological record of changes to this wiki\.$' "$log"; then
        log "    [stale unlabeled wording survives]"; ok=false
    fi
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    $ok
}

# m4: a prior alias recorded in the identity table refreshes the renamed unit
# through the CLI without leaving a duplicate. The fixture ships the rename the
# way a template edit would: the current anchor becomes `Logformat:`, the old
# `Format:` is recorded as the alias, and the downstream wiki still carries the
# old form. The alias must be a single-token label, because LABEL_RE only
# treats `> Label:` as a unit boundary; `> Log format:` would be absorbed into
# the preceding unit and the test would pass for the wrong reason.
m4_refresh_through_alias() {
    local home; home=$(fresh_scratch m4)
    cp -R "$WIKI_SKILL" "$home/skill"
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    cp "$log" "$log.before"
    local ok=true
    if ! python3 - "$home/skill" "$log" <<'ALIASPY'
import pathlib
import sys

skill = pathlib.Path(sys.argv[1])
log = pathlib.Path(sys.argv[2])

template_path = skill / "references/template_log.md"
template_path.write_text(
    template_path.read_text().replace("> Format:", "> Logformat:", 1)
)
script_path = skill / "scripts/merge_log_preamble.py"
script = script_path.read_text()
old = 'CanonicalUnit("format", "labeled", "Format:")'
new = 'CanonicalUnit("format", "labeled", "Logformat:", ("Format:",))'
if old not in script:
    print(f"    [fixture error: identity table entry not found: {old}]", file=sys.stderr)
    sys.exit(1)
script_path.write_text(script.replace(old, new, 1))

# Prove the live unit resolves to `format` through the alias before merging.
sys.path.insert(0, str(skill / "scripts"))
import merge_log_preamble as m

live = m.extract_h1_prelude(log.read_text())
_, units = m._parse_region(live, m.CANONICAL_UNITS)
format_units = [u for u in units if m._resolve(u, m.CANONICAL_UNITS) == "format"]
if len(format_units) != 1:
    print(f"    [live preamble has {len(format_units)} format units]", file=sys.stderr)
    sys.exit(1)
if not format_units[0][0].startswith("> Format:"):
    print(f"    [live format unit does not carry the alias: {format_units[0][0]!r}]", file=sys.stderr)
    sys.exit(1)
print("alias resolution OK")
ALIASPY
    then
        ok=false
    fi

    local out rc
    out=$(python3 "$home/skill/scripts/merge_log_preamble.py" "$log" 2>&1) && rc=0 || rc=$?
    assert_eq "exit" "$rc" "0" || ok=false
    local logformat_count format_count
    logformat_count=$(grep -c '^> Logformat:' "$log" || true)
    format_count=$(grep -c '^> Format:' "$log" || true)
    assert_eq "one current-anchor unit" "$logformat_count" "1" || ok=false
    assert_eq "no stale alias unit" "$format_count" "0" || ok=false
    _merge_invariants "$log.before" "$log" "$home/skill/references/template_log.md" "Format:" >/dev/null || ok=false
    $ok
}

# m5: owner-line preservation holds across every distribution fixture.
_merge_owner_matrix_case() {
    local id=$1
    shift
    local log; log=$(_merge_fixture "$id" "$@" \
        "add-owner|||Local: this vault names the tenant alongside every rollout entry.")
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*}
    if [[ "$rc" -ne 0 ]]; then
        log "    [$id merge exited $rc]"
        printf '%s\n' "${ret#*|}" | indent
        return 1
    fi
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null
}

m5_owner_preservation_invariant() {
    local ok=true
    _merge_owner_matrix_case m5a "drop-group|||Scope" || ok=false
    _merge_owner_matrix_case m5b \
        "reword-group|||Entries|||every operation that creates or updates wiki files appends one entry." \
        || ok=false
    _merge_owner_matrix_case m5c \
        "reword-line|||Chronological record|||Chronological record of changes to this wiki." \
        || ok=false
    _merge_owner_matrix_case m5d "drop-line|||When this file exceeds" || ok=false
    $ok
}

# m6: a missing canonical unit plus an owner line that closely resembles it is
# refused loudly, and nothing is written.
m6_ambiguous_near_match_refused() {
    local home; home=$(fresh_scratch m6)
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    python3 - "$log" "$TEMPLATE_LOG" "$WIKI_SKILL/scripts" <<'AMBIGPY'
import pathlib
import sys

log, template, scripts = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]
sys.path.insert(0, scripts)
import merge_log_preamble as m

template_units = m.validate_template(
    m.extract_h1_prelude(template.read_text()), m.CANONICAL_UNITS
)
scope = next(
    u for s, u in zip(m.CANONICAL_UNITS, template_units) if s.id == "scope"
)
body = " ".join(line[2:] if line.startswith("> ") else line for line in scope)

text = template.read_text()
i = text.find("\n## ")
out = []
skip = False
for line in text[:i].splitlines():
    if line.startswith("> Scope:"):
        skip = True
        continue
    if skip and line.startswith("> ") and not m.LABEL_RE.match(line) \
            and not line.startswith("> When this file exceeds"):
        continue
    skip = False
    out.append(line)
out.append("> Local: " + body)
pathlib.Path(log).write_text("\n".join(out) + text[i:])
AMBIGPY
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    if ! cmp -s "$log" "$log.before"; then
        log "    [file changed on an ambiguous local rewrite]"; ok=false
    fi
    if ! grep -q "ambiguous local rewrite" <<<"$out" || ! grep -q "scope" <<<"$out"; then
        log "    [refusal did not name the ambiguous unit]"; ok=false
        printf '%s\n' "$out" | indent
    fi
    $ok
}

# m7: a duplicated canonical unit is refused loudly, and nothing is written.
m7_duplicate_unit_refused() {
    local home; home=$(fresh_scratch m7)
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    python3 - "$log" <<'DUPPY'
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
lines = p.read_text().splitlines()
out = []
for line in lines:
    if line.startswith("> Repair:"):
        out.append("> Entries: a stale duplicate entry rule.")
    out.append(line)
p.write_text("\n".join(out) + "\n")
DUPPY
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    if ! cmp -s "$log" "$log.before"; then
        log "    [file changed on a duplicate canonical unit]"; ok=false
    fi
    if ! grep -q "duplicate canonical unit 'entries'" <<<"$out"; then
        log "    [refusal did not name the duplicated unit]"; ok=false
        printf '%s\n' "$out" | indent
    fi
    $ok
}

# m8: a template region the parse validation rejects fails loudly and writes
# nothing. The copied skill tree lets the script resolve a deliberately broken
# template beside itself, exactly as a bad in-repo edit would.
m8_table_rejecting_template_refused() {
    local home; home=$(fresh_scratch m8)
    cp -R "$WIKI_SKILL" "$home/skill"
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    python3 - "$home/skill/references/template_log.md" <<'BADTPL'
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("> Format:", "> Log format:", 1))
BADTPL
    cp "$log" "$log.before"
    local out rc
    out=$(python3 "$home/skill/scripts/merge_log_preamble.py" "$log" 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    if ! cmp -s "$log" "$log.before"; then
        log "    [file changed on a rejected template]"; ok=false
    fi
    if ! grep -qE "resolves to no identity entry|template carries|template unit order" <<<"$out"; then
        log "    [rejection did not name the template/table mismatch]"; ok=false
        printf '%s\n' "$out" | indent
    fi
    $ok
}

# m9: a second run over the converged file reports no change and exits 0.
m9_idempotent() {
    local log; log=$(_merge_fixture m9 "drop-group|||Scope")
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*}
    local ok=true
    assert_eq "first exit" "$rc" "0" || ok=false
    cp "$log" "$log.after-first"
    ret=$(run_merge "$log"); rc=${ret%%|*} local out=${ret#*|}
    assert_eq "second exit" "$rc" "0" || ok=false
    if ! grep -q "no change" <<<"$out"; then
        log "    [second run did not report no change]"; ok=false
        printf '%s\n' "$out" | indent
    fi
    if ! cmp -s "$log" "$log.after-first"; then
        log "    [second run changed the converged file]"; ok=false
    fi
    $ok
}

# m10: entries below the preamble stay byte-identical, including a distinctive
# entry body that a region restore would have to preserve exactly.
m10_entries_byte_identical() {
    local home; home=$(fresh_scratch m10)
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    cat >> "$log" <<'ENTRIES'

## [2026-07-01 12:00] update | KEEP ENTRY A

- concepts/alpha.md: KEEP BULLET A

## [2026-07-02 13:00] query | KEEP ENTRY B

- KEEP BULLET B
ENTRIES
    _merge_preamble "$log" "$TEMPLATE_LOG" "drop-group|||Scope"
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    if ! grep -q 'KEEP ENTRY A' "$log" || ! grep -q 'KEEP BULLET B' "$log"; then
        log "    [entry content lost]"; ok=false
    fi
    $ok
}

# m11: a live restore-instructing boilerplate warn plus an unmatched owner
# line: the script preserves the owner line through the unmatched-owner path
# and the lint warn clears (the owner line becomes an acknowledged insert-only
# extension, not a live warn).
m11_live_warn_owner_preserved() {
    local wiki; wiki=$(stage_fresh_wiki m11)
    local log="$wiki/log.md"
    _merge_preamble "$log" "$TEMPLATE_LOG" \
        "drop-group|||Scope" \
        "add-owner|||Local: this vault names the tenant alongside every rollout entry."
    local ret; ret=$(run_lint "$wiki"); local out=${ret#*|}
    local ok=true
    assert_lint_finding "live boilerplate warn before merge" "$out" warn "boilerplate" || ok=false
    cp "$log" "$log.before"
    ret=$(run_merge "$log"); local rc=${ret%%|*}
    assert_eq "merge exit" "$rc" "0" || ok=false
    grep -q '^> Local: this vault names the tenant alongside every rollout entry\.$' "$log" \
        || { log "    [owner line not preserved]"; ok=false; }
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_lint_category "no live boilerplate warn after merge" "$out" "boilerplate" || ok=false
    $ok
}

# m12: the merge script imports the linter's region extractor, so both share
# one definition of the preamble.
m12_shares_extractor() {
    local ok=true
    if ! grep -q 'from lint import extract_h1_prelude' "$MERGE"; then
        log "    [merge script does not import extract_h1_prelude from lint]"; ok=false
    fi
    if ! grep -q 'extract_h1_prelude(' "$MERGE"; then
        log "    [merge script does not call extract_h1_prelude]"; ok=false
    fi
    $ok
}

# m13: validate_template rejects a template whose current anchor is absent even
# when the missing anchor is recorded as an alias. Aliases exist for live units
# a rename left behind; the canonical template must carry current anchors only.
m13_template_alias_drift_rejected() {
    python3 - "$WIKI_SKILL/scripts" "$TEMPLATE_LOG" <<'ALIASDRIFTPY'
import pathlib
import sys

sys.path.insert(0, sys.argv[1])
import merge_log_preamble as m

specs = tuple(
    m.CanonicalUnit(s.id, s.kind, s.anchor, s.aliases + ("Logformat:",))
    if s.id == "format"
    else s
    for s in m.CANONICAL_UNITS
)
drifted = pathlib.Path(sys.argv[2]).read_text().replace(
    "> Format:", "> Logformat:", 1
)
try:
    m.validate_template(m.extract_h1_prelude(drifted), specs)
except m.MergeError as exc:
    print(f"template alias drift rejected: {exc}")
    raise SystemExit(0)
print(
    "    [validate_template accepted a template whose current anchor is absent]",
    file=sys.stderr,
)
raise SystemExit(1)
ALIASDRIFTPY
}

# m14: owner content the parser could absorb into a canonical unit survives.
# Each case drops a canonical unit so the merge must rewrite the region, then
# places owner content where a continuation-absorbing parser would lose it: a
# plain blockquote line at the end, blank-separated, a plain paragraph at the
# end (with and without a blank line), and a plain line after the opener. The
# invariant is asserted by a line-level diff against the template, not through
# the script's parser.
_merge_absorbed_owner_case() {
    local id=$1
    shift
    local log; log=$(_merge_fixture "$id" "$@")
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*}
    if [[ "$rc" -ne 0 ]]; then
        log "    [$id merge exited $rc]"
        printf '%s\n' "${ret#*|}" | indent
        return 1
    fi
    if ! grep -qF 'Our wiki keeps tenant names in entries.' "$log"; then
        log "    [$id owner line was absorbed and replaced]"
        return 1
    fi
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null
}

m14_absorbed_owner_lines_preserved() {
    local ok=true
    _merge_absorbed_owner_case m14a \
        "drop-group|||Scope" \
        "add-owner|||Our wiki keeps tenant names in entries." || ok=false
    _merge_absorbed_owner_case m14b \
        "drop-group|||Scope" \
        "add-blank-owner-after|||> When this file exceeds|||Our wiki keeps tenant names in entries." || ok=false
    _merge_absorbed_owner_case m14c \
        "drop-group|||Scope" \
        "add-plain|||Our wiki keeps tenant names in entries." || ok=false
    _merge_absorbed_owner_case m14d \
        "drop-group|||Scope" \
        "add-blank-plain-after|||> When this file exceeds|||Our wiki keeps tenant names in entries." || ok=false
    _merge_absorbed_owner_case m14e \
        "drop-group|||Scope" \
        "add-plain-after|||> Chronological record|||Our wiki keeps tenant names in entries." || ok=false
    $ok
}

# m15: the live-warn variant of m14 — a live restore-instructing boilerplate
# warn plus an owner blockquote line that a continuation-absorbing parser
# would swallow. The merge preserves it and the live warn clears.
m15_absorbed_owner_live_warn() {
    local wiki; wiki=$(stage_fresh_wiki m15)
    local log="$wiki/log.md"
    _merge_preamble "$log" "$TEMPLATE_LOG" \
        "drop-group|||Scope" \
        "add-owner|||Our wiki keeps tenant names in entries."
    local ret; ret=$(run_lint "$wiki"); local out=${ret#*|}
    local ok=true
    assert_lint_finding "live boilerplate warn before merge" "$out" warn "boilerplate" || ok=false
    cp "$log" "$log.before"
    ret=$(run_merge "$log"); local rc=${ret%%|*}
    assert_eq "merge exit" "$rc" "0" || ok=false
    grep -qF '> Our wiki keeps tenant names in entries.' "$log" \
        || { log "    [owner blockquote line not preserved]"; ok=false; }
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_lint_category "no live boilerplate warn after merge" "$out" "boilerplate" || ok=false
    $ok
}

# _replace_unit <log> <anchor-prefix> <replacement-file>
# Replace the preamble unit whose first line starts with <anchor-prefix> with
# the lines in <replacement-file>, leaving everything below the preamble and
# every other unit untouched. Continuation lines are blockquote lines that
# carry no label anchor.
_replace_unit() {
    python3 - "$1" "$2" "$3" <<'REPLACEUNITPY'
import pathlib
import re
import sys

log, prefix, replacement = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
LABEL_RE = re.compile(r"^> ([A-Z][A-Za-z0-9_-]*): ")

text = pathlib.Path(log).read_text()
i = text.find("\n## ")
pre, tail = text[:i], text[i:]
out: list[str] = []
skip = False
for line in pre.splitlines():
    if line.startswith(prefix):
        skip = True
        out.extend(replacement.read_text().splitlines())
        continue
    if skip:
        if line.startswith("> ") and not LABEL_RE.match(line):
            continue
        skip = False
    out.append(line)
pathlib.Path(log).write_text("\n".join(out) + "\n" + tail)
REPLACEUNITPY
}

# m16: a drifted labeled unit that grew past the template's line count is
# canonical drift, not owner content. The whole unit refreshes, so no stale
# canonical tail survives beside the current rule.
m16_grown_drifted_labeled() {
    local home; home=$(fresh_scratch m16)
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    cat > "$home/drifted" <<'DRIFT'
> Entries: each operation that writes wiki files records exactly one entry here;
> a run that writes nothing records none, except that lint and audit runs always
> record their outcome. That includes a zero-change audit, which is still a
> process record worth keeping for the next cold walk. Owners also keep this
> older sentence about how entries were once scoped to a single file, which the
> template no longer says anywhere.
DRIFT
    _replace_unit "$log" "> Entries:" "$home/drifted"
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    local count
    count=$(grep -c '^> Entries: an operation that creates or updates wiki files appends one entry; an$' "$log" || true)
    assert_eq "one current Entries block" "$count" "1" || ok=false
    if grep -q 'older sentence about how entries were once scoped' "$log"; then
        log "    [stale drifted Entries wording survives]"; ok=false
    fi
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    $ok
}

# m17: the same defect for an unlabeled unit: a drifted rotation rule that grew
# past the template's one line refreshes whole, leaving no stale tail.
m17_grown_drifted_unlabeled() {
    local home; home=$(fresh_scratch m17)
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    cat > "$home/drifted" <<'DRIFT'
> When this file exceeds 500 entries, rotate: rename the log and start fresh.
> The old rule also said to keep an archive copy beside the log, which the
> current template no longer asks for and downstream wikis copied verbatim.
DRIFT
    _replace_unit "$log" "> When this file exceeds" "$home/drifted"
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    local count
    count=$(grep -c '^> When this file exceeds 500 entries, rotate: rename to log-YYYY.md' "$log" || true)
    assert_eq "one current rotation block" "$count" "1" || ok=false
    if grep -q 'keep an archive copy beside the log' "$log"; then
        log "    [stale drifted rotation wording survives]"; ok=false
    fi
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    $ok
}

# m18: an owner blockquote line inserted inside a canonical unit survives
# byte-identically. The line-count split used to fold it into the refreshed
# prefix and delete it; the line alignment must keep it.
m18_mid_unit_owner_line_survives() {
    local log; log=$(_merge_fixture m18 \
        "insert-in-group|||Body|||> Tenant names appear in entries.")
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    grep -qxF '> Tenant names appear in entries.' "$log" \
        || { log "    [mid-unit owner line was deleted]"; ok=false; }
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    # A second run must leave the preserved line in place (idempotence).
    cp "$log" "$log.after-first"
    ret=$(run_merge "$log"); rc=${ret%%|*}
    assert_eq "second exit" "$rc" "0" || ok=false
    if ! cmp -s "$log" "$log.after-first"; then
        log "    [second run changed the preserved owner line]"; ok=false
    fi
    $ok
}

# m19: drift that both rewords canonical text and adds lines is undecidable —
# the extra lines could be owner content or stale canonical wording — so the
# merge refuses loudly, names the unit, and writes nothing.
m19_mixed_drift_refused() {
    local home; home=$(fresh_scratch m19)
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    cat > "$home/drifted" <<'DRIFT'
> Entries: each operation that writes wiki files records one entry; an
> operation that changes no file appends none. Lint and audit runs are the
> exception. Each records its outcome, including a zero-change one, as a
> process record.
> Owners keep this extra line about tenants.
DRIFT
    _replace_unit "$log" "> Entries:" "$home/drifted"
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    if ! cmp -s "$log" "$log.before"; then
        log "    [file changed on undecidable mixed drift]"; ok=false
    fi
    if ! grep -q "undecidable drift in canonical unit 'entries'" <<<"$out"; then
        log "    [refusal did not name the undecidable unit]"; ok=false
        printf '%s\n' "$out" | indent
    fi
    $ok
}

# m20: a mid-unit owner line keeps its offset, not just its bytes. The merge
# rewrites the region (Scope is dropped), and the owner line inserted between
# two canonical Body lines must stay between those same two lines rather than
# being relocated to the end of the unit.
m20_mid_unit_owner_line_keeps_offset() {
    local log; log=$(_merge_fixture m20 \
        "drop-group|||Scope" \
        "insert-in-group|||Body|||> Tenant names appear in entries.")
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    python3 - "$log" <<'POSITIONPY' || ok=false
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
try:
    at = lines.index("> Tenant names appear in entries.")
except ValueError:
    print("    [mid-unit owner line was deleted]", file=sys.stderr)
    raise SystemExit(1)
before = lines[at - 1]
after = lines[at + 1]
if not before.startswith(
    "> Body: list only files actually created or updated. Skip files that were"
):
    print(f"    [owner line moved; preceding line is {before!r}]", file=sys.stderr)
    raise SystemExit(1)
if not after.startswith(
    "> inspected, considered, or deliberately left unchanged, and do not narrate"
):
    print(f"    [owner line moved; following line is {after!r}]", file=sys.stderr)
    raise SystemExit(1)
POSITIONPY
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    $ok
}

# m21: a mid-unit owner line that precedes a later unmatched owner unit. The
# self-check walks owner units with one forward cursor, so building the list as
# "all unmatched units, then all mid-unit extras" reports the mid-unit line as
# missing even though the merge emitted it in place. Both lines must survive.
m21_mid_unit_before_later_owner_unit() {
    local log; log=$(_merge_fixture m21 \
        "insert-in-group|||Body|||> Tenant names appear in entries." \
        "add-owner|||Local: this vault names the tenant alongside every rollout entry.")
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    if ! grep -qxF '> Tenant names appear in entries.' "$log"; then
        log "    [mid-unit owner line was deleted]"; ok=false
    fi
    if ! grep -qxF '> Local: this vault names the tenant alongside every rollout entry.' "$log"; then
        log "    [later owner unit was deleted]"; ok=false
    fi
    python3 - "$log" <<'ORDERPY' || ok=false
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
try:
    mid = lines.index("> Tenant names appear in entries.")
    later = lines.index(
        "> Local: this vault names the tenant alongside every rollout entry."
    )
except ValueError:
    raise SystemExit(1)
if mid >= later:
    print("    [owner lines are out of order]", file=sys.stderr)
    raise SystemExit(1)
ORDERPY
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    $ok
}

# m22: a log.md that begins directly with its first entry carries no preamble
# at all — exactly the hand-written log whose missing preamble makes lint warn.
# The merge must emit the canonical H1 block and keep the entry's heading as a
# heading, separated from the region by the blank line the template carries,
# rather than appending the region to the heading.
m22_empty_preamble_emits_header() {
    local home; home=$(fresh_scratch m22)
    local log="$home/log.md"
    printf '## [2026-01-01 00:00] create | Wiki initialized\n\n- Domain: x\n' > "$log"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    if [[ "$(head -n 1 "$log")" != "# Wiki Log" ]]; then
        log "    [canonical H1 header not emitted]"; ok=false
    fi
    python3 - "$log" "$TEMPLATE_LOG" <<'EMPTYPREAMBLEPY' || ok=false
import pathlib
import sys

log = pathlib.Path(sys.argv[1]).read_text()
template = pathlib.Path(sys.argv[2]).read_text()
heading = "## [2026-01-01 00:00] create | Wiki initialized"

def prelude(text):
    i = text.find("\n## ")
    return text[:i] if i != -1 else text

lines = log.splitlines()
try:
    at = lines.index(heading)
except ValueError:
    print("    [first entry heading was destroyed]", file=sys.stderr)
    raise SystemExit(1)
if at == 0 or lines[at - 1] != "":
    print("    [entry heading is not blank-line separated from the region]", file=sys.stderr)
    raise SystemExit(1)
if prelude(log) != prelude(template):
    print("    [canonical preamble did not land]", file=sys.stderr)
    raise SystemExit(1)
if not log.endswith("- Domain: x\n"):
    print("    [entry content below the preamble was lost]", file=sys.stderr)
    raise SystemExit(1)
EMPTYPREAMBLEPY
    # A second run is a no-op on the converged file.
    cp "$log" "$log.after-first"
    ret=$(run_merge "$log"); rc=${ret%%|*} out=${ret#*|}
    assert_eq "second exit" "$rc" "0" || ok=false
    if ! grep -q "no change" <<<"$out"; then
        log "    [second run did not report no change]"; ok=false
    fi
    if ! cmp -s "$log" "$log.after-first"; then
        log "    [second run changed the converged file]"; ok=false
    fi
    $ok
}

# m23: a preamble whose only drift is its H1 block converges to the template
# header instead of merging to itself and reporting `no change`. Both drift
# shapes are exercised at once: a reworded H1 and the missing blank line
# beneath it. A second run must report `no change` and leave the file alone.
m23_header_drift_converges() {
    local home; home=$(fresh_scratch m23)
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    python3 - "$log" <<'HEADERDRIFTPY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
if lines[0] != "# Wiki Log" or lines[1] != "":
    raise SystemExit("fixture error: template H1 block is not as expected")
lines[0] = "# Vault Change Log"
del lines[1]
path.write_text("\n".join(lines) + "\n")
HEADERDRIFTPY
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    if ! grep -q "converged" <<<"$out"; then
        log "    [first run did not report convergence]"; ok=false
    fi
    if [[ "$(head -n 1 "$log")" != "# Wiki Log" ]]; then
        log "    [reworded H1 did not converge to the template]"; ok=false
    fi
    if [[ "$(sed -n 2p "$log")" != "" ]]; then
        log "    [blank line under the H1 was not restored]"; ok=false
    fi
    python3 - "$log" "$TEMPLATE_LOG" <<'HEADERPRELUDEY' || ok=false
import pathlib
import sys

log = pathlib.Path(sys.argv[1]).read_text()
template = pathlib.Path(sys.argv[2]).read_text()

def prelude(text):
    i = text.find("\n## ")
    return text[:i] if i != -1 else text

if prelude(log) != prelude(template):
    print("    [preamble did not converge to the template]", file=sys.stderr)
    raise SystemExit(1)
HEADERPRELUDEY
    cp "$log" "$log.after-first"
    ret=$(run_merge "$log"); rc=${ret%%|*} out=${ret#*|}
    assert_eq "second exit" "$rc" "0" || ok=false
    if ! grep -q "no change" <<<"$out"; then
        log "    [second run did not report no change]"; ok=false
    fi
    if ! cmp -s "$log" "$log.after-first"; then
        log "    [second run changed the converged file]"; ok=false
    fi
    $ok
}

# m24: a live `# ` header line beyond the canonical H1 is owner content. The
# merge takes the H1 and the blank line beneath it from the template and keeps
# the owner heading byte-identically, so it survives a converging run and a
# second run is a no-op.
m24_owner_header_line_survives() {
    local log; log=$(_merge_fixture m24 \
        "reword-group|||Actions|||ingest, update, query, lint, create, archive, delete, audit, import, session-wrapup, rotate, publish")
    python3 - "$log" <<'OWNERHEADERPY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
if lines[0] != "# Wiki Log" or lines[1] != "":
    raise SystemExit("fixture error: template H1 block is not as expected")
lines[2:2] = ["# Appendix", ""]
path.write_text("\n".join(lines) + "\n")
OWNERHEADERPY
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    if ! grep -qxF '# Appendix' "$log"; then
        log "    [owner header line was deleted]"; ok=false
    fi
    if [[ "$(head -n 1 "$log")" != "# Wiki Log" ]]; then
        log "    [canonical H1 is not first]"; ok=false
    fi
    if ! grep -q '^> Actions: ingest, update, query, lint, create, archive, delete, audit, import, session-wrapup, rotate$' "$log"; then
        log "    [drifted Actions unit did not converge]"; ok=false
    fi
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    cp "$log" "$log.after-first"
    ret=$(run_merge "$log"); rc=${ret%%|*} out=${ret#*|}
    assert_eq "second exit" "$rc" "0" || ok=false
    if ! grep -q "no change" <<<"$out"; then
        log "    [second run did not report no change]"; ok=false
    fi
    if ! cmp -s "$log" "$log.after-first"; then
        log "    [second run changed the preserved owner header line]"; ok=false
    fi
    $ok
}

# m25: an owner `# ` header line above the canonical H1 is owner content. The
# merge must take the H1 slot at the live line byte-equal to the canonical H1,
# not at the first live `# ` line, so the owner heading above it survives
# byte-identically in its position and the canonical H1 is never duplicated.
m25_owner_header_above_h1_survives() {
    local home; home=$(fresh_scratch m25)
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    python3 - "$log" <<'ABOVEH1PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
if lines[0] != "# Wiki Log" or lines[1] != "":
    raise SystemExit("fixture error: template H1 block is not as expected")
lines[0:0] = ["# Appendix", ""]
path.write_text("\n".join(lines) + "\n")
ABOVEH1PY
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    if ! grep -qxF '# Appendix' "$log"; then
        log "    [owner header line was deleted]"; ok=false
    fi
    python3 - "$log" <<'ABOVEH1CHECKPY' || ok=false
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
expected = ["# Appendix", "", "# Wiki Log", ""]
if lines[:4] != expected:
    print(
        f"    [owner header above the H1 was not preserved: {lines[:4]!r}]",
        file=sys.stderr,
    )
    raise SystemExit(1)
count = lines.count("# Wiki Log")
if count != 1:
    print(f"    [canonical H1 appears {count} times]", file=sys.stderr)
    raise SystemExit(1)
ABOVEH1CHECKPY
    _merge_invariants "$log.before" "$log" "$TEMPLATE_LOG" >/dev/null || ok=false
    cp "$log" "$log.after-first"
    ret=$(run_merge "$log"); rc=${ret%%|*} out=${ret#*|}
    assert_eq "second exit" "$rc" "0" || ok=false
    if ! grep -q "no change" <<<"$out"; then
        log "    [second run did not report no change]"; ok=false
    fi
    if ! cmp -s "$log" "$log.after-first"; then
        log "    [second run changed the preserved owner header line]"; ok=false
    fi
    $ok
}

# m26: an owner `# ` header line above a reworded H1 is undecidable. With no
# live line byte-equal to the canonical H1 and more than one live `# ` line,
# the merge cannot tell which heading is the H1, so it must refuse loudly with
# exit 1 and write nothing rather than delete the owner line by picking the
# first heading as the H1 slot.
m26_owner_above_reworded_h1_refused() {
    local home; home=$(fresh_scratch m26)
    local log="$home/log.md"
    cp "$TEMPLATE_LOG" "$log"
    python3 - "$log" <<'REWORDEDH1PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines()
if lines[0] != "# Wiki Log" or lines[1] != "":
    raise SystemExit("fixture error: template H1 block is not as expected")
lines[0] = "# Vault Change Log"
lines[0:0] = ["# Appendix", ""]
path.write_text("\n".join(lines) + "\n")
REWORDEDH1PY
    cp "$log" "$log.before"
    local ret; ret=$(run_merge "$log"); local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    if ! grep -q "ambiguous header" <<<"$out"; then
        log "    [refusal did not name the ambiguous header]"; ok=false
    fi
    if ! grep -qF '# Appendix' <<<"$out"; then
        log "    [refusal did not name the live '# ' lines]"; ok=false
    fi
    if ! cmp -s "$log" "$log.before"; then
        log "    [refused run still wrote to the file]"; ok=false
    fi
    $ok
}

scenario m1  "merge inserts a missing labeled unit"           m1_insert_missing_labeled
scenario m2  "merge refreshes a drifted labeled unit"        m2_refresh_drifted_labeled
scenario m3  "merge refreshes a drifted unlabeled unit"      m3_refresh_drifted_unlabeled
scenario m4  "merge refreshes through a prior alias"         m4_refresh_through_alias
scenario m5  "merge preserves owner lines across fixtures"   m5_owner_preservation_invariant
scenario m6  "merge refuses an ambiguous near-match"         m6_ambiguous_near_match_refused
scenario m7  "merge refuses a duplicate canonical unit"      m7_duplicate_unit_refused
scenario m8  "merge refuses a table-rejecting template"      m8_table_rejecting_template_refused
scenario m9  "merge is idempotent on a converged file"       m9_idempotent
scenario m10 "merge leaves entries byte-identical"           m10_entries_byte_identical
scenario m11 "merge preserves owner line on live warn"       m11_live_warn_owner_preserved
scenario m12 "merge imports the linter's prelude extractor"  m12_shares_extractor
scenario m13 "merge rejects a template drifted onto an alias" m13_template_alias_drift_rejected
scenario m14 "merge preserves absorbed owner lines"           m14_absorbed_owner_lines_preserved
scenario m15 "merge preserves absorbed owner line on warn"    m15_absorbed_owner_live_warn
scenario m16 "merge refreshes a grown drifted labeled unit"   m16_grown_drifted_labeled
scenario m17 "merge refreshes a grown drifted unlabeled unit" m17_grown_drifted_unlabeled
scenario m18 "merge keeps a mid-unit owner line"              m18_mid_unit_owner_line_survives
scenario m19 "merge refuses undecidable mixed drift"          m19_mixed_drift_refused
scenario m20 "merge keeps a mid-unit owner line's offset"     m20_mid_unit_owner_line_keeps_offset
scenario m21 "merge keeps a mid-unit line before later owner" m21_mid_unit_before_later_owner_unit
scenario m22 "merge emits the header for an empty preamble"   m22_empty_preamble_emits_header
scenario m23 "merge converges a drifted H1 block"             m23_header_drift_converges
scenario m24 "merge keeps an owner header line above the units" m24_owner_header_line_survives
scenario m25 "merge keeps an owner header line above the H1"   m25_owner_header_above_h1_survives
scenario m26 "merge refuses owner header above a reworded H1"  m26_owner_above_reworded_h1_refused

log ""
log "==================================="
log "  Layer 1: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    log "  Failed: ${FAILED_IDS[*]}"
fi
log "==================================="

exit $(( FAIL > 0 ? 1 : 0 ))
