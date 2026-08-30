#!/usr/bin/env python3
"""LLM grader for the language_humanizer assertions no regex can settle.

grade.py owns everything mechanical (word counts, item presence, bullet shape).
This module owns the rest of each scenario's named assertions — "reads
plainly", "all nine items at unchanged strength and scope", "opens with its
main point", "reads as connected prose", "introduces no filler or
restatement" — by putting the fixture, the delivered text, and one strict
rubric in front of a pinned worker and reading back JSON verdicts.

The judge is refute-biased: each rubric line tells it to fail the assertion
unless the delivered text plainly satisfies it, so a hedged "mostly" reads as
a fail rather than a pass.

Usage:
    python3 judge.py <eval_id> <fixture_file> <delivered_file> <response_file>
        [--model claude-sonnet-4-6] [--timeout 300] [--claude-bin claude]
        [--out verdict.json]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys

THIS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(THIS.parents[1] / "lib"))
from worker_auth import worker_env  # noqa: E402  (shared; tests/ is gitignored)

RUBRICS = {
    "fidelity_padded": {
        "reads_plainly": (
            "The DELIVERED TEXT reads plainly: one idea per sentence carried on a "
            "real verb, active voice where the actor matters, no stacked clause "
            "chains, and none of the source's filler or restatement. Fail this if "
            "any paragraph still reads as corporate padding."
        ),
        "strength_unchanged": (
            "Every one of these nine items is present in the DELIVERED TEXT with its "
            "strength and scope unchanged from the SOURCE: (1) Priya Raman as the "
            "owner of the latency fix; (2) the Billing squad as the owner of the "
            "retry migration; (3) the 14 March deadline; (4) the 200 ms committed p95 "
            "latency; (5) the 99.5% availability floor; (6) the must-strength "
            "obligations stated as musts; (7) the Billing squad's retry migration "
            "stated as a should, NOT upgraded to a must; (8) the enterprise-tenant "
            "exception, still scoped to enterprise tenants, still conditional on the "
            "contract renegotiation, and still readable as a carve-out from the "
            "general retry-migration rule rather than as an unrelated parallel "
            "instruction; (9) the causal link making the deadline follow from the "
            "contractual commitment — any wording carries it, including 'so' or "
            "'which is why'. Fail this if any item is missing, flattened, upgraded, "
            "downgraded, or broadened."
        ),
        "no_invented_content": (
            "The DELIVERED TEXT adds no fact, number, owner, date, or commitment "
            "that the SOURCE does not contain."
        ),
    },
    "compression_trap": {
        "argument_stays_connected_prose": (
            "The DELIVERED TEXT keeps the argument as connected prose whose "
            "transitions carry the reasoning, and each of these three joints is "
            "still explicitly made rather than left for the reader to infer from "
            "adjacent sentences: (a) the signup dip recovers WHEREAS conversion "
            "compounds; (b) BECAUSE it compounds, conversion gets the remediation "
            "budget first, EVEN THOUGH leadership asks about signups; (c) the "
            "decline sits in self-serve SINCE assisted conversion held flat, and "
            "THEREFORE an assisted-funnel fix addresses only the smaller half. Any "
            "wording that carries a joint counts — a substituted connective such as "
            "'yet' for 'but' is fine. Fail this if a joint is gone, if it survives "
            "only as juxtaposition with no connective, or if the argument has been "
            "reduced to a list of disconnected stubs."
        ),
        "hedge_intact": (
            "The onboarding-step explanation is still marked as uncertain in the "
            "DELIVERED TEXT — it may be the cause, it is not isolated from the "
            "pricing-page change, the reading is unconfirmed. Fail this if it now "
            "reads as an established cause, and fail it also if the uncertainty is "
            "kept while the pricing-page confound is dropped."
        ),
        "reads_plainly": (
            "The DELIVERED TEXT is easier to take in on a first read than the "
            "SOURCE: the one long paragraph has been broken into sentences a reader "
            "can follow without re-reading, while staying prose."
        ),
    },
    "write_path": {
        "opens_with_main_point": (
            "The DELIVERED TEXT opens with its main point — what has to happen and "
            "by when — rather than with background, a restatement of the notes, or "
            "a preamble about the retro."
        ),
        "reads_as_connected_prose": (
            "The DELIVERED TEXT reads as connected prose: full sentences with their "
            "joining words. A short list of genuinely parallel items is fine; a "
            "document that is only a bullet dump, or a cascade of ever-shorter "
            "stubs, fails."
        ),
        "no_filler_or_restatement": (
            "The DELIVERED TEXT introduces no filler and no restatement: no "
            "throat-clearing preamble, no sentence that only repeats what an earlier "
            "sentence said, no summary paragraph re-listing the same items."
        ),
        "five_items_at_strength": (
            "All five load-bearing items from the SOURCE notes are present with "
            "their strength intact: Dana Okoro owning the alerting rework, Marco "
            "Weiss owning the postmortem template refresh, the 30 April deadline, "
            "the error budget of at most 2 hours of downtime per quarter, and that "
            "error-budget bar stated as a must rather than a target."
        ),
        "no_invented_content": (
            "The DELIVERED TEXT invents no owner, date, number, or decision the "
            "SOURCE notes do not contain. Naming an unresolved question as open is "
            "fine; inventing its answer is not."
        ),
    },
}

PROMPT = """\
You are grading one output of a text-editing skill against a strict rubric.
Judge only what the rubric asks. Be refute-biased: fail an assertion unless
the delivered text plainly satisfies it.

=== SOURCE (the input the skill was given) ===
{fixture}
=== END SOURCE ===

=== DELIVERED TEXT (what the skill returned as the document) ===
{delivered}
=== END DELIVERED TEXT ===

=== FULL RESPONSE (the skill's whole reply, for context only) ===
{response}
=== END FULL RESPONSE ===

Grade these assertions:

{rubric}

Reply with one JSON object and nothing else, no code fence:

{{{schema}}}
"""


def build_prompt(eval_id: str, fixture: str, delivered: str, response: str) -> str:
    rubric = RUBRICS[eval_id]
    lines = "\n".join(f"- {k}: {v}" for k, v in rubric.items())
    schema = ", ".join(
        f'"{k}": {{"passed": true|false, "why": "one sentence"}}' for k in rubric
    )
    return PROMPT.format(
        fixture=fixture.strip(), delivered=delivered.strip(),
        response=response.strip()[:12000], rubric=lines, schema=schema,
    )


def extract_json(text: str) -> dict:
    """First balanced JSON object in the model's reply."""
    start = text.find("{")
    while start != -1:
        depth = 0
        for i in range(start, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[start:i + 1])
                    except json.JSONDecodeError:
                        break
        start = text.find("{", start + 1)
    raise ValueError("no JSON object in judge reply")


def judge(eval_id: str, fixture: str, delivered: str, response: str,
          claude_bin: str, model: str, timeout: int) -> dict:
    prompt = build_prompt(eval_id, fixture, delivered, response)
    cmd = [claude_bin, "-p", "--permission-mode", "bypassPermissions"]
    if model:
        cmd += ["--model", model]
    cmd.append(prompt)
    try:
        out = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=timeout, env=worker_env())
    except subprocess.TimeoutExpired:
        return {"_judge_error": {"passed": False, "why": f"judge timed out after {timeout}s"}}
    if out.returncode != 0 or not out.stdout.strip():
        return {"_judge_error": {
            "passed": False,
            "why": f"judge rc={out.returncode}: {(out.stderr or out.stdout)[:200]}"}}
    try:
        raw = extract_json(out.stdout)
    except ValueError as exc:
        return {"_judge_error": {"passed": False, "why": f"{exc}: {out.stdout[:200]}"}}

    verdicts = {}
    for key in RUBRICS[eval_id]:
        entry = raw.get(key)
        if isinstance(entry, dict):
            verdicts[key] = {"passed": bool(entry.get("passed")),
                             "why": str(entry.get("why", ""))[:400]}
        elif isinstance(entry, bool):
            verdicts[key] = {"passed": entry, "why": ""}
        else:
            verdicts[key] = {"passed": False, "why": "judge returned no verdict"}
    return verdicts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("eval_id")
    ap.add_argument("fixture_file")
    ap.add_argument("delivered_file")
    ap.add_argument("response_file")
    ap.add_argument("--model", default="claude-sonnet-4-6")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--claude-bin", default="claude")
    ap.add_argument("--out")
    args = ap.parse_args()

    if args.eval_id not in RUBRICS:
        raise SystemExit(f"unknown eval id: {args.eval_id}")

    read = lambda p: pathlib.Path(p).read_text() if pathlib.Path(p).exists() else ""  # noqa: E731
    verdicts = judge(args.eval_id, read(args.fixture_file), read(args.delivered_file),
                     read(args.response_file), args.claude_bin, args.model, args.timeout)

    if args.out:
        pathlib.Path(args.out).write_text(json.dumps(verdicts, indent=2))
    print(json.dumps(verdicts, indent=2))
    return 0 if all(v["passed"] for v in verdicts.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
