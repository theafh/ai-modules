#!/usr/bin/env python3
"""Grade Layer 2 pass outputs against the assertions in evals.json.

Reads each pass's TEST REPORT (written by the subagent to `report.md`) and
evaluates the assertion list for the scenario. Writes one `grading.json`
per pass directory.

Layout expected:
    workspace/run-<ts>/
        L2-1/pass-1/{report.md, response.txt, sandbox-snapshot/...}
        L2-1/pass-2/...
        L2-2/...

Run:
    python3 grade.py <run_dir>
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import pathlib
import re
import sys
from typing import Any

THIS = pathlib.Path(__file__).resolve().parent
EVALS_PATH = THIS / "evals.json"
LAYER2_ROOT = THIS  # sandboxes live alongside (L2-1/, L2-2/, ...)
REAL_HOME_WIKI = pathlib.Path.home() / "wiki"


# -----------------------------------------------------------------------------
# Report parsing
# -----------------------------------------------------------------------------

REPORT_RE = re.compile(
    r"====\s*TEST REPORT\s*====\s*\n(.*?)====\s*END REPORT\s*====",
    re.DOTALL,
)


def parse_report(text: str, extra_fields: set[str] | None = None) -> dict[str, str] | None:
    """Extract the TEST REPORT block from agent output.

    Field values that span multiple lines (e.g. files_created with a list of
    paths) are joined with newlines; everything else is a single line.

    `extra_fields` carries a scenario's declared `extra_report_fields` keys so
    scenario-specific report fields register as field starts. Without them, a
    `key: value` line whose key is not in `ALLOWED_FIELDS` is treated as a
    continuation of the field above and the scenario-specific field reads back
    empty — the recognized-field set must track what build_prompt.py injects
    into the report template per scenario.
    """
    match = REPORT_RE.search(text)
    if not match:
        return None
    allowed = ALLOWED_FIELDS | (extra_fields or set())
    body = match.group(1).strip()
    fields: dict[str, str] = {}
    current_key = None
    current_lines: list[str] = []
    for line in body.splitlines():
        m = re.match(r"^([a-z][a-z0-9_]*):\s*(.*)$", line)
        if m and m.group(1) in allowed:
            if current_key is not None:
                fields[current_key] = "\n".join(current_lines).strip()
            current_key = m.group(1)
            current_lines = [m.group(2)]
        elif current_key is not None:
            current_lines.append(line)
    if current_key is not None:
        fields[current_key] = "\n".join(current_lines).strip()
    return fields


ALLOWED_FIELDS = {
    "discovery_invoked",
    "discovery_exit",
    "discovery_resolved_path",
    "ambiguity_presented_to_user",
    "init_invoked",
    "init_target",
    "files_created",
    "files_modified",
    "linted",
    "lint_findings",
    # Sibling-skill workflow plumbing fields (wiki_import, wiki_wrapup).
    # These capture whether the agent delegated to the wiki skill's bundled
    # scripts and whether it respected the propose-then-act discipline.
    "compute_sha256_invoked",
    "wiki_page_writes_before_approval",
    "proposal_sections_emitted",
    "final_action_summary",
}


# -----------------------------------------------------------------------------
# Assertion checks
# -----------------------------------------------------------------------------


def check(assertion: dict, ctx: dict) -> tuple[bool, str]:
    """Return (passed, evidence). evidence is a one-line explanation."""
    t = assertion["type"]
    fields = ctx["report"] or {}
    # `sandbox` is where filesystem state is READ from — the per-pass snapshot
    # when one exists. `sandbox_root` is the canonical live sandbox path the
    # agent actually wrote to, so path-prefix and path-mention checks keep
    # comparing against the paths that appear in the agent's own output.
    sandbox = ctx["sandbox"]
    sandbox_root = ctx["sandbox_root"]
    response = ctx["response"]

    if t == "report_field_eq":
        actual = fields.get(assertion["field"], "")
        ok = actual.strip().lower() == assertion["expected"].strip().lower()
        return ok, f"{assertion['field']}={actual!r} (expected {assertion['expected']!r})"

    if t == "report_field_in":
        # Pass when the field's value matches any of `expected` (case-insensitive).
        # Useful when several values are semantically equivalent
        # (e.g. ambiguity_presented_to_user: "no" or "n/a" both mean "did not ask").
        actual = fields.get(assertion["field"], "").strip().lower()
        accepted = [v.strip().lower() for v in assertion["expected"]]
        ok = actual in accepted
        return ok, f"{assertion['field']}={actual!r} (must be one of {accepted})"

    if t == "report_field_contains":
        actual = fields.get(assertion["field"], "")
        ok = assertion["substr"].lower() in actual.lower()
        return ok, f"{assertion['field']}={actual!r} (must contain {assertion['substr']!r})"

    if t == "report_field_does_not_contain":
        actual = fields.get(assertion["field"], "")
        needle = assertion["needle"].lower()
        ok = needle not in actual.lower()
        return ok, f"{assertion['field']}={actual!r} (must NOT contain {assertion['needle']!r})"

    if t == "report_field_matches":
        # Case-insensitive regex match against a report field's value.
        # Lets assertions accept multiple natural phrasings — e.g. an agent
        # describing a clean lint as "0 blocking", "no blocking", or "clean"
        # all satisfy a single check.
        actual = fields.get(assertion["field"], "")
        ok = re.search(assertion["regex"], actual, re.IGNORECASE) is not None
        return ok, f"{assertion['field']}={actual!r} (must match /{assertion['regex']}/i)"

    if t == "report_field_endswith":
        actual = fields.get(assertion["field"], "").strip()
        ok = actual.endswith(assertion["suffix"])
        return ok, f"{assertion['field']}={actual!r} (must end with {assertion['suffix']!r})"

    if t == "file_exists":
        target = sandbox / assertion["path"]
        ok = target.is_file()
        return ok, f"{target} {'exists' if ok else 'missing'}"

    if t == "file_exists_and_changed":
        target = sandbox / assertion["path"]
        ok = target.is_file() and target.stat().st_size > 0
        return ok, f"{target} {'present and non-empty' if ok else 'missing or empty'}"

    if t == "file_matches_baseline":
        # Byte-identity against a checksum recorded at staging time. The
        # baseline sidecar (written by setup_scenarios.sh outside the wiki tree)
        # holds the hex sha256 of the file as staged, so this asserts the agent
        # left the file untouched — the only way to prove a "no entry written"
        # rule, which no content check can express.
        target = sandbox / assertion["path"]
        baseline_file = sandbox / assertion["baseline"]
        if not target.is_file():
            return False, f"{target} missing (cannot compare to baseline)"
        if not baseline_file.is_file():
            return False, f"baseline {baseline_file} missing — restage the sandbox"
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        expected = baseline_file.read_text().split()[0].strip()
        ok = actual == expected
        return ok, (f"{assertion['path']} byte-identical to staged baseline" if ok
                    else f"{assertion['path']} CHANGED: {actual[:12]} != staged {expected[:12]}")

    if t == "raw_sha256_matches_body":
        # Self-consistency of a raw sidecar: the recorded `sha256:` equals the
        # SHA-256 of the body (everything after the frontmatter's closing
        # `---`), computed the way compute_sha256.py computes it. This proves a
        # re-ingest refreshed the hash in step with the body it rewrote,
        # without the harness having to predict the agent's exact body bytes.
        target = sandbox / assertion["path"]
        if not target.is_file():
            return False, f"{target} missing (cannot check sha256 self-consistency)"
        text = target.read_text()
        if not text.startswith("---\n"):
            return False, f"{assertion['path']} has no frontmatter block"
        end = text.find("\n---\n", 4)
        if end == -1:
            return False, f"{assertion['path']} frontmatter block is unterminated"
        fm_block, body = text[4:end], text[end + 5:]
        m = re.search(r"^sha256\s*:([^\n]*)$", fm_block, re.MULTILINE)
        if not m:
            return False, f"{assertion['path']} carries no sha256 field"
        recorded = m.group(1).strip().strip("'\"")
        actual = hashlib.sha256(body.encode("utf-8")).hexdigest()
        ok = recorded == actual
        return ok, (f"{assertion['path']} sha256 matches its body ({actual[:12]}…)" if ok
                    else f"{assertion['path']} sha256 DRIFTED: recorded {recorded[:12]}… != body {actual[:12]}…")

    if t == "all_dirs_exist":
        missing = [p for p in assertion["paths"] if not (sandbox / p).is_dir()]
        ok = not missing
        return ok, "all dirs present" if ok else f"missing: {missing}"

    if t == "glob_absent":
        # Negation of glob_exists: NO path matches `pattern`. Used to assert a
        # page was not filed anywhere under a type folder, which a
        # path_does_not_exist check on one fixed slug cannot cover.
        matches = glob.glob(str(sandbox / assertion["pattern"]), recursive=True)
        ok = not matches
        return ok, (f"no match for {assertion['pattern']!r}" if ok
                    else f"unexpectedly matched: {matches[:3]}")

    if t == "glob_exists":
        matches = glob.glob(str(sandbox / assertion["pattern"]), recursive=True)
        ok = bool(matches)
        return ok, (f"matched: {matches[:3]}" if ok else f"no match for {assertion['pattern']!r}")

    if t == "glob_file_contains":
        # Filesystem ground-truth: at least one file matching `pattern` (glob,
        # relative to the sandbox) has content matching `regex` (case-insensitive,
        # `(?m)` supported inline). Stronger than a self-reported report field for
        # verifying the content a produced file actually carries.
        matches = glob.glob(str(sandbox / assertion["pattern"]), recursive=True)
        regex = assertion["regex"]
        hits = []
        for m in matches:
            try:
                if re.search(regex, pathlib.Path(m).read_text(), re.IGNORECASE):
                    hits.append(m)
            except OSError:
                continue
        ok = bool(hits)
        return ok, (f"content /{regex}/ in: {hits[:3]}" if ok
                    else f"no file matching {assertion['pattern']!r} contains /{regex}/")

    if t == "glob_file_absent_content":
        # Filesystem ground-truth negation: NO file matching `pattern` contains
        # `regex`. Passes when the glob matches nothing or no match carries the
        # content — used to assert a produced file does NOT carry something (e.g.
        # a machine-local absolute path). Pair with glob_exists to also require
        # the file to be present.
        matches = glob.glob(str(sandbox / assertion["pattern"]), recursive=True)
        regex = assertion["regex"]
        offenders = []
        for m in matches:
            try:
                if re.search(regex, pathlib.Path(m).read_text(), re.IGNORECASE):
                    offenders.append(m)
            except OSError:
                continue
        ok = not offenders
        return ok, (f"no file carries /{regex}/" if ok
                    else f"content /{regex}/ unexpectedly in: {offenders[:3]}")

    if t == "path_does_not_exist":
        target = sandbox / assertion["path"]
        ok = not target.exists()
        return ok, f"{target} {'absent' if ok else 'present (should be absent)'}"

    if t == "no_files_outside_sandbox":
        # The agent should not have written anywhere outside the sandbox.
        # We approximate by checking files_created / files_modified report
        # fields — every absolute path listed should be inside `sandbox`.
        offenders = []
        for raw in (fields.get("files_created", ""), fields.get("files_modified", "")):
            for line in raw.splitlines():
                line = line.strip()
                if not line or line.lower() == "none":
                    continue
                if not line.startswith(str(sandbox_root)):
                    offenders.append(line)
        ok = not offenders
        return ok, "no leak" if ok else f"reported writes outside sandbox: {offenders}"

    if t == "real_home_wiki_absent":
        ok = not REAL_HOME_WIKI.exists()
        return ok, f"~/wiki {'absent' if ok else 'PRESENT — leak from a test'}"

    if t == "response_text_does_not_match":
        ok = re.search(assertion["regex"], response) is None
        return ok, f"regex {assertion['regex']!r} {'absent' if ok else 'matched (must not appear)'}"

    if t == "response_text_matches":
        ok = re.search(assertion["regex"], response) is not None
        return ok, f"regex {assertion['regex']!r} {'matched' if ok else 'NOT matched'}"

    if t == "response_text_contains":
        ok = assertion["needle"] in response
        return ok, f"{assertion['needle']!r} {'present' if ok else 'NOT in response'}"

    if t == "response_text_contains_path":
        subpath = assertion["subpath"]
        full = str(sandbox_root / subpath)
        ok = full in response
        return ok, f"{full} {'mentioned' if ok else 'NOT mentioned in response'}"

    return False, f"unknown assertion type: {t}"


# -----------------------------------------------------------------------------
# Driver
# -----------------------------------------------------------------------------


def grade_pass(pass_dir: pathlib.Path, scenario: dict) -> dict:
    report_file = pass_dir / "report.md"
    response_file = pass_dir / "response.txt"
    timing_file = pass_dir / "timing.json"

    response_text = response_file.read_text() if response_file.is_file() else ""
    report_text = report_file.read_text() if report_file.is_file() else response_text

    # A scenario's `extra_report_fields` (declared in evals.json, injected into
    # the report template by build_prompt.py) name scenario-specific fields the
    # agent fills. Feed their keys to the parser so they register as fields
    # rather than being swallowed as continuation lines of the field above.
    extra_field_keys = {
        key
        for entry in scenario.get("extra_report_fields", [])
        if ":" in entry
        for key in [entry.split(":", 1)[0].strip()]
        if re.match(r"^[a-z][a-z0-9_]*$", key)
    }
    parsed = parse_report(report_text, extra_field_keys)
    sandbox_root = LAYER2_ROOT / scenario["sandbox_path"]
    # Prefer this pass's own snapshot; the live sandbox has been restaged for
    # the next pass and reflects only the most recent run.
    snapshot = pass_dir / "sandbox-snapshot"
    sandbox = snapshot if snapshot.is_dir() else sandbox_root

    ctx = {
        "report": parsed,
        "sandbox": sandbox,
        "sandbox_root": sandbox_root,
        "response": response_text,
    }

    # Worker-completion gate. A pass is trustworthy only if the claude -p worker
    # exited cleanly (rc 0) and produced a response. A timeout (rc -1) or crash
    # leaves partial/empty state that must not grade as a pass — an
    # absence-dominated scenario (path_does_not_exist, response_text_does_not_match,
    # real_home_wiki_absent) would otherwise pass a no-op worker. This tightens the
    # final `passed` without touching per-assertion pass_rate, so the aggregate
    # regression baseline is unperturbed.
    worker_rc = None
    if timing_file.is_file():
        try:
            worker_rc = json.loads(timing_file.read_text()).get("claude_rc")
        except (ValueError, OSError):
            worker_rc = None
    worker_ok = worker_rc == 0 and bool(response_text.strip())

    expectations = []
    passed_count = 0
    for assertion in scenario["assertions"]:
        passed, evidence = check(assertion, ctx)
        expectations.append({
            "text": f"[{assertion['id']}] {assertion['type']}",
            "passed": passed,
            "evidence": evidence,
        })
        if passed:
            passed_count += 1

    all_assertions_pass = (
        passed_count == len(scenario["assertions"]) if scenario["assertions"] else True
    )

    return {
        "scenario_id": scenario["id"],
        "scenario_name": scenario["name"],
        "report_parsed": parsed is not None,
        "worker_ok": worker_ok,
        "worker_rc": worker_rc,
        "expectations": expectations,
        "pass_rate": passed_count / len(scenario["assertions"]) if scenario["assertions"] else 0.0,
        "passed": all_assertions_pass and worker_ok,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir", help="workspace/run-<ts>/ directory to grade")
    args = parser.parse_args()

    run_dir = pathlib.Path(args.run_dir).resolve()
    evals = json.loads(EVALS_PATH.read_text())
    scenarios = {e["id"]: e for e in evals["evals"]}

    summary = []
    for scenario in evals["evals"]:
        sid = scenario["id"]
        scen_dir = run_dir / sid
        if not scen_dir.is_dir():
            print(f"  WARNING: missing scenario dir {scen_dir}", file=sys.stderr)
            continue
        for pass_dir in sorted(scen_dir.glob("pass-*")):
            result = grade_pass(pass_dir, scenario)
            (pass_dir / "grading.json").write_text(json.dumps(result, indent=2))
            summary.append({
                "scenario_id": sid,
                "pass": pass_dir.name,
                "pass_rate": result["pass_rate"],
                "passed": result["passed"],
            })
            mark = "PASS" if result["passed"] else "FAIL"
            note = ("" if result.get("worker_ok", True)
                    else f"  [worker rc={result.get('worker_rc')} — did not complete]")
            print(f"  [{mark}] {sid} {pass_dir.name}: {result['pass_rate']:.1%}{note}")

    (run_dir / "grading_summary.json").write_text(json.dumps(summary, indent=2))
    print(f"\nGraded {len(summary)} pass(es). Summary: {run_dir}/grading_summary.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
