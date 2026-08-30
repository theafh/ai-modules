# skill_doctor skill evals (behavioral surface)

Behavioral evals for the `skill_doctor` skill. The mechanical surface
(bundled-script unit tests for `resolve_scope.py` and
`discovery_safety.py`) lives next door in `script_tests/`.

This directory holds **eval definitions and tooling**, which are committed.
Eval *runs* (staged sandboxes, post-run artifacts) go under
`tests/skill_doctor/workspace/run-<ts>/`, which `tests/.gitignore` keeps
out of git.

## Running them

```bash
python3 tests/skill_doctor/evals/run.py
```

`run.py` spawns one sonnet-pinned `claude -p` worker per eval, per the
model policy in `tests/CLAUDE.md`: the skill under test always runs on the
same cheap, stable model, while `grade.sh` on top uses no model at all. It
honors the shared verdict cache (`--force` to resample, `--no-cache` to
bypass) and writes `summary.json` into the run directory.

Single eval, or a fresh draw on unchanged inputs:

```bash
python3 tests/skill_doctor/evals/run.py discovery_risky_sibling --force
```

The manual three-phase path stays available when you want to drive the
skill yourself in-session:

```bash
eval "$(bash tests/skill_doctor/evals/stage.sh <eval_id>)"
# ... run the skill against $sandbox_repo with $prompt ...
bash tests/skill_doctor/evals/grade.sh <eval_id> "$sandbox_repo" <response.txt>
```

## Not `scripts.run_eval`

An earlier version of this harness's README and RUNBOOK said these evals
run "out-of-band via skill-creator's `scripts.run_eval`". That is wrong,
and `tests/git_commit/evals/README.md` documents why: `run_eval` is
skill-creator's **trigger evaluator** for description optimization. It
consumes `{query, should_trigger}` items, has no `--workspace` argument,
and does not understand the `{id, prompt, expected_output, expectations}`
schema in `evals.json`. Use `run.py` here instead.

## What gets graded

`grade.sh` checks the two surfaces a model is not needed for:

- **Filesystem state** — `stage.sh` records a sha256 manifest of every
  staged `SKILL.md`, and `grade.sh` re-verifies it. This is the whole
  check-only contract, and it is the strongest signal in the harness.
- **Response text** — whether the resolved target set the skill named
  matches the expected one, and whether discovery safety came before the
  registration and instruction-quality passes.

Exclusion checks are deliberately tolerant: a correct run may name an
excluded skill while explaining the exclusion, so `excluded_properly`
requires only that every line mentioning it marks it as excluded.

That tolerance rests on the skill name being unmistakable in prose.
Because the check scans every occurrence of the name, a fixture named
after an ordinary English word matches sentences that have nothing to do
with the skill: the fixture was once called `other`, and a run that
correctly reported "`other` was excluded" still failed on a later
sentence reading "no basis to prefer one over the other". Give every
excluded fixture an invented snake_case name, as `lone_gizmo` now is.
`excluded_properly` fails with a `GRADER BUG:` line when handed a token
from its `ENGLISH_WORD_TOKENS` list, so the lapse surfaces as a named
grader fault rather than an intermittent skill failure.

## The evals

| id | fixture | what it pins |
| --- | --- | --- |
| `scope_hub_family` | `fixtures/scope_hub_family/` | Family resolution unions the hub's `<family>` block with the `token_*` prefix set, so the non-prefix `shared_linter` is in and `lone_gizmo` is out. |
| `scope_prefix_only` | `fixtures/scope_prefix_only/` | A family with no `<family>` block resolves by prefix alone: `wiki`, `wiki_import`, `wiki_wrapup`, without `spr`. |
| `discovery_risky_sibling` | `fixtures/discovery_risky_sibling/` | Discovery safety runs first and flags the risky sibling description with evidence. |
| `scope_single_skill_clean` | `fixtures/scope_multi_plugin/` | Single-skill mode holds to one target, and a clean tree reaches the output contract's clean path: the literal `No blocking issues.` plus a verification summary that names its commands. |
| `scope_whole_repo` | `fixtures/scope_multi_plugin/` | Whole-repo mode walks past the first plugin and reaches `beta_sprocket` in the second. |
| `scope_unresolvable_selector` | `fixtures/scope_multi_plugin/` | An unknown skill name halts the run: it reports the `resolve_scope.py` failure, names the nearest candidates, and asks, rather than substituting a target set and checking it. |

`fixtures/scope_multi_plugin/` is shared by the last three because each
asks a different scope question of one tree. It is the only
registration-complete fixture here (both `plugin.json` pairs, both
marketplace files, plugin and root READMEs), which is what lets the
clean-path eval treat any blocking finding as a false positive. The
`stage.sh` checksum manifest therefore covers `*.json` and `README.md`
alongside `SKILL.md`, so the registration pass has nothing it can edit
unnoticed.
