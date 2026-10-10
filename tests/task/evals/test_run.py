#!/usr/bin/env python3
"""Unit tests for the task-family runner's artefact declarations.

Some task evals grade their sandbox repository's whole `git status`: the
read-only ones through `git_tree_clean` in grade.sh, and `update_contract`
through an unscoped `git status --porcelain`. The micro-deployment writes
agents and styles into that sandbox project on at least one vendor, so every
such eval must declare neither. These checks read grade.sh for those evals,
check each one's declaration, and stage one of them for a real
micro-deployment per vendor, all without a model call.

Run:

    python3 tests/task/evals/test_run.py
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys
import tempfile

import run as runner  # puts tests/lib on sys.path for the import below
import micro_deploy

THIS = pathlib.Path(__file__).resolve().parent
PASS = 0
FAIL = 0

# A grade.sh call that reads the whole sandbox status: `git_tree_clean`, or a
# `git status --porcelain` that names no pathspec.
WHOLE_TREE_CHECK_RE = re.compile(
    r"\bgit_tree_clean\b|status --porcelain(?=\s*(?:2>|\)|\\|$))"
)


def check(label: str, condition: bool) -> None:
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


PARSER_SAMPLE = """\
case "$eval_id" in
  one|two)
    check "read-only" git_tree_clean
    ;;
  scoped)
    # names git_tree_clean only in a comment
    x="$(git -C "$proj" status --porcelain tasks/one.md)"
    ;;
  whole)
      changed="$(git -C "$proj" status --porcelain 2>/dev/null \\
                  | sort -u)"
    ;;
  *)
    ;;
esac
"""


def whole_tree_eval_ids(grade_sh: str) -> list[str]:
    """Eval ids whose grade.sh case grades the sandbox's whole git status."""
    ids: list[str] = []
    current: list[str] = []
    in_case = False
    for line in grade_sh.splitlines():
        if line.startswith('case "$eval_id" in'):
            in_case = True
            continue
        if not in_case:
            continue
        if line.startswith("esac"):
            break
        label = re.match(r"^  (\S+)\)\s*$", line)
        if label:
            current = [] if label.group(1) == "*" else label.group(1).split("|")
            continue
        if line.lstrip().startswith("#"):
            continue
        if WHOLE_TREE_CHECK_RE.search(line):
            ids.extend(i for i in current if i not in ids)
    return ids


def lands_in_sandbox_project(art_type: str) -> bool:
    """Whether the micro-deployment writes this type into the sandbox project."""
    scratch, project = pathlib.Path("/scratch"), pathlib.Path("/project")
    return any(
        project
        in micro_deploy._deployed_path(vendor, "x", art_type, scratch, project).parents
        for vendor in ("cursor", "claude")
    )


def project_scoped(names: list[str]) -> list[str]:
    """The declared names the micro-deployment writes into the sandbox project."""
    index = micro_deploy.discover_artefact_index()
    return [n for n in names if n in index and lands_in_sandbox_project(index[n][0])]


def git_status(project: pathlib.Path) -> str:
    return subprocess.run(
        ["git", "-C", str(project), "status", "--porcelain"],
        capture_output=True, text=True, check=True,
    ).stdout


def main() -> int:
    print("task evals: runner declarations")
    with open(THIS / "evals.json", encoding="utf-8") as fh:
        skills = {e["id"]: e["skill"] for e in json.load(fh)["evals"]}

    check(
        "the grade.sh reader takes git_tree_clean and an unscoped status, "
        "and skips comments and a path-scoped status",
        whole_tree_eval_ids(PARSER_SAMPLE) == ["one", "two", "whole"],
    )
    ids = whole_tree_eval_ids((THIS / "grade.sh").read_text())
    check(
        "grade.sh grades the whole sandbox status in at least one eval, "
        "each one in evals.json",
        bool(ids) and all(i in skills for i in ids),
    )
    for eval_id in ids:
        declared = runner.artefacts_for(skills.get(eval_id, ""))
        check(
            f"{eval_id}: declares no agent or style the deployment writes "
            f"into the sandbox project (got {project_scoped(declared)})",
            not project_scoped(declared),
        )

    # Fail branch of the declaration check: it flags agents and styles and
    # passes skills.
    check(
        "the declaration check flags an agent and a style and passes skills",
        project_scoped(["task_explain", "task", "auto_gate_task", "natural-language"])
        == ["auto_gate_task", "natural-language"],
    )
    for skill in sorted(runner.AGENT_SPAWNING_SKILLS):
        check(
            f"{skill} still declares every auto_*_task agent",
            set(runner.AUTO_AGENTS) <= set(runner.artefacts_for(skill)),
        )
    check(
        "task_fix still declares task_check and task_auto_check",
        {"task_check", "task_auto_check"} <= set(runner.artefacts_for("task_fix")),
    )

    # One staged read-only eval per vendor proves the declaration on the real
    # deploy script, and the agents added back prove that check can fail.
    if ids:
        eval_id = ids[0]
        declared = runner.artefacts_for(skills[eval_id])
        cases = [
            ("cursor", declared, "as declared", True),
            ("claude", declared, "as declared", True),
            ("cursor", declared + runner.AUTO_AGENTS, "with the agents added", False),
        ]
        for vendor_name, names, label, expect_clean in cases:
            with tempfile.TemporaryDirectory() as td:
                target = pathlib.Path(td) / eval_id
                target.mkdir()
                project = pathlib.Path(runner.stage(eval_id, target)["sandbox_proj"])
                before = git_status(project)
                with micro_deploy.micro_deploy(
                    vendor_name, names, project, preflight=False
                ):
                    after = git_status(project)
            outcome = "stays clean" if expect_clean else "turns dirty"
            check(
                f"{eval_id} on {vendor_name} {label}: sandbox git status {outcome}",
                before == "" and (after == "") == expect_clean,
            )

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
