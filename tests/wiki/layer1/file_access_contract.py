#!/usr/bin/env python3
"""Contract checks for wiki file-access guidance."""

from __future__ import annotations

import re
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
WIKI_SKILL = REPO_ROOT / "plugins/knowledge_management/skills/wiki/SKILL.md"
AGENT = REPO_ROOT / "plugins/knowledge_management/agents/auto_shaper_wiki.md"


def section(text: str, name: str) -> str:
    match = re.search(rf"<{name}>\n(.*?)\n\s*</{name}>", text, re.DOTALL)
    if not match:
        raise AssertionError(f"missing <{name}> section")
    return match.group(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    wiki = WIKI_SKILL.read_text(encoding="utf-8")
    agent = AGENT.read_text(encoding="utf-8")

    discipline = section(wiki, "file_handling_discipline")
    stage_edit = section(discipline, "read_to_stage_edit")
    require("Four rules keep tool use stable" in discipline, "rule count is not four")
    require(
        "Three rules keep tool use stable" not in discipline,
        "stale three-rule lead remains",
    )
    for phrase in [
        "use\n`Read` to locate the span",
        "stages the file for `Edit`",
        "Bash `grep`/`cat`/`tail`",
        "<too_large_to_read_in_one_shot>",
        "<appending_to_log>",
        "Bash output alone does not satisfy `Edit`'s precondition",
    ]:
        require(phrase in stage_edit, f"hub staging rule missing: {phrase}")

    too_large = section(discipline, "too_large_to_read_in_one_shot")
    require(
        "`Bash grep -n <pattern> <path>`" in too_large,
        "large-file locate-then-Read path changed",
    )
    require("`Read` only that range" in too_large, "large-file range Read changed")
    append_log = section(wiki, "appending_to_log")
    require("grep -n '^## \\[' \"$WIKI/log.md\" | tail -5" in append_log,
            "post-edit log verification changed")

    provenance = section(wiki, "write_or_update_pages")
    require("Every `sources:` value resolves from the wiki root" in provenance,
            "hub sources root rule missing")
    require("`Read` as `$WIKI/<sources-value>`" in provenance,
            "hub sources open form missing")
    capture_raw = section(wiki, "capture_raw_source")
    require("A raw-sidecar `source_path:` resolves from the wiki root" in capture_raw,
            "hub source_path root rule missing")
    require("`Read` as `$WIKI/<source_path-value>`" in capture_raw,
            "hub source_path open form missing")

    fix_workflow = " ".join(section(agent, "fix_workflow").split())
    for phrase in [
        "use `Read` to locate the span",
        "stages the file for `Edit`",
        "Bash `grep`/`cat`/`tail`",
        "Bash output alone does not satisfy `Edit`'s precondition",
    ]:
        require(phrase in fix_workflow, f"agent staging rule missing: {phrase}")

    external_pointer = section(agent, "external_source_pointer")
    require(
        "Resolve every `sources:` frontmatter value from the wiki root"
        in external_pointer,
        "agent sources root rule missing",
    )
    require("`Read` as `$WIKI/<sources-value>`" in external_pointer,
            "agent sources open form missing")
    raw_fix = section(agent, "fix_raw_source_frontmatter_missing")
    require("A raw-sidecar `source_path:` resolves from the wiki root" in raw_fix,
            "agent source_path root rule missing")
    require("`Read` as `$WIKI/<source_path-value>`" in raw_fix,
            "agent source_path open form missing")

    template_copy = section(agent, "fix_raw_frontmatter_subsection_missing")
    require("source_path:` for a wiki-root-relative in-repo path" in template_copy,
            "SCHEMA template-copy contract changed")
    require("`Read`" not in template_copy and "open it" not in template_copy,
            "agent open guidance leaked into the SCHEMA template copy")

    print("wiki file-access contract: PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
