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

# Status discipline: one family rule for what a body rewrite does to status.
# Each assert below pins one clause of the owner's status rules and fails on
# the text it replaced: the any-rewrite trigger, the confirm-and-proceed
# guard, the location-gated warnings, and the regroup re-gate.
auto_shaper_agent="$repo_root/plugins/ai_dev/agents/auto_shaper_task.md"
[ "$(grep -c '^<status_discipline>$' "$task_skill" | tr -d ' ')" = 1 ] \
  || fail "base task skill opens the status-discipline block once"
guard_line=$(grep -n '^</backward_move_guard>$' "$task_skill" | cut -d: -f1)
block_line=$(grep -n '^<status_discipline>$' "$task_skill" | cut -d: -f1)
[ -n "$guard_line" ] && [ -n "$block_line" ] && [ "$block_line" -gt "$guard_line" ] \
  || fail "the status-discipline block follows the backward-move guard"
# Rule 1: only a substantive rewrite sends ready back to checked.
assert_contains "$task_skill" 'returns to `checked` in the same edit only when the rewrite changes what the task delivers or how that delivery is checked' \
  "a ready task returns to checked only when the rewrite changes what it delivers or how that is checked"
assert_contains "$task_skill" 'A change to `## Goal` always returns the task to `checked`.' \
  "a Goal change always returns a ready task to checked"
assert_contains "$task_skill" 'it keeps `ready` when it only makes an existing requirement explicit' \
  "an Approach or Acceptance edit that only makes a requirement explicit keeps ready"
assert_contains "$task_skill" 'A mechanical change to links never returns the task to `checked`, whether it re-points a link or turns a link into plain text' \
  "a mechanical link change keeps ready"
assert_contains "$task_skill" 'a regroup under the `<lint>` **Repeated-link react protocol**, and a clarifying note keep `ready`' \
  "a regroup and a clarifying note keep ready"
assert_not_contains "$task_skill" 'whenever the rewrite goes beyond the `<lint>` mechanically fixable lint finding set' \
  "the any-rewrite trigger is superseded"
assert_not_contains "$task_skill" 'The trigger is the edit itself rather than its reach' \
  "the edit-not-reach rationale for the any-rewrite trigger is gone"
assert_contains "$task_skill" 'rewrote a `ready` task in a way that changes what it delivers or how that delivery is checked' \
  "the frontmatter checked entry carries the substantive-rewrite trigger"
assert_contains "$task_skill" 'whose rewrite of a `ready` task changes what the task delivers or how that delivery is checked writes `checked` in that edit' \
  "the lifecycle writer list carries the substantive-rewrite trigger"
assert_contains "$task_skill" '**A task file a split creates** starts at `open`' \
  "a file a split creates starts at open"
assert_contains "$task_skill" 'Every coherence repair writes `status` as the family `<status_discipline>` rule directs' \
  "backlog coherence points at the status-discipline block"
assert_contains "$task_skill" "an enumeration completed to the site set the task's own rule already implies each keep a \`ready\` task at \`ready\`" \
  "backlog coherence maps its meaning-preserving repair shapes to keeping ready"
assert_contains "$task_skill" 'write `status` in that edit as `<status_discipline>` directs for a body rewrite' \
  "the update workflow points at the status-discipline block"
assert_not_contains "$task_skill" 'A coherence pass writes no `status` value at all, in either direction.' \
  "the coherence-only status rule is superseded"
assert_not_contains "$task_skill" "leaves its \`status\` standing, \`ready\` included" \
  "the coherence-only keep-ready wording is superseded"
# Rule 2: after implementation, status only moves forward.
assert_contains "$task_skill" 'routes the finding to `task_audit`, to `task_finish`, or to a new follow-up task, and applies only mechanical link and lint fixes to the file' \
  "a finding on completed work is routed, and only mechanical link and lint fixes apply"
assert_contains "$task_skill" "An edit the user explicitly asks for through \`<update>\` stays the user's call, and it leaves the status as it is." \
  "a user's update of completed work leaves its status as it is"
assert_contains "$task_skill" 'No skill or agent writes `open`, `checked`, `ready`, or `implemented` over a later status, and user confirmation does not open that path either' \
  "no writer moves completed work backward, confirmation included"
assert_contains "$task_skill" 'is a hard stop: the stage writes no status, leaves the file as it is' \
  "the backward-move guard is a hard stop"
assert_not_contains "$task_skill" 'ask the user to confirm the move is intended' \
  "the confirm-and-proceed guard is superseded"
assert_contains "$task_skill" 'the move from `ready` to `checked` that `<status_discipline>` prescribes for a rewrite' \
  "the guard lets the rule-one move from ready to checked through"
# Rule 3: archived status is final.
assert_contains "$task_skill" '**A `finished` or `deferred` task** keeps its status for good' \
  "an archived task keeps its status for good"
assert_contains "$task_skill" 'Its body stays as delivered apart from mechanical link rewrites, so a family repair skill or agent reports a finding about it instead of applying the repair.' \
  "an archived task's body stays as delivered apart from mechanical link rewrites"
assert_not_contains "$task_skill" 'reopen the deferred task' \
  "prior-art no longer offers to reopen a deferred task"
# Rule 4: archiving rewrites links and changes no other status.
assert_contains "$task_skill" "These link rewrites are mechanical and change no task's status" \
  "the archive workflow's link rewrites change no task's status"
assert_contains "$task_skill" "The close-out's own move in step 1 is the only status this workflow writes." \
  "the close-out move is the archive workflow's only status write"
# Rule 5: the repeated-link and size warnings fire before implementation only.
assert_contains "$task_skill" 'The oversized-page and repeated-link warnings share one gate and fire only on `open`, `checked`, and `ready` tasks' \
  "the lint warning scope names the pre-implementation statuses"
assert_not_contains "$task_skill" 'oversized page (>300 lines; live tasks only)' \
  "the location-gated size scope is superseded"
assert_contains "$task_skill" 'The repeated-link check fires only on `open`, `checked`, and `ready` tasks' \
  "the react protocol states the status gate"
assert_contains "$task_skill" 'so it keeps a `ready` task at `ready` under `<status_discipline>`' \
  "the react protocol keeps a regrouped ready task ready"
assert_not_contains "$task_skill" 'surfaced because the task is <status>' \
  "the completed-work surfaced reason is gone from the hub"
assert_contains "$task_skill" 'A check whose repair reorganizes or rewrites body prose beyond the mechanically fixable lint finding set, as the oversized-page and repeated-link checks do, runs on `open`, `checked`, and `ready` tasks only.' \
  "the archive-scope rule gates a reorganizing check on the pre-implementation statuses"
assert_contains "$task_skill" 'A check whose repair is a mechanical body fix, as the soft-pointer cleanup is, runs on live pages.' \
  "the archive-scope rule keeps a mechanical body fix on live pages"
assert_contains "$task_skill" 'A check whose repair is mechanical metadata or a mechanical link rewrite, such as a re-pointed link or a wikilink or footnote converted to a standard markdown link, runs archive-inclusive' \
  "the archive-scope rule keeps metadata and link rewrites archive-inclusive"
assert_not_contains "$task_skill" 'runs on live pages only' \
  "the location-drawn archive-scope line for body prose is superseded"
# The siblings and agents follow the rules.
assert_contains "$task_fix_skill" 'write `status` in each repair'"'"'s edit as the base `<status_discipline>` rule directs' \
  "task_fix's gated coherence reconcile cites the status-discipline block"
assert_not_contains "$task_fix_skill" "leave a semantics-preserving repair's \`status\` standing" \
  "task_fix no longer restates the status rule"
assert_contains "$task_fix_skill" "Each one keeps the meaning of the body, so under the base \`<status_discipline>\` rule it keeps the task's status, \`ready\` included." \
  "task_fix's advisory repairs keep a ready task ready"
assert_contains "$task_fix_skill" 'leave the `finished` or `deferred` status of an archived file as it is' \
  "task_fix leaves archived status as it is"
assert_contains "$task_fix_skill" 'Every other finding, which the linter reports only on an `open`, `checked`, or `ready` task, is a meaning-preserving reorganization' \
  "task_fix's inline regroup names the status gate"
assert_not_contains "$task_fix_skill" 'surfaced because the task is <status>' \
  "task_fix drops the completed-work surfaced reason"
assert_not_contains "$task_fix_skill" 'Every other live finding is a meaning-preserving reorganization' \
  "task_fix no longer regroups every live finding inline"
assert_not_contains "$auto_shaper_agent" 'leave every `status:` value exactly as found' \
  "auto_shaper_task no longer leaves every status as found"
assert_not_contains "$auto_shaper_agent" 'never demoted in its frontmatter' \
  "auto_shaper_task no longer bans the checked write"
assert_contains "$auto_shaper_agent" "The base \`<status_discipline>\` block decides whether each fix may change the task's body and what \`status\` the fix's own edit writes." \
  "auto_shaper_task's remediation cites the status-discipline block for every fix"
assert_not_contains "$auto_shaper_agent" 'a mechanical or meaning-preserving fix keeps `ready`' \
  "auto_shaper_task keeps no copy of the status-discipline cases"
assert_not_contains "$auto_shaper_agent" 'did not already require' \
  "auto_shaper_task keeps no copy of the substantive-rewrite trigger"
assert_not_contains "$auto_shaper_agent" 'a rewrite of a `ready` task beyond the base `<lint>` mechanically fixable lint finding set writes `checked`' \
  "auto_shaper_task drops the any-rewrite trigger"
assert_contains "$auto_shaper_agent" 'its `<status_discipline>` block defines what every rewrite does to `status`' \
  "auto_shaper_task's defect-kind rule cites the status-discipline block"
assert_contains "$auto_shaper_agent" 'create the new task file at `status: open`, as `<status_discipline>` directs for a file a split creates' \
  "auto_shaper_task's split instruction cites the new-file clause"
assert_contains "$auto_shaper_agent" 'Flag a task for re-check in the report only where `<status_discipline>` leaves its status standing' \
  "auto_shaper_task's coherence remediation cites the status-discipline block"
assert_contains "$auto_shaper_agent" 'every task left flagged for re-check under the base `<status_discipline>` block' \
  "auto_shaper_task's report format cites the status-discipline block"
assert_not_contains "$auto_gate_agent" 'deferred to the auto_shaper_task writer' \
  "no writer applies an intended gate stamp"
assert_contains "$task_auto_check_skill" '`task_check` owns the ready/checked verdict and status write.' \
  "task_auto_check leaves every status write to task_check"
assert_not_contains "$task_auto_check_skill" 'is the one other writer of `checked`' \
  "task_auto_check no longer writes checked itself"
assert_contains "$task_auto_check_skill" 'Preserve frontmatter except for the `updated` timestamp; stamp' \
  "task_auto_check's repair edit writes no status"
assert_contains "$task_auto_check_skill" 'the round writes no status, no gate call follows it' \
  "the repeated-link round keeps ready with no re-gate"
assert_not_contains "$task_auto_check_skill" 'one re-gate then runs before' \
  "the repeated-link round's re-gate is gone"
assert_contains "$task_check_skill" "is past the readiness gate, and the base skill's \`<backward_move_guard>\` refuses a \`ready\` or \`checked\` stamp over it" \
  "task_check stops on completed or archived work"
assert_contains "$task_implement_skill" "refuses an \`implemented\` stamp over it, so stop before any edit" \
  "task_implement stops before building on audited or archived work"
assert_contains "$task_audit_skill" 'Route the gaps on an `implemented` task to `task_implement`, and the gaps on an `audited` task or an archived `finished` task to a new follow-up task' \
  "task_audit routes gaps on later statuses to a follow-up task"
assert_not_contains "$task_audit_skill" 'leave `status: implemented` and route the gaps to `task_implement`' \
  "task_audit no longer sends every gap to task_implement"
assert_contains "$task_finish_skill" 'keeps that status for good under the base `<status_discipline>` rule' \
  "task_finish leaves an archived task's status final"

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
