"""Content-addressed cache for the expensive behavioral eval runners.

The Pattern-A behavioral evals (`tests/<skill>/evals/run.py`) each spawn one
print-mode worker per eval (`agent -p` on the default Cursor vendor, or
`claude -p`), the slow, token-expensive part of a run. When a
runner is invoked again with nothing changed, re-spawning those workers pays
the full LLM bill to re-derive a verdict already in hand. This module lets a
runner skip the worker (and the re-grade) for an eval whose inputs have not
changed since a prior graded run, replaying that run's deterministic verdict.

"Inputs" for an eval are hashed by content, so the key changes — and the cache
misses, forcing a fresh run — whenever any of them changes:

- the skill source under test and its family dependencies (`source_roots`),
  whole-tree by default, or narrowed by an optional per-eval `dependencies`
  declaration that lists `SKILL.md` stage element names per skill-root
  basename (fail-closed: undeclared files and non-stage `SKILL.md` bytes still
  join every key; an absent or malformed declaration keeps whole-tree skill
  hashes),
- the harness definition (the `evals/` dir: evals.json, stage.sh, fixtures,
  run.py, and every sibling path), with `grade.sh` contributing through a
  per-eval `case "$eval_id"` arm-split only when bash's own parse confirms
  the split and the id-binding preconditions hold (`eval_id` bound once from
  `$1` and never rebound, no positional change before the binding outside a
  `-`-literal guard, every sourced file resolved and free of rebinding, no
  `nocasematch`, no re-invocation of the grader), and as the whole file
  otherwise,
- the shared helpers in `tests/lib` that decide a verdict (`VERDICT_HELPERS`),
- the worker model, the eval id, and the prompt.

A hit means every input the key covers is byte-identical to a run already
graded; a `SKILL.md` stage an eval's `dependencies` map leaves out, and a
`grade.sh` arm that cannot select the eval, may differ. The cache therefore
never serves a stale pass while four conditions hold: the runner's
declaration names every artefact the worker may load, `VERDICT_HELPERS` names
every shared helper a verdict depends on, each `dependencies` map names
every stage its eval's run can reach, and the grader is written in good faith.
Good faith means no program the grader executes re-enters `grade.sh`, and
neither the grader nor a file it sources rebinds `eval_id`, changes
positional parameters before the binding, or changes how bash parses or
matches arms through indirection static inspection cannot read. The split's
checks fail closed on every such construct they recognise, and this
condition covers the rest. A helper that starts deciding verdicts
joins `VERDICT_HELPERS` in the same change, and a stage a run starts reaching
joins that eval's map in the same change. This is the mechanical backstop for the base `task` skill's verification-economy rule —
"re-run only when the inputs changed" — applied to the one surface where the
waste is dramatic. It trades LLM-sampling variance (a second sample of an
unchanged distribution) for cost; a runner's `--force` re-runs and refreshes
the entry when a fresh sample is wanted, and `--no-cache` bypasses it entirely.

This is local, gitignored test tooling; it stores nothing that ships.
"""

from __future__ import annotations

import datetime
import functools
import hashlib
import json
import pathlib
import re
import secrets
import shutil
import subprocess
import tempfile

# Directory names never relevant to an eval's inputs — transient run output,
# the cache itself, Python bytecode, VCS and dependency trees.
_SKIP_DIRS = {
    "__pycache__", ".eval_cache", "workspace", "scratch", "results",
    ".git", "node_modules",
}
_SKIP_FILE_NAMES = {".DS_Store"}
_SKIP_SUFFIXES = {".pyc", ".pyo"}

# How much of the worker response to keep for operator inspection on a hit.
RESPONSE_EXCERPT_CHARS = 4000

# Cap entries per eval id so a long-lived cache file cannot grow without bound
# as skill content and models vary over time.
_MAX_ENTRIES_PER_EVAL = 12

# The shared helpers beside this module that decide a cached verdict:
# micro_deploy.py builds each pass's deployment and runs the
# artefacts_read_from_micro_deployment check, vendor.py builds the worker
# command and environment, host_tasks_guard.sh is the host tasks/ guard the
# task-family stage and grade scripts source, and repeated_link_disposition.sh
# is the record-bounded disposition-line reader task_fix and task_auto_check
# grade through. They feed every key, so an edit to one re-runs each cached
# eval once.
VERDICT_HELPERS = (
    "micro_deploy.py",
    "vendor.py",
    "host_tasks_guard.sh",
    "repeated_link_disposition.sh",
)
_HELPER_DIR = pathlib.Path(__file__).resolve().parent

_CASE_HEADER_RE = re.compile(
    r'case\s+(?:"\$eval_id"|\$eval_id)\s+in\b'
)
_OPEN_TAG_RE = re.compile(r"<([a-zA-Z_][a-zA-Z0-9_]*)>")


def _iter_files(root: pathlib.Path):
    """Yield (relname, path) for every content file under `root`.

    `root` may be a single file (yields it by its bare name) or a directory
    (walked recursively, sorted, with the skip lists applied). relname is
    POSIX-relative to `root`, so the same content hashes identically wherever
    the tree physically sits.
    """
    root = pathlib.Path(root)
    if root.is_file():
        yield root.name, root
        return
    if not root.is_dir():
        return
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root)
        if set(rel.parts[:-1]) & _SKIP_DIRS:
            continue
        if path.name in _SKIP_FILE_NAMES or path.suffix in _SKIP_SUFFIXES:
            continue
        yield rel.as_posix(), path


def _tree_hash(root: pathlib.Path) -> str:
    """Stable content hash of a file or directory tree."""
    digest = hashlib.sha256()
    for relname, path in _iter_files(root):
        digest.update(relname.encode())
        digest.update(b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).hexdigest().encode())
        digest.update(b"\0")
    return digest.hexdigest()


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _strip_frontmatter(text: str) -> str:
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            return parts[2]
    return text


def _matching_close(text: str, name: str, body_start: int) -> int | None:
    """Return end index (after `</name>`) for the element opened before body_start."""
    depth = 1
    i = body_start
    open_tok = f"<{name}>"
    close_tok = f"</{name}>"
    while i < len(text) and depth:
        nxt_open = text.find(open_tok, i)
        nxt_close = text.find(close_tok, i)
        if nxt_close < 0:
            return None
        if nxt_open >= 0 and nxt_open < nxt_close:
            depth += 1
            i = nxt_open + len(open_tok)
        else:
            depth -= 1
            i = nxt_close + len(close_tok)
            if depth == 0:
                return i
    return None


def _parse_top_level_stages(skill_text: str) -> dict[str, str]:
    """Map each top-level child of the skill root wrapper to its full element text."""
    body_src = _strip_frontmatter(skill_text)
    open_m = _OPEN_TAG_RE.search(body_src)
    if not open_m:
        return {}
    root_name = open_m.group(1)
    inner_start = open_m.end()
    root_end = _matching_close(body_src, root_name, inner_start)
    if root_end is None:
        return {}
    inner = body_src[inner_start: root_end - len(f"</{root_name}>")]
    stages: dict[str, str] = {}
    i = 0
    while i < len(inner):
        while i < len(inner) and inner[i] in " \t\n\r":
            i += 1
        if i >= len(inner):
            break
        if inner.startswith("<!--", i):
            end = inner.find("-->", i)
            i = end + 3 if end >= 0 else len(inner)
            continue
        if inner.startswith("</", i):
            gt = inner.find(">", i)
            i = gt + 1 if gt >= 0 else len(inner)
            continue
        om = _OPEN_TAG_RE.match(inner, i)
        if not om:
            nxt = inner.find("<", i + 1)
            i = nxt if nxt >= 0 else len(inner)
            continue
        name = om.group(1)
        elem_start = om.start()
        close_end = _matching_close(inner, name, om.end())
        if close_end is None:
            break
        stages[name] = inner[elem_start:close_end]
        i = close_end
    return stages


def _non_stage_material(skill_text: str, stages: dict[str, str]) -> str:
    """Bytes of SKILL.md outside every top-level stage element."""
    if not stages:
        return skill_text
    # Locate each stage element's first occurrence in the full file and excise it.
    remaining = skill_text
    for element in stages.values():
        remaining = remaining.replace(element, "", 1)
    return remaining


def _normalize_dependencies(dependencies) -> dict[str, list[str]] | None:
    """Return a basename→stage-names map, or None for absent/malformed input."""
    if dependencies is None:
        return None
    if not isinstance(dependencies, dict):
        return None
    out: dict[str, list[str]] = {}
    for key, value in dependencies.items():
        if not isinstance(key, str) or not key:
            return None
        if not isinstance(value, list) or not all(isinstance(x, str) and x for x in value):
            return None
        out[key] = list(value)
    return out


def _decode_for_parsing(raw: bytes) -> str | None:
    """Return `raw` as text for parsing, or None when it must hash whole.

    Parsing reads strict UTF-8 with LF line ends. Bytes carrying a `\\r` or
    failing to decode hash as the raw whole file instead, so a line-end
    conversion or an undecodable byte moves the key rather than vanishing
    in a text read or raising.
    """
    if b"\r" in raw:
        return None
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return None


def _declared_root_hash(root: pathlib.Path, stage_names: list[str]) -> str:
    """Hash a skill root under a stage declaration (fail-closed for the rest)."""
    digest = hashlib.sha256()
    skill_md = root / "SKILL.md" if root.is_dir() else None
    skill_text = ""
    stages: dict[str, str] = {}
    raw_skill = (skill_md.read_bytes()
                 if skill_md is not None and skill_md.is_file() else None)
    if raw_skill is not None and _decode_for_parsing(raw_skill) is None:
        # Unparseable bytes: the whole raw SKILL.md joins the key.
        digest.update(b"raw_skill_md\0")
        digest.update(_sha(raw_skill).encode())
        digest.update(b"\0")
    elif raw_skill is not None:
        skill_text = raw_skill.decode("utf-8")
        stages = _parse_top_level_stages(skill_text)
        for name in stage_names:
            digest.update(b"stage:")
            digest.update(name.encode())
            digest.update(b"\0")
            if name in stages:
                digest.update(_sha(stages[name].encode()).encode())
            else:
                # Missing declared stage → whole-file hash (fail closed).
                digest.update(_sha(skill_text.encode()).encode())
            digest.update(b"\0")
        non_stage = _non_stage_material(skill_text, stages)
        digest.update(b"non_stage\0")
        digest.update(_sha(non_stage.encode()).encode())
        digest.update(b"\0")
    for relname, path in _iter_files(root):
        if relname == "SKILL.md":
            continue
        digest.update(relname.encode())
        digest.update(b"\0")
        digest.update(_sha(path.read_bytes()).encode())
        digest.update(b"\0")
    return digest.hexdigest()


# A plain literal case-pattern alternative, which matches by equality alone.
_PLAIN_ALTERNATIVE_RE = re.compile(r"[A-Za-z0-9_.,:=%/-]+")


def _arm_matches(pattern: str, eval_id: str) -> bool:
    """Whether a `case` arm pattern can select `eval_id`.

    A leading `(` (the POSIX arm form) is dropped, then the pattern splits on
    `|` into alternatives. A plain literal word matches by equality. Every
    other alternative (one carrying a quote, backslash, glob character, `$`,
    or any of `!@+(`) could select ids this splitter does not evaluate, so it
    counts as matching every eval and joins every key (fail closed).
    """
    want = str(eval_id)
    body = pattern.strip()
    if body.startswith("("):
        body = body[1:]
    for part in body.split("|"):
        token = part.strip()
        if token == want or not _PLAIN_ALTERNATIVE_RE.fullmatch(token):
            return True
    return False


# The lexer and arm scanner below propose a grade.sh arm-split; bash decides
# whether it is used (see `_split_plan`). The proposal is itself a
# whitelist: it names a top-level `case "$eval_id"` block only when every
# part of that block is a shape the code below models, and proposes nothing
# otherwise. One lexing pass classifies each index of the grader; the arm
# scanner then reads `case`, `esac`, `in`, and `;;` only at code positions,
# as whole shell words, with `case` and `esac` at a command start. A block
# holding a here-document, a `;&` or `;;&` terminator, a `;;`/`case`/`esac`
# token inside a quote, expansion, or substitution, a pattern that spans a
# line or holds a parenthesis, or any construct the lexer could not
# classify, gets no proposal, so the whole file joins every key.

# Characters after which a shell word starts: blanks and shell metacharacters.
_SHELL_WORD_BREAKS = " \t\n\r;&|()<>"

# What `_lex_shell` records for each index of a grader.
_CODE, _QUOTED, _COMMENT, _HEREDOC, _LITERAL, _HEREDOC_LITERAL = 0, 1, 2, 3, 4, 5

# Reserved words after which a `case` or `esac` keyword can start a command.
_COMMAND_LEAD_WORDS = {"then", "do", "else", "elif", "if", "while", "until", "!", "{"}

# Tokens that, outside code inside a split block, mean the block holds syntax
# text the scanner does not read (a quoted `;;`, a commented `esac`).
_BLOCK_TOKEN_RE = re.compile(r";;|(?<![A-Za-z0-9_])(?:case|esac)(?![A-Za-z0-9_])")


class _Unsplittable(Exception):
    """A grade.sh shape the arm-split does not model; hash the whole file."""


def _word_at(text: str, i: int, word: str) -> bool:
    """Whether `word` stands at `i` as a whole shell word (no kind check)."""
    j = i + len(word)
    return (text.startswith(word, i)
            and (i == 0 or text[i - 1] in _SHELL_WORD_BREAKS)
            and (j >= len(text) or text[j] in _SHELL_WORD_BREAKS))


def _read_heredoc_delimiter(text: str, i: int, pending: list,
                            uncertain: list) -> int:
    """Read the delimiter of the `<<` at `i`; return the index after it."""
    n = len(text)
    j = i + 2
    strip_tabs = j < n and text[j] == "-"
    if strip_tabs:
        j += 1
    while j < n and text[j] in " \t":
        j += 1
    if j < n and text[j] in "'\"":
        close = text.find(text[j], j + 1)
        delim = text[j + 1:close] if close > j + 1 else ""
        if not delim or "\n" in delim or "\\" in delim:
            uncertain.append("unreadable here-document delimiter")
            return j + 1
        end = close + 1
    else:
        end = j
        while end < n and text[end] not in _SHELL_WORD_BREAKS \
                and text[end] not in "'\"\\$`":
            end += 1
        delim = text[j:end]
        if not delim or (end < n and text[end] in "'\"\\$`"):
            uncertain.append("unreadable here-document delimiter")
            return max(end, i + 2)
    if end < n and text[end] not in _SHELL_WORD_BREAKS:
        uncertain.append("unreadable here-document delimiter")
    pending.append((delim, strip_tabs, text[j] in "'\""))
    return end


def _read_heredoc_bodies(text: str, pos: int, pending: list,
                         kinds: bytearray, uncertain: list) -> int:
    """Mark the bodies of `pending` here-documents, which start at `pos`.

    Return the index of the newline that ends the last terminator line, so
    the caller reads that newline as code.
    """
    n = len(text)
    for delim, strip_tabs, literal in pending:
        body_kind = _HEREDOC_LITERAL if literal else _HEREDOC
        while True:
            if pos >= n:
                uncertain.append("unterminated here-document")
                return n
            newline = text.find("\n", pos)
            line_end = n if newline < 0 else newline
            line = text[pos:line_end]
            if (line.lstrip("\t") if strip_tabs else line) == delim:
                kinds[pos:line_end] = bytes([body_kind]) * (line_end - pos)
                pos = line_end + 1
                break
            stop = min(line_end + 1, n)
            kinds[pos:stop] = bytes([body_kind]) * (stop - pos)
            pos = stop
    return pos - 1


def _lex_shell(text: str):
    """Classify every index of a shell script in one pass.

    Returns `(kinds, heredoc_ops, uncertain)`. `kinds[i]` is `_CODE` for
    top-level shell syntax; `_LITERAL` inside single quotes or `$'...'`,
    where nothing expands; `_QUOTED` inside a double quote, a `${...}`,
    `$(...)`, `$((...))`, `((...))`, or backtick span, or a backslash escape;
    `_COMMENT` for a comment; `_HEREDOC` for a here-document body and
    `_HEREDOC_LITERAL` for one whose delimiter is quoted. A `#` opens a
    comment only at a word start in code.
    `heredoc_ops` lists each code-level `<<`. `uncertain` names every
    construct the pass could not classify with certainty: an unterminated
    span, a `case` or `<<` inside a command substitution, an unbalanced
    arithmetic span, or an unusual here-document delimiter.
    """
    n = len(text)
    kinds = bytearray(n)
    heredoc_ops: list[int] = []
    uncertain: list[str] = []
    pending: list[tuple[str, bool]] = []
    stack: list[list] = []  # [context, open-paren depth]

    def mark(a: int, b: int, kind: int) -> None:
        b = min(b, n)
        if b > a:
            kinds[a:b] = bytes([kind]) * (b - a)

    def open_span(i: int) -> int:
        """Open a nested span at `i` when one starts there; return its width."""
        if text.startswith("$((", i):
            stack.append(["arith", 0])
            return 3
        if text.startswith("$(", i):
            stack.append(["cmd", 0])
            return 2
        if text.startswith("${", i):
            stack.append(["param", 0])
            return 2
        if text[i] == "`":
            stack.append(["bt", 0])
            return 1
        return 0

    i = 0
    while i < n:
        c = text[i]
        ctx = stack[-1][0] if stack else None
        if ctx is None:
            if c == "\\":
                mark(i, i + 2, _QUOTED)
                i += 2
                continue
            if c == "'":
                ansi_c = i > 0 and text[i - 1] == "$" and kinds[i - 1] == _CODE
                if ansi_c:
                    kinds[i - 1] = _LITERAL
                stack.append(["ansi" if ansi_c else "sq", 0])
                kinds[i] = _LITERAL
                i += 1
                continue
            if c == '"':
                stack.append(["dq", 0])
                kinds[i] = _QUOTED
                i += 1
                continue
            width = open_span(i)
            if not width and text.startswith("((", i):
                stack.append(["arith", 0])
                width = 2
            if width:
                mark(i, i + width, _QUOTED)
                i += width
                continue
            if c == "#" and (i == 0 or (text[i - 1] in _SHELL_WORD_BREAKS
                                        and kinds[i - 1] == _CODE)):
                end = text.find("\n", i)
                end = n if end < 0 else end
                mark(i, end, _COMMENT)
                i = end
                continue
            if text.startswith("<<<", i):
                i += 3
                continue
            if text.startswith("<<", i):
                heredoc_ops.append(i)
                i = _read_heredoc_delimiter(text, i, pending, uncertain)
                continue
            if c == "\n" and pending:
                i = _read_heredoc_bodies(text, i + 1, pending, kinds, uncertain)
                pending.clear()
                continue
            i += 1
            continue

        # Inside a quoted or substituted span: nothing here is code, and
        # nothing inside single quotes or `$'...'` expands.
        kinds[i] = _LITERAL if ctx in ("sq", "ansi") else _QUOTED
        if ctx == "sq":
            if c == "'":
                stack.pop()
            i += 1
            continue
        if c == "\\":
            mark(i, i + 2, _LITERAL if ctx == "ansi" else _QUOTED)
            i += 2
            continue
        if ctx == "ansi":
            if c == "'":
                stack.pop()
            i += 1
            continue
        if ctx == "arith":
            if c == "(":
                stack[-1][1] += 1
            elif c == ")" and stack[-1][1]:
                stack[-1][1] -= 1
            elif c == ")":
                if text.startswith("))", i):
                    mark(i, i + 2, _QUOTED)
                    stack.pop()
                    i += 2
                    continue
                uncertain.append("unbalanced arithmetic span")
                stack.pop()
            i += 1
            continue
        if ctx == "param" and c == "{":
            stack[-1][1] += 1
            i += 1
            continue
        if ctx == "param" and c == "}" and stack[-1][1]:
            stack[-1][1] -= 1
            i += 1
            continue
        if (ctx == "dq" and c == '"') or (ctx == "param" and c == "}") \
                or (ctx == "bt" and c == "`"):
            stack.pop()
            i += 1
            continue
        if ctx == "cmd" and c == ")" and stack[-1][1] == 0:
            stack.pop()
            i += 1
            continue
        if ctx in ("cmd", "bt"):
            if c == "#" and text[i - 1] in _SHELL_WORD_BREAKS:
                end = text.find("\n", i)
                end = n if end < 0 else end
                mark(i, end, _QUOTED)
                i = end
                continue
            if _word_at(text, i, "case"):
                uncertain.append("`case` inside a command substitution")
            if text.startswith("<<", i) and not text.startswith("<<<", i) \
                    and text[i - 1] != "<":
                uncertain.append("here-document inside a command substitution")
        if ctx == "cmd" and c == "(":
            stack[-1][1] += 1
            i += 1
            continue
        if ctx == "cmd" and c == ")":
            stack[-1][1] -= 1
            i += 1
            continue
        if ctx in ("cmd", "param", "bt") and c in "'\"":
            if c == '"':
                stack.append(["dq", 0])
            else:
                kinds[i] = _LITERAL
                stack.append(["ansi" if text[i - 1] == "$" else "sq", 0])
            i += 1
            continue
        width = open_span(i) if ctx != "bt" or c != "`" else 0
        if width:
            mark(i, i + width, _QUOTED)
            i += width
            continue
        i += 1
    if stack:
        uncertain.append(f"unterminated {stack[-1][0]} span")
    if pending:
        uncertain.append("here-document without a body")
    return kinds, heredoc_ops, uncertain


def _is_code_word(text: str, kinds: bytearray, i: int, word: str) -> bool:
    """Whether `word` stands at `i` as a whole shell word in code."""
    j = i + len(word)
    if not text.startswith(word, i):
        return False
    if any(kinds[k] != _CODE for k in range(i, j)):
        return False
    if i > 0 and not (text[i - 1] in _SHELL_WORD_BREAKS and kinds[i - 1] == _CODE):
        return False
    return j >= len(text) or text[j] in _SHELL_WORD_BREAKS


def _at_command_start(text: str, kinds: bytearray, i: int) -> bool:
    """Whether a reserved word at `i` starts a command."""
    j = i - 1
    while j >= 0 and text[j] in " \t" and kinds[j] == _CODE:
        j -= 1
    if j < 0:
        return True
    if kinds[j] != _CODE:
        return False
    if text[j] in "\n;&|(){":
        return True
    k = j
    while k >= 0 and kinds[k] == _CODE and text[k] not in _SHELL_WORD_BREAKS:
        k -= 1
    if k >= 0 and kinds[k] != _CODE:
        return False
    return text[k + 1:j + 1] in _COMMAND_LEAD_WORDS


def _nested_case_header_end(text: str, kinds: bytearray, i: int) -> int:
    """Return the index after `in` of the `case WORD in` at `i`, or raise."""
    n = len(text)
    if not _at_command_start(text, kinds, i):
        raise _Unsplittable("`case` outside a command start")
    j = i + 4
    while j < n and text[j] in " \t" and kinds[j] == _CODE:
        j += 1
    k = j
    while k < n and (kinds[k] in (_QUOTED, _LITERAL)
                     or (kinds[k] == _CODE and text[k] not in _SHELL_WORD_BREAKS)):
        k += 1
    if k == j:
        raise _Unsplittable("`case` without a word")
    while k < n and text[k] in " \t\n" and kinds[k] == _CODE:
        k += 1
    if not _is_code_word(text, kinds, k, "in"):
        raise _Unsplittable("`case` without `in`")
    return k + 2


def _find_matching_esac(text: str, kinds: bytearray, body_start: int) -> int:
    """Return the index of the `esac` that closes the block whose body starts
    at `body_start`, or raise `_Unsplittable`."""
    depth = 1
    i = body_start
    n = len(text)
    while i < n:
        if kinds[i] != _CODE:
            i += 1
        elif _is_code_word(text, kinds, i, "case"):
            i = _nested_case_header_end(text, kinds, i)
            depth += 1
        elif _is_code_word(text, kinds, i, "esac"):
            if not _at_command_start(text, kinds, i):
                raise _Unsplittable("`esac` outside a command start")
            depth -= 1
            if depth == 0:
                return i
            i += 4
        else:
            i += 1
    raise _Unsplittable("`case` without its `esac`")


def _check_block(text: str, lex, body_start: int, esac_at: int) -> None:
    """Raise `_Unsplittable` for any block shape the arm scanner does not model."""
    kinds, heredoc_ops, _ = lex
    if any(body_start <= p < esac_at for p in heredoc_ops) \
            or _HEREDOC in kinds[body_start:esac_at] \
            or _HEREDOC_LITERAL in kinds[body_start:esac_at]:
        raise _Unsplittable("here-document inside a case block")
    # A comment is exempt: bash skips a `#` comment that starts a word in
    # code, and the lexer marks exactly that span, so a `case` or `;;` in
    # comment prose is never syntax. A token inside a quote, an expansion, a
    # substitution, or an escape still sends the block to the whole file.
    for m in _BLOCK_TOKEN_RE.finditer(text, body_start, esac_at):
        if any(kinds[k] not in (_CODE, _COMMENT) for k in range(m.start(), m.end())):
            raise _Unsplittable(f"`{m.group()}` outside code in a case block")
    at = text.find(";&", body_start, esac_at)
    while at >= 0:
        if kinds[at] == _CODE and kinds[at + 1] == _CODE:
            raise _Unsplittable("`;&` or `;;&` terminator")
        at = text.find(";&", at + 1, esac_at)


def _case_blocks(text: str, lex) -> list[dict]:
    """Return every top-level `case "$eval_id"` block, or raise."""
    kinds, _, uncertain = lex
    if uncertain:
        raise _Unsplittable(uncertain[0])
    blocks: list[dict] = []
    for header in _CASE_HEADER_RE.finditer(text):
        start = header.start()
        if any(b["start"] <= start < b["end"] for b in blocks):
            continue
        if not (_is_code_word(text, kinds, start, "case")
                and _at_command_start(text, kinds, start)
                and _is_code_word(text, kinds, header.end() - 2, "in")):
            continue
        body_start = header.end()
        esac_at = _find_matching_esac(text, kinds, body_start)
        _check_block(text, lex, body_start, esac_at)
        blocks.append({
            "start": start,
            "body_start": body_start,
            "esac_at": esac_at,
            "end": esac_at + len("esac"),
        })
    return blocks


def _parse_top_level_case_blocks(text: str, lex=None):
    """Return the top-level `case "$eval_id"` blocks as dicts, or None when
    the grader holds a shape the arm-split does not model."""
    try:
        return _case_blocks(text, lex if lex is not None else _lex_shell(text))
    except _Unsplittable:
        return None


def _arms_in(text: str, kinds: bytearray, lo: int, hi: int):
    """Return [(pattern, start, end), ...] for the arms of the block body
    `text[lo:hi]`, with indices into `text`, or raise `_Unsplittable`.

    Between arms the scanner accepts only blanks, newlines, and comments. A
    pattern is an optional leading `(` and the text up to the first `)` in
    code, on one line, with no other parenthesis. An arm runs from its
    pattern through the `;;` that ends it at nesting depth 0; a nested
    `case WORD in` opens a level and its `esac` closes it. Only `;;` ends an
    arm: a `;&` or `;;&` terminator, or a last arm without `;;`, raises, so
    the whole file joins every key.
    """
    arms = []
    i = lo
    while i < hi:
        if kinds[i] == _COMMENT or (kinds[i] == _CODE and text[i] in " \t\n"):
            i += 1
            continue
        pat_start = i
        if text[i] == "(" and kinds[i] == _CODE:
            i += 1
        while i < hi and not (text[i] == ")" and kinds[i] == _CODE):
            if text[i] == "\n" or kinds[i] in (_COMMENT, _HEREDOC, _HEREDOC_LITERAL) \
                    or (kinds[i] == _CODE and text[i] in "(;&<>`"):
                raise _Unsplittable("case pattern this splitter does not model")
            i += 1
        if i >= hi:
            raise _Unsplittable("case pattern without `)`")
        pattern = text[pat_start:i]
        i += 1
        depth = 0
        while True:
            if i >= hi:
                raise _Unsplittable("case arm without `;;`")
            if kinds[i] != _CODE:
                i += 1
            elif _is_code_word(text, kinds, i, "case"):
                i = _nested_case_header_end(text, kinds, i)
                depth += 1
            elif _is_code_word(text, kinds, i, "esac"):
                if depth == 0 or not _at_command_start(text, kinds, i):
                    raise _Unsplittable("stray `esac` in a case arm")
                depth -= 1
                i += 4
            elif text.startswith(";;", i) and kinds[i + 1] == _CODE:
                i += 2
                if depth == 0:
                    arms.append((pattern, pat_start, i))
                    break
            else:
                i += 1
    return arms


def _arm_spans(body: str, lex=None):
    """Return [(pattern, start, end), ...] for each arm in a case body, with
    `start`/`end` indexing the arm in `body` from its pattern through its
    `;;`, or None when the body holds a shape the arm-split does not model
    (see `_arms_in`)."""
    lex = lex if lex is not None else _lex_shell(body)
    if lex[2]:
        return None
    try:
        return _arms_in(body, lex[0], 0, len(body))
    except _Unsplittable:
        return None


# --- bash arbitrates every split ---------------------------------------------
#
# The lexer above only proposes a split. `_split_plan` uses a proposal only
# when the bash on PATH, the bash the runners run grade.sh with, confirms it
# in one subprocess per grader content; any disagreement, any bash failure,
# or no bash at all means the whole grade.sh joins every key. bash confirms
# four things:
#
# 1. Syntax: `bash -n` accepts the raw grader.
# 2. Top level: in bash's normalized print of the grader (`declare -f` of a
#    wrapper function), every `case "$eval_id"` statement is a top-level
#    command, outside any function, loop, subshell, brace group, or other
#    compound command, there are exactly as many as the lexer proposed, and
#    each proposed block's own print matches the grader's print at that
#    statement.
# 3. Arm boundaries: each proposed arm, wrapped alone in the block's
#    `case` header, prints exactly one clause with the proposed pattern, and
#    the block's print equals its header, then those clauses in order, then
#    `esac`.
# 4. Id binding: `eval_id` is bound once, at top level before the first
#    block, from `$1`; nothing else names it except a `$eval_id` or
#    `${eval_id}` read; no `nocasematch`; no `eval` command; no `$0`; no
#    command names grade.sh; `BASH_SOURCE` only inside `dirname`.
# 5. Positionals: no `shift` or positional `set` can run before the binding,
#    outside a function body, except inside a branch that only a `$1`
#    beginning with "-" takes (see `_DASH_TEST`).
# 6. Sourced files: every `source` or `.` resolves statically against the
#    grader's own `HERE`-style directory, and each resolved file passes
#    `_sourced_file_ok` on its current bytes.
# 7. Constructs: `_construct_hazard` finds nothing in the grader's print or
#    any sourced file that reads through quoting, constructed names,
#    aliases, POSIX mode, or re-entry. Command words in checks 4 to 7 are
#    compared after quote removal and through `builtin` and `command`.
#
# These checks assume a grader written in good faith, as the module
# docstring states; they fail closed on every hostile construct they
# recognise, and that contract covers the rest.
#
# Why equal prints mean bash's arms are the proposed arms. bash prints a case
# statement as its header, then per clause a pattern line and a terminator
# line at the clause indent with the body indented below them, then `esac`.
# Each wrapped arm prints exactly one clause, so the concatenation holds one
# clause per proposed arm, each with its proposed pattern. Scan the arms
# left to right to the first one whose bash boundary differs from the
# proposal; up to it, bash reads the block and the wrapped arm in the same
# lexical state. If bash ends that clause early (a real `;;` inside the
# proposed arm), the arm wrapped alone ends there too and prints two
# clauses or fails to parse, which fails the check. If bash ends it late
# (the proposed `;;` is a comment or string to bash), bash folds the next
# proposed arm's pattern into the clause body, and since every later arm
# also prints one clause alone, the block ends with fewer clauses than
# proposed arms, so the prints differ. Equal prints therefore leave no
# first difference: bash's clauses are the proposed arms, in order, with the
# proposed patterns. Text bash prints verbatim (a multi-line string or
# substitution) can only add lines at the clause indent, which breaks the
# one-clause count and fails closed.

_WRAP_HEAD = "__o () {\n__s () {\n"
_WRAP_TAIL = "\n}\n}\n"
_EVAL_ID_CASE_LINE_RE = re.compile(
    r'^( *)case (?:"\$eval_id"|\$eval_id|"\$\{eval_id\}"|\$\{eval_id\}) in ?$'
)
# `eval_id="${1:?...}"` and the plainer `$1` / `${1}` forms, quoted or not.
_BINDING_LINE_RE = re.compile(
    r'^ {8}eval_id=("?)\$(?:1|\{1(?::?\?[^}]*)?\})\1;?$'
)
_ORACLE_SCRIPT = r'''
d=$1; m=$2
"$BASH" -n "$d/g" 2>/dev/null || { printf '%s SYNTAX\n' "$m"; exit 0; }
for f in "$d"/w_*; do
  printf '%s BEGIN %s\n' "$m" "${f##*/}"
  ( source "$f" 2>/dev/null && declare -f __o ) || printf '%s FAIL\n' "$m"
done
printf '%s DONE\n' "$m"
'''


def _bash_prints(raw: bytes, wrappers: dict[str, str], bash: str):
    """Return {name: printed lines or None} for each wrapper, or None when
    the grader fails `bash -n` or bash cannot run. Defining a wrapper runs
    nothing: each source only defines `__o`, and the grader passed `bash -n`
    first."""
    marker = "@@" + secrets.token_hex(8)
    with tempfile.TemporaryDirectory(prefix="eval_cache_oracle_") as tmp:
        root = pathlib.Path(tmp)
        (root / "g").write_bytes(raw)
        for name, source in wrappers.items():
            (root / f"w_{name}").write_text(source, encoding="utf-8")
        try:
            run = subprocess.run(
                [bash, "-c", _ORACLE_SCRIPT, "oracle", str(root), marker],
                capture_output=True, timeout=120,
            )
        except (OSError, subprocess.SubprocessError):
            return None
    out = run.stdout.decode("utf-8", "surrogateescape")
    if run.returncode != 0 or f"{marker} DONE" not in out \
            or f"{marker} SYNTAX" in out:
        return None
    prints: dict[str, list[str] | None] = {}
    current = None
    for line in out.split("\n"):
        if line.startswith(marker + " BEGIN "):
            current = line[len(marker) + 7:].removeprefix("w_")
            prints[current] = []
        elif line == f"{marker} FAIL" and current is not None:
            prints[current] = None
            current = None
        elif line == f"{marker} DONE":
            break
        elif current is not None:
            prints[current].append(line)
    for name in wrappers:
        if name not in prints:
            return None
    return prints


def _wrapper_body(lines):
    """The lines inside `__s` of a wrapper print, or None if the print is
    not exactly the one nested definition."""
    if lines is None or len(lines) < 6:
        return None
    if not (lines[0].startswith("__o ()") and lines[1].strip() == "{"
            and lines[2].strip() == "function __s ()" and lines[3].strip() == "{"
            and lines[-2] == "    }" and lines[-1] == "}"):
        return None
    return lines[4:-2]


def _id_binding_line(print_text: str, first_case_line: int) -> int | None:
    """Return the print line that binds `eval_id` when the grader's
    normalized print satisfies the id-binding preconditions the split relies
    on (see the section comment above), else None."""
    kinds = _lex_shell(print_text)[0]
    lines = print_text.split("\n")
    bindings = []
    for m in re.finditer(r"(?<![A-Za-z0-9_])eval_id(?![A-Za-z0-9_])", print_text):
        p = m.start()
        if print_text[p - 1:p] == "$":
            continue
        if print_text[p - 2:p] == "${" and print_text[m.end():m.end() + 1] == "}":
            continue
        line_no = print_text.count("\n", 0, p)
        if p == print_text.rfind("\n", 0, p) + 9 \
                and _BINDING_LINE_RE.match(lines[line_no]):
            bindings.append(line_no)
            continue
        return None
    if len(bindings) != 1 or bindings[0] >= first_case_line:
        return None
    if "nocasematch" in print_text or "grade.sh" in print_text:
        return None
    for m in re.finditer(r"\$(?:0|\{0)(?![0-9])", print_text):
        if kinds[m.start()] not in (_LITERAL, _HEREDOC_LITERAL):
            return None
    for m in re.finditer(r"(?<![A-Za-z0-9_])eval(?![A-Za-z0-9_])", print_text):
        if kinds[m.start()] == _CODE and _word_at(print_text, m.start(), "eval"):
            return None
    sources = [m.start() for m in re.finditer("BASH_SOURCE", print_text)
               if kinds[m.start()] not in (_LITERAL, _HEREDOC_LITERAL)]
    allowed = re.findall(r'dirname "\$\{BASH_SOURCE(?:\[0\])?\}"', print_text)
    return bindings[0] if len(sources) == len(allowed) else None


# A test whose branch runs only when `$1` begins with "-": `[[ "$1" == "-..." ]]`
# or `[ "$1" = "-..." ]`, with `$1` written as `$1`, `${1}`, or `${1:-...}`,
# quoted or not. On 2026-10-15 every id in the tree's evals.json files (229
# ids across 14 files) began with a letter or digit, never "-", and
# test_eval_cache.py keeps that true, so the runner's eval id never takes
# such a branch and a positional change inside it leaves `$1` holding the id.
_DASH_TEST = (
    r'(?:\[\[ ("?)\$(?:1|\{1(?::-[^}]*)?\})\1 ==? '
    r'(?:"-[^"]*"|\'-[^\']*\'|-[^\s\]()|]*) \]\]'
    r'|\[ ("?)\$(?:1|\{1(?::-[^}]*)?\})\2 = '
    r'(?:"-[^"]*"|\'-[^\']*\'|-[^\s\]()|]*) \])'
)
_DASH_BRANCH_RE = re.compile(r"^ *(?:if|elif) " + _DASH_TEST + r"; then$")
_DASH_AND_RE = re.compile(r"^ *" + _DASH_TEST + r" && ")
_SET_OPTION_RE = re.compile(r"[-+][A-Za-z]+")
_FUNCTION_LINE_RE = re.compile(r"^( *)(?:function )?([^\s()]+) \(\) ?$")
# The grader's own `HERE`-style directory: `NAME="$(cd "$(dirname
# "${BASH_SOURCE[0]}")" && pwd)"`, as bash prints it at top level.
_GRADER_DIR_LINE_RE = re.compile(
    r'^ {8}([A-Za-z_][A-Za-z0-9_]*)="\$\(cd "\$\(dirname '
    r'"\$\{BASH_SOURCE(?:\[0\])?\}"\)" && pwd\)";?$'
)
_SOURCE_PATH_RE = re.compile(
    r'^("?)\$(?:([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\})'
    r'(/[^\s"\'`$*?\[\\]+)\1$'
)
# Commands a sourced file must not replace with a function, because the
# split's checks read them as the builtins they are.
_PROTECTED_COMMANDS = {
    "bash", "sh", "source", ".", "eval", "exec", "shift", "set", "shopt",
    "local", "declare", "typeset", "export", "readonly", "unset", "read",
    "mapfile", "readarray", "printf", "builtin", "command", "cd", "dirname",
    "pwd",
}


# Command words are compared after quote removal, so `\set`, `'set'`,
# `"source"`, and `builtin source` read as `set` and `source`.
_ASSIGNMENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?\+?=")
_PLAIN_NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]$`'\"\\]*\])?")
_RESERVED_LEADS = {"then", "do", "else", "elif", "if", "while", "until", "!",
                   "{", "}", "time"}
_DECLARATION_COMMANDS = {"declare", "typeset", "local", "readonly", "export", "unset"}
_NAMEREF_COMMANDS = {"declare", "typeset", "local"}
_OPTION_VARIABLES = {"POSIXLY_CORRECT", "BASHOPTS", "SHELLOPTS"}
# Text that changes how bash parses or matches arms (aliases, POSIX mode,
# case-insensitive matching) or names the running script without `$0`.
_HAZARD_TEXT_RE = re.compile(
    r"(?<![A-Za-z0-9_])(?:alias|expand_aliases|posix|POSIXLY_CORRECT|nocasematch"
    r"|BASH_ARGV\w*|BASH_EXECUTION_STRING)(?![A-Za-z0-9_])"
)
_HAZARD_VALUES = ("expand_aliases", "nocasematch", "POSIXLY_CORRECT", "posix",
                  "grade.sh", "BASH_ARGV", "BASH_EXECUTION_STRING")


def _unquote(raw: str) -> str:
    """Shell quote removal of one word, leaving expansions as written."""
    out: list[str] = []
    i, n = 0, len(raw)
    while i < n:
        c = raw[i]
        if c == "\\" and i + 1 < n:
            if raw[i + 1] != "\n":
                out.append(raw[i + 1])
            i += 2
        elif raw.startswith("$'", i):
            j = i + 2
            while j < n and raw[j] != "'":
                j += 2 if raw[j] == "\\" else 1
            out.append(raw[i + 2:j].replace("\\", ""))
            i = j + 1
        elif c == "'":
            j = raw.find("'", i + 1)
            j = n if j < 0 else j
            out.append(raw[i + 1:j])
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n and raw[j] != '"':
                if raw[j] == "\\" and j + 1 < n and raw[j + 1] in '$`"\\\n':
                    if raw[j + 1] != "\n":
                        out.append(raw[j + 1])
                    j += 2
                else:
                    out.append(raw[j])
                    j += 1
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _simple_commands(text: str, kinds: bytearray) -> list[list[tuple]]:
    """Split code into simple commands, each a list of `(start, end, raw,
    value)` words with `value` quote-removed. Separators are newlines and
    `;`, `&`, `|`, `(`, `)` in code; a redirection's target word is dropped."""
    commands: list[list[tuple]] = []
    current: list[tuple] = []
    skip_next = False
    i, n = 0, len(text)
    while i < n:
        k, c = kinds[i], text[i]
        if k in (_COMMENT, _HEREDOC, _HEREDOC_LITERAL) or (k == _CODE and c in " \t"):
            i += 1
            continue
        if k == _CODE and c in ";&|()\n":
            if current:
                commands.append(current)
            current, skip_next = [], False
            i += 1
            continue
        if k == _CODE and c in "<>":
            while i < n and kinds[i] == _CODE and text[i] in "<>&-":
                i += 1
            skip_next = True
            continue
        j = i
        while j < n and (kinds[j] in (_QUOTED, _LITERAL)
                         or (kinds[j] == _CODE and text[j] not in _SHELL_WORD_BREAKS)):
            j += 1
        if j == i:
            i += 1
            continue
        if skip_next:
            skip_next = False
        else:
            raw = text[i:j]
            current.append((i, j, raw, _unquote(raw)))
        i = j
    if current:
        commands.append(current)
    return commands


def _command_index(words: list[tuple]) -> int | None:
    """Index of the word bash runs as the command: past reserved words and
    assignments, and through `builtin X` and `command X` to `X`."""
    i = 0
    while i < len(words):
        raw, value = words[i][2], words[i][3]
        if value in _RESERVED_LEADS or _ASSIGNMENT_RE.match(raw):
            i += 1
        elif value in ("builtin", "command"):
            i += 1
            while i < len(words) and words[i][3].startswith("-"):
                i += 1
        else:
            return i
    return None


def _plain_name(text: str, kinds: bytearray, word: tuple, until_equals: bool) -> bool:
    """Whether a declaration or read target names a variable literally: no
    quote, backslash, expansion, or other non-code character in the name."""
    start, end, raw = word[0], word[1], word[2]
    stop = end
    if until_equals:
        for p in range(start, end):
            if text[p] == "=" and kinds[p] == _CODE:
                stop = p
                break
    if any(kinds[p] != _CODE for p in range(start, stop)):
        return False
    return bool(_PLAIN_NAME_RE.fullmatch(text[start:stop].rstrip("+")))


def _option_targets(words: list[tuple], arg_letters: str, target_letter: str):
    """Split option words from operands; return (targets named by
    `-target_letter`, operand words)."""
    targets, operands = [], []
    i = 0
    while i < len(words):
        value = words[i][3]
        if value == "--":
            operands.extend(words[i + 1:])
            break
        if value.startswith("-") and len(value) > 1 and not operands:
            for k, letter in enumerate(value[1:]):
                if letter in arg_letters:
                    if k + 2 < len(value):
                        if letter == target_letter:
                            targets.append(None)
                    elif i + 1 < len(words):
                        i += 1
                        if letter == target_letter:
                            targets.append(words[i])
                    break
        else:
            operands.append(words[i])
        i += 1
    return targets, operands


def _positional_changes(text: str, kinds: bytearray) -> list[int]:
    """Indices of `shift`, and of `set` with operands, run as commands."""
    hits = []
    for words in _simple_commands(text, kinds):
        ci = _command_index(words)
        if ci is None:
            continue
        name, args = words[ci][3], words[ci + 1:]
        if name == "shift":
            hits.append(words[ci][0])
        elif name == "set":
            # `set -euo pipefail` or `set +x` changes options only; any
            # operand, `-`, or `--` replaces the positional parameters.
            option_name_next = False
            for word in args:
                if option_name_next:
                    option_name_next = False
                    continue
                if not _SET_OPTION_RE.fullmatch(word[3]):
                    hits.append(words[ci][0])
                    break
                option_name_next = word[3].endswith("o")
    return hits


def _construct_hazard(text: str, kinds: bytearray, dir_vars) -> str | None:
    """Name the first construct in `text` the split cannot read through,
    or return None. Applied to the grader's print and to each sourced file:
    aliases, POSIX mode, `nocasematch`, `shopt`, `eval`, `BASH_ARGV`,
    `BASH_EXECUTION_STRING`, a `grade.sh` path, a nameref, a declaration
    or read whose target name is quoted, escaped, or expanded, and a glob or
    brace in a word built on the grader's directory variable."""
    for m in _HAZARD_TEXT_RE.finditer(text):
        if kinds[m.start()] not in (_LITERAL, _HEREDOC_LITERAL, _COMMENT):
            return m.group()
    dir_ref = (re.compile(r"\$\{?(?:%s)(?![A-Za-z0-9_])"
                          % "|".join(map(re.escape, sorted(dir_vars))))
               if dir_vars else None)
    for words in _simple_commands(text, kinds):
        for start, end, raw, value in words:
            if any(token in value for token in _HAZARD_VALUES):
                return value
            assignment = _ASSIGNMENT_RE.match(raw)
            if assignment and raw[:assignment.end()].rstrip("+=").split("[")[0] \
                    in _OPTION_VARIABLES:
                return raw
            if dir_ref and dir_ref.search(raw) and any(
                    kinds[p] == _CODE and text[p] in "*?[{" for p in range(start, end)):
                return f"glob on the grader directory: {raw}"
        ci = _command_index(words)
        if ci is None:
            continue
        name, args = words[ci][3], words[ci + 1:]
        if name in ("eval", "alias", "unalias", "shopt"):
            return name
        if name == "set" and any("$" in a[2] for a in args):
            return "set with an expanded option"
        if name in _DECLARATION_COMMANDS:
            for a in args:
                if a[3][:1] in "-+" and len(a[3]) > 1:
                    if name in _NAMEREF_COMMANDS and "n" in a[3][1:]:
                        return "nameref"
                    continue
                if not _plain_name(text, kinds, a, until_equals=True) \
                        or _unquote(a[2]).split("=")[0] in _OPTION_VARIABLES:
                    return f"{name} {a[2]}"
        targets: list = []
        if name == "printf":
            targets = _option_targets(args, "v", "v")[0]
        elif name == "read":
            named, operands = _option_targets(args, "adinNptu", "a")
            targets = named + operands
        elif name in ("mapfile", "readarray"):
            named, operands = _option_targets(args, "dnOsuCc", "")
            targets = operands[:1]
        for target in targets:
            if target is None or not _plain_name(text, kinds, target, until_equals=False):
                return f"{name} into a constructed name"
    return None


def _function_body_lines(print_text: str, kinds: bytearray) -> set[int]:
    """Indices of print lines inside a function definition's body. A head
    counts only when its name and `{` are code in the print's lex, and the
    body closes at the code `}` at the head's indent."""
    lines = print_text.split("\n")
    offsets = [0]
    for line in lines[:-1]:
        offsets.append(offsets[-1] + len(line) + 1)
    inside: set[int] = set()
    for i, line in enumerate(lines):
        m = _FUNCTION_LINE_RE.match(line)
        if not m or i + 1 >= len(lines):
            continue
        indent = m.group(1)
        if kinds[offsets[i] + len(indent)] != _CODE \
                or lines[i + 1].rstrip() != indent + "{" \
                or kinds[offsets[i + 1] + len(indent)] != _CODE:
            continue
        body: set[int] = set()
        for j in range(i + 2, len(lines)):
            if lines[j].startswith(indent + "}") \
                    and kinds[offsets[j] + len(indent)] == _CODE:
                inside |= body
                break
            body.add(j)
    return inside


def _positionals_kept_until(print_text: str, binding_line: int) -> bool:
    """Whether `$1` still holds the runner's eval id at the binding: no
    positional change can run before it, except inside a `-`-literal guard."""
    kinds = _lex_shell(print_text)[0]
    lines = print_text.split("\n")
    in_function = _function_body_lines(print_text, kinds)
    for i in _positional_changes(print_text, kinds):
        line_no = print_text.count("\n", 0, i)
        if line_no >= binding_line or line_no in in_function:
            continue
        line = lines[line_no]
        guard = _DASH_AND_RE.match(line)
        if guard and print_text.rfind("\n", 0, i) + 1 + guard.end() == i:
            continue
        indent = len(line) - len(line.lstrip(" "))
        header = next((lines[j] for j in range(line_no - 1, -1, -1)
                       if len(lines[j]) - len(lines[j].lstrip(" ")) == indent - 4
                       and lines[j].strip()), "")
        if not _DASH_BRANCH_RE.match(header):
            return False
    return True


def _grader_functions(print_text: str) -> frozenset:
    """Names of the functions the grader defines."""
    return frozenset(m.group(2) for line in print_text.split("\n")
                     if (m := _FUNCTION_LINE_RE.match(line)))


def _grader_dir_vars(print_text: str) -> dict:
    """Map each `HERE`-style directory variable to the print lines binding it."""
    found: dict[str, list[int]] = {}
    for i, line in enumerate(print_text.split("\n")):
        m = _GRADER_DIR_LINE_RE.match(line)
        if m:
            found.setdefault(m.group(1), []).append(i)
    return found


def _sourced_paths(print_text: str, grader_dir) -> tuple | None:
    """Resolve every file the grader sources against its own directory, or
    return None when any `source` or `.` command, however it is spelled,
    cannot be resolved that way."""
    kinds = _lex_shell(print_text)[0]
    dir_vars = _grader_dir_vars(print_text)
    paths = []
    for words in _simple_commands(print_text, kinds):
        ci = _command_index(words)
        if ci is None or words[ci][3] not in ("source", "."):
            continue
        args = words[ci + 1:]
        target = _SOURCE_PATH_RE.match(args[0][2]) if len(args) == 1 else None
        if grader_dir is None or not target:
            return None
        line_no = print_text.count("\n", 0, words[ci][0])
        name = target.group(2) or target.group(3)
        bound = dir_vars.get(name, [])
        # The directory variable is bound once, before this source, and
        # every other mention of it is a `$NAME` or `${NAME}` read.
        rebinds = [
            p for p in (m.start() for m in re.finditer(
                r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])", print_text))
            if not (print_text[p - 1:p] == "$"
                    or (print_text[p - 2:p] == "${"
                        and print_text[p + len(name):p + len(name) + 1] == "}"))
        ]
        if len(bound) != 1 or bound[0] >= line_no or len(rebinds) != 1:
            return None
        paths.append(str((pathlib.Path(grader_dir) / target.group(4).lstrip("/")).resolve()))
    return tuple(paths)


@functools.lru_cache(maxsize=256)
def _sourced_file_ok(raw: bytes, grader_functions: frozenset, dir_vars: frozenset) -> bool:
    """Whether a file the grader sources is provably free of what could
    change the eval id or re-enter the grader: no `eval_id` or `shopt`
    anywhere; no `$0` outside single quotes or comments; no construct
    `_construct_hazard` names; no nested `source` or `.`, `shift`, or
    positional `set`, however spelled; and no function that replaces one the
    grader defines or a protected command."""
    text = _decode_for_parsing(raw)
    if text is None or any(w in text for w in ("eval_id", "shopt")):
        return False
    kinds, _, uncertain = _lex_shell(text)
    if uncertain or _positional_changes(text, kinds) \
            or _construct_hazard(text, kinds, dir_vars) is not None:
        return False
    for m in re.finditer(r"\$(?:0|\{0)(?![0-9])", text):
        if kinds[m.start()] not in (_LITERAL, _HEREDOC_LITERAL, _COMMENT):
            return False
    for words in _simple_commands(text, kinds):
        ci = _command_index(words)
        if ci is not None and words[ci][3] in ("source", ".", "eval"):
            return False
    for m in re.finditer(r"(?m)^[ \t]*(?:function[ \t]+)?([A-Za-z_][\w.-]*)[ \t]*\(\)"
                         r"|function[ \t]+([A-Za-z_][\w.-]*)", text):
        name = m.group(1) or m.group(2)
        if kinds[m.start(1) if m.group(1) else m.start(2)] == _CODE \
                and (name in grader_functions or name in _PROTECTED_COMMANDS):
            return False
    return True


@functools.lru_cache(maxsize=256)
def _split_plan(raw: bytes, bash: str | None, grader_dir: str | None):
    """Return `(plan, sourced, functions, dir_vars)` for one grader, or None when the
    whole grade.sh must join every key. `plan` is a tuple of
    `(start, body_start, esac_at, end, arms)` blocks with `arms` a tuple of
    `(pattern, start, end)`; `sourced` lists the resolved files the grader
    sources, which `grade_sh_contribution` checks by their current bytes;
    `functions` names the functions the grader defines; `dir_vars` names its
    `HERE`-style directory variables."""
    text = _decode_for_parsing(raw)
    if text is None or bash is None:
        return None
    try:
        lex = _lex_shell(text)
        blocks = _case_blocks(text, lex)
        if not blocks:
            return None
        plan = tuple(
            (b["start"], b["body_start"], b["esac_at"], b["end"],
             tuple(_arms_in(text, lex[0], b["body_start"], b["esac_at"])))
            for b in blocks
        )
    except _Unsplittable:
        return None
    wrappers = {"whole": _WRAP_HEAD + text + _WRAP_TAIL}
    for bi, (start, body_start, _, end, arms) in enumerate(plan):
        header = text[start:body_start]
        wrappers[f"b{bi}"] = _WRAP_HEAD + text[start:end] + _WRAP_TAIL
        for ai, (_, a_start, a_end) in enumerate(arms):
            wrappers[f"b{bi}_a{ai}"] = (
                _WRAP_HEAD + header + "\n" + text[a_start:a_end] + "\nesac" + _WRAP_TAIL
            )
    prints = _bash_prints(raw, wrappers, bash)
    if prints is None:
        return None
    whole = _wrapper_body(prints["whole"])
    if whole is None:
        return None
    case_lines = [i for i, line in enumerate(whole) if _EVAL_ID_CASE_LINE_RE.match(line)]
    top_level = [i for i in case_lines
                 if _EVAL_ID_CASE_LINE_RE.match(whole[i]).group(1) == " " * 8]
    if len(case_lines) != len(plan) or len(top_level) != len(plan):
        return None
    whole_text = "\n".join(whole)
    binding_line = _id_binding_line(whole_text, top_level[0])
    if binding_line is None or not _positionals_kept_until(whole_text, binding_line):
        return None
    dir_vars = frozenset(_grader_dir_vars(whole_text))
    if _construct_hazard(whole_text, _lex_shell(whole_text)[0], dir_vars) is not None:
        return None
    sourced = _sourced_paths(whole_text, grader_dir)
    if sourced is None:
        return None
    for bi, (_, _, _, _, arms) in enumerate(plan):
        block = _wrapper_body(prints[f"b{bi}"])
        if block is None or len(block) < 2 or block[-1].strip() != "esac":
            return None
        # The block is the grader's own top-level statement at this place.
        region = whole[top_level[bi]:top_level[bi] + len(block)]
        if len(region) != len(block) or region[:-1] != block[:-1] \
                or region[-1] not in (block[-1], block[-1] + ";"):
            return None
        clause_indent = " " * (len(block[0]) - len(block[0].lstrip()) + 4)
        clauses: list[str] = []
        for ai, (pattern, _, _) in enumerate(arms):
            arm = _wrapper_body(prints[f"b{bi}_a{ai}"])
            if arm is None or len(arm) < 4 or arm[0] != block[0] \
                    or arm[-1] != block[-1]:
                return None
            lines = arm[1:-1]
            at_indent = [line for line in lines if line.startswith(clause_indent)
                         and not line.startswith(clause_indent + " ")]
            if at_indent != [lines[0], lines[-1]] or lines[-1].strip() != ";;":
                return None
            printed = lines[0].strip()
            proposed = pattern.strip()
            proposed = proposed[1:] if proposed.startswith("(") else proposed
            if not printed.endswith(")") or \
                    printed[:-1].replace(" ", "") != re.sub(r"\s", "", proposed):
                return None
            clauses.extend(lines)
        if block != [block[0], *clauses, block[-1]]:
            return None
    return plan, sourced, _grader_functions(whole_text), dir_vars


def grade_sh_contribution(grade, eval_id: str, grader_dir=None) -> bytes:
    """Bytes of grade.sh that join this eval's key: the arm-split when bash
    confirms it (see `_split_plan`), else the whole file.

    `grade` is the grader's raw bytes, or its text; `grader_dir` is the
    directory it lives in, against which the files it sources resolve (a
    grader that sources a file with no `grader_dir` hashes whole). The
    contribution is the grader's bytes with every confirmed arm that cannot
    select `eval_id` left out, so an unconfirmed grader contributes exactly
    its raw bytes. The decision is memoized on the grader's bytes and, in
    `_sourced_file_ok`, on each sourced file's bytes, so a helper edit
    re-decides the split.
    """
    raw = grade if isinstance(grade, bytes) else grade.encode("utf-8", "surrogateescape")
    directory = None if grader_dir is None else str(pathlib.Path(grader_dir).resolve())
    decided = _split_plan(raw, shutil.which("bash"), directory)
    if decided is None:
        return raw
    plan, sourced, functions, dir_vars = decided
    for path in sourced:
        try:
            helper = pathlib.Path(path).read_bytes()
        except OSError:
            return raw
        if not _sourced_file_ok(helper, functions, dir_vars):
            return raw
    text = raw.decode("utf-8")
    parts: list[str] = []
    cursor = 0
    for _, body_start, _, end, arms in plan:
        parts.append(text[cursor:body_start])
        pos = body_start
        for pattern, start, arm_end in arms:
            parts.append(text[pos:start])
            if _arm_matches(pattern, eval_id):
                parts.append(text[start:arm_end])
            pos = arm_end
        parts.append(text[pos:end])
        cursor = end
    parts.append(text[cursor:])
    return "".join(parts).encode("utf-8")


def _harness_hash(harness_dir: pathlib.Path, eval_id: str) -> str:
    """Tree hash of harness_dir with the harness's own top-level grade.sh
    replaced by its arm-split contribution, read from raw bytes. A file named
    grade.sh deeper in the tree (a fixture, say) hashes whole, exactly as
    `_tree_hash` does."""
    digest = hashlib.sha256()
    for relname, path in _iter_files(harness_dir):
        digest.update(relname.encode())
        digest.update(b"\0")
        if relname == "grade.sh":
            content = grade_sh_contribution(path.read_bytes(), eval_id, harness_dir)
            digest.update(_sha(content).encode())
        else:
            digest.update(_sha(path.read_bytes()).encode())
        digest.update(b"\0")
    return digest.hexdigest()


def dependencies_for(evals_path, eval_id):
    """Load the optional `dependencies` field for `eval_id` from an evals.json.

    Returns the raw field value (possibly None) when the eval exists; returns
    None when the file or eval is missing. Callers pass the result straight to
    `content_key(..., dependencies=...)`, which treats absent and malformed
    values as the no-declaration baseline.
    """
    path = pathlib.Path(evals_path)
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    if isinstance(data, dict):
        evals = data.get("evals", [])
    elif isinstance(data, list):
        evals = data
    else:
        return None
    want = str(eval_id)
    for entry in evals:
        if isinstance(entry, dict) and str(entry.get("id")) == want:
            return entry.get("dependencies")
    return None


def content_key(
    *,
    source_roots,
    harness_dir,
    model: str,
    eval_id: str,
    prompt: str,
    dependencies=None,
) -> str:
    """Compute the cache key for one eval from everything that determines its
    verdict.

    `source_roots` is an iterable of skill/agent dirs (or files) the worker's
    behavior depends on; `harness_dir` is the `evals/` dir defining how the
    eval is staged and graded. Optional `dependencies` is a map from skill-root
    basename to `SKILL.md` stage element names that eval exercises under that
    root; when present and well-formed, those roots hash the listed stage
    bodies plus fail-closed non-stage material and other files, omitting
    undeclared top-level stage bodies. An absent or malformed declaration
    keeps today's whole-tree skill contribution. Harness contribution
    arm-splits `grade.sh` by `eval_id` only when bash's own parse confirms the
    split and the id-binding preconditions hold, and uses the whole
    `grade.sh` otherwise (see `_split_plan`); the split assumes the
    good-faith grader contract the module docstring states. The
    shared `VERDICT_HELPERS` join every key, because the deployment, read
    check, worker command, host `tasks/` guard, and repeated-link disposition
    reader that decide a verdict come from them.
    """
    deps = _normalize_dependencies(dependencies)
    digest = hashlib.sha256()
    # Label each source root by basename so moving content between roots, or
    # renaming a root, changes the key.
    for root in source_roots:
        root = pathlib.Path(root)
        digest.update(b"root:")
        digest.update(root.name.encode())
        digest.update(b"\0")
        if deps is not None and root.name in deps:
            digest.update(_declared_root_hash(root, deps[root.name]).encode())
        else:
            digest.update(_tree_hash(root).encode())
        digest.update(b"\0")
    digest.update(b"harness\0")
    digest.update(_harness_hash(pathlib.Path(harness_dir), eval_id).encode())
    digest.update(b"\0")
    for name in VERDICT_HELPERS:
        digest.update(b"helper:")
        digest.update(name.encode())
        digest.update(b"\0")
        digest.update(_tree_hash(_HELPER_DIR / name).encode())
        digest.update(b"\0")
    digest.update(("model=" + (model or "<cli-default>")).encode())
    digest.update(b"\0")
    digest.update(("eval=" + eval_id).encode())
    digest.update(b"\0")
    digest.update(("prompt=" + prompt).encode())
    digest.update(b"\0")
    return digest.hexdigest()


def _now_iso() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


class EvalCache:
    """Per-harness verdict cache stored as one small JSON file per eval id
    under `cache_dir` (default `<evals>/.eval_cache`). Each file maps a content
    key to the graded verdict recorded for it.
    """

    def __init__(self, cache_dir):
        self.dir = pathlib.Path(cache_dir)

    def _file(self, eval_id: str) -> pathlib.Path:
        safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in eval_id)
        return self.dir / f"{safe}.json"

    def _load(self, eval_id: str) -> dict:
        path = self._file(eval_id)
        if not path.exists():
            return {}
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            return {}
        return data if isinstance(data, dict) else {}

    def lookup(self, eval_id: str, key: str):
        """Return the stored verdict entry for (eval_id, key), or None."""
        return self._load(eval_id).get(key)

    def record(
        self,
        eval_id: str,
        key: str,
        *,
        passed: bool,
        model: str,
        duration_s: float,
        worker_rc: int,
        grading_output: str,
        response_excerpt: str,
    ) -> dict:
        """Store (and return) the verdict entry for (eval_id, key)."""
        entry = {
            "passed": bool(passed),
            "model": model,
            "duration_s": round(duration_s, 3),
            "worker_rc": worker_rc,
            "graded_at": _now_iso(),
            "grading_output": grading_output,
            "response_excerpt": response_excerpt[:RESPONSE_EXCERPT_CHARS],
        }
        data = self._load(eval_id)
        data[key] = entry
        if len(data) > _MAX_ENTRIES_PER_EVAL:
            keep = sorted(
                data.items(),
                key=lambda kv: kv[1].get("graded_at", ""),
                reverse=True,
            )[:_MAX_ENTRIES_PER_EVAL]
            data = dict(keep)
        self.dir.mkdir(parents=True, exist_ok=True)
        tmp = self._file(eval_id).with_suffix(".json.tmp")
        tmp.write_text(json.dumps(data, indent=2, sort_keys=True))
        tmp.replace(self._file(eval_id))
        return entry


def write_replay_artifacts(eval_dir, entry: dict) -> None:
    """On a cache hit, populate the per-eval run dir from the stored entry so a
    replayed run leaves the same file shape as a fresh one — with a clear banner
    that no worker ran this time.
    """
    eval_dir = pathlib.Path(eval_dir)
    eval_dir.mkdir(parents=True, exist_ok=True)
    (eval_dir / "cached.json").write_text(json.dumps(entry, indent=2, sort_keys=True))
    (eval_dir / "grading.txt").write_text(entry.get("grading_output", ""))
    banner = (
        "[CACHED REPLAY: no worker ran this time because the eval's inputs were\n"
        "unchanged since the grade below. What follows is an excerpt of the prior\n"
        "run's response; re-run with --force for a full fresh one.]\n\n"
    )
    (eval_dir / "response.txt").write_text(banner + entry.get("response_excerpt", ""))
    (eval_dir / "timing.json").write_text(json.dumps({
        "eval_id": eval_dir.name,
        "cached": True,
        "graded_at": entry.get("graded_at"),
        "model": entry.get("model"),
        "duration_s_original": entry.get("duration_s"),
    }, indent=2))
