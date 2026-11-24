#!/usr/bin/env python3
"""Contract checks for the wiki family's inheritance structure.

The hub declares its `wiki_*` family and states every shared rule once; each
front end carries one `<authority>` block citing the hub and replaces a
restated hub rule with a citation of the hub block by its verbatim tag name.
A self-test runs first and proves the checks fail on the defects they exist
to catch, so a broken checker cannot pass the real files.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
SKILLS = REPO_ROOT / "plugins/knowledge_management/skills"
HUB = SKILLS / "wiki/SKILL.md"
PSEUDO_XML_LINT = (
    REPO_ROOT
    / "plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py"
)

# Phrases a front end inherited by copy. Each one now lives in the hub block
# the front end cites, so a reappearance means the restatement came back.
RETIRED_RESTATEMENTS = [
    "Defer all wiki structure, discovery, orientation",
    "Defer all discovery, orientation, lint, semantic audit, remediation, "
    "and verification behavior to the agent",
    "exceeds maximum allowed tokens",
    "session-local temporary file outside the wiki tree",
    "For a URL to an externally-published article, confirm the target slug under",
    "The full orientation pass",
    "350 lines",
    "tail -n 350",
]

# Hub blocks `wiki_import` must cite rather than restate.
IMPORT_CITATIONS = [
    "<too_large_to_read_in_one_shot>",
    "<list_before_manipulating_unfamiliar_paths>",
    "<capture_raw_source>",
    "**Re-ingest compares before it writes**",
    'ls "$WIKI/raw/<kind>/"',
]

FAMILY_BULLET_RE = re.compile(r"^- `(wiki_[a-z_]+)`: (\S.*)$")


def section(text: str, name: str) -> str:
    match = re.search(rf"(?m)^\s*<{name}>\n(.*?)\n\s*</{name}>", text, re.DOTALL)
    if not match:
        raise AssertionError(f"missing <{name}> section")
    return match.group(1)


def inline_section(text: str, name: str) -> str:
    """Return a block whose content sits on the tag's own line."""
    match = re.search(rf"(?m)^\s*<{name}>(.*?)</{name}>\s*$", text)
    if not match:
        raise AssertionError(f"missing one-line <{name}> block")
    return match.group(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def front_ends() -> list[Path]:
    return sorted(SKILLS.glob("wiki_*/SKILL.md"))


def family_problems(text: str) -> list[str]:
    openers = re.findall(r"(?m)^<family>\s*$", text)
    closers = re.findall(r"(?m)^</family>\s*$", text)
    if len(openers) != 1 or len(closers) != 1:
        return [f"expected one <family> block, found {len(openers)}"]
    problems = []
    after = text.split("</output_contract>", 1)
    if len(after) != 2 or not after[1].lstrip("\n").startswith("<family>"):
        problems.append("<family> is not the first content after </output_contract>")
    if not text.split("</family>", 1)[1].lstrip("\n").startswith("</wiki>"):
        problems.append("<family> does not close immediately before </wiki>")
    return problems


def family_jobs(text: str) -> dict[str, str]:
    block = re.search(r"(?m)^<family>\n(.*?)\n</family>", text, re.DOTALL)
    if not block:
        raise AssertionError("missing column-0 <family> block")
    jobs = {}
    for line in block.group(1).splitlines():
        match = FAMILY_BULLET_RE.match(line)
        if match:
            jobs[match.group(1)] = match.group(2)
    return jobs


def restatement_problems(text: str) -> list[str]:
    return [phrase for phrase in RETIRED_RESTATEMENTS if phrase in text]


def occurrences(text: str, needle: str) -> int:
    return text.count(needle)


def self_test() -> None:
    hub = (
        "</pitfalls>\n\n<output_contract>\nx\n</output_contract>\n\n"
        "<family>\nHub of a family.\n\n"
        "- `wiki_alpha`: do the alpha job\n"
        "</family>\n\n</wiki>\n"
    )
    require(not family_problems(hub), "family placement check rejects a correct block")
    require(
        family_problems(hub.replace("<family>", "</output_contract>\n\n<family>")),
        "family placement check accepts a duplicate closing tag",
    )
    require(
        family_problems(hub.replace("</family>", "</family>\n<family>\n")),
        "family placement check accepts two family blocks",
    )
    require(
        family_problems(hub.replace("</wiki>", "<family>\nz\n</family>\n</wiki>")),
        "family placement check accepts a family block after </wiki>",
    )
    require(
        family_jobs(hub) == {"wiki_alpha": "do the alpha job"},
        "family job parser misses a bullet",
    )
    require(
        restatement_problems("Defer all wiki structure, discovery, orientation"),
        "restatement check misses a retired deferral",
    )
    require(
        restatement_problems("roughly the last 350 lines of log.md"),
        "restatement check misses a retired line-count read",
    )
    require(
        not restatement_problems("Cite `<resuming_an_existing_wiki>` for the pass."),
        "restatement check flags a citation",
    )


def main() -> int:
    self_test()

    hub = HUB.read_text(encoding="utf-8")
    siblings = front_ends()
    require(len(siblings) >= 3, f"family walk found {len(siblings)} front ends")

    problems = family_problems(hub)
    require(not problems, "; ".join(problems))
    jobs = family_jobs(hub)
    for path in siblings:
        name = path.parent.name
        require(name in jobs, f"hub <family> does not name {name}")
        require(len(jobs[name].split()) >= 3, f"{name} carries no one-job line")
    for forbidden in ["knowledge_management", "http", "plugins/", "~/"]:
        require(
            forbidden not in hub.split("<family>", 1)[1].split("</family>", 1)[0],
            f"hub <family> names a deployment detail: {forbidden}",
        )

    role = section(hub, "role")
    require("Andreas F. Hoffmann" in role, "hub <role> dropped the author credit")
    require("RAG" in role, "hub <role> dropped the RAG contrast")
    for detail in ["knowledge_management", "github.com/theafh"]:
        require(detail not in hub, f"hub still names a deployment detail: {detail}")

    for path in siblings:
        name = path.parent.name
        text = path.read_text(encoding="utf-8")
        authorities = re.findall(r"(?m)^\s*<authority>", text)
        require(len(authorities) == 1, f"{name} carries {len(authorities)} <authority> blocks")
        authority = inline_section(text, "authority")
        require("`wiki` skill" in authority, f"{name} <authority> does not cite the hub")
        require("source of truth" in authority, f"{name} <authority> names no authority")
        retired = restatement_problems(text)
        if retired:
            raise AssertionError(f"{name} restates a hub rule: {retired[0]!r}")

    import_text = (SKILLS / "wiki_import/SKILL.md").read_text(encoding="utf-8")
    for citation in IMPORT_CITATIONS:
        require(citation in import_text, f"wiki_import does not cite {citation}")

    resuming = section(hub, "resuming_an_existing_wiki")
    require(
        occurrences(hub, "the last 20 to 30 entries") == 1,
        "the hub states the orientation quantity other than once",
    )
    require("the last 20 to 30 entries" in resuming,
            "the hub quantity sits outside <resuming_an_existing_wiki>")
    for path in siblings:
        require(
            "the last 20 to 30 entries" not in path.read_text(encoding="utf-8"),
            f"{path.parent.name} restates the orientation quantity",
        )
    pitfall = section(hub, "pitfalls")
    require("<resuming_an_existing_wiki>" in section(pitfall, "orient_first"),
            "hub pitfall <orient_first> no longer cites the orientation block")
    for name in ["wiki_import", "wiki_wrapup"]:
        text = (SKILLS / f"{name}/SKILL.md").read_text(encoding="utf-8")
        require("<resuming_an_existing_wiki>" in text,
                f"{name} does not cite <resuming_an_existing_wiki>")
        require("<orient_first_top>" in inline_section(text, "orient_first_top"),
                f"{name} <orient_first_top> does not cite the hub top-line note")
    searching = section(hub, "searching")
    require("<resuming_an_existing_wiki>" in searching,
            "hub <searching> does not cite the orientation block")
    require("last 20 log entries" not in searching,
            "hub <searching> carries its own log-read quantity")

    fix_text = (SKILLS / "wiki_fix/SKILL.md").read_text(encoding="utf-8")
    require("<authority>" in fix_text, "wiki_fix carries no <authority> block")
    objective = inline_section(fix_text, "objective")
    require("Defer all" not in objective, "wiki_fix <objective> still defers in prose")
    block_bodies = {
        "role": inline_section(fix_text, "role"),
        "delegate": inline_section(fix_text, "delegate"),
        "steps": section(fix_text, "steps"),
    }
    for block, body in block_bodies.items():
        require(
            occurrences(body, "auto_shaper_wiki") == 1,
            f"wiki_fix <{block}> names auto_shaper_wiki "
            f"{occurrences(body, 'auto_shaper_wiki')} times",
        )

    result = subprocess.run(
        [sys.executable, str(PSEUDO_XML_LINT), str(HUB)]
        + [str(path) for path in siblings],
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )
    require(
        result.returncode == 0,
        f"pseudo-XML lint reports errors:\n{result.stdout}{result.stderr}",
    )

    print(f"wiki family inheritance: PASS ({len(siblings)} front ends, "
          f"one <family> block, one <authority> each)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
