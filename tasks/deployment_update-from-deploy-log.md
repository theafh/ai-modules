---
description: Add `make update`, a log-driven deploy mode that redeploys each global or project scope the deploy log records, with its recorded targets and types, from this checkout.
scope: deployment
created: 2026-10-07T08:38:14
updated: 2026-10-09T18:48:19
status: open
reported-by: Andreas Hoffmann
---

# Redeploy every recorded scope from the deploy log with `make update`

## Goal

`make update` redeploys every scope the deploy log records, so a user who edits a source artefact refreshes the global copies and every project copy with one command. It reads the log, groups the entries by deploy scope (the global scope and each project directory a `--project-dir` deploy wrote into), and redeploys each scope from the current checkout, limited to the artefacts that scope's entries record for each target and type. That reaches what `make deploy` cannot, because a global deploy writes only the global scope while some artefacts now reach their harness only through a project deploy. A `--dry-run` previews the whole replay and writes nothing.

## Context

Every deployed artefact is a copy, so it goes stale when its source changes. `deployment/README.md` gives the refresh as "Re-run the script after editing a source artifact to refresh its deployed copy." For the global scope that rerun is `make deploy`. A project scope needs its `--project-dir` deploy rerun by hand, and only the deploy log remembers which projects received one.

The Cursor output style makes project scopes routine. The `cursor)` case of the style branch in `install_for_app` writes the rule file that `generate_cursor_style_rule` builds only under `--project-dir`, and under `--global` it reports that Cursor has no machine-wide rule file that injects. So each repository that should carry the style holds its own copy, and a global deploy never refreshes it.

The deploy log is the file `DEPLOYED_ARTIFACTS_LOG` names in `deployment/deployment.sh`. `append_deployed_artifact_log` writes one tab-separated line per deployed artefact: the deployed path (or `path[key]` for a JSON-merge entry), the target id, the type, the source path, and an optional prior value. `dedupe_deployed_artifact_log` sorts the file unique on exit. No field names the scope, but the deployed path implies it. [Limiting a scoped uninstall to its scope](deployment_uninstall-respects-scope.md) adds the helper that derives an entry's scope from that path, returning the global scope, a project directory, or no scope. This task follows that task and reuses its helper.

`uninstall_logged_artifacts` is the existing log-driven mode and the precedent for this one. It runs without a scope flag through the `NO_SCOPE_UNINSTALL` branch of the explicit-scope check, narrows by `--target` and `--type` through `logged_path_matches_active_targets` and `logged_type_matches_filter`, previews under `--dry-run`, and drops the entry of a logged path that is already gone. A log also outlives the scopes it names: a test run that deploys into a sandbox project and then deletes it leaves that project's entries behind.

[Relocating the per-machine state to `$HOME`](deployment_relocate-state-to-home.md) turns the log into one machine-wide file that every checkout and every bundled copy of the script writes. The log then holds entries whose sources lie in other checkouts, which is why the **Skip foreign groups** step below checks where each group's sources live.

The deploy script's regression harness is `tests/deployment/`. Its `run_all.sh` runs one script-test file per theme, `script_tests/run.sh` and `script_tests/style_run.sh`. Each file stages a scratch home through `HOME` and scratch project directories, runs the script on `/bin/bash`, and copies the deploy log aside before its checks and restores it on exit. The deployment entries of `tests/README.md` and `tests/CLAUDE.md` describe what each file covers.

## Approach

Add an `--update` mode to `deployment/deployment.sh`. List it in `print_usage` and in the header comment's `Features:` block, and extend the `--type` line's exception "unless used with --uninstall" to cover it. Add an `update` target to the `Makefile` that runs `./deployment/deployment.sh --update`, with a `##` help line, a `.PHONY` entry, and a line in the `# Targets:` header comment.

Model the mode on `--uninstall`. It joins the no-scope branch of the explicit-scope check, reads the log only through `DEPLOYED_ARTIFACTS_LOG` so the relocation's path change carries over, and accepts `--dry-run`, `--target`, and `--type` as uninstall does. Passing `--global` or `--project-dir DIR` alongside it narrows the run to that one scope. A scope flag or a filter narrows the replay and the vanished-scope drop alike. The script rejects `--update` together with `--uninstall`, and with no deploy log the mode reports the missing log and exits successfully.

Run the mode in these steps:

1. **Read and group.** Read the log once and group its entries by scope, target, and type, taking each entry's scope from the helper named in Context. Report an entry the helper gives no scope as unrecognized, and keep it in the log and out of the replay.
2. **Drop vanished scopes.** For a project directory that no longer exists, drop its entries from the log and report the scope with the number of entries dropped, as uninstall does for an absent path. Write the drop before the first replay, so the replay's own log appends survive. The replay never recreates a missing project directory.
3. **Skip foreign groups.** Replay a (scope, target, type) group only when at least one of its entries has a source path under this checkout's `REPO_ROOT`. Report every other group as deployed from another checkout, and leave its paths untouched.
4. **Replay.** Redeploy each remaining scope through the existing deploy path, one target at a time, so the scope receives what `deployment.sh <scope flag> --target <target> --type <types> --only <names>` would deliver. `<types>` lists the types that scope records for that target, and `<names>` lists the artefacts it records there, each named the way `discover_artifacts` names it and `--only` (in the script since 9 October 2026) matches it: a skill's directory basename, or an agent's or style's file basename without its extension, taken from the entry's source path. An entry whose source is not an artefact, such as a settings merge sourced from the conf, adds no name. Each scope thus receives exactly its recorded artefacts: never the cross product of its targets and types, never an artefact added to the checkout since, and never more than a subset deploy through `--only` gave it. Discovery, `deployment.conf` rules, generated formats, and backups behave as on a manual deploy: the global scope backs up each of its target roots once, project scopes skip backups, and an artefact of a recorded type that joined the repo since the last deploy arrives as well.
5. **Report orphans and summarize.** Report each entry whose source path lies under `REPO_ROOT` but no longer exists, naming its deployed path, and keep both that copy and its entry. Close the run with one line per scope that names what it replayed or why it was skipped.

Bring the documentation of the deploy commands in line with the mode:

- In `deployment/README.md`, add `--update` to the **Run It** examples and to the **Flags** table, and add update to each passage that lists the modes able to run without a scope: the **Run It** introduction, the `--type` row, and the paragraph beginning "Deploy operations require an explicit scope". Rewrite the **Deploy Log and Uninstall** section so it covers both readers of the log and says that `make deploy` widens the global scope to every discovered artefact while `make update` refreshes what the log records. Rewrite the sentence "Re-run the script after editing a source artifact to refresh its deployed copy." so it names `make update` as the refresh for every recorded scope.
- In the root `README.md`, add `make update` to the block of Makefile workflows.
- In the **Common tasks** list of `CLAUDE.md` and of `AGENTS.md`, add `make update` with the guard "Run only when the user asks for it." that `make deploy` carries, because it writes into the same configuration directories and into project directories besides.
- In `wiki/concepts/deployment-model.md`, rewrite the overview sentence ending "uninstall works by replaying that log" and the sentence that lists what the script carries, which names "an uninstall path", so each names update too. Make the edit through the wiki skill family, as the standing repo rules direct.

Cover the mode in a new `tests/deployment/script_tests/update_run.sh` that follows the sibling files' isolation pattern, run it from `tests/deployment/run_all.sh`, and describe it in the deployment entries of `tests/README.md` and `tests/CLAUDE.md`.

**Out of scope:**

- Removing a deployed copy whose source has left the repo, which `make deploy` does not do either. The run reports such an entry as an orphan.

## Acceptance

Every scenario runs in `update_run.sh` against a scratch home and scratch project directories, under the harness's isolation pattern.

- `make help` lists an `update` target, and `make -n update` prints `./deployment/deployment.sh --update`.
- `deployment.sh --help` lists `--update`, and its `--type` line names `--update` beside `--uninstall` as a mode that needs no scope.
- After a global deploy of the Claude skills and a project deploy of the Cursor style into a scratch project, with one file deleted from a deployed skill and the deployed `.mdc` rule overwritten, `--update` restores both copies byte for byte to what a fresh deploy writes, and its closing summary names both scopes as replayed.
- After that update, the scratch project holds no `.claude` directory and no `.cursor/skills` directory, because the Cursor style is its only recorded pair.
- `--update --dry-run` names each scope it would replay and leaves the scratch home, the scratch project, and the deploy log byte for byte unchanged.
- With a logged project directory deleted, `--update --dry-run` reports that scope and keeps its entries, and `--update` then reports it, removes its entries from the log, and leaves the directory absent.
- With a logged project directory deleted, `--update --project-dir <another scratch project>` leaves the deleted scope's entries in the log.
- A log entry whose source path lies outside the checkout, in a scope with no entry from the checkout, is reported as deployed from another checkout, and its deployed path stays byte for byte unchanged.
- A log entry whose source path lies under the checkout but no longer exists is reported with its deployed path, and both the deployed copy and the log entry remain.
- A log entry whose deployed path fits neither the global nor the project form is reported as unrecognized and stays in the log.
- With the global skill and the project rule both tampered again, `--update --project-dir <scratch project>` restores the project rule and leaves the global skill tampered.
- With the project rule tampered once more, `--update --target cursor` restores it and leaves the global skill tampered.
- A scratch project that received one skill through `--only`, in a checkout holding a second skill, still holds only that one skill after `--update`, refreshed from the checkout.
- `--update --uninstall` exits non-zero with an error that names both flags.
- `--update` without a deploy log reports the missing log and exits zero.
- `deployment/README.md` has an `--update` row in its **Flags** table, names update in each passage that lists the modes able to run without a scope, and describes update beside uninstall in its log section.
- The sentence "Re-run the script after editing a source artifact to refresh its deployed copy." no longer appears in `deployment/README.md`, and the passage that held it names `make update`.
- The root `README.md` Makefile block lists `make update`, and the **Common tasks** lists in `CLAUDE.md` and `AGENTS.md` each carry `make update` with the guard "Run only when the user asks for it."
- `wiki/concepts/deployment-model.md` names update beside uninstall as a reader of the deploy log and in its list of what the script carries.
- `tests/deployment/run_all.sh` runs `update_run.sh`, and the deployment entries in `tests/README.md` and `tests/CLAUDE.md` name what that file covers.
