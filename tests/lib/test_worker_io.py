#!/usr/bin/env python3
"""Unit tests for worker_io — no LLM, no claude -p. Run:

    python3 tests/lib/test_worker_io.py

The case that matters is the real one: a `TimeoutExpired` raised by
`subprocess.run(..., text=True)` carries *bytes*, and the runners append their
timeout note to it. Every check below appends that note, because the append is
where the old `TypeError: can't concat str to bytes` fired.
"""

from __future__ import annotations

import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from worker_io import as_text  # noqa: E402

PASS = 0
FAIL = 0

NOTE = "\n[TIMEOUT after 900s]"


def check(label: str, cond: bool) -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def main() -> int:
    # 1. The reported crash: bytes in both streams of a real TimeoutExpired.
    exc = subprocess.TimeoutExpired(
        cmd=["claude", "-p"], timeout=900,
        output=b"partial worker output\n", stderr=b"partial worker stderr\n",
    )
    try:
        stdout = as_text(exc.stdout)
        stderr = as_text(exc.stderr) + NOTE
        raised = None
    except TypeError as err:
        stdout = stderr = ""
        raised = err
    check("bytes streams append the note without raising", raised is None)
    check("stdout decodes to text", stdout == "partial worker output\n")
    check("stderr keeps its text and the note",
          stderr == "partial worker stderr\n" + NOTE)

    # 2. A worker killed before writing anything: both attributes are None.
    empty = subprocess.TimeoutExpired(cmd=["claude", "-p"], timeout=900)
    check("None stdout becomes the empty string", as_text(empty.stdout) == "")
    check("None stderr appends the note", as_text(empty.stderr) + NOTE == NOTE)

    # 3. A completed run under text=True already hands back str.
    check("str passes through unchanged", as_text("already text") == "already text")
    check("str appends the note", as_text("out") + NOTE == "out" + NOTE)

    # 4. The deadline can cut the stream mid multi-byte sequence, so a strict
    #    decode would raise the very failure this helper prevents.
    truncated = "wrote ü".encode("utf-8")[:-1]
    try:
        got = as_text(truncated) + NOTE
        raised = None
    except UnicodeDecodeError as err:
        got = ""
        raised = err
    check("truncated UTF-8 decodes instead of raising", raised is None)
    check("truncated UTF-8 keeps the intact prefix", got.startswith("wrote "))
    check("truncated UTF-8 appends the note", got.endswith(NOTE))

    # 5. Bytes that are not UTF-8 at all still yield appendable text.
    check("non-UTF-8 bytes yield str", isinstance(as_text(b"\xff\xfe raw"), str))
    check("non-UTF-8 bytes append the note",
          (as_text(b"\xff\xfe raw") + NOTE).endswith(NOTE))

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
