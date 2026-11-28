---
description: "Make the agent_spinner ledger accept valid gate argv and an absolute brief target, and stop the brief verb crashing when its source and destination are one file."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-27T09:00:44Z
updated: 2026-11-28T00:23:46Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Make the agent_spinner ledger accept a valid gate argv and an absolute brief target

## Goal

The ledger accepts a valid gate command and a brief whose target is an absolute path instead of rejecting them on form. `brief` records an absolute target without a `SameFileError`, and `init` refuses a gate argv that carries no `{controls}` placeholder.

## Context

- Two input contracts reject valid input in `plugins/ai_dev/skills/agent_spinner/scripts/run_ledger.py`:
  - `brief` raised `shutil.SameFileError` when `--target` is an absolute path: `os.path.join(root, target)` and `os.path.join(dest_dir, target)` both return the absolute target, so the source and destination are one file. Reproduced on a row with no recorded path: `brief check:r --body B --target "$PWD/a.txt"` exits 1 at `shutil.copyfile`.
  - `run_gate_argv` appends the controls directory when the argv carries no `{controls}` placeholder. A lint gate whose argv already names its own path therefore failed from `init` onward with `unrecognized arguments`, and the run's baseline gate was a usage error.
- These two are one class: the ledger's input contracts are narrower than the contract the skill's workflow relies on, and a run that follows the skill loses its verification to a form mismatch.

## Approach

1. In `brief`, normalize the target with the `norm_path` idiom `cmd_snapshot` uses, then refuse a target whose normalized form is absolute or starts with `../` with a named error naming the row and the target — the same guard `Ledger.admitted_inputs` applies at `rel.startswith("../") or os.path.isabs(rel)`. Record the normalized relative path on the row, copy from it, and record the same path in `input_versions["target_path"]` when the target is a file, because `Ledger.admitted_inputs` admits the row's target only through `if versions.get("target_path"):`, normalizing that path into the admitted set; without it a reader whose brief body does not name the path is refused at the accept audit. For an in-project absolute target this yields a path relative to the project root, so the copy into `snapshots/inputs/<label>/<path>` — or `baseline/inputs/<label>/<path>` for a writer row — keeps its directory prefix, the source and destination differ by construction, and the accept audit reads the recorded copy rather than the live file. A target outside the project is refused rather than copied: `norm_path` leaves an out-of-project path as `../…`, and its `except ValueError` fallback leaves a different-drive path absolute, so the one guard covers both.
2. In `init`, validate each gate argv in `gate_spec`, before `init` writes `request.txt` and the run state: the accepted `--gate NAME=COMMAND` form is an argv carrying `{controls}`, and `init` refuses an argv that carries none with a named error that names the gate. The refusal condition is the placeholder's absence: the refusal must be decided before the baseline run, so the placeholder is the one detectable signal. Never append a positional path to an argv that did not ask for one. In `cmd_gate`, keep the `gate NAME -- ARGV` form and render `{controls}` in the operator's ARGV through `run_gate_argv` against the gate's recorded controls directory before running it; an ARGV without the placeholder runs verbatim, so drop the `if not used: rendered.append(controls_dir)` fallback in `run_gate_argv` and a placeholder-less ARGV keeps exactly its own arguments. An empty ARGV after `--` — the form `gate NAME --`, which `main` reaches because it still requires the `--` — is the gate's control re-run: it renders the registered argv's `{controls}` against the same recorded controls directory `init` planted the known positive in and runs it, so its expected exit status is that gate's recorded `baseline_rc` and, for a gate that reports the plant, a non-zero status whose `gate_result` record carries `ok: false` as the control re-check result rather than a verification failure. It resolves the registered argv through the same `shutil.which(command[0])` call an operator-supplied ARGV uses: a relative command such as `./lint.sh` resolves against the directory the ledger is invoked from, and a bare name resolves on `PATH`. Record the controls directory on the gate spec at `init` as a root-relative path (`<run>/controls/<slugify(name)>`), so a later gate run renders the same directory `init` planted the known positive in.
3. Rewrite in place the `--gate` bullet in `### init`, the `### gate` entry in `references/run-protocol.md`, and the C4 command sentence in `references/checks.md` so step 2's argv contract is stated once and each site carries only its own fact. The `### gate` entry in `references/run-protocol.md` owns the contract: a `{controls}` placeholder in the ARGV is replaced with the gate's recorded controls directory before the command runs, an ARGV without one runs verbatim with exactly its own arguments, and an ARGV after `--` that is empty selects the registered argv. The `--gate` bullet in `### init` owns the registration requirement: `--gate NAME=COMMAND` registers a gate whose COMMAND carries a `{controls}` placeholder, and `init` refuses a COMMAND without one with an error naming the gate. The C4 command sentence in `references/checks.md` (the sentence that reads `gate NAME -- ARGV`) names the `{controls}` placeholder and defers the substitution rule to `### gate` instead of restating it. Extend the `--gate` argument's help string in `build_parser` (`help="NAME=COMMAND"`) to name `{controls}`. In the `--target` bullet of the `brief` entry write the phrase `an absolute target is resolved before the copy`, so an in-project absolute path is recorded relative to the project root and a target that resolves outside the project is refused with a named error.
4. Add one `ledger_run.sh` scenario per contract and register each in `run_all_scenarios`: a brief whose target is an in-project absolute path succeeds and its accept audit resolves the recorded copy; an out-of-project absolute target is refused with the named error; an argv without `{controls}` is refused at `init` with a named error; a gate registered with `{controls}` renders it at `gate NAME --` and the gate script receives only its own arguments; `gate NAME -- <cmd>` with no placeholder hands the command exactly its own argv; and `gate NAME -- <cmd> {controls}` hands the command the controls directory in place of the placeholder. For every fixture setup that registers `--gate`, add `{controls}` to its gate argv unless it already carries the placeholder; `gate_scope_checked_before_dispatch` keeps its worker scenario on the placeholder form, so its gate argv reads `./lint.sh {controls}` and the auto-fix refusal it proves still runs on the same argv shape.

**Out of scope:** relaxing the severity ladder or the classification rules; those are substantive checks and stay strict. Also out of scope: changing the return contract to accept a prose-only return; it requires one fenced JSON block by design.

## Acceptance

- A new `ledger_run.sh` scenario stages a brief whose target is an in-project absolute path; `brief` exits 0.
- In that scenario `brief` writes the brief.
- In that scenario the recorded input copy exists as a file distinct from the live target.
- In that scenario the accept audit still resolves the recorded copy.
- In that scenario re-briefing the row with no `--target` exits 0.
- In that scenario the roster `path` column reads the normalized relative path.
- A new scenario stages an out-of-project absolute target and calls `brief` with it; `brief` exits non-zero with the named error naming the row and the target, and copies nothing.
- A new scenario calls `init` with a gate argv that lacks `{controls}`; `init` exits non-zero with a named error naming the gate and leaves no `request.txt` in the run directory.
- A new scenario registers a gate whose argv carries `{controls}`, runs `gate NAME --` with nothing after `--`, and the gate receives the recorded controls directory in place of the placeholder with its exit status recorded; the same scenario also runs `gate NAME -- <cmd> {controls}` and asserts the command received the controls directory in place of the placeholder and only its own arguments.
- In that scenario the gate reports the planted known positive and exits non-zero, and the recorded `gate_result` carries the `baseline_rc` `init` recorded for that gate as its `exit` with `ok: false` — the control re-run's expected result on a clean tree.
- A new scenario runs `gate NAME -- <cmd>` with no `{controls}` in the ARGV, and the command receives exactly its own argv: the recorded output carries no appended controls directory.
- Every fixture setup that registers `--gate` carries `{controls}` in its gate argv: `rg -n -F -- '--gate' tests/agent_spinner/evals/fixtures/` lists one line per such fixture and each line names `{controls}`. As a regression guard, `bash tests/agent_spinner/evals/stage.sh <fixture>` exits 0 for each such fixture; each such fixture stages at exit 0 today, so the stage check guards against a later bare argv rather than flipping new behaviour.
- `rg -n -F 'an absolute target is resolved before the copy' plugins/ai_dev/skills/agent_spinner/references/run-protocol.md` prints exactly one line.
- `rg -n -F '{controls}' plugins/ai_dev/skills/agent_spinner/references/run-protocol.md` finds the `--gate` bullet in `### init` and the `### gate` entry.
- `rg -n -F '{controls}' plugins/ai_dev/skills/agent_spinner/references/checks.md` finds the C4 command sentence.
- `bash tests/agent_spinner/script_tests/ledger_run.sh` passes, including every pre-existing scenario.
- `bash tests/agent_spinner/script_tests/ledger_run.sh` exits 0 and its output names at least one `PASS` check from each new scenario; a scenario left out of `run_all_scenarios` drops its own labels, so the check fails.
