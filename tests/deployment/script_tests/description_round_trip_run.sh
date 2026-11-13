#!/usr/bin/env bash
# Regression coverage for the description round trip.
#
# Every deploy generator that rebuilds frontmatter must carry the source
# `description` through unchanged, whichever YAML scalar form the source uses:
# plain, single-quoted, double-quoted, or a `>` / `|` block scalar with clip,
# `-`, or `+` chomping. Each generator is called the way style_run.sh calls
# merge_json_key: inside a subshell that sets argv, sets
# DEPLOYMENT_SH_SKIP_MAIN=1, and sources the deploy script. The generated
# description is read back with scripts/lint_frontmatter.py --values for the
# YAML outputs and tomllib for the Codex TOML, then compared with the source.
#
# Every generator in scope appends to $DEPLOYED_ARTIFACTS_LOG, so the script
# points that at a file in its own temporary directory before it calls any
# generator, and asserts the developer's real log is byte-identical afterwards.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
DEPLOY_SCRIPT="${REPO_ROOT}/deployment/deployment.sh"
LINT_FM="${REPO_ROOT}/scripts/lint_frontmatter.py"
REAL_LOG="${REPO_ROOT}/deployment/deployed_artefacts.log"
SCRATCH="$(mktemp -d)"
TEST_LOG="${SCRATCH}/deployed_artefacts.log"
FIXTURES="${SCRATCH}/fixtures"
OUT="${SCRATCH}/out"
mkdir -p "$FIXTURES" "$OUT"

comparisons=0
negative_controls=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

cd "$REPO_ROOT"

if ! python3 -c 'import tomllib' >/dev/null 2>&1; then
  printf '%s\n' \
    "description_round_trip: python3.11+ with tomllib is required for the" \
    "Codex TOML comparisons; install it and re-run." >&2
  exit 2
fi

# The developer's deploy log must survive the run untouched. Keep a copy to
# compare against, and note whether it existed at all.
REAL_LOG_HAD_FILE=false
REAL_LOG_BACKUP="${SCRATCH}/real-deployed_artefacts.log"
if [[ -f "$REAL_LOG" ]]; then
  REAL_LOG_HAD_FILE=true
  cp "$REAL_LOG" "$REAL_LOG_BACKUP"
fi

# --- Fixtures: one agent/style source per YAML scalar form ------------------
# Every fixture carries an <engineering_behavior> block so the Cursor style
# generator accepts it, and a body so the Codex developer_instructions check
# has text to compare.

cat > "${FIXTURES}/plain.md" <<'EOF'
---
name: round-trip-plain
description: Plain description with no special characters
model: inherit
---

Body paragraph for the plain fixture.

<engineering_behavior>Original behavior.</engineering_behavior>
EOF

cat > "${FIXTURES}/single.md" <<'EOF'
---
name: round-trip-single
description: 'Single-quoted: it''s a value # with a hash and a backslash \ here'
model: inherit
---

Body paragraph for the single-quoted fixture.

<engineering_behavior>Original behavior.</engineering_behavior>
EOF

cat > "${FIXTURES}/double.md" <<'EOF'
---
name: round-trip-double
description: "Double-quoted: \"quoted\" # hash, backslash \\ path, newline\nnext\ttab \u00e9 accent, nel\N nbsp\_ ls\L ps\P nul\0 end"
model: inherit
---

Body paragraph for the double-quoted fixture.

<engineering_behavior>Original behavior.</engineering_behavior>
EOF

cat > "${FIXTURES}/fold_clip.md" <<'EOF'
---
name: round-trip-fold-clip
description: >
  Folded clip: text with a colon: and a # hash
  on a second line.

  A new paragraph after a blank line.
    A more-indented line stays literal.
model: inherit
---

Body paragraph for the folded clip fixture.

<engineering_behavior>Original behavior.</engineering_behavior>
EOF

cat > "${FIXTURES}/fold_strip.md" <<'EOF'
---
name: round-trip-fold-strip
description: >-
  Folded strip: first line
  second line: with colon and # hash
model: inherit
---

Body paragraph for the folded strip fixture.

<engineering_behavior>Original behavior.</engineering_behavior>
EOF

cat > "${FIXTURES}/fold_keep.md" <<'EOF'
---
name: round-trip-fold-keep
description: >+
  Folded keep: first line
  second line: with colon and # hash

model: inherit
---

Body paragraph for the folded keep fixture.

<engineering_behavior>Original behavior.</engineering_behavior>
EOF

cat > "${FIXTURES}/literal_clip.md" <<'EOF'
---
name: round-trip-literal-clip
description: |
  Literal clip: line one
  line two: with colon and # hash
model: inherit
---

Body paragraph for the literal clip fixture.

<engineering_behavior>Original behavior.</engineering_behavior>
EOF

cat > "${FIXTURES}/literal_strip.md" <<'EOF'
---
name: round-trip-literal-strip
description: |-
  Literal strip: line one
  line two: with colon and # hash
model: inherit
---

Body paragraph for the literal strip fixture.

<engineering_behavior>Original behavior.</engineering_behavior>
EOF

cat > "${FIXTURES}/literal_keep.md" <<'EOF'
---
name: round-trip-literal-keep
description: |+
  Literal keep: line one
  line two: with colon and # hash

model: inherit
---

Body paragraph for the literal keep fixture.

<engineering_behavior>Original behavior.</engineering_behavior>
EOF

FORMS=(
  plain
  single
  double
  fold_clip
  fold_strip
  fold_keep
  literal_clip
  literal_strip
  literal_keep
)

# --- Fixture sanity --------------------------------------------------------
# If a fixture lost its escaping or chomping shape, the round-trip comparisons
# would pass trivially. Pin the decoded source text first.
python3 - "$LINT_FM" "$FIXTURES" <<'PY' || fail "fixture sanity check failed"
import json
import subprocess
import sys

lint, fixtures = sys.argv[1:3]


def description(form):
    path = f"{fixtures}/{form}.md"
    result = subprocess.run(
        [sys.executable, lint, "--values", path],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"fixture does not parse: {form}\n{result.stderr}")
    return json.loads(result.stdout)[path]["description"]


def trailing_newlines(text):
    return len(text) - len(text.rstrip("\n"))


plain = description("plain")
single = description("single")
double = description("double")
fold = {form: description(form) for form in ("fold_clip", "fold_strip", "fold_keep")}
literal = {
    form: description(form)
    for form in ("literal_clip", "literal_strip", "literal_keep")
}

checks = [
    ("plain value", plain, "Plain description with no special characters"),
    ("single-quoted embedded quote", "it's a value", single),
    ("single-quoted hash", " # with a hash", single),
    ("single-quoted backslash", "\\ here", single),
    ("double-quoted embedded quote", '"quoted"', double),
    ("double-quoted newline escape", "newline\nnext", double),
    ("double-quoted tab escape", "next\ttab", double),
    ("double-quoted unicode escape", "\u00e9", double),
    ("double-quoted backslash", "backslash \\ path", double),
    ("double-quoted NEL escape", "\x85", double),
    ("double-quoted NBSP escape", "\xa0", double),
    ("double-quoted line-separator escape", "\u2028", double),
    ("double-quoted paragraph-separator escape", "\u2029", double),
    ("double-quoted NUL escape", "\x00", double),
    ("folded clip paragraph break", "\nA new paragraph", fold["fold_clip"]),
    ("folded clip indented line", "\n  A more-indented line", fold["fold_clip"]),
    ("folded clip colon and hash", "colon: and a # hash", fold["fold_clip"]),
    ("fold strip trailing newlines", trailing_newlines(fold["fold_strip"]), 0),
    ("fold clip trailing newlines", trailing_newlines(fold["fold_clip"]), 1),
    ("fold keep trailing newlines", trailing_newlines(fold["fold_keep"]), 2),
    ("literal strip trailing newlines", trailing_newlines(literal["literal_strip"]), 0),
    ("literal clip trailing newlines", trailing_newlines(literal["literal_clip"]), 1),
    ("literal keep trailing newlines", trailing_newlines(literal["literal_keep"]), 2),
    ("literal clip newline kept", "\nline two", literal["literal_clip"]),
    ("literal clip colon and hash", "line two: with colon and # hash", literal["literal_clip"]),
]
for label, needle, haystack in checks:
    if isinstance(needle, int):
        if needle != haystack:
            raise SystemExit(f"fixture sanity: {label}: got {haystack}, want {needle}")
        continue
    if needle not in haystack:
        raise SystemExit(f"fixture sanity: {label}: {needle!r} missing from {haystack!r}")
PY

# --- Comparison helpers ----------------------------------------------------

# Compare the description a YAML parser reads from a generated file with the
# one the source declares, through the frontmatter gate's --values mode.
# Findings naming other keys are ignored: the OpenCode generator emits a nested
# `permissions:` mapping that the strict gate rejects but that is out of scope
# here. A finding that names `description`, or a missing or different value,
# fails the comparison.
yaml_description_matches() {
  python3 - "$LINT_FM" "$1" "$2" <<'PY'
import json
import subprocess
import sys

lint, source, output = sys.argv[1:4]


def values(path):
    result = subprocess.run(
        [sys.executable, lint, "--values", path],
        capture_output=True,
        text=True,
    )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise SystemExit(f"--values printed no JSON for {path}\n{result.stderr}")
    for line in result.stderr.splitlines():
        if ": description:" in line:
            raise SystemExit(f"description finding for {path}: {line}")
    return payload.get(path, {})


source_value = values(source).get("description")
output_value = values(output).get("description")
if source_value is None:
    raise SystemExit(f"source declares no description: {source}")
if output_value != source_value:
    print(
        "description mismatch\n"
        f"  source: {source_value!r}\n"
        f"  output: {output_value!r}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

# Compare the Codex TOML description with the source's decoded description.
toml_description_matches() {
  python3 - "$LINT_FM" "$1" "$2" <<'PY'
import json
import subprocess
import sys
import tomllib

lint, source, output = sys.argv[1:4]
result = subprocess.run(
    [sys.executable, lint, "--values", source],
    capture_output=True,
    text=True,
)
source_value = json.loads(result.stdout)[source]["description"]
with open(output, "rb") as handle:
    output_value = tomllib.load(handle).get("description")
if output_value != source_value:
    print(
        "toml description mismatch\n"
        f"  source: {source_value!r}\n"
        f"  output: {output_value!r}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

# Compare the Codex developer_instructions with the source body. TOML trims the
# newline right after the opening delimiter, and the closing delimiter keeps
# the body's own final newline, so the value equals the source body text.
toml_body_matches_source() {
  python3 - "$1" "$2" <<'PY'
import sys
import tomllib

source, output = sys.argv[1:3]
with open(source, encoding="utf-8") as handle:
    lines = handle.read().split("\n")
closers = [index for index, line in enumerate(lines) if line == "---"]
body = lines[closers[1] + 1 :]
while body and body[0] == "":
    body.pop(0)
expected = "\n".join(body)
with open(output, "rb") as handle:
    got = tomllib.load(handle).get("developer_instructions")
if got != expected:
    print(
        "developer_instructions mismatch\n"
        f"  source body: {expected!r}\n"
        f"  output:      {got!r}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

compare_yaml() {
  local label="$1" source="$2" output="$3"
  yaml_description_matches "$source" "$output" ||
    fail "${label}: description did not round-trip"
  comparisons=$((comparisons + 1))
}

compare_toml() {
  local label="$1" source="$2" output="$3"
  toml_description_matches "$source" "$output" ||
    fail "${label}: description did not round-trip through tomllib"
  comparisons=$((comparisons + 1))
}

compare_codex_body() {
  local label="$1" source="$2" output="$3"
  toml_body_matches_source "$source" "$output" ||
    fail "${label}: developer_instructions did not round-trip"
  comparisons=$((comparisons + 1))
}

# A Cursor rule must parse as accepted frontmatter with no findings at all.
assert_yaml_clean() {
  local label="$1" path="$2"
  python3 - "$LINT_FM" "$path" <<'PY' || fail "${label}: frontmatter did not parse cleanly"
import subprocess
import sys

lint, path = sys.argv[1:3]
result = subprocess.run(
    [sys.executable, lint, "--values", path],
    capture_output=True,
    text=True,
)
if result.returncode != 0:
    sys.stderr.write(result.stderr)
    raise SystemExit(1)
PY
}

# Run one deploy function the way style_run.sh calls merge_json_key: in a
# subshell whose argv satisfies the deploy script's scope check, with the
# skip-main flag set and the deploy log redirected into the scratch tree.
run_in_deploy_shell() {
  local fn="$1"
  shift
  local -a args=("$@")
  # The assignments below configure the sourced deployment.sh; shellcheck
  # cannot see their use through `source=/dev/null`.
  # shellcheck disable=SC2034
  (
    set -- --uninstall
    DEPLOYMENT_SH_SKIP_MAIN=1
    DEPLOYED_ARTIFACTS_LOG="$TEST_LOG"
    # shellcheck source=/dev/null
    source "$DEPLOY_SCRIPT"
    DRY_RUN=false
    "$fn" "${args[@]}"
  )
}

# --- Generate and compare every form through every generator in scope ------
for form in "${FORMS[@]}"; do
  source_path="${FIXTURES}/${form}.md"
  opencode_out="${OUT}/opencode-${form}.md"
  antigravity_out="${OUT}/antigravity-${form}.md"
  cursor_out="${OUT}/cursor-${form}.mdc"
  codex_out="${OUT}/codex-${form}.toml"
  rewritten_out="${OUT}/rewritten-${form}.md"

  run_in_deploy_shell generate_opencode_agent \
    "$source_path" "$opencode_out" opencode agent >/dev/null
  run_in_deploy_shell generate_antigravity_agent \
    "$source_path" "$antigravity_out" antigravity agent >/dev/null
  run_in_deploy_shell generate_cursor_style_rule \
    "$source_path" "$cursor_out" cursor style >/dev/null
  run_in_deploy_shell generate_toml_agent \
    "$source_path" "$codex_out" codex agent >/dev/null
  run_in_deploy_shell rewrite_agent_frontmatter \
    "$source_path" "$rewritten_out" claude true >/dev/null

  compare_yaml "opencode (${form})" "$source_path" "$opencode_out"
  compare_yaml "antigravity (${form})" "$source_path" "$antigravity_out"
  compare_yaml "cursor style rule (${form})" "$source_path" "$cursor_out"
  compare_yaml "rewrite_agent_frontmatter (${form})" "$source_path" "$rewritten_out"
  compare_toml "codex (${form})" "$source_path" "$codex_out"
  compare_codex_body "codex developer_instructions (${form})" \
    "$source_path" "$codex_out"
done

# The Cursor rule built from a double-quoted value holding a colon followed by
# a space must parse cleanly, which quote stripping would break.
assert_yaml_clean "cursor (double)" "${OUT}/cursor-double.mdc"

# --- Byte-level proof for the escapes a shell string cannot carry ----------
# The TOML must hold `\u0000` for the NUL escape, real UTF-8 bytes for the
# NEL/NBSP escapes, and tomllib must read the NUL and the two code points back.
python3 - "${OUT}/codex-double.toml" <<'PY' ||
import sys
import tomllib

path = sys.argv[1]
with open(path, "rb") as handle:
    raw = handle.read()
if b"\\u0000" not in raw:
    raise SystemExit(f"{path}: NUL escape is not written as \\u0000")
if b"\xc2\x85" not in raw:
    raise SystemExit(f"{path}: NEL escape is not valid UTF-8")
if b"\xc2\xa0" not in raw:
    raise SystemExit(f"{path}: NBSP escape is not valid UTF-8")
with open(path, "rb") as handle:
    value = tomllib.load(handle)["description"]
for label, needle in (
    ("NUL", "\x00"),
    ("NEL", "\x85"),
    ("NBSP", "\xa0"),
    ("LINE SEPARATOR", "\u2028"),
    ("PARAGRAPH SEPARATOR", "\u2029"),
):
    if needle not in value:
        raise SystemExit(f"{path}: tomllib did not read the {label} escape")
PY
  fail "codex (double): byte-level escape proof failed"

# --- Negative control: a quote-stripped description must fail --------------
stripped="${OUT}/double-quotes-stripped.mdc"
python3 - "${FIXTURES}/double.md" "$stripped" <<'PY'
import sys

source, dest = sys.argv[1:3]
with open(source, encoding="utf-8") as handle:
    lines = handle.read().split("\n")
out = []
for line in lines:
    if line.startswith("description: "):
        value = line[len("description: "):]
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        line = "description: " + value
    out.append(line)
with open(dest, "w", encoding="utf-8") as handle:
    handle.write("\n".join(out))
PY
if yaml_description_matches "${FIXTURES}/double.md" "$stripped" 2>/dev/null; then
  fail "negative control: a quote-stripped description must not match the source"
fi
negative_controls=$((negative_controls + 1))

# --- Deploy log: every row in the scratch log, the real log untouched ------
[[ -s "$TEST_LOG" ]] || fail "no generator appended to the scratch deploy log"
expected_rows=$((${#FORMS[@]} * 4))
actual_rows="$(wc -l < "$TEST_LOG" | tr -d ' ')"
[[ "$actual_rows" == "$expected_rows" ]] ||
  fail "scratch deploy log has ${actual_rows} rows, expected ${expected_rows}"
if awk -F'\t' -v prefix="$SCRATCH/" 'index($1, prefix) != 1 { bad = 1 } END { exit bad }' "$TEST_LOG"; then
  :
else
  fail "a deploy log row points outside the scratch tree"
fi

if [[ "$REAL_LOG_HAD_FILE" == true ]]; then
  cmp -s "$REAL_LOG_BACKUP" "$REAL_LOG" ||
    fail "the real deploy log changed during the run"
else
  [[ ! -e "$REAL_LOG" ]] || fail "the run created the real deploy log"
fi

[[ "$comparisons" -gt 0 ]] || fail "no comparisons ran"
[[ "$negative_controls" -gt 0 ]] || fail "no negative control ran"

printf '%s\n' \
  "Description round-trip regression passed: ${comparisons} comparison(s)," \
  "${negative_controls} negative control(s), ${actual_rows} scratch log row(s)"
