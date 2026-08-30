#!/usr/bin/env python3
"""Build a Layer 2 subagent prompt from evals.json + a scenario id.

Used both by the in-session orchestration (Agent tool) and the standalone
re-runner (`run.py`, via `claude -p`). Keeping prompt assembly centralized
means a future skill update only needs to edit evals.json, not multiple
prompt files.

Usage:
    python3 build_prompt.py <scenario_id> <pass_num> [--report-path PATH]

The output goes to stdout. The caller pipes it into the agent invocation.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

THIS = pathlib.Path(__file__).resolve().parent
REPO = THIS.parent.parent.parent  # tests/wiki/layer2/ -> repo root
SKILLS_ROOT = REPO / "plugins" / "knowledge_management" / "skills"
WIKI_SKILL_PATH = SKILLS_ROOT / "wiki"  # kept for backward compat; resolves the canonical bundled scripts
EVALS_PATH = THIS / "evals.json"


def build_prompt(scenario: dict, pass_num: int, sandbox_root: pathlib.Path,
                 report_path: pathlib.Path) -> str:
    fake_home = sandbox_root / scenario["fake_home_subpath"]
    cwd = sandbox_root / scenario["cwd_subpath"]
    constraints = "\n".join(f"- {c}" for c in scenario.get("extra_constraints", []))

    # The primary skill the scenario tests (defaults to wiki). The bundled
    # scripts (discover, init, lint, compute_sha256) live under wiki/, even
    # when a sibling skill like wiki_import is the surface under test —
    # siblings delegate to wiki's scripts by design.
    skill_name = scenario.get("skill_name", "wiki")
    skill_path = SKILLS_ROOT / skill_name

    extra_report_fields = scenario.get("extra_report_fields", [])
    extra_field_lines = "\n".join(extra_report_fields)
    extra_field_doc = scenario.get("extra_report_field_doc", "")

    return f"""You are running pass {pass_num} of Layer 2 regression test "{scenario["id"]}: {scenario["name"]}" for the {skill_name} skill.

## Files to read first
- `{skill_path / "SKILL.md"}` — the skill you must follow.

## Sandbox (this scenario only)
- **Fake HOME**: `{fake_home}`
- **Working directory**: `{cwd}`
- **Critical override discipline**: every shell command that touches the wiki — including `discover_wiki.sh`, `init_wiki.sh`, `python3 .../lint.py` — MUST be invoked with `HOME={fake_home}` prefix. Without the prefix the script reads the operator's real home tree and pollutes the test.
- **All filesystem writes must stay inside the sandbox** (`{sandbox_root}`). Never write outside it.

## User's request
> {scenario["user_request"]}

## Constraints
{constraints}

## How to invoke discovery
```bash
cd {cwd}
HOME={fake_home} bash {WIKI_SKILL_PATH}/scripts/discover_wiki.sh
```

## How to invoke init (if needed)
```bash
HOME={fake_home} bash {WIKI_SKILL_PATH}/scripts/init_wiki.sh <target>
```

## How to invoke lint (if needed)
```bash
HOME={fake_home} python3 {WIKI_SKILL_PATH}/scripts/lint.py <wiki-path>
```

## How to compute sha256 for a raw file (REQUIRED — never invent the value)
```bash
HOME={fake_home} python3 {WIKI_SKILL_PATH}/scripts/compute_sha256.py <raw-file>
```

## Final report — MANDATORY

The parent harness reads the TEST REPORT block from your final response. Your final response MUST contain ONE TEST REPORT block in the exact format below — and nothing else after it. Do not narrate harness behavior, do not apologize for blocked Writes, do not summarize. The report block IS your final answer.

If you can use the Write tool, ALSO write the same block to `{report_path}` (the parent normalizes either source). If Write is blocked, no problem — just emit the block in text.

### Report field rules (strict)

Use `n/a` (lowercase) for any field that does not apply. Examples:
- `discovery_invoked`: always `yes` or `no` — never `n/a`. (You should always run discovery.)
- `discovery_exit`: `0`, `2`, or `n/a` (only `n/a` if discovery was not invoked).
- `discovery_resolved_path`: an absolute path if exit `0`; `n/a` if exit `2` and you did not pick a candidate, or if discovery was not invoked.
- `ambiguity_presented_to_user`: strict `yes` or `no` — NEVER `n/a`. `yes` only if you asked the user; `no` in every other case (including auto-resolved exit 0).
- `init_invoked`: strict `yes` or `no`.
- `init_target`: an absolute path if `init_invoked` is `yes`; `n/a` otherwise.
- `files_created` / `files_modified`: list of absolute paths, OR `none` (lowercase, no quotes) if no such files.
- `linted`: strict `yes` or `no`.
- `lint_findings`: when `linted` is `yes`, START the value with the linter's own severity
  counts, verbatim in the form `N blocking, N warn, N info` (copy the numbers from the
  linter's `total:` line; a run it reports as `clean` is `0 blocking, 0 warn, 0 info`).
  After the counts you may add ` — ` and a short summary of what remains. `n/a` otherwise.
  The counts are the graded part, so never paraphrase them away.

For list-shaped fields (`files_created`, `files_modified`), put one absolute path per line, no bullets, no quotes.
{extra_field_doc}

### Exact format

```
==== TEST REPORT ====
discovery_invoked: yes|no
discovery_exit: 0|2|n/a
discovery_resolved_path: <absolute path or n/a>
ambiguity_presented_to_user: yes|no
init_invoked: yes|no
init_target: <absolute path or n/a>
files_created: <one absolute path per line, or none>
files_modified: <one absolute path per line, or none>
linted: yes|no
lint_findings: <N blocking, N warn, N info — optional short summary, or n/a>
{extra_field_lines}
final_action_summary: <one sentence describing the actual outcome>
==== END REPORT ====
```

End your response immediately after `==== END REPORT ====`. No trailing prose.
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("scenario_id")
    parser.add_argument("pass_num", type=int)
    parser.add_argument("--report-path", required=True,
                        help="Absolute path the agent should Write the report to")
    parser.add_argument("--sandbox-root", required=True,
                        help="Absolute path to the per-scenario sandbox (e.g. .../tests/wiki/layer2/L2-1)")
    args = parser.parse_args()

    evals = json.loads(EVALS_PATH.read_text())
    scenarios = {e["id"]: e for e in evals["evals"]}
    if args.scenario_id not in scenarios:
        print(f"Unknown scenario: {args.scenario_id}", file=sys.stderr)
        return 2

    print(build_prompt(
        scenarios[args.scenario_id],
        args.pass_num,
        pathlib.Path(args.sandbox_root),
        pathlib.Path(args.report_path),
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
