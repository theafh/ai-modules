"""Isolate a worker or a judge from the host's standing-instruction files.

Each worker and each judge stays free of the host's standing-instruction
files that its working directory and ancestor walk would reach, because it
runs under a fresh root outside the home directory and any git repository.

Cursor is the preferred measurement vendor. The Claude branch serves
compatibility runs and Claude-only product surfaces such as output-style loading.
Two Cursor sources stay outside this helper. User Rules stay outside it,
because Cursor keeps them in its settings rather than in project files.
The other source outside it is deployed user-level skills.

The Claude inheritance evidence is `### Configuration roots` and
`### Standing instruction files` on `wiki/entities/anthropic-claude-code.md`,
and `### A worker inherits the host's instructions unless it is isolated`
on `wiki/concepts/verification-surfaces.md`.
"""

from __future__ import annotations

import pathlib
import shutil
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager


class CreateRootRefusal(RuntimeError):
    """The create-root refusal.

    The sandbox root resolves under the home directory or inside a git
    repository, so host standing-instruction files could reach the worker.
    """


def isolation_args(vendor_name: str) -> list[str]:
    """Return the worker arguments that keep host instruction sources out.

    Claude gets ``--setting-sources project,local``. Cursor's ``agent -p``
    worker is isolated by the fresh root alone, so its argument list is empty.
    """

    name = vendor_name.strip().lower()
    if name == "claude":
        return ["--setting-sources", "project,local"]
    if name == "cursor":
        return []
    message = (
        f"unsupported vendor {vendor_name!r}; choose one of: claude, cursor"
    )
    raise ValueError(message)


def _inside_git_repository(path: pathlib.Path) -> bool:
    probe = path if path.is_dir() else path.parent
    for candidate in (probe, *probe.parents):
        if (candidate / ".git").exists():
            return True
    return False


def raise_if_refused(root: pathlib.Path) -> None:
    """Raise the create-root refusal when ``root`` can see host instructions."""

    resolved = root.resolve()
    home = pathlib.Path.home().resolve()
    if resolved == home or home in resolved.parents:
        message = (
            f"create-root refusal: {resolved} resolves under the home directory"
        )
        raise CreateRootRefusal(message)
    if _inside_git_repository(resolved):
        message = (
            f"create-root refusal: {resolved} resolves inside a git repository"
        )
        raise CreateRootRefusal(message)


def create_sandbox_root(prefix: str) -> pathlib.Path:
    """Create a fresh sandbox root under the system temporary directory.

    The root comes from ``tempfile.mkdtemp`` with the caller-named prefix.
    A root that resolves under the home directory or inside any git
    repository is removed and raised as the create-root refusal.
    """

    root = pathlib.Path(tempfile.mkdtemp(prefix=prefix))
    try:
        raise_if_refused(root)
    except CreateRootRefusal:
        shutil.rmtree(root, ignore_errors=True)
        raise
    # macOS temp paths resolve through /private; callers compare against pwd.
    return root.resolve()


def preserve_sandbox_copy(root: pathlib.Path, keep_copy: pathlib.Path) -> None:
    """Copy a finished sandbox into the run directory, then remove the root.

    Call from a ``finally`` after grading the live root in place. The copy
    keeps symlinks so the run directory's ``sandbox/`` matches today's layout.
    """

    try:
        if root.exists():
            shutil.copytree(root, keep_copy, symlinks=True, dirs_exist_ok=True)
    finally:
        shutil.rmtree(root, ignore_errors=True)


@contextmanager
def relocated_sandbox_root(
    prefix: str, keep_copy: pathlib.Path
) -> Iterator[pathlib.Path]:
    """Yield an outside-checkout sandbox root, then keep a copy and remove it.

    The caller stages, runs the worker, and grades against the live root
    inside the block. On every exit path — success, cache hit, worker or
    grader failure — ``preserve_sandbox_copy`` runs.
    """

    root = create_sandbox_root(prefix)
    try:
        yield root
    finally:
        preserve_sandbox_copy(root, keep_copy)
