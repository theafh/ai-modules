#!/usr/bin/env python3
"""Unit tests for eval_cache — no LLM, no claude -p. Run:

    python3 tests/lib/test_eval_cache.py
"""

from __future__ import annotations

import ast
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import eval_cache  # noqa: E402

PASS = 0
FAIL = 0

# Every split fixture binds eval_id from $1 before its first case block, the
# id-binding precondition eval_cache requires before it splits a grader.
BIND = 'eval_id="${1:?eval id required}"\n'


def check(label: str, cond: bool) -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def make_skill(root: pathlib.Path, body: str | None = None) -> pathlib.Path:
    skill = root / "skills" / "demo"
    (skill / "scripts").mkdir(parents=True)
    if body is None:
        body = (
            "<demo_skill>\n"
            "  <alpha>alpha-body</alpha>\n"
            "  <beta>beta-body</beta>\n"
            "</demo_skill>\n"
        )
    (skill / "SKILL.md").write_text(body)
    (skill / "scripts" / "helper.sh").write_text("echo hi\n")
    return skill


def make_harness(root: pathlib.Path, grade: str | None = None) -> pathlib.Path:
    harness = root / "evals"
    (harness / "fixtures").mkdir(parents=True)
    (harness / "evals.json").write_text('[{"id": "e1"}]\n')
    if grade is None:
        grade = (
            "#!/bin/bash\n"
            "eval_id=\"${1:?eval id required}\"\n"
            "shared_pred() { true; }\n"
            "case \"$eval_id\" in\n"
            "  e1)\n"
            "    echo arm-e1\n"
            "    ;;\n"
            "  e2)\n"
            "    echo arm-e2\n"
            "    ;;\n"
            "esac\n"
        )
    (harness / "grade.sh").write_text(grade)
    # Noise that must NOT affect the key.
    (harness / "workspace" / "run-xyz").mkdir(parents=True)
    (harness / "workspace" / "run-xyz" / "response.txt").write_text("junk\n")
    (harness / "__pycache__").mkdir()
    (harness / "__pycache__" / "run.cpython.pyc").write_text("bytecode\n")
    return harness


def independent_harness_digest(harness: pathlib.Path, grade_bytes: bytes) -> str:
    """The harness digest in `_tree_hash`'s per-file form, with the top-level
    grade.sh contributing `grade_bytes` and every other path its own bytes."""
    digest = hashlib.sha256()
    for relname, path in eval_cache._iter_files(harness):
        content = grade_bytes if relname == "grade.sh" else path.read_bytes()
        digest.update(relname.encode())
        digest.update(b"\0")
        digest.update(hashlib.sha256(content).hexdigest().encode())
        digest.update(b"\0")
    return digest.hexdigest()


def independent_no_decl_key(roots, harness, grade_bytes, helper_dir, *,
                            model, eval_id, prompt) -> str:
    """A no-declaration key built without `content_key`: each root's label and
    `_tree_hash`, the harness digest, each helper's `_tree_hash`, then the
    model, eval id, and prompt fields."""
    digest = hashlib.sha256()
    for root in roots:
        digest.update(b"root:" + root.name.encode() + b"\0")
        digest.update(eval_cache._tree_hash(root).encode() + b"\0")
    digest.update(b"harness\0")
    digest.update(independent_harness_digest(harness, grade_bytes).encode() + b"\0")
    for name in eval_cache.VERDICT_HELPERS:
        digest.update(b"helper:" + name.encode() + b"\0")
        digest.update(eval_cache._tree_hash(helper_dir / name).encode() + b"\0")
    for field in ("model=" + model, "eval=" + eval_id, "prompt=" + prompt):
        digest.update(field.encode() + b"\0")
    return digest.hexdigest()


def bash_arm_markers(grade: str, eval_id: str) -> list[str]:
    """Run a fixture grader in bash for `eval_id` and return the `*-body`
    markers its arms print, so bash itself says which arm text runs."""
    out = subprocess.run(
        ["bash", "-O", "extglob", "-c", grade, "grader", eval_id],
        env={"eval_id": eval_id, "PATH": os.environ.get("PATH", "/usr/bin:/bin")},
        capture_output=True, text=True,
    ).stdout
    return [word for word in out.split() if word.endswith("-body")]


def _call_name(func) -> str | None:
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return None


def _is_evals_json_path(node, assigns: dict) -> bool:
    """`<dir> / "evals.json"`, or a module-level name bound to one."""
    if (isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div)
            and isinstance(node.right, ast.Constant)
            and node.right.value == "evals.json"):
        return True
    if isinstance(node, ast.Name) and node.id in assigns:
        return _is_evals_json_path(assigns[node.id], {})
    return False


def content_key_forwarding_problems(src: str) -> tuple[int, list[str]]:
    """Return (content_key call count, problems) for one runner's source.

    Every `content_key(...)` call must pass `dependencies=` as one of the two
    forms the Pattern A runners use: `dependencies_for(<evals.json path>,
    <the call's own eval_id= value>)` or `<spec>.get("dependencies")`. A
    missing keyword, `dependencies=None`, a declaration computed but not
    passed, one named only in a comment, or one read for another eval id is
    a problem.
    """
    tree = ast.parse(src)
    assigns = {
        target.id: node.value
        for node in tree.body if isinstance(node, ast.Assign)
        for target in node.targets if isinstance(target, ast.Name)
    }
    calls = [node for node in ast.walk(tree)
             if isinstance(node, ast.Call) and _call_name(node.func) == "content_key"]
    problems = []
    for call in calls:
        keywords = {k.arg: k.value for k in call.keywords if k.arg}
        dep, eval_id = keywords.get("dependencies"), keywords.get("eval_id")
        if dep is None:
            problems.append(f"line {call.lineno}: content_key() has no dependencies=")
            continue
        forwards = False
        if isinstance(dep, ast.Call) and _call_name(dep.func) == "dependencies_for":
            forwards = (len(dep.args) == 2 and not dep.keywords and eval_id is not None
                        and _is_evals_json_path(dep.args[0], assigns)
                        and ast.dump(dep.args[1]) == ast.dump(eval_id))
        elif (isinstance(dep, ast.Call) and isinstance(dep.func, ast.Attribute)
              and dep.func.attr == "get" and isinstance(dep.func.value, ast.Name)
              and len(dep.args) == 1 and not dep.keywords
              and isinstance(dep.args[0], ast.Constant)
              and dep.args[0].value == "dependencies"):
            forwards = True
        if not forwards:
            problems.append(f"line {call.lineno}: dependencies={ast.unparse(dep)} "
                            "does not forward this eval's declaration")
    return len(calls), problems


def key_for(skill, harness, *, model="claude-sonnet-4-6", eval_id="e1",
            prompt="do the thing", dependencies=None) -> str:
    return eval_cache.content_key(
        source_roots=[skill], harness_dir=harness,
        model=model, eval_id=eval_id, prompt=prompt,
        dependencies=dependencies,
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
        (skill / "SKILL.md").write_text(
            "<demo_skill>\n  <alpha>CHANGED</alpha>\n  <beta>beta-body</beta>\n"
            "</demo_skill>\n"
        )
        changed_skill = key_for(skill, harness)
        check("skill-source edit misses", base != changed_skill)

        # 3b. A bundled script edit also moves it.
        base2 = key_for(skill, harness)
        (skill / "scripts" / "helper.sh").write_text("echo bye\n")
        check("bundled-script edit misses", base2 != key_for(skill, harness))

        # 4. Editing the harness def (grade.sh) moves the key.
        base3 = key_for(skill, harness)
        grade_text = (harness / "grade.sh").read_text()
        (harness / "grade.sh").write_text(grade_text + "# touched\n")
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

        # 6b. The shared verdict helpers feed every key: an edit to one moves
        # it, and an edit to a tests/lib file outside the list does not.
        helper_dir = root / "lib"
        helper_dir.mkdir()
        for name in eval_cache.VERDICT_HELPERS:
            (helper_dir / name).write_text(f"# {name}\n")
        (helper_dir / "test_unrelated.py").write_text("# unit test\n")
        real_helper_dir = eval_cache._HELPER_DIR
        eval_cache._HELPER_DIR = helper_dir
        try:
            check("key stable on unchanged helpers",
                  key_for(skill, harness) == key_for(skill, harness))
            for name in eval_cache.VERDICT_HELPERS:
                before = {e: key_for(skill, harness, eval_id=e) for e in ("e1", "e2")}
                (helper_dir / name).write_text(f"# {name} CHANGED\n")
                for e in ("e1", "e2"):
                    check(f"verdict-helper edit misses ({name}, {e})",
                          before[e] != key_for(skill, harness, eval_id=e))
            before = {e: key_for(skill, harness, eval_id=e) for e in ("e1", "e2")}
            (helper_dir / "test_unrelated.py").write_text("# unit test CHANGED\n")
            for e in ("e1", "e2"):
                check(f"an edit outside VERDICT_HELPERS keeps the key ({e})",
                      before[e] == key_for(skill, harness, eval_id=e))
        finally:
            eval_cache._HELPER_DIR = real_helper_dir
        # A subset, so a helper that joins the list later needs no test edit.
        check(
            "the helper list names the deployment and read check, the worker "
            "command, and the host tasks/ guard",
            {"micro_deploy.py", "vendor.py", "host_tasks_guard.sh"}
            <= set(eval_cache.VERDICT_HELPERS),
        )
        check(
            "every listed helper exists beside eval_cache, so a rename cannot "
            "drop it from the key",
            all((real_helper_dir / name).is_file() for name in eval_cache.VERDICT_HELPERS),
        )

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

        # --- Acceptance 1: no-declaration baseline + grade.sh arm-split ---
        skill_a = make_skill(root / "a")
        harness_a = make_harness(root / "a")
        grade_a = (harness_a / "grade.sh").read_text()
        # The fixture grader makes the split explicit: each eval keeps its own
        # arm and the shared region, and loses exactly the other eval's arm.
        expected_grade = {
            "e1": grade_a.replace("e2)\n    echo arm-e2\n    ;;", "").encode(),
            "e2": grade_a.replace("e1)\n    echo arm-e1\n    ;;", "").encode(),
        }
        for e in ("e1", "e2"):
            check(f"no-decl arm-split contribution is the explicit split ({e})",
                  eval_cache.grade_sh_contribution(grade_a, e) == expected_grade[e])
        # With grade.sh hashed whole, the per-file harness digest built here is
        # today's whole-tree hash, so every other harness path keeps today's
        # contribution once grade.sh follows the split.
        check("independent harness digest is today's _tree_hash form",
              independent_harness_digest(harness_a, grade_a.encode())
              == eval_cache._tree_hash(harness_a))
        a_helper_dir = root / "a_lib"
        a_helper_dir.mkdir()
        for name in eval_cache.VERDICT_HELPERS:
            (a_helper_dir / name).write_text(f"# {name}\n")
        real_helper_dir = eval_cache._HELPER_DIR
        eval_cache._HELPER_DIR = a_helper_dir
        try:
            no_decl = {e: key_for(skill_a, harness_a, eval_id=e) for e in ("e1", "e2")}
            check("no-decl arm-split: e1 and e2 keys differ",
                  no_decl["e1"] != no_decl["e2"])
            for e in ("e1", "e2"):
                check(f"no-decl key equals the independently built digest ({e})",
                      no_decl[e] == independent_no_decl_key(
                          [skill_a], harness_a, expected_grade[e], a_helper_dir,
                          model="claude-sonnet-4-6", eval_id=e,
                          prompt="do the thing"))
            for name in eval_cache.VERDICT_HELPERS:
                (a_helper_dir / name).write_text(f"# {name} CHANGED\n")
                for e in ("e1", "e2"):
                    moved = key_for(skill_a, harness_a, eval_id=e)
                    check(f"helper edit moves the no-decl key ({name}, {e})",
                          moved != no_decl[e])
                    check(f"helper contribution is today's _tree_hash ({name}, {e})",
                          moved == independent_no_decl_key(
                              [skill_a], harness_a, expected_grade[e],
                              a_helper_dir, model="claude-sonnet-4-6",
                              eval_id=e, prompt="do the thing"))
                    no_decl[e] = moved
        finally:
            eval_cache._HELPER_DIR = real_helper_dir
        pinned = key_for(skill_a, harness_a, eval_id="e1")
        # Skill root still whole-tree: edit any stage moves the no-decl key.
        (skill_a / "SKILL.md").write_text(
            "<demo_skill>\n  <alpha>alpha-body</alpha>\n"
            "  <beta>beta-CHANGED</beta>\n</demo_skill>\n"
        )
        check("no-decl skill whole-tree: undeclared-looking stage still misses",
              pinned != key_for(skill_a, harness_a, eval_id="e1"))
        # Restore and confirm evals.json (non-grade.sh harness path) moves every key.
        skill_a = make_skill(root / "a2")
        harness_a = make_harness(root / "a2")
        before_json = key_for(skill_a, harness_a, eval_id="e1")
        before_json_e2 = key_for(skill_a, harness_a, eval_id="e2")
        (harness_a / "evals.json").write_text('[{"id": "e1"}, {"id": "e2"}]\n')
        check("evals.json edit misses e1",
              before_json != key_for(skill_a, harness_a, eval_id="e1"))
        check("evals.json edit misses e2",
              before_json_e2 != key_for(skill_a, harness_a, eval_id="e2"))

        # --- Acceptance 2: malformed declaration == no-decl baseline ---
        skill_b = make_skill(root / "b")
        harness_b = make_harness(root / "b")
        baseline = key_for(skill_b, harness_b)
        for bad in ("not-a-map", ["alpha"], {"demo": "alpha"}, {"demo": [1]},
                    {"": ["alpha"]}, None):
            check(
                f"malformed dependencies matches no-decl ({bad!r})",
                baseline == key_for(skill_b, harness_b, dependencies=bad),
            )

        # --- Acceptance 3: declared stage narrow ---
        skill_c = make_skill(root / "c")
        harness_c = make_harness(root / "c")
        deps = {"demo": ["alpha"]}
        k_decl = key_for(skill_c, harness_c, dependencies=deps)
        (skill_c / "SKILL.md").write_text(
            "<demo_skill>\n  <alpha>alpha-body</alpha>\n"
            "  <beta>beta-CHANGED</beta>\n</demo_skill>\n"
        )
        check("undeclared sibling stage keeps key",
              k_decl == key_for(skill_c, harness_c, dependencies=deps))
        (skill_c / "SKILL.md").write_text(
            "<demo_skill>\n  <alpha>alpha-CHANGED</alpha>\n"
            "  <beta>beta-CHANGED</beta>\n</demo_skill>\n"
        )
        check("declared stage change misses",
              k_decl != key_for(skill_c, harness_c, dependencies=deps))

        # Multi-root: sibling basename in dependencies — undeclared stage there
        # keeps the key; absent sibling basename keeps whole-tree for that root.
        skill_d = make_skill(root / "d")
        sib = root / "d" / "skills" / "sib"
        sib.mkdir(parents=True)
        (sib / "SKILL.md").write_text(
            "<sib_skill>\n  <one>1</one>\n  <two>2</two>\n</sib_skill>\n"
        )
        harness_d = make_harness(root / "d")
        multi_deps = {"demo": ["alpha"], "sib": ["one"]}
        k_multi = eval_cache.content_key(
            source_roots=[skill_d, sib], harness_dir=harness_d,
            model="m", eval_id="e1", prompt="p", dependencies=multi_deps,
        )
        (sib / "SKILL.md").write_text(
            "<sib_skill>\n  <one>1</one>\n  <two>2CHANGED</two>\n</sib_skill>\n"
        )
        check(
            "multi-root: undeclared stage under declared sibling keeps key",
            k_multi == eval_cache.content_key(
                source_roots=[skill_d, sib], harness_dir=harness_d,
                model="m", eval_id="e1", prompt="p", dependencies=multi_deps,
            ),
        )
        # Restore sib; omit sib from deps → whole-tree for sib.
        (sib / "SKILL.md").write_text(
            "<sib_skill>\n  <one>1</one>\n  <two>2</two>\n</sib_skill>\n"
        )
        deps_omit_sib = {"demo": ["alpha"]}
        k_omit = eval_cache.content_key(
            source_roots=[skill_d, sib], harness_dir=harness_d,
            model="m", eval_id="e1", prompt="p", dependencies=deps_omit_sib,
        )
        (sib / "SKILL.md").write_text(
            "<sib_skill>\n  <one>1</one>\n  <two>2CHANGED</two>\n</sib_skill>\n"
        )
        check(
            "multi-root: absent sibling basename keeps whole-tree contribution",
            k_omit != eval_cache.content_key(
                source_roots=[skill_d, sib], harness_dir=harness_d,
                model="m", eval_id="e1", prompt="p", dependencies=deps_omit_sib,
            ),
        )

        # --- Acceptance 4: undeclared file + non-stage SKILL.md material ---
        skill_e = make_skill(root / "e")
        harness_e = make_harness(root / "e")
        deps_e = {"demo": ["alpha"]}
        k_e = key_for(skill_e, harness_e, dependencies=deps_e)
        (skill_e / "notes.md").write_text("new file\n")
        check("undeclared file under declared root misses",
              k_e != key_for(skill_e, harness_e, dependencies=deps_e))
        skill_e2 = make_skill(root / "e2")
        harness_e2 = make_harness(root / "e2")
        k_e2 = key_for(skill_e2, harness_e2, dependencies=deps_e)
        (skill_e2 / "SKILL.md").write_text(
            "<demo_skill>\n"
            "  preamble-CHANGED\n"
            "  <alpha>alpha-body</alpha>\n"
            "  <beta>beta-body</beta>\n"
            "</demo_skill>\n"
        )
        check("non-stage SKILL.md material change misses",
              k_e2 != key_for(skill_e2, harness_e2, dependencies=deps_e))

        # --- Acceptance 5: missing declared stage → whole-file fallback ---
        skill_f = make_skill(root / "f")
        harness_f = make_harness(root / "f")
        deps_f = {"demo": ["alpha"]}
        k_f = key_for(skill_f, harness_f, dependencies=deps_f)
        (skill_f / "SKILL.md").write_text(
            "<demo_skill>\n  <alpha_renamed>alpha-body</alpha_renamed>\n"
            "  <beta>beta-body</beta>\n</demo_skill>\n"
        )
        check("renamed declared stage misses (whole-file fallback)",
              k_f != key_for(skill_f, harness_f, dependencies=deps_f))

        # --- Acceptance 6: grade.sh arm / shared / multi-block / other harness ---
        skill_g = make_skill(root / "g")
        multi_grade = (
            "#!/bin/bash\n"
            "eval_id=\"${1:?eval id required}\"\n"
            "shared_one() { true; }\n"
            "case \"$eval_id\" in\n"
            "  e1)\n"
            "    echo first-e1\n"
            "    case \"$nested\" in\n"
            "      x) echo nested-in-e1 ;;\n"
            "    esac\n"
            "    ;;\n"
            "  e2)\n"
            "    echo first-e2\n"
            "    ;;\n"
            "esac\n"
            "shared_two() { true; }\n"
            "case \"$eval_id\" in\n"
            "  e1)\n"
            "    echo second-e1\n"
            "    ;;\n"
            "  e2)\n"
            "    echo second-e2\n"
            "    ;;\n"
            "esac\n"
        )
        harness_g = make_harness(root / "g", grade=multi_grade)
        k_g1 = key_for(skill_g, harness_g, eval_id="e1")
        k_g2 = key_for(skill_g, harness_g, eval_id="e2")
        # Change e2 arm only.
        (harness_g / "grade.sh").write_text(
            multi_grade.replace("echo first-e2", "echo first-e2-CHANGED")
        )
        check("other eval's arm change keeps this eval's key",
              k_g1 == key_for(skill_g, harness_g, eval_id="e1"))
        check("other eval's arm change misses that eval",
              k_g2 != key_for(skill_g, harness_g, eval_id="e2"))
        # The second block's arms join their eval's key too: a splitter that
        # read only the first block, or dropped what follows it, fails here.
        (harness_g / "grade.sh").write_text(
            multi_grade.replace("echo second-e1", "echo second-e1-CHANGED")
        )
        check("second-block arm change misses its eval",
              k_g1 != key_for(skill_g, harness_g, eval_id="e1"))
        check("second-block arm change keeps the other eval's key",
              k_g2 == key_for(skill_g, harness_g, eval_id="e2"))
        # The shared region between the two blocks joins every key.
        (harness_g / "grade.sh").write_text(
            multi_grade.replace("shared_two() { true; }", "shared_two() { false; }")
        )
        check("shared region between blocks misses e1",
              k_g1 != key_for(skill_g, harness_g, eval_id="e1"))
        check("shared region between blocks misses e2",
              k_g2 != key_for(skill_g, harness_g, eval_id="e2"))
        # Restore; change shared region.
        (harness_g / "grade.sh").write_text(multi_grade)
        k_g1 = key_for(skill_g, harness_g, eval_id="e1")
        k_g2 = key_for(skill_g, harness_g, eval_id="e2")
        (harness_g / "grade.sh").write_text(
            multi_grade.replace("shared_one() { true; }", "shared_one() { false; }")
        )
        check("shared region change misses e1",
              k_g1 != key_for(skill_g, harness_g, eval_id="e1"))
        check("shared region change misses e2",
              k_g2 != key_for(skill_g, harness_g, eval_id="e2"))
        # Nested case inside e1 arm joins e1.
        (harness_g / "grade.sh").write_text(multi_grade)
        k_g1 = key_for(skill_g, harness_g, eval_id="e1")
        (harness_g / "grade.sh").write_text(
            multi_grade.replace("echo nested-in-e1", "echo nested-CHANGED")
        )
        check("nested case inside selected arm joins that eval",
              k_g1 != key_for(skill_g, harness_g, eval_id="e1"))
        # Other harness path (fixture) invalidates every eval.
        (harness_g / "grade.sh").write_text(multi_grade)
        k_g1 = key_for(skill_g, harness_g, eval_id="e1")
        k_g2 = key_for(skill_g, harness_g, eval_id="e2")
        (harness_g / "fixtures" / "x.txt").write_text("fixture\n")
        check("fixture path change misses e1",
              k_g1 != key_for(skill_g, harness_g, eval_id="e1"))
        check("fixture path change misses e2",
              k_g2 != key_for(skill_g, harness_g, eval_id="e2"))

        # --- Acceptance 7: unparseable grade.sh → whole file ---
        skill_h = make_skill(root / "h")
        bad_grade = "case \"$eval_id\" in\n  e1)\n    echo hi\n"  # no esac
        harness_h = make_harness(root / "h", grade=bad_grade)
        whole = eval_cache.grade_sh_contribution(bad_grade, "e1")
        check("unparseable grade.sh contributes whole file",
              whole == bad_grade.encode())
        k_h1 = key_for(skill_h, harness_h, eval_id="e1")
        k_h2 = key_for(skill_h, harness_h, eval_id="e2")
        check("unparseable grade.sh: every eval shares the whole-file contribution",
              k_h1 != k_h2)  # eval_id still in key
        # But grade content is identical contribution — changing it moves both.
        (harness_h / "grade.sh").write_text(bad_grade + "\n#x\n")
        check("unparseable grade.sh edit misses e1",
              k_h1 != key_for(skill_h, harness_h, eval_id="e1"))
        check("unparseable grade.sh edit misses e2",
              k_h2 != key_for(skill_h, harness_h, eval_id="e2"))

        # --- Arm matching: POSIX `(id)` arms, glob arms, split location ---
        skill_m = make_skill(root / "m")
        arm_grade = (
            "#!/bin/bash\n"
            "eval_id=\"${1:?eval id required}\"\n"
            "case \"$eval_id\" in\n"
            "  (e1)\n"
            "    echo paren-e1\n"
            "    ;;\n"
            "  e*)\n"
            "    echo glob-e\n"
            "    ;;\n"
            "  x[0-9])\n"
            "    echo bracket-x\n"
            "    ;;\n"
            "esac\n"
        )
        harness_m = make_harness(root / "m", grade=arm_grade)
        k_m1 = key_for(skill_m, harness_m, eval_id="e1")
        k_m2 = key_for(skill_m, harness_m, eval_id="e2")
        (harness_m / "grade.sh").write_text(
            arm_grade.replace("echo paren-e1", "echo paren-e1-CHANGED")
        )
        check("POSIX (id) arm change misses its eval",
              k_m1 != key_for(skill_m, harness_m, eval_id="e1"))
        check("POSIX (id) arm change keeps another eval's key",
              k_m2 == key_for(skill_m, harness_m, eval_id="e2"))
        (harness_m / "grade.sh").write_text(
            arm_grade.replace("echo glob-e", "echo glob-e-CHANGED")
        )
        check("glob arm change misses e1",
              k_m1 != key_for(skill_m, harness_m, eval_id="e1"))
        check("glob arm change misses e2",
              k_m2 != key_for(skill_m, harness_m, eval_id="e2"))
        (harness_m / "grade.sh").write_text(
            arm_grade.replace("echo bracket-x", "echo bracket-x-CHANGED")
        )
        check("bracket-glob arm change misses e1",
              k_m1 != key_for(skill_m, harness_m, eval_id="e1"))
        # Only the harness's own top-level grade.sh is split; a grade.sh under
        # a fixture keeps today's whole-file contribution to every key.
        (harness_m / "grade.sh").write_text(arm_grade)
        nested = harness_m / "fixtures" / "nested"
        nested.mkdir()
        nested_grade = (
            "case \"$eval_id\" in\n"
            "  e1) echo nested-e1 ;;\n"
            "  e2) echo nested-e2 ;;\n"
            "esac\n"
        )
        (nested / "grade.sh").write_text(nested_grade)
        k_m1 = key_for(skill_m, harness_m, eval_id="e1")
        (nested / "grade.sh").write_text(
            nested_grade.replace("echo nested-e2", "echo nested-e2-CHANGED")
        )
        check("a nested grade.sh hashes whole: another eval's arm edit misses e1",
              k_m1 != key_for(skill_m, harness_m, eval_id="e1"))

        # --- A `#` that opens no comment keeps the `;;` on its line ---
        # A quoted `#`, `${#arr[@]}`, and `$#` are code, so the `;;` sharing
        # their line ends the arm and e2 keeps an arm of its own. A trailing
        # comment after a blank still hides the `;;` inside it.
        hash_graders = {
            "quoted '#'":
                "  e1) grep -q '^## Verdict' \"$f\" && echo ok ;;\n",
            "${#hits[@]}":
                "  e1) n=${#hits[@]}; echo \"$n\" ;;\n",
            "$#":
                "  e1) echo \"$#\" args; [ $# -gt 0 ] && echo some ;;\n",
            "trailing comment":
                "  e1) echo e1-body # a comment holding ;; stays a comment\n"
                "    ;;\n",
        }
        for label, e1_arm in hash_graders.items():
            grade = (
                "#!/bin/bash\n"
                "eval_id=\"${1:?eval id required}\"\n"
                "case \"$eval_id\" in\n"
                + e1_arm +
                "  e2) echo e2-body ;;\n"
                "esac\n"
            )
            blocks = eval_cache._parse_top_level_case_blocks(grade)
            arms = None
            if blocks:
                body = grade[blocks[0]["body_start"]:blocks[0]["esac_at"]]
                arms = eval_cache._arm_spans(body)
            check(f"{label} arm: the splitter finds both arms",
                  arms is not None and [a[0] for a in arms] == ["e1", "e2"])
            slug = "".join(c if c.isalnum() else "_" for c in label)
            skill_q = make_skill(root / f"hash_{slug}")
            harness_q = make_harness(root / f"hash_{slug}", grade=grade)
            k_q1 = key_for(skill_q, harness_q, eval_id="e1")
            k_q2 = key_for(skill_q, harness_q, eval_id="e2")
            (harness_q / "grade.sh").write_text(
                grade.replace("echo e2-body", "echo e2-body-CHANGED")
            )
            check(f"{label} arm: an e2 arm edit misses e2",
                  k_q2 != key_for(skill_q, harness_q, eval_id="e2"))
            check(f"{label} arm: an e2 arm edit keeps e1's key",
                  k_q1 == key_for(skill_q, harness_q, eval_id="e1"))

        # --- Fail-closed whitelist: grader shapes the split does not model ---
        # Each grader is legal bash in a shape the arm-split once misread.
        # It now hashes whole or splits exactly, so an edit to text bash runs
        # for an eval moves that eval's key, and bash itself confirms that
        # every arm marker it prints for an eval sits in that eval's
        # contribution.
        head = "#!/bin/bash\n" + BIND + "case \"$eval_id\" in\n"
        shapes = {
            # label: (grader, edited marker, evals whose key must move,
            #         evals whose key must stay)
            "quoted ;;": (
                head + "  e1) sep=';;'; echo e1-body ;; # it's the separator\n"
                "  e2) echo e2-body ;;\nesac\n",
                "e2-body", ["e2"], []),
            ";& fall-through": (
                head + "  e1) echo e1-body ;&\n  e2) echo e2-body ;;\nesac\n",
                "e2-body", ["e1", "e2"], []),
            "here-document holding ;;": (
                head + "  e1) cat <<EOF\nx ;; e1-body\nEOF\n    ;;\n"
                "  e2) echo e2-body ;;\nesac\n",
                "e2-body", ["e2"], []),
            "quoted case and esac": (
                head + "  e1) echo \"a case\" e1-body ;;\n  e2) echo e2-body ;;\n"
                "  e3) echo \"esac x\" e3-body ;;\nesac\n",
                "e2-body", ["e2"], []),
            "extglob arm": (
                head + "  @(e1|e2)) echo shared-body ;;\n  e3) echo e3-body ;;\nesac\n",
                "shared-body", ["e1", "e2"], []),
            "words holding case and esac": (
                head + "  e1) echo lowercase e1-body ;;\n  e2) echo e2-body ;;\n"
                "  e3) echo xesac e3-body ;;\nesac\n",
                "e2-body", ["e2"], ["e1"]),
        }
        for label, (grade, marker, must_move, must_keep) in shapes.items():
            slug = "".join(c if c.isalnum() else "_" for c in label)
            skill_s = make_skill(root / f"shape_{slug}")
            harness_s = make_harness(root / f"shape_{slug}", grade=grade)
            before = {e: key_for(skill_s, harness_s, eval_id=e)
                      for e in must_move + must_keep}
            (harness_s / "grade.sh").write_text(
                grade.replace(marker, marker.replace("-body", "-CHANGED-body"))
            )
            for e in must_move:
                check(f"{label}: an edit bash runs for {e} misses {e}",
                      before[e] != key_for(skill_s, harness_s, eval_id=e))
            for e in must_keep:
                check(f"{label}: the split keeps {e}'s key",
                      before[e] == key_for(skill_s, harness_s, eval_id=e))
            for e in ("e1", "e2", "e3"):
                contribution = eval_cache.grade_sh_contribution(grade, e)
                ran = bash_arm_markers(grade, e)
                check(f"{label}: every arm bash runs for {e} is in its contribution",
                      all(word.encode() in contribution for word in ran))

        # --- Raw bytes: CRLF and undecodable graders and SKILL.md files ---
        skill_r = make_skill(root / "raw")
        harness_r = make_harness(root / "raw")
        lf_grade = (harness_r / "grade.sh").read_bytes()
        k_lf = key_for(skill_r, harness_r)
        (harness_r / "grade.sh").write_bytes(lf_grade.replace(b"\n", b"\r\n"))
        check("a CRLF conversion of a parseable grade.sh misses",
              k_lf != key_for(skill_r, harness_r))
        harness_ru = make_harness(root / "raw_u", grade=bad_grade)
        skill_ru = make_skill(root / "raw_u")
        k_ru = key_for(skill_ru, harness_ru)
        (harness_ru / "grade.sh").write_bytes(bad_grade.encode().replace(b"\n", b"\r\n"))
        check("a CRLF conversion of an unparseable grade.sh misses",
              k_ru != key_for(skill_ru, harness_ru))

        def key_or_none(*args, **kwargs):
            try:
                return key_for(*args, **kwargs)
            except UnicodeDecodeError:
                return None

        (harness_r / "grade.sh").write_bytes(lf_grade + b"# \xff\n")
        k_ff = key_or_none(skill_r, harness_r)
        check("a non-UTF-8 grade.sh still yields a key", k_ff is not None)
        (harness_r / "grade.sh").write_bytes(lf_grade + b"# \xfe\n")
        check("an edit of a non-UTF-8 grade.sh byte misses",
              k_ff is not None and k_ff != key_or_none(skill_r, harness_r))

        skill_rd = make_skill(root / "raw_d")
        harness_rd = make_harness(root / "raw_d")
        deps_rd = {"demo": ["alpha"]}
        lf_md = (skill_rd / "SKILL.md").read_bytes()
        k_md = key_for(skill_rd, harness_rd, dependencies=deps_rd)
        (skill_rd / "SKILL.md").write_bytes(lf_md.replace(b"\n", b"\r\n"))
        check("a CRLF conversion of a declared SKILL.md misses",
              k_md != key_for(skill_rd, harness_rd, dependencies=deps_rd))
        (skill_rd / "SKILL.md").write_bytes(lf_md + b"\xff\n")
        k_md_ff = key_or_none(skill_rd, harness_rd, dependencies=deps_rd)
        check("a non-UTF-8 declared SKILL.md still yields a key", k_md_ff is not None)
        (skill_rd / "SKILL.md").write_bytes(lf_md + b"\xfe\n")
        check("an edit of a non-UTF-8 declared SKILL.md byte misses",
              k_md_ff is not None
              and k_md_ff != key_or_none(skill_rd, harness_rd, dependencies=deps_rd))

        # --- bash arbitrates: graders the lexer misreads or the split's ---
        # --- id-binding preconditions exclude hash whole               ---
        # Each grader holds an edit bash runs for the named eval, so that
        # eval's key must move: a syntax error bash rejects, two comments
        # bash reads differently from the lexer, and five ways the eval id
        # bash sees differs from the runner's.
        review_grade = (pathlib.Path(__file__).resolve().parents[1]
                        / "git_review" / "evals" / "grade.sh").read_text()
        arbiter_cases = {
            "a stray fi bash rejects": (
                review_grade, "\n  30)\n", "\n  30)\n    fi\n", ["1", "29", "31"]),
            "a comment after a backslash-newline": (
                BIND + "case \"$eval_id\" in\n  e1) echo one-body \\\n#;; e2)\n"
                "    true ;;\n  e3) echo three-body ;;\nesac\n",
                "    true ;;", "    false ;;", ["e1"]),
            "a comment right after (( ))": (
                BIND + "case \"$eval_id\" in\n  e1) (( 1 ))#;; e2)\n    true ;;\n"
                "  e3) echo three-body ;;\nesac\n",
                "    true ;;", "    false ;;", ["e1"]),
            "re-entry through $0": (
                BIND + "case \"$eval_id\" in\n  e1) true ;;\n"
                "  e3) bash \"$0\" e1 && echo three-body ;;\nesac\n",
                "e1) true", "e1) false", ["e3"]),
            "a function that rebinds eval_id with local": (
                BIND + "grade_arms() {\n  case \"$eval_id\" in\n    e1) true ;;\n"
                "    e3) grade_as e1 ;;\n  esac\n}\n"
                "grade_as() { local eval_id=\"$1\"; grade_arms; }\ngrade_arms\n",
                "e1) true", "e1) false", ["e3"]),
            "an id normalized from $1": (
                "eval_id=\"${1#eval-}\"\ncase \"$eval_id\" in\n  e1) true ;;\n"
                "  e2) echo two-body ;;\nesac\n",
                "e1) true", "e1) false", ["eval-e1"]),
            "nocasematch": (
                BIND + "shopt -s nocasematch\ncase \"$eval_id\" in\n  E1) true ;;\n"
                "  e2) echo two-body ;;\nesac\n",
                "E1) true", "E1) false", ["e1"]),
            "a for loop over eval_id": (
                BIND + "for eval_id in e1 e2; do\n  case \"$eval_id\" in\n"
                "    e1) true ;;\n    e2) echo two-body ;;\n  esac\ndone\n",
                "e1) true", "e1) false", ["e2"]),
        }
        for label, (grade, old, new, evals) in arbiter_cases.items():
            slug = "".join(c if c.isalnum() else "_" for c in label)
            skill_x = make_skill(root / f"arb_{slug}")
            harness_x = make_harness(root / f"arb_{slug}", grade=grade)
            before = {e: key_for(skill_x, harness_x, eval_id=e) for e in evals}
            edited = grade.replace(old, new, 1)
            check(f"{label}: the fixture edit lands", edited != grade)
            (harness_x / "grade.sh").write_text(edited)
            for e in evals:
                check(f"{label}: an edit bash runs for {e} misses {e}",
                      before[e] != key_for(skill_x, harness_x, eval_id=e))

        # --- Positionals before the binding, and sourced files ---
        def run_grade_file(grade_path, *args) -> str:
            return subprocess.run(
                ["bash", str(grade_path), *args], capture_output=True, text=True,
                env={"PATH": os.environ.get("PATH", "/usr/bin:/bin")},
            ).stdout

        two_arms = ("case \"$eval_id\" in\n  e1) echo one-body ;;\n"
                    "  e2) echo two-body ;;\nesac\n")

        def arm_edit_moves(label, grade, helper=None, *, runner_args=("e1", "e2"),
                           runs="two-body", moves="e1"):
            """Stage `grade` (and `helper.sh` beside it), show bash runs the
            e2 arm for the runner's eval id, and check an e2-arm edit moves
            that eval's key."""
            slug = "".join(c if c.isalnum() else "_" for c in label)
            skill_p = make_skill(root / f"pos_{slug}")
            harness_p = make_harness(root / f"pos_{slug}", grade=grade)
            if helper is not None:
                (harness_p / "helper.sh").write_text(helper)
            if runs:
                check(f"{label}: bash runs the e2 arm for {moves}",
                      runs in run_grade_file(harness_p / "grade.sh", *runner_args))
            before = key_for(skill_p, harness_p, eval_id=moves)
            (harness_p / "grade.sh").write_text(grade.replace("two-body", "two-CHANGED-body"))
            return before != key_for(skill_p, harness_p, eval_id=moves)

        check("an unconditional shift before the binding: an e2-arm edit misses e1",
              arm_edit_moves("unconditional shift",
                             "#!/bin/bash\nshift\n" + BIND + two_arms))
        check("set -- before the binding: an e2-arm edit misses e1",
              arm_edit_moves("set --",
                             "#!/bin/bash\nset -- e2 \"$@\"\n" + BIND + two_arms,
                             runner_args=("e1",)))
        check("a != guard is no dash guard: an e2-arm edit misses e1",
              arm_edit_moves("!= guard",
                             "#!/bin/bash\nif [[ \"${1:-}\" != \"--form-only\" ]]; then\n"
                             "    shift\nfi\n" + BIND + two_arms))
        guarded = ("#!/bin/bash\nset -uo pipefail\nform_only=false\n"
                   "if [[ \"${1:-}\" == \"--form-only\" ]]; then\n    form_only=true\n"
                   "    shift\nfi\n" + BIND + two_arms)
        check("git_review's --form-only guard keeps the split: an e2-arm edit keeps e1's key",
              not arm_edit_moves("form-only guard", guarded, runs=None))
        check("git_review's --form-only guard keeps the split: an e2-arm edit misses e2",
              arm_edit_moves("form-only guard e2", guarded, runs=None, moves="e2"))

        sourcing = ("#!/bin/bash\n" + BIND
                    + "HERE=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"\n"
                    + ". \"$HERE/helper.sh\"\n" + two_arms)
        check("a benign sourced helper keeps the split: an e2-arm edit keeps e1's key",
              not arm_edit_moves("benign helper", sourcing,
                                 helper="say() { echo \"$*\"; }\n", runs=None))
        check("a sourced helper that rebinds eval_id: an e2-arm edit misses e1",
              arm_edit_moves("rebinding helper", sourcing, helper="eval_id=e2\n",
                             runner_args=("e1",)))
        check("an unresolvable source \"$x\": an e2-arm edit misses e1",
              arm_edit_moves("unresolvable source",
                             "#!/bin/bash\n" + BIND
                             + "HERE=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"\n"
                             + "x=\"$HERE/helper.sh\"\nsource \"$x\"\n" + two_arms,
                             helper="eval_id=e2\n", runner_args=("e1",)))

        # --- Shapes that read through quoting, names, aliases, and re-entry ---
        # Each grader makes bash run the e2 arm's text for e1; the split must
        # fail closed, so an edit to that text moves e1's key.
        here = "HERE=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"\n"
        rebinding_helper = "eval_id=e2\n"
        hidden_cases = {}
        for spelling in ("builtin source", "command source", "builtin .", "command .",
                         "\"source\"", "\\source", "\\."):
            hidden_cases[f"{spelling} of a rebinding helper"] = (
                "#!/bin/bash\n" + BIND + here + f"{spelling} \"$HERE/helper.sh\"\n"
                + two_arms, rebinding_helper)
        for spelling in ("\\set -- e2", "'set' -- e2"):
            hidden_cases[f"{spelling} before the binding"] = (
                "#!/bin/bash\n" + spelling + "\n" + BIND + two_arms, None)
        hidden_cases["shopt -s nocase\"match\""] = (
            "#!/bin/bash\n" + BIND + "shopt -s nocase\"match\"\n"
            "case \"$eval_id\" in\n  E1) echo two-body ;;\n  e2) echo other-body ;;\nesac\n",
            None)
        hidden_cases["declare of a constructed name"] = (
            "#!/bin/bash\n" + BIND + "declare \"eval\"\"_id=e2\"\n" + two_arms, None)
        hidden_cases["printf -v into a constructed name"] = (
            "#!/bin/bash\n" + BIND + "printf -v \"eval\"\"_id\" %s e2\n" + two_arms, None)
        hidden_cases["a nameref to a constructed name"] = (
            "#!/bin/bash\n" + BIND + "v=eval\ndeclare -n r=\"${v}_id\"\nr=e2\n" + two_arms,
            None)
        hidden_cases["a sourced helper that declares a constructed name"] = (
            "#!/bin/bash\n" + BIND + here + ". \"$HERE/helper.sh\"\n" + two_arms,
            "declare -g \"eval\"\"_id=e2\"\n")
        alias_arms = ("alias lead='true ;; e1)'\n"
                      "case \"$eval_id\" in\n  e2) lead\n    echo two-body ;;\n"
                      "  e3) echo three-body ;;\nesac\n")
        hidden_cases["an alias that re-cuts the arms (expand_aliases)"] = (
            "#!/bin/bash\n" + BIND + "shopt -s expand_aliases\n" + alias_arms, None)
        hidden_cases["an alias that re-cuts the arms (set -o posix)"] = (
            "#!/bin/bash\n" + BIND + "set -o posix\n" + alias_arms, None)
        hidden_cases["set -- after a string that prints like a function head"] = (
            "#!/bin/bash\nnote=\"\nfake () \n{\n  body\n  }\"\nset -- e2\n" + BIND + two_arms,
            None)
        hidden_cases["set -- after a here-document that prints like a function head"] = (
            "#!/bin/bash\ncat > /dev/null <<'EOF'\nfake ()\n{\n  echo stub\n  }\nEOF\n"
            "set -- e2\n" + BIND + two_arms, None)
        hidden_cases["re-entry through $BASH_ARGV0"] = (
            "#!/bin/bash\n" + BIND + "case \"$eval_id\" in\n"
            "  e1) [[ -z \"${NESTED:-}\" ]] && NESTED=1 bash \"$BASH_ARGV0\" e2 ;;\n"
            "  e2) echo two-body ;;\nesac\n", None)
        hidden_cases["re-entry through a glob on the grader directory"] = (
            "#!/bin/bash\n" + BIND + here + "case \"$eval_id\" in\n"
            "  e1) [[ -z \"${NESTED:-}\" ]] && NESTED=1 bash \"$HERE\"/grade.s[h] e2 ;;\n"
            "  e2) echo two-body ;;\nesac\n", None)
        # A shape that needs a newer bash cannot misroute an older one, so the
        # check that bash runs the e2 arm applies only where the feature
        # exists; the key check applies on every bash.
        bash_version = tuple(int(part) for part in subprocess.run(
            ["bash", "-c", "echo ${BASH_VERSINFO[0]} ${BASH_VERSINFO[1]}"],
            capture_output=True, text=True).stdout.split())
        needs_bash = {
            "a nameref to a constructed name": (4, 3),
            "a sourced helper that declares a constructed name": (4, 2),
            "re-entry through $BASH_ARGV0": (5, 0),
        }
        for label, (grade, helper) in hidden_cases.items():
            runs = "two-body" if bash_version >= needs_bash.get(label, (0, 0)) else None
            check(f"{label}: an edit bash runs for e1 misses e1",
                  arm_edit_moves(label, grade, helper, runner_args=("e1", "e2"), runs=runs))

        # The dash guard rests on no eval id beginning with "-".
        dash_ids = []
        for evals_file in (pathlib.Path(__file__).resolve().parents[1]).glob("*/evals/evals.json"):
            data = json.loads(evals_file.read_text())
            entries = data.get("evals", []) if isinstance(data, dict) else data
            dash_ids += [str(e.get("id")) for e in entries
                         if isinstance(e, dict) and str(e.get("id", "")).startswith("-")]
        check("no evals.json id begins with \"-\"", not dash_ids)

        # With no bash on PATH nothing can confirm a split: whole file.
        split_grade = make_harness(root / "nobash").joinpath("grade.sh").read_text()
        saved_path = os.environ.get("PATH", "")
        os.environ["PATH"] = ""
        try:
            no_bash = eval_cache.grade_sh_contribution(split_grade, "e1")
        finally:
            os.environ["PATH"] = saved_path
        check("without bash on PATH the grader contributes whole",
              no_bash == split_grade.encode())
        check("with bash on PATH the same grader splits",
              eval_cache.grade_sh_contribution(split_grade, "e1") != split_grade.encode())

        # --- Acceptance 8 call-site: dependencies_for + runners forward it ---
        evals_json = root / "evals_fwd" / "evals.json"
        evals_json.parent.mkdir()
        evals_json.write_text(json.dumps({
            "evals": [
                {"id": "e1", "dependencies": {"demo": ["alpha"]}},
                {"id": "e2"},
            ]
        }))
        check("dependencies_for returns map when present",
              eval_cache.dependencies_for(evals_json, "e1") == {"demo": ["alpha"]})
        check("dependencies_for returns None when omitted",
              eval_cache.dependencies_for(evals_json, "e2") is None)
        # The call-site check reads each content_key() call through the AST,
        # so only a dependencies= keyword that forwards this eval's own
        # declaration passes. Staged runner sources prove each fail branch.
        call = ("key = eval_cache.content_key(source_roots=roots, "
                "harness_dir=THIS, model=m, eval_id=eval_id, prompt=p{extra})\n")
        prelude = ('THIS = pathlib.Path(__file__).parent\n'
                   'EVALS = THIS / "evals.json"\n')
        flagged = {
            "missing": prelude + call.format(extra=""),
            "set to None": prelude + call.format(extra=", dependencies=None"),
            "only in a comment": prelude
            + "# dependencies=eval_cache.dependencies_for(EVALS, eval_id)\n"
            + call.format(extra=""),
            "computed but not passed": prelude
            + "deps = eval_cache.dependencies_for(EVALS, eval_id)\n"
            + call.format(extra=""),
            "read for another eval id": prelude + call.format(
                extra=', dependencies=eval_cache.dependencies_for(EVALS, "e1")'),
        }
        for label, src in flagged.items():
            count, problems = content_key_forwarding_problems(src)
            check(f"call-site check flags a runner whose dependencies= is {label}",
                  count == 1 and bool(problems))
        accepted = {
            "dependencies_for over a bound evals.json path": prelude + call.format(
                extra=", dependencies=eval_cache.dependencies_for(EVALS, eval_id)"),
            "dependencies_for over an inline evals.json path": prelude + call.format(
                extra=', dependencies=eval_cache.dependencies_for('
                      'THIS / "evals.json", eval_id)'),
            "the eval spec's dependencies field": prelude + call.format(
                extra=', dependencies=spec.get("dependencies")'),
        }
        for label, src in accepted.items():
            count, problems = content_key_forwarding_problems(src)
            check(f"call-site check accepts {label}", count == 1 and not problems)

        # Tree check: every Pattern A runner that calls content_key forwards
        # its eval's declaration on every call.
        tests_root = pathlib.Path(__file__).resolve().parents[1]
        runners = sorted(tests_root.glob("*/evals/run.py"))
        callers = []
        forwarding_problems = []
        for runner in runners:
            count, problems = content_key_forwarding_problems(
                runner.read_text(encoding="utf-8"))
            if count:
                callers.append(runner)
            rel = runner.relative_to(tests_root.parent)
            forwarding_problems += [f"{rel}: {p}" for p in problems]
        check("at least one Pattern A content_key caller exists", bool(callers))
        check(
            "every content_key caller forwards dependencies",
            not forwarding_problems,
        )
        for problem in forwarding_problems:
            print(f"    {problem}")

        # --- Acceptance 10: non-publishing git_review eval omits publishing ---
        import shutil
        repo = pathlib.Path(__file__).resolve().parents[2]
        gr_skill = repo / "plugins" / "ai_dev" / "skills" / "git_review"
        gr_evals = repo / "tests" / "git_review" / "evals"
        if gr_skill.is_dir() and (gr_evals / "evals.json").is_file():
            data = json.loads((gr_evals / "evals.json").read_text())
            sample = None
            for e in data["evals"]:
                deps = e.get("dependencies") or {}
                stages = deps.get("git_review") or []
                if stages and "publishing" not in stages:
                    sample = e
                    break
            if sample is None:
                check("git_review sample non-publishing eval with deps exists", False)
            else:
                # Copy the skill so the probe edit never touches the live tree.
                skill_copy = root / "gr_skill_copy" / "git_review"
                shutil.copytree(gr_skill, skill_copy)
                th = root / "gr_harness"
                th.mkdir()
                (th / "evals.json").write_text("{}")
                (th / "grade.sh").write_text("case \"$eval_id\" in\n  x) ;;\nesac\n")
                deps = sample["dependencies"]
                before = eval_cache.content_key(
                    source_roots=[skill_copy], harness_dir=th, model="m",
                    eval_id=str(sample["id"]), prompt="p", dependencies=deps,
                )
                original = (skill_copy / "SKILL.md").read_text(encoding="utf-8")
                mutated = original.replace(
                    "<publishing>", "<publishing>\n<!-- cache-key probe -->\n", 1
                )
                if mutated == original:
                    check("publishing stage present for probe edit", False)
                else:
                    (skill_copy / "SKILL.md").write_text(mutated)
                    after = eval_cache.content_key(
                        source_roots=[skill_copy], harness_dir=th, model="m",
                        eval_id=str(sample["id"]), prompt="p", dependencies=deps,
                    )
                    check(
                        "non-publishing eval keeps key when publishing changes",
                        before == after,
                    )
        else:
            check("git_review skill and evals present for acceptance 10", False)

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
