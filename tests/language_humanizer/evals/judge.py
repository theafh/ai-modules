#!/usr/bin/env python3
"""Vendor-aware LLM grader for the language_humanizer assertions.

grade.py owns everything mechanical (word counts, item presence, bullet shape).
This module owns the rest of each scenario's named assertions ("reads
plainly", "every ledger item at unchanged strength and scope", "opens with its
main point", "reads as connected prose", "introduces no filler or
restatement"). It puts the fixture, the delivered text, and one strict rubric
in front of a vendor-resolved print-mode worker and reads back JSON verdicts.
That worker starts from an isolated root of its own, created by
`tests/lib/worker_isolation.py`, so no host standing-instruction file shapes
the verdict.

The judge is refute-biased: each rubric line tells it to fail the assertion
unless the delivered text plainly satisfies it, so a hedged "mostly" reads as
a fail rather than a pass.

The judge's model and effort come from the vendor's judge settings: on
Claude it runs `opus` at `xhigh` effort, and on Cursor it runs `auto`, which
takes no effort. Run on its own, this module resolves those same judge
settings, so a re-judged pass is graded the way the runner grades it.

Usage:
    python3 judge.py <eval_id> <fixture_file> <delivered_file> <response_file>
        [--vendor claude|cursor] [--judge-model opus|auto|'']
        [--judge-effort xhigh|<level>|''] [--timeout 300] [--worker-bin <bin>]
        [--out verdict.json]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import subprocess
import sys

THIS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(THIS.parents[1] / "lib"))
import vendor  # noqa: E402  (shared vendor helper in tests/lib)
import worker_isolation  # noqa: E402  (shared helper in tests/lib)

# Every isolated root a judge call creates starts with this prefix, so a
# leftover root is easy to find under the system temporary directory.
ISOLATION_PREFIX = "lh_judge_"

RUBRICS = {
    "fidelity_padded": {
        "reads_plainly": (
            "The DELIVERED TEXT reads plainly: one idea per sentence carried on a "
            "real verb, active voice where the actor matters, no stacked clause "
            "chains, and none of the source's filler or restatement. Fail this if "
            "any paragraph still reads as corporate padding."
        ),
        "strength_unchanged": (
            "Every one of these thirteen items is present in the DELIVERED TEXT with "
            "its strength and scope unchanged from the SOURCE: (1) Priya Raman as the "
            "owner of the latency fix; (2) the Billing squad as the owner of the "
            "retry migration; (3) the 14 March deadline; (4) the 200 ms committed p95 "
            "latency; (5) the 99.5% availability floor; (6) the current p95 checkout "
            "latency of about 340 ms, kept as the present measurement rather than "
            "turned into a target; (7) Priya shipping the fix, stated as a must; (8) "
            "availability staying at or above 99.5% for the migration, stated as a "
            "must; (9) the Billing squad's retry migration, stated as a should and "
            "NOT upgraded to a must; (10) enterprise retries staying on the "
            "dedicated worker, stated as a should and NOT upgraded to a must; (11) "
            "the enterprise-tenant exception, still scoped to enterprise tenants, "
            "still conditional on the contract renegotiation, and still readable as "
            "a carve-out from the general retry-migration rule rather than as an "
            "unrelated parallel instruction; (12) the causal link making the "
            "deadline follow from the contractual commitment; (13) the causal link "
            "making the fix necessary because the current latency is above the "
            "committed 200 ms. Any wording that carries a causal link counts, "
            "including 'so' or 'which is why'. Fail this if any item is missing, "
            "flattened, upgraded, downgraded, or broadened."
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
            "wording that carries a joint counts, and a substituted connective such "
            "as 'yet' for 'but' is fine. Fail this if a joint is gone, if it survives "
            "only as juxtaposition with no connective, or if the argument has been "
            "reduced to a list of disconnected stubs."
        ),
        "hedge_intact": (
            "The onboarding-step explanation is still marked as uncertain in the "
            "DELIVERED TEXT: it may be the cause, it is not isolated from the "
            "pricing-page change, and the reading is unconfirmed. Fail this if it now "
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
            "The DELIVERED TEXT opens with its main point, meaning what has to "
            "happen and by when, rather than with background, a restatement of the "
            "notes, or a preamble about the retro."
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
          vendor_name: str, worker_bin: str, model: str, timeout: int,
          *, effort: str) -> dict:
    """Grade one pass from an isolated root of the judge's own.

    The root comes from the shared isolation helper, so the judge call starts
    outside the home directory and outside any git repository and carries the
    helper's arguments for the resolved vendor. No host standing-instruction
    file reaches the verdict. The root is removed after the call. ``effort``
    is required beside ``model`` and reaches the judge command as
    ``--effort``; ``''`` omits the flag.
    """
    prompt = build_prompt(eval_id, fixture, delivered, response)
    root = worker_isolation.create_sandbox_root(ISOLATION_PREFIX)
    cmd = vendor.build_print_cmd(
        vendor=vendor_name,
        bin=worker_bin,
        model=model,
        effort=effort,
        prompt=prompt,
        workspace=str(root),
        extra_args=worker_isolation.isolation_args(vendor_name),
    )
    try:
        try:
            out = subprocess.run(
                cmd,
                cwd=root,
                capture_output=True,
                text=True,
                timeout=timeout,
                env=vendor.worker_env(vendor_name),
            )
        except subprocess.TimeoutExpired:
            return {"_judge_error": {"passed": False,
                                     "why": f"judge timed out after {timeout}s"}}
    finally:
        shutil.rmtree(root, ignore_errors=True)
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
    vendor.add_vendor_arguments(ap, with_judge=True)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--out")
    args = ap.parse_args()
    if args.model is not None or args.effort is not None:
        ap.error("the standalone judge starts no worker, so it takes --judge-model "
                 "and --judge-effort in place of --model and --effort")
    resolved = vendor.resolve(args, with_judge=True)

    if args.eval_id not in RUBRICS:
        raise SystemExit(f"unknown eval id: {args.eval_id}")

    read = lambda p: pathlib.Path(p).read_text() if pathlib.Path(p).exists() else ""  # noqa: E731
    verdicts = judge(args.eval_id, read(args.fixture_file), read(args.delivered_file),
                     read(args.response_file), resolved.vendor, resolved.bin,
                     resolved.judge_model or "", args.timeout,
                     effort=resolved.judge_effort or "")

    if args.out:
        pathlib.Path(args.out).write_text(json.dumps(verdicts, indent=2))
    print(json.dumps(verdicts, indent=2))
    return 0 if all(v["passed"] for v in verdicts.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
