#!/usr/bin/env python3
"""Refute-biased judge for the spr behavioral evals.

grade.sh owns the mechanical checks (bullet coverage, numbered lists, trailing
punctuation, out-of-scope terms, the rating). This module judges what a string
check cannot: whether the SPR lets an unprimed reader reconstruct the source,
and whether its bullets stay non-overlapping. The judge is refute-biased, so a
hedged "mostly" reads as a fail.

Usage:
    python3 judge.py <eval_id> <source_file> <delivered_file>
        [--vendor claude|cursor] [--judge-model ...] [--judge-effort ...]
        [--timeout 300] [--out verdict.json]
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
import vendor  # noqa: E402
import worker_isolation  # noqa: E402

ISOLATION_PREFIX = "spr_judge_"

RUBRIC = """\
You are a strict, refute-biased grader. Fail each assertion unless the SPR
plainly satisfies it. A hedge, a guess, or a "mostly" is a fail.

SOURCE:
---
{source}
---

SPR:
---
{delivered}
---

Return only a JSON object with exactly these keys:
{{"reconstructability": "pass" or "fail", "non_overlap": "pass" or "fail", "reason": "<one sentence>"}}

- "reconstructability": pass only when a reader who has not seen the SOURCE
  could reconstruct its structure, key claims, and scope from the SPR alone.
  Fail when a section, claim, or qualification is missing.
- "non_overlap": pass only when each bullet carries one distinct concept and
  no two bullets restate the same content. Fail on duplication or a bullet
  that collapses several distinct concepts.
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
            workspace=str(root),
            effort=resolved.judge_effort,
            extra_args=worker_isolation.isolation_args(resolved.vendor),
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
