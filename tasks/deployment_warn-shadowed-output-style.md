---
description: Warn on a style deploy when a settings file the run can read shadows the outputStyle just written, and state the override caveat on every global run for the repos it cannot read.
scope: deployment
created: 2026-08-10T11:56:32
updated: 2026-09-05T21:26:04
status: open
reported-by: Andreas Hoffmann
---

# Report output-style shadowing where the deploy can see it, and caveat where it cannot

## Goal

Today the style arm of the deploy writes `outputStyle` into the settings file of the tree it is deploying into, logs the merge, and says nothing about whether that value can take effect. Claude resolves the key from three settings files, where local project settings outrank checked-in project settings, which in turn outrank the user-level file. A key already present in a higher-precedence file therefore wins silently: every new session ignores the deployed style while the run's summary reports the merge as done, and the operator has no signal distinguishing that outcome from a working deploy.

After this task the run reports the resolution reality in two forms, split by what it can actually observe. Where the deploy can read the file that outranks its own merge, it warns concretely, naming that file, the value it holds, the value just deployed, and how to clear it. Where it cannot, meaning every repository outside the trees it touches, a global style deploy states unconditionally that the merge lands at user level and that any project's local `outputStyle` overrides it. The deploy keeps writing exactly the files it writes today and keeps its exit status; it gains the diagnostic only.

The split exists because silence has to stay meaningless: a run that inspected one tree must not let the absence of a warning read as an all-clear for trees it never opened. The unconditional statement is the only claim that holds for a repository the deploy cannot see.

## Context

The edit site is the `claude)` arm of the `style)` case in `deployment/deployment.sh`, whose activation half is the call `merge_json_key "$DEPLOYMENT_CONF" "${app_dir}/settings.json" "outputStyle"`. The tree that call writes into follows the run's scope: `CLAUDE_DIR="${PROJECT_DIR}/.claude"` under `--project-dir`, and `CLAUDE_DIR="${HOME_DIR}/.claude"` otherwise.

`REPO_ROOT` is this repository's own checkout, not the operator's working directory. It starts from the script's own location and walks up until it finds a directory containing `plugins/`, under the comment beginning `Discover REPO_ROOT by walking up from SCRIPT_DIR`, so it resolves to the same checkout on every run whatever the cwd is. Anything keyed on it therefore inspects one fixed repository, which is why the global arm below is framed as a check of this checkout rather than as a scan of wherever the operator happens to be.

The precedence fact this task rests on is recorded in the wiki on [Claude output styles](../wiki/concepts/claude-output-styles.md) under the heading `### Locations and activation`: project and local settings outrank the user-level key that the global mode sets, and running `/config` to choose an output style writes the pick to `.claude/settings.local.json` at local project scope. That asymmetry is the whole diagnostic gap: a style picked by hand sticks because the pick lands in the file that wins, while a deployed style looks ignored because its merge lands in the file that loses.

Reporting and exit behaviour are already in place. The `warn()` helper takes a short label and a message and prints without touching any counter, and the script ends with `print_summary` and no error accounting, so an added warning leaves the run's exit status alone.

Regression coverage for this artefact type lives in `tests/deployment/script_tests/style_run.sh`, which stages a scratch home tree and a scratch project, copies the deploy log aside before the checks, and restores it on exit. New scenarios extend that harness rather than starting a second one.

The arm being edited was built by the archived [output-style Claude groundwork](archive/deployment_output-style-claude-groundwork.md) task, whose Approach defines the two-placement deploy and the first-write prior-value capture inside `merge_json_key`. The shadow check runs beside that capture and changes neither the recorded prior nor the restore path.

## Approach

Add reporting after the `outputStyle` merge in the `claude)` style arm, in the two forms the Goal splits, because what outranks the merge target, and what the run can see at all, differs between the deploy scopes.

Under `--project-dir D` the merge writes `D/.claude/settings.json`, and exactly one file outranks it: `D/.claude/settings.local.json`. Read that file and warn on a divergent `outputStyle`. This check is exact and complete for the scope, since the deploy is handed the very tree whose resolution it is affecting.

Under `--global` the merge writes the user-level settings file, which every project settings file outranks, and the run can open only the trees it already knows. Deliver both halves there:

- Check this checkout's own `.claude/settings.local.json` and `.claude/settings.json`, and warn on a divergent `outputStyle` the same way. Frame the message as what it is, the deploy's own repository shadowing the style it just installed, rather than as a general finding. This repository is where styles get authored and tried out, so a stale local pick here is the likely case, and it is the one the run can settle for free.
- Print one unconditional line for the global scope, whether or not the check above fires, stating that the merge activated the style at user level and that a project-level `outputStyle` in any repository overrides it, with `.claude/settings.local.json` named as the file to look at. This is what keeps a warning-free run from reading as machine-wide confirmation.

Read the key with `jq`, already a standing dependency of the script. Warn when a checked file exists, defines `outputStyle`, and holds a value differing from the style name just deployed; stay silent when the file is absent, carries no such key, or already agrees. Compose each warning so it carries four facts: the path of the shadowing file, the value it holds, the value just deployed, and the remedy of removing the key from that file or selecting the style through `/config`, which writes to the same local file and so takes effect immediately.

Emit both forms under `--dry-run` as well as on a real deploy. The shadowing condition is readable without writing anything, and a dry run exists to preview what a real run would do, so suppressing the report there would hide the very outcome the preview is for.

Rewrite the `### Repo-root styles` section of `deployment/README.md` in place so it states the three-file precedence chain, the exact per-project check, the single-checkout reach of the global check, and the unconditional caveat, replacing the current description of the merge as unconditional activation rather than adding a second paragraph beside it. Naming the reach in the documentation is what stops a reader from mistaking the global check for full coverage.

**Out of scope:**

- A configurable list of extra repositories to scan, such as a new `deployment.conf` directive naming them. The unconditional caveat, rather than a wider scan, is this task's answer for repositories the run cannot see, and the repo's standing rules keep new deployment-config surfaces to what a request explicitly asks for. This task settles the question as a rejection rather than leaving it for a sibling.
- The user-level `~/.claude/settings.local.json` file, whose rank against the user-level `settings.json` no evidence behind this task establishes. The checked files are the project-level ones whose precedence over the merge target is documented on the wiki page named under **Context**.
- A shadow check for the hooks merge that shares the `merge_json_key` path. Project hook settings add to user hooks rather than replacing them, so a differing value there is not a shadow and the same warning would misreport it.
- Every non-Claude target inside the `style)` case, each of which reports that style deployment is not implemented and writes no settings key at all.

## Acceptance

Every deploy item below runs under the isolation pattern the style harness already uses: the deploy log copied aside and restored on exit, and a scratch home tree for a `--global` check.

- A scratch project whose `.claude/settings.local.json` sets `outputStyle` to a value differing from the conf's `style:<name>` produces, on a `--project-dir` deploy of the style type, exactly one warning carrying the shadowing file path, the shadowing value, the deployed value, and the remedy; the run exits 0.
- The same scratch project with its local value equal to the deployed style name produces no shadow warning.
- The same scratch project with `.claude/settings.local.json` absent produces no shadow warning, and with that file present but carrying no `outputStyle` key it produces none either.
- A `--project-dir` deploy produces no unconditional user-level caveat line, which belongs to the global scope alone.
- A `--global` deploy of the style type prints the unconditional caveat line naming user-level activation, project-level override, and `.claude/settings.local.json`, both when the checkout's own settings carry no divergent key and when they do.
- A `--global` deploy run with a divergent `outputStyle` staged in this checkout's own `.claude/settings.local.json` (backed aside and restored on exit, in the pattern the harness already applies to the deploy log) additionally produces one warning naming that file and identifying it as the deploy's own repository; with the staged key removed, that warning is absent while the caveat line remains.
- A `--dry-run` in each scope prints the same lines as the real run in that scope.
- `tests/deployment/script_tests/style_run.sh` carries the scenarios above and passes.
- `deployment/README.md` under `### Repo-root styles` states the three-file precedence chain, the exact per-project check, the single-checkout reach of the global check, and the unconditional caveat; no remaining `style` passage in that file describes the `outputStyle` merge as activation that always takes effect.
