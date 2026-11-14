#!/usr/bin/env python3
"""Stage every agent_spinner eval and accept every return it leaves open.

Usage:
    python3 fixture_stage.py [eval_id ...]

The check guards the eval fixtures against the shipped ledger's return
contract, so a ledger change that leaves a fixture behind fails `make test`
rather than a paid eval run. For each id in evals/evals.json (or each id
named on the command line) it:

1. runs evals/stage.sh into a fresh temporary directory and fails the eval
   when the stage exits non-zero;
2. reads every staged return under proj/.agent_spinner/returns/ and fails
   the eval when a return whose fenced JSON block parses lacks an
   `objections` list;
3. for every roster row in state `dispatched` whose return file exists,
   copies the staged project to a throwaway directory, runs the bundled
   ledger's `accept <label>` there, and compares the refusal lines with
   EXPECTED_REFUSALS. A return absent from the map must accept with exit 0,
   and a mapped return must be refused with exactly its mapped lines.

A map entry that matches no staged return also fails the check, so the map
cannot outlive the fixture it describes.
"""

import concurrent.futures
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
HARNESS = HERE.parent
REPO_ROOT = HARNESS.parent.parent
EVALS_DIR = HARNESS / "evals"
STAGE = EVALS_DIR / "stage.sh"
EVALS_JSON = EVALS_DIR / "evals.json"
LEDGER = REPO_ROOT / "plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py"

# Roster columns the check reads, by the ledger's column order.
LABEL_COLUMN = 0
STATE_COLUMN = 6

# Returns a fixture stages for the run to accept and that the ledger must
# refuse, keyed on (eval id, row label), each with the exact refusal lines
# `accept` prints. Every other open return must accept with exit 0.
EXPECTED_REFUSALS = {
    # failure_taxonomy stages a boilerplate-only spawn glitch: no END line
    # and no fenced block.
    ("failure_taxonomy", "survey:beta"): [
        "missing END line (expected END survey:beta)",
        "block count is 0, expected exactly one",
    ],
    # failure_taxonomy stages a schema-valid return whose finding fields are
    # all placeholders.
    ("failure_taxonomy", "survey:delta"): [
        "finding claim is a placeholder or missing",
        "finding quote is a placeholder or missing",
        "finding anchor is a placeholder or missing",
    ],
    # hollow_plan_blocks_writes stages a planner return whose one checklist
    # line cites a placeholder span, so the row becomes a contract violation.
    ("hollow_plan_blocks_writes", "produce:plan"): [
        "checklist line cites a placeholder span: 'TODO'",
    ],
    # uncited_clean_reroute stages a clean verdict whose receipt line is
    # absent from the input version the row recorded.
    ("uncited_clean_reroute", "check:deploy"): [
        "receipt for docs/deploy.md is missing from the recorded input version",
    ],
    # judge_flaws_capped: pinned as observed, not judged intended. The judge
    # rows record no input version for candidates/one.md, a refusal that
    # predates ledger phase 2 while the eval's prompt asks the run to accept
    # both returns.
    ("judge_flaws_capped", "judge:speed"): [
        "examined candidates/one.md has no recorded input version",
    ],
    ("judge_flaws_capped", "judge:cost"): [
        "examined candidates/one.md has no recorded input version",
    ],
}

REFUSAL_LINE = re.compile(r"^\s+- (.*)$")
FENCED_JSON = re.compile(r"^```json\n(.*?)^```", re.M | re.S)


def child_env():
    """The caller's environment without git variables that bind a repo."""
    env = dict(os.environ)
    for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
        env.pop(name, None)
    return env


def eval_ids():
    data = json.loads(EVALS_JSON.read_text(encoding="utf-8"))
    return [entry["id"] for entry in data["evals"]]


def roster_rows(state_dir):
    roster = state_dir / "roster.tsv"
    if not roster.is_file():
        return []
    rows = []
    for line in roster.read_text(encoding="utf-8").splitlines():
        cells = line.split("\t")
        if len(cells) > STATE_COLUMN:
            rows.append((cells[LABEL_COLUMN], cells[STATE_COLUMN]))
    return rows


def missing_objections(returns_dir):
    """Name each parseable staged return that carries no objections list."""
    problems = []
    if not returns_dir.is_dir():
        return problems
    for path in sorted(returns_dir.glob("*.md")):
        match = FENCED_JSON.search(path.read_text(encoding="utf-8"))
        if not match:
            continue
        try:
            data = json.loads(match.group(1))
        except ValueError:
            continue
        if not isinstance(data, dict):
            continue
        if not isinstance(data.get("objections"), list):
            problems.append("%s carries no objections list" % path.name)
    return problems


def dry_run_accept(proj, label, scratch):
    """Accept one row in a throwaway copy; return (exit code, refusal lines)."""
    copy = scratch / ("accept-" + re.sub(r"[^A-Za-z0-9_.-]", "_", label))
    shutil.copytree(proj, copy, symlinks=True)
    try:
        proc = subprocess.run(
            [sys.executable, "-B", str(LEDGER), "accept", label],
            cwd=str(copy),
            env=child_env(),
            capture_output=True,
            text=True,
        )
    finally:
        shutil.rmtree(copy, ignore_errors=True)
    output = proc.stdout + proc.stderr
    lines = []
    for line in output.splitlines():
        match = REFUSAL_LINE.match(line)
        if match:
            lines.append(match.group(1))
    return proc.returncode, lines, output


def check_eval(eval_id, root):
    """Stage one eval and check its staged returns; return (failures, seen)."""
    failures = []
    seen = set()
    target = root / eval_id
    scratch = root / (eval_id + ".scratch")
    scratch.mkdir(parents=True)
    env = child_env()
    env["TMPDIR"] = str(scratch)
    try:
        proc = subprocess.run(
            ["bash", str(STAGE), eval_id, str(target)],
            env=env,
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            tail = [line for line in proc.stderr.splitlines() if line.strip()]
            failures.append(
                "%s: stage.sh exited %d: %s"
                % (eval_id, proc.returncode, " | ".join(tail[-3:]) or "no stderr")
            )
            return failures, seen

        proj = target / "proj"
        state_dir = proj / ".agent_spinner"
        returns_dir = state_dir / "returns"
        for problem in missing_objections(returns_dir):
            failures.append("%s: %s" % (eval_id, problem))

        for label, state in roster_rows(state_dir):
            if state != "dispatched":
                continue
            if not (returns_dir / (label + ".md")).is_file():
                continue
            key = (eval_id, label)
            seen.add(key)
            code, refusals, output = dry_run_accept(proj, label, scratch)
            expected = EXPECTED_REFUSALS.get(key)
            if expected is None:
                if code != 0:
                    failures.append(
                        "%s %s: accept exited %d, expected exit 0: %s"
                        % (eval_id, label, code,
                           " | ".join(refusals) or output.strip()[-300:])
                    )
            elif code == 0:
                failures.append(
                    "%s %s: accept exited 0, expected refusal: %s"
                    % (eval_id, label, " | ".join(expected))
                )
            elif refusals != expected:
                failures.append(
                    "%s %s: refusal lines %r, expected %r"
                    % (eval_id, label, refusals, expected)
                )
    finally:
        shutil.rmtree(target, ignore_errors=True)
        shutil.rmtree(scratch, ignore_errors=True)
    return failures, seen


def main(argv):
    known = eval_ids()
    wanted = argv[1:] or known
    unknown = [eval_id for eval_id in wanted if eval_id not in known]
    if unknown:
        sys.stderr.write("unknown eval id: %s\n" % ", ".join(unknown))
        return 2

    root = pathlib.Path(tempfile.mkdtemp(prefix="agent_spinner_fixture_stage."))
    failures = []
    failed_ids = set()
    seen = set()
    workers = min(8, os.cpu_count() or 1)
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {
                pool.submit(check_eval, eval_id, root): eval_id
                for eval_id in wanted
            }
            results = {}
            for future in concurrent.futures.as_completed(futures):
                results[futures[future]] = future.result()
        for eval_id in wanted:
            eval_failures, eval_seen = results[eval_id]
            failures.extend(eval_failures)
            seen.update(eval_seen)
            if eval_failures:
                failed_ids.add(eval_id)
            status = "FAIL" if eval_failures else "PASS"
            print("%s: %s stages and its open returns match the ledger" % (status, eval_id))
    finally:
        shutil.rmtree(root, ignore_errors=True)

    for key in sorted(EXPECTED_REFUSALS):
        if key[0] in wanted and key not in seen:
            failed_ids.add(key[0])
            failures.append(
                "%s %s: expected refusal names no open staged return" % key
            )

    print(
        "\n%d evals checked, %d passed, %d failed"
        % (len(wanted), len(wanted) - len(failed_ids), len(failed_ids))
    )
    if failures:
        print("failures:")
        for line in failures:
            print("  - %s" % line)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
