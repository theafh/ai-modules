#!/usr/bin/env python3
"""Unit tests for worker_isolation that start no LLM and no worker process. Run:

    python3 tests/lib/test_worker_isolation.py
"""

from __future__ import annotations

import pathlib
import shutil
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import worker_isolation  # noqa: E402

PASS = 0
FAIL = 0


def check(label: str, cond: bool) -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def expect_refusal(label: str, root: pathlib.Path, needle: str) -> None:
    try:
        worker_isolation.raise_if_refused(root)
    except worker_isolation.CreateRootRefusal as err:
        text = str(err)
        check(label, "create-root refusal" in text and needle in text)
        return
    check(label, False)


def main() -> int:
    home_root = pathlib.Path.home() / "nl-isolation-probe"
    expect_refusal(
        "create-root refusal for a root under the home directory",
        home_root,
        "under the home directory",
    )

    git_probe = pathlib.Path(tempfile.mkdtemp(prefix="nl_iso_git_"))
    try:
        (git_probe / ".git").mkdir()
        nested = git_probe / "proj"
        nested.mkdir()
        expect_refusal(
            "create-root refusal for a root inside a git repository",
            nested,
            "inside a git repository",
        )
    finally:
        shutil.rmtree(git_probe, ignore_errors=True)

    fake_repo = pathlib.Path(tempfile.mkdtemp(prefix="nl_iso_repo_"))
    previous_tempdir = tempfile.tempdir
    try:
        (fake_repo / ".git").mkdir()
        tempfile.tempdir = str(fake_repo)
        try:
            worker_isolation.create_sandbox_root("nl_iso_")
            refused = False
        except worker_isolation.CreateRootRefusal as err:
            refused = "inside a git repository" in str(err)
        check("create_sandbox_root refuses a root inside a git repository", refused)
        leftovers = list(fake_repo.glob("nl_iso_*"))
        check("create_sandbox_root removes the refused root", not leftovers)
    finally:
        tempfile.tempdir = previous_tempdir
        shutil.rmtree(fake_repo, ignore_errors=True)

    created = worker_isolation.create_sandbox_root("nl_iso_")
    try:
        check("accepted fresh temporary root exists", created.is_dir())
        check("accepted root uses the caller prefix", created.name.startswith("nl_iso_"))
        check(
            "accepted root is the resolved path",
            created == created.resolve(),
        )
        try:
            worker_isolation.raise_if_refused(created)
            allowed = True
        except worker_isolation.CreateRootRefusal:
            allowed = False
        check("accepted root is outside home and any git repository", allowed)
    finally:
        shutil.rmtree(created, ignore_errors=True)

    keep = pathlib.Path(tempfile.mkdtemp(prefix="nl_iso_keep_"))
    keep_copy = keep / "sandbox"
    try:
        with worker_isolation.relocated_sandbox_root(
            "nl_iso_reloc_", keep_copy
        ) as root:
            live_root = root
            (root / "proj").mkdir()
            (root / "proj" / "ok.txt").write_text("kept\n")
            check("relocated root exists during the block", root.is_dir())
        check(
            "relocated helper copies the tree into keep_copy",
            (keep_copy / "proj" / "ok.txt").read_text() == "kept\n",
        )
        check(
            "relocated helper removes the temporary root",
            not live_root.exists(),
        )
    finally:
        shutil.rmtree(keep, ignore_errors=True)

    check(
        "claude isolation args",
        worker_isolation.isolation_args("claude") == ["--setting-sources", "project,local"],
    )
    check(
        "claude args ignore case",
        worker_isolation.isolation_args("Claude") == ["--setting-sources", "project,local"],
    )
    check("cursor isolation args", worker_isolation.isolation_args("cursor") == [])

    doc = worker_isolation.__doc__ or ""
    check("doc states the isolation contract", "standing-instruction files" in doc)
    check("doc names User Rules", "User Rules" in doc)
    check("doc names deployed user-level skills", "deployed user-level skills" in doc)
    check("doc states the Cursor-first posture", "preferred measurement vendor" in doc)
    check("doc states the Claude branch purpose", "output-style loading" in doc)
    check(
        "doc names the Claude inheritance pages",
        "wiki/entities/anthropic-claude-code.md" in doc
        and "wiki/concepts/verification-surfaces.md" in doc,
    )

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
