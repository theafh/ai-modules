#!/usr/bin/env python3
"""lint.py — health-check the tasks directory, plus repo-wide link integrity.

Per-file task checks (naming, frontmatter, provenance, status/location,
datetime, title, size, footnotes, wikilinks, soft-pointer, repeated-link,
collisions) stay scoped to task files under the resolved tasks/ tree: live
``*.md`` by default, the whole archive under ``--include-archive``, or one
named task under ``--file``. The oversized-page and repeated-link warnings
fire only on live open, checked, and ready tasks; the soft-pointer check
stays on live pages.

On a default or ``--include-archive`` run, the link check walks every
markdown file under the project root (the parent of tasks/) and reports
broken in-repo targets of any kind (files or directories). When that
project root sits in a git work tree, as the toplevel or a subdirectory
git does not ignore, the inventory is
``git ls-files -z --cached --others --exclude-standard -- '*.md'`` run
from the root, so gitignored trees such as ``node_modules/`` stay out.
Outside git, or in a root git ignores, the walk is an ``*.md`` rglob
that skips only ``.git/``. When the repo-root
Makefile defines an ``EXCLUDE`` whose tokens are ``find`` prune clauses
ending in ``-o``, that prune set further filters the inventory (and is
the sole inventory outside git); any other ``EXCLUDE`` spelling is
ignored so a non-prune assignment cannot silence the check. Targets that
leave the repository (``://``, ``mailto:``, empty or fragment-only, or a
path that resolves outside the project root) draw no finding. A
destination that starts with ``/`` and does not exist as an absolute
filesystem path is treated as repository-root-relative before the
silence rule runs. Under ``--file``, link checks stay scoped to the
named task file alone so archive close-out still sees findings only for
that file. The two flags are mutually exclusive.

Usage:
    python3 lint.py [TASKS_PATH] [--quiet] [--include-archive | --file PATH]

When TASKS_PATH is omitted the linter shells out to the sibling
``discover_tasks.sh`` so it resolves the same path the skill uses at
runtime — single source of truth for discovery semantics.

Exit codes:
    0  no blocking issues
    1  one or more blocking issues found
"""

from __future__ import annotations

import argparse
import html
import re
import shlex
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator
from urllib.parse import unquote


SCRIPT_DIR = Path(__file__).resolve().parent
DISCOVER_SCRIPT = SCRIPT_DIR / "discover_tasks.sh"

REQUIRED_FRONTMATTER = (
    "description",
    "scope",
    "created",
    "updated",
    "status",
    "reported-by",
)
VALID_STATUS = {
    "open",
    "checked",
    "ready",
    "implemented",
    "audited",
    "finished",
    "deferred",
}
ARCHIVE_STATUS = {"finished", "deferred"}
# The statuses before implementation. The oversized-page and repeated-link
# warnings fire only on live tasks at these statuses, because each prompts
# the author to reorganize or split a task that may have grown organically,
# and that prompt is moot once the task is implemented, audited, or archived.
PRE_IMPLEMENTATION_STATUS = {"open", "checked", "ready"}
IMPLEMENTER_STATUS = {"implemented", "audited", "finished"}

NAME_RE = re.compile(r"^(?P<scope>[a-z0-9]+(?:-[a-z0-9]+)*)_(?P<name>[a-z0-9]+(?:-[a-z0-9]+)*)\.md$")
DATETIME_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}"            # date
    r"(?:[T ]\d{2}:\d{2}(?::\d{2})?"  # optional time
    r"(?:Z|[+-]\d{2}:?\d{2})?)?$"     # optional tz
)
H1_RE = re.compile(r"^#\s+\S")
# First character of an unquoted scalar that YAML reads as an indicator
# rather than as text. Covers the skill_doctor start class and the flow
# indicators {, }, and ,. A leading "- " or "? " and a colon followed by
# a space or a tab are matched on their own, because the marker there is
# the following whitespace.
YAML_HOSTILE_START_RE = re.compile(r"^[&*!|>%@`\[\]{},]")
LEADING_BLOCK_MARK_RE = re.compile(r"^[?-][ \t]")
COLON_WHITESPACE_RE = re.compile(r":[ \t]")
# Keys whose misread repair is to quote the value and keep its text.
FREE_TEXT_QUOTE_KEYS = {"description", "reported-by", "implemented-by"}

# Standard-markdown enforcement: footnotes and wikilinks are surfaced as
# blocking so the tasks tree stays portable to any CommonMark renderer.
FOOTNOTE_REF_RE = re.compile(r"\[\^([^\]\s]+)\]")
FOOTNOTE_DEF_RE = re.compile(r"^\s*\[\^([^\]\s]+)\]:")
WIKILINK_RE = re.compile(r"\[\[([^\[\]\n]+)\]\]")
FENCE_RE = re.compile(r"^( {0,3})(`{3,}|~{3,})(.*)$")
LIST_ITEM_RE = re.compile(r"^( *)([-+*]|[0-9]{1,9}[.)])( +|$)")
ENTITY_RE = re.compile(
    r"&(?:#[xX][0-9A-Fa-f]{1,6}|#[0-9]{1,7}|[A-Za-z][A-Za-z0-9]{1,31});"
)
MARKDOWN_ESCAPABLE = frozenset(r"!\"#$%&'()*+,-./:;<=>?@[\]^_`{|}~")

# The only `find` tokens a Makefile EXCLUDE may carry before the linter
# passes it to `find`: tests that take one operand, and bare operators.
FIND_PRUNE_TESTS = frozenset({
    "-path", "-ipath", "-name", "-iname", "-wholename", "-iwholename", "-type",
})
FIND_PRUNE_OPERATORS = frozenset({
    "-prune", "-o", "-or", "-a", "-and", "!", "-not", "(", ")",
})

# Soft-pointer rule: a task reference anchors on a verbatim greppable
# label, never a line-number position claim that goes stale silently.
# Three anchored, false-positive-resistant shapes warn (open tasks only,
# fenced blocks skipped):
#   - a `:N` suffix or adjacent `~N` marker on a path with a known
#     source/config/doc extension, so `localhost:8080`, `host:port`, and
#     `13:40:10` stay silent;
#   - a `line N` / `around lines N-M` prose claim, matched
#     case-insensitively and with optional `~`;
#   - a parenthesized approximate range like `(~N)` / `(~N-M)`.
# Each pattern reaches outward to the surrounding path token / number
# range so the finding can quote the offending text as written; the
# trigger at the core is still the extension+position marker (resp.
# `line[s]` / parenthesized `~`), so every documented silent case stays
# silent. The extension allowlist is deliberately partial — widen it only
# when a missed extension proves common in real task references.
POSITION_PATH_RE = re.compile(
    r"[\w./-]*\.(?:md|sh|py|json|ya?ml|toml|js|ts|go|rs|c|h)(?::[0-9]+|\s+~[0-9]+)"
)
POSITION_PROSE_RE = re.compile(
    r"\b(?:around\s+)?lines?\s+~?[0-9]+(?:[-–][0-9]+)?",
    re.IGNORECASE,
)
POSITION_TILDE_RANGE_RE = re.compile(r"\(~[0-9]+(?:[-–][0-9]+)?\)")
SIZE_SUFFIX_RE = re.compile(r"\s*(?:B|KB|MB|GB|TB|bytes)\b", re.IGNORECASE)

# Repeated-link hint: warn when one local target is linked more than
# REPEATED_LINK_FLOOR times in a single body (count > floor). Measured
# on 2026-08-12 across live tasks/*.md: 36 target-and-file pairs at
# exactly 2 links, 8 at 3, one at 4, and one at 7. The hint strengthens
# with the count rather than switching on at a harder threshold; retune
# against a fresh distribution if triage load proves too broad.
REPEATED_LINK_FLOOR = 1

SEV_BLOCKING = 0
SEV_WARN = 1
SEV_INFO = 2
SEVERITY_LABEL = {SEV_BLOCKING: "blocking", SEV_WARN: "warn", SEV_INFO: "info"}

MAX_LINES_BEFORE_SPLIT = 300


@dataclass
class Issue:
    severity: int
    category: str
    path: Path
    message: str
    line: int | None = None

    def render(self, tasks: Path) -> str:
        try:
            rel = self.path.relative_to(tasks)
        except ValueError:
            try:
                rel = self.path.relative_to(tasks.parent)
            except ValueError:
                rel = self.path
        loc = f":{self.line}" if self.line else ""
        label = SEVERITY_LABEL[self.severity]
        return f"  [{label:8}] {self.category:14} {rel}{loc}  {self.message}"


def discover_tasks(arg: str | None) -> Path:
    if arg:
        path = Path(arg).expanduser().resolve()
        if not path.is_dir():
            sys.exit(f"tasks path does not exist: {path}")
        return path

    if not DISCOVER_SCRIPT.is_file():
        sys.exit(f"discovery script missing: {DISCOVER_SCRIPT}")

    result = subprocess.run(
        ["bash", str(DISCOVER_SCRIPT)],
        capture_output=True,
        text=True,
    )
    printed = result.stdout.strip()
    if not printed:
        sys.exit("discover_tasks.sh produced no path")
    path = Path(printed)
    if not path.is_dir():
        sys.exit(
            f"tasks directory does not exist at {path}; "
            f"run `bash {SCRIPT_DIR}/init_tasks.sh {path}` to scaffold it"
        )
    return path


def _scalar_start(line: str) -> int:
    """Return the index where the frontmatter value begins.

    On a `key: value` line that is the first character after the key
    separator. When the text is already just the value, it is the first
    non-whitespace character. A quote opens a scalar only at that index,
    so an apostrophe inside a plain value stays a character.
    """
    index = 0
    length = len(line)
    while index < length and line[index].isspace():
        index += 1
    scan = index
    while scan < length:
        char = line[scan]
        if char in "\"'":
            return index
        if char == ":":
            scan += 1
            while scan < length and line[scan].isspace():
                scan += 1
            return scan
        scan += 1
    return index


def _strip_yaml_comment(line: str) -> str:
    """Drop a trailing comment whose # follows whitespace outside quotes.

    A # inside a single- or double-quoted scalar stays in the value. A #
    that is not preceded by whitespace stays in an unquoted value. A quote
    opens only at the start of the value, and a doubled apostrophe inside
    a single-quoted scalar is one escaped apostrophe.
    """
    scalar_start = _scalar_start(line)
    in_single = False
    in_double = False
    index = 0
    length = len(line)
    while index < length:
        char = line[index]
        if not in_single and not in_double and index == scalar_start:
            if char == "'":
                in_single = True
                index += 1
                continue
            if char == '"':
                in_double = True
                index += 1
                continue
        if in_double and char == "\\":
            index += 2
            continue
        if in_double and char == '"':
            in_double = False
            index += 1
            continue
        if in_single and char == "'":
            if index + 1 < length and line[index + 1] == "'":
                index += 2
                continue
            in_single = False
            index += 1
            continue
        preceded_by_space = index == 0 or line[index - 1].isspace()
        if char == "#" and not in_single and not in_double and preceded_by_space:
            return line[:index].rstrip()
        index += 1
    return line.rstrip()


def _decode_double_quoted(value: str) -> str:
    """Resolve \\\\ and \\" inside a double-quoted scalar, quotes removed."""
    parts: list[str] = []
    index = 0
    length = len(value)
    while index < length:
        char = value[index]
        if char == "\\" and index + 1 < length and value[index + 1] in '\\"':
            parts.append(value[index + 1])
            index += 2
            continue
        parts.append(char)
        index += 1
    return "".join(parts)


def _decode_quoted_scalar(value: str) -> str:
    """Return the text of a quoted scalar, or value when it is unquoted."""
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return _decode_double_quoted(value[1:-1])
    if len(value) >= 2 and value[0] == "'" and value[-1] == "'":
        return value[1:-1]
    return value


def _quoted_scalar(value: str) -> bool:
    """Return True when value opens a quoted scalar that also closes."""
    if len(value) < 2 or value[0] not in "\"'":
        return False
    quote = value[0]
    index = 1
    length = len(value)
    while index < length:
        char = value[index]
        if quote == '"' and char == "\\":
            index += 2
            continue
        if char == quote:
            return True
        index += 1
    return False


def _plain_unquoted_misread(value: str) -> bool:
    """Return True when the value itself is one YAML would misread."""
    if not value or _quoted_scalar(value):
        return False
    if YAML_HOSTILE_START_RE.match(value):
        return True
    if LEADING_BLOCK_MARK_RE.match(value):
        return True
    if COLON_WHITESPACE_RE.search(value):
        return True
    return value.endswith(":")


def _trailing_comment_only(raw_value: str) -> bool:
    """Return True when a trailing comment is the whole misread.

    raw_value is the text after the key's colon, surrounding whitespace
    removed, with any trailing comment still attached. The value that
    remains once that comment is removed is one YAML accepts as plain text.
    """
    if not raw_value or _quoted_scalar(raw_value):
        return False
    stripped = _strip_yaml_comment(raw_value)
    if stripped == raw_value.rstrip():
        return False
    return not _plain_unquoted_misread(stripped)


def _unquoted_yaml_misread(raw_value: str) -> bool:
    """Return True when an unquoted scalar is one YAML would misread.

    raw_value is the text after the key's colon, surrounding whitespace
    removed, with any trailing comment still attached.
    """
    if not raw_value or _quoted_scalar(raw_value):
        return False
    if _plain_unquoted_misread(raw_value):
        return True
    return _trailing_comment_only(raw_value)


def _quote_misread(key: str, raw_value: str) -> bool:
    """Return True when the repair is to wrap the value in double quotes."""
    if key in FREE_TEXT_QUOTE_KEYS:
        return True
    return key == "scope" and not _trailing_comment_only(raw_value)


def _misread_message(key: str, raw_value: str) -> str:
    """Return the blocking finding text for one misread value."""
    if _quote_misread(key, raw_value):
        return (
            f"unquoted value for {key} is one YAML would misread; "
            "wrap it in double quotes, escaping any \" or \\ inside it"
        )
    if _trailing_comment_only(raw_value):
        return (
            f"unquoted value for {key} has a trailing comment; "
            "remove the comment and leave the value"
        )
    return (
        f"unquoted value for {key} is one YAML would misread; "
        "rewrite the value as a plain scalar"
    )


def _frontmatter_entries(block: str) -> list[tuple[str, str, str]]:
    """Return top-level (key, comment-stripped value, raw value) triples.

    The raw value keeps a trailing comment so the misread check can see a
    # that YAML would treat as the start of one.
    """
    entries: list[tuple[str, str, str]] = []
    for raw_line in block.splitlines():
        if not raw_line or raw_line[0].isspace():
            continue
        code = _strip_yaml_comment(raw_line)
        if not code or ":" not in code:
            continue
        key, _, parsed = code.partition(":")
        key = key.strip()
        if not key:
            continue
        _, _, raw_value = raw_line.partition(":")
        entries.append((key, parsed.strip(), raw_value.strip()))
    return entries


def _frontmatter_block(text: str) -> tuple[str, str] | None:
    """Return (block, body) when the frontmatter fences close, else None."""
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        end = text.find("\n---", 4)
        if end == -1 or text[end:].strip() != "---":
            return None
    block = text[4:end]
    body = text[end + 5:] if text[end:end + 5] == "\n---\n" else ""
    return block, body


def get_raw_scope(text: str) -> str | None:
    """Return the raw `scope:` value verbatim — quotes preserved — so the
    scope check can tell quoted text from an unquoted path candidate.
    Returns None when there is no frontmatter or no scope field.
    A # inside quotes stays in the value; a trailing comment is removed
    only when its # follows whitespace outside quotes.
    """
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        end = text.find("\n---", 4)
        if end == -1:
            return None
    for key, value, _raw in _frontmatter_entries(text[4:end]):
        if key == "scope":
            return value
    return None


def parse_frontmatter(text: str) -> tuple[dict | None, str]:
    found = _frontmatter_block(text)
    if found is None:
        return None, text
    block, body = found
    data: dict = {}
    for key, value, _raw in _frontmatter_entries(block):
        if not value:
            data[key] = ""
        elif value.lower() in {"true", "false"}:
            data[key] = value.lower() == "true"
        else:
            data[key] = _decode_quoted_scalar(value)
    return data, body


def _misread_findings(page: Path, text: str) -> list[Issue]:
    """Block each unquoted top-level value YAML would misread."""
    found = _frontmatter_block(text)
    if found is None:
        return []
    block, _body = found
    issues: list[Issue] = []
    reported: set[str] = set()
    for key, _parsed, raw_value in _frontmatter_entries(block):
        if key in reported or not _unquoted_yaml_misread(raw_value):
            continue
        reported.add(key)
        issues.append(
            Issue(SEV_BLOCKING, "frontmatter", page, _misread_message(key, raw_value))
        )
    return issues


def iter_task_files(tasks: Path, include_archive: bool = False) -> Iterator[Path]:
    """Yield `*.md` task files: live tasks at the root by default, and
    archived tasks when archive-maintenance mode is requested. Other
    folders are ignored — the tasks tree is intentionally two-level only.
    """
    if not tasks.is_dir():
        return
    for path in sorted(tasks.glob("*.md")):
        if path.is_file():
            yield path
    if not include_archive:
        return
    archive = tasks / "archive"
    if archive.is_dir():
        for path in sorted(archive.glob("*.md")):
            if path.is_file():
                yield path


def parse_makefile_exclude(makefile: Path) -> list[str] | None:
    """Return the tokenized ``EXCLUDE`` value from a Makefile, or None.

    Reads a ``EXCLUDE := …`` / ``EXCLUDE = …`` / ``EXCLUDE ?= …`` /
    ``EXCLUDE += …`` assignment (optional ``override`` prefix), including
    backslash-continued lines, and splits it the way ``find`` would see
    ``$(EXCLUDE)``. A missing Makefile or a Makefile with no ``EXCLUDE``
    assignment yields None.
    """
    if not makefile.is_file():
        return None
    chunks: list[str] = []
    collecting = False
    for line in makefile.read_text(encoding="utf-8").splitlines():
        if not collecting:
            match = re.match(
                r"^(?:override\s+)?EXCLUDE\s*(?:\?|\+|:)?=\s*(.*)$",
                line,
            )
            if not match:
                continue
            collecting = True
            rest = match.group(1)
        else:
            rest = line
        stripped = rest.rstrip()
        continued = stripped.endswith("\\")
        piece = stripped[:-1].rstrip() if continued else stripped
        piece = piece.strip()
        if piece:
            chunks.append(piece)
        if not continued:
            break
    if not collecting:
        return None
    return shlex.split(" ".join(chunks))


def is_find_prune_exclude(tokens: list[str]) -> bool:
    """True when ``tokens`` look like ``find`` prune clauses ending in ``-o``.

    This repository's Makefile uses that shape for ``MD_FILES``. A bare
    path, a lone ``-name`` filter, or any other non-prune spelling must
    not drive the inventory, because ``find . $(EXCLUDE) …`` then either
    matches nothing or treats the value as a second start path.

    Every token must be a test from ``FIND_PRUNE_TESTS`` followed by its
    operand, or an operator from ``FIND_PRUNE_OPERATORS``. The tokens come
    from the linted repository's Makefile and are handed to ``find``, so
    an action such as ``-exec`` or ``-delete`` rejects the whole value and
    linting never runs a command the repository chose.
    """
    if not tokens or tokens[-1] != "-o" or "-prune" not in tokens:
        return False
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in FIND_PRUNE_TESTS:
            if index + 1 >= len(tokens):
                return False
            index += 2
        elif token in FIND_PRUNE_OPERATORS:
            index += 1
        else:
            return False
    return True


def _git_toplevel(root: Path) -> Path | None:
    """Return the git toplevel for ``root``, or None when not in a work tree."""
    result = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    top = result.stdout.strip()
    if not top:
        return None
    return Path(top).resolve()


def _git_ignores(toplevel: Path, root: Path) -> bool:
    """True when git ignores ``root``, a directory below ``toplevel``."""
    try:
        relative = root.relative_to(toplevel).as_posix()
    except ValueError:
        return True
    result = subprocess.run(
        ["git", "-C", str(toplevel), "check-ignore", "-q", "--", f"{relative}/"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode == 0


def _list_git_markdown_files(root: Path) -> list[Path]:
    """Markdown paths tracked or untracked-but-not-ignored under ``root``.

    ``git ls-files`` run from ``root`` lists only paths below it, relative
    to it. ``-z`` keeps a non-ASCII name unquoted, so it still resolves.
    """
    result = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            "*.md",
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="surrogateescape",
        check=False,
    )
    if result.returncode != 0:
        sys.exit(
            f"git ls-files for markdown inventory failed under {root}: "
            f"{result.stderr.strip() or result.stdout.strip() or result.returncode}"
        )
    paths: list[Path] = []
    for entry in result.stdout.split("\0"):
        if not entry:
            continue
        candidate = (root / entry).resolve()
        if candidate.is_file():
            paths.append(candidate)
    return paths


def _list_rglob_markdown_files(root: Path) -> list[Path]:
    """Every ``*.md`` under ``root``, skipping only ``.git/``."""
    paths: list[Path] = []
    for path in root.rglob("*.md"):
        if not path.is_file():
            continue
        if ".git" in path.relative_to(root).parts:
            continue
        paths.append(path.resolve())
    return paths


def _list_find_markdown_files(root: Path, exclude: list[str]) -> list[Path]:
    """``find . $(EXCLUDE) -type f -name '*.md' -print`` under ``root``."""
    result = subprocess.run(
        ["find", ".", *exclude, "-type", "f", "-name", "*.md", "-print"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode not in (0, 1):
        sys.exit(
            f"find for markdown inventory failed under {root}: "
            f"{result.stderr.strip() or result.stdout.strip() or result.returncode}"
        )
    paths: list[Path] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        candidate = (root / line).resolve()
        if candidate.is_file():
            paths.append(candidate)
    return paths


def iter_repo_markdown_files(project_root: Path) -> Iterator[Path]:
    """Yield every ``*.md`` file under ``project_root`` for link checks.

    Prefer a git-aware inventory when ``project_root`` sits in a git work
    tree, whether it is the toplevel or a subdirectory such as a monorepo
    package, so gitignored trees like ``node_modules/`` stay out. A root
    that git itself ignores, such as a scratch fixture inside another
    checkout, takes the non-git path instead, because ``git ls-files``
    would list nothing there. Layer a Makefile ``EXCLUDE`` on top only
    when it parses as ``find`` prune clauses ending in ``-o``. Outside
    git, that prune ``EXCLUDE`` is the sole inventory; otherwise fall
    back to an ``*.md`` rglob that skips ``.git/``. Resolved paths are
    deduplicated.
    """
    root = project_root.resolve()
    exclude = parse_makefile_exclude(root / "Makefile")
    prune = exclude if exclude is not None and is_find_prune_exclude(exclude) else None
    toplevel = _git_toplevel(root)
    use_git = toplevel is not None and (
        toplevel == root or not _git_ignores(toplevel, root)
    )
    if use_git:
        paths = _list_git_markdown_files(root)
        if prune is not None:
            allowed = set(_list_find_markdown_files(root, prune))
            paths = [path for path in paths if path in allowed]
    elif prune is not None:
        paths = _list_find_markdown_files(root, prune)
    else:
        paths = _list_rglob_markdown_files(root)
    seen: set[Path] = set()
    for path in sorted(paths):
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        yield resolved


def _path_inside_root(candidate: Path, project_root: Path) -> bool:
    try:
        candidate.resolve().relative_to(project_root.resolve())
        return True
    except ValueError:
        return False


def is_archived(tasks: Path, page: Path) -> bool:
    try:
        rel = page.relative_to(tasks)
    except ValueError:
        return False
    return len(rel.parts) == 2 and rel.parts[0] == "archive"


def resolve_scoped_file(tasks: Path, arg: str, all_pages: list[Path]) -> Path:
    """Resolve the `--file` argument to one task page, live or archived.

    Try the value relative to the tasks root, then to the project root,
    then as given (against the current directory), and return the first
    candidate that names a page in ``all_pages`` (the live + archive page
    set). Matching against that set rather than against the filesystem is
    what lets an explicit ``TASKS_PATH`` outrank an identically named file
    under the caller's own directory, and it returns the page object
    itself, so the scoped page is object-identical to the one collision
    detection sees. When no candidate names a page, the first one that
    exists at all supplies the path the error message reports. Exit
    non-zero naming the offending value when it is empty, missing, a
    directory, outside the tasks root, or not a task file at either
    task level.
    """
    if not arg.strip():
        sys.exit("--file requires a task file path, and the value given is empty")
    raw = Path(arg).expanduser()
    candidates = (
        [raw] if raw.is_absolute()
        else [tasks / raw, tasks.parent / raw, Path.cwd() / raw]
    )
    by_resolved = {page.resolve(): page for page in all_pages}
    fallback: Path | None = None
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved in by_resolved:
            return by_resolved[resolved]
        if fallback is None and resolved.exists():
            fallback = resolved
    if fallback is None:
        sys.exit(f"--file target does not exist: {arg}")
    if fallback.is_dir():
        sys.exit(f"--file target is a directory, not a task file: {arg}")
    try:
        fallback.relative_to(tasks.resolve())
    except ValueError:
        sys.exit(f"--file target resolves outside the tasks root ({tasks}): {arg}")
    sys.exit(
        f"--file target is not a task file under tasks/ or tasks/archive/: {arg}"
    )


def check_filename(page: Path) -> list[Issue]:
    if NAME_RE.match(page.name):
        return []
    return [Issue(
        SEV_BLOCKING, "naming", page,
        f"filename {page.name!r} does not match `<scope>_<name>.md` with "
        f"lowercase a-z, 0-9, and `-` inside scope and name "
        f"(example: `wiki-fix_split-page-anatomy.md`)",
    )]


def _git_output(cwd: Path, args: list[str]) -> list[str]:
    try:
        result = subprocess.run(
            ["git", "-C", str(cwd), *args],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return []
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def user_name_head(tasks: Path) -> str:
    names = _git_output(tasks.parent, ["config", "user.name"])
    return names[0] if names else "default_user"


def _rel_to_project(tasks: Path, page: Path) -> str:
    try:
        return str(page.relative_to(tasks.parent))
    except ValueError:
        return str(page)


def reported_by_value(tasks: Path, page: Path) -> tuple[str, str]:
    names = _git_output(
        tasks.parent,
        ["log", "--diff-filter=A", "--follow", "--format=%an", "--", _rel_to_project(tasks, page)],
    )
    if names:
        return names[-1], "derived from the first-add commit author"
    return user_name_head(tasks), "derived from `git config user.name`"


def implemented_by_value(tasks: Path, page: Path) -> tuple[str, str]:
    names = _git_output(
        tasks.parent,
        ["log", "--diff-filter=R", "--follow", "--format=%an", "--", _rel_to_project(tasks, page)],
    )
    if names:
        return names[0], "derived from the archive-move commit author"
    return user_name_head(tasks), "derived from `git config user.name`"


def check_frontmatter(tasks: Path, page: Path) -> tuple[list[Issue], dict | None]:
    text = page.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    issues: list[Issue] = []
    if fm is None:
        issues.append(Issue(
            SEV_BLOCKING, "frontmatter", page,
            "missing or malformed frontmatter — every task needs "
            "`description`, `scope`, `created`, `updated`, `status`, "
            "and `reported-by` between `---` fences",
        ))
        return issues, None

    issues.extend(_misread_findings(page, text))

    for field in REQUIRED_FRONTMATTER:
        if field == "reported-by":
            continue
        if field not in fm or fm[field] == "":
            issues.append(Issue(
                SEV_BLOCKING, "frontmatter", page,
                f"missing required field: {field}",
            ))

    status = fm.get("status")
    if isinstance(status, str) and status and status not in VALID_STATUS:
        issues.append(Issue(
            SEV_BLOCKING, "frontmatter", page,
            f"invalid status {status!r} (expected one of {sorted(VALID_STATUS)})",
        ))

    if "reported-by" not in fm or fm["reported-by"] == "":
        value, source = reported_by_value(tasks, page)
        issues.append(Issue(
            SEV_BLOCKING, "frontmatter", page,
            "missing required field: reported-by — add "
            f"`reported-by: {value}` ({source}; legacy provenance "
            "backfill does not bump `updated` when this is the only change)",
        ))

    if status in IMPLEMENTER_STATUS and ("implemented-by" not in fm or fm["implemented-by"] == ""):
        value, source = implemented_by_value(tasks, page)
        issues.append(Issue(
            SEV_BLOCKING, "frontmatter", page,
            "missing required field: implemented-by — add "
            f"`implemented-by: {value}` ({source}; legacy provenance "
            "backfill does not bump `updated` when this is the only change)",
        ))

    # design-extended is optional and only its type is checked. Newly stamped
    # tasks record it explicitly as true or false; absence reads as false, so
    # every task closed before the field existed stays clean and needs no
    # backfill of a code-level verdict no stage could now derive.
    if "design-extended" in fm and not isinstance(fm["design-extended"], bool):
        issues.append(Issue(
            SEV_BLOCKING, "frontmatter", page,
            "invalid field: design-extended must be boolean "
            "(`true` or `false`) when present; omit it when the work left "
            "the design unchanged",
        ))

    for date_field in ("created", "updated"):
        v = fm.get(date_field)
        if isinstance(v, str) and v and not DATETIME_RE.match(v):
            issues.append(Issue(
                SEV_WARN, "frontmatter", page,
                f"{date_field} not in ISO 8601 format (YYYY-MM-DD or "
                f"YYYY-MM-DDTHH:MM:SS): {v!r}",
            ))

    description = fm.get("description")
    if isinstance(description, str) and len(description) > 200:
        issues.append(Issue(
            SEV_WARN, "frontmatter", page,
            f"description is {len(description)} chars — keep it compact "
            f"(<=200), put detail in the body",
        ))

    if not any(H1_RE.match(line) for line in body.splitlines()):
        issues.append(Issue(
            SEV_WARN, "structure", page,
            "body has no `# Title` heading on its first non-blank line",
        ))

    return issues, fm


def check_location(tasks: Path, page: Path, fm: dict | None) -> list[Issue]:
    if not fm:
        return []
    status = fm.get("status")
    if not isinstance(status, str) or status not in VALID_STATUS:
        return []
    archived = is_archived(tasks, page)
    if status in ARCHIVE_STATUS and not archived:
        return [Issue(
            SEV_BLOCKING, "location", page,
            f"status is `{status}` but file lives under tasks/ — "
            f"move to {tasks / 'archive' / page.name}",
        )]
    return []


def check_archive_migration(tasks: Path, page: Path, fm: dict | None) -> list[Issue]:
    if not fm or not is_archived(tasks, page):
        return []
    status = fm.get("status")
    if not isinstance(status, str) or status not in VALID_STATUS or status in ARCHIVE_STATUS:
        return []
    return [Issue(
        SEV_BLOCKING, "migration", page,
        f"status is `{status}` under archive/ — migrate to `status: finished`; "
        "legacy status migration does not bump `updated` when this is the only change",
    )]


def is_pre_implementation(fm: dict | None) -> bool:
    """Return True when the frontmatter status is open, checked, or ready."""
    return bool(fm) and fm.get("status") in PRE_IMPLEMENTATION_STATUS


def is_live_pre_implementation(tasks: Path, page: Path, fm: dict | None) -> bool:
    """Return True for a live task at open, checked, or ready.

    The one gate the oversized-page and repeated-link warnings share. An
    archived page stays quiet whatever status it carries: a status other than
    finished or deferred under archive/ is the actual error there, and the
    blocking migration finding reports it.
    """
    return is_pre_implementation(fm) and not is_archived(tasks, page)


def check_size(tasks: Path, page: Path, fm: dict | None) -> list[Issue]:
    """Warn when a task body exceeds the split threshold.

    Live open, checked, and ready tasks only: the warning prompts a split
    before implementation, so an implemented or audited task, a page without
    a valid status, and every archived page stay quiet.
    """
    if not is_live_pre_implementation(tasks, page, fm):
        return []
    text = page.read_text(encoding="utf-8")
    line_count = len(text.splitlines())
    if line_count > MAX_LINES_BEFORE_SPLIT:
        return [Issue(
            SEV_WARN, "size", page,
            f"{line_count} lines (split into multiple tasks at "
            f">{MAX_LINES_BEFORE_SPLIT})",
        )]
    return []


def check_scope(tasks: Path, page: Path) -> list[Issue]:
    """Validate the `scope:` frontmatter field.

    Unquoted values are treated as relative paths under the project root
    (the parent of `tasks/`). Quoted values (single or double) are
    accepted as descriptive text. The rule keeps the filesystem as the
    source of truth: when a directory fits, point at it; only fall back
    to a quoted label when nothing on disk matches.
    """
    text = page.read_text(encoding="utf-8")
    raw = get_raw_scope(text)
    if raw is None or raw == "":
        return []  # missing-field reported by check_frontmatter

    quoted = (
        (raw.startswith('"') and raw.endswith('"') and len(raw) >= 2)
        or (raw.startswith("'") and raw.endswith("'") and len(raw) >= 2)
    )
    if quoted:
        inner = raw[1:-1]
        if not inner.strip():
            return [Issue(
                SEV_BLOCKING, "scope", page,
                "scope is quoted but empty — write a real label or a relative path",
            )]
        return []

    project_root = tasks.parent.resolve()
    target = (project_root / raw).resolve()
    try:
        target.relative_to(project_root)
    except ValueError:
        return [Issue(
            SEV_BLOCKING, "scope", page,
            f"scope {raw!r} escapes the project root ({project_root}) — "
            f"use a path inside the project, or quote it as text: "
            f"`scope: \"{raw}\"`",
        )]
    if not target.exists():
        return [Issue(
            SEV_BLOCKING, "scope", page,
            f"scope path {raw!r} does not exist under project root "
            f"{project_root} — either point at a real folder/file or quote "
            f"it as descriptive text: `scope: \"{raw}\"`",
        )]
    return []


def _fence_marker(line: str) -> tuple[str, int] | None:
    """Return a valid CommonMark fence marker and its run length."""
    match = FENCE_RE.match(line)
    if match is None:
        return None
    run = match.group(2)
    if run[0] == "`" and "`" in match.group(3):
        return None
    return run[0], len(run)


def _scrub_inline_code(text: str) -> str:
    """Blank code spans closed by a matching-length backtick run."""
    chars = list(text)
    index = 0
    while index < len(text):
        if text[index] != "`":
            index += 1
            continue
        opener = index
        while index < len(text) and text[index] == "`":
            index += 1
        run_length = index - opener
        search = index
        closing_end = None
        while search < len(text):
            if text[search] != "`":
                search += 1
                continue
            closing_start = search
            while search < len(text) and text[search] == "`":
                search += 1
            if search - closing_start == run_length:
                closing_end = search
                break
        if closing_end is None:
            continue
        for scrub_index in range(opener, closing_end):
            if chars[scrub_index] not in "\r\n":
                chars[scrub_index] = " "
        index = closing_end
    return "".join(chars)


def _list_item_content_column(line: str) -> int | None:
    """Return the content column a list-item marker line opens, or None."""
    match = LIST_ITEM_RE.match(line)
    if match is None:
        return None
    marker_end = len(match.group(1)) + len(match.group(2))
    spaces = len(match.group(3))
    if not line[match.end():].strip() or spaces > 4:
        # An empty item or one opening with indented code starts its
        # content one column past the marker.
        return marker_end + 1
    return marker_end + spaces


def _scrub_fenced_blocks(text: str) -> str:
    """Blank CommonMark fenced blocks while preserving line structure.

    A fence counts when it sits zero to three columns right of its
    container: the document, or the content column of the innermost open
    list item. Open list items are tracked as a stack of content columns,
    so a fence nested under ``1.`` at four spaces is a fence. A list item
    ends at the first non-blank line indented left of its content column
    that follows a blank line, interrupts with a fence, or opens a sibling
    item; a lazy paragraph continuation keeps it open. A fence inside a
    list item also closes when that item ends.
    """
    out: list[str] = []
    containers: list[int] = []
    fence: tuple[str, int, int] | None = None
    previous_blank = True
    for line in text.splitlines(keepends=True):
        content = line.rstrip("\r\n")
        line_ending = line[len(content):]
        expanded = content.expandtabs(4)
        blank = not expanded.strip()
        indent = len(expanded) - len(expanded.lstrip(" "))
        if fence is not None:
            fence_char, fence_length, fence_column = fence
            if blank or indent >= fence_column:
                marker = _fence_marker(expanded[fence_column:])
                if (
                    marker is not None
                    and marker[0] == fence_char
                    and marker[1] >= fence_length
                    and not expanded[fence_column:].lstrip(" ").lstrip(fence_char).strip()
                ):
                    fence = None
                out.append(line_ending)
                previous_blank = False
                continue
            # The list item holding the fence ended, and the fence with it.
            fence = None
        if blank:
            out.append(line)
            previous_blank = True
            continue
        item_column = _list_item_content_column(expanded)
        if item_column is not None:
            while containers and containers[-1] > indent:
                containers.pop()
            containers.append(item_column)
            candidate_column = item_column
        else:
            if containers and indent < containers[-1]:
                interrupts = _fence_marker(expanded) is not None
                if previous_blank or interrupts:
                    while containers and containers[-1] > indent:
                        containers.pop()
            candidate_column = containers[-1] if containers else 0
        marker = (
            _fence_marker(expanded[candidate_column:])
            if indent >= candidate_column or item_column is not None
            else None
        )
        if marker is not None:
            fence = (marker[0], marker[1], candidate_column)
            out.append(line_ending)
        else:
            out.append(line)
        previous_blank = False
    return "".join(out)


def _autolink_end(text: str, start: int) -> int | None:
    """Return the index after a CommonMark URI or email autolink at start."""
    if start >= len(text) or text[start] != "<":
        return None
    index = start + 1
    if index >= len(text):
        return None
    if text[index].isalpha():
        scheme_start = index
        index += 1
        while index < len(text) and (
            text[index].isalnum() or text[index] in "+.-"
        ):
            index += 1
        scheme_length = index - scheme_start
        if (
            2 <= scheme_length <= 32
            and index < len(text)
            and text[index] == ":"
        ):
            index += 1
            while index < len(text) and text[index] not in "<> \t\r\n":
                index += 1
            if index < len(text) and text[index] == ">":
                return index + 1
            return None
    # Email autolink: <local@domain>
    index = start + 1
    at_index = -1
    while index < len(text) and text[index] not in "<> \t\r\n":
        if text[index] == "@":
            if at_index != -1:
                return None
            at_index = index
        index += 1
    if (
        at_index > start + 1
        and at_index + 1 < index
        and index < len(text)
        and text[index] == ">"
    ):
        return index + 1
    return None


def _raw_html_end(text: str, start: int) -> int | None:
    """Return the index after a raw HTML tag, comment, or declaration."""
    if start >= len(text) or text[start] != "<":
        return None
    index = start + 1
    if index >= len(text):
        return None
    if text.startswith("!--", index):
        close = text.find("-->", index + 3)
        return None if close < 0 else close + 3
    if text[index] in "?!":
        close = text.find(">", index + 1)
        return None if close < 0 else close + 1
    if text[index] == "/":
        index += 1
    if index >= len(text) or not text[index].isalpha():
        return None
    index += 1
    while index < len(text) and (
        text[index].isalnum() or text[index] in "-:"
    ):
        index += 1
    in_quote: str | None = None
    while index < len(text):
        char = text[index]
        if in_quote is not None:
            if char == in_quote:
                in_quote = None
            index += 1
            continue
        if char in "\"'":
            in_quote = char
            index += 1
            continue
        if char == ">":
            return index + 1
        if char == "<":
            return None
        index += 1
    return None


def _angle_opens_link_destination(text: str, angle_index: int) -> bool:
    """Return whether ``<`` at angle_index opens a markdown link destination.

    Inline destinations sit after ``](``; reference destinations sit after
    ``]:``. Those angle brackets are path spelling, not autolinks or HTML,
    and must survive scrubbing so spaced destinations keep working.
    """
    index = angle_index - 1
    while index >= 0 and text[index] in " \t":
        index -= 1
    if index >= 0 and text[index] == ":":
        index -= 1
        return index >= 0 and text[index] == "]"
    while index >= 0 and text[index] in " \t\n\r":
        index -= 1
    if index < 0 or text[index] != "(":
        return False
    index -= 1
    while index >= 0 and text[index] in " \t\n\r":
        index -= 1
    return index >= 0 and text[index] == "]"


def _scrub_angle_constructs(text: str) -> str:
    """Blank CommonMark autolinks and raw HTML while preserving newlines."""
    chars = list(text)
    index = 0
    while index < len(text):
        if text[index] != "<" or _is_escaped(text, index):
            index += 1
            continue
        if _angle_opens_link_destination(text, index):
            index += 1
            continue
        end = _autolink_end(text, index) or _raw_html_end(text, index)
        if end is None:
            index += 1
            continue
        for scrub_index in range(index, end):
            if chars[scrub_index] not in "\r\n":
                chars[scrub_index] = " "
        index = end
    return "".join(chars)


def _scrub_code(text: str) -> list[str]:
    """Return body lines with fenced code blocks and inline code stripped
    out so test syntax and code samples don't false-positive the
    standard-markdown checks.
    """
    return _scrub_inline_code(_scrub_fenced_blocks(text)).splitlines()


def _scrub_fences(text: str) -> list[str]:
    """Return body lines with fenced code blocks blanked but inline code
    spans kept intact.

    The soft-pointer check needs the opposite of `_scrub_code`: tool
    output (grep dumps, stack traces, expected-output blocks) is the
    dominant false-positive source and lives in fences, so fences go;
    real references legitimately live in inline code spans, so those stay
    checked. The companion writing convention is outputs-in-fences,
    references-in-inline-code.
    """
    return _scrub_fenced_blocks(text).splitlines()


def _is_escaped(text: str, index: int) -> bool:
    """Return whether punctuation at index has an odd backslash prefix."""
    backslashes = 0
    index -= 1
    while index >= 0 and text[index] == "\\":
        backslashes += 1
        index -= 1
    return backslashes % 2 == 1


def _decode_markdown(value: str) -> str:
    """Decode CommonMark backslash escapes and character references."""
    decoded: list[str] = []
    index = 0
    while index < len(value):
        if (
            value[index] == "\\"
            and index + 1 < len(value)
            and value[index + 1] in MARKDOWN_ESCAPABLE
            and not _is_escaped(value, index)
        ):
            index += 1
        decoded.append(value[index])
        index += 1
    return ENTITY_RE.sub(lambda match: html.unescape(match.group(0)), "".join(decoded))


def _parse_link_label(text: str, start: int) -> tuple[str, int] | None:
    """Return a possibly nested bracket label and the index after it."""
    if start >= len(text) or text[start] != "[":
        return None
    depth = 1
    index = start + 1
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text) and not _is_escaped(text, index):
            index += 2
            continue
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return text[start + 1:index], index + 1
        index += 1
    return None


def _parse_bare_destination(text: str, start: int) -> tuple[str, int] | None:
    """Return a non-angle destination with balanced parentheses."""
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if char == "\\" and index + 1 < len(text) and not _is_escaped(text, index):
            index += 2
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            if depth == 0:
                break
            depth -= 1
        elif char.isspace() and depth == 0:
            break
        index += 1
    if depth != 0:
        return None
    return _decode_markdown(text[start:index]), index


def _skip_link_title(text: str, start: int) -> int | None:
    """Return the closing inline-link parenthesis after an optional title."""
    index = start
    had_whitespace = False
    while index < len(text) and text[index].isspace():
        had_whitespace = True
        index += 1
    if index < len(text) and text[index] == ")":
        return index + 1
    if not had_whitespace or index >= len(text) or text[index] not in "\"'(":
        return None
    opener = text[index]
    closer = ")" if opener == "(" else opener
    index += 1
    while index < len(text):
        if (
            text[index] == "\\"
            and index + 1 < len(text)
            and not _is_escaped(text, index)
        ):
            index += 2
            continue
        if text[index] == closer:
            index += 1
            break
        if text[index] == "\n":
            return None
        index += 1
    else:
        return None
    while index < len(text) and text[index].isspace():
        index += 1
    return index + 1 if index < len(text) and text[index] == ")" else None


def _parse_reference_title(text: str, start: int) -> int | None:
    """Return the index after one complete reference-definition title."""
    if start >= len(text) or text[start] not in "\"'(":
        return None
    opener = text[start]
    closer = ")" if opener == "(" else opener
    index = start + 1
    while index < len(text):
        if (
            text[index] == "\\"
            and index + 1 < len(text)
            and not _is_escaped(text, index)
        ):
            index += 2
            continue
        if text[index] == closer:
            return index + 1
        index += 1
    return None


def _parse_inline_destination(text: str, start: int) -> tuple[str, int] | None:
    """Return a decoded inline destination and the index after its link."""
    index = start
    while index < len(text) and text[index].isspace():
        index += 1
    if index < len(text) and text[index] == "<":
        index += 1
        destination_start = index
        while index < len(text) and text[index] not in ">\n":
            index += (
                2
                if text[index] == "\\"
                and index + 1 < len(text)
                and not _is_escaped(text, index)
                else 1
            )
        if index >= len(text) or text[index] != ">":
            return None
        destination = _decode_markdown(text[destination_start:index])
        end = _skip_link_title(text, index + 1)
    else:
        parsed = _parse_bare_destination(text, index)
        if parsed is None:
            return None
        destination, index = parsed
        end = _skip_link_title(text, index)
    return (destination, end) if end is not None else None


def _normalize_reference_label(label: str) -> str:
    """Return CommonMark's case-insensitive, whitespace-collapsed label key."""
    return " ".join(_decode_markdown(label).split()).casefold()


def _reference_definitions(text: str) -> tuple[dict[str, str], list[tuple[int, int]]]:
    """Collect link reference definitions and their source spans."""
    definitions: dict[str, str] = {}
    spans: list[tuple[int, int]] = []
    lines = text.splitlines(keepends=True)
    offsets: list[int] = []
    offset = 0
    for line in lines:
        offsets.append(offset)
        offset += len(line)
    for line_index, line in enumerate(lines):
        offset = offsets[line_index]
        content = line.rstrip("\r\n")
        indent = len(content) - len(content.lstrip(" "))
        start = offset + indent
        parsed_label = _parse_link_label(text, start) if indent <= 3 else None
        if parsed_label is not None:
            label, after_label = parsed_label
            if after_label < len(text) and text[after_label] == ":":
                destination_start = after_label + 1
                while destination_start < len(text) and text[destination_start] in " \t":
                    destination_start += 1
                line_end = offset + len(content)
                if destination_start < line_end and text[destination_start] == "<":
                    destination_start += 1
                    destination_end = destination_start
                    while destination_end < line_end and text[destination_end] != ">":
                        if (
                            text[destination_end] == "<"
                            and not _is_escaped(text, destination_end)
                        ):
                            break
                        destination_end += 1
                    valid = (
                        destination_end < line_end
                        and text[destination_end] == ">"
                        and not _is_escaped(text, destination_end)
                    )
                    after_destination = destination_end + 1
                else:
                    parsed_destination = _parse_bare_destination(
                        text[:line_end], destination_start
                    )
                    valid = parsed_destination is not None
                    if valid:
                        _destination, after_destination = parsed_destination
                        destination_end = after_destination
                span_end = line_end
                remainder = text[after_destination:line_end] if valid else ""
                if remainder.strip():
                    title_start = after_destination
                    while title_start < line_end and text[title_start] in " \t":
                        title_start += 1
                    title_end = _parse_reference_title(text[:line_end], title_start)
                    valid = (
                        title_end is not None
                        and not text[title_end:line_end].strip()
                    )
                elif valid and line_index + 1 < len(lines):
                    next_offset = offsets[line_index + 1]
                    next_content = lines[line_index + 1].rstrip("\r\n")
                    next_indent = len(next_content) - len(next_content.lstrip(" "))
                    next_end = next_offset + len(next_content)
                    if next_indent <= 3:
                        title_start = next_offset + next_indent
                        title_end = _parse_reference_title(
                            text[:next_end], title_start
                        )
                        if (
                            title_end is not None
                            and not text[title_end:next_end].strip()
                        ):
                            span_end = next_end
                if valid and destination_end > destination_start and label:
                    if not label.startswith("^"):
                        definitions.setdefault(
                            _normalize_reference_label(label),
                            _decode_markdown(
                                text[destination_start:destination_end],
                            ),
                        )
                    spans.append((start, span_end))
    return definitions, spans


def iter_markdown_links(text: str) -> Iterator[tuple[str, str]]:
    """Yield link labels and decoded destinations from CommonMark links.

    URI/email autolinks and raw HTML take precedence over link parsing in
    CommonMark, so they are scrubbed first and link-shaped text inside them
    yields no destination. Indented code blocks stay unscrubbed on purpose:
    list-item content indented four columns is ordinary content with live
    links, and a caller's blanked inline code span at the start of a line
    would otherwise read as indentation. Samples belong in fences.
    """
    text = _scrub_angle_constructs(text)
    definitions, definition_spans = _reference_definitions(text)
    index = 0
    span_index = 0
    while index < len(text):
        while span_index < len(definition_spans) and index >= definition_spans[span_index][1]:
            span_index += 1
        if (
            span_index < len(definition_spans)
            and definition_spans[span_index][0] <= index < definition_spans[span_index][1]
        ):
            index = definition_spans[span_index][1]
            continue
        escaped_bracket = _is_escaped(text, index)
        if text[index] != "[" or escaped_bracket:
            index += 1
            continue
        parsed_label = _parse_link_label(text, index)
        if parsed_label is None:
            index += 1
            continue
        label, after_label = parsed_label
        image_opener = (
            index > 0
            and text[index - 1] == "!"
            and not _is_escaped(text, index - 1)
        )
        if image_opener:
            if after_label < len(text) and text[after_label] == "(":
                parsed_destination = _parse_inline_destination(text, after_label + 1)
                if parsed_destination is not None:
                    _destination, index = parsed_destination
                    continue
            if after_label < len(text) and text[after_label] == "[":
                parsed_reference = _parse_link_label(text, after_label)
                if parsed_reference is not None:
                    _reference, index = parsed_reference
                    continue
            index = after_label
            continue
        if after_label < len(text) and text[after_label] == "(":
            parsed_destination = _parse_inline_destination(text, after_label + 1)
            if parsed_destination is not None:
                destination, index = parsed_destination
                yield label, destination
                continue
        if after_label < len(text) and text[after_label] == "[":
            parsed_reference = _parse_link_label(text, after_label)
            if parsed_reference is not None:
                reference, reference_end = parsed_reference
                key = _normalize_reference_label(reference or label)
                if key in definitions:
                    yield label, definitions[key]
                    index = reference_end
                    continue
        key = _normalize_reference_label(label)
        if key in definitions:
            yield label, definitions[key]
            index = after_label
            continue
        index = after_label


def _has_size_suffix(line: str, end: int) -> bool:
    """Return True when a position-like number is immediately a size."""
    return bool(SIZE_SUFFIX_RE.match(line[end:]))


def check_no_position_claims(tasks: Path, page: Path) -> list[Issue]:
    """Warn on line-number position claims in an open task body.

    The soft-pointer rule bans a position claim — a `:N` suffix or `~N`
    marker on a file path, a bare `line N` / `line ~N`, an `around lines
    N-M` range, or a parenthesized `(~N-M)` range — because the number
    rots silently as the referenced file evolves while a verbatim
    greppable label fails loudly. Warn-only: never blocks, so a residual
    false positive surfaces one advisory line and fails nothing. Open
    tasks only — archived pages are closed records nobody maintains, so
    checking them would only create permanent noise. Fenced code blocks
    are skipped; inline code stays checked.
    """
    if is_archived(tasks, page):
        return []
    text = page.read_text(encoding="utf-8")
    _, body = parse_frontmatter(text)
    issues: list[Issue] = []
    for i, line in enumerate(_scrub_fences(body), start=1):
        for match in POSITION_PATH_RE.finditer(line):
            if _has_size_suffix(line, match.end()):
                continue
            issues.append(Issue(
                SEV_WARN, "soft-pointer", page,
                f"line-number position claim {match.group(0).strip()!r} — the "
                f"soft-pointer rule bans a `:N` suffix or `~N` marker on a file path; "
                f"anchor on a verbatim greppable label instead",
                line=i,
            ))
        for match in POSITION_PROSE_RE.finditer(line):
            if _has_size_suffix(line, match.end()):
                continue
            issues.append(Issue(
                SEV_WARN, "soft-pointer", page,
                f"line-number position claim {match.group(0).strip()!r} — "
                f"the soft-pointer rule bans a bare `line N`, `line ~N`, "
                f"or `around lines N-M`; anchor on a verbatim greppable label, and "
                f"give extent as size if useful",
                line=i,
            ))
        for match in POSITION_TILDE_RANGE_RE.finditer(line):
            if _has_size_suffix(line, match.end()):
                continue
            issues.append(Issue(
                SEV_WARN, "soft-pointer", page,
                f"line-number position claim {match.group(0).strip()!r} — "
                f"the soft-pointer rule bans a parenthesized `~N` / `~N-M` "
                f"range; anchor on a verbatim greppable label, and give "
                f"extent as size if useful",
                line=i,
            ))
    return issues


def check_no_footnotes(page: Path) -> list[Issue]:
    text = page.read_text(encoding="utf-8")
    _, body = parse_frontmatter(text)
    issues: list[Issue] = []
    for i, line in enumerate(_scrub_code(body), start=1):
        is_def = bool(FOOTNOTE_DEF_RE.match(line))
        for match in FOOTNOTE_REF_RE.finditer(line):
            kind = "definition" if is_def else "reference"
            issues.append(Issue(
                SEV_BLOCKING, "footnote", page,
                f"`[^{match.group(1)}]` footnote {kind} — footnotes are a "
                f"non-standard extension; place attribution inline as a "
                f"normal markdown link",
                line=i,
            ))
            if is_def:
                break
    return issues


def check_no_wikilinks(page: Path) -> list[Issue]:
    text = page.read_text(encoding="utf-8")
    _, body = parse_frontmatter(text)
    issues: list[Issue] = []
    for i, line in enumerate(_scrub_code(body), start=1):
        for match in WIKILINK_RE.finditer(line):
            inner = match.group(1)
            target_part, _, alias_part = inner.partition("|")
            target_part = target_part.strip()
            text_part = alias_part.strip() or target_part
            issues.append(Issue(
                SEV_BLOCKING, "wikilink", page,
                f"`[[{inner}]]` is an Obsidian extension, not standard "
                f"markdown — use `[{text_part}](<relative-path-to-"
                f"{target_part}>.md)`",
                line=i,
            ))
    return issues


def _normalize_local_link_destination(raw_target: str) -> str | None:
    """Return a local filesystem path spelling, or None when silent.

    Strips fragment and query components, then percent-decodes escaped
    path characters so URL-spelled destinations such as
    ``existing%20file.md`` and ``existing.md?view=1`` resolve to the
    same filesystem names readers follow. Returns None when the
    destination is empty, fragment-only, carries ``://``, or starts with
    ``mailto:``. A leading ``/`` that does not name an existing absolute
    filesystem path is rewritten without the slash so callers resolve it
    as repository-root-relative (renderer convention); an existing
    absolute path is left intact for the silence rule.
    """
    target = raw_target.split("#", 1)[0]
    target = target.split("?", 1)[0].strip()
    if not target or "://" in target or target.startswith("mailto:"):
        return None
    target = unquote(target)
    if target.startswith("/") and not Path(target).exists():
        return target.lstrip("/") or None
    return target


def _resolve_local_link_target(
    tasks: Path, page: Path, raw_target: str,
) -> Path | None:
    """Return a normalized local path for a markdown link target, or None
    when the target is empty, external (`://`), or `mailto:`.

    Resolves against the task file's directory first, then the project
    root (`tasks.parent`). When either candidate exists, that resolved
    path is the key; when neither exists, the page-relative resolution
    is still returned so distinct written prefixes that name the same
    missing path can still collapse.
    """
    target = _normalize_local_link_destination(raw_target)
    if target is None:
        return None
    project_root = tasks.parent.resolve()
    if target.startswith("/"):
        absolute = Path(target).resolve()
        if absolute.exists():
            return absolute
        # Defensive: normalize already strips a non-existing leading slash.
        target = target.lstrip("/")
        if not target:
            return None
    from_page = (page.parent / target).resolve()
    if from_page.exists():
        return from_page
    from_root = (project_root / target).resolve()
    if from_root.exists():
        return from_root
    return from_page


def check_local_links(tasks: Path, page: Path) -> list[Issue]:
    """Block on broken in-repo markdown link targets from this page.

    Silence rule: a target draws no finding when it carries ``://``,
    starts with ``mailto:``, is empty or fragment-only, or resolves
    outside the repo root once normalised (an absolute path elsewhere on
    the machine, or a relative path that climbs past the root). A
    leading-``/`` destination that does not exist as an absolute
    filesystem path is treated as repository-root-relative before that
    rule runs.

    Anchor fragments, query components, and trailing titles are stripped
    and percent-escaped path characters are decoded before resolving.
    A target is resolved against two roots before it is called broken:
    the linking file's own directory (so sibling and ``./``/``../`` links
    keep working) and the project root (``tasks.parent``, the same root
    ``scope:`` resolves against). Existence under either root is enough,
    and a target that resolves to a directory counts as present. Any
    in-repo path is checked, not only ``.md`` targets. Fenced code blocks
    and inline code are scrubbed via ``_scrub_code`` before links are
    collected, and ``iter_markdown_links`` also blanks autolinks and raw
    HTML, so link-shaped text in those constructs stays silent. A link in
    four-space-indented text is checked, because that text is usually
    list-item content; indented samples belong in fences.
    """
    text = page.read_text(encoding="utf-8")
    _, body = parse_frontmatter(text)
    project_root = tasks.parent.resolve()
    scrubbed = "\n".join(_scrub_code(body))

    def display(candidate: Path) -> Path:
        try:
            return candidate.relative_to(project_root)
        except ValueError:
            try:
                return candidate.relative_to(tasks)
            except ValueError:
                return candidate

    issues: list[Issue] = []
    for link_text, raw_target in iter_markdown_links(scrubbed):
        target = _normalize_local_link_destination(raw_target)
        if target is None:
            continue
        if target.startswith("/"):
            absolute = Path(target).resolve()
            if absolute.exists():
                # Present absolute path: silence whether in-repo or not.
                continue
            target = target.lstrip("/")
            if not target:
                continue
        from_page = (page.parent / target).resolve()
        if from_page.exists():
            # Present in-repo → clean; present outside → silence.
            continue
        from_root = (project_root / target).resolve()
        if from_root.exists():
            continue
        # Missing under both roots: silence when the page-relative
        # candidate sits outside the repo (absolute path elsewhere, or
        # climb past root). A project-root-relative miss that still lands
        # inside the root stays a broken-link finding.
        if not _path_inside_root(from_page, project_root):
            continue
        issues.append(Issue(
            SEV_BLOCKING, "broken-link", page,
            f"link target missing: {display(from_page)} "
            f"(also tried project root: {display(from_root)}) "
            f"({link_text!r})",
        ))
    return issues


def check_repeated_links(tasks: Path, page: Path, fm: dict | None) -> list[Issue]:
    """Warn when one local link target appears more than once in a body.

    Counts every non-fenced markdown link whose target is local (skips
    `://` and `mailto:` the same way ``check_local_links`` does), keyed
    by normalized resolved path so different relative prefixes to one
    file count once. Warn-only and candidate-not-verdict: the count is a
    hint that material about the target may sit in several places, not
    an instruction to drop a link. Leave out of the mechanically fixable
    finding set. Live open, checked, and ready tasks only: the warning
    prompts a reorganization before implementation, so an implemented or
    audited task, a page without a valid status, and every archived page
    stay quiet.
    """
    if not is_live_pre_implementation(tasks, page, fm):
        return []
    text = page.read_text(encoding="utf-8")
    _, body = parse_frontmatter(text)
    scrubbed = "\n".join(_scrub_fences(body))
    counts: dict[Path, int] = defaultdict(int)
    for _link_text, raw_target in iter_markdown_links(scrubbed):
        resolved = _resolve_local_link_target(tasks, page, raw_target)
        if resolved is None:
            continue
        counts[resolved] += 1

    def display(candidate: Path) -> str:
        try:
            return str(candidate.relative_to(tasks.parent.resolve()))
        except ValueError:
            try:
                return str(candidate.relative_to(tasks))
            except ValueError:
                return str(candidate)

    issues: list[Issue] = []
    for target, count in sorted(counts.items(), key=lambda item: str(item[0])):
        if count <= REPEATED_LINK_FLOOR:
            continue
        strength = (
            "a strong hint"
            if count > REPEATED_LINK_FLOOR + 1
            else "a hint"
        )
        issues.append(Issue(
            SEV_WARN, "repeated-link", page,
            f"{display(target)} is linked {count} times — {strength} that "
            f"material about it sits in several places and the body may "
            f"have grown organically; re-read those sections and gather "
            f"what belongs together (the hint strengthens with the count)",
        ))
    return issues


def check_name_collisions(pages: list[Path]) -> list[Issue]:
    by_name: dict[str, list[Path]] = defaultdict(list)
    for page in pages:
        by_name[page.name].append(page)
    issues: list[Issue] = []
    for name, paths in by_name.items():
        if len(paths) > 1:
            for path in paths:
                others = [str(p) for p in paths if p != path]
                issues.append(Issue(
                    SEV_BLOCKING, "collision", path,
                    f"duplicate task filename {name!r} also at {', '.join(others)}",
                ))
    return issues


def render_report(tasks: Path, issues: list[Issue], quiet: bool) -> str:
    if quiet:
        issues = [i for i in issues if i.severity != SEV_INFO]
    if not issues:
        return f"clean — no issues in {tasks}"

    issues.sort(key=lambda i: (i.severity, i.category, str(i.path), i.line or 0))
    by_sev: dict[int, list[Issue]] = defaultdict(list)
    for i in issues:
        by_sev[i.severity].append(i)

    out = [f"audit of {tasks}", ""]
    for sev in (SEV_BLOCKING, SEV_WARN, SEV_INFO):
        bucket = by_sev.get(sev, [])
        if not bucket:
            continue
        out.append(f"{SEVERITY_LABEL[sev].upper()} ({len(bucket)})")
        for issue in bucket:
            out.append(issue.render(tasks))
        out.append("")
    counts = Counter(i.severity for i in issues)
    summary = ", ".join(
        f"{counts.get(s, 0)} {SEVERITY_LABEL[s]}"
        for s in (SEV_BLOCKING, SEV_WARN, SEV_INFO)
    )
    out.append(f"total: {len(issues)}  ({summary})")
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Health-check the tasks directory (naming, frontmatter, "
            "status/location, size, collisions, and related per-file "
            "checks on task files) and, on a default or "
            "--include-archive run, check every in-repo markdown link "
            "from every markdown file under the project root (any in-repo "
            "target; silence outside). Under --file, link checks stay "
            "scoped to the named task file alone."
        ),
    )
    parser.add_argument(
        "tasks_path",
        nargs="?",
        help="Path to the tasks directory. If omitted, defers to scripts/discover_tasks.sh.",
    )
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument(
        "--include-archive",
        action="store_true",
        help="Extend the mechanical per-file checks across the whole "
        "tasks/archive/ tree for task_fix whole-archive maintenance (legacy "
        "retrofit hints included); the size and repeated-link warnings stay "
        "on live open, checked, and ready tasks. Link checks already cover "
        "every repo markdown file on a default run.",
    )
    scope.add_argument(
        "--file",
        metavar="PATH",
        help="Scope the per-file checks and the link check to one named "
        "task file, live or archived — the archive close-out verifies the "
        "single file it just moved. Mutually exclusive with "
        "--include-archive.",
    )
    parser.add_argument("--quiet", action="store_true", help="Suppress info-level findings.")
    args = parser.parse_args()

    tasks = discover_tasks(args.tasks_path)
    collision_pages = list(iter_task_files(tasks, include_archive=True))

    if args.file is not None:
        scoped_file = resolve_scoped_file(tasks, args.file, collision_pages)
        pages = [scoped_file]
        link_pages = [scoped_file]
    else:
        scoped_file = None
        pages = list(iter_task_files(tasks, include_archive=args.include_archive))
        link_pages = list(iter_repo_markdown_files(tasks.parent))

    issues: list[Issue] = []
    collision_issues = check_name_collisions(collision_pages)
    if scoped_file is not None:
        collision_issues = [i for i in collision_issues if i.path == scoped_file]
    issues.extend(collision_issues)

    for page in pages:
        issues.extend(check_filename(page))
        fm_issues, fm = check_frontmatter(tasks, page)
        issues.extend(fm_issues)
        issues.extend(check_scope(tasks, page))
        issues.extend(check_location(tasks, page, fm))
        issues.extend(check_archive_migration(tasks, page, fm))
        issues.extend(check_size(tasks, page, fm))
        issues.extend(check_no_footnotes(page))
        issues.extend(check_no_wikilinks(page))
        issues.extend(check_repeated_links(tasks, page, fm))
        issues.extend(check_no_position_claims(tasks, page))

    for page in link_pages:
        issues.extend(check_local_links(tasks, page))

    print(render_report(tasks, issues, args.quiet))
    return 1 if any(i.severity == SEV_BLOCKING for i in issues) else 0


if __name__ == "__main__":
    sys.exit(main())
