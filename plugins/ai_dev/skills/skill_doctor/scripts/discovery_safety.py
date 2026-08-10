#!/usr/bin/env python3
"""Discovery-safety audit for selected SKILL.md frontmatter descriptions.

Parses frontmatter, checks name/description/version usability, dual-audience
description balance, workflow leakage, risky punctuation / non-ASCII, and
sibling distinctness / routing overlap. Prints JSON findings. Edits nothing.

Severity line: a finding blocks when it states a mechanical fact about the
file — absent or unparseable frontmatter, a missing required field, a
name/directory mismatch, a parser-hostile character, a byte-identical sibling
purpose. Every judgement about description *quality* warns instead, because a
regex cannot tell "carries no trigger coverage" from "phrases its triggers
differently", and a false block on a healthy shipped skill costs more than a
warning a reader dismisses. Detection scope is unchanged either way: every
dimension is still inspected and still reported.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

FRONTMATTER_LINE_RE = re.compile(r"^([A-Za-z0-9_-]+):\s*(.*)$")
USE_WHEN_RE = re.compile(r"\bUse when\b", re.IGNORECASE)
WORKFLOW_LEAK_RE = re.compile(
    r"(?i)\b("
    r"step\s+\d+|first\s+run|then\s+invoke|then\s+run|"
    r"workflow:|implementation\s+steps|after\s+parsing|"
    r"open\s+the\s+file\s+and|edit\s+the\s+selected"
    r")\b"
)
YAML_HOSTILE_START_RE = re.compile(r"^[&*!|>%@`\[\]]")
RISKY_PUNCT_RE = re.compile(r"[#{}]|:{2,}|\t")
# Characters that genuinely break a parse or hide content: C0/C1 controls,
# no-break space, zero-width and bidi controls, line/paragraph separators,
# word joiner, and the BOM. Ordinary typographic non-ASCII (em dash, curly
# quotes, ellipsis) is safe in UTF-8 frontmatter and stays a warning.
HOSTILE_CHAR_RE = re.compile(
    "[\x00-\x08\x0b-\x1f\x7f-\x9f"       # C0 / C1 control characters
    "\u00a0"                                 # no-break space
    "\u200b-\u200f\u2028\u2029"             # zero-width, marks, separators
    "\u202a-\u202e\u2060\u2066-\u2069"      # bidi controls, word joiner
    "\ufeff]"                                # byte-order mark
)
# Trigger coverage: an explicit trigger clause, a concrete file type, or a
# spread of concrete artefact nouns. Plurals are matched too — an exact-word
# list silently rejects "skills" while accepting "skill".
TRIGGER_CLAUSE_RE = re.compile(
    r"\bUse (?:when|for|this|it|to)\b"
    r"|\bTrigger(?:s|ed|ing)?\s+(?:on|when)\b"
    r"|\b(?:when|whenever)\s+\w+",
    re.IGNORECASE,
)
FILE_TYPE_RE = re.compile(r"\B\.[a-z][a-z0-9]{1,4}\b|\b[A-Za-z_]+\.md\b")
CONCRETE_NOUN_RE = re.compile(
    r"\b(skills?|plugins?|agents?|hooks?|commits?|wikis?|tasks?|guardrails?"
    r"|changelogs?|prompts?|frontmatter|descriptions?|manifests?"
    r"|repositor(?:y|ies)|repos?)\b",
    re.IGNORECASE,
)
TRIGGER_MIN_CHARS = 60
TRIGGER_MIN_DISTINCT_NOUNS = 3
# Purpose-clause shape thresholds. A purpose clause is prose that is not a
# bare keyword dump; no closed verb list decides it, and a crisp short lead
# sentence ("Close one completed or parked task.") counts as good writing.
PURPOSE_MIN_CHARS = 20
PURPOSE_MIN_WORDS = 5
KEYWORD_DUMP_MIN_SEGMENTS = 4
KEYWORD_DUMP_MAX_AVG_WORDS = 3.0
STOPWORDS = {
    "a",
    "an",
    "and",
    "as",
    "at",
    "by",
    "for",
    "from",
    "in",
    "into",
    "of",
    "on",
    "or",
    "the",
    "to",
    "when",
    "with",
    "without",
    "use",
    "using",
    "that",
    "this",
    "it",
    "its",
    "is",
    "are",
    "be",
}


def die(message: str, code: int = 2) -> None:
    print(f"discovery_safety: {message}", file=sys.stderr)
    raise SystemExit(code)


def split_frontmatter(text: str) -> tuple[str | None, str]:
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return None, text
    # Normalize to \n for scanning; keep original offsets via find on text.
    if text.startswith("---\r\n"):
        search_from = 5
        marker = "\r\n---\r\n"
        alt = "\n---\n"
    else:
        search_from = 4
        marker = "\n---\n"
        alt = "\r\n---\r\n"
    end = text.find(marker, search_from)
    if end == -1:
        end = text.find(alt, search_from)
        if end == -1:
            return None, text
        closer_len = len(alt)
    else:
        closer_len = len(marker)
    return text[search_from:end], text[end + closer_len :]


def parse_frontmatter_fields(fm: str) -> tuple[dict[str, str], list[str]]:
    """Parse a minimal YAML-frontmatter subset into a flat string map.

    Returns (fields, parse_issues). Does not mutate files.
    """
    fields: dict[str, str] = {}
    issues: list[str] = []
    lines = fm.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if line[:1] in (" ", "\t"):
            issues.append(
                f"unexpected indented line without a parent key: {line!r}"
            )
            i += 1
            continue
        match = FRONTMATTER_LINE_RE.match(line)
        if not match:
            issues.append(f"unparseable frontmatter line: {line!r}")
            i += 1
            continue
        key, raw = match.group(1), match.group(2)
        if raw in ("|", ">", "|-", ">-", "|+", ">+"):
            block: list[str] = []
            i += 1
            while i < len(lines) and (
                lines[i].startswith("  ") or lines[i].startswith("\t")
                or lines[i] == ""
            ):
                block.append(lines[i])
                i += 1
            fields[key] = "\n".join(block).strip()
            continue
        value = raw.strip()
        if (
            (value.startswith('"') and value.endswith('"') and len(value) >= 2)
            or (value.startswith("'") and value.endswith("'") and len(value) >= 2)
        ):
            value = value[1:-1]
        else:
            if YAML_HOSTILE_START_RE.match(value):
                issues.append(
                    f"unquoted value for `{key}` starts with YAML-significant "
                    f"character: {value[:20]!r}"
                )
            if ":" in value and not value.startswith("http"):
                # Unquoted colon mid-value is a common YAML footgun for
                # description strings that confuse naive parsers.
                issues.append(
                    f"unquoted value for `{key}` contains ':' — quote the "
                    "scalar for YAML safety"
                )
        fields[key] = value
        i += 1
    return fields, issues


def tokens(text: str) -> set[str]:
    words = re.findall(r"[a-z0-9_]+", text.lower())
    return {w for w in words if len(w) > 2 and w not in STOPWORDS}


def has_non_ascii(text: str) -> bool:
    return any(ord(ch) > 127 for ch in text)


def purpose_clause(description: str) -> str:
    """The part of a description that precedes its `Use when` triggers."""
    return USE_WHEN_RE.split(description.strip(), maxsplit=1)[0].strip()


def lead_sentence(text: str) -> str:
    """The first sentence — what a user reads to learn what the skill is."""
    match = re.match(r"(.+?[.!?])(?:\s|$)", text, re.DOTALL)
    return (match.group(1) if match else text).strip()


def purpose_score(description: str) -> bool:
    """True when the description leads with a readable purpose clause.

    Judged from sentence shape rather than a closed verb list. An allowlist
    of purpose verbs rejects ordinary ones it happens to omit (`import`,
    `wrap up`), which blocks healthy shipped descriptions, so the test is
    instead: prose of real length that is not a bare keyword dump.
    """
    purpose = purpose_clause(description)
    if len(purpose) < PURPOSE_MIN_CHARS:
        return False
    # Judge the lead sentence, not the whole clause: a "Covers a, b, c, d"
    # tail is legitimate router keyword material and would otherwise drag an
    # opening sentence of real prose below the keyword-dump threshold. A
    # parenthetical is an enumeration by nature and says nothing about
    # whether the clause around it reads as prose.
    prose = re.sub(r"\([^)]*\)", " ", lead_sentence(purpose))
    if len(prose.split()) < PURPOSE_MIN_WORDS:
        return False
    segments = [s for s in (seg.strip() for seg in re.split(r"[;,]", prose)) if s]
    if len(segments) >= KEYWORD_DUMP_MIN_SEGMENTS:
        avg_words = sum(len(s.split()) for s in segments) / len(segments)
        if avg_words < KEYWORD_DUMP_MAX_AVG_WORDS:
            return False
    return True


def trigger_score(description: str) -> bool:
    """True when the description carries router-usable trigger coverage.

    An explicit trigger clause is the clearest form, and a "when creating or
    editing markdown files (.md, .mdc)" context is the same signal phrased
    differently — so file types and a spread of concrete artefact nouns count
    too, rather than only the literal `Use when` opener.
    """
    if len(description) < TRIGGER_MIN_CHARS:
        return False
    if TRIGGER_CLAUSE_RE.search(description):
        return True
    if FILE_TYPE_RE.search(description):
        return True
    nouns = {n.lower() for n in CONCRETE_NOUN_RE.findall(description)}
    return len(nouns) >= TRIGGER_MIN_DISTINCT_NOUNS


def analyze_skill(path: Path) -> dict:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return {
            "path": str(path),
            "name": path.parent.name,
            "blocking": [
                {
                    "code": "unreadable",
                    "message": f"cannot read {path}: {exc}",
                    "evidence": str(path),
                }
            ],
            "warnings": [],
            "description": "",
            "version": "",
        }

    fm, _ = split_frontmatter(text)
    blocking: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []

    if fm is None:
        blocking.append(
            {
                "code": "frontmatter_missing",
                "message": "SKILL.md has no YAML frontmatter",
                "evidence": str(path),
            }
        )
        return {
            "path": str(path),
            "name": path.parent.name,
            "blocking": blocking,
            "warnings": warnings,
            "description": "",
            "version": "",
        }

    fields, parse_issues = parse_frontmatter_fields(fm)
    for issue in parse_issues:
        blocking.append(
            {
                "code": "yaml_parse",
                "message": issue,
                "evidence": str(path),
            }
        )

    name = fields.get("name", "").strip()
    description = fields.get("description", "").strip()
    version = fields.get("version", "").strip()

    if not name:
        blocking.append(
            {
                "code": "name_missing",
                "message": "frontmatter lacks usable `name:`",
                "evidence": str(path),
            }
        )
    elif name != path.parent.name:
        blocking.append(
            {
                "code": "name_directory_mismatch",
                "message": (
                    f"frontmatter name `{name}` does not match directory "
                    f"`{path.parent.name}`"
                ),
                "evidence": str(path),
            }
        )

    if not version:
        blocking.append(
            {
                "code": "version_missing",
                "message": "frontmatter lacks usable `version:`",
                "evidence": str(path),
            }
        )

    if not description:
        blocking.append(
            {
                "code": "description_missing",
                "message": "frontmatter lacks usable `description:`",
                "evidence": str(path),
            }
        )
    else:
        hostile = HOSTILE_CHAR_RE.search(description)
        if hostile:
            blocking.append(
                {
                    "code": "description_hostile_characters",
                    "message": (
                        "description contains a parser-hostile or invisible "
                        f"character (U+{ord(hostile.group()):04X})"
                    ),
                    "evidence": description[:120],
                }
            )
        elif has_non_ascii(description):
            warnings.append(
                {
                    "code": "description_non_ascii",
                    "message": (
                        "description contains typographic non-ASCII "
                        "characters, which stay valid in UTF-8 frontmatter; "
                        "confirm every consuming manifest and router reads "
                        "UTF-8 and keep the character as written. Where an "
                        "em dash instead holds together a clause break the "
                        "sentence never earned, split the description into "
                        "two sentences; a hyphen, a double hyphen, or an en "
                        "dash substituted into that slot keeps the same "
                        "break and fixes nothing"
                    ),
                    "evidence": description[:120],
                }
            )
        if RISKY_PUNCT_RE.search(description):
            warnings.append(
                {
                    "code": "description_risky_punctuation",
                    "message": (
                        "description contains risky punctuation "
                        "(#, {, }, ::, or tab) for YAML / router safety"
                    ),
                    "evidence": description[:120],
                }
            )
        if WORKFLOW_LEAK_RE.search(description):
            warnings.append(
                {
                    "code": "description_workflow_leak",
                    "message": (
                        "description leaks implementation workflow detail; "
                        "keep that detail in the skill body"
                    ),
                    "evidence": description[:160],
                }
            )

        readable = purpose_score(description)
        triggers = trigger_score(description)
        if readable and not triggers:
            warnings.append(
                {
                    "code": "description_missing_triggers",
                    "message": (
                        "description reads for humans but shows no LLM-router "
                        "trigger coverage (add a `Use when` clause or "
                        "equivalent keyword-rich triggers)"
                    ),
                    "evidence": description[:160],
                }
            )
        if triggers and not readable:
            warnings.append(
                {
                    "code": "description_missing_purpose",
                    "message": (
                        "description exposes routing keywords but reads as a "
                        "keyword list rather than explaining the skill's "
                        "purpose to a user"
                    ),
                    "evidence": description[:160],
                }
            )
        if not readable and not triggers:
            warnings.append(
                {
                    "code": "description_dual_audience_gap",
                    "message": (
                        "description serves neither audience well — write a "
                        "user-readable purpose summary, then trigger-rich "
                        "`Use when` language"
                    ),
                    "evidence": description[:160],
                }
            )

    return {
        "path": str(path),
        "name": name or path.parent.name,
        "blocking": blocking,
        "warnings": warnings,
        "description": description,
        "version": version,
    }


def sibling_findings(reports: list[dict]) -> list[dict]:
    """Compare sibling descriptions for overlap and formatting outliers."""
    findings: list[dict] = []
    with_desc = [r for r in reports if r.get("description")]
    if len(with_desc) < 2:
        return findings

    lengths = [len(r["description"]) for r in with_desc]
    mean_len = sum(lengths) / len(lengths)

    # An outlier is a sibling that differs from the rest of the set. A trait
    # the whole family shares is house style, and repeating the per-skill
    # finding for every sibling would only duplicate it.
    def is_outlier_trait(predicate) -> set:
        carriers = {r["name"] for r in with_desc if predicate(r["description"])}
        return carriers if 0 < len(carriers) < len(with_desc) else set()

    non_ascii_outliers = is_outlier_trait(has_non_ascii)
    risky_punct_outliers = is_outlier_trait(lambda d: bool(RISKY_PUNCT_RE.search(d)))

    for report in with_desc:
        desc = report["description"]
        if abs(len(desc) - mean_len) > max(120, mean_len * 0.75):
            findings.append(
                {
                    "severity": "warning",
                    "code": "sibling_length_outlier",
                    "skill": report["name"],
                    "path": report["path"],
                    "message": (
                        "description length is an outlier versus siblings "
                        f"(len={len(desc)}, sibling mean≈{mean_len:.0f})"
                    ),
                    "evidence": desc[:120],
                }
            )
        if report["name"] in non_ascii_outliers:
            findings.append(
                {
                    "severity": "warning",
                    "code": "sibling_non_ascii_outlier",
                    "skill": report["name"],
                    "path": report["path"],
                    "message": (
                        "description carries non-ASCII characters while its "
                        "siblings stay ASCII-only; align it by rewriting the "
                        "sentence rather than transliterating the character"
                    ),
                    "evidence": desc[:120],
                }
            )
        if report["name"] in risky_punct_outliers:
            findings.append(
                {
                    "severity": "warning",
                    "code": "sibling_risky_punctuation_outlier",
                    "skill": report["name"],
                    "path": report["path"],
                    "message": (
                        "description carries risky punctuation while its "
                        "siblings stay clear of it"
                    ),
                    "evidence": desc[:120],
                }
            )

    # Pairwise routing overlap / high-level distinctness.
    for i, left in enumerate(with_desc):
        left_tokens = tokens(left["description"])
        for right in with_desc[i + 1 :]:
            right_tokens = tokens(right["description"])
            if not left_tokens or not right_tokens:
                continue
            inter = left_tokens & right_tokens
            union = left_tokens | right_tokens
            jaccard = len(inter) / len(union)
            if jaccard >= 0.55:
                findings.append(
                    {
                        "severity": "warning",
                        "code": "sibling_routing_overlap",
                        "skill": f"{left['name']} vs {right['name']}",
                        "path": f"{left['path']}; {right['path']}",
                        "message": (
                            "sibling descriptions overlap heavily at the "
                            f"token level (jaccard={jaccard:.2f}); keep "
                            "user-readable high-level purposes distinct"
                        ),
                        "evidence": ", ".join(sorted(inter)[:12]),
                    }
                )
            # Near-duplicate openings hide distinctness for a human reader.
            left_head = purpose_clause(left["description"]).lower()
            right_head = purpose_clause(right["description"]).lower()
            if (
                left_head
                and right_head
                and left_head == right_head
                and len(left_head) > 30
            ):
                findings.append(
                    {
                        "severity": "blocking",
                        "code": "sibling_purpose_not_distinct",
                        "skill": f"{left['name']} vs {right['name']}",
                        "path": f"{left['path']}; {right['path']}",
                        "message": (
                            "sibling purpose summaries are identical at a "
                            "user-readable high level"
                        ),
                        "evidence": left_head[:120],
                    }
                )
    return findings


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Discovery-safety audit for SKILL.md descriptions."
    )
    parser.add_argument(
        "paths",
        nargs="+",
        help="One or more SKILL.md paths (or skill directories)",
    )
    return parser


def resolve_skill_md(raw: str) -> Path:
    path = Path(raw)
    if path.is_dir():
        path = path / "SKILL.md"
    if not path.is_file():
        die(f"SKILL.md not found: {raw}")
    return path


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    paths = [resolve_skill_md(p) for p in args.paths]
    reports = [analyze_skill(p) for p in paths]
    extra = sibling_findings(reports)

    blocking: list[dict] = []
    warnings: list[dict] = []
    for report in reports:
        for item in report["blocking"]:
            blocking.append(
                {
                    "severity": "blocking",
                    "skill": report["name"],
                    "path": report["path"],
                    **item,
                }
            )
        for item in report["warnings"]:
            warnings.append(
                {
                    "severity": "warning",
                    "skill": report["name"],
                    "path": report["path"],
                    **item,
                }
            )
    for item in extra:
        if item["severity"] == "blocking":
            blocking.append(item)
        else:
            warnings.append(item)

    # Stable ordering: blocking first already; sort within by path/code.
    blocking.sort(key=lambda x: (x.get("path", ""), x.get("code", "")))
    warnings.sort(key=lambda x: (x.get("path", ""), x.get("code", "")))

    payload = {
        "skills_checked": [r["name"] for r in reports],
        "blocking_count": len(blocking),
        "warning_count": len(warnings),
        "blocking": blocking,
        "warnings": warnings,
        "skill_reports": [
            {
                "name": r["name"],
                "path": r["path"],
                "version": r["version"],
                "description_length": len(r["description"]),
            }
            for r in reports
        ],
    }
    print(json.dumps(payload, indent=2, sort_keys=True))

    # Exit 1 when blocking findings exist so the doctor can gate on it.
    return 1 if blocking else 0


if __name__ == "__main__":
    raise SystemExit(main())
