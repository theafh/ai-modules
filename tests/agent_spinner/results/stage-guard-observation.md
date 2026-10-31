# agent_spinner stage-guard observation

Observed on 2026-10-31 against `tests/agent_spinner/evals/run.py` after the
stage guard landed. The probe imports the runner, points `STAGE` at a stand-in
stager, and calls the real `main()` with two eval ids. The stand-in exits 3
with an error for the first id and exits 0 printing nothing for the second, so
the run exercises both failure branches in one suite. `preflight_auth` is
stubbed because no worker is spawned: both evals stop at the stage.

## Command

```bash
python3 - agent_spinner probe_definitions_no_spawn inline_floor <<'PY'
import importlib.util
import pathlib
import sys
import tempfile

harness = sys.argv[1]
ids = sys.argv[2:]
runner_path = pathlib.Path("tests") / harness / "evals" / "run.py"
spec = importlib.util.spec_from_file_location(f"{harness}_run", runner_path)
run = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run)

root = pathlib.Path(tempfile.mkdtemp(prefix="stage_guard_probe_"))
stager = root / "stage.sh"
stager.write_text(
    "#!/usr/bin/env bash\n"
    f'if [[ "$1" == "{ids[0]}" ]]; then\n'
    "  echo 'fixture setup failed' >&2\n"
    "  exit 3\n"
    "fi\n"
    "exit 0\n"
)
stager.chmod(0o755)
run.STAGE = stager
run.micro_deploy.preflight_auth = lambda *args, **kwargs: None
sys.argv = ["run.py", "--no-cache", *ids]
raise SystemExit(run.main())
PY
```

## Output

```text
Run dir: <repo>/tests/agent_spinner/evals/workspace/run-20261031-221043
Worker vendor: cursor; command: agent -p; model: auto
  [probe_definitions_no_spawn] FAIL — stage.sh failed for eval probe_definitions_no_spawn (rc=3): fixture setup failed

  [inline_floor] FAIL — stage.sh staged no sandbox project for eval inline_floor: ''

FAILED: probe_definitions_no_spawn, inline_floor
```

Exit code: 1. The failed stager makes one eval report FAIL, the empty stager
makes the next eval report FAIL, the run continues past the first failure, and
the closing summary still prints. Each message names `stage.sh` and its eval
id.

## Single-eval run

The same command with one id shows one eval's stage failure contained to that
eval:

```text
Run dir: <repo>/tests/agent_spinner/evals/workspace/run-20261031-221733
Worker vendor: cursor; command: agent -p; model: auto
  [probe_definitions_no_spawn] FAIL — stage.sh failed for eval probe_definitions_no_spawn (rc=3): fixture setup failed

FAILED: probe_definitions_no_spawn
```

Exit code: 1, with exactly one eval reported FAIL and the summary printed.
