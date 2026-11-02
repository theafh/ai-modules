#!/usr/bin/env python3
"""Deterministic grader for the natural_language behavioral evals.

connected_rewrite grades delivered.md: word count at or below the draft,
no three consecutive pronoun openings, the three-item series as a list or a
colon series, no em dash, canary and shadow share defined in their first-use
window, the delivered file present, and the draft untouched.
chat_brevity grades response.txt: the response is present, at most 120 words,
and has no heading line, and the grader exits non-zero when the delivery is
absent or empty.

Usage:
    python3 grade.py <eval_id> <sandbox_proj> <source_file> [--json]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

WORD_RE = re.compile(r"[^\W_]", re.UNICODE)
LIST_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\S")
HEADING_RE = re.compile(r"^#{1,6}\s+\S")
PRONOUNS = {"It", "This", "They", "Its"}
SERIES_ITEMS = ("intake", "review", "release")
EM_DASH = "\u2014"
CHAT_WORD_CAP = 120


def word_count(text: str) -> int:
    """Count tokens that carry at least one alphanumeric character."""

    return sum(1 for token in text.split() if WORD_RE.search(token))


def _is_kept_line(stripped: str) -> bool:
    """True for lines that stay separate: headings, lists, and table rows."""

    return bool(
        HEADING_RE.match(stripped)
        or LIST_RE.match(stripped)
        or stripped.startswith("|")
    )


def sentences(text: str) -> list[str]:
    """Split prose into sentences after joining each paragraph's wrapped lines.

    Headings, list items, and table rows stay as their own chunks. A hard wrap
    inside a prose paragraph does not split a sentence or a colon series.
    """

    chunks: list[str] = []
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        if not paragraph:
            return
        joined = " ".join(paragraph)
        parts = re.split(r"(?<=[.!?])\s+", joined)
        chunks.extend(part.strip() for part in parts if part.strip())
        paragraph.clear()

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            flush_paragraph()
            continue
        if _is_kept_line(stripped):
            flush_paragraph()
            chunks.append(stripped)
            continue
        paragraph.append(stripped)
    flush_paragraph()
    return chunks


def pronoun_run(text: str) -> int:
    """Longest run of sentences whose first word is It, This, They, or Its."""

    best = 0
    run = 0
    for sentence in sentences(text):
        match = re.match(r"^[\"'(\[]*([A-Za-z]+)", sentence)
        if match and match.group(1) in PRONOUNS:
            run += 1
            best = max(best, run)
        else:
            run = 0
    return best


def has_series(text: str) -> bool:
    """True when intake, review, and release form a list or a colon series."""

    bullets = [line.lower() for line in text.splitlines() if LIST_RE.match(line)]
    if bullets and all(any(item in bullet for bullet in bullets) for item in SERIES_ITEMS):
        return True
    for sentence in sentences(text):
        if ":" not in sentence:
            continue
        after = sentence.split(":", 1)[1].lower()
        if all(item in after for item in SERIES_ITEMS):
            return True
    return False


def has_heading(text: str) -> bool:
    return any(HEADING_RE.match(line) for line in text.splitlines())


def first_sentence_with(text: str, term: str) -> str:
    """Return the first sentence that contains term, or an empty string."""

    needle = term.lower()
    for sentence in sentences(text):
        if needle in sentence.lower():
            return sentence
    return ""


def term_defined_in_first_use(
    text: str, term: str, required_phrases: tuple[str, ...]
) -> bool:
    """True when every required phrase sits in the term's first-use sentence."""

    sentence = first_sentence_with(text, term)
    if not sentence:
        return False
    lower = sentence.lower()
    return all(phrase.lower() in lower for phrase in required_phrases)


def _has_canary_gloss(lower: str) -> bool:
    """True when a sentence carries the canary release gloss."""

    if "small share" in lower and (
        "first" in lower
        or "users" in lower
        or "reaches" in lower
        or "traffic" in lower
    ):
        return True
    # Paraphrase: reaches a share of users/traffic first.
    return (
        "share" in lower
        and ("reaches" in lower or "first" in lower)
        and ("users" in lower or "traffic" in lower or "first" in lower)
    )


def _has_shadow_gloss(lower: str) -> bool:
    """True when a sentence carries the shadow-share traffic gloss."""

    if (
        "portion of traffic" in lower
        and "new build" in lower
        and "old" in lower
    ):
        return True
    # Paraphrase: a share that sees the new build while the old still serves.
    return (
        "new build" in lower
        and "old" in lower
        and ("share" in lower or "traffic" in lower)
    )


def _is_naming_sentence(sentence: str, term: str) -> bool:
    """True when the sentence mainly names the term after a prior gloss."""

    lower = sentence.lower()
    needle = term.lower()
    if needle not in lower:
        return False
    return (
        f"is the {needle}" in lower
        or f"called the {needle}" in lower
        or f"called {needle}" in lower
        or "calls " in lower
        or "call that " in lower
        or "name" in lower
        or (lower.lstrip().startswith("that ") and needle in lower)
    )


def _gloss_in_first_use_window(
    text: str, term: str, gloss_ok
) -> bool:
    """True when the gloss sits in the first-use window.

    The window is the first-use sentence, the next sentence when it still
    names the term, or the previous sentence when the first-use sentence
    only names the term after a plain-words gloss.
    """

    chunks = sentences(text)
    needle = term.lower()
    for index, sentence in enumerate(chunks):
        if needle not in sentence.lower():
            continue
        if gloss_ok(sentence.lower()):
            return True
        if index + 1 < len(chunks):
            nxt = chunks[index + 1]
            if needle in nxt.lower() and gloss_ok(nxt.lower()):
                return True
        if (
            index > 0
            and _is_naming_sentence(sentence, term)
            and gloss_ok(chunks[index - 1].lower())
        ):
            return True
        return False
    return False


def canary_defined_at_first_use(text: str) -> bool:
    """True when canary's first-use window carries a gloss.

    Accepts the canary gloss itself, or an alias onto the shadow-share gloss.
    The gloss may sit in the first-use sentence or in the next sentence when
    that sentence still names the term.
    """

    return _gloss_in_first_use_window(
        text,
        "canary",
        lambda lower: _has_canary_gloss(lower) or _has_shadow_gloss(lower),
    )


def shadow_defined_at_first_use(text: str) -> bool:
    """True when shadow share's first-use window carries a gloss.

    When the text uses "shadow share", that name's own first use must
    carry the gloss. "canary share" is checked only when "shadow share"
    is absent.
    """

    def share_gloss(lower: str) -> bool:
        return _has_shadow_gloss(lower) or _has_canary_gloss(lower)

    if "shadow share" in text.lower():
        return _gloss_in_first_use_window(
            text, "shadow share", share_gloss
        )
    return _gloss_in_first_use_window(text, "canary share", share_gloss)


def build_checks(eval_id: str, ctx: dict) -> dict:
    delivered = ctx["delivered"]
    delivered_words = ctx["delivered_words"]
    fixture_words = ctx["fixture_words"]
    checks: dict[str, dict] = {}

    def add(check_id: str, ok: bool, detail: str) -> None:
        checks[check_id] = {"passed": bool(ok), "detail": detail}

    if eval_id == "connected_rewrite":
        add(
            "length_at_most_draft",
            delivered_words <= fixture_words,
            f"{delivered_words} words vs the draft's {fixture_words}",
        )
        run = pronoun_run(delivered)
        add(
            "no_pronoun_chain",
            run < 3,
            f"longest It/This/They/Its opening run: {run}",
        )
        found = has_series(delivered)
        add(
            "series_is_list_or_colon",
            found,
            "list or colon series found" if found else "list or colon series missing",
        )
        add(
            "no_em_dash",
            EM_DASH not in delivered,
            "no em dash in delivered.md",
        )
        canary_ok = canary_defined_at_first_use(delivered)
        add(
            "canary_definition_kept",
            canary_ok,
            (
                "canary defined in its first-use window"
                if canary_ok
                else "canary missing a definition at first use"
            ),
        )
        shadow_ok = shadow_defined_at_first_use(delivered)
        add(
            "term_referent",
            shadow_ok,
            (
                "shadow share defined in its first-use window"
                if shadow_ok
                else "shadow share missing a referent at first use"
            ),
        )
    elif eval_id == "chat_brevity":
        add(
            "response_text_present",
            bool(delivered.strip()),
            (
                "response.txt carries the delivered answer"
                if delivered.strip()
                else "response.txt is absent or empty"
            ),
        )
        add(
            "length_at_most_120",
            delivered_words <= CHAT_WORD_CAP,
            f"{delivered_words} words vs the cap of {CHAT_WORD_CAP}",
        )
        add(
            "no_heading",
            not has_heading(delivered),
            "response.txt has no heading line",
        )
    else:
        raise SystemExit(f"unknown eval id: {eval_id}")
    return checks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("eval_id")
    parser.add_argument("sandbox_proj")
    parser.add_argument("source_file")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    proj = pathlib.Path(args.sandbox_proj)
    source = pathlib.Path(args.source_file)
    pristine_path = proj.parent / ".fixture_pristine"
    if args.eval_id == "chat_brevity":
        delivered_path = proj / "response.txt"
    else:
        delivered_path = proj / "delivered.md"

    fixture_text = pristine_path.read_text() if pristine_path.exists() else source.read_text()
    delivered = delivered_path.read_text() if delivered_path.exists() else ""
    ctx = {
        "delivered": delivered,
        "fixture": fixture_text,
        "delivered_words": word_count(delivered),
        "fixture_words": word_count(fixture_text),
    }
    checks = build_checks(args.eval_id, ctx)
    integrity = {
        "fixture_unmodified": {
            "passed": pristine_path.exists()
            and source.exists()
            and source.read_text() == pristine_path.read_text(),
            "detail": "source document matches the staged fixture",
        },
    }
    if args.eval_id == "connected_rewrite":
        integrity["delivered_file_written"] = {
            "passed": delivered_path.exists(),
            "detail": f"{delivered_path.name} exists in the sandbox",
        }

    all_checks = {**checks, **integrity}
    verdict = {
        "eval_id": args.eval_id,
        "delivered_words": ctx["delivered_words"],
        "fixture_words": ctx["fixture_words"],
        "mechanical": checks,
        "integrity": integrity,
        "passed": all(item["passed"] for item in all_checks.values()),
    }
    if args.json:
        print(json.dumps(verdict, indent=2))
    else:
        print(
            f"  grade[{args.eval_id}] "
            f"delivered={ctx['delivered_words']}w fixture={ctx['fixture_words']}w"
        )
        for check_id, item in all_checks.items():
            label = "PASS" if item["passed"] else "FAIL"
            print(f"    {label}  {check_id}: {item['detail']}")
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
