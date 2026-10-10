#!/usr/bin/env python3
"""Vendor-aware LLM grader for the natural_language assertions.

grade.py owns the mechanical checks. This module owns the rest: whether each
enumerated relation is still stated, whether paragraphs and sections lead with
their point, and whether a chat reply answers first without a recap.

The judge is refute-biased: each rubric line tells it to fail an assertion
unless the delivered text plainly satisfies it, so a hedged reading is a fail.

The judge runs from its own isolated root, with no staged output style and no
outputStyle selection. The root and the worker arguments come from
tests/lib/worker_isolation.py.
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
import vendor  # noqa: E402
import worker_isolation  # noqa: E402

RUBRICS = {
    "connected_rewrite": {
        "contrast_kept": (
            "Fail this unless the DELIVERED TEXT still states this contrast as a "
            "contrast: both (1) the build can pass every automated check and "
            "(2) a quiet failure in one client library still reaches users who "
            "never opted into the trial, joined in one sentence or across a "
            "clear opposition by but or yet. Fail when the two sides appear "
            "only as separate sentences with no but or yet. Fail when the only "
            "candidate marker is 'still' modifying a verb such as 'still "
            "reaches'. Fail when the failure only 'would' reach those users "
            "under a counterfactual, or when who is reached changes."
        ),
        "two_reasons_kept": (
            "Fail this unless the DELIVERED TEXT still states both reasons as "
            "causes that the gate holds the release: the shadow share is still "
            "climbing (growing, expanding, or increasing counts as the same "
            "claim), and the error count in that share has not yet fallen below "
            "the rollback line. Keep the causal relation with because, since, "
            "or an equivalent cause marker. Fail if either reason is missing, "
            "if 'still climbing' is replaced by a different claim such as "
            "having run long enough, or if the reasons are only circumstances "
            "joined by while, until, or as without a cause marker."
        ),
        "condition_kept": (
            "Fail this unless the DELIVERED TEXT still states the condition that "
            "the release advances to the full user base only if the shadow share "
            "stays under the error line for a full day."
        ),
        "signal_inventory_kept": (
            "Fail this unless the DELIVERED TEXT still names intake, review, "
            "and release as the three parallel items the gate checks, asks, or "
            "signals. Any wording that keeps that three-item inventory counts. "
            "Fail only when one of the three names is missing."
        ),
        "paragraphs_open_with_point": (
            "Fail this unless every body paragraph opens with its main point "
            "in the first sentence. Fail this if a body paragraph opens with "
            "evidence, raw counts, mechanism or chronology and only reaches "
            "its point later. A topic-only heading does not supply that "
            "opening."
        ),
        "figures_tied": (
            "Fail this unless the passage that carries the fall from 40 errors "
            "in the first hour to 6 in the third either names that fall as the "
            "quieter deciding signal or the evidence for the release decision, "
            "or states that the quieter signal should decide and then gives "
            "that fall as its supporting figure in the same passage. Fail when "
            "the fall appears with no deciding-signal or release-decision "
            "frame. Support tickets staying flat may appear in the same "
            "passage."
        ),
        "arithmetic_opens_with_conclusion": (
            "Fail this unless the passage that contains both arithmetic counts "
            "(40 errors across 800 requests and 6 errors across 800 requests) "
            "opens with the conclusion that the release can advance, or that "
            "the shadow share is inside the rollback line, before either count "
            "appears. Any wording of that conclusion counts. A softer opener "
            "such as 'getting quieter' does not count. Fail if the passage "
            "leads with the counts, rates, or chronology and only reaches the "
            "conclusion later."
        ),
        "connected_prose": (
            "Fail this unless the delivered text reads as connected prose. "
            "Sentences keep the relations between claims, and the argument is "
            "not a run of disconnected one-clause stubs."
        ),
    },
    "chat_brevity": {
        "answer_in_first_sentence": (
            "Fail this unless the first sentence answers the question: the "
            "canary reaches one user in twenty."
        ),
        "no_preamble_restatement_recap": (
            "Fail this unless the reply has no preamble, no restatement of the "
            "question, and no closing recap."
        ),
    },
}

PROMPT = """\
You are grading one piece of delivered text against a strict rubric.
Judge only what the rubric asks. Be refute-biased: fail an assertion unless
the delivered text plainly satisfies it. For paragraphs_open_with_point,
pass a paragraph when its first sentence already states a claim; later
elaboration, definition or evidence does not undo that. Do not fail a
paragraph for a first sentence that is already a claim by calling that claim
vague. How a check runs, where a library lives, and similar mechanism
sentences are not claims. Fail only the inverted shape: evidence, counts,
mechanism or chronology first, claim later.

=== SOURCE (the input the writer was given) ===
{fixture}
=== END SOURCE ===

=== DELIVERED TEXT ===
{delivered}
=== END DELIVERED TEXT ===

=== FULL RESPONSE (context only) ===
{response}
=== END FULL RESPONSE ===

Grade these assertions:

{rubric}

Reply with one JSON object and nothing else, no code fence:

{{{schema}}}
"""


def build_prompt(eval_id: str, fixture: str, delivered: str, response: str) -> str:
    rubric = RUBRICS[eval_id]
    lines = "\n".join(f"- {key}: {value}" for key, value in rubric.items())
    schema = ", ".join(
        f'"{key}": {{"passed": true|false, "why": "one sentence"}}' for key in rubric
    )
    return PROMPT.format(
        fixture=fixture.strip(),
        delivered=delivered.strip(),
        response=response.strip()[:12000],
        rubric=lines,
        schema=schema,
    )


def extract_json(text: str) -> dict:
    """Return the first balanced JSON object in the model's reply."""

    start = text.find("{")
    while start != -1:
        depth = 0
        for index in range(start, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[start:index + 1])
                    except json.JSONDecodeError:
                        break
        start = text.find("{", start + 1)
    raise ValueError("no JSON object in judge reply")


def judge(
    eval_id: str,
    fixture: str,
    delivered: str,
    response: str,
    vendor_name: str,
    worker_bin: str,
    model: str,
    timeout: int,
) -> dict:
    """Grade one pass from an isolated root with no output style selected."""

    prompt = build_prompt(eval_id, fixture, delivered, response)
    root = worker_isolation.create_sandbox_root("nl_judge_")
    cmd = vendor.build_print_cmd(
        vendor=vendor_name,
        bin=worker_bin,
        model=model,
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
            return {
                "_judge_error": {
                    "passed": False,
                    "why": f"judge timed out after {timeout}s",
                }
            }
    finally:
        shutil.rmtree(root, ignore_errors=True)

    if out.returncode != 0 or not out.stdout.strip():
        detail = (out.stderr or out.stdout)[:200]
        return {
            "_judge_error": {
                "passed": False,
                "why": f"judge rc={out.returncode}: {detail}",
            }
        }
    try:
        raw = extract_json(out.stdout)
    except ValueError as exc:
        return {
            "_judge_error": {
                "passed": False,
                "why": f"{exc}: {out.stdout[:200]}",
            }
        }

    verdicts = {}
    for key in RUBRICS[eval_id]:
        entry = raw.get(key)
        if isinstance(entry, dict):
            verdicts[key] = {
                "passed": bool(entry.get("passed")),
                "why": str(entry.get("why", ""))[:400],
            }
        elif isinstance(entry, bool):
            verdicts[key] = {"passed": entry, "why": ""}
        else:
            verdicts[key] = {"passed": False, "why": "judge returned no verdict"}
    return verdicts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("eval_id")
    parser.add_argument("fixture_file")
    parser.add_argument("delivered_file")
    parser.add_argument("response_file")
    vendor.add_vendor_arguments(parser, harness_id="natural_language")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--out")
    args = parser.parse_args()
    resolved = vendor.resolve(args)
    vendor.require_vendor_allowed(resolved.vendor, "natural_language")

    if args.eval_id not in RUBRICS:
        raise SystemExit(f"unknown eval id: {args.eval_id}")

    def read(path: str) -> str:
        file_path = pathlib.Path(path)
        return file_path.read_text() if file_path.exists() else ""

    verdicts = judge(
        args.eval_id,
        read(args.fixture_file),
        read(args.delivered_file),
        read(args.response_file),
        resolved.vendor,
        resolved.bin,
        resolved.worker_model,
        args.timeout,
    )
    if args.out:
        pathlib.Path(args.out).write_text(json.dumps(verdicts, indent=2))
    print(json.dumps(verdicts, indent=2))
    return 0 if all(item["passed"] for item in verdicts.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
