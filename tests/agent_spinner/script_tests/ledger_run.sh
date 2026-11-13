#!/usr/bin/env bash
# script_tests/ledger_run.sh - script tests for the bundled run ledger.
#
# Every scenario stages its own repository under script_tests/scratch/ and runs
# the ledger under the oldest and the newest python3 the machine offers. The
# suite keeps the bash 3.2 floor that lint-sh enforces.
#
# The no-helper scenario is the load-bearing one: a launcher installs a Python
# audit hook over every spawn surface before it runs the ledger, and the run
# fails on any spawn event whose target is neither the git wrapper nor the
# scenario's gate wrapper. A scratch copy that forks and then execs a helper
# fails the same assertion.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
LEDGER="$REPO_ROOT/plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py"
SCRATCH="$HERE/scratch"
HELPER="$SCRATCH/return_helper.py"
LAUNCHER="$SCRATCH/audit_launcher.py"

PASS=0
FAIL=0
FAILURES=""

ok() {
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$1"
}

bad() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$1"
    FAILURES="$FAILURES$1
"
}

check() {
    label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        ok "$label"
    else
        bad "$label"
    fi
}

not() {
    ! "$@"
}

# --- python discovery -------------------------------------------------------

find_pythons() {
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
            realpath "$candidate"
        fi
    done | sort -u
}

python_version() {
    "$1" -c 'import sys; sys.stdout.write("%d.%d.%d" % sys.version_info[:3])'
}

# Prints "version path" lines, oldest first, one per distinct version.
python_versions() {
    find_pythons | while IFS= read -r candidate; do
        version="$(python_version "$candidate" 2>/dev/null)" || continue
        printf '%s %s\n' "$version" "$candidate"
    done | sort -t. -k1,1n -k2,2n -k3,3n | awk '!seen[$1]++'
}

# --- shared staging ---------------------------------------------------------

setup_repo() {
    dir="$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "ledger@example.invalid"
    git -C "$dir" config user.name "Ledger Tests"
    printf 'alpha\nbeta\n' > "$dir/a.txt"
    printf 'gamma\n' > "$dir/b.txt"
    printf '# Notes\n' > "$dir/NOTES.md"
    printf '*.log\n' > "$dir/.gitignore"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "initial"
}

setup_plain() {
    dir="$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    printf 'alpha\n' > "$dir/a.txt"
    printf 'beta\n' > "$dir/b.txt"
}

ledger() {
    dir="$1"
    shift
    ( cd "$dir" && "$PY" -B "$LEDGER" "$@" )
}

ledger_has() {
    d="$1"
    shift
    icase=""
    if [ "$1" = "-i" ]; then
        icase="-i"
        shift
    fi
    pat="$1"
    shift
    out=$(ledger "$d" "$@" 2>&1)
    printf '%s' "$out" | grep -q $icase "$pat"
}

token_of() {
    dir="$1"
    label="$2"
    tail -1 "$dir/.agent_spinner/briefs/$label.txt"
}

emit_return() {
    dir="$1"
    label="$2"
    token="$3"
    spec="${4:-}"
    "$PY" "$HELPER" "$dir/.agent_spinner/returns/$label.md" "$label" "$token" "$spec"
}

write_helper_files() {
    mkdir -p "$SCRATCH"
    cat > "$HELPER" <<'PY'
import json
import sys

out, label, token = sys.argv[1:4]
spec = json.loads(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else {}
data = {
    "label": label,
    "brief": token,
    "status": "done",
    "verdict": "pass",
    "examined": [],
    "checklist": [],
    "findings": [],
    "forks": [],
    "objections": [],
    "beyond_brief": [],
    "incidents": [],
    "own_authority": [],
    "alternatives": [],
    "brief_corrections": [],
    "dropped_suspicions": [],
    "notes": "",
}
data.update(spec)
text = "Return for %s.\n\n```json\n%s\n```\n\nEND %s\n" % (
    label,
    json.dumps(data),
    label,
)
with open(out, "w") as fh:
    fh.write(text)
PY
    cat > "$LAUNCHER" <<'PY'
import json
import os
import runpy
import shutil
import sys

ledger_path = sys.argv[1]
log_path = sys.argv[2]
ledger_args = sys.argv[3:]
events = []


def resolve(target):
    if not target:
        return ""
    if os.path.isabs(target):
        return os.path.realpath(target)
    found = shutil.which(target)
    return os.path.realpath(found) if found else ""


def hook(event, args):
    if event == "subprocess.Popen":
        executable = args[0] if args else None
        argv = args[1] if len(args) > 1 else None
        target = executable or (argv[0] if argv else "")
        events.append({"event": event, "target": resolve(target)})
    elif event == "os.exec":
        events.append({"event": event, "target": resolve(args[0] if args else "")})
    elif event == "os.system":
        command = args[0] if args else ""
        first = command.split()[0] if command.split() else ""
        events.append({"event": event, "target": resolve(first)})
    elif event == "os.posix_spawn":
        events.append({"event": event, "target": resolve(args[0] if args else "")})
    elif event == "os.spawn":
        events.append({"event": event, "target": resolve(args[1] if len(args) > 1 else "")})
    elif event == "os.fork":
        events.append({"event": event, "target": ""})


sys.addaudithook(hook)
sys.argv = ["run_ledger.py"] + ledger_args
try:
    runpy.run_path(ledger_path, run_name="__main__")
except SystemExit:
    pass
finally:
    existing = []
    if os.path.exists(log_path):
        try:
            existing = json.load(open(log_path))
        except ValueError:
            existing = []
    existing.extend(events)
    with open(log_path, "w") as fh:
        fh.write(json.dumps(existing))
PY
}

# run_audited <dir> <ledger> <log> <allowed-json> -- args...
run_audited() {
    dir="$1"
    script="$2"
    log="$3"
    allowed="$4"
    shift 4
    ( cd "$dir" && "$PY" -B "$LAUNCHER" "$script" "$log" "$@" )
    "$PY" - "$log" "$allowed" <<'PY'
import json
import sys

log, allowed_json = sys.argv[1:3]
allowed = set(json.loads(allowed_json))
events = json.load(open(log)) if __import__("os").path.exists(log) else []
bad = [e for e in events if e.get("target") not in allowed]
if bad:
    sys.stderr.write("disallowed spawn events: %s\n" % json.dumps(bad))
    raise SystemExit(1)
PY
}

# --- scenarios --------------------------------------------------------------

scenario_help() {
    dir="$1"
    setup_repo "$dir"
    out="$dir/help.txt"
    if ledger "$dir" --help > "$out" 2>&1; then ok "help exits 0"; else bad "help exits 0"; fi
    for verb in init attach brief dispatch accept rows dispose diff gate snapshot status show search stop close; do
        if grep -Eq "^    $verb( |$)" "$out"; then
            ok "help lists $verb"
        else
            bad "help lists $verb"
        fi
        if ledger "$dir" "$verb" --help >/dev/null 2>&1; then
            ok "$verb --help exits 0"
        else
            bad "$verb --help exits 0"
        fi
    done
    frozen="init attach brief dispatch accept rows dispose diff gate snapshot status show search stop close"
    listed=$(grep -E '^    [a-z][a-z-]*( |$)' "$out" | awk '{print $1}' | sort | tr '\n' ' ')
    expected=$(for verb in $frozen; do printf '%s\n' "$verb"; done | sort | tr '\n' ' ')
    if [ "$listed" = "$expected" ]; then
        ok "help lists exactly the frozen verb set"
    else
        bad "help lists exactly the frozen verb set (got: $listed)"
    fi
    if ledger "$dir" no-such-verb >/dev/null 2>&1; then
        bad "unknown verb exits non-zero"
    else
        ok "unknown verb exits non-zero"
    fi
    if ledger "$dir" status --help > "$dir/status-help.txt" 2>&1 && grep -q 'blind rows' "$dir/status-help.txt"; then
        ok "status --help names the blind rows listing"
    else
        bad "status --help names the blind rows listing"
    fi
}

scenario_slugs() {
    dir="$1"
    setup_repo "$dir"
    if ledger "$dir" init --unit "produce:" >/dev/null 2>&1; then bad "blank slug refused"; else ok "blank slug refused"; fi
    if ledger "$dir" init --unit "produce:x" --unit "produce:x" >/dev/null 2>&1; then bad "duplicate slug refused"; else ok "duplicate slug refused"; fi
    if ledger "$dir" init --unit "produce:X" --unit "produce:x" >/dev/null 2>&1; then bad "case-colliding slug refused"; else ok "case-colliding slug refused"; fi
    if ledger "$dir" init --unit "produce:x" --unit "check:y" >/dev/null 2>&1; then ok "distinct labels accepted"; else bad "distinct labels accepted"; fi
    if ledger "$dir" init --unit "produce:y" >/dev/null 2>&1; then bad "open run refused"; else ok "open run refused"; fi
    if ledger_has "$dir" -i 'attach' init --unit "produce:y"; then ok "open-run refusal names attach"; else bad "open-run refusal names attach"; fi
}

scenario_probe() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --probe --cheapest cheap --role r1 --role r2 >/dev/null 2>&1
    briefs=$(find "$dir/.agent_spinner/briefs" -type f 2>/dev/null | wc -l | tr -d ' ')
    rows=$(grep -c . "$dir/.agent_spinner/roster.tsv" 2>/dev/null || true)
    check "probe renders three briefs" test "$briefs" = 3
    check "probe writes three rows" test "$rows" = 3
    check "probe opens no run" test ! -f "$dir/.agent_spinner/run.json"
    if ledger_has "$dir" -i 'init' dispatch probe:cheap; then ok "probe dispatch before init names init"; else bad "probe dispatch before init names init"; fi

    token=$(token_of "$dir" probe:cheap)
    emit_return "$dir" probe:cheap "$token" '{"capabilities":{"delegation_surface":"established","concurrency":"unverified"}}'
    touch "$dir/.agent_spinner/returns/probe:cheap.start"
    ledger "$dir" accept --probe probe:cheap >/dev/null 2>&1
    if grep -q '"read_only": "not-enforced"' "$dir/.agent_spinner/probe.json"; then ok "probe read-only lever not enforced when a file was left"; else bad "probe read-only lever not enforced when a file was left"; fi

    rm -f "$dir/.agent_spinner/returns/probe:cheap.start"
    emit_return "$dir" probe:cheap "$token" '{"capabilities":{"delegation_surface":"established","concurrency":"unverified"}}'
    ledger "$dir" accept --probe probe:cheap >/dev/null 2>&1
    if grep -q '"read_only": "enforced"' "$dir/.agent_spinner/probe.json"; then ok "probe read-only lever enforced when no file was left"; else bad "probe read-only lever enforced when no file was left"; fi

    ledger "$dir" accept --probe probe:cheap --observed-model M --observed-effort E >/dev/null 2>&1
    if grep -q '"model": "observed"' "$dir/.agent_spinner/probe.json" && grep -q '"depth": "observed"' "$dir/.agent_spinner/probe.json"; then ok "probe records observed model and depth"; else bad "probe records observed model and depth"; fi
    ledger "$dir" accept --probe probe:cheap >/dev/null 2>&1
    if grep -q '"model": "unobserved"' "$dir/.agent_spinner/probe.json" && grep -q '"depth": "unobserved"' "$dir/.agent_spinner/probe.json"; then ok "probe records unobserved model and depth"; else bad "probe records unobserved model and depth"; fi

    if ledger "$dir" init --unit produce:doc --unit-path produce:doc=a.txt >/dev/null 2>&1; then ok "init opens a run after probe"; else bad "init opens a run after probe"; fi
    if grep -q '^probe:cheap' "$dir/.agent_spinner/roster.tsv"; then ok "init keeps probe rows"; else bad "init keeps probe rows"; fi
}

scenario_brief_lint() {
    dir="$1"
    setup_repo "$dir"
    printf 'shared one\n' > "$dir/shared.txt"
    ledger "$dir" init --unit produce:a --unit produce:b >/dev/null 2>&1
    ledger "$dir" brief produce:a --shared-file "$dir/shared.txt" --body "A" >/dev/null 2>&1
    printf 'shared two\n' > "$dir/shared.txt"
    if ledger "$dir" brief produce:b --shared-file "$dir/shared.txt" --body "B" >/dev/null 2>&1; then bad "differing shared block refused"; else ok "differing shared block refused"; fi

    dir2="$dir/second"
    setup_repo "$dir2"
    ledger "$dir2" init --unit produce:a >/dev/null 2>&1
    if ledger "$dir2" brief produce:a --body "A" --permit-path a.txt --forbid-path a.txt >/dev/null 2>&1; then bad "permit and forbid path refused"; else ok "permit and forbid path refused"; fi
    check "path refusal writes no brief" test ! -f "$dir2/.agent_spinner/briefs/produce:a.txt"
    if ledger "$dir2" brief produce:a --body "A" --permit-command "make lint" --forbid-command "make lint" >/dev/null 2>&1; then bad "permit and forbid command refused"; else ok "permit and forbid command refused"; fi
    check "command refusal writes no brief" test ! -f "$dir2/.agent_spinner/briefs/produce:a.txt"

    if ledger_has "$dir2" -i 'steering' brief produce:a --body "You will find the bug is real." --checker; then ok "checker steering word warns"; else bad "checker steering word warns"; fi
}

scenario_dispatch() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit produce:b --unit check:c --wave 1 --bound 60 >/dev/null 2>&1
    for label in produce:a produce:b check:c; do ledger "$dir" brief "$label" --body "$label" >/dev/null 2>&1; done
    ledger "$dir" stop >/dev/null 2>&1
    if ledger "$dir" dispatch produce:a >/dev/null 2>&1; then bad "dispatch refused under STOP"; else ok "dispatch refused under STOP"; fi
    rm -f "$dir/.agent_spinner/STOP"
    if ledger "$dir" dispatch produce:a >/dev/null 2>&1; then ok "dispatch resumes once STOP is removed"; else bad "dispatch resumes once STOP is removed"; fi
    if ledger "$dir" dispatch produce:b >/dev/null 2>&1; then bad "wave cap refuses another writer"; else ok "wave cap refuses another writer"; fi
    if ledger "$dir" dispatch check:c >/dev/null 2>&1; then ok "wave cap still dispatches a check row"; else bad "wave cap still dispatches a check row"; fi

    dir2="$dir/two"
    setup_repo "$dir2"
    ledger "$dir2" init --unit produce:a >/dev/null 2>&1
    ledger "$dir2" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir2" dispose --open-gate g1 --question "Proceed?" >/dev/null 2>&1
    if ledger "$dir2" dispatch produce:a >/dev/null 2>&1; then bad "open user gate refuses a writer"; else ok "open user gate refuses a writer"; fi

    dir3="$dir/three"
    setup_repo "$dir3"
    ledger "$dir3" init --unit produce:a >/dev/null 2>&1
    ledger "$dir3" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir3" dispatch produce:a >/dev/null 2>&1
    ledger "$dir3" dispatch produce:a >/dev/null 2>&1
    if ledger "$dir3" dispatch produce:a >/dev/null 2>&1; then bad "third attempt refused"; else ok "third attempt refused"; fi

    dir4="$dir/four"
    setup_repo "$dir4"
    ledger "$dir4" init --unit repair:a --unit repair:b --unit-path repair:a=a.txt --unit-path repair:b=a.txt >/dev/null 2>&1
    ledger "$dir4" brief repair:a --body "A" --kind repair --target a.txt >/dev/null 2>&1
    ledger "$dir4" brief repair:b --body "B" --kind repair --target a.txt >/dev/null 2>&1
    ledger "$dir4" dispatch repair:a >/dev/null 2>&1
    if ledger "$dir4" dispatch repair:b >/dev/null 2>&1; then bad "second repair of one path refused"; else ok "second repair of one path refused"; fi

    dir5="$dir/five"
    setup_repo "$dir5"
    ledger "$dir5" init --unit recheck:a --unit recheck:b --unit-path recheck:a=a.txt --unit-path recheck:b=a.txt >/dev/null 2>&1
    ledger "$dir5" brief recheck:a --body "A" --kind recheck >/dev/null 2>&1
    ledger "$dir5" brief recheck:b --body "B" --kind recheck >/dev/null 2>&1
    ledger "$dir5" dispatch recheck:a >/dev/null 2>&1
    if ledger "$dir5" dispatch recheck:b >/dev/null 2>&1; then bad "second re-check of one item refused"; else ok "second re-check of one item refused"; fi
}

scenario_spawn_recording() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit produce:b --wave 2 >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" brief produce:b --body "B" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a --helper-id H1 --model M1 --effort E1 --route r1 >/dev/null 2>&1
    ledger "$dir" dispatch produce:b --route r2 >/dev/null 2>&1
    line_a=$(grep '^produce:a' "$dir/.agent_spinner/roster.tsv")
    line_b=$(grep '^produce:b' "$dir/.agent_spinner/roster.tsv")
    printf '%s\n' "$line_a" | awk -F'\t' '{print $11, $12, $13, $14, $17}' > "$dir/fields_a"
    if grep -q 'H1 r1 M1 E1 .*' "$dir/fields_a" && awk -F'\t' '$17 != ""' "$dir/.agent_spinner/roster.tsv" | grep -q 'produce:a'; then
        ok "dispatch records helper id, route, model, effort and time"
    else
        bad "dispatch records helper id, route, model, effort and time"
    fi
    printf '%s\n' "$line_b" | awk -F'\t' '{print $11, $17}' > "$dir/fields_b"
    if awk -F'\t' '$11 == "" && $17 != "" {found=1} END {exit !found}' <<EOF
$line_b
EOF
    then
        ok "dispatch without helper id leaves that column empty"
    else
        bad "dispatch without helper id leaves that column empty"
    fi
}

rejection_setup() {
    d="$1"
    shift
    setup_repo "$d"
    ledger "$d" init --unit produce:a --unit-path produce:a=a.txt "$@" >/dev/null 2>&1
    ledger "$d" brief produce:a --body "A" --target a.txt --obligation a.txt >/dev/null 2>&1
    ledger "$d" dispatch produce:a >/dev/null 2>&1
}

rejection_expect() {
    d="$1"
    name="$2"
    want="${3:-violation}"
    if ledger "$d" accept produce:a >/dev/null 2>&1; then
        bad "$name rejected"
    else
        ok "$name rejected"
    fi
    state=$(awk -F'\t' '$1=="produce:a"{print $7}' "$d/.agent_spinner/roster.tsv")
    if [ "$state" = "$want" ]; then
        ok "$name leaves the row in $want"
    else
        bad "$name leaves the row in $want"
    fi
}

scenario_rejection() {
    dir="$1"

    d="$dir/end"
    rejection_setup "$d"
    cat > "$d/.agent_spinner/returns/produce:a.md" <<EOF
prose only, no sentinel
EOF
    rejection_expect "$d" "missing END line"
    cat > "$d/.agent_spinner/returns/produce:a.md" <<EOF
still no sentinel
EOF
    if ledger "$d" accept produce:a >/dev/null 2>&1; then bad "second rejection fails the row"; else ok "second rejection fails the row"; fi
    state=$(awk -F'\t' '$1=="produce:a"{print $7}' "$d/.agent_spinner/roster.tsv")
    check "second rejection leaves the row in failed" test "$state" = failed

    d="$dir/blocks"
    rejection_setup "$d"
    cat > "$d/.agent_spinner/returns/produce:a.md" <<EOF
\`\`\`json
{}
\`\`\`
\`\`\`json
{}
\`\`\`
END produce:a
EOF
    rejection_expect "$d" "two fenced blocks"

    d="$dir/label"
    rejection_setup "$d"
    token=$(token_of "$d" produce:a)
    emit_return "$d" produce:a "$token" '{"label":"produce:b"}'
    rejection_expect "$d" "echoed label mismatch"

    d="$dir/token"
    rejection_setup "$d"
    token=$(token_of "$d" produce:a)
    emit_return "$d" produce:a "$token" '{"brief":"deadbeef"}'
    rejection_expect "$d" "brief token mismatch"

    d="$dir/missing-key"
    rejection_setup "$d"
    token=$(token_of "$d" produce:a)
    emit_return "$d" produce:a "$token" '{}'
    "$PY" - "$d/.agent_spinner/returns/produce:a.md" <<'PY'
import json
import re
import sys

path = sys.argv[1]
text = open(path).read()
match = re.search(r"```json\n(.*?)\n```", text, re.S)
data = json.loads(match.group(1))
del data["notes"]
text = text[:match.start(1)] + json.dumps(data) + text[match.end(1):]
open(path, "w").write(text)
PY
    rejection_expect "$d" "required key missing"

    d="$dir/out-of-set"
    rejection_setup "$d"
    token=$(token_of "$d" produce:a)
    emit_return "$d" produce:a "$token" '{"status":"maybe"}'
    rejection_expect "$d" "value outside its allowed set"

    d="$dir/placeholder"
    rejection_setup "$d"
    token=$(token_of "$d" produce:a)
    emit_return "$d" produce:a "$token" '{"findings":[{"claim":"TODO","severity":"major","quote":"q","anchor":"a"}]}'
    rejection_expect "$d" "placeholder value"

    d="$dir/receipt"
    rejection_setup "$d"
    token=$(token_of "$d" produce:a)
    emit_return "$d" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"not in the recorded copy"}]}'
    rejection_expect "$d" "receipt absent from the recorded version"

    d="$dir/span"
    rejection_setup "$d"
    token=$(token_of "$d" produce:a)
    emit_return "$d" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}],"checklist":[{"n":1,"verdict":"pass","span":""}]}'
    rejection_expect "$d" "passing checklist line with no span"

    d="$dir/obligations"
    setup_repo "$d"
    ledger "$d" init --unit produce:a --unit-path produce:a=a.txt >/dev/null 2>&1
    ledger "$d" brief produce:a --body "A" --target a.txt --obligation a.txt --obligation b.txt >/dev/null 2>&1
    ledger "$d" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$d" produce:a)
    emit_return "$d" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}],"checklist":[{"n":1,"verdict":"pass","span":"a.txt:1"}]}'
    rejection_expect "$d" "list short of its obligations"

    d="$dir/hollow"
    setup_repo "$d"
    printf 'one\n' > "$d/a.txt"
    ledger "$d" init --unit check:hollow --unit-path check:hollow=a.txt >/dev/null 2>&1
    ledger "$d" brief check:hollow --body "Check" --target a.txt --obligation a.txt --obligation b.txt --obligation NOTES.md --obligation c.txt --obligation d.txt >/dev/null 2>&1
    ledger "$d" dispatch check:hollow >/dev/null 2>&1
    token=$(token_of "$d" check:hollow)
    emit_return "$d" check:hollow "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"one"}],"checklist":[{"n":1,"verdict":"pass","span":"<path>"}]}'
    if ledger "$d" accept check:hollow >/dev/null 2>&1; then bad "schema-valid hollow return rejected"; else ok "schema-valid hollow return rejected"; fi

    d="$dir/inability"
    setup_repo "$d"
    ledger "$d" init --unit produce:a >/dev/null 2>&1
    ledger "$d" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$d" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$d" produce:a)
    emit_return "$d" produce:a "$token" '{"status":"inability","verdict":"fail"}'
    ledger "$d" accept produce:a >/dev/null 2>&1
    state=$(awk -F'\t' '$1=="produce:a"{print $7}' "$d/.agent_spinner/roster.tsv")
    check "inability completes its row" test "$state" = inability
}

scenario_joins() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit produce:b >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" brief produce:b --body "B" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    ledger "$dir" dispatch produce:b >/dev/null 2>&1
    token_a=$(token_of "$dir" produce:a)
    token_b=$(token_of "$dir" produce:b)
    emit_return "$dir" produce:a "$token_a" '{}'
    emit_return "$dir" produce:b "$token_b" '{}'
    if ledger "$dir" accept produce:b >/dev/null 2>&1 && ledger "$dir" accept produce:a >/dev/null 2>&1; then
        ok "reverse-order returns join by echoed label and token"
    else
        bad "reverse-order returns join by echoed label and token"
    fi
}

scenario_diff() {
    dir="$1"
    setup_repo "$dir"
    printf '2026-01-01\n' >> "$dir/NOTES.md"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "dated notes"
    ledger "$dir" init --unit produce:a --unit-path produce:a=a.txt >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1

    printf 'alpha\nbeta\ndelta\n' > "$dir/a.txt"
    printf 'orchestrator\n' > "$dir/b.txt"
    printf 'new\n' > "$dir/new.txt"
    printf '# Notes\n2026-02-02\n' > "$dir/NOTES.md"
    printf 'residue\n' > "$dir/residue.log"

    ledger "$dir" diff --add-checks > "$dir/diff.txt" 2>&1
    check "diff adds a check row for a changed path" grep -q 'check:a.txt' "$dir/.agent_spinner/roster.tsv"
    if grep -q 'b.txt -> orchestrator' "$dir/diff.txt"; then ok "orchestrator write attributed to the orchestrator"; else bad "orchestrator write attributed to the orchestrator"; fi
    if grep -q 'new.txt' "$dir/diff.txt"; then ok "untracked file caught"; else bad "untracked file caught"; fi
    if grep -q 'date-only' "$dir/diff.txt"; then ok "date-only change flagged"; else bad "date-only change flagged"; fi
    if grep -q 'new-ignored-residue' "$dir/diff.txt"; then ok "new ignored residue caught"; else bad "new ignored residue caught"; fi
    if ledger_has "$dir" 'condition 3' close; then ok "an open check row keeps close refusing"; else bad "an open check row keeps close refusing"; fi

    printf 'stashed\n' >> "$dir/NOTES.md"
    git -C "$dir" stash push -q -m ledger-test 2>/dev/null || true
    ledger "$dir" diff > "$dir/diff-stash.txt" 2>&1
    if grep -q 'stash-change' "$dir/diff-stash.txt"; then ok "stash change caught"; else bad "stash change caught"; fi
    git -C "$dir" add -A
    git -C "$dir" commit -qm "move head" >/dev/null 2>&1
    ledger "$dir" diff > "$dir/diff-head.txt" 2>&1
    if grep -q 'head-move' "$dir/diff-head.txt"; then ok "HEAD move caught"; else bad "HEAD move caught"; fi
}

scenario_nonrepo_walk() {
    dir=$(mktemp -d "${TMPDIR:-/tmp}/ledger-nonrepo.XXXXXX")
    setup_plain "$dir"
    ledger "$dir" init --unit produce:a --unit-path produce:a=a.txt >/dev/null 2>&1
    check "non-repository init records a hashed walk" test -s "$dir/.agent_spinner/baseline/walk.json"
    if grep -q '"type": "narrowing"' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "non-repository init records the hashed-walk narrowing"
    else
        bad "non-repository init records the hashed-walk narrowing"
    fi
    printf 'alpha changed\n' > "$dir/a.txt"
    ledger "$dir" diff --add-checks > "$dir/diff.txt" 2>&1
    if grep -q 'a.txt' "$dir/diff.txt"; then ok "non-repository diff reports a changed file"; else bad "non-repository diff reports a changed file"; fi
    if grep -q 'check:a.txt' "$dir/.agent_spinner/roster.tsv"; then ok "non-repository diff adds a check row"; else bad "non-repository diff adds a check row"; fi
    if grep -q 'b.txt' "$dir/diff.txt"; then bad "non-repository diff leaves unchanged files out"; else ok "non-repository diff leaves unchanged files out"; fi
    rm -rf "$dir"
}

scenario_small_return() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit produce:b --wave 2 >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" brief produce:b --body "B" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    ledger "$dir" dispatch produce:b >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    long=$("$PY" -c 'print("x" * 2000)')
    emit_return "$dir" produce:a "$token" "{\"notes\":\"$long\"}"
    ledger "$dir" accept produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:b)
    emit_return "$dir" produce:b "$token" '{}'
    if ledger_has "$dir" -i 'far smaller than its siblings' accept produce:b; then
        ok "a return far smaller than its siblings warns"
    else
        bad "a return far smaller than its siblings warns"
    fi
}

scenario_approved_edits() {
    dir="$1"
    setup_repo "$dir"
    printf 'one\ntwo\nthree\nfour\nfive\n' > "$dir/a.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "long file"
    ledger "$dir" init --unit produce:a --unit-path produce:a=a.txt >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    printf 'ONE\ntwo\nthree\nfour\nFIVE\nextra\n' > "$dir/a.txt"
    cat > "$dir/approved.json" <<'JSON'
[{"id":"e1","path":"a.txt","text":"ONE"},{"id":"e2","path":"a.txt","text":"FIVE"}]
JSON
    ledger "$dir" diff --approved-edits "$dir/approved.json" > "$dir/approved.out" 2>&1
    if grep -q 'mapped e1' "$dir/approved.out" && grep -q 'mapped e2' "$dir/approved.out"; then
        ok "approved edits map by path and text"
    else
        bad "approved edits map by path and text"
    fi
    if [ "$(grep -c 'unmapped' "$dir/approved.out")" = 1 ]; then ok "the extra hunk maps to no approved id"; else bad "the extra hunk maps to no approved id"; fi
}

scenario_counters() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    if ledger "$dir" diff --count --counter 'good=CONTROL_MARKER' >/dev/null 2>&1; then ok "counter finds its known positive"; else bad "counter finds its known positive"; fi
    if ledger "$dir" diff --count --counter 'bad=NO_SUCH_MARKER' >/dev/null 2>&1; then bad "counter missing its known positive fails closed"; else ok "counter missing its known positive fails closed"; fi
}

scenario_gate_expect() {
    dir="$1"
    setup_repo "$dir"
    cat > "$dir/gate.sh" <<'SH'
#!/bin/sh
printf 'gate output\n'
exit 0
SH
    chmod +x "$dir/gate.sh"
    ledger "$dir" init --unit produce:a --gate "md=$dir/gate.sh {controls}" >/dev/null 2>&1
    ledger "$dir" gate silent --expect exit0 -- /usr/bin/true > "$dir/gate1.txt" 2>&1
    if grep -q 'silent=True' "$dir/gate1.txt"; then ok "exit0 records a silent pass as silent"; else bad "exit0 records a silent pass as silent"; fi
    if ledger "$dir" gate empty --expect nonempty -- /usr/bin/true >/dev/null 2>&1; then bad "nonempty fails on empty output"; else ok "nonempty fails on empty output"; fi
    if ledger "$dir" gate counted --expect count -- "$dir/gate.sh" >/dev/null 2>&1; then bad "count refuses without a passing positive control"; else ok "count refuses without a passing positive control"; fi
    ledger "$dir" gate md --on-baseline -- "$dir/gate.sh" >/dev/null 2>&1
    ledger "$dir" gate md -- "$dir/gate.sh" > "$dir/gate2.txt" 2>&1
    if grep -q 'baseline difference' "$dir/gate2.txt"; then ok "baseline difference reported"; else bad "baseline difference reported"; fi
    if grep -q '"executable"' "$dir/.agent_spinner/ledger.jsonl"; then ok "resolved executable path recorded"; else bad "resolved executable path recorded"; fi
    if ledger "$dir" gate missing -- /no/such/executable >/dev/null 2>&1; then bad "unresolved executable records unavailable"; else ok "unresolved executable records unavailable"; fi
    if grep -q '"type": "narrowing"' "$dir/.agent_spinner/ledger.jsonl"; then ok "unresolved executable names the narrowing"; else bad "unresolved executable names the narrowing"; fi
}

build_clean() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit check:b --unit-path produce:a=a.txt --unit-path check:b=a.txt --bound 60 >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" --target a.txt --depth 2 >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    printf 'alpha\nbeta\ngamma\n' > "$dir/a.txt"
    ledger "$dir" brief check:b --body "B" --target a.txt --relay produce:a --depth 2 --obligation a.txt >/dev/null 2>&1
    ledger "$dir" dispatch check:b >/dev/null 2>&1
    token=$(token_of "$dir" check:b)
    emit_return "$dir" check:b "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"gamma"}]}'
    ledger "$dir" accept check:b >/dev/null 2>&1
    ledger "$dir" diff --add-checks >/dev/null 2>&1
    ledger "$dir" brief check:a.txt --body "C" --target a.txt --depth 2 --obligation a.txt >/dev/null 2>&1
    ledger "$dir" dispatch check:a.txt >/dev/null 2>&1
    token=$(token_of "$dir" check:a.txt)
    emit_return "$dir" check:a.txt "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"gamma"}]}'
    ledger "$dir" accept check:a.txt >/dev/null 2>&1
    ledger "$dir" close 2>/dev/null | sed -n '/TALLY-BEGIN/,/TALLY-END/p' > "$dir/.agent_spinner/report.md"
    printf '\n# Report\n\nAll clear.\n' >> "$dir/.agent_spinner/report.md"
}

close_assert() {
    d="$1"
    name="$2"
    pattern="$3"
    shift 3
    ledger "$d" close "$@" > "$d/.agent_spinner/close.out" 2>&1
    rc=$?
    if [ "$rc" -eq 3 ] && grep -q "$pattern" "$d/.agent_spinner/close.out"; then
        ok "$name"
    else
        bad "$name (rc=$rc)"
    fi
}

scenario_close_conditions() {
    base="$1"

    dir="$base/c1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    close_assert "$dir" "condition 1 refuses an open row with exit 3" 'condition 1'

    dir="$base/c2"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"findings":[{"claim":"A defect","severity":"major","quote":"alpha","anchor":"a.txt:1"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    close_assert "$dir" "condition 2 refuses an undisposed finding with exit 3" 'condition 2'

    dir="$base/c3"
    build_clean "$dir"
    printf 'extra\n' > "$dir/b.txt"
    ledger "$dir" diff >/dev/null 2>&1
    close_assert "$dir" "condition 3 refuses an uncovered changed path with exit 3" 'condition 3'

    dir="$base/c4"
    build_clean "$dir"
    "$PY" - "$dir/.agent_spinner/run.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for change in data.get("changes", []):
    change["attribution"] = ""
json.dump(data, open(path, "w"))
PY
    close_assert "$dir" "condition 4 refuses an unattributed change with exit 3" 'condition 4'

    dir="$base/c5"
    build_clean "$dir"
    printf 'stray\n' > "$dir/stray.txt"
    close_assert "$dir" "condition 5 refuses an undisposed tree change with exit 3" 'condition 5'

    dir="$base/c6"
    build_clean "$dir"
    ledger "$dir" dispose --open-gate g1 --question "Proceed?" >/dev/null 2>&1
    close_assert "$dir" "condition 6 refuses an unanswered gate with exit 3" 'condition 6'
    ledger "$dir" dispose --gate g1 --answered "yes" >/dev/null 2>&1
    if ledger "$dir" close >/dev/null 2>&1; then ok "condition 6 clears once the gate is answered"; else bad "condition 6 clears once the gate is answered"; fi

    dir="$base/c6fork"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"forks":[{"issue":"Which option should land?","options":[{"id":"a","text":"Option a","cost":"1"},{"id":"b","text":"Option b","cost":"2"}],"passages":[{"text":"alpha","anchor":"a.txt:1"}],"preferred":"a"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" close 2>/dev/null | sed -n '/TALLY-BEGIN/,/TALLY-END/p' > "$dir/.agent_spinner/report.md"
    printf '\n# Report\n' >> "$dir/.agent_spinner/report.md"
    close_assert "$dir" "condition 6 refuses an undecided fork with exit 3" 'condition 6'
    if grep -q 'produce:a:forks:0' "$dir/.agent_spinner/close.out"; then ok "condition 6 names the undecided fork"; else bad "condition 6 names the undecided fork"; fi
    ledger "$dir" dispose --fork produce:a:forks:0 --own-decision "chose option a" >/dev/null 2>&1
    if ledger "$dir" close >/dev/null 2>&1; then ok "an own-authority call clears the fork"; else bad "an own-authority call clears the fork"; fi

    dir="$base/c7"
    build_clean "$dir"
    printf 'no tally here\n' > "$dir/.agent_spinner/report.md"
    close_assert "$dir" "condition 7 refuses an altered report with exit 3" 'condition 7'

    dir="$base/c8"
    build_clean "$dir"
    awk -F'\t' 'BEGIN{OFS="\t"} $1=="produce:a" {$20=""} {print}' "$dir/.agent_spinner/roster.tsv" > "$dir/roster.tmp"
    mv "$dir/roster.tmp" "$dir/.agent_spinner/roster.tsv"
    close_assert "$dir" "condition 8 refuses a row with no source with exit 3" 'condition 8'

    dir="$base/c9"
    build_clean "$dir"
    ledger "$dir" brief check:b --body "B" --target a.txt --relay produce:a --depth 1 --obligation a.txt >/dev/null 2>&1
    close_assert "$dir" "condition 9 flags a checker below its producer with exit 3" 'condition 9'
    ledger "$dir" dispose --flag check:b --reason "depth accepted for this run" >/dev/null 2>&1
    if ledger "$dir" close >/dev/null 2>&1; then ok "a flags record clears condition 9"; else bad "a flags record clears condition 9"; fi

    dir="$base/c1rows"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"findings":[{"claim":"A defect","severity":"major","quote":"alpha","anchor":"a.txt:1"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" rows --phase review --from-records 'produce:a:findings:*' >/dev/null 2>&1 || true
    close_assert "$dir" "condition 1 covers runtime rows with exit 3" 'condition 1'

    dir="$base/stopped"
    build_clean "$dir"
    printf 'stray\n' > "$dir/stray.txt"
    close_assert "$dir" "close --stopped lists modified paths with exit 3" 'modified:' --stopped
    close_assert "$dir" "close --stopped lists untouched paths with exit 3" 'untouched:' --stopped
    close_assert "$dir" "close --stopped lists unknown paths with exit 3" 'unknown:' --stopped
}

scenario_run_directory() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit-path produce:a=a.txt --exclude "skip:not needed" >/dev/null 2>&1
    mkdir -p "$dir/.agent_spinner/access" "$dir/.agent_spinner/kinds" "$dir/.agent_spinner/items"
    printf 'access\n' > "$dir/.agent_spinner/access/work.md"
    printf 'kind\n' > "$dir/.agent_spinner/kinds/kind.md"
    printf 'item\n' > "$dir/.agent_spinner/items/produce:a.md"
    printf 'announcement\n' > "$dir/.agent_spinner/announcement.txt"
    printf 'gate log\n' > "$dir/.agent_spinner/gates/g1.log"
    printf 'draft\n' > "$dir/.agent_spinner/outbound/draft.txt"
    check "exclusion recorded with its reason" grep -q 'skip' "$dir/.agent_spinner/exclusions.tsv"
    ledger "$dir" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" close 2>/dev/null | sed -n '/TALLY-BEGIN/,/TALLY-END/p' > "$dir/.agent_spinner/report.md"
    printf '\n# Report\n' >> "$dir/.agent_spinner/report.md"
    if ledger "$dir" close >/dev/null 2>&1; then ok "hand-supplied run-directory files reach close"; else bad "hand-supplied run-directory files reach close"; fi
    for entry in run.json request.txt intent.md preamble.md facts.tsv access kinds items roster.tsv exclusions.tsv briefs returns ledger.jsonl baseline snapshots diffs gates outbound controls announcement.txt report.md history; do
        if [ -e "$dir/.agent_spinner/$entry" ]; then
            ok "flat run directory holds $entry"
        else
            bad "flat run directory holds $entry"
        fi
    done
    files=$(find "$dir/.agent_spinner/snapshots" -type f 2>/dev/null | wc -l | tr -d ' ')
    check "close empties snapshots" test "$files" = 0
    fields=$(awk -F'\t' 'NR==1{print NF}' "$dir/.agent_spinner/roster.tsv")
    check "roster carries all columns" test "$fields" = 21
    first=$(awk -F'\t' 'NR==1{print $1, $2, $3, $4, $5, $6, $7}' "$dir/.agent_spinner/roster.tsv")
    check "roster columns keep their order" test "$first" = "produce:a work produce a a.txt writer accepted"
    ledger "$dir" init --unit produce:b >/dev/null 2>&1
    if find "$dir/.agent_spinner/history" -name roster.tsv | grep -q .; then ok "the next init moves the closed run under history"; else bad "the next init moves the closed run under history"; fi
}

scenario_repo_safety() {
    dir="$1"
    setup_repo "$dir"
    printf '#!/bin/sh\nexit 0\n' > "$dir/gate.sh"
    chmod +x "$dir/gate.sh"
    tree_before=$(cd "$dir" && find . -path ./.agent_spinner -prune -o -type f -print0 | sort -z | xargs -0 shasum | shasum)
    index_before=$(shasum "$dir/.git/index")
    refs_before=$(git -C "$dir" for-each-ref)
    objects_before=$(git -C "$dir" count-objects -v)
    ledger "$dir" init --unit produce:a --unit-path produce:a=a.txt --gate "md=$dir/gate.sh {controls}" >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" diff >/dev/null 2>&1
    ledger "$dir" gate md -- "$dir/gate.sh" >/dev/null 2>&1
    ledger "$dir" snapshot produce:a a.txt >/dev/null 2>&1
    ledger "$dir" status >/dev/null 2>&1
    ledger "$dir" show produce:a >/dev/null 2>&1
    ledger "$dir" search alpha >/dev/null 2>&1
    ledger "$dir" close >/dev/null 2>&1
    tree_after=$(cd "$dir" && find . -path ./.agent_spinner -prune -o -type f -print0 | sort -z | xargs -0 shasum | shasum)
    index_after=$(shasum "$dir/.git/index")
    refs_after=$(git -C "$dir" for-each-ref)
    objects_after=$(git -C "$dir" count-objects -v)
    check "tree outside the run directory is unchanged" test "$tree_before" = "$tree_after"
    check "index bytes unchanged" test "$index_before" = "$index_after"
    check "refs unchanged" test "$refs_before" = "$refs_after"
    check "object count unchanged" test "$objects_before" = "$objects_after"
    check "no bytecode written" test -z "$(find "$REPO_ROOT/plugins/ai_dev/skills/agent_spinner" -name __pycache__ -print 2>/dev/null)"
}

scenario_accept_stdin() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit-path produce:a=a.txt >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    if cat "$dir/.agent_spinner/returns/produce:a.md" | ledger "$dir" accept produce:a --stdin >/dev/null 2>&1; then
        ok "accept --stdin takes the verbatim final message"
    else
        bad "accept --stdin takes the verbatim final message"
    fi
    source=$(awk -F'\t' '$1=="produce:a"{print $20}' "$dir/.agent_spinner/roster.tsv")
    check "stdin return records source relayed" test "$source" = relayed

    dir2="$dir/two"
    setup_repo "$dir2"
    ledger "$dir2" init --unit produce:a --unit-path produce:a=a.txt >/dev/null 2>&1
    ledger "$dir2" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir2" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir2" produce:a)
    emit_return "$dir2" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    "$PY" - "$dir2/.agent_spinner/returns/produce:a.md" "$dir2/host.log" <<'PY'
import json
import sys

text = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(json.dumps({"type": "result", "result": text}) + "\n")
PY
    if cat "$dir2/host.log" | ledger "$dir2" accept produce:a --stdin >/dev/null 2>&1; then
        ok "accept --stdin takes a piped host log"
    else
        bad "accept --stdin takes a piped host log"
    fi
    source=$(awk -F'\t' '$1=="produce:a"{print $20}' "$dir2/.agent_spinner/roster.tsv")
    check "a piped host log records source log" test "$source" = log

    dir4="$dir/four"
    setup_repo "$dir4"
    ledger "$dir4" init --unit produce:a --unit-path produce:a=a.txt >/dev/null 2>&1
    ledger "$dir4" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir4" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir4" produce:a)
    emit_return "$dir4" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    cp "$dir4/.agent_spinner/returns/produce:a.md" "$dir4/host.log"
    ledger "$dir4" accept produce:a --log "$dir4/host.log" >/dev/null 2>&1
    source=$(awk -F'\t' '$1=="produce:a"{print $20}' "$dir4/.agent_spinner/roster.tsv")
    check "the --log file alias still records source log" test "$source" = log

    dir3="$dir/three"
    setup_repo "$dir3"
    ledger "$dir3" init --unit produce:a >/dev/null 2>&1
    ledger "$dir3" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir3" dispatch produce:a >/dev/null 2>&1
    if printf 'no sentinel\n' | ledger "$dir3" accept produce:a --stdin >/dev/null 2>&1; then
        bad "stdin applies the same rejections as a file"
    else
        ok "stdin applies the same rejections as a file"
    fi
}

scenario_attach() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    ledger "$dir" attach > "$dir/attach1.txt" 2>&1
    if grep -q 'pending returns' "$dir/attach1.txt" && grep -q 'produce:a' "$dir/attach1.txt"; then ok "attach reports the open run and pending returns"; else bad "attach reports the open run and pending returns"; fi
    printf 'head move\n' > "$dir/head.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "head move"
    ledger "$dir" attach > "$dir/attach2.txt" 2>&1
    if grep -qi 'moved since baseline' "$dir/attach2.txt"; then ok "attach reports a HEAD that moved"; else bad "attach reports a HEAD that moved"; fi
}

scenario_rows() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"findings":[{"claim":"A defect","severity":"major","quote":"alpha","anchor":"a.txt:1"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" rows --phase review --from-records 'produce:a:findings:*' > "$dir/rows.txt" 2>&1
    check "rows makes one row per source record" grep -q '^row: check:' "$dir/rows.txt"
    check "rows records the source phase" grep -q '"source_phase": "review"' "$dir/.agent_spinner/ledger.jsonl"
    if ledger "$dir" rows --phase review --from-records 'produce:a:findings:*' >/dev/null 2>&1; then bad "rows refuses a duplicate"; else ok "rows refuses a duplicate"; fi

    "$PY" - "$dir/.agent_spinner/run.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["repair_list"] = [{"id": "repair-one", "path": "a.txt"}]
json.dump(data, open(path, "w"))
PY
    ledger "$dir" rows --phase repair --from-repair-list >/dev/null 2>&1
    check "rows from the repair list" grep -q 'repair' "$dir/.agent_spinner/roster.tsv"

    "$PY" - "$dir/.agent_spinner/ledger.jsonl" <<'PY'
import json, sys
path = sys.argv[1]
record = {"type": "gap", "row": "produce:a", "id": "gap-one", "text": "missing check"}
with open(path, "a") as fh:
    fh.write(json.dumps(record) + "\n")
PY
    ledger "$dir" rows --phase gaps --from-gaps produce:a >/dev/null 2>&1
    check "rows from gaps" grep -q 'gap-one' "$dir/.agent_spinner/roster.tsv"
}

scenario_show_search() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"findings":[{"claim":"A defect","severity":"major","quote":"alpha","anchor":"a.txt:1"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" show produce:a > "$dir/show.txt" 2>&1
    if grep -q 'label: produce:a' "$dir/show.txt" && grep -q 'produce:a:findings:0' "$dir/show.txt"; then ok "show prints one row's records in full"; else bad "show prints one row's records in full"; fi
    printf 'NEEDLE_MARKER\n' > "$dir/.agent_spinner/planted.txt"
    ledger "$dir" search NEEDLE_MARKER > "$dir/search.txt" 2>&1
    if grep -q 'NEEDLE_MARKER' "$dir/search.txt" && grep -q 'positive control: passed' "$dir/search.txt"; then ok "search finds a marker with its positive control passing"; else bad "search finds a marker with its positive control passing"; fi
    if git -C "$dir" grep -q NEEDLE_MARKER >/dev/null 2>&1; then bad "an ignore-honouring search misses the marker"; else ok "an ignore-honouring search misses the marker"; fi
}

scenario_snapshot() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit check:b --unit-path check:b=a.txt >/dev/null 2>&1
    ledger "$dir" brief check:b --body "B" --target a.txt >/dev/null 2>&1
    printf 'changed\n' > "$dir/a.txt"
    ledger "$dir" snapshot check:b a.txt NOTES.md >/dev/null 2>&1
    check "snapshot copies a changed file byte for byte" cmp -s "$dir/a.txt" "$dir/.agent_spinner/snapshots/check:b/a.txt"
    check "snapshot copies an unchanged file byte for byte" cmp -s "$dir/NOTES.md" "$dir/.agent_spinner/snapshots/check:b/NOTES.md"
    ledger "$dir" snapshot check:b a.txt --base >/dev/null 2>&1
    git -C "$dir" show HEAD:a.txt > "$dir/base-a.txt"
    check "snapshot --base copies the base commit's content" cmp -s "$dir/base-a.txt" "$dir/.agent_spinner/snapshots/check:b/a.txt"
}

scenario_status() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit produce:b --bound 60 >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" brief produce:b --body "B" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    ledger "$dir" dispose --open-gate g1 --question "Proceed?" >/dev/null 2>&1
    "$PY" - "$dir/.agent_spinner/run.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["repair_list"] = [{"id": "repair-one", "path": "a.txt"}]
json.dump(data, open(path, "w"))
PY
    ledger "$dir" status > "$dir/status.txt" 2>&1
    if grep -q 'tally:' "$dir/status.txt"; then ok "status prints the live tally"; else bad "status prints the live tally"; fi
    if grep -q 'produce:a state=dispatched deadline=' "$dir/status.txt"; then ok "status prints an open row with its deadline"; else bad "status prints an open row with its deadline"; fi
    if grep -q 'g1 Proceed' "$dir/status.txt"; then ok "status prints the open gate"; else bad "status prints the open gate"; fi
    if grep -q 'repair-one\|a.txt' "$dir/status.txt"; then ok "status prints the repair list"; else bad "status prints the repair list"; fi
    resume=$(grep -c '^  [0-9a-f]\{64\} ' "$dir/status.txt")
    check "status resume lists one line per recorded brief" test "$resume" = 2
}

scenario_no_helper() {
    dir="$1"
    setup_repo "$dir"
    stub="$dir/stub"
    mkdir -p "$stub"
    real_git=$(command -v git)
    cat > "$stub/git" <<SH
#!/bin/sh
exec "$real_git" "\$@"
SH
    cat > "$stub/gate" <<'SH'
#!/bin/sh
for arg in "$@"; do
    if [ -d "$arg" ]; then
        find "$arg" -type f -print
    fi
done
exit 0
SH
    chmod +x "$stub/git" "$stub/gate"
    allowed=$("$PY" -c 'import json,os,sys; print(json.dumps([os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])]))' "$stub/git" "$stub/gate")
    log="$dir/audit.json"
    old_path="$PATH"
    export PATH="$stub:$PATH"

    run_audited "$dir" "$LEDGER" "$log" "$allowed" init --probe --cheapest cheap --role r1 --role r2
    run_audited "$dir" "$LEDGER" "$log" "$allowed" dispatch probe:cheap >/dev/null 2>&1
    token=$(token_of "$dir" probe:cheap)
    emit_return "$dir" probe:cheap "$token" '{"capabilities":{"delegation_surface":"established","concurrency":"unverified"}}'
    run_audited "$dir" "$LEDGER" "$log" "$allowed" accept --probe probe:cheap >/dev/null 2>&1

    run_audited "$dir" "$LEDGER" "$log" "$allowed" init --unit produce:doc --unit-path produce:doc=a.txt --gate "md=$stub/gate {controls}" --bound 60 --wave 2
    run_audited "$dir" "$LEDGER" "$log" "$allowed" attach >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" brief produce:doc --body "Update a.txt." --target a.txt --depth 2 >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" dispatch produce:doc --helper-id H1 --model M1 --effort E1 >/dev/null 2>&1
    token=$(token_of "$dir" produce:doc)
    emit_return "$dir" produce:doc "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}],"findings":[{"claim":"A defect","severity":"major","quote":"alpha","anchor":"a.txt:1"}]}'
    run_audited "$dir" "$LEDGER" "$log" "$allowed" accept produce:doc >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" diff --add-checks >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" rows --phase review --from-records 'produce:doc:findings:*' >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" brief check:produce-doc-findings-0 --body "Check the finding." --target a.txt --depth 2 --obligation a.txt >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" dispatch check:produce-doc-findings-0 >/dev/null 2>&1
    token=$(token_of "$dir" check:produce-doc-findings-0)
    emit_return "$dir" check:produce-doc-findings-0 "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    run_audited "$dir" "$LEDGER" "$log" "$allowed" accept check:produce-doc-findings-0 >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" dispose --id 'produce:doc:findings:0' --disposition applied --tag re-derived >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" dispose --flag produce:doc --reason "noted" >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" gate md -- "$stub/gate" "$dir/.agent_spinner/controls/md" >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" snapshot produce:doc a.txt >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" status >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" show produce:doc >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" search alpha >/dev/null 2>&1
    run_audited "$dir" "$LEDGER" "$log" "$allowed" stop >/dev/null 2>&1
    rm -f "$dir/.agent_spinner/STOP"
    run_audited "$dir" "$LEDGER" "$log" "$allowed" close >/dev/null 2>&1 || true
    run_audited "$dir" "$LEDGER" "$log" "$allowed" close 2>/dev/null | sed -n '/TALLY-BEGIN/,/TALLY-END/p' > "$dir/.agent_spinner/report.md"
    printf '\n# Report\n' >> "$dir/.agent_spinner/report.md"
    if run_audited "$dir" "$LEDGER" "$log" "$allowed" close >/dev/null 2>&1; then
        ok "the audited run reaches its close"
    else
        bad "the audited run reaches its close"
    fi
    if "$PY" - "$log" "$allowed" <<'PY'
import json, sys
log, allowed = sys.argv[1:3]
allowed = set(json.loads(allowed))
events = json.load(open(log))
bad = [e for e in events if e.get("target") not in allowed]
raise SystemExit(1 if bad else 0)
PY
    then
        ok "no helper launched: every spawn resolves to git or the gate wrapper"
    else
        bad "no helper launched: every spawn resolves to git or the gate wrapper"
    fi

    # Negative control: a scratch copy that forks and then execs a helper must
    # fail the same assertion.
    forked="$dir/forked_ledger.py"
    "$PY" - "$LEDGER" "$forked" <<'PY'
import sys
source = open(sys.argv[1]).read()
needle = "def cmd_stop(args):\n"
inject = (
    "def cmd_stop(args):\n"
    "    import os as _os\n"
    "    if _os.fork() == 0:\n"
    "        _os.execv(sys.executable, [sys.executable, '-c', 'pass'])\n"
)
source = source.replace(needle, inject, 1)
open(sys.argv[2], "w").write(source)
PY
    fork_log="$dir/fork-audit.json"
    if run_audited "$dir" "$forked" "$fork_log" "$allowed" stop >/dev/null 2>&1; then
        bad "the assertion catches a fork-then-exec launch"
    else
        ok "the assertion catches a fork-then-exec launch"
    fi
    export PATH="$old_path"
}

scenario_gate_scope() {
    dir="$1"
    setup_repo "$dir"
    cat > "$dir/gate.sh" <<'SH'
#!/bin/sh
for arg in "$@"; do
    if [ -d "$arg" ]; then
        find "$arg" -type f -print
    fi
done
printf '%s/.agent_spinner/run.json\n' "$PWD"
exit 0
SH
    chmod +x "$dir/gate.sh"
    ledger "$dir" init --unit produce:a --gate "md=$dir/gate.sh --type .md {controls}" --gate "sh=$dir/gate.sh --type .sh {controls}" >/dev/null 2>&1
    check "init plants a markdown known positive" test -f "$dir/.agent_spinner/controls/md/known-positive.md"
    check "init plants a shell known positive" test -f "$dir/.agent_spinner/controls/sh/known-positive.sh"
    ledger "$dir" gate md -- "$dir/gate.sh" "$dir/.agent_spinner/controls/md" > "$dir/gate.txt" 2>&1
    if grep -qi 'dropped' "$dir/gate.txt"; then ok "the path filter drops run-directory findings"; else bad "the path filter drops run-directory findings"; fi
    dir2="$dir/autofix"
    setup_repo "$dir2"
    if ledger_has "$dir2" -i 'auto-fixing' init --unit produce:a --gate "md=$dir2/gate.sh {controls}" --auto-fix-gate md; then
        ok "a defined auto-fix gate is refused"
    else
        bad "a defined auto-fix gate is refused"
    fi
    check "the defined auto-fix refusal opens no run" test ! -f "$dir2/.agent_spinner/run.json"

    dir3="$dir/autofix-standalone"
    setup_repo "$dir3"
    if ledger_has "$dir3" -i 'auto-fixing' init --unit produce:a --auto-fix-gate md; then
        ok "a standalone auto-fix mark is refused"
    else
        bad "a standalone auto-fix mark is refused"
    fi
    check "the standalone auto-fix refusal opens no run" test ! -f "$dir3/.agent_spinner/run.json"
}

scenario_hostile_git() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    printf 'hidden\n' > "$dir/hidden.txt"
    old_params="${GIT_CONFIG_PARAMETERS:-}"
    export GIT_CONFIG_PARAMETERS="'status.showUntrackedFiles=no' 'color.ui=always' 'diff.external=/bin/false'"
    ledger "$dir" diff > "$dir/hostile.txt" 2>&1
    export GIT_CONFIG_PARAMETERS="$old_params"
    if grep -q 'hidden.txt' "$dir/hostile.txt"; then ok "hidden untracked files stay visible under hostile settings"; else bad "hidden untracked files stay visible under hostile settings"; fi
    link="$dir-link"
    ln -sfn "$dir" "$link"
    ledger "$link" status > "$dir/link.txt" 2>&1
    if grep -q 'run:' "$dir/link.txt"; then ok "a symlinked root resolves to the repository root"; else bad "a symlinked root resolves to the repository root"; fi
}

scenario_recorded_versions() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit check:b --unit-path check:b=a.txt >/dev/null 2>&1
    printf 'withheld secret\n' | ledger "$dir" brief check:b --body "B" --target a.txt --withheld >/dev/null 2>&1
    if grep -q '"withheld"' "$dir/.agent_spinner/roster.tsv" && not grep -q 'withheld secret' "$dir/.agent_spinner/roster.tsv"; then
        ok "a withheld text on stdin leaves only its hash on the blind row"
    else
        bad "a withheld text on stdin leaves only its hash on the blind row"
    fi
    if not grep -q 'withheld secret' "$dir/.agent_spinner/run.json"; then
        ok "the withheld body reaches no run file"
    else
        bad "the withheld body reaches no run file"
    fi
    ledger "$dir" dispatch check:b >/dev/null 2>&1
    printf 'live changed\n' > "$dir/a.txt"
    token=$(token_of "$dir" check:b)
    emit_return "$dir" check:b "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    if ledger "$dir" accept check:b >/dev/null 2>&1; then
        ok "a receipt matching the recorded snapshot is accepted after the live file changed"
    else
        bad "a receipt matching the recorded snapshot is accepted after the live file changed"
    fi

    dir2="$dir/withheld-seen"
    setup_repo "$dir2"
    ledger "$dir2" init --unit check:b --unit-path check:b=a.txt >/dev/null 2>&1
    printf 'withheld secret\n' | ledger "$dir2" brief check:b --body "B" --target a.txt --withheld >/dev/null 2>&1
    ledger "$dir2" dispatch check:b >/dev/null 2>&1
    withheld_hash=$("$PY" - "$dir2/.agent_spinner/roster.tsv" <<'PY'
import json
import sys
for line in open(sys.argv[1]):
    parts = line.rstrip("\n").split("\t")
    if parts and parts[0] == "check:b":
        versions = json.loads(parts[9])
        print(versions["withheld"][0])
PY
)
    token=$(token_of "$dir2" check:b)
    emit_return "$dir2" check:b "$token" "{\"examined\":[{\"path\":\"a.txt\",\"how\":\"full\",\"receipt\":\"alpha\"}],\"withheld_seen\":[\"$withheld_hash\"]}"
    if ledger "$dir2" accept check:b >/dev/null 2>&1; then
        bad "a blind row that returns the withheld hash is rejected"
    else
        ok "a blind row that returns the withheld hash is rejected"
    fi
    state=$(awk -F'\t' '$1=="check:b"{print $7}' "$dir2/.agent_spinner/roster.tsv")
    check "the withheld-hash rejection leaves violation" test "$state" = violation
}

scenario_recall_tags() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit check:b >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" brief check:b --body "B" --relay produce:a >/dev/null 2>&1
    ledger "$dir" dispatch check:b >/dev/null 2>&1
    token=$(token_of "$dir" check:b)
    emit_return "$dir" check:b "$token" '{"confirmations":[{"text":"the finding held"}]}'
    ledger "$dir" accept check:b >/dev/null 2>&1
    if grep -q '"provenance": "recall-confirmed"' "$dir/.agent_spinner/ledger.jsonl"; then ok "a relayed confirmation is tagged recall-confirmed"; else bad "a relayed confirmation is tagged recall-confirmed"; fi
    ledger "$dir" close 2>/dev/null | sed -n '/TALLY-BEGIN/,/TALLY-END/p' > "$dir/tally.txt"
    if grep -q 'recall-confirmed 1' "$dir/tally.txt" && grep -q 'independently-surfaced 0' "$dir/tally.txt"; then ok "the tally splits the two confirmation kinds"; else bad "the tally splits the two confirmation kinds"; fi
    if ledger_has "$dir" -i 'advisory.*independent' close; then ok "close flags an independent claim on a recall-confirmed row"; else bad "close flags an independent claim on a recall-confirmed row"; fi

    dir2="$dir/two"
    setup_repo "$dir2"
    ledger "$dir2" init --unit check:b >/dev/null 2>&1
    ledger "$dir2" brief check:b --body "B" >/dev/null 2>&1
    ledger "$dir2" dispatch check:b >/dev/null 2>&1
    token=$(token_of "$dir2" check:b)
    emit_return "$dir2" check:b "$token" '{"confirmations":[{"text":"found independently"}]}'
    ledger "$dir2" accept check:b >/dev/null 2>&1
    if grep -q '"provenance": "independently surfaced"' "$dir2/.agent_spinner/ledger.jsonl"; then ok "an unrelayed confirmation is independently surfaced"; else bad "an unrelayed confirmation is independently surfaced"; fi
}

scenario_start_markers() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit produce:b --unit produce:c --wave 3 >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" brief produce:b --body "B" >/dev/null 2>&1
    ledger "$dir" brief produce:c --body "C" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    ledger "$dir" dispatch produce:b >/dev/null 2>&1
    ledger "$dir" dispatch produce:c >/dev/null 2>&1
    printf 'start a\n' > "$dir/.agent_spinner/returns/produce:a.start"
    printf 'start b\n' > "$dir/.agent_spinner/returns/produce:b.start"
    printf 'start c\n' > "$dir/.agent_spinner/returns/produce:c.start"
    touch -t 202601010101 "$dir/.agent_spinner/returns/produce:a.start"
    touch -t 202601010102 "$dir/.agent_spinner/returns/produce:b.start"
    touch -t 202601010105 "$dir/.agent_spinner/returns/produce:c.start"
    token_a=$(token_of "$dir" produce:a)
    token_b=$(token_of "$dir" produce:b)
    token_c=$(token_of "$dir" produce:c)
    emit_return "$dir" produce:a "$token_a" '{}'
    emit_return "$dir" produce:b "$token_b" '{}'
    emit_return "$dir" produce:c "$token_c" '{}'
    touch -t 202601010104 "$dir/.agent_spinner/returns/produce:a.md"
    touch -t 202601010103 "$dir/.agent_spinner/returns/produce:b.md"
    touch -t 202601010106 "$dir/.agent_spinner/returns/produce:c.md"
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" accept produce:b >/dev/null 2>&1
    ledger "$dir" accept produce:c >/dev/null 2>&1
    ledger "$dir" status > "$dir/status.txt" 2>&1
    if grep -q 'overlap: produce:a produce:b' "$dir/status.txt"; then ok "overlapping intervals read from filesystem times"; else bad "overlapping intervals read from filesystem times"; fi
    if grep -q 'produce:c start=.* serial' "$dir/status.txt"; then ok "serial intervals read from filesystem times"; else bad "serial intervals read from filesystem times"; fi
}

scenario_version_floor() {
    dir="$1"
    setup_repo "$dir"
    "$PY" - "$LEDGER" <<'PY' > "$dir/floor.txt" 2>&1
import runpy
import sys

path = sys.argv[1]
sys.version_info = (3, 8, 0)
sys.argv = ["run_ledger.py", "--help"]
runpy.run_path(path, run_name="__main__")
PY
    if grep -q '3\.9' "$dir/floor.txt" && grep -q '3\.8' "$dir/floor.txt"; then ok "below 3.9 the ledger names the floor and the running version"; else bad "below 3.9 the ledger names the floor and the running version"; fi
}

scenario_phase_count() {
    dir="$1"
    mkdir -p "$dir"
    printf 'Phase 1: plan\nPhase 2: run\n' > "$dir/two.txt"
    printf 'Phase 1: plan\nPhase 2: run\nPhase 3: check\nPhase 4: report\n' > "$dir/four.txt"
    printf 'Phase 1: plan\n' > "$dir/one.txt"
    printf 'Phase 1: a\nPhase 2: b\nPhase 3: c\nPhase 4: d\nPhase 5: e\n' > "$dir/five.txt"
    printf 'I will work through three phases: discovery, dispatch, and synthesis.\n' > "$dir/prose.txt"
    printf '%s\n' 'Phases:' '- Discovery' '- Dispatch' '- Synthesis' > "$dir/bullets.txt"
    printf '%s\n' 'I will work through three phases:' '- Discovery' '- Dispatch' '- Synthesis' > "$dir/sentence-bullets.txt"
    printf '%s\n' '## Phases' '- Discovery' '- Dispatch' '- Synthesis' > "$dir/heading-bullets.txt"
    printf '%s\n' 'I will inspect the repository.' '- run the tests' '- read the docs' '- report back' > "$dir/unrelated-bullets.txt"
    printf '%s\n' 'This is one phase of the work.' '- alpha' '- beta' '- gamma' > "$dir/mention-bullets.txt"
    phase="$REPO_ROOT/tests/agent_spinner/evals/phase_plan.py"
    if "$PY" "$phase" "$dir/two.txt" >/dev/null 2>&1; then ok "phase count accepts two phases"; else bad "phase count accepts two phases"; fi
    if "$PY" "$phase" "$dir/four.txt" >/dev/null 2>&1; then ok "phase count accepts four phases"; else bad "phase count accepts four phases"; fi
    if "$PY" "$phase" "$dir/prose.txt" >/dev/null 2>&1; then ok "phase count accepts a prose three-phase sentence"; else bad "phase count accepts a prose three-phase sentence"; fi
    if "$PY" "$phase" "$dir/bullets.txt" >/dev/null 2>&1; then ok "phase count accepts a bulleted phase list"; else bad "phase count accepts a bulleted phase list"; fi
    if "$PY" "$phase" "$dir/one.txt" >/dev/null 2>&1; then bad "phase count rejects one phase"; else ok "phase count rejects one phase"; fi
    if "$PY" "$phase" "$dir/five.txt" >/dev/null 2>&1; then bad "phase count rejects five phases"; else ok "phase count rejects five phases"; fi
    if "$PY" "$phase" "$dir/sentence-bullets.txt" >/dev/null 2>&1; then ok "phase count accepts a colon-ended sentence over a bullet list"; else bad "phase count accepts a colon-ended sentence over a bullet list"; fi
    if "$PY" "$phase" "$dir/heading-bullets.txt" >/dev/null 2>&1; then ok "phase count accepts a markdown heading over a bullet list"; else bad "phase count accepts a markdown heading over a bullet list"; fi
    if "$PY" "$phase" "$dir/unrelated-bullets.txt" >/dev/null 2>&1; then bad "phase count rejects an unrelated bullet list"; else ok "phase count rejects an unrelated bullet list"; fi
    if "$PY" "$phase" "$dir/mention-bullets.txt" >/dev/null 2>&1; then bad "phase count rejects a bare phase mention over a bullet list"; else ok "phase count rejects a bare phase mention over a bullet list"; fi
}

scenario_exclude_prune() {
    dir="$1"
    setup_repo "$dir"
    if grep -q 'name .agent_spinner -prune' "$REPO_ROOT/Makefile"; then ok "EXCLUDE carries the .agent_spinner prune"; else bad "EXCLUDE carries the .agent_spinner prune"; fi
    if grep -q '.git_auto_review' "$REPO_ROOT/Makefile" && grep -qi 'review-and-fix' "$REPO_ROOT/Makefile"; then ok "the comment keeps the .git_auto_review rationale"; else bad "the comment keeps the .git_auto_review rationale"; fi
    check "tests/.gitignore is unchanged by the prune" grep -q 'workspace/' "$REPO_ROOT/tests/.gitignore"
}

scenario_docs() {
    dir="$1"
    mkdir -p "$dir"
    hits=$(grep -rniE --exclude-dir=workspace --exclude-dir=.eval_cache --exclude-dir=__pycache__ 'prose-only|no bundled scripts|bundles no (runtime )?scripts|ships no bundled' "$REPO_ROOT/tests/agent_spinner" "$REPO_ROOT/tests/README.md" "$REPO_ROOT/tests/CLAUDE.md" 2>/dev/null | grep -i 'agent_spinner' | grep -v 'script_tests/run.sh' | grep -v 'script_tests/ledger_run.sh' || true)
    if [ -z "$hits" ]; then ok "no agent_spinner line calls the skill prose-only or scriptless"; else bad "no agent_spinner line calls the skill prose-only or scriptless"; fi
    if grep -q 'ledger_run.sh' "$REPO_ROOT/tests/agent_spinner/README.md"; then ok "the README names ledger_run.sh"; else bad "the README names ledger_run.sh"; fi
    if grep -q 'ledger_run.sh' "$REPO_ROOT/tests/agent_spinner/RUNBOOK.md"; then ok "the RUNBOOK names ledger_run.sh as the third entrypoint"; else bad "the RUNBOOK names ledger_run.sh as the third entrypoint"; fi
    if grep -q 'run_ledger.py' "$REPO_ROOT/wiki/concepts/agent-delegated-automation.md"; then ok "the concept page names the run ledger"; else bad "the concept page names the run ledger"; fi
    proto="$REPO_ROOT/plugins/ai_dev/skills/agent_spinner/references/run-protocol.md"
    if "$PY" - "$proto" <<'PY'
import re
import sys

text = open(sys.argv[1]).read()
forks = re.search(r"^- `forks` is a list.*?(?=\n- |\n\n)", text, re.M | re.S)
cond10 = re.search(r"^10\. A changed path.*?(?=\n\n)", text, re.M | re.S)
if not forks or not cond10:
    raise SystemExit(1)
entry = forks.group(0)
clause = cond10.group(0)
ok = (
    "`path`" in entry
    and "condition 10" in entry
    and "`path` field" in clause
)
sys.exit(0 if ok else 1)
PY
    then
        ok "run-protocol names the fork path field that clears condition 10"
    else
        bad "run-protocol names the fork path field that clears condition 10"
    fi
}

scenario_markers() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --owned-target a.txt:task:task_finish >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    printf 'alpha\nbeta\ngamma\n' > "$dir/a.txt"
    ledger "$dir" diff >/dev/null 2>&1
    ledger "$dir" close > "$dir/close.txt" 2>&1
    rc=$?
    if [ "$rc" -eq 3 ] && grep -q 'condition 10' "$dir/close.txt" && grep -q 'a.txt' "$dir/close.txt"; then
        ok "a changed stamped path with no routing keeps close at exit 3 with the path named"
    else
        bad "a changed stamped path with no routing keeps close at exit 3 with the path named (rc=$rc)"
    fi
    ledger "$dir" status > "$dir/status.txt" 2>&1
    if grep -q 'a.txt family=task gate=task_finish' "$dir/status.txt"; then
        ok "status lists the stamped path awaiting routing"
    else
        bad "status lists the stamped path awaiting routing"
    fi
    if ledger "$dir" dispose --path a.txt --routed other_gate >/dev/null 2>&1; then
        bad "a routed disposition naming another gate is refused"
    else
        ok "a routed disposition naming another gate is refused"
    fi
    ledger "$dir" dispose --path a.txt --routed task_finish >/dev/null 2>&1
    ledger "$dir" close > "$dir/close2.txt" 2>&1
    if grep -q 'condition 10' "$dir/close2.txt"; then
        bad "a routed disposition naming the recorded owner clears condition 10"
    else
        ok "a routed disposition naming the recorded owner clears condition 10"
    fi

    dir="$dir/fork"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --owned-target a.txt:task:task_finish >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"forks":[{"issue":"Route a.txt or hold it?","options":[{"id":"route","text":"Route it","cost":"a hand-off"},{"id":"hold","text":"Hold it","cost":"a stale stamp"}],"passages":[{"text":"alpha","anchor":"a.txt:1"}],"preferred":"route","path":"a.txt"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    printf 'alpha\nbeta\ngamma\n' > "$dir/a.txt"
    ledger "$dir" diff >/dev/null 2>&1
    ledger "$dir" close > "$dir/close.txt" 2>&1
    if grep -q 'condition 10' "$dir/close.txt"; then
        bad "a fork record naming the path clears condition 10"
    else
        ok "a fork record naming the path clears condition 10"
    fi

    dir="$dir/fork-dot"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --owned-target a.txt:task:task_finish >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"forks":[{"issue":"Route a.txt or hold it?","options":[{"id":"route","text":"Route it","cost":"a hand-off"},{"id":"hold","text":"Hold it","cost":"a stale stamp"}],"passages":[{"text":"alpha","anchor":"a.txt:1"}],"preferred":"route","path":"./a.txt"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    printf 'alpha\nbeta\ngamma\n' > "$dir/a.txt"
    ledger "$dir" diff >/dev/null 2>&1
    ledger "$dir" close > "$dir/close.txt" 2>&1
    if grep -q 'condition 10' "$dir/close.txt"; then
        bad "a fork path of ./a.txt clears condition 10 for a.txt"
    else
        ok "a fork path of ./a.txt clears condition 10 for a.txt"
    fi

    dir="$dir/unchanged"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --owned-target a.txt:task:task_finish >/dev/null 2>&1
    ledger "$dir" diff >/dev/null 2>&1
    ledger "$dir" close > "$dir/close.txt" 2>&1
    if grep -q 'condition 10' "$dir/close.txt"; then
        bad "an unchanged stamped path needs no routing"
    else
        ok "an unchanged stamped path needs no routing"
    fi

    dir="$dir/unstamped"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    printf 'alpha\nbeta\ngamma\n' > "$dir/a.txt"
    ledger "$dir" diff >/dev/null 2>&1
    ledger "$dir" close > "$dir/close.txt" 2>&1
    if grep -q 'condition 10' "$dir/close.txt"; then
        bad "an unstamped changed path needs no routing"
    else
        ok "an unstamped changed path needs no routing"
    fi
}

scenario_checklist_lint() {
    dir="$1"
    setup_repo "$dir"
    cat > "$dir/spec.md" <<'MD'
# Spec

## Other

- An ignored item.

## Accept

- The first item lands.
- The second item lands.
MD
    ledger "$dir" init --unit check:c >/dev/null 2>&1
    if ledger "$dir" brief check:c --checker --body "1. The first item lands.
2. The second item lands." --acceptance "spec.md#Accept" >/dev/null 2>&1; then
        ok "a checklist covering every acceptance item verbatim renders"
    else
        bad "a checklist covering every acceptance item verbatim renders"
    fi
    if grep -q '"acceptance"' "$dir/.agent_spinner/roster.tsv"; then
        ok "the row records the acceptance source's version"
    else
        bad "the row records the acceptance source's version"
    fi
    if ledger "$dir" brief check:c --checker --body "1. The first item lands.
2. Something else entirely." --acceptance "spec.md#Accept" > "$dir/miss.txt" 2>&1; then
        bad "a brief missing one acceptance item is refused"
    else
        if grep -q 'The second item lands' "$dir/miss.txt"; then
            ok "a brief missing one acceptance item is refused with that item named"
        else
            bad "a brief missing one acceptance item is refused with that item named"
        fi
    fi
    if ledger "$dir" brief check:c --checker --body "1. The first item lands." --acceptance "spec.md#Accept" >/dev/null 2>&1; then
        bad "a brief with fewer lines than acceptance items is refused"
    else
        ok "a brief with fewer lines than acceptance items is refused"
    fi
    if ledger "$dir" brief check:c --checker --body "1. The first item lands.
2. The second item lands." --acceptance spec.md >/dev/null 2>&1; then
        bad "an unscoped source reads every list item"
    else
        ok "an unscoped source reads every list item"
    fi
}

scenario_packets() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"forks":[{"issue":"Keep the page or retire it?","options":[{"id":"o1","text":"Keep the page","cost":"one more edit"},{"id":"o2","text":"Retire the page","cost":"a dead link"}],"passages":[{"text":"alpha","anchor":"a.txt:1"},{"text":"beta","anchor":"a.txt:2"}],"preferred":"o2"}],"objections":[{"text":"the link graph still points at the page","fork":"0","option":"o2"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    if grep -q '"type": "objection"' "$dir/.agent_spinner/ledger.jsonl" && grep -q '"option": "o2"' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "an objections entry imports as an objection record"
    else
        bad "an objections entry imports as an objection record"
    fi
    ledger "$dir" dispose --id 'produce:a:forks:0' --disposition surfaced --packet pkt-1 --recommend "Option o2" --why "it removes the drift" >/dev/null 2>&1
    ledger "$dir" show --packet pkt-1 > "$dir/packet.txt" 2>&1
    if grep -q 'Decision packet: pkt-1' "$dir/packet.txt"; then ok "show --packet names the packet id"; else bad "show --packet names the packet id"; fi
    if grep -q 'Issue: Keep the page or retire it?' "$dir/packet.txt"; then ok "the packet carries the issue in one sentence"; else bad "the packet carries the issue in one sentence"; fi
    if grep -q 'anchor: a.txt:1' "$dir/packet.txt" && grep -q 'anchor: a.txt:2' "$dir/packet.txt"; then
        ok "both passages render with their anchors"
    else
        bad "both passages render with their anchors"
    fi
    if "$PY" - "$dir/packet.txt" "$dir/.agent_spinner/ledger.jsonl" <<'PY'
import json
import sys

packet_path, ledger_path = sys.argv[1:3]
records = [json.loads(line) for line in open(ledger_path) if line.strip()]
fork = [rec for rec in records if rec.get("type") == "fork"][0]
expected = [passage["text"] for passage in fork.get("passages") or []]
quoted = []
for line in open(packet_path).read().splitlines():
    if line.startswith('- "') and line.endswith('"'):
        quoted.append(line[3:-1])
sys.exit(0 if quoted == expected and expected else 1)
PY
    then
        ok "both passages render byte-identical to the fork record"
    else
        bad "both passages render byte-identical to the fork record"
    fi
    if grep -q 'id: o1' "$dir/packet.txt" && grep -q 'id: o2' "$dir/packet.txt" && grep -q 'Cost: a dead link' "$dir/packet.txt"; then
        ok "each option renders with its stable id and its cost"
    else
        bad "each option renders with its stable id and its cost"
    fi
    if grep -q 'Option o2: the link graph still points at the page' "$dir/packet.txt"; then
        ok "the objection renders under the second option"
    else
        bad "the objection renders under the second option"
    fi
    if grep -q "preferred end state (produce:a:forks:0)" "$dir/packet.txt" && grep -qF '"o2"' "$dir/packet.txt"; then
        ok "the helper's preferred end state is present"
    else
        bad "the helper's preferred end state is present"
    fi
    if grep -q 'Recommendation: Option o2' "$dir/packet.txt" && grep -q 'Reason: it removes the drift' "$dir/packet.txt"; then
        ok "the recommendation and reason close the packet"
    else
        bad "the recommendation and reason close the packet"
    fi
    if ledger "$dir" show --packet no-such-packet >/dev/null 2>&1; then
        bad "show --packet refuses an id with no surfaced fork"
    else
        ok "show --packet refuses an id with no surfaced fork"
    fi
    ledger "$dir" status > "$dir/status.txt" 2>&1
    if grep -q 'pkt-1' "$dir/status.txt"; then ok "status lists the open packet ids"; else bad "status lists the open packet ids"; fi
    ledger "$dir" close > "$dir/close.txt" 2>&1
    rc=$?
    if [ "$rc" -eq 3 ] && grep -q 'produce:a:objections:0' "$dir/close.txt"; then
        ok "an undisposed objection keeps close at exit 3"
    else
        bad "an undisposed objection keeps close at exit 3 (rc=$rc)"
    fi
    ledger "$dir" dispose --id 'produce:a:objections:0' --disposition applied >/dev/null 2>&1
    ledger "$dir" close > "$dir/close2.txt" 2>&1
    if grep -q 'produce:a:objections:0' "$dir/close2.txt"; then
        bad "a disposed objection leaves condition 2"
    else
        ok "a disposed objection leaves condition 2"
    fi

    dir="$dir/bad-option"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"forks":[{"issue":"Keep or retire?","options":[{"id":"o1","text":"Keep","cost":"one edit"},{"id":"o2","text":"Retire","cost":"a link"}],"passages":[{"text":"alpha","anchor":"a.txt:1"}],"preferred":"o1"}],"objections":[{"text":"a bad reference","fork":"0","option":"o9"}]}'
    ledger "$dir" accept produce:a > "$dir/accept.txt" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ] && grep -q 'o9' "$dir/accept.txt"; then
        ok "an objection naming an unknown option is refused with that option named"
    else
        bad "an objection naming an unknown option is refused with that option named (rc=$rc)"
    fi
}

write_format_a() {
    cat > "$1" <<'JSON'
{
  "match": {"kind": "call"},
  "calls": "call",
  "name": "tool",
  "args": "args",
  "kinds": {"read": ["reader"], "write": ["writer"], "shell": ["runner"], "spawn": ["spawner"]},
  "path_args": ["target"],
  "partial_args": ["partial"],
  "command_args": ["cmd"],
  "time": "at"
}
JSON
}

write_format_b() {
    cat > "$1" <<'JSON'
{
  "match": {"role": "assistant"},
  "calls": "message.content[]",
  "name": "name",
  "args": "input",
  "kinds": {"read": ["open_file"], "write": ["save_file"], "shell": ["run_cmd"], "spawn": ["fork_task"]},
  "path_args": ["path"],
  "partial_args": ["limit"],
  "command_args": ["command"],
  "time": "ts"
}
JSON
}

# write_shipped_claude_format <out> — copy the Claude Code description the
# delegation reference ships, so the own-session test reads the same format
# the orchestrator would pass as --log-format.
write_shipped_claude_format() {
    "$PY" - "$REPO_ROOT/plugins/ai_dev/skills/harness_portability/references/delegation-surfaces.md" "$1" <<'PY'
import json
import re
import sys

ref, out = sys.argv[1:3]
text = open(ref).read()
section = re.search(r"^## Claude Code\n(.*?)(?=^## )", text, re.M | re.S).group(1)
entry = re.search(r"\*\*Helper log format\.\*\*(.*?)(?=^- |\Z)", section, re.M | re.S).group(1)
block = re.search(r"```json\n(.*?)\n[ \t]*```", entry, re.S).group(1)
open(out, "w").write(json.dumps(json.loads(block)))
PY
}

audit_repo() {
    dir="$1"
    setup_repo "$dir"
    printf 'alpha\nbeta\n' > "$dir/a.txt"
    printf 'gamma\n' > "$dir/b.txt"
    printf 'delta\n' > "$dir/c.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "audit files"
    ledger "$dir" init --unit produce:a --unit-path produce:a=a.txt >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "Read a.txt and b.txt." --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
}

scenario_audit() {
    dir="$1"
    audit_repo "$dir"
    write_format_a "$dir/fmt-a.json"
    cat > "$dir/log-a.jsonl" <<'LOG'
{"kind": "call", "at": "2026-01-01T00:00:00+00:00", "call": {"tool": "reader", "args": {"target": "a.txt"}}}
{"kind": "call", "at": "2026-01-01T00:00:01+00:00", "call": {"tool": "reader", "args": {"target": "b.txt", "partial": true}}}
{"kind": "call", "at": "2026-01-01T00:00:02+00:00", "call": {"tool": "reader", "args": {"target": "c.txt"}}}
{"kind": "call", "at": "2026-01-01T00:00:03+00:00", "call": {"tool": "writer", "args": {"target": "d.txt"}}}
{"kind": "call", "at": "2026-01-01T00:00:04+00:00", "call": {"tool": "runner", "args": {"cmd": "printf hi"}}}
LOG
    ledger "$dir" accept produce:a --log "$dir/log-a.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1
    if "$PY" - "$dir/.agent_spinner/ledger.jsonl" <<'PY'
import json
import sys

records = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
audit = [rec for rec in records if rec.get("type") == "audit"][-1]
sys.exit(0 if "a.txt" in audit["full_reads"] and "b.txt" not in audit["full_reads"] else 1)
PY
    then
        ok "format A records a full read as tool evidence"
    else
        bad "format A records a full read as tool evidence"
    fi
    if "$PY" - "$dir/.agent_spinner/ledger.jsonl" <<'PY'
import json
import sys

records = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
audit = [rec for rec in records if rec.get("type") == "audit"][-1]
sys.exit(0 if "b.txt" in audit["partial_reads"] else 1)
PY
    then
        ok "format A leaves a ranged read out of tool evidence"
    else
        bad "format A leaves a ranged read out of tool evidence"
    fi
    if "$PY" - "$dir/.agent_spinner/ledger.jsonl" <<'PY'
import json
import sys

records = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
audit = [rec for rec in records if rec.get("type") == "audit"][-1]
sys.exit(0 if "c.txt" in audit["outside_reads"] else 1)
PY
    then
        ok "format A records a read outside the admitted inputs"
    else
        bad "format A records a read outside the admitted inputs"
    fi
    if grep -q '"ledger_calls": \[\]' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "a shell command that invokes no ledger records no containment incident"
    else
        bad "a shell command that invokes no ledger records no containment incident"
    fi

    dir="$dir/format-b"
    audit_repo "$dir"
    write_format_b "$dir/fmt-b.json"
    cat > "$dir/log-b.jsonl" <<'LOG'
{"role": "assistant", "ts": "2026-01-01T00:00:00+00:00", "message": {"content": [{"name": "open_file", "input": {"path": "a.txt"}}, {"name": "open_file", "input": {"path": "b.txt", "limit": 3}}, {"name": "save_file", "input": {"path": "d.txt"}}]}}
LOG
    ledger "$dir" accept produce:a --log "$dir/log-b.jsonl" --log-format "$dir/fmt-b.json" >/dev/null 2>&1
    if "$PY" - "$dir/.agent_spinner/ledger.jsonl" <<'PY'
import json
import sys

records = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
audit = [rec for rec in records if rec.get("type") == "audit"][-1]
ok = "a.txt" in audit["full_reads"] and "b.txt" in audit["partial_reads"] and "b.txt" not in audit["full_reads"]
sys.exit(0 if ok else 1)
PY
    then
        ok "format B reads several calls in one record and splits full from ranged reads"
    else
        bad "format B reads several calls in one record and splits full from ranged reads"
    fi

    dir="$dir/bad-format"
    audit_repo "$dir"
    printf 'not json\n' > "$dir/bad.json"
    if ledger "$dir" accept produce:a --log "$dir/log-a.jsonl" --log-format "$dir/bad.json" >/dev/null 2>&1; then
        bad "a malformed description is refused"
    else
        ok "a malformed description is refused"
    fi
    write_format_a "$dir/fmt-a.json"
    if ledger "$dir" accept produce:a --log "$dir/no-such-log.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1; then
        bad "an unreadable log is refused"
    else
        ok "an unreadable log is refused"
    fi
    cat > "$dir/no-match.jsonl" <<'LOG'
{"kind": "other", "at": "2026-01-01T00:00:00+00:00", "call": {"tool": "reader", "args": {"target": "a.txt"}}}
LOG
    if ledger "$dir" accept produce:a --log "$dir/no-match.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1; then
        bad "a description that matches no call is refused"
    else
        ok "a description that matches no call is refused"
    fi

    dir="$dir/unchanged"
    audit_repo "$dir"
    write_format_a "$dir/fmt-a.json"
    cp "$dir/.agent_spinner/returns/produce:a.md" "$dir/before.md"
    before_state=$(awk -F'\t' '$1=="produce:a" {print $7}' "$dir/.agent_spinner/roster.tsv")
    cat > "$dir/log.jsonl" <<'LOG'
{"kind": "call", "at": "2026-01-01T00:00:00+00:00", "call": {"tool": "reader", "args": {"target": "a.txt"}}}
LOG
    ledger "$dir" accept produce:a --log "$dir/log.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1
    after_state=$(awk -F'\t' '$1=="produce:a" {print $7}' "$dir/.agent_spinner/roster.tsv")
    if [ "$before_state" = "accepted" ] && [ "$after_state" = "accepted" ]; then
        ok "an audit on an accepted row leaves its state unchanged"
    else
        bad "an audit on an accepted row leaves its state unchanged"
    fi
    if cmp -s "$dir/before.md" "$dir/.agent_spinner/returns/produce:a.md"; then
        ok "an audit leaves returns/<label>.md byte-identical"
    else
        bad "an audit leaves returns/<label>.md byte-identical"
    fi

    dir="$dir/incident"
    audit_repo "$dir"
    write_format_a "$dir/fmt-a.json"
    cat > "$dir/log.jsonl" <<'LOG'
{"kind": "call", "at": "2026-01-01T00:00:00+00:00", "call": {"tool": "runner", "args": {"cmd": "python3 run_ledger.py status"}}}
{"kind": "call", "at": "2026-01-01T00:00:01+00:00", "call": {"tool": "spawner", "args": {}}}
LOG
    ledger "$dir" accept produce:a --log "$dir/log.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1
    if [ "$(grep -c '"type": "incident"' "$dir/.agent_spinner/ledger.jsonl")" -eq 2 ]; then
        ok "a ledger invocation and a spawn call each record an incident"
    else
        bad "a ledger invocation and a spawn call each record an incident"
    fi
    ledger "$dir" close > "$dir/close.txt" 2>&1
    rc=$?
    if [ "$rc" -eq 3 ] && grep -q 'condition 2' "$dir/close.txt"; then
        ok "an audit incident keeps close refusing"
    else
        bad "an audit incident keeps close refusing (rc=$rc)"
    fi
    ledger "$dir" dispose --id 'produce:a:audit-incidents:0' --disposition applied >/dev/null 2>&1
    ledger "$dir" dispose --id 'produce:a:audit-incidents:1' --disposition refuted >/dev/null 2>&1
    ledger "$dir" close > "$dir/close-disposed.txt" 2>&1
    if grep -q 'produce:a:audit-incidents' "$dir/close-disposed.txt"; then
        bad "disposing both audit incidents clears them from close"
    else
        ok "disposing both audit incidents clears them from close"
    fi

    dir="$dir/blind"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    printf 'the withheld hypothesis\n' | ledger "$dir" brief produce:a --body "Read a.txt." --withheld >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    write_format_a "$dir/fmt-a.json"
    cat > "$dir/inside.jsonl" <<'LOG'
{"kind": "call", "at": "2026-01-01T00:00:00+00:00", "call": {"tool": "reader", "args": {"target": "a.txt"}}}
LOG
    ledger "$dir" accept produce:a --log "$dir/inside.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1
    if grep -q '"blind": "blind by log"' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "a blind row whose log stays inside its admitted inputs is blind by log"
    else
        bad "a blind row whose log stays inside its admitted inputs is blind by log"
    fi
    cat > "$dir/outside.jsonl" <<'LOG'
{"kind": "call", "at": "2026-01-01T00:00:00+00:00", "call": {"tool": "reader", "args": {"target": "c.txt"}}}
LOG
    ledger "$dir" accept produce:a --log "$dir/outside.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1
    if grep -q '"blind": "blind by prompt"' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "a blind row that read an outside path stays blind by prompt"
    else
        bad "a blind row that read an outside path stays blind by prompt"
    fi

    dir="$dir/no-audit"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    printf 'the withheld hypothesis\n' | ledger "$dir" brief produce:a --body "Read a.txt." --withheld >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" status > "$dir/status.txt" 2>&1
    if grep -q 'produce:a blind by prompt' "$dir/status.txt"; then
        ok "a blind row with no audit stays blind by prompt"
    else
        bad "a blind row with no audit stays blind by prompt"
    fi

    dir="$dir/inline-floor-blind"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a >/dev/null 2>&1
    printf 'the withheld hypothesis\n' | ledger "$dir" brief produce:a --body "Read a.txt." --withheld >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    write_format_a "$dir/fmt-a.json"
    "$PY" - "$dir/.agent_spinner/roster.tsv" "$dir/log.jsonl" <<'PY'
import json
import sys

roster, log = sys.argv[1:3]
returned = ""
for line in open(roster, newline=""):
    parts = line.rstrip("\n").split("\t")
    if parts and parts[0] == "produce:a":
        returned = parts[18]
record = {
    "kind": "call",
    "at": returned,
    "call": {"tool": "reader", "args": {"target": "a.txt"}},
}
open(log, "w").write(json.dumps(record) + "\n")
PY
    ledger "$dir" accept produce:a --log "$dir/log.jsonl" --log-format "$dir/fmt-a.json" --own-session >/dev/null 2>&1
    ledger "$dir" status > "$dir/status.txt" 2>&1
    if grep -q 'produce:a blind by prompt' "$dir/status.txt" && ! grep -q '"blind": "blind by log"' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "a blind row audited with --own-session at the inline floor stays blind by prompt"
    else
        bad "a blind row audited with --own-session at the inline floor stays blind by prompt"
    fi
    if grep -q '"full_reads": \["a.txt"\]' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "an inline-floor blind row's audit still records its tool evidence"
    else
        bad "an inline-floor blind row's audit still records its tool evidence"
    fi

    dir="$dir/brief-names"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit-path produce:a=a.txt >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "Read a.txt and b.txt." --target a.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    write_format_a "$dir/fmt-a.json"
    cat > "$dir/log.jsonl" <<'LOG'
{"kind": "call", "at": "2026-01-01T00:00:00+00:00", "call": {"tool": "reader", "args": {"target": "a.txt"}}}
{"kind": "call", "at": "2026-01-01T00:00:01+00:00", "call": {"tool": "reader", "args": {"target": "b.txt"}}}
LOG
    ledger "$dir" accept produce:a --log "$dir/log.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1
    if grep -q '"outside_reads": \[\]' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "a helper that reads two files its brief names records no outside read"
    else
        bad "a helper that reads two files its brief names records no outside read"
    fi

    dir="$dir/admitted"
    setup_repo "$dir"
    printf 'all:\n\t@echo hi\n' > "$dir/Makefile"
    cat > "$dir/spec.md" <<'MD'
# Spec

## Accept

- The item lands.
MD
    git -C "$dir" add -A
    git -C "$dir" commit -qm "admitted inputs"
    ledger "$dir" init --unit check:c --bound 60 >/dev/null 2>&1
    ledger "$dir" brief check:c --checker --body "1. The item lands. Makefile." --acceptance spec.md >/dev/null 2>&1
    ledger "$dir" dispatch check:c >/dev/null 2>&1
    token=$(token_of "$dir" check:c)
    emit_return "$dir" check:c "$token" '{}'
    ledger "$dir" accept check:c >/dev/null 2>&1
    write_format_a "$dir/fmt-a.json"
    cat > "$dir/log.jsonl" <<'LOG'
{"kind": "call", "at": "2026-01-01T00:00:00+00:00", "call": {"tool": "reader", "args": {"target": "Makefile"}}}
{"kind": "call", "at": "2026-01-01T00:00:01+00:00", "call": {"tool": "reader", "args": {"target": "spec.md"}}}
LOG
    ledger "$dir" accept check:c --log "$dir/log.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1
    if "$PY" - "$dir/.agent_spinner/ledger.jsonl" <<'PY'
import json
import sys

records = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
audit = [rec for rec in records if rec.get("type") == "audit"][-1]
sys.exit(0 if audit["outside_reads"] == [] and set(audit["full_reads"]) == {"Makefile", "spec.md"} else 1)
PY
    then
        ok "the recorded acceptance source and an extensionless brief path are admitted inputs"
    else
        bad "the recorded acceptance source and an extensionless brief path are admitted inputs"
    fi

    dir="$dir/own-session"
    setup_repo "$dir"
    printf 'delta\n' > "$dir/c.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "inline-floor input"
    ledger "$dir" init --unit produce:a --unit produce:b --unit produce:c --unit-path produce:a=a.txt --unit-path produce:b=b.txt --unit-path produce:c=c.txt --bound 60 >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "Read a.txt." --target a.txt >/dev/null 2>&1
    ledger "$dir" brief produce:b --body "Read b.txt." --target b.txt >/dev/null 2>&1
    ledger "$dir" brief produce:c --body "Read c.txt." --target c.txt >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    ledger "$dir" dispatch produce:b >/dev/null 2>&1
    token_a=$(token_of "$dir" produce:a)
    token_b=$(token_of "$dir" produce:b)
    token_c=$(token_of "$dir" produce:c)
    emit_return "$dir" produce:a "$token_a" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    emit_return "$dir" produce:b "$token_b" '{"examined":[{"path":"b.txt","how":"full","receipt":"gamma"}]}'
    emit_return "$dir" produce:c "$token_c" '{"examined":[{"path":"c.txt","how":"full","receipt":"delta"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" accept produce:b >/dev/null 2>&1
    ledger "$dir" accept produce:c >/dev/null 2>&1
    "$PY" - "$dir/.agent_spinner/roster.tsv" "$dir/.agent_spinner/briefs/produce:c.txt" <<'PY'
import calendar
import os
import sys

path, brief = sys.argv[1:3]
rows = []
for line in open(path, newline=""):
    parts = line.rstrip("\n").split("\t")
    if parts and parts[0] == "produce:a":
        parts[16] = "2026-01-01T00:00:00+00:00"
        parts[17] = ""
        parts[18] = "2026-01-01T00:10:00+00:00"
    elif parts and parts[0] == "produce:b":
        parts[16] = "2026-01-01T00:20:00+00:00"
        parts[17] = ""
        parts[18] = "2026-01-01T00:30:00+00:00"
    elif parts and parts[0] == "produce:c":
        # An inline-floor row: it never dispatched and wrote no start marker,
        # so its lower bound is its brief file's modification time.
        parts[16] = ""
        parts[17] = ""
        parts[18] = "2026-01-01T00:40:00+00:00"
    rows.append("\t".join(parts))
open(path, "w").write("\n".join(rows) + "\n")
os.utime(brief, (calendar.timegm((2026, 1, 1, 0, 35, 0, 0, 0, 0)),) * 2)
PY
    write_shipped_claude_format "$dir/claude.json"
    cat > "$dir/session.jsonl" <<'LOG'
{"isSidechain": true, "timestamp": "2026-01-01T00:05:00+00:00", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "a.txt"}}, {"type": "tool_use", "name": "Bash", "input": {"command": "python3 run_ledger.py status"}}, {"type": "tool_use", "name": "Read", "input": {"file_path": "c.txt"}}]}}
{"isSidechain": true, "timestamp": "2026-01-01T00:25:00+00:00", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "b.txt"}}]}}
{"isSidechain": true, "timestamp": "2026-01-01T00:36:00+00:00", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "c.txt"}}]}}
LOG
    ledger "$dir" accept produce:a --log "$dir/session.jsonl" --log-format "$dir/claude.json" --own-session >/dev/null 2>&1
    ledger "$dir" accept produce:b --log "$dir/session.jsonl" --log-format "$dir/claude.json" --own-session >/dev/null 2>&1
    ledger "$dir" accept produce:c --log "$dir/session.jsonl" --log-format "$dir/claude.json" --own-session >/dev/null 2>&1
    if grep -q '"own_session": true' "$dir/.agent_spinner/ledger.jsonl" && ! grep -q '"type": "incident"' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "an own-session audit records no containment incident"
    else
        bad "an own-session audit records no containment incident"
    fi
    if grep -q '"outside_reads": \[\]' "$dir/.agent_spinner/ledger.jsonl"; then
        ok "an own-session audit records no outside read"
    else
        bad "an own-session audit records no outside read"
    fi
    if "$PY" - "$dir/.agent_spinner/ledger.jsonl" <<'PY'
import json
import sys

records = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
audits = {}
for rec in records:
    if rec.get("type") == "audit":
        audits[rec["label"]] = rec
a = audits.get("produce:a", {}).get("full_reads", [])
b = audits.get("produce:b", {}).get("full_reads", [])
c = audits.get("produce:c", {}).get("full_reads", [])
ok = "a.txt" in a and "b.txt" not in a and b == ["b.txt"] and c == ["c.txt"]
sys.exit(0 if ok else 1)
PY
    then
        ok "two dispatched rows and one inline-floor row count only the reads inside their own window"
    else
        bad "two dispatched rows and one inline-floor row count only the reads inside their own window"
    fi
}

scenario_own_session_windows() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:s --unit produce:m --unit-path produce:s=a.txt --unit-path produce:m=b.txt --bound 60 >/dev/null 2>&1
    ledger "$dir" brief produce:s --body "Read a.txt." --target a.txt >/dev/null 2>&1
    ledger "$dir" brief produce:m --body "Read b.txt." --target b.txt >/dev/null 2>&1
    token_s=$(token_of "$dir" produce:s)
    token_m=$(token_of "$dir" produce:m)
    emit_return "$dir" produce:s "$token_s" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    emit_return "$dir" produce:m "$token_m" '{"examined":[{"path":"b.txt","how":"full","receipt":"gamma"}]}'
    touch "$dir/.agent_spinner/returns/produce:s.start"
    ledger "$dir" accept produce:s >/dev/null 2>&1
    ledger "$dir" accept produce:m >/dev/null 2>&1
    "$PY" - "$dir/.agent_spinner/roster.tsv" "$dir/.agent_spinner/briefs/produce:m.txt" <<'PY'
import calendar
import os
import sys

path, brief = sys.argv[1:3]
rows = []
for line in open(path, newline=""):
    parts = line.rstrip("\n").split("\t")
    if parts and parts[0] == "produce:s":
        # No dispatch, but a start marker: the window starts at the marker.
        parts[16] = ""
        parts[17] = "2026-01-01T00:10:00+00:00"
        parts[18] = "2026-01-01T00:20:00+00:00"
    elif parts and parts[0] == "produce:m":
        # Neither dispatch nor start marker: the window starts at the brief's
        # modification time.
        parts[16] = ""
        parts[17] = ""
        parts[18] = "2026-01-01T00:40:00+00:00"
    rows.append("\t".join(parts))
open(path, "w").write("\n".join(rows) + "\n")
os.utime(brief, (calendar.timegm((2026, 1, 1, 0, 30, 0, 0, 0, 0)),) * 2)
PY
    write_shipped_claude_format "$dir/claude.json"
    cat > "$dir/session.jsonl" <<'LOG'
{"isSidechain": true, "timestamp": "2026-01-01T00:05:00+00:00", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "before-s.txt"}}]}}
{"isSidechain": true, "timestamp": "2026-01-01T00:15:00+00:00", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "inside-s.txt"}}]}}
{"isSidechain": true, "timestamp": "2026-01-01T00:25:00+00:00", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "before-m.txt"}}]}}
{"isSidechain": true, "timestamp": "2026-01-01T00:35:00+00:00", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "inside-m.txt"}}]}}
LOG
    ledger "$dir" accept produce:s --log "$dir/session.jsonl" --log-format "$dir/claude.json" --own-session >/dev/null 2>&1
    ledger "$dir" accept produce:m --log "$dir/session.jsonl" --log-format "$dir/claude.json" --own-session >/dev/null 2>&1
    if "$PY" - "$dir/.agent_spinner/ledger.jsonl" <<'PY'
import json
import sys

records = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
audits = {}
for rec in records:
    if rec.get("type") == "audit":
        audits[rec["label"]] = rec
s = audits.get("produce:s", {}).get("full_reads", [])
m = audits.get("produce:m", {}).get("full_reads", [])
sys.exit(0 if s == ["inside-s.txt"] and m == ["inside-m.txt"] else 1)
PY
    then
        ok "an own-session window falls back to the start marker, then the brief's mtime"
    else
        bad "an own-session window falls back to the start marker, then the brief's mtime"
    fi
}

scenario_objection_close() {
    dir="$1"
    setup_repo "$dir"
    ledger "$dir" init --unit produce:a --unit check:b --unit-path produce:a=a.txt --unit-path check:b=a.txt --bound 60 >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "A" --target a.txt --depth 2 >/dev/null 2>&1
    ledger "$dir" dispatch produce:a >/dev/null 2>&1
    token=$(token_of "$dir" produce:a)
    emit_return "$dir" produce:a "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}],"forks":[{"issue":"Keep or retire the page?","options":[{"id":"o1","text":"Keep","cost":"one edit"},{"id":"o2","text":"Retire","cost":"a link"}],"passages":[{"text":"alpha","anchor":"a.txt:1"}],"preferred":"o2"}],"objections":[{"text":"the link graph still points here","fork":"0","option":"o2"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    printf 'alpha\nbeta\ngamma\n' > "$dir/a.txt"
    ledger "$dir" brief check:b --body "B" --target a.txt --relay produce:a --depth 2 --obligation a.txt >/dev/null 2>&1
    ledger "$dir" dispatch check:b >/dev/null 2>&1
    token=$(token_of "$dir" check:b)
    emit_return "$dir" check:b "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"gamma"}]}'
    ledger "$dir" accept check:b >/dev/null 2>&1
    ledger "$dir" diff --add-checks >/dev/null 2>&1
    ledger "$dir" brief check:a.txt --body "C" --target a.txt --depth 2 --obligation a.txt >/dev/null 2>&1
    ledger "$dir" dispatch check:a.txt >/dev/null 2>&1
    token=$(token_of "$dir" check:a.txt)
    emit_return "$dir" check:a.txt "$token" '{"examined":[{"path":"a.txt","how":"full","receipt":"gamma"}]}'
    ledger "$dir" accept check:a.txt >/dev/null 2>&1
    ledger "$dir" dispose --id 'produce:a:forks:0' --disposition surfaced --packet pkt-c >/dev/null 2>&1
    ledger "$dir" close 2>/dev/null | sed -n '/TALLY-BEGIN/,/TALLY-END/p' > "$dir/.agent_spinner/report.md"
    printf '\n# Report\n\nAll clear.\n' >> "$dir/.agent_spinner/report.md"
    ledger "$dir" close > "$dir/.agent_spinner/close.out" 2>&1
    rc=$?
    if [ "$rc" -eq 3 ] && grep -q 'produce:a:objections:0' "$dir/.agent_spinner/close.out"; then
        ok "an objection with no disposition keeps close at exit 3"
    else
        bad "an objection with no disposition keeps close at exit 3 (rc=$rc)"
    fi
    ledger "$dir" dispose --id 'produce:a:objections:0' --disposition applied >/dev/null 2>&1
    if ledger "$dir" close >/dev/null 2>&1; then
        ok "close reaches exit 0 once the objection is disposed"
    else
        bad "close reaches exit 0 once the objection is disposed"
    fi
}

scenario_tally_coverage() {
    dir="$1"
    setup_repo "$dir"
    printf 'delta\n' > "$dir/c.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "coverage inputs"
    ledger "$dir" init --unit produce:a --unit produce:b --unit produce:c --unit-path produce:a=a.txt --unit-path produce:b=b.txt --unit-path produce:c=c.txt --bound 60 --wave 3 >/dev/null 2>&1
    ledger "$dir" brief produce:a --body "Read a.txt." --target a.txt >/dev/null 2>&1
    ledger "$dir" brief produce:b --body "Read b.txt." --target b.txt >/dev/null 2>&1
    ledger "$dir" brief produce:c --body "Read c.txt." --target c.txt >/dev/null 2>&1
    for label in produce:a produce:b produce:c; do
        ledger "$dir" dispatch "$label" >/dev/null 2>&1
    done
    token_a=$(token_of "$dir" produce:a)
    token_b=$(token_of "$dir" produce:b)
    token_c=$(token_of "$dir" produce:c)
    emit_return "$dir" produce:a "$token_a" '{"examined":[{"path":"a.txt","how":"full","receipt":"alpha"}]}'
    emit_return "$dir" produce:b "$token_b" '{"examined":[{"path":"b.txt","how":"searched","receipt":"gamma"}]}'
    emit_return "$dir" produce:c "$token_c" '{"examined":[{"path":"c.txt","how":"unreachable","receipt":"delta"}]}'
    ledger "$dir" accept produce:a >/dev/null 2>&1
    ledger "$dir" accept produce:b >/dev/null 2>&1
    ledger "$dir" accept produce:c >/dev/null 2>&1
    write_format_a "$dir/fmt-a.json"
    cat > "$dir/log.jsonl" <<'LOG'
{"kind": "call", "at": "2026-01-01T00:00:00+00:00", "call": {"tool": "reader", "args": {"target": "a.txt"}}}
LOG
    ledger "$dir" accept produce:a --log "$dir/log.jsonl" --log-format "$dir/fmt-a.json" >/dev/null 2>&1
    ledger "$dir" close 2>/dev/null | sed -n '/TALLY-BEGIN/,/TALLY-END/p' > "$dir/tally.txt"
    if grep -q 'coverage-full-by-tool 1' "$dir/tally.txt" && grep -q 'coverage-receipt-only 0' "$dir/tally.txt"; then
        ok "the tally splits tool evidence from receipt-only coverage"
    else
        bad "the tally splits tool evidence from receipt-only coverage"
    fi
    if grep -q 'coverage-searched 1' "$dir/tally.txt" && grep -q 'coverage-unexamined 1' "$dir/tally.txt"; then
        ok "the tally counts searched and unexamined entries"
    else
        bad "the tally counts searched and unexamined entries"
    fi
}

scenario_log_format_docs() {
    dir="$1"
    mkdir -p "$dir"
    ref="$REPO_ROOT/plugins/ai_dev/skills/harness_portability/references/delegation-surfaces.md"
    if "$PY" - "$ref" "$LEDGER" <<'PY'
import importlib.util
import json
import re
import sys

sys.dont_write_bytecode = True

ref, ledger = sys.argv[1:3]
spec = importlib.util.spec_from_file_location("run_ledger", ledger)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

text = open(ref).read()
errors = []


def section(name):
    pattern = re.compile(r"^## %s\n(.*?)(?=^## |\Z)" % re.escape(name), re.M | re.S)
    match = pattern.search(text)
    return match.group(1) if match else ""


def delivery(name):
    body = section(name)
    match = re.search(r"^### Delivery and concurrency\n(.*?)(?=^### |\Z)", body, re.M | re.S)
    return match.group(1) if match else ""


for host, log_hint in (("Claude Code", "subagents/agent-"), ("Cursor", "agent-transcripts/")):
    body = section(host)
    subs = re.findall(r"^### ", body, re.M)
    if len(subs) != 5:
        errors.append("%s holds %d subsections, expected 5" % (host, len(subs)))
    entry = delivery(host)
    marker = entry.find("**Helper log format.**")
    if marker == -1:
        errors.append("%s has no Helper log format entry" % host)
        continue
    tail = entry[marker:]
    if log_hint not in tail:
        errors.append("%s entry does not name the log it reads" % host)
    for needle in ("Observed 2026-", "build", "result"):
        if needle not in tail:
            errors.append("%s entry records no %s" % (host, needle))
    block = re.search(r"^[ \t]*```json\n(.*?)\n[ \t]*```", tail, re.S | re.M)
    if not block:
        errors.append("%s entry carries no json description" % host)
        continue
    try:
        data = json.loads(block.group(1))
    except ValueError as exc:
        errors.append("%s description is not json: %s" % (host, exc))
        continue
    path = "/tmp/ledger-format-%s.json" % host.replace(" ", "-").lower()
    open(path, "w").write(json.dumps(data))
    try:
        mod.load_log_format(path)
    except SystemExit:
        errors.append("%s description does not parse in the ledger" % host)
    if not data.get("calls") or not data.get("kinds"):
        errors.append("%s description names no calls or kinds" % host)

if errors:
    for error in errors:
        sys.stderr.write("%s\n" % error)
    raise SystemExit(1)
PY
    then
        ok "each delegation-surfaces log-format entry parses and names its log"
    else
        bad "each delegation-surfaces log-format entry parses and names its log"
    fi
}

# --- runner -----------------------------------------------------------------

run_all_scenarios() {
    root="$1"
    mkdir -p "$root"
    scenario_help "$root/help"
    scenario_slugs "$root/slugs"
    scenario_probe "$root/probe"
    scenario_brief_lint "$root/brief-lint"
    scenario_dispatch "$root/dispatch"
    scenario_spawn_recording "$root/spawn"
    scenario_rejection "$root/rejection"
    scenario_joins "$root/joins"
    scenario_diff "$root/diff"
    scenario_nonrepo_walk "$root/nonrepo"
    scenario_small_return "$root/small-return"
    scenario_approved_edits "$root/approved"
    scenario_counters "$root/counters"
    scenario_gate_expect "$root/gate-expect"
    scenario_close_conditions "$root/close"
    scenario_run_directory "$root/run-directory"
    scenario_repo_safety "$root/repo-safety"
    scenario_accept_stdin "$root/accept-stdin"
    scenario_attach "$root/attach"
    scenario_rows "$root/rows"
    scenario_show_search "$root/show-search"
    scenario_snapshot "$root/snapshot"
    scenario_status "$root/status"
    scenario_no_helper "$root/no-helper"
    scenario_gate_scope "$root/gate-scope"
    scenario_hostile_git "$root/hostile-git"
    scenario_recorded_versions "$root/recorded-versions"
    scenario_recall_tags "$root/recall-tags"
    scenario_start_markers "$root/start-markers"
    scenario_markers "$root/markers"
    scenario_checklist_lint "$root/checklist"
    scenario_packets "$root/packets"
    scenario_objection_close "$root/objection-close"
    scenario_audit "$root/audit"
    scenario_own_session_windows "$root/own-session-windows"
    scenario_tally_coverage "$root/tally-coverage"
    scenario_log_format_docs "$root/log-format-docs"
    scenario_version_floor "$root/version-floor"
    scenario_phase_count "$root/phase-count"
    scenario_exclude_prune "$root/exclude-prune"
    scenario_docs "$root/docs"
}

main() {
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                cat <<USAGE
Usage: bash tests/agent_spinner/script_tests/ledger_run.sh

Runs the run-ledger script tests under the oldest and newest python3 on the
machine. Each scenario stages its own repository under script_tests/scratch/.
USAGE
                exit 0
                ;;
        esac
    done

    rm -rf "$SCRATCH"
    write_helper_files

    versions="$(python_versions)"
    if [ -z "$versions" ]; then
        printf 'ledger_run.sh: no python3 found\n' >&2
        exit 1
    fi

    count=$(printf '%s\n' "$versions" | wc -l | tr -d ' ')
    oldest_line=$(printf '%s\n' "$versions" | head -1)
    newest_line=$(printf '%s\n' "$versions" | tail -1)
    oldest_version=${oldest_line%% *}
    oldest_path=${oldest_line#* }
    newest_version=${newest_line%% *}
    newest_path=${newest_line#* }

    printf 'ledger_run: oldest python3 %s (%s)\n' "$oldest_version" "$oldest_path"
    printf 'ledger_run: newest python3 %s (%s)\n' "$newest_version" "$newest_path"
    if [ "$count" -eq 1 ]; then
        printf 'ledger_run: only one python3 found; running once\n'
    fi

    run_one() {
        version="$1"
        path="$2"
        printf '\n=== python %s ===\n' "$version"
        PY="$path"
        export PY
        run_all_scenarios "$SCRATCH/py-$version"
    }

    run_one "$oldest_version" "$oldest_path"
    if [ "$count" -gt 1 ] && [ "$oldest_path" != "$newest_path" ]; then
        run_one "$newest_version" "$newest_path"
    fi

    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    if [ "$FAIL" -gt 0 ]; then
        printf 'failures:\n'
        printf '%s' "$FAILURES" | while IFS= read -r line; do
            [ -n "$line" ] && printf '  - %s\n' "$line"
        done
        exit 1
    fi
    exit 0
}

main "$@"
