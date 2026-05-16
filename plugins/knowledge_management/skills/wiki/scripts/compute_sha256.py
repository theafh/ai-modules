#!/usr/bin/env python3
"""compute_sha256.py — recompute and update body-only sha256 in raw/ frontmatter.

The wiki schema requires every file under `raw/<kind>/` to carry a
`sha256:` frontmatter field whose value is the SHA-256 of the body only
(everything after the closing `---`). This script computes that hash
correctly, then updates the frontmatter in place: existing `sha256:`
lines are rewritten when they drift, and missing `sha256:` lines are
inserted at the end of the frontmatter block. Lint surfaces the
mismatch under the `drift` category; this script is the fix.

Usage:
    python3 compute_sha256.py [PATH...] [--check] [--print] [--wiki-path PATH] [--quiet]

PATH may be a file or a directory; directories are recursed for `*.md`.
With no PATH, the script discovers the wiki (same logic as `lint.py`)
and walks every `*.md` under `raw/`.

Modes:
    default     write the correct sha256 in place when it differs
    --check     exit 1 if any file would change; write nothing
    --print     print `path: <hash>` for each file; write nothing

Exit codes:
    0  every file already carries the correct sha256 (or was updated)
    1  --check mode found at least one file that would change
    2  invocation error (path not found, frontmatter missing, etc.)
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Reuse the lint module's frontmatter parser and wiki discovery so the two
# scripts stay aligned on how raw files are read.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lint import discover_wiki, parse_frontmatter  # noqa: E402


SHA256_LINE_RE = re.compile(r"^sha256\s*:[^\n]*$", re.MULTILINE)


@dataclass
class Result:
    path: Path
    action: str  # "unchanged" | "updated" | "inserted" | "no-frontmatter"
    new_hash: str
    old_hash: str = ""

    @property
    def changed(self) -> bool:
        return self.action in ("updated", "inserted")


def _split_frontmatter(text: str) -> tuple[str, str, str] | None:
    """Return (fm_block_without_delimiters, body, body_offset_marker) when
    the document starts with a `---\\n…\\n---\\n` frontmatter block.
    """
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        return None
    fm_block = text[4:end]
    body = text[end + 5:]
    return fm_block, body, "\n---\n"


def update_sha256(text: str, new_hash: str) -> tuple[str, str, str]:
    """Apply `new_hash` to the frontmatter and return (new_text, action,
    old_hash). Action is `"unchanged"` when the recorded value already
    matches, `"updated"` when an existing line was rewritten, `"inserted"`
    when the field was appended, or `"no-frontmatter"` when the document
    has no frontmatter to update.
    """
    split = _split_frontmatter(text)
    if split is None:
        return text, "no-frontmatter", ""
    fm_block, body, sep = split

    match = SHA256_LINE_RE.search(fm_block)
    if match:
        old = match.group(0).split(":", 1)[1].strip().strip("'\"")
        if old == new_hash:
            return text, "unchanged", old
        new_fm = fm_block[:match.start()] + f"sha256: {new_hash}" + fm_block[match.end():]
        return f"---\n{new_fm}{sep}{body}", "updated", old

    new_fm = fm_block.rstrip() + f"\nsha256: {new_hash}"
    return f"---\n{new_fm}{sep}{body}", "inserted", ""


def process_file(path: Path) -> Result:
    text = path.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    if fm is None:
        return Result(path, "no-frontmatter", "")
    actual = hashlib.sha256(body.encode("utf-8")).hexdigest()
    _, action, old = update_sha256(text, actual)
    return Result(path, action, actual, old)


def write_file(path: Path, new_hash: str) -> None:
    text = path.read_text(encoding="utf-8")
    new_text, _, _ = update_sha256(text, new_hash)
    path.write_text(new_text, encoding="utf-8")


def collect_files(paths: list[str], wiki_path: str | None) -> list[Path]:
    if paths:
        files: list[Path] = []
        for raw in paths:
            p = Path(raw)
            if p.is_file():
                files.append(p)
            elif p.is_dir():
                files.extend(sorted(p.rglob("*.md")))
            else:
                print(f"path does not exist: {p}", file=sys.stderr)
                sys.exit(2)
        return files

    wiki = discover_wiki(wiki_path)
    raw_dir = wiki / "raw"
    if not raw_dir.is_dir():
        print(f"raw/ not found under {wiki}; nothing to compute", file=sys.stderr)
        sys.exit(2)
    return sorted(raw_dir.rglob("*.md"))


def render(result: Result, wiki_root: Path | None) -> str:
    try:
        rel = result.path.relative_to(wiki_root) if wiki_root else result.path
    except ValueError:
        rel = result.path
    if result.action == "no-frontmatter":
        return f"  skip   {rel}  (no frontmatter)"
    if result.action == "unchanged":
        return f"  ok     {rel}  {result.new_hash[:12]}…"
    if result.action == "updated":
        return f"  update {rel}  {result.old_hash[:12]}… → {result.new_hash[:12]}…"
    return f"  insert {rel}  {result.new_hash[:12]}…"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Recompute and update the body-only sha256 in raw/ frontmatter.",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Files or directories to process. Without args, walks the discovered wiki's raw/ tree.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit 1 if any file would change; write nothing.",
    )
    parser.add_argument(
        "--print",
        action="store_true",
        dest="print_only",
        help="Print `path: <hash>` for each file; write nothing.",
    )
    parser.add_argument(
        "--wiki-path",
        help="Explicit wiki root (forwarded to the same discovery logic as lint.py).",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress per-file status lines; summary only.",
    )
    args = parser.parse_args()

    files = collect_files(args.paths, args.wiki_path)
    if not files:
        print("no .md files to process")
        return 0

    # Resolve a reasonable display root for relative paths.
    wiki_root: Path | None = None
    if not args.paths:
        wiki_root = discover_wiki(args.wiki_path)

    results = [process_file(f) for f in files]

    if args.print_only:
        for r in results:
            if r.action == "no-frontmatter":
                continue
            print(f"{r.path}: {r.new_hash}")
        return 0

    would_change = [r for r in results if r.changed]
    skipped = [r for r in results if r.action == "no-frontmatter"]

    if not args.quiet:
        for r in results:
            print(render(r, wiki_root))

    if args.check:
        print(
            f"check: {len(would_change)} would change, "
            f"{len(results) - len(would_change) - len(skipped)} ok, "
            f"{len(skipped)} skipped"
        )
        return 1 if would_change else 0

    for r in would_change:
        write_file(r.path, r.new_hash)

    print(
        f"done: {len(would_change)} updated, "
        f"{len(results) - len(would_change) - len(skipped)} unchanged, "
        f"{len(skipped)} skipped"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
