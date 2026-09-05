"""Shared captured-output decoding for the local `claude -p` eval runners.

Every runner spawns its worker through `subprocess.run(..., text=True,
timeout=...)` and, on the timeout path, reads the partial output back off the
`TimeoutExpired` the call raises. That partial output is *bytes* even though
`text=True` was passed: `text=True` only governs the value `subprocess.run`
returns on a normal completion, while the exception carries whatever
`communicate()` had buffered when the deadline passed, undecoded.

Appending the runner's `[TIMEOUT after Ns]` note to those bytes raises
`TypeError: can't concat str to bytes`, which escapes the per-eval function and
`main()` alike — so one slow eval used to kill the whole run: no verdict for
itself, none for anything queued behind it, and a traceback where the graded
summary belongs. Routing the timeout path through `as_text` keeps the failure
local to the eval that earned it.

This module is the single definition every runner imports so the decoding does
not drift back into nine local copies. Unit test: tests/lib/test_worker_io.py.
"""

from __future__ import annotations


def as_text(stream) -> str:
    """Captured child output as str, whatever subprocess handed back.

    `errors="replace"` matters on the timeout path specifically: the deadline
    can cut the stream mid multi-byte sequence, and a strict decode would then
    raise the very failure this helper exists to prevent.
    """
    if stream is None:
        return ""
    if isinstance(stream, bytes):
        return stream.decode("utf-8", "replace")
    return stream
