#!/usr/bin/env python3
"""Unit tests for eval_cache — no LLM, no claude -p. Run:

    python3 tests/lib/test_eval_cache.py
"""

from __future__ import annotations

import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import eval_cache  # noqa: E402

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


def make_skill(root: pathlib.Path) -> pathlib.Path:
    skill = root / "skills" / "demo"
    (skill / "scripts").mkdir(parents=True)
    (skill / "SKILL.md").write_text("# demo\nbody\n")
    (skill / "scripts" / "helper.sh").write_text("echo hi\n")
    return skill


def make_harness(root: pathlib.Path) -> pathlib.Path:
    harness = root / "evals"
    (harness / "fixtures").mkdir(parents=True)
    (harness / "evals.json").write_text('[{"id": "e1"}]\n')
    (harness / "grade.sh").write_text("exit 0\n")
    # Noise that must NOT affect the key.
    (harness / "workspace" / "run-xyz").mkdir(parents=True)
    (harness / "workspace" / "run-xyz" / "response.txt").write_text("junk\n")
    (harness / "__pycache__").mkdir()
    (harness / "__pycache__" / "run.cpython.pyc").write_text("bytecode\n")
    return harness


def key_for(skill, harness, *, model="claude-sonnet-4-6", eval_id="e1",
            prompt="do the thing") -> str:
    return eval_cache.content_key(
        source_roots=[skill], harness_dir=harness,
        model=model, eval_id=eval_id, prompt=prompt,
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as td:
        root = pathlib.Path(td)
        skill = make_skill(root)
        harness = make_harness(root)

        base = key_for(skill, harness)

        # 1. Stable across recomputation on unchanged inputs.
        check("key stable on unchanged inputs", base == key_for(skill, harness))

        # 2. Transient noise (workspace/pycache) does not move the key.
        (harness / "workspace" / "run-xyz" / "response.txt").write_text("different junk\n")
        (harness / "workspace" / "run-2").mkdir()
        check("workspace/pycache noise ignored", base == key_for(skill, harness))

        # 3. Editing skill source moves the key.
        (skill / "SKILL.md").write_text("# demo\nbody CHANGED\n")
        changed_skill = key_for(skill, harness)
        check("skill-source edit misses", base != changed_skill)

        # 3b. A bundled script edit also moves it.
        base2 = key_for(skill, harness)
        (skill / "scripts" / "helper.sh").write_text("echo bye\n")
        check("bundled-script edit misses", base2 != key_for(skill, harness))

        # 4. Editing the harness def (grade.sh) moves the key.
        base3 = key_for(skill, harness)
        (harness / "grade.sh").write_text("exit 1\n")
        check("harness-def edit misses", base3 != key_for(skill, harness))

        # 5. Model / eval_id / prompt each move the key.
        b = key_for(skill, harness)
        check("model change misses", b != key_for(skill, harness, model="claude-opus-4-8"))
        check("eval_id change misses", b != key_for(skill, harness, eval_id="e2"))
        check("prompt change misses", b != key_for(skill, harness, prompt="something else"))

        # 6. A second source root contributes to the key.
        extra = root / "skills" / "base"
        extra.mkdir(parents=True)
        (extra / "SKILL.md").write_text("# base\n")
        with_extra = eval_cache.content_key(
            source_roots=[skill, extra], harness_dir=harness,
            model="claude-sonnet-4-6", eval_id="e1", prompt="do the thing",
        )
        check("extra source root moves key", with_extra != key_for(skill, harness))

        # 7. record -> lookup round-trip (hit), and a wrong key misses.
        cache = eval_cache.EvalCache(root / ".eval_cache")
        k = key_for(skill, harness)
        check("lookup before record is a miss", cache.lookup("e1", k) is None)
        cache.record("e1", k, passed=True, model="claude-sonnet-4-6",
                     duration_s=12.5, worker_rc=0,
                     grading_output="PASS all\n", response_excerpt="hello world")
        hit = cache.lookup("e1", k)
        check("lookup after record is a hit", hit is not None)
        check("hit carries passed=True", bool(hit) and hit["passed"] is True)
        check("wrong key misses", cache.lookup("e1", "deadbeef") is None)
        check("wrong eval_id misses", cache.lookup("e2", k) is None)

        # 8. Recording a superseding key for the same eval keeps both entries.
        cache.record("e1", "otherkey", passed=False, model="m", duration_s=1.0,
                     worker_rc=1, grading_output="FAIL\n", response_excerpt="x")
        check("original entry still present after second record",
              cache.lookup("e1", k) is not None)

        # 9. LRU trim caps entries per eval id.
        for i in range(40):
            cache.record("big", f"k{i:03d}", passed=True, model="m",
                         duration_s=0.1, worker_rc=0, grading_output="", response_excerpt="")
        import json
        stored = json.loads((root / ".eval_cache" / "big.json").read_text())
        check("LRU trim caps entries", len(stored) <= eval_cache._MAX_ENTRIES_PER_EVAL)

        # 10. Corrupt cache file degrades to a miss, never raises.
        (root / ".eval_cache" / "e1.json").write_text("{ not valid json")
        check("corrupt cache file -> miss (no raise)", cache.lookup("e1", k) is None)

        # 11. write_replay_artifacts populates the run dir.
        eval_dir = root / "run" / "e1"
        eval_cache.write_replay_artifacts(eval_dir, {
            "passed": True, "grading_output": "PASS all\n",
            "response_excerpt": "hello", "graded_at": "2026-07-16T00:00:00",
            "model": "claude-sonnet-4-6", "duration_s": 12.5,
        })
        check("replay writes cached.json", (eval_dir / "cached.json").exists())
        check("replay writes grading.txt", (eval_dir / "grading.txt").read_text() == "PASS all\n")
        check("replay response banner present",
              "CACHED REPLAY" in (eval_dir / "response.txt").read_text())
        tj = json.loads((eval_dir / "timing.json").read_text())
        check("replay timing marks cached", tj.get("cached") is True)

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
