# evals/ — language_humanizer behavioral evals

Three scenarios, each run over a fixed denominator of passes. `evals.json`
carries the canonical schema (`id`, `prompt`, `expected_output`, `files`,
`expectations[]`) plus a `path` field naming which of the skill's two paths the
scenario exercises and a `passes` field recording the intended denominator.

## The pieces

| File | Role |
| --- | --- |
| `stage.sh <id> [target]` | Stages one fixture and prints `sandbox_proj`, `source_file`, `skill_name`, `skill_path`, `prompt` as `printf %q`-quoted `name=value` lines. Also drops a pristine copy of the fixture at `<target>/.fixture_pristine`. |
| `fixtures/<id>/setup.sh <target>` | Writes the fixture document into `<target>/proj/` and prints that project path. The header comment enumerates the fixture's load-bearing items, so the fixture and its assertion set can be checked against each other by reading one file. |
| `grade.py <id> <proj> <source> [--json]` | Deterministic grader. Exits 0 when every mechanical and integrity check passed. |
| `judge.py <id> <fixture> <delivered> <response>` | LLM grader for the qualitative assertions, refute-biased, one JSON verdict per rubric line. |
| `run.py [scenario ...]` | Drives worker → `grade.py` → `judge.py` per pass (five passes at a time by default), then aggregates the per-scenario rate. |
| `regrade.py <run_dir>` | Re-measures an existing run's captured responses with the current graders, spawning no worker. Writes `verdict.regrade.json` / `summary.regrade.*` beside the originals. |

## Where each expectation is graded

`evals.json`'s `expectations[]` is the full human-readable list per scenario.
Each entry is settled by exactly one grader:

- **Word-count ratios, ledger-item presence, bullet-cascade shape, filler
  phrases, fixture integrity** → `grade.py`, deterministically. Item presence
  is graded leniently on purpose (a first name matches, a spelled-out number
  matches) because whether the item survived *at its original strength and
  scope* is a semantic question the judge answers better than a regex. The one
  exception is a requirement-strength word: `must` and `should` are graded
  mechanically *and* semantically, because the modal verb is the carrier and
  its absence is a fact, not a reading.
- **"Reads plainly", "strength and scope unchanged", "opens with its main
  point", "reads as connected prose", "no invented content"** → `judge.py`,
  against a rubric that names the specific items and joints to look for rather
  than asking for a general impression.

A pass is clean only when every assertion from both graders held, plus the two
integrity checks. That split keeps the cheap surface deterministic while the
part that genuinely needs reading comprehension gets it.

## The worker prompt

`run.py` tells the worker to read the SKILL.md, follow it exactly, carry out
the staged request inside the sandbox, and then save the delivered document —
document text only, no commentary, notes, or metadata lines — verbatim to
`delivered.md`. The full reply still goes to `response.txt`, so the skill's own
output contract (selection line, preservation note, open items) stays visible
for inspection while `delivered.md` gives the graders a clean word-count and
item-presence surface. The prompt names none of the skill's rules, so the
worker's behavior comes from the skill rather than from the harness.

## Adding a scenario

1. Write `fixtures/<id>/setup.sh`, enumerating the fixture's load-bearing items
   in the header comment.
2. Add the `case` branch to `stage.sh` with the user prompt.
3. Add the mechanical assertions to `build_checks()` in `grade.py` and the
   qualitative rubric to `RUBRICS` in `judge.py`.
4. Add the id to `SCENARIOS` in `run.py` and the full expectation list to
   `evals.json`.
5. Validate the graders before spending worker calls: hand-write a faithful
   `delivered.md` and a deliberately lossy one, and confirm `grade.py` passes
   the first and fails the second. A grader that cannot fail proves nothing.
