#!/usr/bin/env python3
"""Check that an eval runner's stage() stops on a failed or empty stage.

Each Pattern A runner stages a fixture by running
`out="$(stage.sh <id> <target>)" || exit $?; eval "$out"; printf ...` under
`bash -c` and reading the printed values back. Before that guard, a failed
stage.sh left `eval` an empty string, the script still reached its `printf`,
and the runner got an empty sandbox path. pathlib.Path("") is the current
directory, so the worker would have started in the repository checkout.

This check imports `<evals_dir>/run.py`, points its STAGE at two stand-in
stagers, and calls stage() with each. One stager prints an error and exits 3;
the other exits 0 and prints nothing, so every staged value is empty. The check
passes only when both calls raise RuntimeError, the first naming the failed
stage.sh and the second the missing sandbox, before any worker could start.

Usage:
    python3 tests/lib/check_stage_guard.py <evals_dir>

Prints one line per attempt and exits 0 only when both raised as expected.
"""

from __future__ import annotations

import inspect
import os
import pathlib
import sys
import tempfile

STAGE_ID = "stage-guard"

ATTEMPTS = (
    (
        "failed stage",
        "#!/usr/bin/env bash\necho 'fixture setup failed' >&2\nexit 3\n",
        "stage.sh failed for",
    ),
    (
        "empty stage",
        "#!/usr/bin/env bash\nexit 0\n",
        "stage.sh staged no sandbox",
    ),
)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: check_stage_guard.py <evals_dir>", file=sys.stderr)
        return 2
    evals_dir = pathlib.Path(sys.argv[1]).resolve()
    sys.path.insert(0, str(evals_dir))
    import run  # noqa: PLC0415  (the runner under test, found on sys.path)

    extra = (
        [dict(os.environ)]
        if "env" in inspect.signature(run.stage).parameters
        else []
    )
    ok = True
    with tempfile.TemporaryDirectory(prefix="stage_guard_") as tmp:
        root = pathlib.Path(tmp)
        for label, body, expected in ATTEMPTS:
            stager = root / f"{label.replace(' ', '_')}.sh"
            stager.write_text(body)
            stager.chmod(0o755)
            run.STAGE = stager
            try:
                staged = run.stage(STAGE_ID, root / "target", *extra)
            except RuntimeError as exc:
                message = str(exc)
                if expected in message:
                    print(f"ok   {label}: raised: {message}")
                else:
                    ok = False
                    print(f"FAIL {label}: raised without {expected!r}: {message}")
            else:
                ok = False
                print(f"FAIL {label}: returned {staged!r}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
