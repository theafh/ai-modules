#!/usr/bin/env python3
"""lint.py — health-check the tasks directory.

Audits live `*.md` task files under the resolved tasks/ tree by default:
filename naming convention, frontmatter completeness, provenance,
status/location consistency, datetime format, title presence, page size,
and name collisions across live + archive. Pass `--include-archive` to
extend per-file checks over archived files: task_fix runs it for
whole-archive maintenance, and the task archive close-out runs it to
verify the single file it just moved.

Usage:
    python3 lint.py [TASKS_PATH] [--quiet] [--include-archive]

When TASKS_PATH is omitted the linter shells out to the sibling
``discover_tasks.sh`` so it resolves the same path the skill uses at
runtime — single source of truth for discovery semantics.

Exit codes:
    0  no blocking issues
    1  one or more blocking issues found
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator


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
IMPLEMENTER_STATUS = {"implemented", "audited", "finished"}

NAME_RE = re.compile(r"^(?P<scope>[a-z0-9]+(?:-[a-z0-9]+)*)_(?P<name>[a-z0-9]+(?:-[a-z0-9]+)*)\.md$")
DATETIME_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}"            # date
    r"(?:[T ]\d{2}:\d{2}(?::\d{2})?"  # optional time
    r"(?:Z|[+-]\d{2}:?\d{2})?)?$"     # optional tz
)
H1_RE = re.compile(r"^#\s+\S")

# Standard-markdown enforcement: footnotes and wikilinks are surfaced as
# blocking so the tasks tree stays portable to any CommonMark renderer.
FOOTNOTE_REF_RE = re.compile(r"\[\^([^\]\s]+)\]")
FOOTNOTE_DEF_RE = re.compile(r"^\s*\[\^([^\]\s]+)\]:")
WIKILINK_RE = re.compile(r"\[\[([^\[\]\n]+)\]\]")
FENCE_RE = re.compile(r"^```")
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
LINK_RE = re.compile(r"(?<!\!)\[([^\^\]][^\]]*)\]\(([^)]+)\)")

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


def get_raw_scope(text: str) -> str | None:
    """Return the raw `scope:` value verbatim — quotes preserved — so the
    scope check can tell quoted text from an unquoted path candidate.
    Returns None when there is no frontmatter or no scope field.
    """
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        end = text.find("\n---", 4)
        if end == -1:
            return None
    for raw_line in text[4:end].splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line or line.startswith(" ") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        if key.strip() == "scope":
            return value.strip()
    return None


def parse_frontmatter(text: str) -> tuple[dict | None, str]:
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end == -1:
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
        elif value.lower() in {"true", "false"}:
            data[key] = value.lower() == "true"
        else:
            data[key] = value.strip("'\"")
    return data, body


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


def is_archived(tasks: Path, page: Path) -> bool:
    try:
        rel = page.relative_to(tasks)
    except ValueError:
        return False
    return len(rel.parts) == 2 and rel.parts[0] == "archive"


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


def check_size(page: Path) -> list[Issue]:
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


def _scrub_code(text: str) -> list[str]:
    """Return body lines with fenced code blocks and inline code stripped
    out so test syntax and code samples don't false-positive the
    standard-markdown checks.
    """
    out: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if FENCE_RE.match(line.strip()):
            in_fence = not in_fence
            out.append("")
            continue
        if in_fence:
            out.append("")
            continue
        out.append(INLINE_CODE_RE.sub("", line))
    return out


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
    out: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if FENCE_RE.match(line.strip()):
            in_fence = not in_fence
            out.append("")
            continue
        if in_fence:
            out.append("")
            continue
        out.append(line)
    return out


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
    target = raw_target.split("#", 1)[0].split(" ", 1)[0].strip()
    if not target or "://" in target or target.startswith("mailto:"):
        return None
    from_page = (page.parent / target).resolve()
    if from_page.exists():
        return from_page
    from_root = (tasks.parent.resolve() / target).resolve()
    if from_root.exists():
        return from_root
    return from_page


def check_local_links(tasks: Path, page: Path) -> list[Issue]:
    """Block on broken relative `.md` links from this task to others.

    External links (`https://…`, `mailto:`) are ignored. Anchor and
    query-string fragments are stripped before resolving. A target is
    resolved against two roots before it is called broken: the task file's
    own directory (so sibling-task and `./`/`../` links keep working) and
    the project root (`tasks.parent`, the same root `scope:` resolves
    against — so a repo-root-relative path to a source file lints clean
    without a `../` prefix). Only a target that exists under neither root
    is a broken link.
    """
    text = page.read_text(encoding="utf-8")
    _, body = parse_frontmatter(text)
    project_root = tasks.parent.resolve()

    def display(candidate: Path) -> Path:
        try:
            return candidate.relative_to(tasks)
        except ValueError:
            return candidate

    issues: list[Issue] = []
    for match in LINK_RE.finditer(body):
        link_text, raw_target = match.group(1), match.group(2)
        target = raw_target.split("#", 1)[0].split(" ", 1)[0].strip()
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        if not target.endswith(".md"):
            continue
        from_page = (page.parent / target).resolve()
        if from_page.exists():
            continue
        from_root = (project_root / target).resolve()
        if from_root.exists():
            continue
        issues.append(Issue(
            SEV_BLOCKING, "broken-link", page,
            f"link target missing: {display(from_page)} "
            f"(also tried project root: {display(from_root)}) "
            f"({link_text!r})",
        ))
    return issues


def check_repeated_links(tasks: Path, page: Path) -> list[Issue]:
    """Warn when one local link target appears more than once in a body.

    Counts every non-fenced markdown link whose target is local (skips
    `://` and `mailto:` the same way ``check_local_links`` does), keyed
    by normalized resolved path so different relative prefixes to one
    file count once. Warn-only and candidate-not-verdict: the count is a
    hint that material about the target may sit in several places, not
    an instruction to drop a link. Leave out of the mechanically fixable
    finding set.
    """
    text = page.read_text(encoding="utf-8")
    _, body = parse_frontmatter(text)
    scrubbed = "\n".join(_scrub_fences(body))
    counts: dict[Path, int] = defaultdict(int)
    for match in LINK_RE.finditer(scrubbed):
        resolved = _resolve_local_link_target(tasks, page, match.group(2))
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
        description="Health-check the tasks directory: naming, frontmatter, status/location, size, collisions.",
    )
    parser.add_argument(
        "tasks_path",
        nargs="?",
        help="Path to the tasks directory. If omitted, defers to scripts/discover_tasks.sh.",
    )
    parser.add_argument(
        "--include-archive",
        action="store_true",
        help="Include tasks/archive/*.md in per-file checks and legacy retrofit hints.",
    )
    parser.add_argument("--quiet", action="store_true", help="Suppress info-level findings.")
    args = parser.parse_args()

    tasks = discover_tasks(args.tasks_path)
    pages = list(iter_task_files(tasks, include_archive=args.include_archive))
    collision_pages = list(iter_task_files(tasks, include_archive=True))

    issues: list[Issue] = []
    issues.extend(check_name_collisions(collision_pages))

    for page in pages:
        issues.extend(check_filename(page))
        fm_issues, fm = check_frontmatter(tasks, page)
        issues.extend(fm_issues)
        issues.extend(check_scope(tasks, page))
        issues.extend(check_location(tasks, page, fm))
        issues.extend(check_archive_migration(tasks, page, fm))
        issues.extend(check_size(page))
        issues.extend(check_no_footnotes(page))
        issues.extend(check_no_wikilinks(page))
        issues.extend(check_local_links(tasks, page))
        issues.extend(check_repeated_links(tasks, page))
        issues.extend(check_no_position_claims(tasks, page))

    print(render_report(tasks, issues, args.quiet))
    return 1 if any(i.severity == SEV_BLOCKING for i in issues) else 0


if __name__ == "__main__":
    sys.exit(main())
