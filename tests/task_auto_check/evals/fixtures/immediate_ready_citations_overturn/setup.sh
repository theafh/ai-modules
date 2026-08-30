#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

# Historical false-approval reproduction. The task file is a verbatim snapshot
# of wiki_base-skill-output-contract.md at commit 1c8bb9f (status: open) — the
# body a 2026-08 batch gate stamped ready first-call with zero issues, and a
# 2026-08-12 re-gate then overturned with five readiness gaps:
#   1. fixed files/lint/log triad demanded of every core-operation entry
#   2. tag-only citation rule though only <ingest> has <report_what_changed>
#   3. weak per-operation "names the report returned" acceptance proof
#   4. placement "at the end of the hub body" proven by existence search only
#   5. positive-shape framing rule with no acceptance item verifying it
# Every artifact the task cites is staged frozen at the same commit, so all
# existence checks pass and only the comparative reading surfaces the gaps.
A="$HERE/assets"
P="$target/proj"

cp "$A/task_snapshot.md" "$P/tasks/wiki_base-skill-output-contract.md"

mkdir -p "$P/plugins/knowledge_management/skills/wiki/scripts" \
         "$P/plugins/knowledge_management/skills/wiki_fix" \
         "$P/plugins/knowledge_management/skills/wiki_import" \
         "$P/plugins/knowledge_management/skills/wiki_wrapup" \
         "$P/plugins/ai_dev/skills/ai_instruction_formatting/scripts"

cp "$A/wiki_SKILL.md" "$P/plugins/knowledge_management/skills/wiki/SKILL.md"
cp "$A/discover_wiki.sh" "$P/plugins/knowledge_management/skills/wiki/scripts/discover_wiki.sh"
chmod +x "$P/plugins/knowledge_management/skills/wiki/scripts/discover_wiki.sh"
cp "$A/wiki_fix_SKILL.md" "$P/plugins/knowledge_management/skills/wiki_fix/SKILL.md"
cp "$A/wiki_import_SKILL.md" "$P/plugins/knowledge_management/skills/wiki_import/SKILL.md"
cp "$A/wiki_wrapup_SKILL.md" "$P/plugins/knowledge_management/skills/wiki_wrapup/SKILL.md"
cp "$A/ai_instruction_formatting_SKILL.md" "$P/plugins/ai_dev/skills/ai_instruction_formatting/SKILL.md"
cp "$A/lint_pseudo_xml.py" "$P/plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py"

commit_proj "$target"
