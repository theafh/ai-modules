#!/usr/bin/env bash
# Bundled-script unit tests for tests/trigger_evals/run.py.
#
# Hermetic: exercises the baseline-regression detector, the
# deployed-versus-unavailable-versus-`--force-uuid` mode-selection guards, and
# the per-vendor deployed worker path with a stub worker and canned record
# streams. Nothing here depends on recorded runs under results/ (gitignored)
# or on spawning a live `claude` / `agent` worker. Fast, deterministic, no LLM
# cost.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - "$HERE/.." <<'PY'
import contextlib, importlib.util, io, json, multiprocessing, os, shutil
import subprocess, sys, tempfile
from pathlib import Path

run_dir = Path(sys.argv[1]).resolve()
repo_root = run_dir.parent.parent.parent
spec = importlib.util.spec_from_file_location("trun", run_dir / "run.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
sys.modules["trun"] = m

# The in-process pool forks so it inherits this importlib-loaded module; a
# spawn child could not re-import the module by the name "trun".
if sys.platform == "darwin":
    try:
        multiprocessing.set_start_method("fork", force=True)
    except RuntimeError:
        pass

fails = []
def check(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond: fails.append(msg)

def run_out(rows):
    """Build a minimal deployed-mode output dict from (query, expected, precise_n, runs) tuples."""
    results = [{"query": q, "expected_skill": e, "precise_triggers": p, "runs": n,
                "precise_pass": p / n >= 0.5} for q, e, p, n in rows]
    return {"mode": "deployed", "results": results}

def write_baseline(out):
    d = Path(tempfile.mkdtemp())
    (d / "results.json").write_text(json.dumps(out))
    return d

# --- baseline captures a passing state; current drops one query below threshold
base = run_out([("a", "task", 3, 3), ("b", "task_fix", 2, 3), ("c", "task_audit", 0, 3)])
cur  = run_out([("a", "task", 3, 3), ("b", "task_fix", 1, 3), ("c", "task_audit", 0, 3)])
bp = write_baseline(base)
cmp = m.compare_to_baseline(cur, bp)
check(len(cmp["regressions"]) == 1 and cmp["regressions"][0]["query"] == "b",
      "regression: a query crossing pass->fail is flagged")
check(cmp["regressions"][0]["baseline_precise"] == 2 and cmp["regressions"][0]["current_precise"] == 1,
      "regression: carries baseline and current trigger counts")

# --- a flip that stays above threshold is NOT a regression (noise discrimination)
base2 = run_out([("a", "task", 3, 3)])
cur2  = run_out([("a", "task", 2, 3)])
cmp2 = m.compare_to_baseline(cur2, write_baseline(base2))
check(not cmp2["regressions"], "no regression: 3/3 -> 2/3 stays passing, not flagged")

# --- recovery is reported as an improvement
base3 = run_out([("a", "task", 1, 3)])
cur3  = run_out([("a", "task", 2, 3)])
cmp3 = m.compare_to_baseline(cur3, write_baseline(base3))
check(len(cmp3["improvements"]) == 1, "improvement: a query crossing fail->pass is flagged")

# --- self-compare shows no movement
cmp4 = m.compare_to_baseline(base, bp)
check(not cmp4["regressions"] and not cmp4["improvements"], "self-compare: zero movement")

# --- a baseline given as the results.json file works like the directory form
cmp5 = m.compare_to_baseline(cur, bp / "results.json")
check(len(cmp5["regressions"]) == 1, "baseline path accepts the results.json file directly")

# --- differing cohorts compare on the shared queries without crashing
big = run_out([("a", "task", 3, 3), ("b", "task_fix", 3, 3), ("new", "task", 3, 3)])
cmp6 = m.compare_to_baseline(big, bp)
check(cmp6["shared_queries"] == 2 and cmp6["only_in_current"] == ["new"],
      "cohort mismatch: shared set computed, extra query reported not crashed")

# --- the pure function never mutates its input
before = json.dumps(cur, sort_keys=True)
m.compare_to_baseline(cur, bp)
check(json.dumps(cur, sort_keys=True) == before, "compare_to_baseline leaves current output unmutated")

# --- mode selection: unavailable skill fails loudly (no score)

SCORE_KEYS = ("accuracy", "recall", "precise_passed", "family_passed",
              "precise_triggers", "passed")

def has_score_fields(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError:
        return False
    blob = json.dumps(data)
    if any(k in data or k in data.get("summary", {}) for k in SCORE_KEYS):
        return True
    # also catch nested result rows carrying precise/family trigger counts
    for r in data.get("results", []) if isinstance(data.get("results"), list) else []:
        if any(k in r for k in SCORE_KEYS):
            return True
    return "accuracy" in blob or "recall" in blob

def stage_home(*roots):
    home = Path(tempfile.mkdtemp())
    for root in roots or (".claude",):
        (home / root / "skills").mkdir(parents=True, exist_ok=True)
    return home

def stage_skill(root: Path, name: str = "demo",
                description: str = "demo skill for hermetic mode tests") -> Path:
    skill = root / name
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: {description}\n---\n\n# {name}\n"
    )
    return skill

def deploy_skill(home: Path, root: str, source: Path,
                 description: str | None = None) -> Path:
    dest = home / root / "skills" / source.name
    dest.mkdir(parents=True)
    text = source.joinpath("SKILL.md").read_text()
    if description is not None:
        lines = []
        for line in text.splitlines():
            lines.append(f"description: {description}" if line.startswith("description:") else line)
        text = "\n".join(lines) + "\n"
    (dest / "SKILL.md").write_text(text)
    return dest

def stage_eval_set(entries=None):
    d = Path(tempfile.mkdtemp())
    p = d / "demo.json"
    entries = entries or [{"query": "do the demo thing", "expected_skill": "demo"}]
    p.write_text(json.dumps(entries))
    return p

calls = {"uuid": 0, "deployed": 0}
DEPLOYED_STUB_SENTINEL = "SENTINEL_DEPLOYED_STUB_NO_SCORE"

def stub_uuid(*_a, **_k):
    calls["uuid"] += 1
    return {"mode": "uuid_fallback", "summary": {}}

def stub_deployed(*_a, **_k):
    calls["deployed"] += 1
    # Raise before main writes results.json: a normal return would need
    # precise/family summary fields for the deployed print/exit path.
    raise RuntimeError(DEPLOYED_STUB_SENTINEL)

def run_main(argv, home: Path):
    """Invoke main() under a staged HOME with mode runners stubbed."""
    old_argv, old_home = sys.argv, os.environ.get("HOME")
    old_uuid, old_dep = m.run_uuid_fallback, m.run_deployed_mode
    m.run_uuid_fallback = stub_uuid
    m.run_deployed_mode = stub_deployed
    # hermetic: never require a real worker binary for the force-uuid path
    old_which = shutil.which
    shutil.which = lambda *_a, **_k: "/usr/bin/true"
    sys.argv = ["run.py", *argv]
    os.environ["HOME"] = str(home)
    err = io.StringIO()
    try:
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
            rc = m.main()
    finally:
        sys.argv = old_argv
        m.run_uuid_fallback = old_uuid
        m.run_deployed_mode = old_dep
        shutil.which = old_which
        if old_home is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = old_home
    return rc, err.getvalue()

def run_live(argv, home: Path, extra_env=None):
    """Invoke main() under a staged HOME with the real deployed worker path."""
    old_argv, old_home = sys.argv, os.environ.get("HOME")
    saved = {}
    for key, value in (extra_env or {}).items():
        saved[key] = os.environ.get(key)
        os.environ[key] = value
    sys.argv = ["run.py", *argv]
    os.environ["HOME"] = str(home)
    err = io.StringIO()
    try:
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
            rc = m.main()
    finally:
        sys.argv = old_argv
        if old_home is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = old_home
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
    return rc, err.getvalue()

# --- has_score_fields detects a real score (fail-branch control)
scored = Path(tempfile.mkdtemp()) / "results.json"
scored.write_text(json.dumps({"summary": {"precise_passed": 1}}))
check(has_score_fields(scored),
      "has_score_fields: detects precise_passed in summary")
check(not has_score_fields(Path(tempfile.mkdtemp()) / "missing.json"),
      "has_score_fields: missing file is not scored")

eval_set = stage_eval_set()
skill_src = stage_skill(Path(tempfile.mkdtemp()))

# (1) unavailable without --force-uuid → named failure, no score
home1 = stage_home(".claude")
results1 = Path(tempfile.mkdtemp()) / "out"
calls["uuid"] = calls["deployed"] = 0
rc1, err1 = run_main(
    ["--vendor", "claude", "--eval-set", str(eval_set), "--skill", "demo",
     "--skill-path", str(skill_src), "--results-dir", str(results1)],
    home1,
)
check(rc1 != 0, "unavailable: exits non-zero without --force-uuid")
check("unavailable" in err1.lower() and "demo" in err1,
      "unavailable: stderr names the unavailability and the skill")
check(not results1.exists(),
      "unavailable: creates no results directory")
check(calls["uuid"] == 0 and calls["deployed"] == 0,
      "unavailable: neither mode runner is called")

# (2) --force-uuid → uuid stub reached, no scored results.json
home2 = stage_home(".claude")
results2 = Path(tempfile.mkdtemp()) / "out"
calls["uuid"] = calls["deployed"] = 0
rc2, _err2 = run_main(
    ["--vendor", "claude", "--eval-set", str(eval_set), "--skill", "demo",
     "--skill-path", str(skill_src), "--results-dir", str(results2),
     "--force-uuid"],
    home2,
)
check(calls["uuid"] == 1, "force-uuid: records a run_uuid_fallback call")
check(calls["deployed"] == 0, "force-uuid: does not call run_deployed_mode")
check(not has_score_fields(results2 / "results.json"),
      "force-uuid: stubbed run leaves no scored results.json")
# Stubbed uuid payload has an empty summary; main treats missing passed/total
# as 0==0, so do not assert exit 0. Exit 2 is the preflight/unavailable path.
check(rc2 != 2, "force-uuid: stubbed uuid path is not a preflight failure")

# (3) skill present under staged HOME → deployed stub reached
home3 = stage_home(".claude")
deployed = home3 / ".claude" / "skills" / "demo"
deployed.mkdir(parents=True)
(deployed / "SKILL.md").write_text(skill_src.joinpath("SKILL.md").read_text())
results3 = Path(tempfile.mkdtemp()) / "out"
calls["uuid"] = calls["deployed"] = 0
rc3, err3 = run_main(
    ["--vendor", "claude", "--eval-set", str(eval_set), "--skill", "demo",
     "--skill-path", str(skill_src), "--results-dir", str(results3)],
    home3,
)
check(calls["deployed"] == 1, "deployed: records a run_deployed_mode call")
check(calls["uuid"] == 0, "deployed: does not call run_uuid_fallback")
check(rc3 == 1 and DEPLOYED_STUB_SENTINEL in err3,
      "deployed: stub exits via sentinel before scoring")
check(not has_score_fields(results3 / "results.json"),
      "deployed: stubbed run leaves no scored results.json")

# (4) --force-uuid without a resolvable skill source → fail before results dir
home4 = stage_home(".claude")
results4 = Path(tempfile.mkdtemp()) / "out"
calls["uuid"] = calls["deployed"] = 0
rc4, err4 = run_main(
    ["--vendor", "claude", "--eval-set", str(eval_set), "--skill", "demo_no_default_path",
     "--results-dir", str(results4), "--force-uuid"],
    home4,
)
check(rc4 != 0, "force-uuid no-path: exits non-zero")
check("requires a skill source path" in err4,
      "force-uuid no-path: names the missing source path")
check("plugins/knowledge_management/skills/" in err4,
      "force-uuid no-path: names the knowledge_management default")
check(not results4.exists(),
      "force-uuid no-path: creates no results directory")
check(calls["uuid"] == 0 and calls["deployed"] == 0,
      "force-uuid no-path: neither mode runner is called")

# --- hermetic per-vendor deployed worker path ------------------------------
#
# Test Integrity: the case that used to assert "an explicit --vendor cursor
# stops with an error before either mode runs" is superseded behaviour. The
# **Vendor parity** decision recorded in
# tasks/archive/tests_trigger-evals-cursor-vendor.md made Cursor a supported vendor, so
# the Cursor cases below replace it.

STUB = r'''#!/usr/bin/env python3
import json, os, sys

argv = sys.argv[1:]
log = os.environ.get("STUB_LOG")
if log:
    with open(log, "a") as fh:
        fh.write(json.dumps({"argv": argv, "cwd": os.getcwd()}) + "\n")

cursor = len(argv) > 1 and argv[1] == "--output-format"
query = argv[-1] if cursor else (argv[1] if len(argv) > 1 else "")
home = os.environ.get("HOME", "")
native = home + ("/.cursor/skills/demo/SKILL.md" if cursor else "/.claude/skills/demo/SKILL.md")
compat = home + "/.claude/skills/demo/SKILL.md"

def emit(obj):
    print(json.dumps(obj), flush=True)

def claude_tool(name, payload):
    emit({"type": "stream_event", "event": {"type": "content_block_start", "content_block": {"type": "tool_use", "name": name}}})
    emit({"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "input_json_delta", "partial_json": json.dumps(payload)}}})
    emit({"type": "stream_event", "event": {"type": "content_block_stop"}})
    emit({"type": "result", "is_error": False})

def cursor_tool(kind, args):
    emit({"type": "tool_call", "subtype": "started", "tool_call": {kind: {"args": args}}})
    emit({"type": "tool_call", "subtype": "completed", "tool_call": {kind: {"args": args, "result": {"success": {}}}}})
    emit({"type": "result", "subtype": "success", "is_error": False})

if query == "load":
    if cursor:
        cursor_tool("readToolCall", {"path": native})
    else:
        claude_tool("Skill", {"skill": "demo"})
elif query == "read":
    if cursor:
        cursor_tool("readToolCall", {"path": native})
    else:
        claude_tool("Read", {"file_path": native})
elif query == "compat":
    if cursor:
        cursor_tool("readToolCall", {"path": compat})
    else:
        claude_tool("Read", {"file_path": compat})
elif query == "other":
    if cursor:
        cursor_tool("readToolCall", {"path": "/tmp/other/file.py"})
    else:
        claude_tool("Read", {"file_path": "/tmp/other/file.py"})
elif query == "shell":
    if cursor:
        cursor_tool("shellToolCall", {"command": "true"})
    else:
        claude_tool("Bash", {"command": "true"})
elif query == "no_tool":
    emit({"type": "result", "subtype": "success", "is_error": False})
elif query == "result_error":
    emit({"type": "result", "subtype": "success", "is_error": True})
    sys.exit(0)
elif query == "exit_nonzero":
    sys.exit(3)
elif query == "escape":
    path = os.environ.get("STUB_ESCAPE_PATH")
    if path:
        with open(path, "w") as fh:
            fh.write("escaped\n")
    emit({"type": "result", "is_error": False})
else:
    emit({"type": "result", "is_error": False})
'''

stub_dir = Path(tempfile.mkdtemp())
stub_path = stub_dir / "stub_worker.py"
stub_path.write_text(STUB)
stub_path.chmod(0o755)

HERMETIC = [
    {"query": "load", "expected_skill": "demo"},
    {"query": "read", "expected_skill": "demo"},
    {"query": "compat", "expected_skill": "demo"},
    {"query": "other", "expected_skill": None},
    {"query": "shell", "expected_skill": None},
    {"query": "no_tool", "expected_skill": None},
    {"query": "result_error", "expected_skill": None},
    {"query": "exit_nonzero", "expected_skill": None},
]
hermetic_set = stage_eval_set(HERMETIC)
hermetic_src = stage_skill(Path(tempfile.mkdtemp()))

def run_hermetic(vendor_name: str, root: str):
    home = stage_home(root)
    deploy_skill(home, root, hermetic_src)
    results = Path(tempfile.mkdtemp()) / "out"
    log = Path(tempfile.mkdtemp()) / "stub.log"
    rc, err = run_live(
        ["--vendor", vendor_name, "--eval-set", str(hermetic_set),
         "--skill", "demo", "--skill-path", str(hermetic_src),
         "--results-dir", str(results), "--worker-bin", str(stub_path),
         "--runs-per-query", "1"],
        home,
        {"STUB_LOG": str(log)},
    )
    return home, results, log, rc, err

for vendor_name, root, model in (
    ("claude", ".claude", "sonnet"),
    ("cursor", ".cursor", "auto"),
):
    home, results, log, rc, err = run_hermetic(vendor_name, root)
    data = json.loads((results / "results.json").read_text())
    by_query = {r["query"]: r["triggered_skill_per_run"][0] for r in data["results"]}
    run_log = (results / "run.log").read_text()

    check(data["vendor"] == vendor_name,
          f"{vendor_name}: results.json carries its vendor")
    check(data["worker_model"] == model,
          f"{vendor_name}: results.json carries its worker model")
    check(f"{root}/skills/demo" in run_log,
          f"{vendor_name}: the deployed-mode line names {root}/skills/demo")
    check(f"workers:        {m.vendor.DEFAULT_PARALLEL_WORKERS}" in run_log,
          f"{vendor_name}: --workers defaults to vendor.DEFAULT_PARALLEL_WORKERS")

    check(by_query["load"] == "demo",
          f"{vendor_name}: a skill load records demo")
    check(by_query["read"] == "demo",
          f"{vendor_name}: a read of the native SKILL.md records demo")
    check(by_query["compat"] == "demo",
          f"{vendor_name}: a read of the compatibility SKILL.md records demo")
    check(by_query["other"] is None,
          f"{vendor_name}: a first read of another path records no skill")
    check(by_query["shell"] is None,
          f"{vendor_name}: a first shell call records no skill")
    check(by_query["no_tool"] is None,
          f"{vendor_name}: a clean exit with no tool call records no skill")
    check(by_query["result_error"] == m.WORKER_FAILED,
          f"{vendor_name}: a result with is_error true records a failed worker")
    check(by_query["exit_nonzero"] == m.WORKER_FAILED,
          f"{vendor_name}: a non-zero exit before any tool records a failed worker")

    lines = [json.loads(line) for line in log.read_text().splitlines() if line.strip()]
    cwds = [Path(entry["cwd"]).resolve() for entry in lines]
    check(len(cwds) == len(set(cwds)),
          f"{vendor_name}: every worker has its own directory")
    check(all(repo_root != cwd and repo_root not in cwd.parents for cwd in cwds),
          f"{vendor_name}: every worker directory lies outside the checkout")
    check(all(not cwd.exists() for cwd in cwds),
          f"{vendor_name}: every worker directory is gone after the run")
    check(all(
        not any(flag in entry["argv"] for flag in ("--permission-mode", "--force", "--yolo"))
        for entry in lines
    ), f"{vendor_name}: no argv carries a permission override")
    if vendor_name == "cursor":
        ok = True
        for entry in lines:
            argv = entry["argv"]
            if "--output-format" not in argv or argv[argv.index("--output-format") + 1] != "stream-json":
                ok = False
            if "--trust" not in argv:
                ok = False
            if "--workspace" not in argv or argv[argv.index("--workspace") + 1] != entry["cwd"]:
                ok = False
        check(ok, "cursor: argv carries stream-json, --trust, and --workspace <worker dir>")

# --- Cursor drift warning over every skill root ----------------------------
drift_home = stage_home(".cursor", ".claude")
deploy_skill(drift_home, ".cursor", hermetic_src)
deploy_skill(drift_home, ".claude", hermetic_src,
             description="a different description")
drift_results = Path(tempfile.mkdtemp()) / "out"
drift_log = Path(tempfile.mkdtemp()) / "stub.log"
drift_rc, _drift_err = run_live(
    ["--vendor", "cursor", "--eval-set", str(hermetic_set), "--skill", "demo",
     "--skill-path", str(hermetic_src), "--results-dir", str(drift_results),
     "--worker-bin", str(stub_path), "--runs-per-query", "1"],
    drift_home,
    {"STUB_LOG": str(drift_log)},
)
drift_run_log = (drift_results / "run.log").read_text()
check("WARNING: deployed description differs from source" in drift_run_log,
      "cursor drift: warns about a differing copy")
check(".claude/skills/demo/SKILL.md" in drift_run_log,
      "cursor drift: names the differing compatibility copy")

# --- Cursor unavailability ignores a compatibility copy --------------------
missing_home = stage_home(".claude")
deploy_skill(missing_home, ".claude", hermetic_src)
missing_results = Path(tempfile.mkdtemp()) / "out"
missing_log = Path(tempfile.mkdtemp()) / "stub.log"
missing_rc, missing_err = run_live(
    ["--vendor", "cursor", "--eval-set", str(hermetic_set), "--skill", "demo",
     "--skill-path", str(hermetic_src), "--results-dir", str(missing_results),
     "--worker-bin", str(stub_path)],
    missing_home,
    {"STUB_LOG": str(missing_log)},
)
check(missing_rc != 0 and "unavailable" in missing_err.lower(),
      "cursor unavailable: exits non-zero naming the unavailability")
check(not (missing_results / "results.json").is_file(),
      "cursor unavailable: writes no scored results.json")
check(not missing_log.exists() or missing_log.read_text() == "",
      "cursor unavailable: starts no worker")

# --- Cursor rejects --force-uuid before any worker -------------------------
uuid_home = stage_home(".cursor")
deploy_skill(uuid_home, ".cursor", hermetic_src)
uuid_results = Path(tempfile.mkdtemp()) / "out"
uuid_log = Path(tempfile.mkdtemp()) / "stub.log"
uuid_rc, uuid_err = run_live(
    ["--vendor", "cursor", "--eval-set", str(hermetic_set), "--skill", "demo",
     "--skill-path", str(hermetic_src), "--results-dir", str(uuid_results),
     "--worker-bin", str(stub_path), "--force-uuid"],
    uuid_home,
    {"STUB_LOG": str(uuid_log)},
)
check(uuid_rc != 0 and "Claude-only" in uuid_err and "UUID-proxy" in uuid_err,
      "cursor --force-uuid: exits non-zero naming the UUID proxy as Claude-only")
check(not uuid_log.exists() or uuid_log.read_text() == "",
      "cursor --force-uuid: starts no worker")

# --- baseline vendor rule --------------------------------------------------
def baseline_run(current_vendor: str, baseline_vendor: str | None):
    root = ".cursor" if current_vendor == "cursor" else ".claude"
    home = stage_home(root)
    deploy_skill(home, root, hermetic_src)
    base = {"mode": "deployed", "results": [
        {"query": "load", "expected_skill": "demo", "precise_triggers": 1,
         "runs": 1, "precise_pass": True}]}
    if baseline_vendor is not None:
        base["vendor"] = baseline_vendor
    base_dir = write_baseline(base)
    results = Path(tempfile.mkdtemp()) / "out"
    log = Path(tempfile.mkdtemp()) / "stub.log"
    eval_path = stage_eval_set([{"query": "load", "expected_skill": "demo"}])
    rc, err = run_live(
        ["--vendor", current_vendor, "--eval-set", str(eval_path),
         "--skill", "demo", "--skill-path", str(hermetic_src),
         "--results-dir", str(results), "--worker-bin", str(stub_path),
         "--runs-per-query", "1", "--baseline", str(base_dir)],
        home,
        {"STUB_LOG": str(log)},
    )
    data = json.loads((results / "results.json").read_text())
    return rc, err, data

rc, err, data = baseline_run("cursor", "claude")
check(rc != 0 and "claude" in err and "cursor" in err,
      "baseline: a Cursor run given a Claude baseline exits non-zero naming both vendors")
check(data["vendor"] == "cursor" and "baseline_comparison" not in data,
      "baseline: the mismatched Cursor run keeps its vendor and no comparison")

rc, err, data = baseline_run("cursor", None)
check(rc != 0 and "claude" in err and "cursor" in err,
      "baseline: a missing vendor reads as claude and mismatches Cursor")
check(data["vendor"] == "cursor" and "baseline_comparison" not in data,
      "baseline: the missing-vendor Cursor run keeps its vendor and no comparison")

rc, err, data = baseline_run("claude", "cursor")
check(rc != 0 and "claude" in err and "cursor" in err,
      "baseline: a Claude run given a Cursor baseline exits non-zero naming both vendors")
check(data["vendor"] == "claude" and "baseline_comparison" not in data,
      "baseline: the mismatched Claude run keeps its vendor and no comparison")

rc, err, data = baseline_run("claude", None)
check("baseline_comparison" in data,
      "baseline: a Claude run given a missing-vendor baseline compares")

# --- escape guard: a worker writing into the checkout fails the run --------
escape_repo = Path(tempfile.mkdtemp())
(escape_repo / "tests" / "trigger_evals").mkdir(parents=True)
(escape_repo / "tests" / "lib").mkdir(parents=True)
for src, dest in (
    (run_dir / "run.py", escape_repo / "tests" / "trigger_evals" / "run.py"),
    (run_dir.parent / "lib" / "vendor.py", escape_repo / "tests" / "lib" / "vendor.py"),
    (run_dir.parent / "lib" / "micro_deploy.py", escape_repo / "tests" / "lib" / "micro_deploy.py"),
    (run_dir.parent / "lib" / "worker_io.py", escape_repo / "tests" / "lib" / "worker_io.py"),
):
    shutil.copy2(src, dest)
subprocess.run(["git", "init", "-q", str(escape_repo)], check=True)
subprocess.run(["git", "-C", str(escape_repo), "config", "user.email", "test@example.com"], check=True)
subprocess.run(["git", "-C", str(escape_repo), "config", "user.name", "Test"], check=True)
subprocess.run(["git", "-C", str(escape_repo), "add", "-A"], check=True)
subprocess.run(["git", "-C", str(escape_repo), "commit", "-q", "-m", "init"], check=True)

escape_home = stage_home(".claude")
deploy_skill(escape_home, ".claude", hermetic_src)
escape_results = Path(tempfile.mkdtemp()) / "out"
escape_log = Path(tempfile.mkdtemp()) / "stub.log"
escape_eval = stage_eval_set([{"query": "escape", "expected_skill": None}])
escape_file = escape_repo / "ESCAPE.txt"
env = os.environ.copy()
env["HOME"] = str(escape_home)
env["STUB_LOG"] = str(escape_log)
env["STUB_ESCAPE_PATH"] = str(escape_file)
escape_proc = subprocess.run(
    [sys.executable, str(escape_repo / "tests" / "trigger_evals" / "run.py"),
     "--vendor", "claude", "--eval-set", str(escape_eval), "--skill", "demo",
     "--skill-path", str(hermetic_src), "--results-dir", str(escape_results),
     "--worker-bin", str(stub_path), "--runs-per-query", "1"],
    capture_output=True, text=True, env=env,
)
check(escape_proc.returncode != 0,
      "escape guard: a worker write into the checkout fails the run")
check("ESCAPE.txt" in escape_proc.stderr,
      "escape guard: stderr names the changed path")
check(escape_file.is_file(),
      "escape guard: the stub really wrote into the checkout")

# --- hermetic git_review trigger-set schema check --------------------------
#
# Approach Route and register. requires every raw entry of the two-family
# set to carry an explicit expected_skill key and no should_trigger key, with
# both git_review and git_auto_review among the expected skills. The check
# reads the raw entries before run.py's normalize_eval_entry, so a
# should_trigger entry cannot slip through by being inferred instead.

def raw_set_error(path):
    """Return an error string when the raw set violates the schema, else None."""
    try:
        raw = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return f"cannot read the eval set: {exc}"
    if not isinstance(raw, list):
        return "the eval set is not a JSON array"
    seen = set()
    for i, entry in enumerate(raw):
        if "should_trigger" in entry:
            return f"entry {i} carries should_trigger, which the explicit form forbids"
        if "expected_skill" not in entry:
            return f"entry {i} lacks an explicit expected_skill key"
        if entry["expected_skill"] is not None:
            seen.add(entry["expected_skill"])
    for required in ("git_review", "git_auto_review"):
        if required not in seen:
            return f"the set never expects {required}"
    return None

git_set = run_dir / "git_review.json"
check(raw_set_error(git_set) is None,
      "git_review set: every raw entry carries expected_skill and no should_trigger")
check(git_set.is_file() and len(json.loads(git_set.read_text())) >= 1,
      "git_review set: the file exists and is non-empty")

mutated_dir = Path(tempfile.mkdtemp())
mutated = mutated_dir / "git_review.json"
raw_entries = json.loads(git_set.read_text())
raw_entries[0] = {"query": raw_entries[0]["query"], "should_trigger": True}
mutated.write_text(json.dumps(raw_entries))
check(raw_set_error(mutated) is not None,
      "git_review set: a should_trigger entry without expected_skill is rejected")

print()
if fails:
    print(f"FAIL: {len(fails)} assertion(s) failed")
    sys.exit(1)
print("PASS: baseline regression detector + mode-selection + per-vendor worker guards")
PY
