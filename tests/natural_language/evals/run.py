#!/usr/bin/env python3
"""Multi-pass runner for the natural-language output-style evals.

Each scenario runs over a fixed denominator of passes (default 5). The bar is
every assertion holding on every pass. A scenario that misses the bar reports
its measured rate and the diverging assertions. The run does not repeat a
scenario for a better draw. There is no verdict cache.

Passes run concurrently (`--workers`, default `vendor.DEFAULT_PARALLEL_WORKERS`).
Each pass owns an isolated sandbox from `tests/lib/worker_isolation.py`.

The harness exercises Claude output-style selection, so `--vendor cursor` is
refused with an error while the runner defaults to Claude: a scenario run is a
Claude run, made where a change to the style needs it, and its command names
`--vendor claude` so the Claude run is visible. Every worker and every judge
takes its sandbox root and its worker arguments from the isolation helper. The
style under test is micro-deployed
through the deploy script (`--only natural-language`) into the sandbox project
and a scratch config home, and each worker's reads are classified against that
deployment. The preflight marker style is written into the project after the
micro-deployment and is never part of `--only`. A scenario worker is asked only
to rewrite the staged draft or to answer the staged question. It is not given a
path to the style file.

Usage:
    python3 tests/natural_language/evals/run.py --vendor claude [scenario ...]
      [--passes 5] [--workers 4]
      [--style styles/natural-language.md] [--run-label baseline|refined]
      [--preflight malformed]
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import json
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time

THIS = pathlib.Path(__file__).resolve().parent
HARNESS = THIS.parent
REPO = THIS.parents[2]
STAGE = THIS / "stage.sh"
GRADE = THIS / "grade.py"
WORKSPACE = HARNESS / "workspace"
RESULTS = HARNESS / "results"
DEFAULT_STYLE = REPO / "styles" / "natural-language.md"
PROBE_VERSION = (2, 1, 226)
MARKER_NAME = "nl_load_marker"
MARKER_TOKEN = "NL_STYLE_LOAD_OK"
MARKER_BODY = (
    "Begin every reply with the exact token NL_STYLE_LOAD_OK "
    "on its own first line, then stop."
)
MALFORMED_SETTINGS = '{\n  "outputStyle": "nl_load_marker",\n}\n'

sys.path.insert(0, str(THIS.parents[1] / "lib"))
import micro_deploy  # noqa: E402
import vendor  # noqa: E402
from worker_io import as_text  # noqa: E402
import worker_isolation  # noqa: E402

import judge as judge_mod  # noqa: E402

SCENARIOS = ["connected_rewrite", "chat_brevity"]
ARTEFACTS = ["natural-language"]
PRINT_LOCK = threading.Lock()

REWRITE_PROMPT = """\
Rewrite the staged draft under the active output style. Do exactly this:

1. Read draft.md in the current directory.
2. Rewrite it so a reader follows the reasoning on the first read.
3. Save only the rewritten document, with no commentary around it, to delivered.md in the current directory.
4. Leave draft.md unchanged.

{prompt}
"""

CHAT_PROMPT = """\
Answer the staged question. Do exactly this:

1. Read question.md and context.md in the current directory.
2. Answer the question in your reply.

{prompt}
"""


def emit(*lines: str) -> None:
    with PRINT_LOCK:
        for line in lines:
            print(line, flush=True)


def style_name(path: pathlib.Path) -> str:
    match = re.search(r"(?m)^name:\s*(\S+)\s*$", path.read_text())
    if match:
        return match.group(1)
    return path.stem


def version_tuple(text: str) -> tuple[int, int, int] | None:
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", text)
    if match is None:
        return None
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)))


def cli_version(binary: str) -> str:
    try:
        result = subprocess.run(
            [binary, "--version"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as err:
        return f"unavailable ({err})"
    text = (result.stdout or result.stderr).strip()
    return text or "unavailable"


def abort_on_malformed_settings(settings_text: str) -> None:
    """Abort before any scenario pass when settings.json will not parse.

    A trailing comma is the shape that drops outputStyle without an error.
    """

    try:
        json.loads(settings_text)
    except json.JSONDecodeError as err:
        raise SystemExit(
            "preflight abort: sandbox .claude/settings.json is malformed "
            f"({err}). A trailing comma drops outputStyle without an error. "
            "No scenario pass started."
        ) from err


def write_settings(proj: pathlib.Path, selected: str) -> None:
    settings_text = json.dumps({"outputStyle": selected}, indent=2) + "\n"
    abort_on_malformed_settings(settings_text)
    settings_path = proj / ".claude" / "settings.json"
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    if settings_path.is_file():
        try:
            merged = json.loads(settings_path.read_text())
        except json.JSONDecodeError:
            merged = {}
        if isinstance(merged, dict):
            merged["outputStyle"] = selected
            settings_text = json.dumps(merged, indent=2) + "\n"
            abort_on_malformed_settings(settings_text)
    settings_path.write_text(settings_text)


def stage_marker(proj: pathlib.Path) -> None:
    styles = proj / ".claude" / "output-styles"
    styles.mkdir(parents=True, exist_ok=True)
    marker = (
        "---\n"
        f"name: {MARKER_NAME}\n"
        "description: Preflight marker.\n"
        "---\n"
        "\n"
        f"{MARKER_BODY}\n"
    )
    (styles / f"{MARKER_NAME}.md").write_text(marker)
    write_settings(proj, MARKER_NAME)


def stage_style(proj: pathlib.Path, style_path: pathlib.Path) -> pathlib.Path:
    """Select the style under test for the project after the micro-deployment.

    The default repository style arrives through the deploy script, so only
    the outputStyle selection is written. A custom ``--style`` file is copied
    over the project's output-styles directory first.
    """

    styles = proj / ".claude" / "output-styles"
    styles.mkdir(parents=True, exist_ok=True)
    selected = style_name(style_path)
    dest = styles / f"{selected}.md"
    if style_path.resolve() != DEFAULT_STYLE.resolve() or not dest.is_file():
        shutil.copyfile(style_path, dest)
    write_settings(proj, selected)
    return dest


def run_worker(
    deploy: micro_deploy.MicroDeployHandle,
    proj: pathlib.Path,
    prompt: str,
    resolved: vendor.Resolved,
    timeout: int,
    extra_args: list[str],
) -> tuple[int, str, str, float, dict]:
    start = time.time()
    worker = micro_deploy.run_worker(
        vendor_name=resolved.vendor,
        bin_name=resolved.bin,
        model=resolved.worker_model,
        prompt=prompt,
        deploy=deploy,
        timeout=timeout,
        cwd=proj,
        extra_args=extra_args,
    )
    integrity = micro_deploy.integrity_record(
        worker.read_paths, worker.out_of_set_paths
    )
    return (
        worker.returncode,
        worker.stdout,
        worker.stderr,
        time.time() - start,
        integrity,
    )


def run_malformed_preflight(resolved: vendor.Resolved) -> None:
    """Stage a trailing-comma settings.json and abort before any scenario."""

    root = worker_isolation.create_sandbox_root("nl_malformed_")
    proj = root / "proj"
    proj.mkdir()
    try:
        styles = proj / ".claude" / "output-styles"
        styles.mkdir(parents=True)
        (styles / f"{MARKER_NAME}.md").write_text(MARKER_BODY + "\n")
        settings_path = proj / ".claude" / "settings.json"
        settings_path.write_text(MALFORMED_SETTINGS)
        abort_on_malformed_settings(settings_path.read_text())
    finally:
        shutil.rmtree(root, ignore_errors=True)


def marker_preflight(resolved: vendor.Resolved, timeout: int) -> dict:
    root = worker_isolation.create_sandbox_root("nl_marker_")
    proj = root / "proj"
    proj.mkdir()
    try:
        # The marker style is written after the micro-deployment and never
        # joins --only, so the deployed layout stays what a user would get.
        with micro_deploy.micro_deploy(
            resolved.vendor, ARTEFACTS, proj, preflight=False
        ) as md:
            stage_marker(proj)
            code, stdout, stderr, duration, _integrity = run_worker(
                md,
                proj,
                "Reply.",
                resolved,
                timeout,
                worker_isolation.isolation_args(resolved.vendor),
            )
    finally:
        shutil.rmtree(root, ignore_errors=True)
    present = MARKER_TOKEN in stdout
    return {
        "marker_present": present,
        "worker_rc": code,
        "duration_s": duration,
        "reply_excerpt": stdout.strip()[:400],
        "stderr_excerpt": stderr.strip()[:400],
    }


def select_style_route(preflight: dict, version: str) -> tuple[bool, str]:
    """Return whether to append the style and the route recorded in results."""

    if preflight.get("marker_present"):
        return False, "outputStyle"

    parsed = version_tuple(version)
    if parsed is None or parsed <= PROBE_VERSION:
        raise SystemExit(
            "preflight abort: the marker NL_STYLE_LOAD_OK is missing and "
            f"the CLI version {version!r} is not newer than 2.1.226. "
            "No scenario pass started."
        )
    return True, "append-system-prompt-file"


def stage(scenario: str, target: pathlib.Path) -> dict:
    emit_cmd = (
        f'eval "$({shlex.quote(str(STAGE))} {shlex.quote(scenario)} '
        f'{shlex.quote(str(target))})"; '
        'printf "%s\\0%s\\0%s\\0" "$sandbox_proj" "$source_file" "$prompt"'
    )
    out = subprocess.run(
        ["bash", "-c", emit_cmd],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    sandbox_proj, source_file, prompt, _trailing = out.split("\0")
    return {
        "sandbox_proj": sandbox_proj,
        "source_file": source_file,
        "prompt": prompt,
    }


def run_pass(
    scenario: str,
    number: int,
    run_dir: pathlib.Path,
    args,
    resolved: vendor.Resolved,
    style_path: pathlib.Path,
    use_append: bool,
) -> dict:
    pass_dir = run_dir / scenario / f"pass-{number}"
    pass_dir.mkdir(parents=True, exist_ok=True)
    root = worker_isolation.create_sandbox_root(f"nl_{scenario}_{number}_")
    try:
        staged = stage(scenario, root)
        proj = pathlib.Path(staged["sandbox_proj"])
        template = REWRITE_PROMPT if scenario == "connected_rewrite" else CHAT_PROMPT
        prompt = template.format(prompt=staged["prompt"])
        emit(
            f"  [{scenario} pass-{number}] running {resolved.config.label} ..."
        )
        with micro_deploy.micro_deploy(
            resolved.vendor, ARTEFACTS, proj, preflight=False
        ) as md:
            staged_style = stage_style(proj, style_path)
            extra = worker_isolation.isolation_args(resolved.vendor)
            if use_append:
                extra = extra + ["--append-system-prompt-file", str(staged_style)]
            code, stdout, stderr, duration, integrity_record = run_worker(
                md, proj, prompt, resolved, args.timeout, extra
            )
        stdout, stderr = as_text(stdout), as_text(stderr)
        (pass_dir / "response.txt").write_text(stdout)
        (pass_dir / "stderr.txt").write_text(stderr)
        if scenario == "chat_brevity":
            (proj / "response.txt").write_text(stdout)

        completed = code == 0 and bool(stdout.strip())
        graded = subprocess.run(
            [
                sys.executable,
                str(GRADE),
                scenario,
                str(proj),
                staged["source_file"],
                "--json",
            ],
            capture_output=True,
            text=True,
        )
        try:
            mechanical = json.loads(graded.stdout)
        except json.JSONDecodeError:
            mechanical = {
                "passed": False,
                "mechanical": {},
                "integrity": {},
                "error": (graded.stderr or graded.stdout)[:400],
            }

        delivered_path = proj / "delivered.md"
        response_path = proj / "response.txt"
        pristine = proj.parent / ".fixture_pristine"
        if args.skip_judge or not completed:
            qualitative: dict = {}
        else:
            if scenario == "connected_rewrite":
                delivered_text = (
                    delivered_path.read_text() if delivered_path.exists() else ""
                )
            else:
                delivered_text = stdout
            qualitative = judge_mod.judge(
                scenario,
                pristine.read_text() if pristine.exists() else "",
                delivered_text,
                stdout,
                resolved.vendor,
                resolved.bin,
                resolved.judge_model or "",
                args.judge_timeout,
            )

        assertions = {
            **{key: value["passed"] for key, value in mechanical.get("mechanical", {}).items()},
            **{key: value["passed"] for key, value in qualitative.items()},
        }
        integrity = {
            key: value["passed"] for key, value in mechanical.get("integrity", {}).items()
        }
        integrity["artefacts_read_from_micro_deployment"] = integrity_record["passed"]
        void = (
            scenario == "connected_rewrite"
            and completed
            and not integrity.get("delivered_file_written", True)
        )
        if void:
            assertions = {}
        passed = (
            completed
            and not void
            and all(assertions.values())
            and all(integrity.values())
        )
        if delivered_path.exists():
            shutil.copyfile(delivered_path, pass_dir / "delivered.md")
        if response_path.exists() and scenario == "chat_brevity":
            shutil.copyfile(response_path, pass_dir / "response.txt")
        verdict = {
            "scenario": scenario,
            "pass": number,
            "passed": passed,
            "void": void,
            "void_reason": (
                "worker answered but never wrote delivered.md" if void else None
            ),
            "worker_completed": completed,
            "worker_rc": code,
            "duration_s": duration,
            "delivered_words": mechanical.get("delivered_words"),
            "fixture_words": mechanical.get("fixture_words"),
            "assertions": assertions,
            "integrity": integrity,
            "mechanical_detail": mechanical.get("mechanical", {}),
            "judge_detail": qualitative,
            "artefacts_read_from_micro_deployment": integrity_record,
        }
        (pass_dir / "verdict.json").write_text(json.dumps(verdict, indent=2))
        diverging = [key for key, ok in {**assertions, **integrity}.items() if not ok]
        if void:
            label, tail = "VOID", ", worker answered but never wrote delivered.md"
        else:
            label = "PASS" if passed else "FAIL"
            tail = "" if passed else (
                f", diverging: {', '.join(diverging) or 'worker did not complete'}"
            )
        emit(
            f"  [{scenario} pass-{number}] {label} "
            f"({mechanical.get('delivered_words')}w/"
            f"{mechanical.get('fixture_words')}w, {duration:.0f}s){tail}"
        )
        return verdict
    finally:
        shutil.rmtree(root, ignore_errors=True)


def summarize(results: dict, denominator: int) -> dict:
    summary = {"denominator": denominator, "scenarios": {}}
    for scenario, verdicts in results.items():
        clean = sum(1 for verdict in verdicts if verdict["passed"])
        voids = [verdict["pass"] for verdict in verdicts if verdict.get("void")]
        measured = [verdict for verdict in verdicts if not verdict.get("void")]
        names = sorted({
            key
            for verdict in measured
            for key in list(verdict["assertions"]) + list(verdict["integrity"])
        })
        per_assertion = {}
        for name in names:
            hits = sum(
                1
                for verdict in measured
                if {**verdict["assertions"], **verdict["integrity"]}.get(name) is True
            )
            per_assertion[name] = f"{hits}/{len(measured)}"
        diverging = {
            name: rate
            for name, rate in per_assertion.items()
            if rate != f"{len(measured)}/{len(measured)}"
        }
        summary["scenarios"][scenario] = {
            "pass_rate": f"{clean}/{denominator}",
            "met_bar": clean == denominator,
            "void_passes": voids,
            "measured_passes": len(measured),
            "per_assertion": per_assertion,
            "diverging_assertions": diverging,
            "delivered_words": [verdict["delivered_words"] for verdict in verdicts],
            "fixture_words": next(
                (
                    verdict["fixture_words"]
                    for verdict in verdicts
                    if verdict.get("fixture_words")
                ),
                None,
            ),
        }
    summary["all_scenarios_met_bar"] = all(
        scenario["met_bar"] for scenario in summary["scenarios"].values()
    )
    return summary


def render(summary: dict) -> str:
    lines = [
        f"# natural_language eval run with a denominator of {summary['denominator']}",
        "",
        f"Run label: {summary.get('run_label', 'measurement')}",
        "",
        f"CLI version: {summary.get('cli_version', 'unrecorded')}",
        "",
        f"Preflight: {json.dumps(summary.get('preflight', {}), indent=2)}",
        "",
    ]
    if summary.get("fixture_does_not_discriminate"):
        lines.extend([
            "The fixture does not discriminate: the baseline style passed every "
            "connected_rewrite assertion in the scenario inventory. Read this "
            "finding before the refined-style result.",
            "",
        ])
    for scenario, item in summary["scenarios"].items():
        status = "met the bar" if item["met_bar"] else "below the bar"
        lines.append(f"## {scenario} passed {item['pass_rate']} ({status})")
        lines.append("")
        lines.append(
            f"Delivered word counts per pass: {item['delivered_words']} "
            f"(fixture: {item['fixture_words']})"
        )
        lines.append("")
        if item.get("void_passes"):
            lines.append(
                f"Void passes (worker answered but never wrote delivered.md): "
                f"{item['void_passes']}. These count against the fixed denominator "
                f"and are excluded from the per-assertion rates below, which run "
                f"over {item['measured_passes']} measured pass(es)."
            )
            lines.append("")
        if item["diverging_assertions"]:
            lines.append("Diverging assertions:")
            lines.append("")
            for name, rate in item["diverging_assertions"].items():
                lines.append(f"- `{name}` held on {rate}")
            lines.append("")
            lines.append(
                "This report records the measured rate and the diverging "
                "assertions. The disposition belongs to the operator. The run "
                "does not repeat the scenario for a better draw."
            )
        else:
            lines.append("Every assertion held on every measured pass.")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("scenarios", nargs="*", default=None)
    parser.add_argument("--passes", type=int, default=5)
    parser.add_argument(
        "--workers",
        type=int,
        default=vendor.DEFAULT_PARALLEL_WORKERS,
        help=(
            "Passes run concurrently, up to this many "
            f"(default: {vendor.DEFAULT_PARALLEL_WORKERS}). "
            "Each pass owns its own isolated sandbox."
        ),
    )
    vendor.add_vendor_arguments(parser, with_judge=True, harness_id="natural_language")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--judge-timeout", type=int, default=300)
    parser.add_argument("--style", default=str(DEFAULT_STYLE))
    parser.add_argument(
        "--run-label",
        default="measurement",
        choices=("measurement", "baseline", "refined"),
    )
    parser.add_argument(
        "--preflight",
        default="run",
        choices=("run", "malformed"),
        help="malformed aborts on a trailing-comma settings.json before any scenario.",
    )
    parser.add_argument("--skip-judge", action="store_true")
    args = parser.parse_args()
    vendor.require_vendor_allowed(args.vendor, "natural_language")
    resolved = vendor.resolve(args, with_judge=True)

    if args.preflight == "malformed":
        run_malformed_preflight(resolved)
        return 0

    style_path = pathlib.Path(args.style).resolve()
    if not style_path.is_file():
        raise SystemExit(f"style file not found: {style_path}")

    scenarios = args.scenarios or SCENARIOS
    for scenario in scenarios:
        if scenario not in SCENARIOS:
            raise SystemExit(
                f"unknown scenario: {scenario} (known: {', '.join(SCENARIOS)})"
            )

    version = cli_version(resolved.bin)
    print(f"CLI version: {version}")
    # Workers run in the micro-deployment environment and the judge in the host
    # worker environment, so both logins are probed before the marker preflight.
    vendor.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)
    micro_deploy.preflight_auth(resolved.vendor, resolved.bin, resolved.worker_model)
    preflight = marker_preflight(resolved, args.timeout)
    print(f"Preflight: {json.dumps(preflight)}")
    use_append, route = select_style_route(preflight, version)
    if use_append:
        print(
            "Marker missing on a CLI newer than 2.1.226. "
            "Continuing with --append-system-prompt-file. "
            "This route appends the style file to the default prompt."
        )
    preflight["route"] = route
    preflight["probe_version"] = "2.1.226"
    preflight["cli_version_raw"] = version

    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = WORKSPACE / f"run-{timestamp}"
    run_dir.mkdir(parents=True)
    print(f"Run dir: {run_dir}")
    print(f"Style: {style_path}")
    print(f"Scenarios: {scenarios}; passes per scenario: {args.passes}\n")

    jobs = [(scenario, number) for scenario in scenarios for number in range(1, args.passes + 1)]
    workers = max(1, min(args.workers, len(jobs)))
    print(f"Running {len(jobs)} passes across {workers} concurrent worker(s)\n")

    wall_start = time.time()
    verdicts: dict[tuple[str, int], dict] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(
                run_pass,
                scenario,
                number,
                run_dir,
                args,
                resolved,
                style_path,
                use_append,
            ): (scenario, number)
            for scenario, number in jobs
        }
        for future in concurrent.futures.as_completed(futures):
            scenario, number = futures[future]
            try:
                verdicts[(scenario, number)] = future.result()
            except Exception as exc:
                emit(f"  [{scenario} pass-{number}] ERROR, harness fault: {exc!r}")
                verdicts[(scenario, number)] = {
                    "scenario": scenario,
                    "pass": number,
                    "passed": False,
                    "void": False,
                    "worker_completed": False,
                    "harness_error": repr(exc),
                    "assertions": {},
                    "integrity": {"harness_ran": False},
                    "delivered_words": None,
                    "fixture_words": None,
                }
    wall_s = time.time() - wall_start
    results = {
        scenario: [verdicts[(scenario, number)] for number in range(1, args.passes + 1)]
        for scenario in scenarios
    }
    print(f"\nAll {len(jobs)} passes done in {wall_s / 60:.1f} min wall-clock\n")

    summary = summarize(results, args.passes)
    summary["cli_version"] = version
    summary["preflight"] = preflight
    summary["run_label"] = args.run_label
    try:
        summary["style"] = str(style_path.relative_to(REPO))
    except ValueError:
        summary["style"] = style_path.name
    connected = summary["scenarios"].get("connected_rewrite")
    summary["fixture_does_not_discriminate"] = bool(
        args.run_label == "baseline" and connected and connected["met_bar"]
    )
    report = render(summary)
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    (run_dir / "summary.md").write_text(report)
    RESULTS.mkdir(parents=True, exist_ok=True)
    (RESULTS / f"run-{timestamp}.md").write_text(report)
    (RESULTS / f"run-{timestamp}.json").write_text(json.dumps(summary, indent=2))
    print("=" * 60)
    print(report)
    print(f"Recorded: {RESULTS}/run-{timestamp}.json")
    return 0 if summary["all_scenarios_met_bar"] else 1


if __name__ == "__main__":
    sys.exit(main())
