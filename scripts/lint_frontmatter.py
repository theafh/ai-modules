#!/usr/bin/env python3
"""Lint tracked YAML frontmatter against a strict, parser-stable subset.

Every tracked ``.md`` or ``.mdc`` file outside ``tests/`` that opens with a
``---`` line is checked. The accepted shapes are the ones this repository
actually uses, and each one parses to the value its author wrote under every
YAML parser: plain scalars, single- and double-quoted scalars, flow sequences,
``|`` / ``>`` block scalars with chomping indicators, and a block sequence
under an empty key. Anything else is reported with its path, line, and key.

The check also runs skill_doctor's bundled ``discovery_safety.py`` in place
over every tracked ``SKILL.md`` outside ``tests/``, so a skill whose frontmatter
the harness cannot route fails the same gate. The dependency runs from this
repository to the skill, never the other way, so skill_doctor stays portable
to repositories that carry no such gate.

Run with ``--values`` to print the decoded top-level values of the given files
as JSON keyed by path. That mode prints JSON alone, so another harness can
compare a generated file with its source.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve()
REPO_ROOT = SCRIPT_PATH.parent.parent
DISCOVERY_SAFETY = (
    REPO_ROOT
    / "plugins"
    / "ai_dev"
    / "skills"
    / "skill_doctor"
    / "scripts"
    / "discovery_safety.py"
)

FRONTMATTER_OPEN = "---"
KEY_RE = re.compile(r"^([A-Za-z0-9_-]+):(.*)$")
BLOCK_HEADER_RE = re.compile(r"^([|>])([-+]?)$")
FLOW_RE = re.compile(r"^\[(.*)\]$")
BLOCK_ITEM_RE = re.compile(r"^[ \t]+-[ \t]+(.*)$")
INDENTED_RE = re.compile(r"^[ \t]")

# YAML indicator characters. A plain scalar may not begin with any of them.
YAML_INDICATORS = set("-?:,[]{}#&*!|>'\"%@`")

# Backslash escapes YAML defines for double-quoted scalars. The numeric forms
# are handled separately in decode_double.
SIMPLE_ESCAPES = {
    "0": "\0",
    "a": "\a",
    "b": "\b",
    "t": "\t",
    "n": "\n",
    "v": "\v",
    "f": "\f",
    "r": "\r",
    "e": "\x1b",
    " ": " ",
    '"': '"',
    "/": "/",
    "\\": "\\",
    "N": "\u0085",
    "_": "\u00a0",
    "L": "\u2028",
    "P": "\u2029",
}


class Finding:
    """One rejection: where it is, the key it belongs to, and why."""

    def __init__(self, path, line, key, message):
        self.path = path
        self.line = line
        self.key = key
        self.message = message

    def render(self):
        where = self.path
        if self.line is not None:
            where = f"{where}:{self.line}"
        if self.key:
            where = f"{where}: {self.key}"
        return f"{where}: {self.message}"


def decode_single(raw, findings, line, key):
    """Decode a single-quoted scalar, or report why it is malformed."""
    if len(raw) < 2 or not raw.endswith("'"):
        findings.append(
            Finding("", line, key, "unterminated single-quoted value")
        )
        return None
    inner = raw[1:-1]
    out = []
    index = 0
    while index < len(inner):
        char = inner[index]
        if char == "'":
            if index + 1 < len(inner) and inner[index + 1] == "'":
                out.append("'")
                index += 2
                continue
            findings.append(
                Finding(
                    "",
                    line,
                    key,
                    "single-quoted value holds a lone `'`; write `''` for one",
                )
            )
            return None
        out.append(char)
        index += 1
    return "".join(out)


def decode_double(raw, findings, line, key):
    """Decode a double-quoted scalar, or report why it is malformed."""
    if len(raw) < 2 or not raw.endswith('"'):
        findings.append(
            Finding("", line, key, "unterminated double-quoted value")
        )
        return None
    out = []
    index = 1
    end = len(raw) - 1
    while index < end:
        char = raw[index]
        if char == '"':
            findings.append(
                Finding(
                    "",
                    line,
                    key,
                    "double-quoted value holds an unescaped `\"`; write `\\\"`",
                )
            )
            return None
        if char != "\\":
            out.append(char)
            index += 1
            continue
        if index + 1 >= end:
            findings.append(
                Finding("", line, key, "double-quoted value ends in a backslash")
            )
            return None
        escape = raw[index + 1]
        if escape in SIMPLE_ESCAPES:
            out.append(SIMPLE_ESCAPES[escape])
            index += 2
            continue
        widths = {"x": 2, "u": 4, "U": 8}
        if escape in widths:
            width = widths[escape]
            digits = raw[index + 2 : index + 2 + width]
            if len(digits) != width or not re.fullmatch(
                r"[0-9A-Fa-f]+", digits
            ):
                findings.append(
                    Finding(
                        "",
                        line,
                        key,
                        f"double-quoted value carries a malformed `\\{escape}` "
                        "escape",
                    )
                )
                return None
            out.append(chr(int(digits, 16)))
            index += 2 + width
            continue
        findings.append(
            Finding(
                "",
                line,
                key,
                f"double-quoted value carries an unknown `\\{escape}` escape",
            )
        )
        return None
    return "".join(out)


def plain_problem(value, extra_reject=""):
    """Why a plain scalar is outside the subset, or None when it is inside."""
    if value == "":
        return "is empty"
    if value[0] in YAML_INDICATORS:
        return (
            "starts with the YAML indicator character "
            f"`{value[0]}`; quote the value"
        )
    if ": " in value:
        return "contains a colon followed by a space; quote the value"
    if re.search(r"\s#", value):
        return "contains a `#` after whitespace; quote the value"
    if value.endswith(":"):
        return "ends with a colon; quote the value"
    for char in extra_reject:
        if char in value:
            return f"contains `{char}` inside a flow-sequence item; quote it"
    return None


def decode_quoted_or_plain(
    raw, findings, line, key, extra_reject="", context="plain value"
):
    """Decode one scalar written as a quoted or plain value."""
    value = raw.strip()
    if value.startswith("'"):
        return decode_single(value, findings, line, key)
    if value.startswith('"'):
        return decode_double(value, findings, line, key)
    problem = plain_problem(value, extra_reject)
    if problem:
        findings.append(Finding("", line, key, f"{context} {problem}"))
        return None
    return value


def split_flow_items(inner, findings, line, key):
    """Split a flow sequence body on top-level commas, respecting quotes."""
    items = []
    buffer = []
    quote = None
    index = 0
    while index < len(inner):
        char = inner[index]
        if quote is not None:
            if quote == '"' and char == "\\":
                buffer.append(char)
                if index + 1 < len(inner):
                    buffer.append(inner[index + 1])
                    index += 2
                    continue
                index += 1
                continue
            if char == quote:
                if (
                    quote == "'"
                    and index + 1 < len(inner)
                    and inner[index + 1] == "'"
                ):
                    buffer.append("''")
                    index += 2
                    continue
                quote = None
            buffer.append(char)
            index += 1
            continue
        if char in "'\"":
            quote = char
            buffer.append(char)
            index += 1
            continue
        if char == ",":
            items.append("".join(buffer))
            buffer = []
            index += 1
            continue
        buffer.append(char)
        index += 1
    if quote is not None:
        findings.append(
            Finding("", line, key, "flow-sequence item holds an unterminated quote")
        )
    items.append("".join(buffer))
    return items


def decode_flow(raw, findings, line, key):
    """Decode a one-line flow sequence into a list."""
    match = FLOW_RE.match(raw)
    if not match:
        findings.append(Finding("", line, key, "malformed flow sequence"))
        return None
    inner = match.group(1)
    raw_items = split_flow_items(inner, findings, line, key)
    values = []
    for raw_item in raw_items:
        item = raw_item.strip()
        if item == "":
            if inner.strip() == "":
                continue
            findings.append(
                Finding("", line, key, "flow sequence holds an empty item")
            )
            continue
        if item.startswith("'"):
            values.append(decode_single(item, findings, line, key))
        elif item.startswith('"'):
            values.append(decode_double(item, findings, line, key))
        else:
            problem = plain_problem(item, extra_reject=",[]{}")
            if problem:
                findings.append(
                    Finding(
                        "",
                        line,
                        key,
                        f"flow-sequence item is a plain value that {problem}",
                    )
                )
                values.append(None)
            else:
                values.append(item)
    return values


def fold_lines(lines):
    """Fold block-scalar lines by the YAML `>` rule.

    A line indented deeper than the block's base indent is a more-indented
    line: its line break is kept literally and its extra indentation
    preserved, where ordinary lines fold into a single space.
    """
    out = []
    previous = None
    for line in lines:
        if line == "":
            out.append("\n")
            previous = "blank"
            continue
        indented = line[:1] in (" ", "\t")
        kind = "indented" if indented else "normal"
        if previous == "normal" and not indented:
            out.append(" ")
        elif previous in ("normal", "indented"):
            out.append("\n")
        out.append(line)
        previous = kind
    return "".join(out)


def chomp(text, indicator):
    """Apply a block scalar's chomping indicator to its joined text."""
    if indicator == "-":
        return text.rstrip("\n")
    if indicator == "+":
        return text + ("\n" if text else "")
    body = text.rstrip("\n")
    return body + "\n" if body else ""


def decode_block(content, style, chomp_indicator):
    """Decode a `|` or `>` block scalar body."""
    indent = None
    for line in content:
        if line.strip():
            indent = len(line) - len(line.lstrip(" "))
            break
    if indent is None:
        indent = 0
    stripped = []
    for line in content:
        if line == "":
            stripped.append("")
        elif len(line) >= indent:
            stripped.append(line[indent:])
        else:
            stripped.append(line.lstrip())
    text = "\n".join(stripped) if style == "|" else fold_lines(stripped)
    return chomp(text, chomp_indicator)


def parse_block(block, path):
    """Parse one frontmatter block into values and findings."""
    findings = []
    fields = {}
    seen = set()
    index = 0
    total = len(block)
    while index < total:
        line = block[index]
        line_number = index + 2
        if line == "":
            index += 1
            continue
        if line.startswith("#"):
            index += 1
            continue
        if INDENTED_RE.match(line):
            findings.append(
                Finding(
                    path,
                    line_number,
                    None,
                    "indented line without a parent key (nested mappings are "
                    "outside the accepted subset)",
                )
            )
            index += 1
            continue
        match = KEY_RE.match(line)
        if not match:
            findings.append(
                Finding(
                    path,
                    line_number,
                    None,
                    "unparseable frontmatter line; expected `key: value`",
                )
            )
            index += 1
            continue
        key = match.group(1)
        rest = match.group(2)
        if rest and rest[0] not in " \t":
            findings.append(
                Finding(
                    path,
                    line_number,
                    key,
                    "missing space after the colon",
                )
            )
            index += 1
            continue
        raw = rest.strip()
        if key in seen:
            findings.append(
                Finding(path, line_number, key, "key appears more than once")
            )
        seen.add(key)

        if raw == "":
            region_end = index + 1
            while region_end < total and (
                block[region_end] == "" or INDENTED_RE.match(block[region_end])
            ):
                region_end += 1
            region = block[index + 1 : region_end]
            nonblank = [
                (offset, item)
                for offset, item in enumerate(region)
                if item.strip()
            ]
            if nonblank and all(
                BLOCK_ITEM_RE.match(item) for _, item in nonblank
            ):
                items = []
                for offset, item in nonblank:
                    item_line = index + 3 + offset
                    item_value = BLOCK_ITEM_RE.match(item).group(1)
                    decoded = decode_quoted_or_plain(
                        item_value,
                        findings,
                        item_line,
                        key,
                        context="block-sequence item is a plain value that",
                    )
                    items.append(decoded)
                fields[key] = items
                index = region_end
                continue
            if nonblank:
                offset = nonblank[0][0]
                findings.append(
                    Finding(
                        path,
                        index + 3 + offset,
                        key,
                        "nested mapping or indented value is outside the "
                        "accepted subset",
                    )
                )
                index = region_end
                continue
            findings.append(
                Finding(
                    path,
                    line_number,
                    key,
                    "empty value with no block sequence",
                )
            )
            index += 1
            continue

        block_match = BLOCK_HEADER_RE.match(raw)
        if block_match:
            style = block_match.group(1)
            chomp_indicator = block_match.group(2)
            content = []
            index += 1
            while index < total and (
                block[index] == "" or INDENTED_RE.match(block[index])
            ):
                content.append(block[index])
                index += 1
            fields[key] = decode_block(content, style, chomp_indicator)
            continue

        if raw.startswith("["):
            fields[key] = decode_flow(raw, findings, line_number, key)
            index += 1
            continue

        fields[key] = decode_quoted_or_plain(
            raw, findings, line_number, key
        )
        index += 1

    for finding in findings:
        finding.path = path
    return fields, findings


def read_lines(path):
    """The file's lines, or None when it cannot be read as UTF-8 text."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    return text.splitlines()


def has_frontmatter(lines):
    return bool(lines) and lines[0] == FRONTMATTER_OPEN


def check_file(path, display):
    """Return (values, findings) for one file, skipping files with no block."""
    lines = read_lines(path)
    if lines is None:
        return None, [
            Finding(display, None, None, "cannot read file as UTF-8 text")
        ]
    if not has_frontmatter(lines):
        return None, []
    try:
        close = lines.index(FRONTMATTER_OPEN, 1)
    except ValueError:
        return None, [
            Finding(display, None, None, "frontmatter block has no closing `---`")
        ]
    return parse_block(lines[1:close], display)


def tracked_files():
    """Every tracked path, as strings, from `git ls-files`."""
    try:
        result = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "ls-files", "-z"],
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise SystemExit(f"lint_frontmatter: cannot run git: {exc}")
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", "replace").strip()
        raise SystemExit(f"lint_frontmatter: git ls-files failed: {message}")
    return [
        entry.decode("utf-8", "surrogateescape")
        for entry in result.stdout.split(b"\0")
        if entry
    ]


def default_file_set(tracked):
    """Tracked .md/.mdc files outside tests/ whose first line is `---`."""
    selected = []
    for relative in tracked:
        if not (relative.endswith(".md") or relative.endswith(".mdc")):
            continue
        if relative.startswith("tests/"):
            continue
        if not has_frontmatter(read_lines(REPO_ROOT / relative) or []):
            continue
        selected.append(relative)
    return selected


def default_skill_set(tracked):
    """Tracked SKILL.md files outside tests/, whether or not they parse."""
    return [
        relative
        for relative in tracked
        if relative.endswith("/SKILL.md") or relative == "SKILL.md"
        if not relative.startswith("tests/")
    ]


def run_discovery_safety(skill_paths, stream):
    """Run skill_doctor's discovery check in place and report its findings.

    Returns (failed, warning_count). The missing-script check runs on every
    invocation, so a moved skill surfaces as a failure even when the set is
    empty.
    """
    if not DISCOVERY_SAFETY.is_file():
        print(
            "frontmatter: skill check script is missing: "
            f"{DISCOVERY_SAFETY}",
            file=stream,
        )
        return True, 0
    if not skill_paths:
        return False, 0
    command = [
        sys.executable,
        str(DISCOVERY_SAFETY),
        "--root",
        str(REPO_ROOT),
    ] + [str(path) for path in skill_paths]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    try:
        report = json.loads(result.stdout)
    except json.JSONDecodeError:
        print(
            "frontmatter: skill check produced no readable JSON report",
            file=stream,
        )
        return True, 0
    failed = False
    for item in report.get("blocking", []):
        print(
            f"frontmatter: {item.get('path', '')}: "
            f"discovery_safety.py {item.get('code', 'blocking')}: "
            f"{item.get('message', '')}",
            file=stream,
        )
        failed = True
    return failed, int(report.get("warning_count", 0))


def run_values(paths):
    """Print decoded top-level values as JSON alone."""
    payload = {}
    failed = False
    for display in paths:
        path = Path(display)
        values, findings = check_file(path, display)
        for finding in findings:
            print(finding.render(), file=sys.stderr)
            failed = True
        if values is not None:
            payload[display] = values
    print(json.dumps(payload, indent=2, sort_keys=True))
    if not DISCOVERY_SAFETY.is_file():
        print(
            "frontmatter: skill check script is missing: "
            f"{DISCOVERY_SAFETY}",
            file=sys.stderr,
        )
        failed = True
    return 1 if failed else 0


def run_default(explicit_paths):
    """Check the default or explicit file set and the skill set."""
    if explicit_paths:
        files = []
        for display in explicit_paths:
            lines = read_lines(Path(display))
            if lines is None or has_frontmatter(lines):
                files.append(display)
        skills = [
            path for path in explicit_paths if path.endswith("SKILL.md")
        ]
    else:
        tracked = tracked_files()
        files = default_file_set(tracked)
        skills = default_skill_set(tracked)

    print(f"\n== frontmatter ({len(files)} files, {len(skills)} skills) ==")

    failed = False
    for display in files:
        path = Path(display)
        if not explicit_paths and not path.is_absolute():
            path = REPO_ROOT / display
        _, findings = check_file(path, display)
        for finding in findings:
            print(finding.render())
            failed = True

    skill_failed, warning_count = run_discovery_safety(skills, sys.stdout)
    if skill_failed:
        failed = True
    if skills:
        print(
            f"frontmatter: {warning_count} discovery-safety warning(s) "
            "(non-blocking)"
        )

    print(f"frontmatter: checked {len(files)} files and {len(skills)} skills")
    return 1 if failed else 0


def build_parser():
    parser = argparse.ArgumentParser(
        description=(
            "Check tracked YAML frontmatter against a strict subset and run "
            "skill_doctor's discovery check over every tracked SKILL.md."
        )
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help=(
            "Explicit files to check (default: every tracked .md/.mdc outside "
            "tests/ whose first line is `---`)"
        ),
    )
    parser.add_argument(
        "--values",
        action="store_true",
        help="print decoded top-level values as JSON keyed by path",
    )
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    if args.values:
        return run_values(args.paths)
    return run_default(args.paths)


if __name__ == "__main__":
    raise SystemExit(main())
