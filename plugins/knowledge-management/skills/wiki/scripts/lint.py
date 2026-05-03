#!/usr/bin/env python3
"""lint.py — health-check the wiki.

Audits frontmatter validity, link integrity, markdown style (matching
the format_markdown skill), tag taxonomy compliance, stale content,
oversized pages, source drift, and log rotation. Findings are grouped
by severity so the caller knows what to fix first.

Usage:
    python3 lint.py [WIKI_PATH] [--quiet]

Discovery if WIKI_PATH is omitted (current working directory only):
    1. ./wiki/         → use it
    2. ./.no_wiki  → use ~/wiki
    3. neither         → error; pass an explicit path

Exit codes:
    0  no blocking issues
    1  one or more blocking issues found
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from typing import Iterator


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

def discover_wiki(arg: str | None) -> Path:
    if arg:
        path = Path(arg).expanduser().resolve()
        if not path.is_dir():
            sys.exit(f"wiki path does not exist: {path}")
        return path
    cwd = Path.cwd()
    if (cwd / "wiki").is_dir():
        return (cwd / "wiki").resolve()
    if (cwd / ".no_wiki").is_file():
        home_wiki = Path.home() / "wiki"
        if not home_wiki.is_dir():
            sys.exit(f"wiki not found at {home_wiki}; init it before linting")
        return home_wiki
    sys.exit(
        "no wiki/ or .no_wiki in current directory; pass an explicit path"
    )


# Top-level files that aren't pages but live in the wiki root.
SPECIAL_FILES = ("SCHEMA.md", "index.md", "log.md")

VALID_CONFIDENCE = {"high", "medium", "low"}
REQUIRED_FRONTMATTER = ("title", "created", "updated", "type", "tags", "sources")

# Built-in keys handled by other checks; custom-field validation skips these.
CANONICAL_FRONTMATTER = set(REQUIRED_FRONTMATTER) | {"confidence", "contested", "contradictions"}

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TYPE_ENUM_RE = re.compile(r"^\s*type\s*:\s*([^\n]+)$", re.MULTILINE)


def pluralize_page_dir(page_type: str) -> str:
    """Standard English plural for the wiki's `<type>s` directory convention.

    `entity` → `entities`, `procedure` → `procedures`, `summary` → `summaries`.
    Trailing `y` after a consonant becomes `ies`; otherwise `+s`.
    """
    if len(page_type) >= 2 and page_type.endswith("y") and page_type[-2] not in "aeiou":
        return page_type[:-1] + "ies"
    return page_type + "s"


# ---------------------------------------------------------------------------
# Issue model + reporter
# ---------------------------------------------------------------------------

SEV_BLOCKING = 0
SEV_WARN = 1
SEV_INFO = 2

SEVERITY_LABEL = {SEV_BLOCKING: "blocking", SEV_WARN: "warn", SEV_INFO: "info"}


@dataclass
class Issue:
    severity: int
    category: str
    path: Path
    message: str
    line: int | None = None

    def render(self, wiki: Path) -> str:
        try:
            rel = self.path.relative_to(wiki)
        except ValueError:
            rel = self.path
        loc = f":{self.line}" if self.line else ""
        label = SEVERITY_LABEL[self.severity]
        return f"  [{label:8}] {self.category:14} {rel}{loc}  {self.message}"


# ---------------------------------------------------------------------------
# Minimal YAML-frontmatter parser (stdlib-only)
#
# Handles the subset the wiki uses: scalar key:value, inline list [a, b],
# bool true/false, and trailing # comments. Returns None when frontmatter is
# absent so the caller can flag the page distinctly from "frontmatter parsed
# but missing fields".
# ---------------------------------------------------------------------------

def parse_frontmatter(text: str) -> tuple[dict | None, str]:
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end == -1:
        # Allow files that consist only of frontmatter (no trailing newline).
        end = text.find("\n---", 4)
        if end == -1 or text[end:].strip() != "---":
            return None, text
    block = text[4:end]
    body = text[end + 5:] if text[end:end + 5] == "\n---\n" else ""
    data: dict = {}
    for raw_line in block.splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line or line.startswith(" ") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if not value:
            data[key] = ""
        elif value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            data[key] = [
                item.strip().strip("'\"")
                for item in inner.split(",")
                if item.strip()
            ]
        elif value.lower() in {"true", "false"}:
            data[key] = value.lower() == "true"
        else:
            data[key] = value.strip("'\"")
    return data, body


# ---------------------------------------------------------------------------
# File iteration
# ---------------------------------------------------------------------------

def iter_wiki_pages(wiki: Path, page_dirs: tuple[str, ...]) -> Iterator[Path]:
    for sub in page_dirs:
        d = wiki / sub
        if d.is_dir():
            yield from sorted(d.rglob("*.md"))


def iter_raw_files(wiki: Path) -> Iterator[Path]:
    raw = wiki / "raw"
    if raw.is_dir():
        yield from sorted(raw.rglob("*.md"))


# ---------------------------------------------------------------------------
# Schema / taxonomy
# ---------------------------------------------------------------------------

def _read_schema_frontmatter_block(wiki: Path) -> str | None:
    """Return the body of the ```yaml fenced block under `## Frontmatter` in
    SCHEMA.md, or None if SCHEMA.md is missing, has no Frontmatter section,
    or has no yaml block in it. Both load_page_type_spec and
    load_custom_field_spec parse this block.
    """
    schema = wiki / "SCHEMA.md"
    if not schema.is_file():
        return None
    text = schema.read_text(encoding="utf-8")
    section = re.search(r"##\s+Frontmatter(.+?)(?=\n##\s|\Z)", text, re.DOTALL)
    if not section:
        return None
    yaml_block = re.search(r"```yaml\n(.+?)\n```", section.group(1), re.DOTALL)
    if not yaml_block:
        return None
    return yaml_block.group(1)


def load_page_type_spec(wiki: Path) -> tuple[set[str], tuple[str, ...]] | None:
    """Extract the page-type enum from SCHEMA.md and derive page directories.

    Looks for a `type: a | b | c` line inside the `## Frontmatter` yaml block
    and returns (types_set, dirs_tuple). Returns None when SCHEMA.md is
    missing, has no Frontmatter section, no yaml block in it, or no type
    line — the caller produces a blocking issue and skips type-dependent
    checks.
    """
    block = _read_schema_frontmatter_block(wiki)
    if block is None:
        return None
    match = TYPE_ENUM_RE.search(block)
    if not match:
        return None
    raw = match.group(1).split("#", 1)[0].strip()
    types = [p.strip() for p in raw.split("|") if p.strip()]
    if not types:
        return None
    return set(types), tuple(pluralize_page_dir(t) for t in types)


def load_custom_field_spec(wiki: Path) -> dict[str, set[str] | None]:
    """Extract custom (non-canonical) field declarations from SCHEMA.md's
    `## Frontmatter` yaml block. Returns {field: allowed_values_or_None};
    None means the field is declared without an enum constraint.
    """
    block = _read_schema_frontmatter_block(wiki)
    if block is None:
        return {}
    spec: dict[str, set[str] | None] = {}
    for raw_line in block.splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line or line.startswith(("---", " ", "\t")) or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if not key or key in CANONICAL_FRONTMATTER:
            continue
        if "|" in value:
            spec[key] = {v.strip() for v in value.split("|") if v.strip()}
        else:
            spec[key] = None
    return spec


def load_taxonomy(wiki: Path) -> set[str] | None:
    """Extract the tag taxonomy from SCHEMA.md so off-taxonomy tags can be
    flagged. Returns None when SCHEMA.md is absent or has no taxonomy section
    — the caller treats that as a structural issue.
    """
    schema = wiki / "SCHEMA.md"
    if not schema.is_file():
        return None
    text = schema.read_text(encoding="utf-8")
    match = re.search(r"##\s+Tag Taxonomy(.+?)(?=\n##\s|\Z)", text, re.DOTALL)
    if not match:
        return None
    section = match.group(1)
    tags: set[str] = set()
    # Tags appear as bullets like "- Models: model, architecture, benchmark".
    for line in section.splitlines():
        stripped = line.strip()
        if not stripped.startswith("-"):
            continue
        body = stripped.lstrip("- ").split(":", 1)[-1]
        for tag in body.split(","):
            t = tag.strip().strip("`'\"")
            if t and " " not in t and not t.startswith("["):
                tags.add(t)
    return tags or None


# ---------------------------------------------------------------------------
# Per-check implementations
# ---------------------------------------------------------------------------

def check_frontmatter(
    page: Path, wiki: Path, taxonomy: set[str] | None, valid_types: set[str]
) -> list[Issue]:
    text = page.read_text(encoding="utf-8")
    fm, _ = parse_frontmatter(text)
    issues: list[Issue] = []
    if fm is None:
        issues.append(Issue(SEV_BLOCKING, "frontmatter", page, "missing or malformed frontmatter"))
        return issues

    for field in REQUIRED_FRONTMATTER:
        if field not in fm:
            issues.append(Issue(SEV_BLOCKING, "frontmatter", page, f"missing required field: {field}"))

    if valid_types and "type" in fm and fm["type"] not in valid_types:
        issues.append(Issue(
            SEV_WARN, "frontmatter", page,
            f"invalid type {fm['type']!r} (expected one of {sorted(valid_types)})",
        ))

    for date_field in ("created", "updated"):
        v = fm.get(date_field)
        if isinstance(v, str) and v and not DATE_RE.match(v):
            issues.append(Issue(SEV_WARN, "frontmatter", page, f"{date_field} not in YYYY-MM-DD format: {v!r}"))

    if "confidence" in fm and fm["confidence"] not in VALID_CONFIDENCE:
        issues.append(Issue(SEV_WARN, "frontmatter", page, f"invalid confidence: {fm['confidence']!r}"))

    if taxonomy is not None:
        tags = fm.get("tags") or []
        if isinstance(tags, list):
            for tag in tags:
                if tag and tag not in taxonomy:
                    issues.append(Issue(SEV_WARN, "tag", page, f"tag {tag!r} not in SCHEMA.md taxonomy"))

    return issues


# Match `[text](path)` but ignore image links (`![alt](path)`) and footnotes
# (`[^name]`). Anchor and query-string fragments are stripped before resolving.
LINK_RE = re.compile(r"(?<!\!)\[([^\^\]][^\]]*)\]\(([^)]+)\)")


def extract_md_links(body: str, page: Path) -> list[tuple[Path, str]]:
    out: list[tuple[Path, str]] = []
    for match in LINK_RE.finditer(body):
        text, raw_target = match.group(1), match.group(2)
        target = raw_target.split("#", 1)[0].split(" ", 1)[0].strip()
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        if not target.endswith(".md"):
            continue
        candidate = (page.parent / target).resolve()
        out.append((candidate, text))
    return out


def check_links_and_orphans(wiki: Path, page_dirs: tuple[str, ...]) -> list[Issue]:
    issues: list[Issue] = []
    inbound: dict[Path, int] = defaultdict(int)
    pages = list(iter_wiki_pages(wiki, page_dirs))

    for page in pages:
        _, body = parse_frontmatter(page.read_text(encoding="utf-8"))
        for target, link_text in extract_md_links(body, page):
            if not target.exists():
                try:
                    rel = target.relative_to(wiki)
                except ValueError:
                    rel = target
                issues.append(Issue(
                    SEV_BLOCKING, "broken-link", page,
                    f"link target missing: {rel} ({link_text!r})",
                ))
            else:
                inbound[target] += 1

    for page in pages:
        if inbound[page] == 0:
            issues.append(Issue(SEV_WARN, "orphan", page, "no inbound links from other wiki pages"))

    return issues


def check_index_completeness(wiki: Path, page_dirs: tuple[str, ...]) -> list[Issue]:
    index = wiki / "index.md"
    if not index.is_file():
        return [Issue(SEV_BLOCKING, "structure", index, "index.md missing")]
    index_text = index.read_text(encoding="utf-8")
    issues: list[Issue] = []
    for page in iter_wiki_pages(wiki, page_dirs):
        rel = page.relative_to(wiki).as_posix()
        if rel not in index_text and page.name not in index_text:
            issues.append(Issue(SEV_WARN, "index", page, "page not referenced in index.md"))
    return issues


def check_unused_tags(wiki: Path, taxonomy: set[str], page_dirs: tuple[str, ...]) -> list[Issue]:
    used: set[str] = set()
    for page in iter_wiki_pages(wiki, page_dirs):
        fm, _ = parse_frontmatter(page.read_text(encoding="utf-8"))
        if not fm:
            continue
        tags = fm.get("tags") or []
        if isinstance(tags, list):
            used.update(t for t in tags if t)
    return [
        Issue(SEV_INFO, "tag", wiki / "SCHEMA.md", f"tag {tag!r} defined in taxonomy but unused on any page")
        for tag in sorted(taxonomy - used)
    ]


def check_page_size(wiki: Path, page_dirs: tuple[str, ...]) -> list[Issue]:
    issues: list[Issue] = []
    for page in iter_wiki_pages(wiki, page_dirs):
        line_count = sum(1 for _ in page.read_text(encoding="utf-8").splitlines())
        if line_count > 200:
            issues.append(Issue(SEV_INFO, "size", page, f"{line_count} lines (consider splitting at >200)"))
    return issues


def check_log_rotation(wiki: Path) -> list[Issue]:
    log = wiki / "log.md"
    if not log.is_file():
        return []
    entries = sum(
        1 for line in log.read_text(encoding="utf-8").splitlines()
        if line.startswith("## [")
    )
    if entries > 500:
        return [Issue(SEV_INFO, "log", log, f"{entries} entries — rotate to log-YYYY.md")]
    return []


def check_stale_content(wiki: Path, page_dirs: tuple[str, ...]) -> list[Issue]:
    """A page is stale when its `updated` date trails the most recent
    `ingested` date among its cited raw sources by more than 90 days.
    """
    raw_ingested: dict[str, date] = {}
    for raw in iter_raw_files(wiki):
        fm, _ = parse_frontmatter(raw.read_text(encoding="utf-8"))
        if fm and isinstance(fm.get("ingested"), str):
            try:
                raw_ingested[raw.relative_to(wiki).as_posix()] = date.fromisoformat(fm["ingested"])
            except ValueError:
                continue

    issues: list[Issue] = []
    for page in iter_wiki_pages(wiki, page_dirs):
        fm, _ = parse_frontmatter(page.read_text(encoding="utf-8"))
        if not fm:
            continue
        try:
            updated = date.fromisoformat(str(fm.get("updated", "")))
        except ValueError:
            continue
        sources = fm.get("sources") or []
        if not isinstance(sources, list):
            continue
        max_source_date = max((raw_ingested[s] for s in sources if s in raw_ingested), default=None)
        if max_source_date and (max_source_date - updated) > timedelta(days=90):
            issues.append(Issue(
                SEV_INFO, "stale", page,
                f"updated {updated} but newest cited source is {max_source_date} (>90d gap)",
            ))
    return issues


def check_quality_signals(wiki: Path, page_dirs: tuple[str, ...]) -> list[Issue]:
    issues: list[Issue] = []
    for page in iter_wiki_pages(wiki, page_dirs):
        fm, _ = parse_frontmatter(page.read_text(encoding="utf-8"))
        if not fm:
            continue
        if fm.get("contested") is True:
            issues.append(Issue(SEV_WARN, "quality", page, "contested: true — reconcile or document the dispute"))
        if fm.get("confidence") == "low":
            issues.append(Issue(SEV_INFO, "quality", page, "confidence: low — corroborate or note why"))
        sources = fm.get("sources") or []
        if isinstance(sources, list) and len(sources) == 1 and "confidence" not in fm:
            issues.append(Issue(
                SEV_INFO, "quality", page,
                "single source with no confidence field — set confidence: medium or low",
            ))
    return issues


def check_custom_fields(
    wiki: Path, spec: dict[str, set[str] | None], page_dirs: tuple[str, ...]
) -> list[Issue]:
    """Validate non-canonical frontmatter keys against the SCHEMA.md spec:
    flag pages using undeclared keys, flag values outside the declared enum,
    and surface declared-but-unused fields as info.
    """
    def normalize(v) -> str:
        if isinstance(v, bool):
            return "true" if v else "false"
        return str(v)

    issues: list[Issue] = []
    used_fields: set[str] = set()
    for page in iter_wiki_pages(wiki, page_dirs):
        fm, _ = parse_frontmatter(page.read_text(encoding="utf-8"))
        if not fm:
            continue
        for key, value in fm.items():
            if key in CANONICAL_FRONTMATTER:
                continue
            used_fields.add(key)
            if key not in spec:
                issues.append(Issue(
                    SEV_WARN, "custom-field", page,
                    f"custom field {key!r} not declared in SCHEMA.md ## Frontmatter",
                ))
                continue
            allowed = spec[key]
            if allowed is None:
                continue
            values = value if isinstance(value, list) else [value]
            for v in values:
                if v == "" or v is None:
                    continue
                norm = normalize(v)
                if norm not in allowed:
                    issues.append(Issue(
                        SEV_WARN, "custom-field", page,
                        f"{key}: value {norm!r} not in declared set {sorted(allowed)}",
                    ))
    for key in sorted(set(spec) - used_fields):
        issues.append(Issue(
            SEV_INFO, "custom-field", wiki / "SCHEMA.md",
            f"custom field {key!r} declared in SCHEMA.md but unused on any page",
        ))
    return issues


def check_source_drift(wiki: Path) -> list[Issue]:
    issues: list[Issue] = []
    for raw in iter_raw_files(wiki):
        text = raw.read_text(encoding="utf-8")
        fm, body = parse_frontmatter(text)
        if not fm or "sha256" not in fm:
            continue
        recorded = str(fm.get("sha256", ""))
        if not recorded:
            continue
        actual = hashlib.sha256(body.encode("utf-8")).hexdigest()
        if recorded != actual:
            issues.append(Issue(
                SEV_WARN, "drift", raw,
                f"sha256 mismatch (recorded {recorded[:12]}…, actual {actual[:12]}…)",
            ))
    return issues


# ---------------------------------------------------------------------------
# Markdown style (subset matching the format_markdown skill)
#
# These rules match what format_markdown asks authors to do. The checks here
# stay conservative — only clear violations are flagged so style noise
# doesn't drown out the structural findings above.
# ---------------------------------------------------------------------------

BAD_BULLET_RE = re.compile(r"^\s*[\*\+]\s")
HEADER_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
FENCE_RE = re.compile(r"^```(\w*)\s*$")
LIST_MARKER_RE = re.compile(r"^(\s*-)([^\s])")
BARE_URL_RE = re.compile(r"(?<![<\(\"\[/])(https?://\S+)")


def check_markdown_style(wiki: Path, page_dirs: tuple[str, ...]) -> list[Issue]:
    issues: list[Issue] = []
    targets = list(iter_wiki_pages(wiki, page_dirs))
    for special in SPECIAL_FILES:
        candidate = wiki / special
        if candidate.is_file():
            targets.append(candidate)

    for page in targets:
        text = page.read_text(encoding="utf-8")
        # Style checks operate on the body — frontmatter follows YAML rules.
        if text.startswith("---"):
            _, body = parse_frontmatter(text)
        else:
            body = text
        lines = body.splitlines()

        if not text.endswith("\n"):
            issues.append(Issue(SEV_INFO, "md-style", page, "file does not end with a newline"))
        elif text.endswith("\n\n"):
            issues.append(Issue(SEV_INFO, "md-style", page, "file ends with multiple blank lines"))

        blank_run = 0
        in_fence = False
        last_header_level = 0
        for i, line in enumerate(lines, start=1):
            stripped = line.strip()
            fence = FENCE_RE.match(stripped)
            if fence:
                if not in_fence and not fence.group(1):
                    issues.append(Issue(
                        SEV_INFO, "md-style", page,
                        "fenced code block missing language identifier", line=i,
                    ))
                in_fence = not in_fence
                blank_run = 0
                continue

            if in_fence:
                continue

            if stripped == "":
                blank_run += 1
                if blank_run > 1:
                    issues.append(Issue(
                        SEV_INFO, "md-style", page,
                        "more than one consecutive blank line", line=i,
                    ))
                continue
            blank_run = 0

            if BAD_BULLET_RE.match(line):
                issues.append(Issue(
                    SEV_INFO, "md-style", page,
                    "use '-' for unordered list bullets (not * or +)", line=i,
                ))

            if LIST_MARKER_RE.match(line):
                issues.append(Issue(
                    SEV_INFO, "md-style", page,
                    "list marker missing single space after '-'", line=i,
                ))

            header = HEADER_RE.match(line)
            if header:
                level = len(header.group(1))
                title = header.group(2)
                if last_header_level and level > last_header_level + 1:
                    issues.append(Issue(
                        SEV_INFO, "md-style", page,
                        f"header skips levels (H{last_header_level} -> H{level})", line=i,
                    ))
                last_header_level = level
                if title and title[-1] in ".,;:!":
                    issues.append(Issue(
                        SEV_INFO, "md-style", page,
                        "header has trailing punctuation", line=i,
                    ))

            for url_match in BARE_URL_RE.finditer(line):
                issues.append(Issue(
                    SEV_INFO, "md-style", page,
                    f"bare URL (wrap with <> or use [text](url)): {url_match.group(1)}",
                    line=i,
                ))
                break  # one finding per line is enough

    return issues


# ---------------------------------------------------------------------------
# Reporter
# ---------------------------------------------------------------------------

def render_report(wiki: Path, issues: list[Issue], quiet: bool) -> str:
    if quiet:
        issues = [i for i in issues if i.severity != SEV_INFO]

    if not issues:
        return f"clean — no issues in {wiki}"

    issues.sort(key=lambda i: (i.severity, i.category, str(i.path), i.line or 0))
    by_sev: dict[int, list[Issue]] = defaultdict(list)
    for i in issues:
        by_sev[i.severity].append(i)

    out = [f"audit of {wiki}", ""]
    for sev in (SEV_BLOCKING, SEV_WARN, SEV_INFO):
        bucket = by_sev.get(sev, [])
        if not bucket:
            continue
        out.append(f"{SEVERITY_LABEL[sev].upper()} ({len(bucket)})")
        for issue in bucket:
            out.append(issue.render(wiki))
        out.append("")

    counts = Counter(i.severity for i in issues)
    summary = ", ".join(
        f"{counts.get(s, 0)} {SEVERITY_LABEL[s]}"
        for s in (SEV_BLOCKING, SEV_WARN, SEV_INFO)
    )
    out.append(f"total: {len(issues)}  ({summary})")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Health-check the wiki: frontmatter, links, markdown style, tags, and more.",
    )
    parser.add_argument(
        "wiki_path",
        nargs="?",
        help="Path to the wiki directory. If omitted, uses ./wiki/ (or ~/wiki when ./.no_wiki is present).",
    )
    parser.add_argument("--quiet", action="store_true", help="Suppress info-level findings.")
    args = parser.parse_args()

    wiki = discover_wiki(args.wiki_path)
    if not wiki.is_dir():
        sys.exit(f"wiki not found at {wiki}")

    issues: list[Issue] = []

    type_spec = load_page_type_spec(wiki)
    if type_spec is None:
        issues.append(Issue(
            SEV_BLOCKING, "schema", wiki / "SCHEMA.md",
            "cannot extract page-type enum — SCHEMA.md must contain a "
            "`## Frontmatter` section with a ```yaml block declaring "
            "`type: a | b | c`; type-dependent checks skipped",
        ))
        valid_types: set[str] = set()
        page_dirs: tuple[str, ...] = ()
    else:
        valid_types, page_dirs = type_spec

    taxonomy = load_taxonomy(wiki)
    custom_spec = load_custom_field_spec(wiki)

    if taxonomy is None:
        issues.append(Issue(
            SEV_WARN, "schema", wiki / "SCHEMA.md",
            "missing SCHEMA.md or no Tag Taxonomy section — tag compliance not checked",
        ))

    if page_dirs:
        for page in iter_wiki_pages(wiki, page_dirs):
            issues.extend(check_frontmatter(page, wiki, taxonomy, valid_types))

        issues.extend(check_links_and_orphans(wiki, page_dirs))
        issues.extend(check_index_completeness(wiki, page_dirs))
        if taxonomy:
            issues.extend(check_unused_tags(wiki, taxonomy, page_dirs))
        issues.extend(check_page_size(wiki, page_dirs))
        issues.extend(check_stale_content(wiki, page_dirs))
        issues.extend(check_quality_signals(wiki, page_dirs))
        issues.extend(check_custom_fields(wiki, custom_spec, page_dirs))
        issues.extend(check_markdown_style(wiki, page_dirs))

    issues.extend(check_log_rotation(wiki))
    issues.extend(check_source_drift(wiki))

    print(render_report(wiki, issues, args.quiet))
    return 1 if any(i.severity == SEV_BLOCKING for i in issues) else 0


if __name__ == "__main__":
    sys.exit(main())
