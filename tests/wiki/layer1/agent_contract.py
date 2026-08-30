#!/usr/bin/env python3
"""Contract checks for the auto_shaper_wiki prompt.

The wiki Layer 1 harness is deterministic shell/Python. The
auto_shaper_wiki behavior itself is prose executed by an agent, so these
checks pin the load-bearing prompt contract that protects token-cost
changes from becoming fidelity regressions.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
AGENT = REPO_ROOT / "plugins/knowledge_management/agents/auto_shaper_wiki.md"


def section(text: str, name: str) -> str:
    match = re.search(rf"<{name}>\n(.*?)\n\s*</{name}>", text, re.DOTALL)
    if not match:
        raise AssertionError(f"missing <{name}> section")
    return match.group(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def derive_cold_reads(
    pages: set[str],
    baseline: str | None,
    changed: set[str],
    grep_hits: set[str],
    contradiction_peers: dict[str, set[str]],
) -> set[str]:
    """Mirror the prompt's working-set contract for a tiny fixture trace."""
    if baseline is None:
        return set(pages)

    reads = set(changed) | set(grep_hits)
    for page in list(reads):
        reads.update(contradiction_peers.get(page, set()))
    return reads & pages


def main() -> int:
    text = AGENT.read_text(encoding="utf-8")
    read_canonical = section(text, "read_canonical_references")
    working_set = section(text, "derive_page_audit_working_set")
    page_first = section(text, "page_first_iteration")
    scaffold = section(text, "scaffold_drift")
    raw_subtree = section(text, "raw_subtree_drift")
    contradiction = section(text, "cross_page_contradiction")
    audit_log = section(text, "append_audit_log_entry")
    iterate_policy = section(text, "iterate_page_first_not_check_first")

    # Orientation trim: the wiki-owned scaffold remains a full read, while
    # skill-owned canonical references are demand-loaded.
    require("Read `$WIKI/SCHEMA.md` end-to-end" in text, "SCHEMA full read was weakened")
    require("Read `$WIKI/index.md` end-to-end" in text, "index full read was weakened")
    require("tail -n 350 \"$WIKI/log.md\"" in text, "recent log read was weakened")
    require("without whole-file preloads" in read_canonical, "canonical orientation is not demand-loaded")
    require("by contiguous semantic block" in read_canonical, "wiki skill is not read by semantic block")
    require("Defer the \"Page thresholds\" figure" in read_canonical, "threshold read is not deferred")
    require("as on-demand references" in read_canonical, "templates are not on-demand")
    require(re.search(r"read the relevant template section only when a\s+diff hunk needs interpretation", read_canonical),
            "template reads are not hunk-scoped")
    require(re.search(r"`mkdir` calls in\s+`init_wiki\.sh`", raw_subtree),
            "raw subtree check does not derive from init_wiki.sh mkdir calls")
    require("quote only the relevant bucket descriptions" in raw_subtree,
            "raw taxonomy read is not scoped to relevant buckets")
    require("Read the canonical scaffold references" not in read_canonical,
            "old unconditional canonical-reference mandate remains")
    require("template_schema.md` —" not in read_canonical,
            "old template_schema full-read bullet remains")

    for command in [
        'diff -u "$WIKI/SCHEMA.md" "$WIKI_SKILL/references/template_schema.md"',
        'diff -u "$WIKI/index.md"  "$WIKI_SKILL/references/template_index.md"',
        '<(sed \'/^## \\[/,$d\' "$WIKI/log.md")',
    ]:
        require(command in scaffold, f"missing scaffold diff command: {command}")

    # Page-walk scoping: first audit covers all pages; incremental runs are
    # scoped by git evidence, additive grep hits, and contradiction peers.
    for phrase in [
        "First audit or unknown baseline",
        "the working set is the full page inventory",
        "Incremental audit",
        "git diff --name-status <baseline> -- \"$WIKI\"",
        "git status --short -- \"$WIKI\"",
        "unchanged since it last passed a cold walk stays out",
        "A grep hit adds the page to the full-read set",
        "a grep miss removes\n      nothing",
        "Read\n      both sides of the pair in full",
        "lint outcome\n    never gates page selection",
    ]:
        require(phrase in working_set, f"missing working-set contract phrase: {phrase}")

    require("read the page body in full" in page_first, "page-first walk no longer cold-reads pages")
    require("per-page subagents" in page_first, "optional page-boundary parallelism is not documented")
    require("read the\n    candidate peer pages in full" in contradiction,
            "contradiction peers are not full-read")
    require("Audit baseline:" in audit_log, "audit log does not record a future diff baseline")
    require("Cold page reads:" in audit_log, "audit log does not record the read set")

    # Clean audits must still leave a baseline; otherwise an incremental re-run
    # of an already-clean wiki falls back to a full re-read — the task's
    # headline saving. (Real end-to-end behavior is checked by an operator
    # run/re-run, not here; this only pins the prose contract.)
    compile_list = section(text, "compile_issue_list")

    def flat(s: str) -> str:
        return re.sub(r"\s+", " ", s)

    require("append_audit_log_entry" in flat(compile_list),
            "clean-exit path no longer records the audit baseline before reporting clean")
    require("on every completed audit" in flat(audit_log),
            "audit log entry is not pinned to every audit; clean runs would skip the baseline")
    require("zero-change outcome entry" in flat(audit_log),
            "append_audit_log_entry does not sanction the clean-audit baseline record")

    require("Run one cold full read for each page in that set" in iterate_policy,
            "page-first policy no longer requires cold full reads")

    reflective_checks = [
        "topic_mixing",
        "type_anatomy_mismatch",
        "section_order_or_gaps",
        "procedure_instance_leakage",
        "procedure_vs_concept_misclassification",
        "tag_drift",
        "provenance_violation",
        "external_source_pointer",
        "confidence_violation",
        "cross_page_contradiction",
    ]
    for check in reflective_checks:
        require(check in text, f"reflective check missing from agent text: {check}")

    # Banned mechanisms from the deferred attempt stay absent.
    banned_patterns = {
        "grep-gated page selection": r"grep[- ]gated page selection",
        "lint-clean skip": r"lint[^.\n]{0,80}clean[^.\n]{0,80}skip[^.\n]{0,80}page",
        "size-scaled read cap": r"size[- ]scaled read cap|read cap|cap[^.\n]{0,40}read",
        "grep hit as read precondition": r"grep hit[^.\n]{0,80}precondition[^.\n]{0,80}read",
    }
    for label, pattern in banned_patterns.items():
        require(re.search(pattern, text, re.IGNORECASE) is None, f"banned mechanism present: {label}")

    pages = {
        "concepts/widget-default.md",
        "concepts/widget-policy.md",
        "procedures/widget-default-procedure.md",
        "concepts/unchanged-reference.md",
    }
    contradiction_peers = {
        "concepts/widget-default.md": {"concepts/widget-policy.md"},
    }

    first = derive_cold_reads(pages, None, set(), set(), contradiction_peers)
    require(first == pages, f"first-audit fallback read set wrong: {sorted(first)}")

    second = derive_cold_reads(
        pages,
        "abc123",
        {"concepts/widget-default.md"},
        set(),
        contradiction_peers,
    )
    require(
        second == {"concepts/widget-default.md", "concepts/widget-policy.md"},
        f"incremental contradiction read set wrong: {sorted(second)}",
    )

    ungreppable_procedure = derive_cold_reads(
        pages,
        "abc123",
        {"procedures/widget-default-procedure.md"},
        set(),
        contradiction_peers,
    )
    require(
        ungreppable_procedure == {"procedures/widget-default-procedure.md"},
        f"ungreppable procedure read set wrong: {sorted(ungreppable_procedure)}",
    )

    semantic_flags = []
    if {"concepts/widget-default.md", "concepts/widget-policy.md"} <= second:
        semantic_flags.append("cross_page_contradiction")
    if "procedures/widget-default-procedure.md" in ungreppable_procedure:
        semantic_flags.append("procedure_vs_concept_misclassification")

    require(
        semantic_flags == [
            "cross_page_contradiction",
            "procedure_vs_concept_misclassification",
        ],
        f"fixture semantic flags wrong: {semantic_flags}",
    )

    print("auto_shaper_wiki contract trace:")
    print(f"  first audit cold reads: {', '.join(sorted(first))}")
    print(f"  second audit cold reads: {', '.join(sorted(second))}")
    print(f"  ungreppable procedure cold reads: {', '.join(sorted(ungreppable_procedure))}")
    print(f"  fixture semantic flags: {', '.join(semantic_flags)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
