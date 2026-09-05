#!/usr/bin/env python3
"""Discovery-safety audit for selected SKILL.md frontmatter descriptions.

Parses frontmatter, checks the skill file the harness would load, checks
name/description usability, dual-audience description balance, workflow
leakage, risky and typographic punctuation, description length against the
harness skill-listing budget, and sibling distinctness / routing overlap.
Prints JSON findings. Edits nothing.

Every sibling check compares within one comparison group, which
`skill_discovery.comparison_groups` derives from the walk under `--root`, so
a finding that calls a description out of step with its *siblings* measures
it against the skills a deliberate declaration binds it to. The grouping
needs no argument from the caller.

Severity line: three tiers, each carrying what it can prove.

- **blocking** — the harness fails to load the skill or cannot route it:
  absent or unparseable frontmatter, an absent `name`, an absent
  `description`, a parser-hostile or invisible character in the
  description, a skill file the harness skips (not a regular file, or over
  its plugin-skill byte limit), more than one skill file in one directory,
  and a byte-identical sibling purpose summary.
- **warning** — every judgement about description *quality*, plus a
  mechanical fact the harness tolerates. A regex cannot tell "carries no
  trigger coverage" from "phrases its triggers differently", and a false
  block on a healthy shipped skill costs more than a warning a reader
  dismisses.
- **info** — a fact that is true of the file while a repository convention
  owns the requirement rather than the harness.

Detection scope is unchanged across the tiers: every dimension is still
inspected and still reported.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import sys
from pathlib import Path

# Load the shared discovery module by sibling name. A script run by absolute
# path already has its own directory first on the import path, while the
# `importlib.util.spec_from_file_location` form the script tests use adds no
# such entry, so inserting it here satisfies both load paths.
_SCRIPT_DIR = str(Path(__file__).resolve().parent)
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

from skill_discovery import (  # noqa: E402
    SKILL_FILE_RE,
    comparison_groups,
    die,
    family_token,
    group_label,
    split_frontmatter,
)

FRONTMATTER_LINE_RE = re.compile(r"^([A-Za-z0-9_-]+):\s*(.*)$")
# Standing harness rule files. A repository states its own conventions here,
# and the info tier cites them rather than assuming the convention exists.
RULE_FILES = ("AGENTS.md", "CLAUDE.md", "GEMINI.md")
RULE_LEAD_RE = re.compile(r"\*\*(.+?)\*\*", re.DOTALL)
VERSION_RULE_RE = re.compile(
    r"\bversion|\bbump|\bsemver|\b\d+\.\d+\.\d+\b",
    re.IGNORECASE,
)
# Settled by reading the installed harness CLI's own skill load path rather
# than by assuming the harness enforces this repository's naming convention.
# The loader registers a skill under its frontmatter `name:` and falls back to
# the directory basename only when that field is absent or empty, so a `name:`
# that disagrees with its directory still loads, lists, and routes. The
# mismatch therefore warns, and this record is what the severity reads from.
NAME_DIRECTORY_SEVERITY = "warning"
NAME_DIRECTORY_SEVERITY_RECORD = (
    "settled against the installed harness CLI skill load path (observed in "
    "Claude Code 2.1.226): the loader resolves a skill's registered name as "
    "frontmatter `name:` when that field is a non-empty string and falls back "
    "to the directory basename only otherwise, so a name that disagrees with "
    "its directory still loads and routes; the Codex CLI corroborates it "
    "(observed in codex-cli 0.147.0): its skill tooling reads the name from "
    "SKILL.md frontmatter and enforces no directory equality; the finding "
    "warns rather than blocks, and the repository convention that requires "
    "alignment stays enforced by the registration step"
)
# The plugin-skill byte limit the harness itself applies, read out of the
# installed CLI at check time. The CLI logs `Skipping plugin skill <path>:
# not a regular file or exceeds <N> byte limit` and interpolates that <N>
# from one constant, so the probe finds the message template, captures the
# identifier it interpolates, and resolves that identifier's value. Writing
# the number into this script instead would freeze it against a harness that
# raises it.
BYTE_LIMIT_TEMPLATE_RE = re.compile(
    rb"Skipping plugin skill \$\{[^}]{1,40}\}: not a regular file or "
    rb"exceeds \$\{([A-Za-z_$][A-Za-z0-9_$]{0,40})\} byte limit"
)
BYTE_LIMIT_LITERAL_RE = re.compile(
    rb"Skipping plugin skill [^\n]{0,120}?exceeds (\d{3,12}) byte limit"
)
# Recorded fallback for the plugin-skill byte limit, used when no installed
# harness CLI yields the value. The probe stays primary because the installed
# harness is ground truth for the host the check runs on; the recording keeps
# the check alive on hosts with no readable CLI. Either way a single number is
# a hint about any other system — a deployed skill meets each target machine's
# own harness build. Refresh the value and its provenance line when a probed
# run reports the recording stale.
FALLBACK_BYTE_LIMIT = 1048576
FALLBACK_BYTE_LIMIT_PROVENANCE = "recorded from Claude Code 2.1.226 on 2026-08-13"
HARNESS_CLI_NAMES = ("claude", "codex")
# Harness CLIs installed at fixed application-bundle locations rather than on
# PATH. The macOS Codex CLI ships inside the ChatGPT desktop application, so a
# PATH lookup alone misses an installed Codex entirely.
HARNESS_CLI_BUNDLE_PATHS = (
    "/Applications/ChatGPT.app/Contents/Resources/codex",
)
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
# The typographic punctuation that stands in for sentence structure: em dash,
# en dash, curly single and double quotes, and the horizontal ellipsis. The
# codepoint boundary at 127 was the wrong axis for this check, because it
# swept in an accented Latin letter, a proper name, and any non-Latin script
# and handed each of them advice about splitting a clause that does not apply.
# Every character here parses safely in UTF-8 frontmatter, so what the finding
# reports is a writing habit rather than an encoding hazard; the parse-safety
# axis belongs to HOSTILE_CHAR_RE and RISKY_PUNCT_RE by character class.
TYPOGRAPHIC_PUNCT_RE = re.compile("[–—‘’“”…]")
# Characters that genuinely break a parse or hide content: C0/C1 controls,
# no-break space, zero-width and bidi controls, line/paragraph separators,
# word joiner, and the BOM. Typographic punctuation parses fine here and draws
# the separate TYPOGRAPHIC_PUNCT_RE warning instead.
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
# Absolute description-length risk, measured against the harness's skill
# listing rather than against the siblings in its comparison group. The
# listing is built under a character budget of contextWindow × 4
# bytes-per-token × skillListingBudgetFraction (default 0.01), which is
# roughly 8000 characters at a 200k-token window, and each entry costs its
# name plus its description truncated to skillListingMaxDescChars (default
# 1536). When the entries overrun that budget the listing keeps them greedily
# by a recency-weighted usage score and drops the rest to a name-only entry,
# so a never-invoked skill loses its description first. The threshold is
# one-eighth of that default budget: past it, a description's own length puts
# its listing entry at risk however many siblings surround it, so the check
# runs per skill.
LISTING_BUDGET_CHARS = 8000
LISTING_BUDGET_RISK_CHARS = LISTING_BUDGET_CHARS // 8
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


def harness_cli_paths() -> list[Path]:
    """Every installed harness CLI executable this probe can read."""
    found: list[Path] = []
    seen: set[Path] = set()
    candidates = [os.environ.get("CLAUDE_CODE_EXECPATH", "")]
    candidates += [shutil.which(name) or "" for name in HARNESS_CLI_NAMES]
    candidates += list(HARNESS_CLI_BUNDLE_PATHS)
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate)
        try:
            resolved = path.resolve()
        except OSError:
            continue
        if resolved in seen or not resolved.is_file():
            continue
        seen.add(resolved)
        found.append(resolved)
    return found


def identifier_values(data: bytes, ident: bytes) -> set[int]:
    """Every numeric value assigned to one identifier in a bundle.

    Scans with bytes.find and validates each hit in a small window. A single
    regex carrying a leading boundary alternation walks every position of a
    several-hundred-megabyte executable and costs seconds; this stays in
    milliseconds while accepting the same assignments.
    """
    values: set[int] = set()
    window_re = re.compile(rb"\s*=\s*(\d{3,12})(?![0-9])")
    boundary_re = re.compile(rb"[A-Za-z0-9_$]")
    span = len(ident)
    index = data.find(ident)
    while index != -1:
        before = data[index - 1 : index] if index else b""
        if not before or not boundary_re.match(before):
            match = window_re.match(data, index + span, index + span + 24)
            if match:
                values.add(int(match.group(1)))
        index = data.find(ident, index + 1)
    return values


def probe_byte_limit() -> tuple[int | None, str]:
    """The harness plugin-skill byte limit, read from the installed CLI.

    Returns (limit, detail). A None limit means the check cannot run, and the
    detail names why so the caller can report the skip with its reason.
    """
    clis = harness_cli_paths()
    if not clis:
        return (
            None,
            "no harness CLI found on PATH or at a known application-bundle "
            "location to read the limit from",
        )
    reasons: list[str] = []
    for cli in clis:
        try:
            data = cli.read_bytes()
        except OSError as exc:
            reasons.append(f"{cli.name}: cannot read executable ({exc})")
            continue
        values: set[int] = set()
        for ident in sorted(set(BYTE_LIMIT_TEMPLATE_RE.findall(data))):
            values.update(identifier_values(data, ident))
        if not values:
            # A build that interpolates the number straight into the message
            # needs no identifier lookup.
            values = {int(hit) for hit in BYTE_LIMIT_LITERAL_RE.findall(data)}
        if not values:
            reasons.append(
                f"{cli.name}: no `Skipping plugin skill ... byte limit` "
                "message found in the executable"
            )
            continue
        if len(values) > 1:
            reasons.append(
                f"{cli.name}: the byte-limit message resolves to more than "
                f"one value ({sorted(values)})"
            )
            continue
        limit = values.pop()
        return limit, (
            f"read {limit} from the `Skipping plugin skill ... byte limit` "
            f"message in {cli}"
        )
    return None, "; ".join(reasons)


def resolve_byte_limit(
    probed: int | None,
    probe_detail: str,
) -> tuple[int, str, str]:
    """The byte limit the check runs with, its source, and the report detail.

    The probed value wins: it is what the host's installed harness actually
    enforces, and it is authoritative for that host alone. Without a readable
    CLI the check runs against the recorded fallback instead of going silent,
    and a probe that disagrees with the recording reports the drift so the
    recorded value gets refreshed.
    """
    if probed is not None:
        detail = probe_detail
        if probed != FALLBACK_BYTE_LIMIT:
            detail += (
                f"; the recorded fallback {FALLBACK_BYTE_LIMIT} "
                f"({FALLBACK_BYTE_LIMIT_PROVENANCE}) is stale — refresh it "
                f"to {probed}"
            )
        return probed, "probe", detail
    return (
        FALLBACK_BYTE_LIMIT,
        "fallback",
        (
            f"no installed harness CLI yielded the limit ({probe_detail}); "
            f"using the recorded fallback {FALLBACK_BYTE_LIMIT} "
            f"({FALLBACK_BYTE_LIMIT_PROVENANCE}) — a recorded value is a "
            "hint, not the installed harness's own number"
        ),
    )


def find_repo_root(start: Path) -> Path | None:
    """The nearest directory above a skill that looks like a repo root."""
    current = start.resolve()
    if current.is_file():
        current = current.parent
    while True:
        if (current / ".git").exists() or any(
            (current / rule).is_file() for rule in RULE_FILES
        ):
            return current
        if current == current.parent:
            return None
        current = current.parent


def version_rule_citation(root: Path | None) -> tuple[str | None, str | None]:
    """The version rule a repository's standing rule files state, if any.

    Returns (rule_text, source_file). Both are None when the rule files carry
    no version rule, so the finding can say so rather than assert one exists.
    """
    if root is None:
        return None, None
    for rule_file in RULE_FILES:
        path = root / rule_file
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for lead in RULE_LEAD_RE.findall(text):
            candidate = " ".join(lead.split())
            if len(candidate) > 200:
                continue
            if VERSION_RULE_RE.search(candidate):
                return candidate, rule_file
    return None, None


def version_missing_message(root: Path | None) -> str:
    rule, source = version_rule_citation(root)
    base = (
        "frontmatter carries no `version:`, which no harness field reads, so "
        "the requirement is owned by repository convention rather than by the "
        "harness"
    )
    if rule:
        return f"{base}; this repository states it in {source} as **{rule}**"
    return (
        f"{base}; the standing rule files "
        f"({', '.join(RULE_FILES)}) state no version rule here, so no "
        "convention was found to require one"
    )


def ambiguous_skill_files(names: list[str]) -> list[str]:
    """The skill files in one directory when the harness has to pick one.

    Kept a pure function of the directory listing so the decision is testable
    on a case-insensitive filesystem, where staging both spellings side by
    side is impossible while the harness still meets that state elsewhere.
    """
    matches = sorted(name for name in names if SKILL_FILE_RE.match(name))
    return matches if len(matches) > 1 else []


def skill_file_findings(
    path: Path,
    byte_limit: int | None,
    byte_limit_source: str = "probe",
) -> list[dict[str, str]]:
    """Blocking findings about the skill file the harness would load."""
    findings: list[dict[str, str]] = []
    try:
        info = path.stat()
    except OSError as exc:
        return [
            {
                "code": "skill_file_not_regular",
                "message": (
                    f"the harness skips this skill file because it cannot be "
                    f"read as a regular file ({exc})"
                ),
                "evidence": str(path),
            }
        ]
    if not stat.S_ISREG(info.st_mode):
        findings.append(
            {
                "code": "skill_file_not_regular",
                "message": (
                    "the harness skips this skill file because it is not a "
                    "regular file"
                ),
                "evidence": str(path),
            }
        )
    if byte_limit is not None and info.st_size > byte_limit:
        source_note = (
            " (recorded fallback, not read from an installed harness)"
            if byte_limit_source == "fallback"
            else ""
        )
        findings.append(
            {
                "code": "skill_file_over_byte_limit",
                "message": (
                    f"skill file is {info.st_size} bytes, over the harness "
                    f"plugin-skill limit of {byte_limit} bytes{source_note}, "
                    "so the harness skips it entirely"
                ),
                "evidence": str(path),
            }
        )
    try:
        siblings = ambiguous_skill_files([e.name for e in path.parent.iterdir()])
    except OSError:
        siblings = []
    if siblings:
        findings.append(
            {
                "code": "skill_file_ambiguous",
                "message": (
                    "the directory holds more than one skill file "
                    f"({', '.join(siblings)}); the harness matches the name "
                    "case-insensitively, picks one, and logs the ambiguity, "
                    "so the loaded file may not be the authored one"
                ),
                "evidence": str(path.parent),
            }
        )
    return findings


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


def analyze_skill(
    path: Path,
    byte_limit: int | None = None,
    repo_root: Path | None = None,
    byte_limit_source: str = "probe",
) -> dict:
    file_blocking = skill_file_findings(path, byte_limit, byte_limit_source)
    not_regular = any(
        item["code"] == "skill_file_not_regular" for item in file_blocking
    )
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        # A file the harness skips already carries its precise diagnosis, so
        # the generic read failure would only repeat it.
        unreadable = (
            []
            if not_regular
            else [
                {
                    "code": "unreadable",
                    "message": f"cannot read {path}: {exc}",
                    "evidence": str(path),
                }
            ]
        )
        return {
            "path": str(path),
            "name": path.parent.name,
            "blocking": file_blocking + unreadable,
            "warnings": [],
            "info": [],
            "description": "",
            "version": "",
        }

    fm, _ = split_frontmatter(text)
    blocking: list[dict[str, str]] = list(file_blocking)
    warnings: list[dict[str, str]] = []
    info: list[dict[str, str]] = []

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
            "info": info,
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
        mismatch = {
            "code": "name_directory_mismatch",
            "message": (
                f"frontmatter name `{name}` does not match directory "
                f"`{path.parent.name}`; {NAME_DIRECTORY_SEVERITY_RECORD}"
            ),
            "evidence": str(path),
        }
        if NAME_DIRECTORY_SEVERITY == "blocking":
            blocking.append(mismatch)
        else:
            warnings.append(mismatch)

    if not version:
        info.append(
            {
                "code": "version_missing",
                "message": version_missing_message(repo_root),
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
        elif TYPOGRAPHIC_PUNCT_RE.search(description):
            warnings.append(
                {
                    "code": "description_typographic_punctuation",
                    "message": (
                        "description contains typographic punctuation (em "
                        "dash, en dash, curly quote, or ellipsis). "
                        "ai_instruction_writing bans the em dash and en "
                        "dash outright in AI-consumed content, so split "
                        "the description into two sentences where a dash "
                        "joins two clauses; a hyphen, a double hyphen, or "
                        "an en dash "
                        "substituted into that slot keeps the same break and "
                        "fixes nothing"
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
        if len(description) > LISTING_BUDGET_RISK_CHARS:
            warnings.append(
                {
                    "code": "description_listing_budget_length",
                    "message": (
                        f"description is {len(description)} characters, over "
                        f"the {LISTING_BUDGET_RISK_CHARS}-character threshold "
                        "at which its length alone risks the harness dropping "
                        "it from the skill listing (default listing budget "
                        f"≈{LISTING_BUDGET_CHARS} characters); a listing that "
                        "overruns that budget keeps descriptions by a "
                        "recency-weighted usage ranking and lists the rest by "
                        "name alone, so a never-invoked skill loses its "
                        "description first"
                    ),
                    "evidence": description[:120],
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
        "info": info,
        "description": description,
        "version": version,
    }


def sibling_findings(reports: list[dict], groups: dict[str, str]) -> list[dict]:
    """Compare each description against its own comparison group.

    Every sibling finding claims a description is out of step with its
    *siblings*, so the comparison runs inside one declared family at a time
    rather than across whatever set a run selected: `groups` maps each
    report's path to the group `skill_discovery.comparison_groups` derived
    from the walk. A skill bound to no family is a group of one, which the
    fewer-than-two short-circuit leaves silent, so every finding here means
    what its message says.
    """
    findings: list[dict] = []
    by_group: dict[str, list[dict]] = {}
    for report in reports:
        if not report.get("description"):
            continue
        # Falling back to the label the report's own name implies keeps a
        # message readable rather than naming an empty group, in the one case
        # a caller hands over a grouping that misses a path it passed.
        label = groups.get(report["path"]) or group_label(
            family_token(report["name"]), None
        )
        by_group.setdefault(label, []).append(report)
    for label, group in sorted(by_group.items()):
        findings.extend(group_sibling_findings(label, group))
    return findings


def group_sibling_findings(label: str, with_desc: list[dict]) -> list[dict]:
    """Overlap and formatting outliers inside one comparison group."""
    findings: list[dict] = []
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

    typographic_outliers = is_outlier_trait(
        lambda d: bool(TYPOGRAPHIC_PUNCT_RE.search(d))
    )
    risky_punct_outliers = is_outlier_trait(lambda d: bool(RISKY_PUNCT_RE.search(d)))
    # The message reports the split the run actually measured. Asserting that
    # the other siblings are clean is a claim the outlier test never makes:
    # it fires whenever the carriers are a proper non-empty subset, so two of
    # four carriers produce two findings that each face a set with a carrier
    # in it. A count of one states the single-carrier case just as plainly.
    typographic_carriers = ", ".join(sorted(typographic_outliers))
    typographic_message = (
        f"{len(typographic_outliers)} of {len(with_desc)} descriptions in the "
        f"{label} carry typographic punctuation ({typographic_carriers}). "
        "ai_instruction_writing bans the em dash and en dash outright in "
        "AI-consumed content, so split the description into two sentences "
        "where a dash joins two clauses; a hyphen, a double hyphen, or an en "
        "dash substituted into that slot keeps the same break and fixes "
        "nothing"
    )

    for report in with_desc:
        desc = report["description"]
        if abs(len(desc) - mean_len) > max(120, mean_len * 0.75):
            findings.append(
                {
                    "severity": "warning",
                    "code": "sibling_length_outlier",
                    "skill": report["name"],
                    "path": report["path"],
                    "group": label,
                    "message": (
                        "description length is an outlier versus its siblings "
                        f"in the {label} (len={len(desc)}, "
                        f"sibling mean≈{mean_len:.0f})"
                    ),
                    "evidence": desc[:120],
                }
            )
        if report["name"] in typographic_outliers:
            findings.append(
                {
                    "severity": "warning",
                    "code": "sibling_typographic_punctuation_outlier",
                    "skill": report["name"],
                    "path": report["path"],
                    "group": label,
                    "message": typographic_message,
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
                    "group": label,
                    "message": (
                        "description carries risky punctuation while its "
                        f"siblings in the {label} stay clear of it"
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
                        "group": label,
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
                        "group": label,
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
    parser.add_argument(
        "--root",
        default=None,
        help=(
            "Repository root whose standing rule files the info tier cites "
            "(default: the nearest root above the first selected skill)"
        ),
    )
    return parser


def resolve_skill_md(raw: str) -> Path:
    path = Path(raw)
    # A path already named like a skill file stays the target even when it is
    # not a regular file, so the harness-skips-it finding can fire on it
    # instead of the selector failing as a missing file.
    if path.is_dir() and not SKILL_FILE_RE.match(path.name):
        found = None
        try:
            for entry in sorted(p.name for p in path.iterdir()):
                if SKILL_FILE_RE.match(entry):
                    found = path / entry
                    if entry == "SKILL.md":
                        break
        except OSError as exc:
            die(f"cannot read {raw}: {exc}")
        if found is None:
            die(f"SKILL.md not found: {raw}")
        path = found
    if not path.exists() and not path.is_symlink():
        die(f"SKILL.md not found: {raw}")
    return path


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    paths = [resolve_skill_md(p) for p in args.paths]
    probed_limit, probe_detail = probe_byte_limit()
    byte_limit, byte_limit_source, byte_limit_detail = resolve_byte_limit(
        probed_limit, probe_detail
    )
    repo_root = Path(args.root).resolve() if args.root else find_repo_root(paths[0])
    reports = [
        analyze_skill(p, byte_limit, repo_root, byte_limit_source) for p in paths
    ]
    # The grouping is derived here from the same `--root` the info tier cites,
    # so a correct family run needs no grouping argument from its caller.
    groups = comparison_groups(
        repo_root,
        [{"name": r["name"], "path": r["path"]} for r in reports],
    )
    extra = sibling_findings(reports, groups)

    blocking: list[dict] = []
    warnings: list[dict] = []
    info: list[dict] = []
    tiers = {"blocking": blocking, "warnings": warnings, "info": info}
    severities = {"blocking": "blocking", "warnings": "warning", "info": "info"}
    for report in reports:
        for tier, bucket in tiers.items():
            for item in report[tier]:
                bucket.append(
                    {
                        "severity": severities[tier],
                        "skill": report["name"],
                        "path": report["path"],
                        **item,
                    }
                )
    for item in extra:
        if item["severity"] == "blocking":
            blocking.append(item)
        elif item["severity"] == "info":
            info.append(item)
        else:
            warnings.append(item)

    # Stable ordering: blocking first already; sort within by path/code.
    for bucket in (blocking, warnings, info):
        bucket.sort(key=lambda x: (x.get("path", ""), x.get("code", "")))

    grouped_names: dict[str, list[str]] = {}
    for report in reports:
        grouped_names.setdefault(groups[report["path"]], []).append(report["name"])

    payload = {
        "skills_checked": [r["name"] for r in reports],
        "comparison_groups": {
            label: sorted(names) for label, names in sorted(grouped_names.items())
        },
        "blocking_count": len(blocking),
        "warning_count": len(warnings),
        "info_count": len(info),
        "blocking": blocking,
        "warnings": warnings,
        "info": info,
        "checks": [
            {
                "check": "skill_file_byte_limit",
                "status": "ran",
                "source": byte_limit_source,
                "detail": byte_limit_detail,
                "limit": byte_limit,
            }
        ],
        "severity_records": [
            {
                "code": "name_directory_mismatch",
                "severity": NAME_DIRECTORY_SEVERITY,
                "record": NAME_DIRECTORY_SEVERITY_RECORD,
            }
        ],
        "repo_root": str(repo_root) if repo_root else None,
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
