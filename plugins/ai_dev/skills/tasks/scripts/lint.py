#!/usr/bin/env python3
"""lint.py — health-check the tasks directory.

Audits every `*.md` task file under the resolved tasks/ tree:
filename naming convention, frontmatter completeness, status/location
consistency, datetime format, title presence, page size, and name
collisions across open + archive.

Usage:
    python3 lint.py [TASKS_PATH] [--quiet]

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

REQUIRED_FRONTMATTER = ("description", "scope", "created", "updated", "status")
VALID_STATUS = {"open", "implemented", "deferred"}
ARCHIVE_STATUS = {"implemented", "deferred"}

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


def iter_task_files(tasks: Path) -> Iterator[Path]:
    """Yield every `*.md` task file: open tasks at the root and archived
    tasks under archive/. Other folders are ignored — the tasks tree is
    intentionally two-level only.
    """
    if not tasks.is_dir():
        return
    for path in sorted(tasks.glob("*.md")):
        if path.is_file():
            yield path
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


def check_frontmatter(page: Path) -> tuple[list[Issue], dict | None]:
    text = page.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    issues: list[Issue] = []
    if fm is None:
        issues.append(Issue(
            SEV_BLOCKING, "frontmatter", page,
            "missing or malformed frontmatter — every task needs "
            "`description`, `created`, `updated`, and `status` between `---` fences",
        ))
        return issues, None

    for field in REQUIRED_FRONTMATTER:
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
    if status == "open" and archived:
        return [Issue(
            SEV_BLOCKING, "location", page,
            "status is `open` but file lives under archive/ — "
            f"move to {tasks / page.name}",
        )]
    if status in ARCHIVE_STATUS and not archived:
        return [Issue(
            SEV_BLOCKING, "location", page,
            f"status is `{status}` but file lives under tasks/ — "
            f"move to {tasks / 'archive' / page.name}",
        )]
    return []


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


def check_local_links(tasks: Path, page: Path) -> list[Issue]:
    """Block on broken relative `.md` links from this task to others.

    External links (`https://…`, `mailto:`) are ignored. Anchor and
    query-string fragments are stripped before resolving. The local
    cross-reference contract is the same one the filesystem enforces —
    if the file is not there, the link is wrong.
    """
    text = page.read_text(encoding="utf-8")
    _, body = parse_frontmatter(text)
    issues: list[Issue] = []
    for match in LINK_RE.finditer(body):
        link_text, raw_target = match.group(1), match.group(2)
        target = raw_target.split("#", 1)[0].split(" ", 1)[0].strip()
        if not target or "://" in target or target.startswith("mailto:"):
            continue
        if not target.endswith(".md"):
            continue
        candidate = (page.parent / target).resolve()
        if not candidate.exists():
            try:
                rel = candidate.relative_to(tasks)
            except ValueError:
                rel = candidate
            issues.append(Issue(
                SEV_BLOCKING, "broken-link", page,
                f"link target missing: {rel} ({link_text!r})",
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
    parser.add_argument("--quiet", action="store_true", help="Suppress info-level findings.")
    args = parser.parse_args()

    tasks = discover_tasks(args.tasks_path)
    pages = list(iter_task_files(tasks))

    issues: list[Issue] = []
    issues.extend(check_name_collisions(pages))

    for page in pages:
        issues.extend(check_filename(page))
        fm_issues, fm = check_frontmatter(page)
        issues.extend(fm_issues)
        issues.extend(check_scope(tasks, page))
        issues.extend(check_location(tasks, page, fm))
        issues.extend(check_size(page))
        issues.extend(check_no_footnotes(page))
        issues.extend(check_no_wikilinks(page))
        issues.extend(check_local_links(tasks, page))

    print(render_report(tasks, issues, args.quiet))
    return 1 if any(i.severity == SEV_BLOCKING for i in issues) else 0


if __name__ == "__main__":
    sys.exit(main())
