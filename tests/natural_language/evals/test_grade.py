#!/usr/bin/env python3
"""Unit tests that grade.py collapses hard wraps in prose."""

from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile
import textwrap

import grade as grader

THIS = pathlib.Path(__file__).resolve().parent
FIXTURES = THIS / "fixtures" / "connected_rewrite"

PASS = 0
FAIL = 0


def check(label: str, condition: bool) -> None:
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def wrap_markdown(text: str, width: int = 72) -> str:
    """Hard-wrap prose paragraphs. Keep headings, lists, and table rows."""

    lines: list[str] = []
    paragraph: list[str] = []

    def flush() -> None:
        if not paragraph:
            return
        lines.append(textwrap.fill(" ".join(paragraph), width=width))
        paragraph.clear()

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            flush()
            lines.append("")
            continue
        if grader._is_kept_line(stripped):
            flush()
            lines.append(stripped)
            continue
        paragraph.append(stripped)
    flush()
    return "\n".join(lines) + "\n"


def empty_delivery_exits_nonzero() -> bool:
    """grade.py fails a chat_brevity run whose response.txt is empty."""

    with tempfile.TemporaryDirectory() as td:
        proj = pathlib.Path(td) / "proj"
        proj.mkdir()
        (proj / "response.txt").write_text("")
        source = pathlib.Path(td) / "question.md"
        source.write_text("What is the answer?\n")
        (pathlib.Path(td) / ".fixture_pristine").write_text(
            source.read_text()
        )
        result = subprocess.run(
            [
                sys.executable,
                str(THIS / "grade.py"),
                "chat_brevity",
                str(proj),
                str(source),
            ],
            capture_output=True,
            text=True,
        )
        return result.returncode != 0


def main() -> int:
    faithful = (FIXTURES / "faithful.md").read_text()
    flattened = (FIXTURES / "flattened.md").read_text()
    wrapped_faithful = wrap_markdown(faithful)
    wrapped_flattened = wrap_markdown(flattened)

    check(
        "unwrapped faithful has a colon series",
        grader.has_series(faithful),
    )
    check(
        "wrapped faithful still has a colon series",
        grader.has_series(wrapped_faithful),
    )
    check(
        "unwrapped flattened pronoun run is at least 3",
        grader.pronoun_run(flattened) >= 3,
    )
    check(
        "wrapped flattened pronoun run stays at least 3",
        grader.pronoun_run(wrapped_flattened) >= 3,
    )
    check(
        "wrap can split a colon series across physical lines",
        "intake,\nreview" in textwrap.fill(
            "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX signals: intake, "
            "review, and release.",
            width=60,
        ),
    )
    check(
        "wrapped faithful still detects its colon series",
        grader.has_series(wrapped_faithful),
    )
    check(
        "wrap splits a pronoun-led sentence across physical lines",
        "error\ncount. It leaves" in wrapped_flattened,
    )
    check(
        "faithful defines canary in its first-use sentence",
        grader.canary_defined_at_first_use(faithful),
    )
    check(
        "faithful defines shadow share in its first-use sentence",
        grader.shadow_defined_at_first_use(faithful),
    )
    check(
        "flattened leaves canary bare at first use",
        not grader.canary_defined_at_first_use(flattened),
    )
    check(
        "flattened leaves shadow share bare at first use",
        not grader.shadow_defined_at_first_use(flattened),
    )
    alias = (
        "The shadow share (also called the canary) is the portion of traffic "
        "that sees the new build while the old build still serves the rest.\n"
    )
    check(
        "same-sentence canary alias onto the shadow gloss counts",
        grader.canary_defined_at_first_use(alias),
    )
    check(
        "same-sentence shadow gloss still counts with a canary alias",
        grader.shadow_defined_at_first_use(alias),
    )
    bare_then_define = (
        "The gate holds until the shadow share shows it is safe. "
        "The shadow share is the portion of traffic that sees the new build "
        "while the old build still serves the rest.\n"
    )
    check(
        "next-sentence shadow gloss counts in the first-use window",
        grader.shadow_defined_at_first_use(bare_then_define),
    )
    late_define = (
        "The gate holds until the shadow share shows it is safe. "
        "The operator waits. "
        "The shadow share is the portion of traffic that sees the new build "
        "while the old build still serves the rest.\n"
    )
    check(
        "gloss two sentences later still fails",
        not grader.shadow_defined_at_first_use(late_define),
    )
    check(
        "canary gloss paraphrase with reaches/share/first counts",
        grader.canary_defined_at_first_use(
            "The operator starts every release as a canary, "
            "one that reaches only this share first.\n"
        ),
    )
    plain_then_name = (
        "The operator starts with a canary, which sends the new build to a "
        "small share of users while the old build serves the rest. "
        "That small share is the shadow share.\n"
    )
    check(
        "canary gloss with small share of users counts",
        grader.canary_defined_at_first_use(plain_then_name),
    )
    check(
        "plain-words gloss then naming sentence counts for shadow share",
        grader.shadow_defined_at_first_use(plain_then_name),
    )
    calls_name = (
        "The operator starts with a canary release, which means the new build "
        "serves only a small share of traffic while the old build serves the "
        "rest. This document calls that small share the shadow share.\n"
    )
    check(
        "calls-that naming sentence after a prior gloss counts",
        grader.shadow_defined_at_first_use(calls_name),
    )
    check(
        "canary gloss with reaches/small share of traffic counts",
        grader.canary_defined_at_first_use(
            "The operator starts with a canary release, which reaches only "
            "that small share of traffic, called the shadow share.\n"
        ),
    )
    bare_shadow_then_canary = (
        "The shadow share is still climbing. "
        "The canary share, the portion of traffic that sees the new build "
        "while the old build still serves the rest, stays under the line.\n"
    )
    check(
        "bare shadow share fails when a later canary share carries the gloss",
        not grader.shadow_defined_at_first_use(bare_shadow_then_canary),
    )
    canary_share_only = (
        "The canary share, the portion of traffic that sees the new build "
        "while the old build still serves the rest, stays under the line.\n"
    )
    check(
        "canary share gloss counts when shadow share is absent",
        grader.shadow_defined_at_first_use(canary_share_only),
    )
    check(
        "an empty chat_brevity delivery exits non-zero",
        empty_delivery_exits_nonzero(),
    )

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
