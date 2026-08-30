"""Content-addressed cache for the expensive behavioral eval runners.

The Pattern-A behavioral evals (`tests/<skill>/evals/run.py`) each spawn one
`claude -p` worker per eval — the slow, token-expensive part of a run. When a
runner is invoked again with nothing changed, re-spawning those workers pays
the full LLM bill to re-derive a verdict already in hand. This module lets a
runner skip the worker (and the re-grade) for an eval whose inputs have not
changed since a prior graded run, replaying that run's deterministic verdict.

"Inputs" for an eval are hashed by content, so the key changes — and the cache
misses, forcing a fresh run — whenever any of them changes:

- the skill source under test and its family dependencies (`source_roots`),
- the harness definition (the `evals/` dir: evals.json, stage.sh, grade.sh,
  fixtures, run.py),
- the worker model, the eval id, and the prompt.

Because every hashed input feeds the key, the cache can never serve a stale
pass: change anything the worker or the grade depends on and the key moves.
A hit means the inputs are byte-identical to a run we already graded. This is
the mechanical backstop for the base `task` skill's verification-economy rule —
"re-run only when the inputs changed" — applied to the one surface where the
waste is dramatic. It trades LLM-sampling variance (a second sample of an
unchanged distribution) for cost; a runner's `--force` re-runs and refreshes
the entry when a fresh sample is wanted, and `--no-cache` bypasses it entirely.

This is local, gitignored test tooling; it stores nothing that ships.
"""

from __future__ import annotations

import datetime
import hashlib
import json
import pathlib

# Directory names never relevant to an eval's inputs — transient run output,
# the cache itself, Python bytecode, VCS and dependency trees.
_SKIP_DIRS = {
    "__pycache__", ".eval_cache", "workspace", "scratch", "results",
    ".git", "node_modules",
}
_SKIP_FILE_NAMES = {".DS_Store"}
_SKIP_SUFFIXES = {".pyc", ".pyo"}

# How much of the worker response to keep for operator inspection on a hit.
RESPONSE_EXCERPT_CHARS = 4000

# Cap entries per eval id so a long-lived cache file cannot grow without bound
# as skill content and models vary over time.
_MAX_ENTRIES_PER_EVAL = 12


def _iter_files(root: pathlib.Path):
    """Yield (relname, path) for every content file under `root`.

    `root` may be a single file (yields it by its bare name) or a directory
    (walked recursively, sorted, with the skip lists applied). relname is
    POSIX-relative to `root`, so the same content hashes identically wherever
    the tree physically sits.
    """
    root = pathlib.Path(root)
    if root.is_file():
        yield root.name, root
        return
    if not root.is_dir():
        return
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root)
        if set(rel.parts[:-1]) & _SKIP_DIRS:
            continue
        if path.name in _SKIP_FILE_NAMES or path.suffix in _SKIP_SUFFIXES:
            continue
        yield rel.as_posix(), path


def _tree_hash(root: pathlib.Path) -> str:
    """Stable content hash of a file or directory tree."""
    digest = hashlib.sha256()
    for relname, path in _iter_files(root):
        digest.update(relname.encode())
        digest.update(b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).hexdigest().encode())
        digest.update(b"\0")
    return digest.hexdigest()


def content_key(
    *,
    source_roots,
    harness_dir,
    model: str,
    eval_id: str,
    prompt: str,
) -> str:
    """Compute the cache key for one eval from everything that determines its
    verdict. `source_roots` is an iterable of skill/agent dirs (or files) the
    worker's behavior depends on; `harness_dir` is the `evals/` dir defining
    how the eval is staged and graded.
    """
    digest = hashlib.sha256()
    # Label each source root by basename so moving content between roots, or
    # renaming a root, changes the key.
    for root in source_roots:
        root = pathlib.Path(root)
        digest.update(b"root:")
        digest.update(root.name.encode())
        digest.update(b"\0")
        digest.update(_tree_hash(root).encode())
        digest.update(b"\0")
    digest.update(b"harness\0")
    digest.update(_tree_hash(pathlib.Path(harness_dir)).encode())
    digest.update(b"\0")
    digest.update(("model=" + (model or "<cli-default>")).encode())
    digest.update(b"\0")
    digest.update(("eval=" + eval_id).encode())
    digest.update(b"\0")
    digest.update(("prompt=" + prompt).encode())
    digest.update(b"\0")
    return digest.hexdigest()


def _now_iso() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


class EvalCache:
    """Per-harness verdict cache stored as one small JSON file per eval id
    under `cache_dir` (default `<evals>/.eval_cache`). Each file maps a content
    key to the graded verdict recorded for it.
    """

    def __init__(self, cache_dir):
        self.dir = pathlib.Path(cache_dir)

    def _file(self, eval_id: str) -> pathlib.Path:
        safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in eval_id)
        return self.dir / f"{safe}.json"

    def _load(self, eval_id: str) -> dict:
        path = self._file(eval_id)
        if not path.exists():
            return {}
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            return {}
        return data if isinstance(data, dict) else {}

    def lookup(self, eval_id: str, key: str):
        """Return the stored verdict entry for (eval_id, key), or None."""
        return self._load(eval_id).get(key)

    def record(
        self,
        eval_id: str,
        key: str,
        *,
        passed: bool,
        model: str,
        duration_s: float,
        worker_rc: int,
        grading_output: str,
        response_excerpt: str,
    ) -> dict:
        """Store (and return) the verdict entry for (eval_id, key)."""
        entry = {
            "passed": bool(passed),
            "model": model,
            "duration_s": round(duration_s, 3),
            "worker_rc": worker_rc,
            "graded_at": _now_iso(),
            "grading_output": grading_output,
            "response_excerpt": response_excerpt[:RESPONSE_EXCERPT_CHARS],
        }
        data = self._load(eval_id)
        data[key] = entry
        if len(data) > _MAX_ENTRIES_PER_EVAL:
            keep = sorted(
                data.items(),
                key=lambda kv: kv[1].get("graded_at", ""),
                reverse=True,
            )[:_MAX_ENTRIES_PER_EVAL]
            data = dict(keep)
        self.dir.mkdir(parents=True, exist_ok=True)
        tmp = self._file(eval_id).with_suffix(".json.tmp")
        tmp.write_text(json.dumps(data, indent=2, sort_keys=True))
        tmp.replace(self._file(eval_id))
        return entry


def write_replay_artifacts(eval_dir, entry: dict) -> None:
    """On a cache hit, populate the per-eval run dir from the stored entry so a
    replayed run leaves the same file shape as a fresh one — with a clear banner
    that no worker ran this time.
    """
    eval_dir = pathlib.Path(eval_dir)
    eval_dir.mkdir(parents=True, exist_ok=True)
    (eval_dir / "cached.json").write_text(json.dumps(entry, indent=2, sort_keys=True))
    (eval_dir / "grading.txt").write_text(entry.get("grading_output", ""))
    banner = (
        "[CACHED REPLAY — no claude -p worker ran this time because the eval's\n"
        "inputs were unchanged since the grade below. What follows is an excerpt\n"
        "of the prior run's response; re-run with --force for a full fresh one.]\n\n"
    )
    (eval_dir / "response.txt").write_text(banner + entry.get("response_excerpt", ""))
    (eval_dir / "timing.json").write_text(json.dumps({
        "eval_id": eval_dir.name,
        "cached": True,
        "graded_at": entry.get("graded_at"),
        "model": entry.get("model"),
        "duration_s_original": entry.get("duration_s"),
    }, indent=2))
