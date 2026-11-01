#!/usr/bin/env python3
"""Coverage checks for the aggregate deterministic gate (tests/run_all.sh).

Run:

    python3 tests/lib/test_run_all_gate.py

The live checks compare the gate's `--list` output against the harness
directories and tests/lib/test_* files on disk, so a harness that joins the
tree without joining the gate fails here. The synthetic checks prove the
comparison's fail branch.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys

THIS = pathlib.Path(__file__).resolve().parent
REPO_ROOT = THIS.parents[1]
TESTS = REPO_ROOT / "tests"

PASS = 0
FAIL = 0


def check(label: str, condition: bool) -> None:
    global PASS, FAIL
    if condition:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def disk_harnesses() -> list[str]:
    """Every immediate tests/ child the gate's discovery rule covers."""
    names = []
    for entry in sorted(TESTS.iterdir()):
        if not entry.is_dir() or entry.name == "lib":
            continue
        if (entry / "run_all.sh").is_file():
            names.append(entry.name)
        elif (entry / "script_tests" / "run.sh").is_file():
            names.append(entry.name)
        elif (entry / "evals" / "test_run.py").is_file():
            names.append(entry.name)
        elif (entry / "evals" / "test_grade.py").is_file():
            names.append(entry.name)
    return names


def disk_lib_files() -> list[str]:
    return sorted(
        path.relative_to(REPO_ROOT).as_posix()
        for path in THIS.glob("test_*")
        if path.is_file()
    )


def parse_listing(text: str) -> tuple[list[str], dict[str, list[str]]]:
    """Split the gate's `--list` output into entries and their files."""
    entries: list[str] = []
    files: dict[str, list[str]] = {}
    current = None
    for line in text.splitlines():
        if not line.strip():
            continue
        if line[0].isspace():
            if current is not None:
                files[current].append(line.strip())
            continue
        current = line.strip()
        entries.append(current)
        files.setdefault(current, [])
    return entries, files


def compare(label: str, expected: list[str], actual: list[str]) -> list[str]:
    """Name every member either side is missing."""
    problems = []
    for name in expected:
        if name not in actual:
            problems.append(f"{label}: missing {name}")
    for name in actual:
        if name not in expected:
            problems.append(f"{label}: unexpected {name}")
    return problems


def run_gate(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "tests/run_all.sh", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )


def main() -> int:
    result = run_gate("--list")
    check("bash tests/run_all.sh --list exits 0", result.returncode == 0)

    entries, files = parse_listing(result.stdout)
    check("listing names lib exactly once", entries.count("lib") == 1)

    expected_harnesses = disk_harnesses()
    listed_harnesses = [name for name in entries if name != "lib"]
    problems = compare("harness", expected_harnesses, listed_harnesses)
    check(
        "listing matches every harness directory on disk",
        not problems,
    )
    for problem in problems:
        print(f"       {problem}")

    expected_lib = disk_lib_files()
    listed_lib = files.get("lib", [])
    problems = compare("lib file", expected_lib, listed_lib)
    check(
        "listing matches every tests/lib/test_* file on disk",
        not problems,
    )
    for problem in problems:
        print(f"       {problem}")

    narrowed = run_gate("--list", "--surface", "lib")
    narrowed_entries, _ = parse_listing(narrowed.stdout)
    check(
        "--surface lib narrows the listing to lib",
        narrowed.returncode == 0 and narrowed_entries == ["lib"],
    )

    unknown = run_gate("--surface", "no_such_surface")
    check("an unknown surface is rejected", unknown.returncode == 2)

    missing = compare("harness", ["alpha", "beta"], ["alpha"])
    check(
        "compare reports a harness that is on disk but not listed",
        missing == ["harness: missing beta"],
    )
    extra = compare("harness", ["alpha"], ["alpha", "beta"])
    check(
        "compare reports a listed harness that is not on disk",
        extra == ["harness: unexpected beta"],
    )
    missing_file = compare("lib file", ["tests/lib/test_a.py"], [])
    check(
        "compare reports a lib file that is on disk but not listed",
        missing_file == ["lib file: missing tests/lib/test_a.py"],
    )

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
