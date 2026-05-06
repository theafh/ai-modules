#!/usr/bin/env python3
"""Lint pseudo-XML in skill, agent, and instruction files.

The linter auto-detects which of four file shapes the input follows
(prose-only markdown, single-root XML body, tutorial with ``` xml fences,
or mixed-agent with multiple top-level XML wrappers) and applies the
pseudo-XML rules to whatever XML the file contains. Rules are documented
in the SKILL.md of this skill (ai_instruction_formatting).

Usage:
    python3 scripts/lint_pseudo_xml.py                # walk CWD recursively
    python3 scripts/lint_pseudo_xml.py path/to/file   # explicit file
    python3 scripts/lint_pseudo_xml.py path/to/dir    # explicit directory
    python3 scripts/lint_pseudo_xml.py --quiet        # issues only
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# --- Configuration ---------------------------------------------------------

TAG_NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")
# Tag-like token: < optional-slash name rest optional-slash >.
# Tag name must start with a letter or underscore so prose like `<2 outbound)`
# does not match.
TAG_RE = re.compile(r"<(/?)([A-Za-z_][^\s/>]*)([^>]*?)(/?)>")
# Backtick code spans (single line). Inline ``…`` literals are markdown code,
# not pseudo-XML, so blank them out before tokenizing.
BACKTICK_SPAN_RE = re.compile(r"`[^`\n]+`")
# Numeric / single-letter suffix patterns that flag artificial differentiation.
NUM_SUFFIX_RE = re.compile(r"^(?P<prefix>.+?)_?(?P<num>\d+)$")

# Repeatable (parent, child) sibling pairs. Named tags are the default in
# pseudo-XML; this allowlist names the specific homogeneous-list shapes where
# repetition genuinely communicates more meaning than naming each child
# (constraints inside `<policy>`, demonstrations inside `<examples>`, etc.).
# Anything outside this set raises a duplicate-sibling warning with a
# suggestion to rename or wrap. A separate info-severity hint
# (check_named_phase_hint) still surfaces every match so the LLM weighs
# whether the structure-by-repetition is really the better choice for this
# spot or whether self-describing tags would communicate more clearly.
REPEATABLE: set[tuple[str, str]] = {
    ("policy", "rule"),
    ("rules", "rule"),
    ("steps", "step"),
    ("substeps", "substep"),
    ("examples", "example"),
    ("scoring_criteria", "criterion"),
    ("validations", "validation"),
}

# Concrete example tag names used in the named-phase hint suggestion text.
# Picked to evoke the anchor case (a child a reader would reference
# independently) the hint asks the LLM to weigh against the unit case
# (children read together as a homogeneous list).
NAMED_PHASE_EXAMPLE: dict[str, str] = {
    "step": "enumerate_dates",
    "substep": "fetch_context",
    "rule": "context_safety",
    "example": "minimal_input_example",
    "criterion": "technical_depth",
    "validation": "output_shape_check",
}

MAX_DEPTH = 5
SEVERITY_SYMBOL = {"error": "X", "warn": "!", "info": "i"}


# --- Data classes ----------------------------------------------------------

@dataclass
class Issue:
    severity: str  # "error" | "warn" | "info"
    line: int
    msg: str
    suggestion: str | None = None


@dataclass
class XmlBlock:
    text: str           # raw XML content
    base_line: int      # 1-indexed line where text[0] sits in the source file
    label: str          # human-readable origin (e.g. "body", "fence@112")


@dataclass
class FileReport:
    path: Path
    mode: str = "prose-only"
    info: list[str] = field(default_factory=list)
    good: list[str] = field(default_factory=list)
    issues: list[Issue] = field(default_factory=list)


@dataclass
class Tok:
    kind: str   # "open" | "close" | "self"
    name: str
    line: int
    raw: str
    rest: str


@dataclass
class Node:
    name: str
    line: int
    children: list["Node"] = field(default_factory=list)


# --- Frontmatter and body splitting ---------------------------------------

def split_frontmatter(text: str) -> tuple[str | None, str, int]:
    """Return (frontmatter_yaml or None, body, body_start_line_1_indexed)."""
    if not text.startswith("---\n"):
        return None, text, 1
    end = text.find("\n---\n", 4)
    if end == -1:
        return None, text, 1
    fm = text[4:end]
    body = text[end + len("\n---\n"):]
    body_start_line = text[: end + len("\n---\n")].count("\n") + 1
    return fm, body, body_start_line


def parse_frontmatter_name(fm: str) -> str | None:
    for line in fm.splitlines():
        m = re.match(r"^name:\s*(.+?)\s*$", line)
        if m:
            return m.group(1).strip().strip('"').strip("'")
    return None


def _normalize_for_match(s: str) -> str:
    """Normalize a name for H1-vs-frontmatter comparison: lowercase and treat
    spaces, hyphens, and underscores as equivalent so `# Wiki Auto Shaper`
    matches `name: wiki_auto_shaper` while genuine drift still trips."""
    return re.sub(r"[\s_\-]+", "_", s.strip().lower()).strip("_")


# --- Fence and top-level XML extraction -----------------------------------

def _strip_backtick_spans(line: str) -> str:
    """Replace inline backtick code spans with spaces of the same width so
    line numbers and column positions stay intact."""
    return BACKTICK_SPAN_RE.sub(lambda m: " " * len(m.group(0)), line)


def extract_fences_and_strip(body: str, body_start_line: int
                             ) -> tuple[list[XmlBlock], str]:
    """Pull `xml` fenced blocks out as XmlBlocks; replace every fenced code
    block (any language) in the returned text with blank lines so XML
    scanning skips them. Inline backtick code spans on prose lines also get
    blanked out so markdown literals like `<placeholder>` do not parse as
    tags. Markdown allows fences indented up to a few spaces inside list
    items — accept any leading whitespace on the opening fence and pair it
    with the next equally fenced close marker."""
    blocks: list[XmlBlock] = []
    out_lines: list[str] = []
    in_fence = False
    fence_lang: str | None = None
    fence_start_line = 0
    fence_buf: list[str] = []
    fence_open_re = re.compile(r"^\s*```([\w_-]*)\s*$")
    fence_close_re = re.compile(r"^\s*```\s*$")
    for i, line in enumerate(body.splitlines()):
        line_no = body_start_line + i
        if not in_fence:
            m = fence_open_re.match(line)
            if m:
                in_fence = True
                fence_lang = m.group(1) or ""
                fence_start_line = line_no + 1
                fence_buf = []
                out_lines.append("")
                continue
            out_lines.append(_strip_backtick_spans(line))
        else:
            if fence_close_re.match(line):
                if fence_lang == "xml":
                    blocks.append(XmlBlock(
                        text="\n".join(fence_buf),
                        base_line=fence_start_line,
                        label=f"fence@{fence_start_line - 1}",
                    ))
                in_fence = False
                fence_lang = None
                fence_buf = []
                out_lines.append("")
            else:
                fence_buf.append(line)
                out_lines.append("")
    return blocks, "\n".join(out_lines)


def extract_top_level_blocks(stripped_body: str, body_start_line: int
                             ) -> list[XmlBlock]:
    """Find top-level pseudo-XML wrappers at column 0.

    A top-level block is opened by a `<tag>` at column 0 and closed by a
    matching `</tag>` at column 0. Tag names must be snake_case ASCII.
    Tags found at non-zero indentation belong to a parent block and are
    parsed by parse_tree, not here."""
    lines = stripped_body.splitlines()
    blocks: list[XmlBlock] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^<([a-z][a-z0-9_]*)>\s*$", line)
        if not m:
            i += 1
            continue
        tag = m.group(1)
        close = f"</{tag}>"
        # Walk forward to find matching close at column 0.
        depth = 1
        j = i + 1
        while j < len(lines):
            cur = lines[j]
            if re.match(rf"^<{re.escape(tag)}>\s*$", cur):
                depth += 1
            elif cur.strip() == close and cur.startswith(close):
                depth -= 1
                if depth == 0:
                    break
            j += 1
        if j >= len(lines):
            # No matching column-0 close — leave it; parse_tree will flag
            # the unclosed tag when we lint the whole region as one block.
            i += 1
            continue
        block_text = "\n".join(lines[i : j + 1])
        blocks.append(XmlBlock(
            text=block_text,
            base_line=body_start_line + i,
            label=f"<{tag}> at line {body_start_line + i}",
        ))
        i = j + 1
    return blocks


# --- Tokenizer and tree builder -------------------------------------------

def tokenize(text: str, base_line: int) -> list[Tok]:
    line_starts = [0]
    for idx, ch in enumerate(text):
        if ch == "\n":
            line_starts.append(idx + 1)

    def line_of(idx: int) -> int:
        lo, hi = 0, len(line_starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if line_starts[mid] <= idx:
                lo = mid
            else:
                hi = mid - 1
        return base_line + lo

    toks: list[Tok] = []
    for m in TAG_RE.finditer(text):
        slash, name, rest, self_close = m.group(1), m.group(2), m.group(3), m.group(4)
        ln = line_of(m.start())
        if slash:
            toks.append(Tok("close", name, ln, m.group(0), rest))
        elif self_close:
            toks.append(Tok("self", name, ln, m.group(0), rest))
        else:
            toks.append(Tok("open", name, ln, m.group(0), rest))
    return toks


def parse_tree(block: XmlBlock, issues: list[Issue]) -> Node | None:
    """Parse one XML block into a tree; emit issues for tag-name shape,
    attributes, mismatched close, unclosed tags, and self-closing usage."""
    root: Node | None = None
    stack: list[Node] = []
    for tok in tokenize(block.text, block.base_line):
        # Tag name shape.
        if not TAG_NAME_RE.match(tok.name):
            issues.append(Issue(
                "error", tok.line,
                f"Tag <{tok.name}> uses an invalid name.",
                "Use ASCII snake_case only — `[a-z][a-z0-9_]*`. Drop "
                "capitals, hyphens, dots, colons, and HTML entities; "
                "encode the meaning in a single snake_case tag name.",
            ))
        # Attributes.
        rest_clean = tok.rest.strip()
        if rest_clean:
            issues.append(Issue(
                "error", tok.line,
                f"Tag <{tok.name} {rest_clean}> carries XML attributes.",
                "Move the attribute meaning into the tag name itself: "
                f"replace <{tok.name} {rest_clean}> with a descriptive "
                "snake_case tag like "
                f"<{tok.name}_"
                f"{re.sub(r'[^a-z0-9]+', '_', rest_clean.split('=')[0].lower()).strip('_') or 'attr'}>"
                ". Pseudo-XML carries every distinction in the tag name.",
            ))
        if tok.kind == "open":
            node = Node(name=tok.name, line=tok.line)
            if stack:
                stack[-1].children.append(node)
            else:
                if root is not None:
                    issues.append(Issue(
                        "error", tok.line,
                        f"Multiple root elements in this block: <{tok.name}> "
                        f"appears after <{root.name}> already closed.",
                        "Wrap the whole region in a single descriptive outer "
                        "tag, or split into separate top-level blocks.",
                    ))
                root = node
            stack.append(node)
        elif tok.kind == "close":
            if not stack:
                issues.append(Issue(
                    "error", tok.line,
                    f"Unexpected closing tag </{tok.name}> with no matching open.",
                    f"Either remove the stray </{tok.name}> or add a "
                    f"<{tok.name}> opening tag earlier in the block.",
                ))
                continue
            top = stack[-1]
            if top.name != tok.name:
                issues.append(Issue(
                    "error", tok.line,
                    f"Mismatched close: </{tok.name}> closes <{top.name}> "
                    f"opened at line {top.line}.",
                    f"Fix the close tag name to </{top.name}>, or close the "
                    "inner tag before this point.",
                ))
                while stack and stack[-1].name != tok.name:
                    stack.pop()
                if stack:
                    stack.pop()
            else:
                stack.pop()
        elif tok.kind == "self":
            issues.append(Issue(
                "warn", tok.line,
                f"Self-closing tag <{tok.name}/> — pseudo-XML uses explicit "
                "open and close tags.",
                f"Replace with <{tok.name}>...content...</{tok.name}>, or "
                "drop the tag if it carries no content.",
            ))
            node = Node(name=tok.name, line=tok.line)
            if stack:
                stack[-1].children.append(node)
            elif root is None:
                root = node
    for n in stack:
        issues.append(Issue(
            "error", n.line,
            f"Unclosed tag <{n.name}> opened at line {n.line}.",
            f"Add a matching </{n.name}> at the appropriate point, or remove "
            f"the <{n.name}> opening if it was unintended.",
        ))
    return root


# --- Tree-level checks -----------------------------------------------------

def check_depth(root: Node, issues: list[Issue]) -> int:
    max_depth_seen = 0

    def walk(n: Node, depth: int) -> None:
        nonlocal max_depth_seen
        if depth > max_depth_seen:
            max_depth_seen = depth
        if depth > MAX_DEPTH:
            issues.append(Issue(
                "warn", n.line,
                f"Tag <{n.name}> sits at depth {depth} — beyond the "
                f"recommended max of {MAX_DEPTH}.",
                "Flatten by extracting the leaf concept into a sibling tag "
                "of the parent, or move the deep detail into prose inside "
                "the parent.",
            ))
        for c in n.children:
            walk(c, depth + 1)

    walk(root, 1)
    return max_depth_seen


def check_repetition(root: Node, issues: list[Issue]) -> None:
    def walk(n: Node) -> None:
        seen: dict[str, Node] = {}
        for c in n.children:
            if c.name in seen and (n.name, c.name) not in REPEATABLE:
                first = seen[c.name]
                issues.append(Issue(
                    "warn", c.line,
                    f"Duplicate sibling <{c.name}> under <{n.name}> "
                    f"(first opened at line {first.line}).",
                    "If the two carry distinct meaning, give them distinct "
                    f"tag names (e.g., <{c.name}_primary> and "
                    f"<{c.name}_fallback>). If they are list items of the "
                    f"same kind, wrap them in a list parent: "
                    f"<{c.name}s>...<{c.name}>...</{c.name}>"
                    f"<{c.name}>...</{c.name}>...</{c.name}s> — repetition "
                    "inside a list parent is the canonical form.",
                ))
            seen.setdefault(c.name, c)
        for c in n.children:
            walk(c)

    walk(root)


def check_named_phase_hint(root: Node, issues: list[Issue]) -> None:
    """For every parent that uses a canonical (parent, child) pair from
    REPEATABLE with two or more children, emit one info-severity hint.

    The hint asks the LLM to weigh unit vs. anchor: are these repeated
    children read as a unit (consumed together, rarely referenced in
    isolation) or as anchors (a child a reader would jump to and reference
    independently)? Anchors promote to self-describing tags (e.g.,
    <enumerate_dates> instead of one of several <step> entries). One hint
    per parent group keeps output concise.
    """
    def walk(n: Node) -> None:
        groups: dict[str, list[Node]] = {}
        for c in n.children:
            if (n.name, c.name) in REPEATABLE:
                groups.setdefault(c.name, []).append(c)
        for child_name, group in groups.items():
            if len(group) < 2:
                continue
            example = NAMED_PHASE_EXAMPLE.get(
                child_name, f"named_{child_name}"
            )
            issues.append(Issue(
                "info", group[0].line,
                f"<{n.name}> contains {len(group)} <{child_name}> siblings "
                "using the canonical homogeneous-list pattern.",
                "Weigh in (unit vs. anchor): keep the repetition only if "
                "these children are read as a unit — a group consumed "
                "together where individual items are rarely referenced in "
                "isolation. If any child is an anchor — something a reader "
                "would jump to and reference independently, like a named "
                "procedure phase or a uniquely-scoped rule — promote it to "
                f"a self-describing tag (e.g., <{example}> rather than one "
                f"of several <{child_name}> entries). Different content "
                "alone is not the signal; addressability is.",
            ))
        for c in n.children:
            walk(c)

    walk(root)


def check_numeric_suffixes(root: Node, issues: list[Issue]) -> None:
    def walk(n: Node) -> None:
        groups: dict[str, list[Node]] = {}
        for c in n.children:
            m = NUM_SUFFIX_RE.match(c.name)
            if m and m.group("prefix"):
                groups.setdefault(m.group("prefix"), []).append(c)
        for prefix, group in groups.items():
            if len(group) >= 2:
                names = ", ".join(f"<{c.name}>" for c in group[:3])
                issues.append(Issue(
                    "warn", group[0].line,
                    f"Numeric-suffix sibling tags under <{n.name}>: {names}.",
                    f"Wrap them in a list parent and repeat the singular: "
                    f"<{prefix}s>\n  <{prefix}>...</{prefix}>\n  "
                    f"<{prefix}>...</{prefix}>\n</{prefix}s>. Repeated "
                    "identical siblings carry the 'homogeneous list' signal "
                    "cleanly; numeric suffixes inject artificial distinction.",
                ))
        for c in n.children:
            walk(c)

    walk(root)


def count_nodes(n: Node) -> int:
    return 1 + sum(count_nodes(c) for c in n.children)


# --- File-level lint -------------------------------------------------------

def lint_block(block: XmlBlock, rep: FileReport) -> None:
    before = len(rep.issues)
    root = parse_tree(block, rep.issues)
    if root is None:
        rep.issues.append(Issue(
            "error", block.base_line,
            f"Block at {block.label} contains no parseable root tag.",
            "Open the block with `<some_tag>` on its own line and close it "
            "with `</some_tag>`.",
        ))
        return
    max_depth_seen = check_depth(root, rep.issues)
    check_repetition(root, rep.issues)
    check_named_phase_hint(root, rep.issues)
    check_numeric_suffixes(root, rep.issues)
    new_blocking = [
        i for i in rep.issues[before:] if i.severity != "info"
    ]
    if not new_blocking:
        n = count_nodes(root)
        rep.good.append(
            f"{block.label}: {n} tags, max depth {max_depth_seen}, "
            "all snake_case, all closed cleanly."
        )


def lint_file(path: Path) -> FileReport:
    text = path.read_text(encoding="utf-8")
    rep = FileReport(path=path)

    fm, body, body_start_line = split_frontmatter(text)

    # Frontmatter checks (only when present).
    fm_name: str | None = None
    if fm is not None:
        fm_name = parse_frontmatter_name(fm)
        if fm_name is None:
            rep.issues.append(Issue(
                "warn", 1,
                "Frontmatter is present but has no `name:` field.",
                "Add `name: <skill_or_agent_name>` to the YAML frontmatter "
                "so the file declares its identity.",
            ))
        else:
            rep.info.append(f"Frontmatter: name={fm_name}")
            parts = path.parts
            if "skills" in parts:
                idx = parts.index("skills")
                if idx + 1 < len(parts):
                    expected = parts[idx + 1]
                    if expected != fm_name:
                        rep.issues.append(Issue(
                            "error", 1,
                            f"Frontmatter `name: {fm_name}` does not match "
                            f"the skill directory `{expected}`.",
                            f"Set `name: {expected}` so the frontmatter and "
                            "the directory name agree.",
                        ))
                    else:
                        rep.good.append(
                            f"Frontmatter name matches directory ({expected})."
                        )
    else:
        rep.info.append("No YAML frontmatter — frontmatter checks skipped.")

    # H1 check.
    h1: str | None = None
    for ln in body.splitlines():
        s = ln.strip()
        if not s:
            continue
        if s.startswith("# "):
            h1 = s[2:].strip()
        break
    if h1:
        rep.info.append(f"H1: # {h1}")
        if fm_name and _normalize_for_match(h1) != _normalize_for_match(fm_name):
            # Heading drift — the H1 is not just a casing or spacing variant
            # of the frontmatter name, it is a different name entirely.
            rep.issues.append(Issue(
                "warn", body_start_line,
                f"H1 `# {h1}` does not match frontmatter `name: {fm_name}`.",
                f"Update the H1 to a friendly form of `{fm_name}` (e.g., "
                f"`# {fm_name}` or `# {fm_name.replace('_', ' ').title()}`), "
                "or align the frontmatter `name:` to whatever the body title "
                "should be. Casing and spaces-vs-underscores are accepted as "
                "equivalent — only genuine name drift is flagged.",
            ))
        elif fm_name:
            rep.good.append("H1 matches frontmatter name.")
    elif fm is not None:
        rep.issues.append(Issue(
            "warn", body_start_line,
            "No H1 heading found after frontmatter.",
            "Add `# <name>` immediately after the frontmatter block, where "
            "<name> matches the frontmatter `name:` field.",
        ))

    # Detect file shape and lint each XML block.
    fence_blocks, stripped_body = extract_fences_and_strip(body, body_start_line)
    top_blocks = extract_top_level_blocks(stripped_body, body_start_line)

    if len(top_blocks) == 1 and not fence_blocks:
        # Confirm the single block actually spans (most of) the body.
        rep.mode = "xml-instruction"
        m = re.match(r"^<([a-z][a-z0-9_]*)>", top_blocks[0].text)
        root_name = m.group(1) if m else "?"
        rep.info.append(
            f"Mode: XML-instruction body (root: <{root_name}>)"
        )
        lint_block(top_blocks[0], rep)
    elif top_blocks and not fence_blocks:
        rep.mode = "mixed-agent"
        rep.info.append(
            f"Mode: mixed-agent ({len(top_blocks)} top-level "
            f"pseudo-XML wrapper{'s' if len(top_blocks) != 1 else ''})"
        )
        # Apply sibling-uniqueness across the top-level wrappers as if the
        # document were the implicit parent.
        seen: dict[str, int] = {}
        for blk in top_blocks:
            m = re.match(r"^<([a-z][a-z0-9_]*)>", blk.text)
            name = m.group(1) if m else "?"
            if name in seen:
                rep.issues.append(Issue(
                    "warn", blk.base_line,
                    f"Duplicate top-level <{name}> wrapper "
                    f"(first opened at line {seen[name]}).",
                    "Top-level wrappers in a mixed-agent file should each "
                    "describe a distinct concern — rename one to capture its "
                    f"specific role (e.g., <{name}_overview> and "
                    f"<{name}_details>).",
                ))
            else:
                seen[name] = blk.base_line
        for blk in top_blocks:
            lint_block(blk, rep)
    elif fence_blocks and not top_blocks:
        rep.mode = "tutorial"
        rep.info.append(
            f"Mode: tutorial ({len(fence_blocks)} `xml` fenced "
            f"example{'s' if len(fence_blocks) != 1 else ''})"
        )
        for blk in fence_blocks:
            lint_block(blk, rep)
    elif fence_blocks and top_blocks:
        rep.mode = "tutorial+mixed"
        rep.info.append(
            f"Mode: tutorial + mixed-agent ({len(top_blocks)} top-level "
            f"wrapper(s), {len(fence_blocks)} fenced example(s))"
        )
        for blk in top_blocks:
            lint_block(blk, rep)
        for blk in fence_blocks:
            lint_block(blk, rep)
    else:
        rep.mode = "prose-only"
        rep.info.append("Mode: prose-only (no pseudo-XML in body)")

    # Trailing-newline check.
    if not text.endswith("\n"):
        rep.issues.append(Issue(
            "warn", text.count("\n") + 1,
            "File does not end with a newline.",
            "Add a single trailing newline so the file matches POSIX text "
            "conventions and existing markdown lint settings.",
        ))
    elif text.endswith("\n\n\n"):
        rep.issues.append(Issue(
            "info", text.count("\n"),
            "File ends with multiple blank lines.",
            "Trim trailing blank lines so the file ends with exactly one "
            "newline.",
        ))
    else:
        rep.good.append("File ends with exactly one trailing newline.")

    return rep


# --- Output ----------------------------------------------------------------

def render_report(rep: FileReport, root: Path, quiet: bool) -> str:
    try:
        rel = rep.path.relative_to(root)
    except ValueError:
        rel = rep.path
    lines: list[str] = [f"--- {rel}"]
    for info in rep.info:
        lines.append(f"   {info}")
    blocking = [i for i in rep.issues if i.severity != "info"]
    hints = [i for i in rep.issues if i.severity == "info"]
    if blocking:
        lines.append("")
        lines.append("   Issues:")
        for issue in blocking:
            sym = SEVERITY_SYMBOL.get(issue.severity, "*")
            lines.append(f"     {sym} line {issue.line}: {issue.msg}")
            if issue.suggestion:
                lines.append(f"        -> {issue.suggestion}")
    if hints:
        lines.append("")
        lines.append("   Hints (LLM judgment — not violations):")
        for hint in hints:
            sym = SEVERITY_SYMBOL.get(hint.severity, "*")
            lines.append(f"     {sym} line {hint.line}: {hint.msg}")
            if hint.suggestion:
                lines.append(f"        -> {hint.suggestion}")
    if rep.good and not quiet:
        lines.append("")
        lines.append("   Looks good:")
        for g in rep.good:
            lines.append(f"     + {g}")
    if not blocking:
        lines.append("")
        lines.append("   PASS — no errors or warnings.")
    lines.append("")
    return "\n".join(lines)


def collect_targets(args_paths: list[str], root: Path) -> list[Path]:
    targets: list[Path] = []
    if args_paths:
        for raw in args_paths:
            p = Path(raw)
            if p.is_dir():
                targets.extend(p.rglob("SKILL.md"))
                targets.extend(p.rglob("agents/*.md"))
            elif p.is_file():
                targets.append(p)
            else:
                print(f"warning: {p} not found", file=sys.stderr)
    else:
        plugins = root / "plugins"
        if plugins.exists():
            targets.extend(plugins.rglob("SKILL.md"))
            targets.extend(plugins.rglob("agents/*.md"))
    return sorted({t.resolve() for t in targets})


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Lint pseudo-XML in skill, agent, and instruction files.",
    )
    parser.add_argument(
        "paths", nargs="*",
        help="Files or directories to lint. Default: ./plugins/",
    )
    parser.add_argument(
        "--quiet", action="store_true",
        help="Show issues only; suppress the 'looks good' detail list.",
    )
    args = parser.parse_args()

    root = Path.cwd()
    targets = collect_targets(args.paths, root)
    if not targets:
        print("No files to lint.")
        return 0

    total_blocking = 0
    total_errors = 0
    total_hints = 0
    for path in targets:
        rep = lint_file(path)
        print(render_report(rep, root, args.quiet))
        total_blocking += sum(1 for i in rep.issues if i.severity != "info")
        total_errors += sum(1 for i in rep.issues if i.severity == "error")
        total_hints += sum(1 for i in rep.issues if i.severity == "info")

    print("-" * 60)
    print(
        f"Linted {len(targets)} file(s). "
        f"Issues: {total_blocking} (errors: {total_errors}). "
        f"Hints: {total_hints}."
    )
    return 1 if total_errors else 0


if __name__ == "__main__":
    sys.exit(main())
