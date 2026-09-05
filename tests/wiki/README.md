# Wiki skill regression test harness

A two-layer test harness for the wiki skill at
`plugins/knowledge_management/skills/wiki/`. The authored harness is
committed; `tests/.gitignore` keeps its run output out of git.

The wiki skill under test is *the product*. The harness exists
to make sure that when the skill or its bundled scripts (`discover_wiki.sh`,
`init_wiki.sh`, `lint.py`) change, the load-bearing behaviors don't quietly
break.

## What we're actually testing

The wiki skill has two surfaces that can regress independently:

1. **The bundled scripts.** `discover_wiki.sh` resolves which wiki path a
   given operation should touch, walking up from CWD with rules for
   `.no_wiki` opt-out markers, existing wikis, and outside-HOME fallback.
   `init_wiki.sh` scaffolds a new wiki and refuses to overwrite an
   existing one. `lint.py` reports broken links / bad frontmatter / etc.
   These are deterministic shell + Python: small inputs, small outputs.
2. **Skill behavior at the agent level.** Whether Claude, given the
   skill's `SKILL.md`, runs discovery first, interprets the script's
   exit code correctly, asks the user when the result is ambiguous,
   refuses to silently adopt an upstream wiki, etc. This is non-deterministic
   and depends on prompt fidelity.

Layer 1 tests the scripts. Layer 2 tests the skill.

## Layer 1: script-level, deterministic

**Runner:** `layer1/run.sh`. Bash + Python only, no LLM calls. ~1 sec.

For each scenario it stages a fake-`HOME` tree under
`layer1/scratch/<id>/` and runs the relevant script with `HOME` and
`PWD` overridden so walk-up is fully isolated from the real
`/Users/<you>/...` filesystem.

The live inventory is `run.sh` itself. Read it with
`grep -E '^scenario ' layer1/run.sh`, which prints one line per
scenario with its id and description. The prefixes group by surface:

- `d*` / `dp*` cover every walk-up branch in `discover_wiki.sh` and the
  bash-vs-python parity of that walk-up:
  no wiki and no marker on the ladder, marker at CWD, marker at every
  level, existing wiki at CWD, **upstream wiki + ambiguous CWD (D6, the
  case explicitly called out in `SKILL.md` because it's where naive
  implementations silently adopt the parent wiki)**, multi-level walk-up,
  outside-HOME fallback in three sub-cases, the `--check` flag, and the
  retired-wiki marker (`.no_wiki` placed inside an existing `wiki/`).
- `i*` cover `init_wiki.sh`: fresh init, refusal over an existing
  wiki, refusal at a `.no_wiki` marker, no-args help.
- `l*` cover `lint.py`, one scenario per check and per suppression
  form, from "clean fresh wiki passes" through the blocking
  frontmatter / link / portability cases to the info-level `size`,
  `stale`, `log`, `log-heading`, and `log-scope` findings and the
  three `Accepted finding:` grammars.
- `a*` cover the `auto_shaper_wiki` contract assertions that a script
  can check, and `s*` cover `compute_sha256.py`.

The runner exits non-zero on any failure. Add a new scenario by
appending a `scenario` invocation in `run.sh` plus a body function next
to the existing helpers. The file is self-documenting.

## Layer 2: skill-level, spawns Claude subagents

For each scenario the harness spawns a subagent that has the wiki
skill's `SKILL.md` available, gives it a sandbox CWD and an isolated
fake `HOME`, hands it a user request, and asks for a structured
TEST REPORT in return. The grader checks that report and the resulting
sandbox filesystem state against per-scenario assertions.

**Two passes** per scenario, run sequentially with a sandbox restage
between them. Two independent samples surface flaky behavior; if the
two passes disagree on an assertion, the regression aggregator flags
it.

### The original five discovery scenarios

`layer2/evals.json` is the live inventory. Read it with
`jq -r '.evals[] | "\(.id)  \(.name)"' layer2/evals.json`. The table below
covers only the five discovery scenarios the harness started with; the
`L2-6`+, `WI-*`, `WU-*`, and `AS-*` scenarios added since are described in
their own `description` field in that file.

| ID | Setup | User request | Skill must… |
| --- | --- | --- | --- |
| **L2-1** | Existing wiki at CWD | "Add a page about transformers, here's a paste" | Auto-resolve (exit 0), orient, ingest the paste, create concept page, update index/log, lint clean |
| **L2-2** | Upstream wiki at HOME, empty CWD (the D6 case) | "Initialize a wiki for this project" | Run discovery (exit 2), present BOTH candidates, **ask the user**, NOT silently adopt the upstream wiki |
| **L2-3** | Wiki already exists at CWD | "Initialize a new wiki here" | Recognize the existing wiki via discovery (exit 0), refuse to re-init, report it back |
| **L2-4** | Empty CWD, ambiguous; user gives pre-decision | "Init. If ambiguous, pick local CWD" | Run discovery (exit 2), apply the user's pre-decision, run init, lint clean |
| **L2-5** | `.no_wiki` at CWD, wiki at HOME | "Add a page about widgets" | Auto-resolve to HOME wiki, NOT ask, add page, update navigation |

These are written to mirror the (a) through (d) cases the user originally
asked about, plus the D6 case from `SKILL.md`'s "Resolving the Wiki
Location" section, the one place where naive agent behavior would
quietly do the wrong thing.

### The load-bearing assertion

Every scenario asserts `real_home_wiki_absent` and
`no_files_outside_sandbox`. If a future skill change ever causes a
test agent to leak a wiki into the operator's actual `~/wiki` (or any
file outside `tests/wiki/`), those assertions fail loudly. They're the
fail-safe that justifies running the harness against the operator's
real filesystem rather than a containerized sandbox.

### What we trust vs. verify

LLM tests are not deterministic. The harness is built around what we
*can* verify cheaply:

- **Filesystem state after the run.** `init_wiki.sh` either left a
  scaffolded wiki at `<sandbox>/HOME/proj/wiki` or it didn't. We assert
  on directory entries, not on the agent's prose.
- **Structured self-report.** The agent's TEST REPORT has fixed fields
  (`discovery_invoked`, `discovery_exit`, `init_invoked`, …). We trust
  the agent to fill these honestly because lying contradicts the
  filesystem state we also check.
- **Canonical script output.** `discover_wiki.sh` emits `AVAILABLE:` /
  `EXISTING:` prefixed lines. If the agent passes those through to its
  response, the candidates were presented.

What we *don't* trust:

- The agent's free-form prose to consistently contain specific words.
  Earlier assertions matched against absolute paths in the response and
  had to be relaxed because agents abbreviate or restructure.
  Response-text checks now look only for the canonical
  `AVAILABLE` / `EXISTING` markers, which the agent has no reason to
  rephrase.

## How to run

### Quick: Layer 1 only (~1 sec, no LLM cost)

```bash
./tests/wiki/run_all.sh
```

### Full: Layer 1 + Layer 2 (~5 to 10 min, ~50k tokens per pass × 10)

The standalone runner shells out to `claude -p` per pass:

```bash
./tests/wiki/run_all.sh --layer2
# or directly:
python3 ./tests/wiki/layer2/run.py
```

Single scenario while debugging:

```bash
python3 ./tests/wiki/layer2/run.py --scenario L2-2
```

### Inside a Claude Code session (faster, true parallel subagents)

The standalone `claude -p` runner runs scenarios sequentially. Inside a
live Claude Code session, the parent agent can spawn 5 subagents in
parallel for pass-1, restage, then 5 in parallel for pass-2, about 3×
faster. Paste this prompt into a fresh session at the repo root:

> Re-run the Layer 2 wiki-skill regression in this repo. The harness is
> in `tests/wiki/layer2/`. For each scenario in `evals.json`, restage
> the sandbox via `setup_scenarios.sh`, spawn a subagent twice using
> the prompt built by `build_prompt.py`, and have each subagent write
> its TEST REPORT to `workspace/run-<ts>/<scenario>/pass-N/report.md`
> (or to its response; `normalize.py` will recover either). After all
> 10 runs finish, run `normalize.py`, `grade.py`, `aggregate.py`, and
> `render_report.py` against the run dir and surface any regressions.

### Output

Each Layer 2 run produces, under
`tests/wiki/layer2/workspace/run-<ts>/`:

- `<scenario>/pass-N/{prompt.md, response.txt, report.md, timing.json, grading.json, sandbox-snapshot/}`
- `grading_summary.json`: flat list of (scenario × pass) PASS/FAIL
- `benchmark.json`: per-scenario stats (mean ± sd of pass rate, duration, tokens) + per-assertion pass rate + regression list
- `benchmark.md`: human-readable summary
- `report.html`: self-contained, interactive viewer with per-assertion results, prompts, responses, reports, and timing

The aggregator automatically compares against the most recent prior
`benchmark.json` and exits non-zero if any assertion that was 100% in
the prior run is <100% now, or any scenario that was clean across all
passes now has at least one fail. That's the regression signal.

## What "all passing" guarantees

When a run shows 100% across the board, it means:

1. The walk-up logic in `discover_wiki.sh` is correct for every input
   shape we've tested (12 cases including the load-bearing D6
   ambiguity case).
2. `init_wiki.sh` refuses to overwrite, refuses on `.no_wiki`, and
   correctly scaffolds when given a fresh path.
3. `lint.py` blocks on missing critical files (SCHEMA, index) and
   passes on a fresh wiki.
4. Across two independent agent runs per scenario, Claude:
   - Always invokes discovery before writing.
   - Correctly interprets exit 0 (auto-adopt) and exit 2 (ambiguous,
     ask).
   - Never silently adopts an upstream `EXISTING` wiki when ambiguity
     should defer to the user.
   - Refuses to re-init an existing wiki.
   - Honors the `.no_wiki` opt-out chain.
   - Adds pages to the right wiki, updates index/log, lints clean.
5. No file leaked outside the sandbox; `~/wiki` was never created.

It does *not* guarantee:

- That Claude will reliably trigger the skill from a real user message.
  That's a description-matching question, separate from skill
  behavior. Test it with the skill-creator's `run_loop.py` against
  realistic user prompts.
- That the wiki skill's prose advice (page-type heuristics, the
  declarative-vs-procedural split, etc.) leads to good wiki content.
  That's a quality question best evaluated by humans on real wikis.
- That every edge case is covered. Notable absences: paths with
  spaces or unicode, very deep walk-up trees, what happens when
  `discover_wiki.sh` itself errors out, what happens when the user
  passes an explicit-but-wrong path.

## Adding a scenario

### Layer 1

Append a `dN_*` / `iN_*` / `lN_*` body function in `layer1/run.sh` and
a `scenario` line at the bottom. The runner is one self-contained
file, ~250 lines, with helpers (`fresh_scratch`, `run_discover`,
`assert_eq`) at the top.

### Layer 2

1. Stage the sandbox shape in `layer2/setup_scenarios.sh`; copy one of
   the existing `L2-N` blocks. Each scenario gets its own per-scenario
   directory with a fake `HOME/`. Add the new id to the `ALL_SCENARIOS`
   array at the bottom of that file, or the restage step skips it.
2. Add a scenario block in `layer2/evals.json` with assertions. The
   types `grade.py` understands today:
   - `report_field_eq`, `report_field_in` (semantic-equivalence value
     set), `report_field_contains`, `report_field_does_not_contain`,
     `report_field_matches`, `report_field_endswith`
   - `file_exists`, `file_exists_and_changed`, `file_matches_baseline`
     (byte-identity against a checksum staged outside the fake `HOME`),
     `raw_sha256_matches_body` (a raw sidecar's recorded `sha256:` equals
     the hash of its own body), `path_does_not_exist`, `all_dirs_exist`
   - `glob_exists`, `glob_absent`, `glob_file_contains`,
     `glob_file_absent_content`
   - `no_files_outside_sandbox`, `real_home_wiki_absent` (always
     include both, the cheap fail-safes)
   - `response_text_contains`, `response_text_matches`,
     `response_text_does_not_match`, `response_text_contains_path`
3. Declare any scenario-specific report field in both
   `extra_report_fields` and `extra_report_field_doc`; `parse_report`
   reads a `key: value` line as a field only when the key is declared.
4. Re-run. The orchestrator picks the new scenario up automatically.

When designing assertions, lean on filesystem state and report-field
checks first; reach for response-text checks only for behaviors the
filesystem can't capture (e.g. "did the agent ask the user?"; there
the canonical signal is `ambiguity_presented_to_user: yes` in the
report, with `response_text_contains: AVAILABLE` and `EXISTING` as
backup).

## Lessons from the first run (worth keeping in mind)

The first Layer 2 run surfaced three real instrumentation problems.
None of them affected the skill verdict, but all of them muddied the
results. The harness now handles each one:

1. **The Agent harness sometimes blocks subagent `Write` calls** to
   absolute paths that look like they escape project scope, even when
   the path is inside the test workspace. Mitigation: subagents emit
   the TEST REPORT block in their text response *and* try to Write it
   to disk. `normalize.py` reads `response.txt` and writes
   `report.md` if missing. So either capture path works.
2. **Agents narrate harness-rejection in their responses** ("The
   harness blocked the file write…"), which polluted the captured
   transcripts. The current prompt explicitly instructs "end your
   response with the TEST REPORT block and nothing after it; do not
   narrate harness behavior." `normalize.py` also strips known noise
   patterns from older runs.
3. **Some report fields had ambiguous meaning across agents**, e.g.
   `ambiguity_presented_to_user: n/a` vs `no` for the same skill
   behavior. The prompt now requires strict `yes|no` for that field;
   the `report_field_in` assertion type accepts equivalent value sets
   for backward compatibility with older runs.

These are good lessons for any future LLM-in-the-loop test harness:
the agent's free-form output is the most variable surface; pin the
structured report format, and back it with filesystem-state assertions
that don't depend on the agent's prose at all.

## Sandbox isolation in detail

Layer 1 fully overrides `HOME` per scenario via `HOME=<scratch>` in
the test runner. The scripts read `$HOME` at invocation, so this gives
deterministic walk-up behavior with no real-filesystem coupling.

Layer 2 spawns subagents that inherit the parent process environment.
We can't trivially override `HOME` for the subagent itself, so the
prompt instructs the agent to prefix every wiki-script invocation with
`HOME=<sandbox-fake-home>`. If a subagent forgets the prefix and runs
e.g. `bash discover_wiki.sh` directly, it'll resolve against
`/Users/<operator>/...`, so the agent might create files outside the
sandbox. **`real_home_wiki_absent` is the assertion that catches that
mistake.** It has never failed in any run so far, but it's the reason
the harness can be safely re-run on the operator's real machine
without containerization.

## File reference

```text
tests/wiki/
├── README.md                       # this file
├── RUNBOOK.md                      # quick reference (subset of this README)
├── run_all.sh                      # entrypoint: Layer 1; --layer2 to add Layer 2
├── results/
│   ├── SUMMARY.md                  # rolling human summary of latest run
│   └── layer1.log                  # latest Layer 1 output
├── layer1/
│   ├── run.sh                      # 19 deterministic scenarios
│   └── scratch/<id>/HOME/...       # transient per-scenario fake-HOME trees
└── layer2/
    ├── evals.json                  # canonical scenarios + assertions
    ├── setup_scenarios.sh          # stages the 5 sandboxes from init_wiki.sh
    ├── build_prompt.py             # eval -> agent prompt (prompt assembly central)
    ├── normalize.py                # extract report.md from response.txt; strip noise
    ├── grade.py                    # report.md + sandbox -> grading.json
    ├── aggregate.py                # gradings -> benchmark.json + regression list
    ├── render_report.py            # benchmark + grading -> self-contained report.html
    ├── run.py                      # standalone orchestrator (claude -p)
    ├── L2-1/ ... L2-5/             # restaged on each run; transient
    └── workspace/
        └── run-<ts>/
            ├── L2-*/pass-N/{prompt, response, report, timing, grading, sandbox-snapshot}/
            ├── grading_summary.json
            ├── benchmark.json
            ├── benchmark.md
            └── report.html
```

The authored harness under `tests/wiki/` is committed. Run output stays
local via `tests/.gitignore`: the `workspace/` and `scratch/` trees, the
staged `layer2/{AS,L2,WI,WU}-*` sandboxes, and the per-run logs under
`results/`.

## Latest results

See `results/SUMMARY.md` for the current and prior runs at a glance.
Open `tests/wiki/layer2/workspace/run-<latest>/report.html` for the
interactive per-pass view.

The skill has so far passed 100% across two independent end-to-end
runs (4 samples per scenario, 0 disagreements on assertion outcomes).
The pass-rate variance is 0%; the only inter-run variance is in
duration and token usage, as expected.
