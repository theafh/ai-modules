#!/usr/bin/env python3
"""Refute-biased judge for the executive_summary behavioral evals.

grade.sh owns the mechanical checks (length ratio, list markers, self-rating,
invented terms). This module judges the two things a string check cannot:
whether the summary preserves the source's reasoning and whether it follows
the source's order. It puts the source and the delivered summary in front of a
vendor-resolved print-mode worker with a strict rubric that tells the judge to
fail unless the delivered text plainly satisfies it, so a hedged "mostly"
reads as a fail.

Usage:
    python3 judge.py <eval_id> <source_file> <delivered_file>
        [--vendor claude|cursor] [--judge-model ...] [--judge-effort ...]
        [--timeout 300] [--out verdict.json]

Writes a verdict JSON to --out (or stdout) and exits 0 when the judge ran; a
judge call that cannot run exits non-zero.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

THIS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(THIS.parents[1] / "lib"))
import vendor  # noqa: E402  (shared vendor helper)
import worker_isolation  # noqa: E402  (shared sandbox-root helper)

ISOLATION_PREFIX = "es_judge_"

RUBRIC = """\
You are a strict, refute-biased grader. Fail each assertion unless the
DELIVERED SUMMARY plainly satisfies it. A hedge, a guess, or a "mostly" is a
fail.

SOURCE:
---
{source}
---

DELIVERED SUMMARY:
---
{delivered}
---

Return only a JSON object with exactly these keys:
{{"fidelity": "pass" or "fail", "order": "pass" or "fail", "reason": "<one sentence>"}}

- "fidelity": pass only when every claim, number, owner, date, and
  recommendation in the delivered summary appears in the source and carries
  the same strength and scope. Fail on any invented or upgraded claim.
- "order": pass only when the delivered summary follows the source's sequence
  of ideas (problem or purpose before evidence, evidence before conclusions).
  Fail when it reorders the argument so a conclusion precedes its evidence.
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("eval_id")
    ap.add_argument("source")
    ap.add_argument("delivered")
    ap.add_argument("--out")
    ap.add_argument("--timeout", type=int, default=300)
    vendor.add_vendor_arguments(ap, with_judge=True)
    args = ap.parse_args()
    resolved = vendor.resolve(args, with_judge=True)

    source = pathlib.Path(args.source).read_text(encoding="utf-8")
    delivered = pathlib.Path(args.delivered).read_text(encoding="utf-8")
    prompt = RUBRIC.format(source=source, delivered=delivered)

    root = worker_isolation.create_sandbox_root(ISOLATION_PREFIX)
    try:
        cmd = vendor.build_print_cmd(
            vendor=resolved.vendor,
            bin=resolved.bin,
            model=resolved.judge_model,
            prompt=prompt,
            effort=resolved.judge_effort,
        )
        proc = subprocess.run(
            cmd, cwd=root, capture_output=True, text=True,
            timeout=args.timeout, env=vendor.worker_env(resolved.vendor),
        )
    finally:
        import shutil
        shutil.rmtree(root, ignore_errors=True)

    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        return 1

    match = re.search(r"\{.*\}", proc.stdout, re.S)
    if not match:
        sys.stderr.write("judge returned no JSON object\n")
        return 1
    verdict = json.loads(match.group(0))
    verdict["eval_id"] = args.eval_id
    verdict["vendor"] = resolved.vendor
    verdict["judge_model"] = resolved.judge_model
    verdict["judge_effort"] = resolved.judge_effort

    out = json.dumps(verdict, indent=2) + "\n"
    if args.out:
        pathlib.Path(args.out).write_text(out, encoding="utf-8")
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
