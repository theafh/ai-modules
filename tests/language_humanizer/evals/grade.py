#!/usr/bin/env python3
"""Deterministic grader for the language_humanizer behavioral evals.

Grades the mechanically checkable half of each scenario's assertions against
the post-run sandbox: the delivered text's word count against the fixture's
own word count, presence of each ledger item (names, dates, thresholds with
their units, requirement-strength words, the exception clause, the causal
joint), and the bullet-cascade / filler shape of the delivered prose. The
qualitative half — "reads plainly", "strength and scope unchanged in
context", "opens with its main point" — lives in judge.py.

Usage:
    python3 grade.py <eval_id> <sandbox_proj> <source_file> [--json]

Exits 0 when every gating check passed. `--json` prints the machine-readable
verdict dict instead of the human-readable PASS/FAIL lines.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

# --------------------------------------------------------------------------
# text helpers
# --------------------------------------------------------------------------

WORD_RE = re.compile(r"[^\W_]", re.UNICODE)


def word_count(text: str) -> int:
    """Whitespace-separated tokens carrying at least one alphanumeric
    character. Applied identically to the fixture and the delivered text, so
    markdown markers (#, -, |) never inflate either side of the ratio."""
    return sum(1 for tok in text.split() if WORD_RE.search(tok))


def bullet_lines(text: str) -> list[str]:
    return [ln.strip() for ln in text.splitlines()
            if re.match(r"^\s*(?:[-*+]|\d+[.)])\s+\S", ln)]


def longest_short_bullet_run(text: str, max_words: int = 12) -> int:
    """Longest run of consecutive bullet lines each under `max_words` words —
    the mechanical proxy for the fidelity contract's banned 'cascade of
    ever-shorter bullets that splinters one argument into disconnected
    stubs'."""
    best = run = 0
    for line in text.splitlines():
        if re.match(r"^\s*(?:[-*+]|\d+[.)])\s+\S", line):
            if word_count(line) < max_words:
                run += 1
                best = max(best, run)
                continue
        run = 0
    return best


FILLER_PHRASES = [
    "it is important to note",
    "it should be noted",
    "it goes without saying",
    "needless to say",
    "at a high level",
    "at the end of the day",
    "as previously mentioned",
    "as mentioned above",
    "to reiterate",
    "in order to bring",
    "the current situation is that",
    "there are a number of considerations",
    "moving forward",
    "in summary, and",
]


def filler_hits(text: str) -> list[str]:
    low = text.lower()
    return [p for p in FILLER_PHRASES if p in low]


def has(text: str, pattern: str) -> bool:
    return re.search(pattern, text, re.IGNORECASE) is not None


# --------------------------------------------------------------------------
# per-scenario mechanical assertions
# --------------------------------------------------------------------------
#
# Each entry maps an assertion id to a callable over the grading context.
# `ctx` carries: delivered (str), fixture (str), delivered_words (int),
# fixture_words (int).

LEDGER_FIDELITY = {
    "item_actor_priya": r"Priya",
    "item_actor_billing": r"Billing",
    "item_deadline_14_march": r"14\s+March|March\s+14|2026-03-14|14\.03",
    "item_threshold_200ms": r"200\s*ms",
    "item_threshold_995": r"99\.5\s*%",
    "item_strength_must": r"\bmust\b",
    "item_strength_should": r"\bshould\b",
    "item_exception_enterprise": r"enterprise",
    # A rewrite is allowed to reword the joint, so this covers the plain
    # conjunction and the relative form too. The earlier
    # /because|since|so that|therefore/ read 0/5 against rewrites that said
    # "so missing it is not an option" and "which is why the deadline is
    # firm" — a paraphrase the skill is entitled to make. Whether the joint
    # still *connects the right two facts* is the judge's call; this only
    # asks whether a causal connective survived at all.
    "item_causal_joint": (
        r"\bbecause\b|\bsince\b|\bso\b|\btherefore\b|\bthus\b|\bhence\b|"
        r"\bwhich is why\b|\bthat is why\b|\bas a result\b|\bgiven\b|"
        r"\bdriven by\b|\bmeans that\b"
    ),
}

LEDGER_WRITE = {
    "item_owner_dana": r"Dana",
    "item_owner_marco": r"Marco",
    "item_deadline_30_april": r"30\s+April|April\s+30|2026-04-30|30\.04",
    "item_threshold_2h": r"(?:2|two)\s*(?:h\b|hrs?\b|hours?)",
    "item_threshold_per_quarter": r"\bquarter",
    "item_strength_must": r"\bmust\b",
}


def build_checks(eval_id: str, ctx: dict) -> dict:
    d, f = ctx["delivered"], ctx["fixture"]
    dw, fw = ctx["delivered_words"], ctx["fixture_words"]
    checks: dict[str, dict] = {}

    def add(cid: str, ok: bool, detail: str) -> None:
        checks[cid] = {"passed": bool(ok), "detail": detail}

    add("delivered_text_present", bool(d.strip()) and "NO_DELIVERED_TEXT" not in d,
        f"delivered.md carries {dw} words")

    if eval_id == "fidelity_padded":
        ceiling = int(fw * 0.75)
        add("length_at_most_75pct", dw <= ceiling,
            f"{dw} words vs ceiling {ceiling} (75% of the fixture's {fw})")
        for cid, pat in LEDGER_FIDELITY.items():
            add(cid, has(d, pat), f"pattern /{pat}/ in delivered text")
        # Whether the enterprise carve-out still reads as a carve-out from the
        # general migration rule is a meaning question, not a wording one: a
        # keyword scan for except/unless flags a faithful rewrite that marks
        # the exception structurally and misses an unfaithful one that says
        # "except" about something else. The judge's strength_unchanged line
        # owns it, naming the item and its scope explicitly.
        add("no_short_bullet_cascade", longest_short_bullet_run(d) < 3,
            f"longest run of sub-12-word bullets: {longest_short_bullet_run(d)}")

    elif eval_id == "compression_trap":
        add("length_at_most_fixture", dw <= fw,
            f"{dw} words vs the fixture's {fw}")
        add("hedge_kept",
            has(d, r"\bmay\b|\bmight\b|\bcould\b|\bappears\b|\bsuggests\b|"
                   r"\bunconfirmed\b|\bnot\s+(?:yet\s+)?isolated\b|\blikely\b|"
                   r"\bpossibly\b|\bhypothes"),
            "an uncertainty marker survives on the onboarding-step claim")
        add("no_flat_causal_assertion",
            not has(d, r"the (?:drop-?off|decline) is (?:driven|caused) by the new onboarding"),
            "the hedged claim is not restated as a flat fact")
        add("paragraph_stays_prose", longest_short_bullet_run(d) < 3,
            f"longest run of sub-12-word bullets: {longest_short_bullet_run(d)}")
        # Counting the *source's* transition words punished rewrites that
        # substituted an equivalent connective — "yet" for "but" — while the
        # argument stayed fully connected. Whether the reasoning still hangs
        # together belongs to the judge's argument_stays_connected_prose line,
        # which names the specific joints and accepts any wording that carries
        # them. The deterministic side keeps the anti-stub check above.
        add("compounding_argument_kept",
            has(d, r"compound|snowball|cumulativ|accumulat|builds? on itself|"
                   r"carr(?:y|ies|ied) .{0,30}(?:smaller|reduced) .{0,20}base"),
            "the compounding mechanism — the argument's hinge — is still named")

    elif eval_id == "write_path":
        for cid, pat in LEDGER_WRITE.items():
            add(cid, has(d, pat), f"pattern /{pat}/ in delivered text")
        add("no_short_bullet_cascade", longest_short_bullet_run(d) < 3,
            f"longest run of sub-12-word bullets: {longest_short_bullet_run(d)}")
        hits = filler_hits(d)
        add("no_filler_phrases", not hits, f"filler phrases found: {hits or 'none'}")

    else:
        raise SystemExit(f"unknown eval id: {eval_id}")

    return checks


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("eval_id")
    ap.add_argument("sandbox_proj")
    ap.add_argument("source_file")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    proj = pathlib.Path(args.sandbox_proj)
    src = pathlib.Path(args.source_file)
    delivered_path = proj / "delivered.md"
    pristine = proj.parent / ".fixture_pristine"

    fixture_text = pristine.read_text() if pristine.exists() else src.read_text()
    delivered = delivered_path.read_text() if delivered_path.exists() else ""

    ctx = {
        "delivered": delivered,
        "fixture": fixture_text,
        "delivered_words": word_count(delivered),
        "fixture_words": word_count(fixture_text),
    }

    checks = build_checks(args.eval_id, ctx)

    # Harness integrity: the source document must come out untouched. A run
    # that rewrote the fixture in place measured the wrong text, so its
    # verdict is void rather than merely failing.
    integrity = {
        "fixture_unmodified": {
            "passed": pristine.exists() and src.exists()
            and src.read_text() == pristine.read_text(),
            "detail": "source document byte-identical to the staged fixture",
        },
        "delivered_file_written": {
            "passed": delivered_path.exists(),
            "detail": f"{delivered_path.name} exists in the sandbox",
        },
    }

    verdict = {
        "eval_id": args.eval_id,
        "delivered_words": ctx["delivered_words"],
        "fixture_words": ctx["fixture_words"],
        "mechanical": checks,
        "integrity": integrity,
        "bullet_lines": len(bullet_lines(delivered)),
    }
    all_checks = {**checks, **integrity}
    verdict["passed"] = all(c["passed"] for c in all_checks.values())

    if args.json:
        print(json.dumps(verdict, indent=2))
    else:
        print(f"  grade[{args.eval_id}] "
              f"delivered={ctx['delivered_words']}w fixture={ctx['fixture_words']}w")
        for cid, c in all_checks.items():
            print(f"    {'PASS' if c['passed'] else 'FAIL'}  {cid}: {c['detail']}")
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
