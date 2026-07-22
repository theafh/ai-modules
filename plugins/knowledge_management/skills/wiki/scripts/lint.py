#!/usr/bin/env python3
"""lint.py — health-check the wiki.

Audits frontmatter validity, link integrity, markdown style (matching
the format_markdown skill), tag taxonomy compliance, stale content,
oversized pages, source drift, and log rotation. Findings are grouped
by severity so the caller knows what to fix first.

Usage:
    python3 lint.py [WIKI_PATH] [--quiet]

Discovery if WIKI_PATH is omitted (mirrors ``scripts/discover_wiki.sh``):
    A directory is a wiki when its basename contains "wiki"
    (case-insensitive) and at least two of SCHEMA.md / index.md / log.md
    exist in it and it carries no ``.no_wiki``. If CWD is itself a wiki,
    resolve to it directly. Otherwise walk up from CWD toward ``$HOME``:
    at each level ``.no_wiki`` skips to the parent and the first child
    directory recognised as a wiki terminates the walk. Auto-resolve when
    the closest non-opted-out level holds a recognised wiki, or when every
    level up through ``$HOME`` is opted out (use ``$HOME/wiki``).
    Otherwise — no recognised wiki, only creation candidates — exit 2 with
    the candidate list and a hint to pass the wiki path as the positional
    argument, since lint runs non-interactively. Outside ``$HOME``, fall
    back: a recognised wiki child of CWD → use it, ``./.no_wiki`` → use
    ``~/wiki``, neither → exit 2 with the two-candidate list.

Exit codes:
    0  no blocking issues
    1  one or more blocking issues found
    2  wiki location undecided (discovery could not pick a wiki)
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from typing import Callable, Iterator


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

def is_wiki(d: Path) -> bool:
    """True when ``d`` is a usable wiki: it carries no ``.no_wiki`` opt-out,
    its basename contains "wiki" (case-insensitive), and at least two of the
    ``SPECIAL_FILES`` markers (SCHEMA.md / index.md / log.md) exist directly
    inside it. ``.no_wiki`` takes precedence, so a retired wiki is dropped.
    """
    if (d / ".no_wiki").is_file():
        return False
    if "wiki" not in d.name.lower():
        return False
    present = sum(1 for marker in SPECIAL_FILES if (d / marker).is_file())
    return present >= 2


def discover_wiki(arg: str | None) -> Path:
    """Resolve the wiki, mirroring ``scripts/discover_wiki.sh``.

    A directory is a wiki per ``is_wiki`` (name contains "wiki" + >=2
    markers, no ``.no_wiki``). If CWD is itself a wiki, resolve to it
    directly. Otherwise walk up from CWD to ``$HOME``: ``.no_wiki`` skips a
    level, the first child (lexical order) recognised as a wiki terminates
    the walk, every other level becomes a creation candidate. Auto-resolves
    when the closest non-opted-out level holds a recognised wiki, or when
    every level up through ``$HOME`` is opted out (use ``$HOME/wiki``).
    Exits 2 with a candidate list and a positional-argument hint when the
    climb leaves only creation candidates — lint runs non-interactively.
    """
    if arg:
        path = Path(arg).expanduser().resolve()
        if not path.is_dir():
            sys.exit(f"wiki path does not exist: {path}")
        return path

    cwd = Path.cwd().resolve()
    home = Path.home().resolve()

    # Standing in a wiki resolves to it directly, before any walk-up and
    # before the under-/outside-$HOME split. .no_wiki at CWD suppresses this
    # (folded into is_wiki), so a retired wiki you stand in is not resolved.
    if is_wiki(cwd):
        return cwd

    under_home = cwd == home or home in cwd.parents

    if under_home:
        ladder: list[Path] = []
        level = cwd
        while True:
            ladder.append(level)
            if level == home:
                break
            parent = level.parent
            if parent == level:
                break
            level = parent
    else:
        ladder = [cwd]

    candidates: list[tuple[str, Path]] = []
    for level in ladder:
        if (level / ".no_wiki").is_file():
            continue
        try:
            children = sorted(level.iterdir())
        except OSError:
            children = []
        existing = next((c for c in children if c.is_dir() and is_wiki(c)), None)
        if existing is not None:
            candidates.append(("existing", existing.resolve()))
            break
        candidates.append(("available", level))

    # Outside-$HOME single-CWD fallback: if the walk-up is disabled and the
    # CWD did not yield an existing wiki, append $HOME as a second creation
    # candidate so the caller can pick "create here or fall back to the
    # global wiki" — mirrors discover_wiki.sh's same-named branch.
    if not under_home and candidates and candidates[-1][0] != "existing":
        candidates.append(("available", home))

    if not candidates:
        home_wiki = home / "wiki"
        if not home_wiki.is_dir():
            sys.exit(f"wiki not found at {home_wiki}; init it before linting")
        return home_wiki

    if candidates[0][0] == "existing":
        return candidates[0][1]

    listing = "\n  ".join(f"{kind}: {path}" for kind, path in candidates)
    print(
        "wiki location is undecided; pass the wiki path as the positional "
        f"argument, e.g. `python3 lint.py /path/to/wiki`. walk-up candidates "
        f"from {cwd} were:\n  {listing}",
        file=sys.stderr,
    )
    sys.exit(2)


# Top-level files that aren't pages but live in the wiki root.
SPECIAL_FILES = ("SCHEMA.md", "index.md", "log.md")

VALID_CONFIDENCE = {"high", "medium", "low"}
REQUIRED_FRONTMATTER = ("title", "created", "updated", "type", "tags", "sources")

# Built-in keys handled by other checks; custom-field validation skips these.
CANONICAL_FRONTMATTER = set(REQUIRED_FRONTMATTER) | {"confidence", "contested", "contradictions"}

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TYPE_ENUM_RE = re.compile(r"^\s*type\s*:\s*([^\n]+)$", re.MULTILINE)

# A leading `scheme://` on an origin-field value. `file://` denotes a local
# file; every other scheme (`https`, `http`, `s3`, `ftp`, …) denotes a remote,
# externally-fetched resource. The raw origin-field-form check keys off this
# split: `source_url:` wants a remote scheme, `source_path:` wants a bare
# repo-relative path carrying no scheme at all.
SCHEME_RE = re.compile(r"^([a-zA-Z][a-zA-Z0-9+.\-]*)://")


def uri_scheme(value: str) -> str | None:
    """Return the lowercased `scheme` of a `scheme://…` value, or None when the
    value carries no `scheme://` prefix (a bare relative or absolute path)."""
    match = SCHEME_RE.match(value.strip())
    return match.group(1).lower() if match else None


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
# block-style scalar list (a key with an empty value followed by indented
# `- item` lines), bool true/false, and trailing # comments. Returns None when
# frontmatter is absent so the caller can flag the page distinctly from
# "frontmatter parsed but missing fields". A general-purpose YAML parser stays
# out of scope — only block scalar lists grow the parser beyond inline lists.
# ---------------------------------------------------------------------------

def _split_frontmatter(text: str) -> tuple[str | None, str]:
    """Split `text` into (frontmatter_block, body).

    Returns (None, text) when there is no leading `---` frontmatter. Shared by
    ``parse_frontmatter`` and the frontmatter block-content belt check so the
    fence-boundary logic lives in exactly one place.
    """
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
    return block, body


def _collect_block_list(lines: list[str], i: int) -> tuple[list[str], int]:
    """From line index `i`, collect a YAML block-style list of scalars — a run
    of indented ``- item`` lines — and return (items, next_index).

    Stops at the first blank line, non-indented line, or indented line that is
    not a ``- `` item (for example an indented ``key: value`` nested mapping),
    leaving that line for the caller to handle. Only block scalar lists grow
    the parser; nested structures are deliberately left unread so the belt
    check can flag them.
    """
    items: list[str] = []
    n = len(lines)
    while i < n:
        raw = lines[i]
        stripped = raw.split("#", 1)[0].strip()
        if not stripped:
            break                        # blank/comment-only line ends the value
        if not raw[:1].isspace():
            break                        # not indented -> end of this value
        if stripped[0] == "-" and (len(stripped) == 1 or stripped[1] in (" ", "\t")):
            item = stripped[1:].strip().strip("'\"")
            if item:
                items.append(item)
            i += 1
        else:
            break                        # indented, but not a `- ` list item
    return items, i


def parse_frontmatter(text: str) -> tuple[dict | None, str]:
    block, body = _split_frontmatter(text)
    if block is None:
        return None, body
    data: dict = {}
    lines = block.splitlines()
    i, n = 0, len(lines)
    while i < n:
        line = lines[i].split("#", 1)[0].rstrip()
        i += 1
        if not line or line[0] in (" ", "\t") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if not value:
            # A key with no inline value may head a block-style list; collect
            # any indented `- item` lines that follow. Unreadable indented
            # content leaves the value empty for the belt check to flag.
            items, i = _collect_block_list(lines, i)
            data[key] = items if items else ""
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


def _field_has_indented_block(text: str, key: str) -> bool:
    """True when frontmatter ``key:`` carries an empty inline value and is
    immediately followed by indented block content.

    Used to flag a required list field whose block the scalar-list parser
    could not read (for example a nested mapping such as an indented
    ``domain: ai`` line rather than ``- item`` lines).
    """
    block, _ = _split_frontmatter(text)
    if block is None:
        return False
    lines = block.splitlines()
    for idx, raw in enumerate(lines):
        if raw[:1].isspace():
            continue
        k, sep, v = raw.split("#", 1)[0].rstrip().partition(":")
        if not sep or k.strip() != key or v.strip():
            continue
        nxt = lines[idx + 1] if idx + 1 < len(lines) else ""
        return bool(nxt[:1].isspace()) and bool(nxt.split("#", 1)[0].strip())
    return False


# ---------------------------------------------------------------------------
# File iteration
# ---------------------------------------------------------------------------

# A single bullet in SCHEMA.md's ``## Lint`` section names extra top-level
# directories to skip during the page walk: ``- Page-check exclusions: a, b``
# (comma-separated dir names directly under the wiki root). ``-``/``*``/``+``
# are all accepted as the marker; the label is matched case-insensitively.
LINT_EXCLUDE_RE = re.compile(
    r"^\s*[-*+]\s+page-check exclusions\s*:\s*(.+)$",
    re.IGNORECASE,
)


def load_excluded_roots(wiki: Path) -> set[str]:
    """Top-level directory names to skip during the page walk.

    Always skips ``raw`` and ``_archive``. A wiki adds more by listing them
    on a ``- Page-check exclusions: a, b`` bullet inside a ``## Lint``
    section in SCHEMA.md — directory names directly under the wiki root,
    comma-separated, additive to the two defaults. A vault that mixes
    curated pages with operational or imported subtrees keeps the page rules
    off those trees this way.

    The scan is scoped to the ``## Lint`` section and skips fenced code
    blocks within it, mirroring ``load_taxonomy`` and the body scanners — so
    the bullet shown inside a fenced example (in the canonical template, or
    where a vault documents its own list) is never read as live config.
    Absent section or bullet leaves the default ``{raw, _archive}``
    unchanged, so existing vaults are unaffected.
    """
    roots = {"raw", "_archive"}
    schema = wiki / "SCHEMA.md"
    if not schema.is_file():
        return roots
    section = re.search(
        r"##\s+Lint(.+?)(?=\n##\s|\Z)", schema.read_text(encoding="utf-8"), re.DOTALL
    )
    if not section:
        return roots
    in_fence = False
    for line in section.group(1).splitlines():
        if FENCE_RE.match(line.strip()):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = LINT_EXCLUDE_RE.match(line)
        if m:
            roots |= {p.strip().strip("`*_'\"") for p in m.group(1).split(",") if p.strip()}
    return roots


def iter_wiki_pages(wiki: Path) -> Iterator[Path]:
    """Yield every page in the wiki, regardless of folder organization.

    Walks the whole tree so misfiled pages are discovered too — the type-
    location check needs to see them in order to flag them. Skips the wiki
    root (SCHEMA.md, index.md, log.md and any other root-level markdown),
    the ``raw/`` source tree, the ``_archive/`` tree, and hidden directories.
    """
    excluded_roots = load_excluded_roots(wiki)
    for path in sorted(wiki.rglob("*.md")):
        if path.parent == wiki:
            continue
        rel_parts = path.relative_to(wiki).parts
        if rel_parts[0] in excluded_roots:
            continue
        if any(part.startswith(".") for part in rel_parts[:-1]):
            continue
        yield path


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


_BULLET_MARKERS = ("-", "*", "+")
_EMPHASIS_RUN = re.compile(r"^[*_]+|[*_]+$")


def _coalesce_taxonomy_bullets(section: str) -> list[str]:
    """Walk the Tag Taxonomy section once and return one joined string per
    logical bullet. A bullet starts on any line whose first non-whitespace
    character is `-`, `*`, or `+` followed by whitespace (or end of line).
    Subsequent non-blank lines that do not themselves start a new bullet are
    treated as CommonMark soft-wrap continuations and folded into the
    in-progress bullet. Blank lines and the end of the section flush.
    """
    bullets: list[str] = []
    current: list[str] = []

    def flush() -> None:
        if current:
            bullets.append(" ".join(current))
            current.clear()

    for raw_line in section.splitlines():
        stripped = raw_line.lstrip()
        if not stripped:
            flush()
            continue
        is_bullet = (
            stripped[0] in _BULLET_MARKERS
            and (len(stripped) == 1 or stripped[1] in (" ", "\t"))
        )
        if is_bullet:
            flush()
            current.append(stripped[1:].strip())
        elif current:
            current.append(stripped)
    flush()
    return bullets


def load_taxonomy(wiki: Path) -> set[str] | None:
    """Extract the tag taxonomy from SCHEMA.md so off-taxonomy tags can be
    flagged. Returns None when SCHEMA.md is absent or has no taxonomy section
    — the caller treats that as a structural issue.

    The parser tolerates common Markdown variations in the Tag Taxonomy
    section so SCHEMA authors do not have to coddle it:

    - Emphasis around the category label is stripped on both sides of the
      colon, so `- **Life domains:**`, `- *Life domains:*`,
      `- __Life domains:__`, and `- _Life domains:_` parse the same as
      `- Life domains:`.
    - Soft-wrapped bullets are folded into one logical bullet before the
      colon split, so a long taxonomy line broken across physical lines
      (CommonMark continuation) contributes every tag.
    - `-`, `*`, and `+` are all accepted as bullet markers regardless of
      what `format_markdown` says elsewhere — robustness here matters more
      than style enforcement, since style is flagged by a separate check.
    - Bullets without a colon contribute no tags (the line has no taxonomy
      entries to extract) instead of accidentally consuming the label as
      a tag.
    - Per-tag cleanup strips surrounding backticks, emphasis markers, and
      quotes so `` `model` ``, `*model*`, and `'model'` all yield `model`.
    """
    schema = wiki / "SCHEMA.md"
    if not schema.is_file():
        return None
    text = schema.read_text(encoding="utf-8")
    match = re.search(r"##\s+Tag Taxonomy(.+?)(?=\n##\s|\Z)", text, re.DOTALL)
    if not match:
        return None

    tags: set[str] = set()
    # Skip fenced code blocks, mirroring load_excluded_roots: a taxonomy shown
    # inside a fenced example (the canonical template's "Example for AI/ML:"
    # block) is documentation, never read as the live tag set.
    for bullet in _coalesce_taxonomy_bullets(strip_fenced_blocks(match.group(1))):
        _, sep, body = bullet.partition(":")
        if not sep:
            continue
        # The closing emphasis of `**Label:**` lands at the start of `body`
        # (because the colon sits inside the bold pair); strip it before
        # splitting on commas.
        body = _EMPHASIS_RUN.sub("", body.strip()).strip()
        for raw_tag in body.split(","):
            t = raw_tag.strip().strip("`*_'\"")
            if t and " " not in t and not t.startswith("["):
                tags.add(t)
    return tags or None


def check_taxonomy_style(wiki: Path) -> list[Issue]:
    """Surface SCHEMA.md Tag Taxonomy formatting that the loader tolerates
    but that authors should simplify so the canonical form stays
    `- Label: tag, tag, …` on one line. The parser leniency in
    `load_taxonomy` is a safety net, not an endorsement — this check
    nudges the SCHEMA back toward the plain form so the leniency does not
    become load-bearing.

    Flags three patterns inside the Tag Taxonomy section:

    - Bullet marker other than `-` (`*` or `+`).
    - Emphasis around the category label (`**Label:**`, `*Label:*`,
      `__Label:__`, `_Label:_`, and their combinations).
    - Soft-wrap continuation lines (a bullet split across physical lines).
    """
    schema = wiki / "SCHEMA.md"
    if not schema.is_file():
        return []
    text = schema.read_text(encoding="utf-8")
    match = re.search(r"##\s+Tag Taxonomy(.+?)(?=\n##\s|\Z)", text, re.DOTALL)
    if not match:
        return []

    # Map offsets within the section back to line numbers in SCHEMA.md so
    # findings point at the line a reader can open directly.
    section_start_line = text[:match.start(1)].count("\n") + 1

    issues: list[Issue] = []
    in_bullet = False
    in_fence = False
    bullet_start_line = 0
    for offset, raw_line in enumerate(match.group(1).splitlines()):
        line_no = section_start_line + offset
        stripped = raw_line.lstrip()
        if FENCE_RE.match(raw_line.strip()):
            in_fence = not in_fence
            in_bullet = False
            continue
        if in_fence:
            continue
        if not stripped:
            in_bullet = False
            continue
        is_bullet = (
            stripped[0] in _BULLET_MARKERS
            and (len(stripped) == 1 or stripped[1] in (" ", "\t"))
        )
        if is_bullet:
            marker = stripped[0]
            if marker != "-":
                issues.append(Issue(
                    SEV_INFO, "taxonomy-style", schema,
                    f"bullet marker {marker!r} in Tag Taxonomy; "
                    f"use '-' for the canonical taxonomy form",
                    line=line_no,
                ))
            after_marker = stripped[1:].lstrip()
            label_part = after_marker.split(":", 1)[0]
            if _EMPHASIS_RUN.search(label_part):
                issues.append(Issue(
                    SEV_INFO, "taxonomy-style", schema,
                    "category label has emphasis (*, **, _, __); "
                    "use plain `- Label: tag, tag, …` form",
                    line=line_no,
                ))
            in_bullet = True
            bullet_start_line = line_no
        elif in_bullet:
            issues.append(Issue(
                SEV_INFO, "taxonomy-style", schema,
                f"soft-wrap continuation of bullet from line "
                f"{bullet_start_line}; keep each taxonomy entry on a "
                f"single line so the canonical form is one bullet per line",
                line=line_no,
            ))
    return issues


# ---------------------------------------------------------------------------
# Verbatim boilerplate (deterministic prelude/preamble enforcement)
#
# Some regions of a wiki must match the canonical template byte for byte
# (e.g., the SCHEMA.md prelude carrying the "managed by the wiki skill"
# attribution paragraph, or the log.md preamble with its append-only
# conventions). The agent's diff-driven scaffold audit catches drift in
# theory but depends on diligence; this check enforces verbatim equality
# deterministically, so the lint output is the structural source of truth.
#
# Add another VerbatimSlot to extend coverage. Each slot pairs a wiki
# file with its canonical template and an extractor that returns the
# region to compare. The default extractor returns everything above the
# first `## ` second-level heading — pluggable for future slots whose
# verbatim region has a different shape.
# ---------------------------------------------------------------------------

REFERENCES_DIR = Path(__file__).resolve().parent.parent / "references"


def extract_h1_prelude(text: str) -> str:
    """Return everything from the start of `text` up to (but not including)
    the first `## ` second-level heading. Trailing newlines are stripped so
    equal preludes compare equal regardless of trailing whitespace.

    The prelude is the canonical home for "must-stay-verbatim" content like
    the attribution paragraph in SCHEMA.md or the conventions blockquote in
    log.md — everything above where configurable section bodies begin.
    """
    out: list[str] = []
    for line in text.splitlines(keepends=True):
        if line.startswith("## "):
            break
        out.append(line)
    return "".join(out).rstrip("\n")


@dataclass(frozen=True)
class VerbatimSlot:
    """A region of a wiki file required to match its canonical template."""
    wiki_file: str
    template_file: str
    label: str
    extract: Callable[[str], str] = extract_h1_prelude


VERBATIM_SLOTS: tuple[VerbatimSlot, ...] = (
    VerbatimSlot(
        wiki_file="SCHEMA.md",
        template_file="template_schema.md",
        label="SCHEMA.md prelude (H1 plus paragraphs above first `##`)",
    ),
    VerbatimSlot(
        wiki_file="log.md",
        template_file="template_log.md",
        label="log.md preamble (H1 plus blockquote above first `##`)",
    ),
)


def check_verbatim_boilerplate(wiki: Path) -> list[Issue]:
    """Compare each VERBATIM_SLOT region against its canonical template
    and warn on mismatch. Deterministic and independent of any other
    check — the agent treats this output as structural source of truth
    for these slots.
    """
    issues: list[Issue] = []
    for slot in VERBATIM_SLOTS:
        wiki_path = wiki / slot.wiki_file
        template_path = REFERENCES_DIR / slot.template_file
        if not wiki_path.is_file() or not template_path.is_file():
            continue
        wiki_region = slot.extract(wiki_path.read_text(encoding="utf-8"))
        canonical_region = slot.extract(template_path.read_text(encoding="utf-8"))
        if wiki_region == canonical_region:
            continue
        issues.append(Issue(
            SEV_WARN, "boilerplate", wiki_path,
            f"{slot.label} differs from canonical "
            f"references/{slot.template_file}; restore the region verbatim "
            f"or update the template if the change is intentional",
        ))
    return issues


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

    # Belt for a list-valued field the parser could not read: present with an
    # empty value while the raw block shows indented content (a nested mapping
    # or other non-`- item` shape). A readable inline or block list parses to a
    # list and clears this.
    for list_field in ("tags", "sources"):
        if fm.get(list_field) == "" and _field_has_indented_block(text, list_field):
            issues.append(Issue(
                SEV_WARN, "frontmatter", page,
                f"`{list_field}:` has an empty value with indented block content "
                f"the parser could not read as a list — write it as an inline "
                f"`[a, b]` list or a block list of `- item` lines",
            ))

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


def extract_md_links(body: str, page: Path) -> list[tuple[Path, str, str]]:
    """Resolve every local `.md` markdown link in `body`.

    Yields ``(resolved_target, link_text, target)`` per link. ``target`` is the
    path exactly as written (anchor and query string stripped) so a caller can
    flag a non-portable absolute or ``~``-prefixed link that would still
    resolve on the author's machine. Image links, footnotes, external URLs,
    ``mailto:``, and non-``.md`` targets are dropped.
    """
    out: list[tuple[Path, str, str]] = []
    for match in LINK_RE.finditer(body):
        text, raw_target = match.group(1), match.group(2)
        target = raw_target.split("#", 1)[0].split(" ", 1)[0].strip()
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        if not target.endswith(".md"):
            continue
        candidate = (page.parent / target).resolve()
        out.append((candidate, text, target))
    return out


def check_links_and_orphans(wiki: Path) -> list[Issue]:
    issues: list[Issue] = []
    inbound: dict[Path, int] = defaultdict(int)
    pages = list(iter_wiki_pages(wiki))

    for page in pages:
        _, body = parse_frontmatter(page.read_text(encoding="utf-8"))
        # Skip fenced and inline code so a documentation example link is never
        # read as a live link — neither blocking as broken nor counted inbound.
        for target, link_text, raw_target in extract_md_links(strip_code(body), page):
            if Path(raw_target).is_absolute() or raw_target.startswith("~"):
                issues.append(Issue(
                    SEV_BLOCKING, "broken-link", page,
                    f"link target is an absolute/home path — use a relative path "
                    f"that resolves on every clone, not just this machine: "
                    f"{raw_target} ({link_text!r})",
                ))
            elif not target.exists():
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


def check_type_location(
    wiki: Path, valid_types: set[str], page_dirs: tuple[str, ...]
) -> list[Issue]:
    """Enforce the flat ``<type>s/<slug>.md`` layout.

    Two structural rules:

    1. **Every expected type folder exists.** SCHEMA.md's `type:` enum
       pluralizes into a fixed set of folder names; each gets a WARN when
       missing on disk so structural drift is visible immediately.
    2. **Every page lives directly at ``<type>s/<slug>.md``.** A page with
       ``type: concept`` belongs at ``concepts/<slug>.md`` — not in a
       thematic prefix (``ai/concepts/<slug>.md``), not nested inside the
       type folder (``concepts/ai/<slug>.md``), not bare at the root. Misfiled
       pages BLOCK with a concrete move suggestion. The pluralized type
       folder is therefore the *only* layer the wiki tree expresses;
       thematic scope belongs in ``tags:`` and ``type:``, not folder names.

    The ``_archive/`` tree mirrors the type layout for archived pages and is
    excluded from page iteration upstream, so archive contents do not block.
    """
    issues: list[Issue] = []

    for dir_name in page_dirs:
        if not (wiki / dir_name).is_dir():
            issues.append(Issue(
                SEV_WARN, "structure", wiki / dir_name,
                f"expected type folder `{dir_name}/` missing — declared in "
                f"SCHEMA.md `type:` enum but absent on disk",
            ))

    if not valid_types:
        return issues

    for page in iter_wiki_pages(wiki):
        fm, _ = parse_frontmatter(page.read_text(encoding="utf-8"))
        if not fm:
            continue
        ptype = fm.get("type")
        if not isinstance(ptype, str) or ptype not in valid_types:
            continue
        expected_dir = pluralize_page_dir(ptype)
        rel = page.relative_to(wiki)
        rel_parts = rel.parts
        if len(rel_parts) == 2 and rel_parts[0] == expected_dir:
            continue
        suggested = f"{expected_dir}/{page.name}"
        issues.append(Issue(
            SEV_BLOCKING, "structure", page,
            f"page declares `type: {ptype}` but lives at {rel.as_posix()} — "
            f"move to {suggested} (flat `<type>s/<slug>.md` layout; thematic "
            f"scope belongs in `tags:` / `type:`, not folder names)",
        ))
    return issues


def check_index_completeness(wiki: Path) -> list[Issue]:
    index = wiki / "index.md"
    if not index.is_file():
        return [Issue(SEV_BLOCKING, "structure", index, "index.md missing")]
    index_text = index.read_text(encoding="utf-8")
    issues: list[Issue] = []
    # Resolve the index's markdown link targets once, then match both
    # directions on resolved paths rather than substring containment — so a
    # filename that is a substring of a listed one (alignment.md inside
    # misalignment.md) no longer counts as listed. Fenced/inline code is
    # stripped so a documented example link is never read as a live entry.
    linked = {target for target, _text, _raw in extract_md_links(strip_code(index_text), index)}

    # Membership: every content page on disk must be linked from the index.
    for page in iter_wiki_pages(wiki):
        if page.resolve() not in linked:
            issues.append(Issue(SEV_WARN, "index", page, "page not referenced in index.md"))

    # Dangling: every page the index links must resolve on disk. index.md sits
    # outside the page walk, so this is the only check that sees a stale entry
    # left behind when a page is renamed, moved, or archived.
    for target in sorted(linked):
        if not target.exists():
            try:
                rel = target.relative_to(wiki)
            except ValueError:
                rel = target
            issues.append(Issue(
                SEV_WARN, "index", index,
                f"index.md links a page that does not exist on disk: {rel}",
            ))
    return issues


def check_unused_tags(wiki: Path, taxonomy: set[str]) -> list[Issue]:
    used: set[str] = set()
    for page in iter_wiki_pages(wiki):
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


def check_page_size(wiki: Path) -> list[Issue]:
    issues: list[Issue] = []
    for page in iter_wiki_pages(wiki):
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


def check_stale_content(wiki: Path) -> list[Issue]:
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
    for page in iter_wiki_pages(wiki):
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


def check_quality_signals(wiki: Path) -> list[Issue]:
    issues: list[Issue] = []
    for page in iter_wiki_pages(wiki):
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


def check_custom_fields(wiki: Path, spec: dict[str, set[str] | None]) -> list[Issue]:
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
    for page in iter_wiki_pages(wiki):
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
            rel = raw.relative_to(wiki).as_posix()
            issues.append(Issue(
                SEV_WARN, "drift", raw,
                f"sha256 mismatch (recorded {recorded[:12]}…, actual {actual[:12]}…); "
                f"run `python3 scripts/compute_sha256.py {rel}` to refresh, "
                f"or re-ingest the source if the body should not have drifted",
            ))
    return issues


def _git_repo_root(wiki: Path) -> Path | None:
    """The git repo the wiki ships within — the nearest ancestor holding a
    `.git` — or None when the wiki is not inside a git repo. A wiki with no repo
    is local-only: it ships nowhere, so its `source_path:` values face no
    portability constraint and the caller skips the check.
    """
    cur = wiki.resolve()
    while True:
        if (cur / ".git").exists():
            return cur
        if cur.parent == cur:
            return None
        cur = cur.parent


def portable_rewrite(resolved: Path, containing_root: Path, wiki: Path) -> str | None:
    """When `resolved` is an existing file inside `containing_root`, return its
    path spelled relative to the wiki root — the portable form the provenance
    field uses (`source_path:` reads from the wiki root; `sources:` as `raw/…`).

    Return None when the file is missing or resolves outside `containing_root`:
    that case has no in-tree equivalent, so the caller keeps it blocking. The
    rewrite is a deterministic, lossless normalization — the same file, portably
    spelled — so the caller surfaces it as a safe auto-fix warn.
    """
    if not resolved.is_file():
        return None
    try:
        resolved.relative_to(containing_root)
    except ValueError:
        return None
    return os.path.relpath(resolved, wiki)


def check_source_path_portable(wiki: Path) -> list[Issue]:
    """Validate every raw sidecar's `source_path:` is a portable path to an
    in-repo source.

    A wiki that is not inside a git repository is local-only — it ships nowhere,
    so every `source_path:` resolves on the single machine that holds it and this
    check does not apply. A wiki inside a git repo ships with the repo, so a
    `source_path:` records a source kept inside that repo; it may sit outside the
    wiki directory (e.g. `../shared/spec.md`) but must stay inside the repo. A
    relative value that escapes the repo, or does not resolve, dangles on every
    clone and stays blocking. An absolute or `~`-prefixed value that resolves to
    an in-repo file has a deterministic repo-relative equivalent — the same file,
    portably spelled — so it is a safe-auto-fix **warn** carrying that rewrite;
    only an absolute value resolving outside the repo (or to no file) stays
    blocking. A file that lives outside the repo takes no `source_path:` at all —
    it is captured by the sidecar body excerpt and a prose locality note — so a
    sidecar without the field is fine.

    A `source_path:` carrying a remote URL scheme (a URL misfiled where a
    repo-relative path belongs) is yielded to `check_raw_origin_form`, which
    emits the single redirecting warn everywhere; skipping it here keeps a repo
    wiki from stacking a misleading blocking "does not resolve" error on top of
    that warn.
    """
    issues: list[Issue] = []
    repo_root = _git_repo_root(wiki)
    if repo_root is None:
        return issues  # local-only wiki: nothing ships, so no source_path is non-portable
    for raw in iter_raw_files(wiki):
        fm, _ = parse_frontmatter(raw.read_text(encoding="utf-8"))
        if not fm:
            continue
        src = fm.get("source_path")
        if not src or not isinstance(src, str):
            continue
        scheme = uri_scheme(src)
        if scheme is not None and scheme != "file":
            continue  # URL-in-source_path is redirected by check_raw_origin_form
        if Path(src).is_absolute() or src.startswith("~"):
            resolved = Path(src).expanduser().resolve()
            rel = portable_rewrite(resolved, repo_root, wiki)
            if rel is not None:
                issues.append(Issue(
                    SEV_WARN, "raw-source-path", raw,
                    f"`source_path:` is an absolute/home path but resolves to an "
                    f"in-repo file — rewrite it repo-relative (same file, portable "
                    f"spelling): {src} -> {rel}",
                ))
            else:
                issues.append(Issue(
                    SEV_BLOCKING, "raw-source-path", raw,
                    f"`source_path:` is an absolute/home path resolving outside the "
                    f"repository (or to no file) — use a relative path to an in-repo "
                    f"source, or drop it and excerpt a local file outside the repo "
                    f"into the body: {src}",
                ))
            continue
        resolved = (wiki / src).resolve()
        try:
            resolved.relative_to(repo_root)
        except ValueError:
            issues.append(Issue(
                SEV_BLOCKING, "raw-source-path", raw,
                f"`source_path:` escapes the repository — reference an in-repo source "
                f"by a relative path, or excerpt a local file outside the repo into "
                f"the body: {src}",
            ))
            continue
        if not resolved.is_file():
            issues.append(Issue(
                SEV_BLOCKING, "raw-source-path", raw,
                f"`source_path:` does not resolve on disk: {src}",
            ))
    return issues


def check_raw_origin_form(wiki: Path) -> list[Issue]:
    """Validate the *form* of whichever origin field a raw sidecar carries.

    The two origin fields name mutually-exclusive origin kinds: `source_url:` is
    a remote URL for an externally-published source, `source_path:` is a
    repo-relative path to a source the repo tracks. This check flags a value
    filed under the wrong field and a sidecar carrying both at once, so a legacy
    or mis-filled sidecar migrates onto the two-field contract. It never
    requires an origin field — a sidecar for an out-of-repo local source
    legitimately carries neither (see `check_raw_frontmatter`); it only checks
    the form of a value that is present.

    All findings are **warn**: these are overwhelmingly legacy or mis-filled
    sidecars to migrate, so a warn surfaces every one without hard-breaking a
    pre-split wiki's lint on upgrade. Unlike `check_source_path_portable`, this
    runs everywhere — including a wiki outside a git repo, where the portable
    check is skipped and a URL-valued `source_path:` would otherwise pass
    silently.
    """
    issues: list[Issue] = []
    for raw in iter_raw_files(wiki):
        fm, _ = parse_frontmatter(raw.read_text(encoding="utf-8"))
        if not fm:
            continue
        url = fm.get("source_url")
        path = fm.get("source_path")
        has_url = isinstance(url, str) and url.strip() != ""
        has_path = isinstance(path, str) and path.strip() != ""

        if has_url and has_path:
            issues.append(Issue(
                SEV_WARN, "raw-origin", raw,
                "sidecar carries both `source_url:` and `source_path:` — the two "
                "name mutually-exclusive origin kinds; keep the one that fits (a "
                "remote URL in `source_url:`, a repo-relative path in "
                "`source_path:`) and drop the other",
            ))

        if has_url:
            scheme = uri_scheme(url)
            if scheme == "file":
                issues.append(Issue(
                    SEV_WARN, "raw-origin", raw,
                    f"`source_url:` is a `file://` URL, not an externally-published "
                    f"source — use a repo-relative `source_path:` for an in-repo "
                    f"file, or drop the field and excerpt an out-of-repo local file "
                    f"into the body: {url}",
                ))
            elif scheme is None:
                issues.append(Issue(
                    SEV_WARN, "raw-origin", raw,
                    f"`source_url:` is a bare path, not a remote URL — use a "
                    f"repo-relative `source_path:` for an in-repo file, or drop the "
                    f"field and excerpt an out-of-repo local file into the body: "
                    f"{url}",
                ))

        if has_path:
            scheme = uri_scheme(path)
            if scheme is not None and scheme != "file":
                issues.append(Issue(
                    SEV_WARN, "raw-origin", raw,
                    f"`source_path:` holds a remote URL where a repo-relative path "
                    f"belongs — put an externally-published source's URL in "
                    f"`source_url:` instead: {path}",
                ))
    return issues


def check_raw_frontmatter(wiki: Path) -> list[Issue]:
    """Every raw sidecar outside `raw/assets/` carries the re-ingest metadata a
    future drift check needs: an `ingested` date and a `sha256` body digest.

    Without them drift detection is silently inert — `check_source_drift` skips
    any file lacking `sha256`, so a source that skipped hashing is never
    checked for drift and the common narrow post-ingest lint never surfaces the
    omission. Warn severity, because both are mechanically fixable:
    `compute_sha256.py` writes the digest and the ingest stamps the date. The
    origin field (`source_url` / `source_path`) stays optional — a sidecar for
    an out-of-repo local source legitimately carries neither. `raw/assets/`
    holds binary companions with no frontmatter, so it is exempt.
    """
    issues: list[Issue] = []
    for raw in iter_raw_files(wiki):
        rel = raw.relative_to(wiki)
        if len(rel.parts) >= 2 and rel.parts[1] == "assets":
            continue
        rel_posix = rel.as_posix()
        fm, _ = parse_frontmatter(raw.read_text(encoding="utf-8"))
        if fm is None:
            issues.append(Issue(
                SEV_WARN, "raw-frontmatter", raw,
                f"raw source has no frontmatter — add `ingested` and `sha256` "
                f"(run `python3 scripts/compute_sha256.py {rel_posix}` for the digest)",
            ))
            continue
        for field in ("ingested", "sha256"):
            if not fm.get(field):
                hint = (
                    f" — run `python3 scripts/compute_sha256.py {rel_posix}` to write it"
                    if field == "sha256" else " — stamp it with the ingest date"
                )
                issues.append(Issue(
                    SEV_WARN, "raw-frontmatter", raw,
                    f"raw source missing `{field}`, so a re-ingest cannot detect drift{hint}",
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
WIKILINK_RE = re.compile(r"\[\[([^\[\]\n]+)\]\]")
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")


def strip_fenced_blocks(text: str) -> str:
    """Return `text` with fenced code blocks dropped, inline code left intact.

    Used where a scanner must ignore ``` fenced examples but still read
    inline-code content on live lines (the taxonomy loader keeps `` `model` ``
    inside a live bullet). Mirrors the fence handling in the body scanners.
    """
    out: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if FENCE_RE.match(line.strip()):
            in_fence = not in_fence
            continue
        if not in_fence:
            out.append(line)
    return "\n".join(out)


def strip_code(text: str) -> str:
    """Return `text` with both fenced code blocks and inline code removed, so
    link and citation scanners never read a documentation example as live
    markup. Combines ``strip_fenced_blocks`` with the inline-code scrub the
    footnote/wikilink checks already apply per line.
    """
    return "\n".join(
        INLINE_CODE_RE.sub("", line)
        for line in strip_fenced_blocks(text).splitlines()
    )


def check_markdown_style(wiki: Path) -> list[Issue]:
    issues: list[Issue] = []
    targets = list(iter_wiki_pages(wiki))
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
# Source-attribution checks
#
# The wiki uses three rules for source attribution:
#
#   1. `sources:` frontmatter is the canonical, page-level source inventory.
#      Every entry must resolve to a real file under `raw/` — blocking when
#      it doesn't, same severity as broken markdown links.
#   2. Pages do not carry a body "Sources" / "Source references" H2 section.
#      The frontmatter alone is the source of truth; a bottom-of-page list
#      duplicates that inventory and splits the claim-source binding across
#      the page. Info-level so legacy pages surface for clean-up without
#      breaking the audit.
#   3. Claim-level attribution uses inline standard-markdown links, never
#      footnote markers (`[^name]` / `[^name]: …`). Footnotes render
#      inconsistently across viewers, hide their targets from the
#      broken-link check, and split a claim from its evidence — undesirable
#      in an LLM-first wiki where attribution should sit next to the claim.
#      Warn-level so the conversion path is clear and actionable.
# ---------------------------------------------------------------------------

SOURCES_HEADER_RE = re.compile(
    r"^\s*##\s+(?:sources?|source\s+references?)\s*$",
    re.IGNORECASE,
)
FOOTNOTE_RE = re.compile(r"\[\^([^\]\s]+)\]")
FOOTNOTE_DEF_RE = re.compile(r"^\s*\[\^([^\]\s]+)\]:")


def check_source_paths_exist(wiki: Path) -> list[Issue]:
    """Validate every `sources:` entry is a portable, repo-relative `raw/…`
    path that resolves on disk.

    Entries are interpreted relative to the wiki root. A `~`-prefixed entry, or
    one that escapes the wiki's `raw/` tree, is non-portable — it resolves only
    on the machine that wrote it, and Python's `pathlib` even lets an absolute
    entry silently override the `wiki /` join — so it is blocking regardless of
    whether it happens to exist locally. An absolute or `~`-prefixed entry that
    resolves to an existing file inside `raw/` has a deterministic
    `raw/…`-relative equivalent — the same file, portably spelled — so it is a
    safe-auto-fix **warn** carrying that rewrite; only an entry resolving
    outside `raw/` (or to no file) stays the blocking `broken-source` finding. A
    surviving repo-relative `raw/…` entry must still resolve on disk.
    """
    issues: list[Issue] = []
    raw_root = (wiki / "raw").resolve()
    for page in iter_wiki_pages(wiki):
        fm, _ = parse_frontmatter(page.read_text(encoding="utf-8"))
        if not fm:
            continue
        sources = fm.get("sources") or []
        if not isinstance(sources, list):
            continue
        for src in sources:
            if not src or not isinstance(src, str):
                continue
            if Path(src).is_absolute() or src.startswith("~"):
                resolved = Path(src).expanduser().resolve()
                rel = portable_rewrite(resolved, raw_root, wiki)
                if rel is not None:
                    issues.append(Issue(
                        SEV_WARN, "broken-source", page,
                        f"`sources:` entry is an absolute/home path but resolves "
                        f"inside `raw/` — rewrite it repo-relative (same file, "
                        f"portable spelling): {src} -> {rel}",
                    ))
                else:
                    issues.append(Issue(
                        SEV_BLOCKING, "broken-source", page,
                        f"`sources:` entry is an absolute/home path resolving "
                        f"outside the wiki's `raw/` tree (or to no file) — use a "
                        f"repo-relative `raw/…` path: {src}",
                    ))
                continue
            target = (wiki / src).resolve()
            try:
                target.relative_to(raw_root)
            except ValueError:
                issues.append(Issue(
                    SEV_BLOCKING, "broken-source", page,
                    f"`sources:` entry escapes the wiki's `raw/` tree — use a repo-relative `raw/…` path: {src}",
                ))
                continue
            if not target.is_file():
                issues.append(Issue(
                    SEV_BLOCKING, "broken-source", page,
                    f"`sources:` entry missing on disk: {src}",
                ))
    return issues


def check_sources_section(wiki: Path) -> list[Issue]:
    """Flag deprecated body "Sources" / "Source references" H2 sections.

    The `sources:` frontmatter is the single source of truth for the
    page-level source inventory. A body collection duplicates that
    inventory, splits the claim-source binding across the page, and drifts
    independently from the frontmatter. Info-level so authors see the
    legacy section and can hoist any per-source commentary into the
    relevant claim before removing the heading.
    """
    issues: list[Issue] = []
    for page in iter_wiki_pages(wiki):
        text = page.read_text(encoding="utf-8")
        if text.startswith("---"):
            _, body = parse_frontmatter(text)
        else:
            body = text
        in_fence = False
        for i, line in enumerate(body.splitlines(), start=1):
            if FENCE_RE.match(line.strip()):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            if SOURCES_HEADER_RE.match(line):
                issues.append(Issue(
                    SEV_INFO, "sources-section", page,
                    "deprecated body 'Sources' section — the `sources:` "
                    "frontmatter is the single source of truth; hoist any "
                    "per-source notes inline and remove the heading",
                    line=i,
                ))
    return issues


def check_footnote_syntax(wiki: Path) -> list[Issue]:
    """Flag `[^name]` footnote markers and `[^name]: …` definitions.

    Skipped inside fenced code blocks and inline code so bash test syntax
    and code samples that legitimately contain `[^` don't false-positive.
    Both references and definitions are reported per line — the conversion
    path is the same in either case: move the source path inline next to
    the claim it attributes as a standard markdown link, and delete the
    bottom-of-page definition.
    """
    issues: list[Issue] = []
    targets = list(iter_wiki_pages(wiki))
    for special in SPECIAL_FILES:
        candidate = wiki / special
        if candidate.is_file():
            targets.append(candidate)

    for page in targets:
        text = page.read_text(encoding="utf-8")
        if text.startswith("---"):
            _, body = parse_frontmatter(text)
        else:
            body = text
        in_fence = False
        for i, line in enumerate(body.splitlines(), start=1):
            if FENCE_RE.match(line.strip()):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            scrubbed = INLINE_CODE_RE.sub("", line)
            is_def = bool(FOOTNOTE_DEF_RE.match(scrubbed))
            for match in FOOTNOTE_RE.finditer(scrubbed):
                kind = "definition" if is_def else "reference"
                issues.append(Issue(
                    SEV_WARN, "footnote", page,
                    f"`[^{match.group(1)}]` footnote {kind} — wiki uses "
                    f"inline `[text](relative/path.md)` links for "
                    f"claim-level attribution; move the source path "
                    f"next to the claim and remove the definition",
                    line=i,
                ))
                if is_def:
                    break
    return issues


def check_wikilink_syntax(wiki: Path) -> list[Issue]:
    """Flag `[[target]]` wikilink-style references — the wiki uses standard
    markdown links `[text](relative/path.md)` so cross-references resolve in
    plain renderers and feed the broken-link check. Inline code (`` `...` ``)
    and fenced code blocks are skipped so bash test syntax and code samples
    don't false-positive.
    """
    issues: list[Issue] = []
    targets = list(iter_wiki_pages(wiki))
    for special in SPECIAL_FILES:
        candidate = wiki / special
        if candidate.is_file():
            targets.append(candidate)

    for page in targets:
        text = page.read_text(encoding="utf-8")
        if text.startswith("---"):
            _, body = parse_frontmatter(text)
        else:
            body = text
        in_fence = False
        for i, line in enumerate(body.splitlines(), start=1):
            if FENCE_RE.match(line.strip()):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            scrubbed = INLINE_CODE_RE.sub("", line)
            for match in WIKILINK_RE.finditer(scrubbed):
                inner = match.group(1)
                target_part, _, alias_part = inner.partition("|")
                target_part = target_part.strip()
                text_part = alias_part.strip() or target_part
                issues.append(Issue(
                    SEV_WARN, "wikilink", page,
                    f"`[[{inner}]]` is not standard markdown; convert to "
                    f"`[{text_part}](<relative-path-to-{target_part}>.md)`",
                    line=i,
                ))

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
        help="Path to the wiki directory. If omitted, discovers it the way scripts/discover_wiki.sh does: a directory whose basename contains 'wiki' with >=2 of SCHEMA.md/index.md/log.md present and no .no_wiki counts as a wiki; uses CWD if it is one, else the closest such wiki walking up toward $HOME, else $HOME/wiki when every level is opted out, otherwise exits 2 with a candidate list.",
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
        for page in iter_wiki_pages(wiki):
            issues.extend(check_frontmatter(page, wiki, taxonomy, valid_types))

        issues.extend(check_type_location(wiki, valid_types, page_dirs))
        issues.extend(check_links_and_orphans(wiki))
        issues.extend(check_source_paths_exist(wiki))
        issues.extend(check_index_completeness(wiki))
        if taxonomy:
            issues.extend(check_unused_tags(wiki, taxonomy))
        issues.extend(check_page_size(wiki))
        issues.extend(check_stale_content(wiki))
        issues.extend(check_quality_signals(wiki))
        issues.extend(check_custom_fields(wiki, custom_spec))
        issues.extend(check_markdown_style(wiki))
        issues.extend(check_wikilink_syntax(wiki))
        issues.extend(check_footnote_syntax(wiki))
        issues.extend(check_sources_section(wiki))

    issues.extend(check_verbatim_boilerplate(wiki))
    issues.extend(check_taxonomy_style(wiki))
    issues.extend(check_log_rotation(wiki))
    issues.extend(check_source_drift(wiki))
    issues.extend(check_source_path_portable(wiki))
    issues.extend(check_raw_origin_form(wiki))
    issues.extend(check_raw_frontmatter(wiki))

    print(render_report(wiki, issues, args.quiet))
    return 1 if any(i.severity == SEV_BLOCKING for i in issues) else 0


if __name__ == "__main__":
    sys.exit(main())
