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
    local wiki=$1
    python3 - "$wiki/SCHEMA.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
marker = "## Tag Taxonomy\n"
bullet = "\n- Domain: model, architecture, benchmark, training\n"
p.write_text(text.replace(marker, marker + bullet, 1))
PY
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

# L45: the two-field (path-only) form keys on no message, so a `size`, `log`, or
# `stale` acceptance keeps matching after that finding's volatile counter or date
# substring changes.
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
    # log: log.md past the 500-entry rotation threshold.
    append_log_entries "$wiki" 520

    set_accept_bullets "$wiki" \
        "size — concepts/widget.md" \
        "stale — concepts/gadget.md" \
        "log — log.md"
    local ret; ret=$(run_lint "$wiki")
    local out=${ret#*|}
    local ok=true
    assert_no_finding_for_file "size accepted" "$out" size "concepts/widget.md" || ok=false
    assert_no_finding_for_file "stale accepted" "$out" stale "concepts/gadget.md" || ok=false
    assert_no_lint_category "log accepted" "$out" "log" || ok=false

    # Move every volatile substring: more lines, a later `updated`, more entries.
    grow_page_past_soft_cap "$wiki/concepts/widget.md" 40
    python3 - "$wiki/concepts/gadget.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("updated: 2020-01-01", "updated: 2021-06-15"))
PY
    append_log_entries "$wiki" 30
    ret=$(run_lint "$wiki"); out=${ret#*|}
    assert_no_finding_for_file "size still accepted after line count changed" "$out" size "concepts/widget.md" || ok=false
    assert_no_finding_for_file "stale still accepted after dates changed" "$out" stale "concepts/gadget.md" || ok=false
    assert_no_lint_category "log still accepted after entry count changed" "$out" "log" || ok=false
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
scenario d22 "positional non-wiki path (AVAILABLE choice)"   d22_positional_non_wiki_path
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

scenario a1  "auto_shaper fidelity-safe token-cost contract" a1_auto_shaper_fidelity_safe_token_cost_contract
scenario a2  "wiki file-access guidance contract"          a2_wiki_file_access_contract

scenario s1  "compute_sha256 inserts missing sha line"        s1_sha256_insert_missing
scenario s2  "compute_sha256 unchanged when correct"          s2_sha256_unchanged_when_correct
scenario s3  "compute_sha256 updates on drift"                s3_sha256_update_on_drift
scenario s4  "compute_sha256 skips when no frontmatter"       s4_sha256_no_frontmatter_skip
scenario s5  "compute_sha256 --check flags drift exit 1"      s5_sha256_check_flags_drift
scenario s6  "compute_sha256 --check clean exits 0"           s6_sha256_check_clean
scenario s7  "compute_sha256 recurses into a directory"       s7_sha256_directory_recurses

log ""
log "==================================="
log "  Layer 1: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    log "  Failed: ${FAILED_IDS[*]}"
fi
log "==================================="

exit $(( FAIL > 0 ? 1 : 0 ))
