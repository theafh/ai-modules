#!/usr/bin/env python3
"""Coverage checks for the aggregate deterministic gate (tests/run_all.sh).

Run:

    python3 tests/lib/test_run_all_gate.py

The live checks compare the gate's `--list` output against the harness
directories, eval files, and tests/lib/test_* files on disk, so a harness that
joins the tree without joining the gate fails here. The synthetic checks stage
one scratch harness per entrypoint shape, each with its own eval file and
counter, and prove the declaration cases: a declared eval file runs only
through its entrypoint, an undeclared one is listed as a surface the gate runs,
and a harness with an eval file and no declaration fails the gate by name.

Set RUN_ALL_GATE to point the checks at a copy of the gate, such as an
inverted-declaration copy used to prove the fail branch:

    RUN_ALL_GATE=/tmp/run_all-inverted.sh python3 tests/lib/test_run_all_gate.py
"""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass

THIS = pathlib.Path(__file__).resolve().parent
REPO_ROOT = THIS.parents[1]
TESTS = REPO_ROOT / "tests"
GATE = pathlib.Path(
    os.environ.get("RUN_ALL_GATE", str(TESTS / "run_all.sh"))
).resolve()

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


def disk_eval_files() -> list[str]:
    return sorted(
        path.relative_to(REPO_ROOT).as_posix()
        for pattern in ("test_run.py", "test_grade.py")
        for path in TESTS.glob(f"*/evals/{pattern}")
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
        ["bash", str(GATE), *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )


def run_scratch_gate(
    root: pathlib.Path, *args: str
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", "tests/run_all.sh", *args],
        cwd=root,
        capture_output=True,
        text=True,
    )


SCRIPT_DIR = 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n'

COUNTER_EVAL = (
    "from pathlib import Path\n"
    "\n"
    "counter = Path(__file__).with_name('counter')\n"
    "with counter.open('a', encoding='utf-8') as handle:\n"
    "    handle.write('run\\n')\n"
)


@dataclass(frozen=True)
class Case:
    name: str
    label: str
    entrypoint: str
    declared: bool = True
    counter: bool = True
    executable: bool = False


# One scratch harness per entrypoint shape. A declared harness names its eval
# file in covered-by-entrypoint, so the gate must run the file only through
# the entrypoint. The comment and here-doc shapes invoke nothing, so their
# declarations stay empty and their eval files stay gate-run surfaces.
CASES = [
    Case(
        "launcher",
        "launcher options",
        SCRIPT_DIR
        + 'nice -n 10 python3 "$SCRIPT_DIR/evals/test_run.py"\n'
        + "exit 0\n",
    ),
    Case(
        "direct",
        "direct execution",
        SCRIPT_DIR + '"$SCRIPT_DIR/evals/test_run.py"\n' + "exit 0\n",
        executable=True,
    ),
    Case(
        "var_path",
        "a variable-held path",
        SCRIPT_DIR
        + 'SCRIPT="$SCRIPT_DIR/evals/test_run.py"\n'
        + 'python3 "$SCRIPT"\n'
        + "exit 0\n",
    ),
    Case(
        "xargs",
        "xargs",
        SCRIPT_DIR
        + 'printf \'%s\\n\' "$SCRIPT_DIR/evals/test_run.py" | xargs python3\n'
        + "exit 0\n",
    ),
    Case(
        "literal",
        "a literal interpreter invocation",
        SCRIPT_DIR + 'python3 "$SCRIPT_DIR/evals/test_run.py"\n' + "exit 0\n",
    ),
    Case(
        "variable",
        "an interpreter held in a variable",
        SCRIPT_DIR
        + "PYTHON=python3\n"
        + '"$PYTHON" "$SCRIPT_DIR/evals/test_run.py"\n'
        + "exit 0\n",
    ),
    Case(
        "loop",
        "a for loop over the file",
        SCRIPT_DIR
        + 'for f in "$SCRIPT_DIR"/evals/test_run.py; do python3 "$f"; done\n'
        + "exit 0\n",
    ),
    Case(
        "loop_multiline",
        "a for loop split across lines",
        SCRIPT_DIR
        + 'for f in "$SCRIPT_DIR"/evals/test_run.py\n'
        + "do\n"
        + '    python3 "$f"\n'
        + "done\n"
        + "exit 0\n",
    ),
    Case(
        "semicolon",
        "a name followed by a semicolon",
        SCRIPT_DIR + 'python3 "$SCRIPT_DIR/evals/test_run.py";\n' + "exit 0\n",
    ),
    Case(
        "arith_command",
        "an arithmetic command before a real invocation",
        SCRIPT_DIR
        + "shift=1\n"
        + "(( shift = 1 << 3 ))\n"
        + 'python3 "$SCRIPT_DIR/evals/test_run.py"\n'
        + "exit 0\n",
    ),
    Case(
        "arith_multiline",
        "an arithmetic expression continued across lines",
        SCRIPT_DIR
        + "shift=$((1 +\n"
        + "    2 << 3))\n"
        + 'python3 "$SCRIPT_DIR/evals/test_run.py"\n'
        + "exit 0\n",
    ),
    Case(
        "reserved_then",
        "an invocation behind then",
        SCRIPT_DIR
        + 'if [ -d . ]; then python3 "$SCRIPT_DIR/evals/test_run.py"; fi\n'
        + "exit 0\n",
    ),
    Case(
        "reserved_do",
        "an invocation behind do",
        SCRIPT_DIR
        + 'i=0; while [ "$i" -eq 0 ]; do i=1; '
        + 'python3 "$SCRIPT_DIR/evals/test_run.py"; done\n'
        + "exit 0\n",
    ),
    Case(
        "reserved_group",
        "an invocation inside a brace group",
        SCRIPT_DIR + '{ python3 "$SCRIPT_DIR/evals/test_run.py"; }\n' + "exit 0\n",
    ),
    Case(
        "reserved_bang",
        "an invocation behind a negation",
        SCRIPT_DIR + '! python3 "$SCRIPT_DIR/evals/test_run.py"\n' + "exit 0\n",
    ),
    Case(
        "comment",
        "a comment-only entrypoint",
        "# The unit tests live in evals/test_run.py and are not run here.\n"
        + "exit 0\n",
        declared=False,
        counter=False,
    ),
    Case(
        "heredoc",
        "a here-doc usage line",
        "cat <<'USAGE'\n"
        + 'python3 "$SCRIPT_DIR/evals/test_run.py"\n'
        + "USAGE\n"
        + "exit 0\n",
        declared=False,
        counter=False,
    ),
]


def stage_case(tests: pathlib.Path, case: Case) -> None:
    harness = tests / case.name
    (harness / "evals").mkdir(parents=True)
    entry = harness / "run_all.sh"
    entry.write_text(case.entrypoint, encoding="utf-8")
    entry.chmod(0o755)
    body = COUNTER_EVAL
    if case.executable:
        body = "#!/usr/bin/env python3\n" + body
    eval_file = harness / "evals" / "test_run.py"
    eval_file.write_text(body, encoding="utf-8")
    if case.executable:
        eval_file.chmod(0o755)
    declaration = harness / "evals" / "covered-by-entrypoint"
    declaration.write_text(
        "test_run.py\n" if case.declared else "", encoding="utf-8"
    )


def counter_lines(tests: pathlib.Path, name: str) -> int:
    counter = tests / name / "evals" / "counter"
    if not counter.is_file():
        return 0
    return len(counter.read_text(encoding="utf-8").splitlines())


def synthetic_listing(
    cases: list[Case],
) -> tuple[int, dict[str, list[str]], dict[str, tuple[int, int, bool]]]:
    """Stage one scratch harness per case, list it, and run each counter case."""
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        tests = root / "tests"
        (tests / "lib").mkdir(parents=True)
        shutil.copy(GATE, tests / "run_all.sh")
        for case in cases:
            stage_case(tests, case)
        listed = run_scratch_gate(root, "--list")
        _, files = parse_listing(listed.stdout)
        runs: dict[str, tuple[int, int, bool]] = {}
        for case in cases:
            if not case.counter:
                continue
            before = {
                other.name: counter_lines(tests, other.name)
                for other in cases
                if other.counter
            }
            result = run_scratch_gate(root, "--surface", case.name)
            only_self = all(
                counter_lines(tests, other.name) == before[other.name]
                for other in cases
                if other.counter and other.name != case.name
            )
            runs[case.name] = (
                result.returncode,
                counter_lines(tests, case.name),
                only_self,
            )
    return listed.returncode, files, runs


def fail_closed_tree() -> tuple[
    subprocess.CompletedProcess[str], subprocess.CompletedProcess[str]
]:
    """A scratch tree with one eval file and no coverage declaration."""
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        tests = root / "tests"
        (tests / "lib").mkdir(parents=True)
        shutil.copy(GATE, tests / "run_all.sh")
        harness = tests / "undeclared"
        (harness / "evals").mkdir(parents=True)
        (harness / "run_all.sh").write_text("exit 0\n", encoding="utf-8")
        (harness / "evals" / "test_run.py").write_text(
            'print("unit")\n', encoding="utf-8"
        )
        listed = run_scratch_gate(root, "--list")
        full = run_scratch_gate(root)
    return listed, full


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

    listed_paths = [path for rows in files.values() for path in rows]
    missing_eval = [
        path for path in disk_eval_files() if listed_paths.count(path) != 1
    ]
    check(
        "listing names each eval file on disk exactly once",
        not missing_eval,
    )
    for path in missing_eval:
        print(f"       eval file: {path} is not named exactly once")

    narrowed = run_gate("--list", "--surface", "lib")
    narrowed_entries, _ = parse_listing(narrowed.stdout)
    check(
        "--surface lib narrows the listing to lib",
        narrowed.returncode == 0 and narrowed_entries == ["lib"],
    )

    unknown = run_gate("--surface", "no_such_surface")
    check("an unknown surface is rejected", unknown.returncode == 2)

    exit_code, synthetic, runs = synthetic_listing(CASES)
    check("a scratch tree listing exits 0", exit_code == 0)

    for case in CASES:
        eval_path = f"tests/{case.name}/evals/test_run.py"
        entry_path = f"tests/{case.name}/run_all.sh"
        check(
            f"{case.label} names its eval file exactly once",
            sum(rows.count(eval_path) for rows in synthetic.values()) == 1,
        )
        check(
            f"{case.label} names its entrypoint under its surface",
            entry_path in synthetic.get(case.name, []),
        )

    for case in CASES:
        if case.counter:
            continue
        eval_path = f"tests/{case.name}/evals/test_run.py"
        check(
            f"{case.label} lists its eval file as a gate-run surface",
            eval_path in synthetic.get(case.name, []),
        )

    for case in CASES:
        if not case.counter:
            continue
        returncode, lines, only_self = runs[case.name]
        check(f"{case.label} runs its surface cleanly", returncode == 0)
        check(
            f"{case.label} invokes its eval file exactly once",
            lines == 1,
        )
        check(
            f"{case.label} runs only its own surface",
            only_self,
        )

    listed, full = fail_closed_tree()
    declaration = "tests/undeclared/evals/covered-by-entrypoint"
    for label, result in (("--list", listed), ("a run", full)):
        check(
            f"{label} fails on a harness with an eval file and no declaration",
            result.returncode != 0,
        )
        check(
            f"{label} names the harness and the declaration it must create",
            "undeclared" in result.stderr and declaration in result.stderr,
        )
    check(
        "the fail-closed step stops the listing before it prints",
        listed.stdout == "",
    )
    check(
        "the fail-closed step stops the run before any surface runs",
        full.stdout == "",
    )

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
