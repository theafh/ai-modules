#!/usr/bin/env bash
# Bundled-script unit tests for tests/trigger_evals/run.py.
#
# Hermetic: exercises the baseline-regression detector and the
# deployed-versus-unavailable-versus-`--force-uuid` mode-selection guards
# with synthetic fixtures and stubbed mode runners, so nothing here depends
# on recorded runs under results/ (gitignored) or on spawning a `claude`
# worker. Fast, deterministic, no LLM cost.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - "$HERE/.." <<'PY'
import importlib.util, json, sys, tempfile
from pathlib import Path

run_dir = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("trun", run_dir / "run.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

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
import contextlib, io, os, shutil

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

def stage_home():
    home = Path(tempfile.mkdtemp())
    (home / ".claude" / "skills").mkdir(parents=True)
    return home

def stage_skill(root: Path, name: str = "demo"):
    skill = root / name
    skill.mkdir(parents=True)
    (skill / "SKILL.md").write_text(
        "---\nname: demo\ndescription: demo skill for hermetic mode tests\n---\n\n# demo\n"
    )
    return skill

def stage_eval_set():
    d = Path(tempfile.mkdtemp())
    p = d / "demo.json"
    p.write_text(json.dumps([{"query": "do the demo thing", "expected_skill": "demo"}]))
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

# --- has_score_fields detects a real score (fail-branch control)
scored = Path(tempfile.mkdtemp()) / "results.json"
scored.write_text(json.dumps({"summary": {"precise_passed": 1}}))
check(has_score_fields(scored),
      "has_score_fields: detects precise_passed in summary")
check(not has_score_fields(Path(tempfile.mkdtemp()) / "missing.json"),
      "has_score_fields: missing file is not scored")

eval_set = stage_eval_set()
skill_src = stage_skill(Path(tempfile.mkdtemp()))

# (0) an explicit --vendor cursor stops with an error before either mode runs;
# without --vendor this Claude-only harness defaults to Claude (cases below)
calls["uuid"] = calls["deployed"] = 0
try:
    run_main(
        ["--vendor", "cursor", "--eval-set", str(eval_set), "--skill", "demo",
         "--skill-path", str(skill_src)],
        stage_home(),
    )
    cursor_exit = None
except SystemExit as exc:
    cursor_exit = str(exc)
check(cursor_exit is not None and "does not support `--vendor cursor`" in cursor_exit,
      "explicit --vendor cursor: stops with an error")
check(calls["uuid"] == 0 and calls["deployed"] == 0,
      "explicit --vendor cursor: neither mode runner is called")

# (1) unavailable without --force-uuid → named failure, no score
home1 = stage_home()
results1 = Path(tempfile.mkdtemp()) / "out"
calls["uuid"] = calls["deployed"] = 0
rc1, err1 = run_main(
    ["--eval-set", str(eval_set), "--skill", "demo",
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
home2 = stage_home()
results2 = Path(tempfile.mkdtemp()) / "out"
calls["uuid"] = calls["deployed"] = 0
rc2, _err2 = run_main(
    ["--eval-set", str(eval_set), "--skill", "demo",
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
home3 = stage_home()
deployed = home3 / ".claude" / "skills" / "demo"
deployed.mkdir(parents=True)
(deployed / "SKILL.md").write_text(skill_src.joinpath("SKILL.md").read_text())
results3 = Path(tempfile.mkdtemp()) / "out"
calls["uuid"] = calls["deployed"] = 0
rc3, err3 = run_main(
    ["--eval-set", str(eval_set), "--skill", "demo",
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
home4 = stage_home()
results4 = Path(tempfile.mkdtemp()) / "out"
calls["uuid"] = calls["deployed"] = 0
rc4, err4 = run_main(
    ["--eval-set", str(eval_set), "--skill", "demo_no_default_path",
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

print()
if fails:
    print(f"FAIL: {len(fails)} assertion(s) failed")
    sys.exit(1)
print("PASS: baseline regression detector + mode-selection guards")
PY
