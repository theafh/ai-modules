#!/usr/bin/env bash
# Bundled-script unit tests for scripts/lint_frontmatter.py.
#
# Every scenario stages its fixture in a temporary directory outside the
# checkout, so a broken fixture never reaches the tracked tree. The harness
# proves the strict YAML subset rejects each shape the task names, accepts
# every shape the repository uses, decodes values under --values, excludes
# tests/ from the default file set while reporting an explicit path there,
# and runs skill_doctor's discovery_safety.py in place over SKILL.md files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CHECK="$REPO_ROOT/scripts/lint_frontmatter.py"
DISCOVERY_DIR="$REPO_ROOT/plugins/ai_dev/skills/skill_doctor/scripts"

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
WORK="$(mktemp -d "$TMP_BASE/lint_frontmatter.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
FAILED_IDS=()

pass() {
    PASS=$((PASS + 1))
    printf 'PASS %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    FAILED_IDS+=("$1")
    printf 'FAIL %s\n' "$1"
    [ -n "${2:-}" ] && printf '     %s\n' "$2"
    return 0
}

# Fixed-string containment without a pipe. `printf ... | grep -q` closes the
# pipe early, and with `set -o pipefail` that SIGPIPE turns a match into a
# failure on large output.
has() {
    case "$1" in
        *"$2"*) return 0 ;;
        *) return 1 ;;
    esac
}

has_ci() {
    local haystack lowered needle_lowered
    haystack="$1"
    needle_lowered="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
    lowered="$(printf '%s' "$haystack" | tr '[:upper:]' '[:lower:]')"
    has "$lowered" "$needle_lowered"
}

# expect_fail <id> <path> [needle]
# The run must exit non-zero, name the path, and (when given) mention needle.
expect_fail() {
    local id="$1"
    local path="$2"
    local needle="${3:-}"
    local out rc
    out="$(python3 "$CHECK" "$path" 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        fail "$id" "expected a non-zero exit"
        return
    fi
    if ! has "$out" "$path"; then
        fail "$id" "finding does not name $path: $out"
        return
    fi
    if [ -n "$needle" ] && ! has_ci "$out" "$needle"; then
        fail "$id" "finding does not mention '$needle': $out"
        return
    fi
    pass "$id"
}

# expect_pass <id> <path> [needle]
expect_pass() {
    local id="$1"
    local path="$2"
    local needle="${3:-}"
    local out rc
    out="$(python3 "$CHECK" "$path" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "$id" "expected exit 0, got $rc: $out"
        return
    fi
    if [ -n "$needle" ] && ! has "$out" "$needle"; then
        fail "$id" "output does not mention '$needle': $out"
        return
    fi
    pass "$id"
}

stage_md() {
    local id="$1"
    local dir="$WORK/shapes/$id"
    mkdir -p "$dir"
    printf '%s\n' "$dir/sample.md"
}

# --- Rejected shapes -------------------------------------------------------

file="$(stage_md plain-colon-space)"
cat > "$file" <<'EOF'
---
description: a value with a colon: here
---
EOF
expect_fail plain-colon-space "$file" "colon followed by a space"

file="$(stage_md plain-end-colon)"
cat > "$file" <<'EOF'
---
description: ends with a colon:
---
EOF
expect_fail plain-end-colon "$file" "ends with a colon"

file="$(stage_md plain-hash)"
cat > "$file" <<'EOF'
---
description: a value with a # comment
---
EOF
expect_fail plain-hash "$file" "after whitespace"

file="$(stage_md plain-backtick)"
cat > "$file" <<'EOF'
---
description: `inline code`
---
EOF
expect_fail plain-backtick "$file" "YAML indicator"

file="$(stage_md single-lone-quote)"
cat > "$file" <<'EOF'
---
description: 'it's broken'
---
EOF
expect_fail single-lone-quote "$file" "lone"

file="$(stage_md double-unescaped-quote)"
cat > "$file" <<'EOF'
---
description: "a "b" c"
---
EOF
expect_fail double-unescaped-quote "$file" "unescaped"

file="$(stage_md flow-brace)"
cat > "$file" <<'EOF'
---
tags: [a, {b}]
---
EOF
expect_fail flow-brace "$file" "flow-sequence item"

file="$(stage_md flow-colon)"
cat > "$file" <<'EOF'
---
tags: [a, b: c]
---
EOF
expect_fail flow-colon "$file" "colon followed by a space"

file="$(stage_md flow-hash)"
cat > "$file" <<'EOF'
---
tags: [a, b # c]
---
EOF
expect_fail flow-hash "$file" "after whitespace"

file="$(stage_md duplicate-key)"
cat > "$file" <<'EOF'
---
name: first
name: second
---
EOF
expect_fail duplicate-key "$file" "appears more than once"

file="$(stage_md nested-mapping)"
cat > "$file" <<'EOF'
---
parent:
  child: value
---
EOF
expect_fail nested-mapping "$file" "nested mapping"

file="$(stage_md no-closing-fence)"
cat > "$file" <<'EOF'
---
description: a value
EOF
expect_fail no-closing-fence "$file" "no closing"

# --- Accepted shapes -------------------------------------------------------

file="$(stage_md accepted-shapes)"
cat > "$file" <<'EOF'
---
# a comment line
plain: hello world

url: http://example.com/a:b
anchor: a#b
single: 'it''s fine: yes'
double: "a: b and \"quote\""
tags: [alpha, 'beta: gamma', "delta"]
description: >
  folded line one
  folded line two
literal: |
  line one
  line two
items:
  - first
  - 'second: item'
---
EOF
expect_pass accepted-shapes "$file" "checked 1 files"

# A block-sequence item takes the plain-value rule, so a comma or a brace is
# legal there even though the flow-sequence rule rejects both.
file="$(stage_md block-item-commas-braces)"
cat > "$file" <<'EOF'
---
items:
  - a, b
  - a{b}
  - plain item
---
EOF
expect_pass block-item-commas-braces "$file"

# A quoted value carrying a colon followed by a space is accepted.
file="$(stage_md quoted-colon-space)"
cat > "$file" <<'EOF'
---
description: "a value with a colon: here"
---
EOF
expect_pass quoted-colon-space "$file"

# A file with no frontmatter is skipped rather than reported.
file="$(stage_md no-frontmatter)"
cat > "$file" <<'EOF'
# No frontmatter here

Just a body.
EOF
expect_pass no-frontmatter "$file" "checked 0 files"

# An explicit non-skill file passes with the skill check skipped.
file="$(stage_md explicit-non-skill)"
cat > "$file" <<'EOF'
---
title: A non-skill file
---
EOF
expect_pass explicit-non-skill "$file" "0 skills"

# --- --values --------------------------------------------------------------

VALUES_FILE="$WORK/values.md"
cat > "$VALUES_FILE" <<'EOF'
---
plain: hello world
single: 'it''s fine'
double: "line\nnext\tand \u00e9"
fold: >
  folded
  text
foldstrip: >-
  folded
  text
foldkeep: >+
  folded
  text

foldindent: >
  line one
    indented line
  line three

lit: |
  literal
  text
litstrip: |-
  literal
  text
litkeep: |+
  literal
  text

flow: [a, 'b c', "d"]
seq:
  - one
  - 'two'
---
EOF
if python3 "$CHECK" --values "$VALUES_FILE" > "$WORK/values.json" 2> "$WORK/values.err"; then
    if python3 - "$WORK/values.json" "$VALUES_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
expected = {
    "plain": "hello world",
    "single": "it's fine",
    "double": "line\nnext\tand \u00e9",
    "fold": "folded text\n",
    "foldstrip": "folded text",
    "foldkeep": "folded text\n\n",
    "foldindent": "line one\n  indented line\nline three\n",
    "lit": "literal\ntext\n",
    "litstrip": "literal\ntext",
    "litkeep": "literal\ntext\n\n",
    "flow": ["a", "b c", "d"],
    "seq": ["one", "two"],
}
got = payload[sys.argv[2]]
if got != expected:
    print("values mismatch:", file=sys.stderr)
    for key in sorted(set(expected) | set(got)):
        if expected.get(key) != got.get(key):
            print(f"  {key}: expected {expected.get(key)!r} got {got.get(key)!r}", file=sys.stderr)
    sys.exit(1)
PY
    then
        pass values-decoding
    else
        fail values-decoding "decoded values differ from the stated expectation"
    fi
    if grep -q '==' "$WORK/values.json"; then
        fail values-json-alone "output carries a section header"
    else
        pass values-json-alone
    fi
    if grep -qi 'discovery' "$WORK/values.json"; then
        fail values-no-skill-finding "output carries a skill finding"
    else
        pass values-no-skill-finding
    fi
else
    fail values-decoding "check exited non-zero: $(cat "$WORK/values.err")"
fi

# --- Default file set and the tests/ exclusion -----------------------------

STAGED="$WORK/staged"
mkdir -p "$STAGED/scripts" "$STAGED/plugins/ai_dev/skills/skill_doctor/scripts" "$STAGED/tests"
cp "$CHECK" "$STAGED/scripts/lint_frontmatter.py"
cp "$DISCOVERY_DIR/discovery_safety.py" "$STAGED/plugins/ai_dev/skills/skill_doctor/scripts/"
cp "$DISCOVERY_DIR/skill_discovery.py" "$STAGED/plugins/ai_dev/skills/skill_doctor/scripts/"
cat > "$STAGED/good.md" <<'EOF'
---
title: Good
tags: [a, b]
---
EOF
cat > "$STAGED/tests/broken.md" <<'EOF'
---
description: broken: here
---
EOF
if (
    cd "$STAGED" || exit 1
    git init -q
    git config user.email "harness@example.com"
    git config user.name "Harness"
    git add -A
    git commit -qm seed
); then
    default_out="$(cd "$STAGED" && python3 scripts/lint_frontmatter.py 2>&1)"
    default_rc=$?
    if [ "$default_rc" -ne 0 ]; then
        fail default-excludes-tests "default run failed: $default_out"
    elif has "$default_out" 'tests/broken.md'; then
        fail default-excludes-tests "default run reported tests/broken.md"
    else
        pass default-excludes-tests
    fi
    explicit_out="$(cd "$STAGED" && python3 scripts/lint_frontmatter.py tests/broken.md 2>&1)"
    explicit_rc=$?
    if [ "$explicit_rc" -eq 0 ]; then
        fail explicit-tests-path "explicit run exited 0"
    elif ! has "$explicit_out" 'tests/broken.md'; then
        fail explicit-tests-path "finding does not name tests/broken.md: $explicit_out"
    else
        pass explicit-tests-path
    fi
else
    fail default-excludes-tests "could not stage the temporary git repo"
    fail explicit-tests-path "could not stage the temporary git repo"
fi

# --- Skill check integration ----------------------------------------------

SKILL_ROOT="$WORK/skills"

mkdir -p "$SKILL_ROOT/noname"
cat > "$SKILL_ROOT/noname/SKILL.md" <<'EOF'
---
description: Does one thing for the sample skill.
---
EOF
expect_fail skill-no-name "$SKILL_ROOT/noname/SKILL.md" "name_missing"

mkdir -p "$SKILL_ROOT/nofm"
cat > "$SKILL_ROOT/nofm/SKILL.md" <<'EOF'
# Sample skill

Body text without frontmatter.
EOF
expect_fail skill-no-frontmatter "$SKILL_ROOT/nofm/SKILL.md" "frontmatter_missing"

mkdir -p "$SKILL_ROOT/warnonly"
cat > "$SKILL_ROOT/warnonly/SKILL.md" <<'EOF'
---
name: warnonly
description: "Does a thing. Use when checking warning only skills with # hash."
version: 1.0.0
---
EOF
expect_pass skill-warning-only "$SKILL_ROOT/warnonly/SKILL.md" "warning(s)"

MISSING_ROOT="$WORK/missing"
mkdir -p "$MISSING_ROOT/scripts" "$MISSING_ROOT/skill"
cp "$CHECK" "$MISSING_ROOT/scripts/lint_frontmatter.py"
cat > "$MISSING_ROOT/skill/SKILL.md" <<'EOF'
---
name: skill
description: Does a thing for the sample skill.
version: 1.0.0
---
EOF
missing_out="$(python3 "$MISSING_ROOT/scripts/lint_frontmatter.py" "$MISSING_ROOT/skill/SKILL.md" 2>&1)"
missing_rc=$?
missing_path="$MISSING_ROOT/plugins/ai_dev/skills/skill_doctor/scripts/discovery_safety.py"
if [ "$missing_rc" -eq 0 ]; then
    fail missing-discovery-script "expected a non-zero exit"
elif ! has "$missing_out" "$missing_path"; then
    fail missing-discovery-script "finding does not name $missing_path: $missing_out"
else
    pass missing-discovery-script
fi

# --- Make wiring -----------------------------------------------------------

make_out="$(cd "$REPO_ROOT" && make -n lint 2>&1)"
if has "$make_out" 'lint-frontmatter'; then
    pass make-lint-wiring
else
    fail make-lint-wiring "make -n lint does not run lint-frontmatter: $make_out"
fi

# --- Tally -----------------------------------------------------------------

TOTAL=$((PASS + FAIL))
printf '\n%d of %d scenarios passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
    printf 'failed scenarios: %s\n' "${FAILED_IDS[*]}"
    exit 1
fi
exit 0
