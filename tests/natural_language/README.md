# tests/natural_language/

Pattern A harness for the `natural-language` output style. The style ships no
bundled scripts, so there is no `script_tests/` layer. The harness is
behavioral, and it exercises Claude output-style selection, so its runner
defaults to Claude, stops with an error on `--vendor cursor`, and runs on
Claude wherever a change to the style needs it, in the foreground, with
`--vendor claude` in the command so the Claude run is visible.

```text
tests/natural_language/
├── README.md
├── RUNBOOK.md
├── results/
└── evals/
    ├── evals.json
    ├── stage.sh
    ├── grade.py
    ├── judge.py
    ├── run.py
    ├── test_run.py
    ├── test_grade.py
    └── fixtures/<id>/setup.sh
```

## How a worker loads the style

Each scenario worker starts in a fresh sandbox from `tests/lib/worker_isolation.py`,
outside the home directory and outside any git repository, with
`--setting-sources project,local`. The runner copies the style under test into
that sandbox's `.claude/output-styles/` and writes `.claude/settings.json` with
a JSON serializer so `outputStyle` names the staged style. The worker prompt
asks only for the rewrite or the answer. It does not name a path to the style
file.

That route is the one observed on 2 October 2026 against Claude Code 2.1.226:
a `claude -p` worker loads a style staged in the sandbox's
`.claude/output-styles/` and selected by `outputStyle` in the sandbox's
`.claude/settings.json`, including under `--setting-sources project,local`.
The record is `### A headless worker honours a project selection` on
`wiki/concepts/claude-output-style-selection.md`. A sandbox outside the home
directory and any repository is what keeps the host's settings, deployed
style, and standing-instruction files away from the worker. That record is
`### A worker inherits the host's instructions unless it is isolated` on
`wiki/concepts/verification-surfaces.md`.

A run starts with a marker style named `nl_load_marker`. Its body is: Begin
every reply with the exact token NL_STYLE_LOAD_OK on its own first line, then
stop. The eliciting prompt is `Reply.` The marker is present when the reply
contains `NL_STYLE_LOAD_OK`. The run report records the CLI version and that
preflight result.

When the marker is missing and the CLI version is not newer than 2.1.226, the
run aborts before any scenario pass. When the marker is missing and the CLI
version is newer than 2.1.226, the runner passes the style file through
`--append-system-prompt-file` and continues. This route appends the style file
to the default prompt.

A project `settings.json` with a trailing comma drops `outputStyle` without an
error, the shape recorded under `### Configuration roots` on
`wiki/entities/anthropic-claude-code.md`. `python3 tests/natural_language/evals/run.py --preflight malformed`
writes that shape into a sandbox and aborts before any scenario pass, without
starting a worker.
`python3 tests/natural_language/evals/test_run.py` checks the marker-present
route and both marker-missing version branches without starting a worker.
`python3 tests/natural_language/evals/test_grade.py` checks that a hard wrap
at 72 columns does not change the series or pronoun-run verdicts.

## What it measures

| Scenario | The pressure |
| --- | --- |
| `connected_rewrite` | A synthetic argument of about 400 to 500 words. The rewrite has to keep the draft's relations and repair its shape without growing longer. |
| `chat_brevity` | A short question whose answer is one sentence in a small context file. The reply has to answer first and then stop. |

Each scenario runs over a fixed denominator of five passes. There is no
verdict cache. The passes run concurrently because each one owns an isolated
sandbox. `--workers 1` serializes them.

`grade.py` checks word count, pronoun-opening runs, the list-or-colon series,
the em dash, canary and shadow-share definitions in their first-use window,
`delivered.md`, and an untouched draft for `connected_rewrite`. For
`chat_brevity` it checks that `response.txt` stays at or under 120 words and
has no heading line. `judge.py` is refute-biased: it fails an assertion unless
the delivered text plainly satisfies it. For `connected_rewrite` it reports
four source-relation assertions (`contrast_kept`, `two_reasons_kept`,
`condition_kept`, `signal_inventory_kept`) plus the shape assertions
(`paragraphs_open_with_point`, `figures_tied`,
`arithmetic_opens_with_conclusion`, `connected_prose`). The judge starts in
its own isolated root with no staged output style and no `outputStyle`
selection.

## Grader validation

Hand-written samples live next to the fixture:

- `evals/fixtures/connected_rewrite/faithful.md` keeps the relations, leads
  with the point, defines shadow share at first use, and stays within the
  draft's word count.
- `evals/fixtures/connected_rewrite/flattened.md` splits the contrast, drops
  "but", writes the series as prose, and chains three pronoun-led sentences.

The recorded grade and judge results for those two files are in
`results/grader-validation.md`.
