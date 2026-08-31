#!/bin/sh
# shellcheck disable=SC2016
set -eu

unset CDPATH
script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_root=$(cd "$script_dir/../../.." && pwd -P)

task_skill="$repo_root/plugins/ai_dev/skills/task/SKILL.md"
task_create_skill="$repo_root/plugins/ai_dev/skills/task_create/SKILL.md"
task_check_skill="$repo_root/plugins/ai_dev/skills/task_check/SKILL.md"
task_implement_skill="$repo_root/plugins/ai_dev/skills/task_implement/SKILL.md"
task_audit_skill="$repo_root/plugins/ai_dev/skills/task_audit/SKILL.md"
task_auto_check_skill="$repo_root/plugins/ai_dev/skills/task_auto_check/SKILL.md"
task_finish_skill="$repo_root/plugins/ai_dev/skills/task_finish/SKILL.md"
task_fix_skill="$repo_root/plugins/ai_dev/skills/task_fix/SKILL.md"
task_lint_script="$repo_root/plugins/ai_dev/skills/task/scripts/lint.py"
auto_gate_agent="$repo_root/plugins/ai_dev/agents/auto_gate_task.md"
auto_reviewer_agent="$repo_root/plugins/ai_dev/agents/auto_reviewer_task.md"
auto_verifier_agent="$repo_root/plugins/ai_dev/agents/auto_verifier_task.md"
discover_script="$repo_root/plugins/ai_dev/skills/task/scripts/discover_tasks.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  file=$1
  needle=$2
  description=$3
  grep -Fq "$needle" "$file" || fail "$description"
}

assert_not_contains() {
  file=$1
  needle=$2
  description=$3
  if grep -Fq "$needle" "$file"; then
    fail "$description"
  fi
}

assert_count() {
  file=$1
  needle=$2
  expected=$3
  description=$4
  count=$(grep -F -c "$needle" "$file" | tr -d ' ')
  [ "$count" = "$expected" ] || fail "$description: expected $expected, got $count"
}

assert_contains "$task_skill" 'project-wide standing material lives at the repo root as optional `UPPERCASE.md` docs' \
  "base task skill documents the root UPPERCASE.md filing convention"
assert_count "$task_skill" 'project-wide standing material lives at the repo root as optional `UPPERCASE.md` docs' 1 \
  "base task skill keeps one canonical file-layout statement"
assert_contains "$task_skill" 'CLAUDE.md?        # optional harness-loaded project rule file' \
  "base task skill names CLAUDE.md as a harness-loaded rule file"
assert_contains "$task_skill" 'AGENTS.md?        # optional harness-loaded project rule file' \
  "base task skill names AGENTS.md as a harness-loaded rule file"
assert_contains "$task_skill" 'GEMINI.md?        # optional harness-loaded project rule file' \
  "base task skill names GEMINI.md as a harness-loaded rule file"
assert_contains "$task_skill" "The project's standing instructions start with the harness-loaded root rule files" \
  "base task skill defines the harness-loaded standing-instruction baseline"
assert_contains "$task_skill" 'Family-consulted guardrail docs are the additive layer over that baseline' \
  "base task skill keeps family guardrail docs additive"
assert_count "$task_skill" '</standing_doc_consumption>' 1 \
  "base task skill keeps one standing-doc consumption section"
assert_contains "$task_skill" 'test -f "$root/<DOC>.md"' \
  "base task skill names POSIX test -f presence gates"
assert_contains "$task_skill" 'The harness baseline governs wherever the family guardrail docs are silent' \
  "base task skill states harness-baseline precedence when guardrails are silent"
assert_contains "$task_skill" 'surface the conflict for human review instead of auto-resolving it' \
  "base task skill surfaces harness-vs-softer-guardrail conflicts"
assert_contains "$task_skill" 'graduated drift-prevention spectrum' \
  "base task skill documents the adoption spectrum"
assert_contains "$task_skill" 'plain manual chain follows the harness-loaded standing-instruction baseline' \
  "base task skill reflects the baseline tier in the family spectrum"
assert_contains "$task_skill" 'verified test-discipline rule, the descriptive `ARCHITECTURE.md`, and the `FEATURES.md` ledger' \
  "base task skill names the softer standing-doc tiers"
assert_contains "$task_skill" 'distinct from the charter' \
  "base task skill distinguishes ARCHITECTURE.md from the charter"
assert_contains "$task_skill" 'status-board, stage-index, or build-order view' \
  "base task skill keeps ARCHITECTURE.md out of index/status-board duties"
assert_count "$task_skill" 'Corollary: content a standing project instruction (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` and equivalents' 1 \
  "base task skill keeps one grounded cite-don't-restate corollary"
assert_contains "$task_skill" '**Restated standing rules**' \
  "base task skill readiness checklist includes the restated standing-rules lens"
assert_contains "$task_skill" 'the `<body>` corollary says belongs in a standing project instruction' \
  "readiness lens points at the grounded body corollary"
assert_contains "$task_skill" 'generic gate is a restatement, while a task-specific executable check remains valid' \
  "readiness lens distinguishes generic project gates from task-specific checks"
assert_contains "$task_skill" '**Title/description coverage**' \
  "base task skill readiness checklist includes the title/description coverage lens"
assert_contains "$task_skill" "named scope is narrower than the body's deliverables or sections" \
  "title/description coverage lens flags under-named task headings and descriptions"
assert_contains "$task_skill" 'a title naming two workflow threads over a five-thread body flips the finding on' \
  "title/description coverage lens carries the under-naming positive example"
assert_contains "$task_skill" 'a title that covers those five threads flips it off' \
  "title/description coverage lens carries the matching non-finding example"
assert_contains "$task_skill" 'Keep this distinct from **Structural check**, which checks presence, and **Contradictions**, which checks consistency rather than under-coverage.' \
  "title/description coverage lens stays distinct from presence and consistency checks"
assert_not_contains "$task_create_skill" '**Restated standing rules**' \
  "task_create keeps no separate copy of the restated standing-rules lens"
assert_not_contains "$task_check_skill" '**Restated standing rules**' \
  "task_check keeps no separate copy of the restated standing-rules lens"
assert_not_contains "$task_check_skill" '**Title/description coverage**' \
  "task_check keeps no separate copy of the title/description coverage lens"
assert_contains "$task_check_skill" "Assess against the base \`task\` skill's \`<readiness_checklist>\`" \
  "task_check still assesses by reference to the base checklist"
assert_contains "$task_create_skill" 'Judge the drafted body against the `task` skill' \
  "task_create still self-checks by reference to the base checklist"
assert_contains "$task_fix_skill" "the base \`<body>\`'s cite-don't-restate corollary is the rule source" \
  "task_fix advisory cites the same grounded corollary source"
assert_contains "$task_lint_script" 'H1_RE = re.compile(r"^#\s+\S")' \
  "task lint keeps H1 validation presence-only"
assert_contains "$task_lint_script" 'if isinstance(description, str) and len(description) > 200:' \
  "task lint keeps description validation length-only"
assert_not_contains "$task_lint_script" '**Title/description coverage**' \
  "task lint gets no semantic title/description coverage rule"
assert_not_contains "$task_lint_script" "named scope is narrower than the body's deliverables or sections" \
  "task lint stays out of semantic under-coverage judgment"

# Reconcile-or-surface open-decision rule: authored once in the base skill's
# Decide or label rule, cited (never copied) by the check/auto_check/implement
# siblings, and inherited unchanged by task_create.
assert_contains "$task_skill" '**Decide or label.** On any open decision a task carries' \
  "base task skill carries the stage-agnostic Decide or label reconciliation rule"
assert_contains "$task_skill" 'first reconcile, else surface' \
  "base Decide or label rule names the reconcile-else-surface procedure"
assert_count "$task_skill" 'first reconcile, else surface' 1 \
  "base skill keeps one canonical reconcile-else-surface statement"
assert_contains "$task_skill" 'When that clause cannot be written truthfully, the decision is reconcilable and the Reconcile branch applies.' \
  "base Decide or label rule states the reconcile-or-surface threshold"
assert_contains "$task_skill" 'ordered evidence base: (a)' \
  "base Decide or label rule names the ordered evidence base"
assert_contains "$task_skill" 'Zero labeled open decisions is the expected authoring outcome and one is the ceiling' \
  "base Decide or label rule keeps zero labeled open decisions as the expectation and one as the ceiling"
assert_not_contains "$task_skill" 'Resolve what you can derive before the file is written' \
  "base Decide or label rule no longer stands as authoring-only"
assert_contains "$task_skill" 'an unresolved either/or is a **Decide or label** finding routed through that rule' \
  "base readiness checklist routes an open decision through the Decide or label rule"
assert_contains "$task_check_skill" "apply the base skill's **Decide or label** reconciliation rule against its evidence base" \
  "task_check cites the base reconciliation rule"
assert_contains "$task_check_skill" 'task_check stays read-only' \
  "task_check keeps the read-only contract when reconciling an open decision"
assert_contains "$task_auto_check_skill" "drawn from that rule's ordered evidence base" \
  "task_auto_check Decide-or-label advocate proposes an evidence-grounded reconciliation"
assert_contains "$task_auto_check_skill" "the base **Decide or label** rule's evidence base supplies the missing decision" \
  "task_auto_check verifier clause cites the base rule's evidence base"
assert_contains "$task_implement_skill" "apply the base skill's **Decide or label** reconciliation rule against its evidence base" \
  "task_implement cites the base reconciliation rule as the backstop"
assert_not_contains "$task_implement_skill" 'explicitly leaves a decision open, make the call' \
  "task_implement drops the unqualified make-the-call license"
for sibling in "$task_check_skill" "$task_auto_check_skill" "$task_implement_skill" "$task_create_skill"; do
  assert_not_contains "$sibling" 'ordered evidence base: (a)' \
    "sibling keeps no copy of the base rule's ordered evidence base ($sibling)"
done

assert_contains "$task_skill" 'When `FEATURES.md` and/or `ARCHITECTURE.md` exist at the project root, read them before the prior-art codebase scan' \
  "task_create inherited create flow reads FEATURES.md and ARCHITECTURE.md when present"
assert_contains "$task_skill" 'When `CHARTER.md` exists at the project root, validate the task content against its boundaries and invariants' \
  "task_check inherited readiness checklist surfaces charter violations"
assert_contains "$auto_gate_agent" 'Preserve any `CHARTER.md` conflict surfaced by the base readiness checklist' \
  "auto_gate_task returns charter conflicts from task_check"
assert_contains "$task_auto_check_skill" 'leave the task file byte-for-byte unchanged' \
  "task_auto_check write seat leaves off-charter work untouched"
assert_contains "$auto_reviewer_agent" 'return `no_proposal` for any edit that would violate its boundaries or invariants' \
  "auto_reviewer_task declines off-charter proposals"
assert_contains "$auto_verifier_agent" 'reject any proposal that would violate its boundaries or invariants' \
  "auto_verifier_task rejects off-charter proposals"
assert_contains "$task_implement_skill" 'When `TESTING.md` exists at the project root, read it for project-specific testing details' \
  "task_implement reads TESTING.md when present"
assert_contains "$task_audit_skill" 'When `TESTING.md` exists at the project root, read it for project-specific testing details' \
  "task_audit reads TESTING.md when present"
assert_contains "$task_skill" 'When `ARCHITECTURE.md` exists at the project root and `design-extended` is `true`, update `ARCHITECTURE.md` in the same archive pass' \
  "task_finish inherited archive flow updates ARCHITECTURE.md for design-extending finished work"
assert_contains "$task_finish_skill" "Follow the \`task\` skill's \`<archive>\` workflow end to end" \
  "task_finish still delegates archive mechanics to the base skill"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/task-standing-docs.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

with_docs="$tmp_dir/with-docs"
without_docs="$tmp_dir/without-docs"
mkdir -p "$with_docs/tasks/archive" "$without_docs/tasks/archive"
: >"$with_docs/.project-root"
: >"$without_docs/.project-root"
for doc in CHARTER.md ARCHITECTURE.md FEATURES.md TESTING.md; do
  : >"$with_docs/$doc"
done

with_tasks=$(cd "$with_docs" && "$discover_script")
with_root=$(dirname "$with_tasks")
expected_with_root=$(cd "$with_docs" && pwd -P)
[ "$with_root" = "$expected_with_root" ] || fail "discover_tasks.sh resolved with-docs root"
for doc in CHARTER.md ARCHITECTURE.md FEATURES.md TESTING.md; do
  test -f "$with_root/$doc" || fail "presence gate detects $doc in staged fixture"
done

without_tasks=$(cd "$without_docs" && "$discover_script")
without_root=$(dirname "$without_tasks")
expected_without_root=$(cd "$without_docs" && pwd -P)
[ "$without_root" = "$expected_without_root" ] || fail "discover_tasks.sh resolved without-docs root"
for doc in CHARTER.md ARCHITECTURE.md FEATURES.md TESTING.md; do
  if test -f "$without_root/$doc"; then
    fail "presence gate treats absent $doc as absent"
  fi
done

if git -C "$repo_root" diff --name-only -- plugins/ai_dev/skills/task/scripts/discover_tasks.sh | grep -q .; then
  fail "discover_tasks.sh has local changes"
fi

if find "$repo_root/plugins/ai_dev/skills/task" -type f \( -iname '*registry*' -o -iname '*banner*' \) | grep -q .; then
  fail "task skill added a registry or banner file"
fi

printf 'PASS: task standing-doc conventions\n'
