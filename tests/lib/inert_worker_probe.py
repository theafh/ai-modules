#!/usr/bin/env python3
"""Inert-worker probe for the behavioral eval graders.

Stages every eval in the named harnesses, writes an empty response file, and
grades the untouched sandbox. An eval that still grades PASS did so with the
worker contributing nothing, which is the defect this probe measures.

Usage:
    python3 tests/lib/inert_worker_probe.py [--harness NAME ...]

Harnesses (default: all): git_checkout, git_review, git_refresh,
git_auto_review, task, task_auto_check, natural_language, wiki.

Each eval is staged through its harness's own ``evals/stage.sh`` into a fresh
temporary root, then graded with an empty response file passed through the
channel that harness's grader reads (``RESPONSE_FILE`` or a positional
argument). ``wiki`` grades a synthetic ``L2-1/pass-1/response.txt`` run
directory because that harness's grader reads a run directory rather than one
eval.

The probe prints one ``INERT-PASS <harness> <id>`` line per eval that passed
without a worker and a per-harness summary. An inert pass outranks an
unmeasured harness: it exits 1 when any eval graded PASS, exits 2 when a
harness could not be measured and no eval graded PASS, and 0 when every graded
eval failed as it should.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile

THIS = pathlib.Path(__file__).resolve().parent
REPO_ROOT = THIS.parents[1]

HARNESSES = (
    "git_checkout",
    "git_review",
    "git_refresh",
    "git_auto_review",
    "task",
    "task_auto_check",
    "natural_language",
    "wiki",
)


def eval_ids(harness: str) -> list[str]:
    """Every eval id the harness's evals.json declares, as strings."""

    if harness == "wiki":
        return ["L2-1"]
    path = REPO_ROOT / "tests" / harness / "evals" / "evals.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    return [str(entry["id"]) for entry in data["evals"]]


def stage(harness: str, eval_id: str, target: pathlib.Path) -> dict[str, str]:
    """Stage one eval and return the paths its grader needs.

    stage.sh prints printf-%q-quoted name=value lines, so bash evaluates them
    and re-emits the raw values NUL-separated. The variable set differs by
    harness: the git harnesses expose ``sandbox_repo``, the task harnesses
    expose ``sandbox_proj``, and natural_language adds ``source_file``.
    """

    stage_sh = REPO_ROOT / "tests" / harness / "evals" / "stage.sh"
    if harness in {"git_checkout", "git_review", "git_refresh", "git_auto_review"}:
        wanted = ('sandbox_repo',)
    elif harness in {"task", "task_auto_check"}:
        wanted = ('sandbox_proj',)
    else:
        wanted = ('sandbox_proj', 'source_file')
    args = ' '.join(f'"${{{name}}}"' for name in wanted)
    emit = (
        f'out="$(bash {shlex.quote(str(stage_sh))} {shlex.quote(eval_id)} '
        f'{shlex.quote(str(target))})" || exit $?; '
        f'eval "$out"; printf \'%s\\0\' {args}'
    )
    result = subprocess.run(
        ["bash", "-c", emit], capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"stage.sh failed for {harness}/{eval_id} "
            f"(rc={result.returncode}): {result.stderr.strip()}"
        )
    values = result.stdout.split("\0")
    return dict(zip(wanted, values))


def grade_command(
    harness: str, eval_id: str, target: pathlib.Path, staged: dict[str, str],
    empty_response: pathlib.Path,
) -> list[str]:
    """The grader invocation for one staged eval."""

    grade_sh = REPO_ROOT / "tests" / harness / "evals" / "grade.sh"
    if harness == "git_checkout":
        return ["bash", str(grade_sh), eval_id, staged["sandbox_repo"]]
    if harness in {"git_review", "git_refresh"}:
        return [
            "bash", str(grade_sh), eval_id, staged["sandbox_repo"],
            str(empty_response),
        ]
    if harness == "git_auto_review":
        return [
            "bash", str(grade_sh), eval_id, staged["sandbox_repo"], str(target),
        ]
    if harness in {"task", "task_auto_check"}:
        return ["bash", str(grade_sh), eval_id, staged["sandbox_proj"]]
    if harness == "natural_language":
        return [
            sys.executable,
            str(REPO_ROOT / "tests" / harness / "evals" / "grade.py"),
            eval_id, staged["sandbox_proj"], staged["source_file"],
        ]
    raise AssertionError(f"no grade command for {harness}")


def grade_env(harness: str, empty_response: pathlib.Path) -> dict[str, str]:
    env = dict(os.environ)
    if harness in {
        "git_auto_review", "task", "task_auto_check",
    }:
        env["RESPONSE_FILE"] = str(empty_response)
    return env


def probe_one(harness: str, eval_id: str) -> int:
    """1 when the eval graded PASS with an empty response, 0 when it graded
    FAIL, and 2 when its stage or grader could not run."""

    target = pathlib.Path(
        tempfile.mkdtemp(prefix=f"inert_probe_{harness}_")
    )
    try:
        empty_response = target / "empty-response.txt"
        empty_response.write_text("")
        try:
            staged = stage(harness, eval_id, target)
        except RuntimeError as exc:
            print(f"cannot measure {harness}/{eval_id}: {exc}", file=sys.stderr)
            return 2
        result = subprocess.run(
            grade_command(harness, eval_id, target, staged, empty_response),
            capture_output=True,
            text=True,
            env=grade_env(harness, empty_response),
        )
        if result.returncode == 0:
            return 1
        if result.returncode == 1:
            return 0
        print(
            f"cannot measure {harness}/{eval_id}: grader rc={result.returncode}"
            f" {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 2
    finally:
        shutil.rmtree(target, ignore_errors=True)


def probe_wiki() -> int:
    """1 when layer2/grade.py passes a run holding one empty response, 0 when
    it grades that run FAIL, and 2 when the grader could not run."""

    target = pathlib.Path(tempfile.mkdtemp(prefix="inert_probe_wiki_"))
    try:
        pass_dir = target / "run" / "L2-1" / "pass-1"
        pass_dir.mkdir(parents=True)
        (pass_dir / "response.txt").write_text("")
        result = subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "tests" / "wiki" / "layer2" / "grade.py"),
                str(target / "run"),
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return 1
        if result.returncode == 1:
            return 0
        print(
            f"cannot measure wiki/L2-1: grader rc={result.returncode}"
            f" {result.stderr.strip()}",
            file=sys.stderr,
        )
        return 2
    finally:
        shutil.rmtree(target, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--harness",
        action="append",
        choices=HARNESSES,
        help="Harness to probe (repeatable; default: every harness).",
    )
    args = parser.parse_args()
    wanted = args.harness or list(HARNESSES)

    total_pass = 0
    measured_any = False
    unmeasured = False
    for harness in wanted:
        if harness == "wiki":
            ids = ["L2-1"]
            status = probe_wiki()
            if status == 2:
                unmeasured = True
                print(
                    f"{harness}: 1 eval(s) could not be measured",
                    file=sys.stderr,
                )
                passes = []
            else:
                passes = [ids[0]] if status == 1 else []
        else:
            ids = eval_ids(harness)
            passes = []
            unmeasured_here = 0
            for eval_id in ids:
                status = probe_one(harness, eval_id)
                if status == 2:
                    unmeasured_here += 1
                elif status == 1:
                    passes.append(eval_id)
            if unmeasured_here:
                unmeasured = True
                print(
                    f"{harness}: {unmeasured_here} eval(s) could not be "
                    f"measured",
                    file=sys.stderr,
                )
        measured_any = True
        total_pass += len(passes)
        for eval_id in passes:
            print(f"INERT-PASS {harness} {eval_id}")
        listing = ", ".join(passes) if passes else "none"
        print(
            f"{harness}: {len(passes)} inert-PASS of {len(ids)} "
            f"(ids: {listing})"
        )

    if not measured_any:
        print("no harness measured", file=sys.stderr)
        return 2
    if total_pass:
        return 1
    if unmeasured:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
