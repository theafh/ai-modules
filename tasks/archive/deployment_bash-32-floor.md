---
description: Rewrite deployment.sh to run under the stock macOS bash 3.2, guard the floor with a lint check and a bash-3.2 test run, fix two mapfile graders, and state the floor in the deploy README.
scope: deployment
created: 2026-09-18T17:48:56Z
updated: 2026-10-03T12:55:53Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Bring deployment.sh and its harness onto the stock bash 3.2 floor

## Goal

`deployment/deployment.sh` opens with a `#!/usr/bin/env bash` shebang and uses constructs that need bash 4 or newer. macOS ships bash 3.2.57 as `/bin/bash` and will not replace it, so that shebang resolves to the stock build in any shell whose `PATH` carries no newer bash. The script then aborts on its first associative-array declaration before doing any work, and every Makefile target driving it aborts with it. A shell spawned by an agent harness hits this on every run, because the `PATH` entry that puts a newer bash first is contributed by a login-shell profile that such a shell never reads.

After this task the script runs unchanged under the stock bash, the artefacts around it keep it there, and the floor is written down:

- The script uses no construct newer than bash 3.2, keeps its current behaviour, and gains no prerequisite.
- A lint check fails the tree when a banned construct reappears in a tracked shell file.
- The deployment script tests execute the script through an explicit `/bin/bash`, so the floor is proven rather than asserted.
- Two eval graders that call `mapfile` run under the same floor.
- `deployment/README.md` names the floor where it currently names only the operating systems.

Everything else the script needs at run time already resolves to a stock macOS binary, including `jq` and `perl`, so the bash floor is the whole of what stands between the current script and a `make deploy` that works from any shell.

## Context

The bash-4 surface is small and concentrated. Five associative-array declarations carry it, each greppable by its own declaration text: `declare -A ASSET_FOLDERS=(`, `declare -A DISALLOW_MAP=()`, `declare -A STYLE_MAP=()`, `declare -A cleared_roots=()`, and `declare -A backed_up=()`. Two case-modification expansions carry the rest, both written as the comparison `[[ "${bname^^}" == README* ]]`.

None of the five maps needs hash semantics, which is what makes the rewrite mechanical. `DISALLOW_MAP`, `cleared_roots`, and `backed_up` are sets whose every value is the literal `1`; membership is tested through the `+x` parameter-expansion idiom and nothing reads a value. `ASSET_FOLDERS` is a fixed four-entry folder-to-type table. `STYLE_MAP` holds one output-style name per deploy target. The one lookup that could slow down, the function `is_disallowed()`, already falls through to a linear scan over the same keys after its exact-match probe, so an indexed array changes its cost by one pass over a handful of configured patterns.

What bash 3.2 does with each construct is verified on a stock macOS build rather than recalled, and the diagnostics differ in a way the guard design depends on. A bare `declare -A m` fails loudly with `declare: -A: invalid option`. A populated `declare -A m=([k]=v)` does not: bash 3.2 reads `[k]` as an arithmetic subscript, so under `set -u` it reports `k: unbound variable`, which is the error this task removes, and without `set -u` it silently degrades to an indexed array. Four constructs fail at parse time and are therefore caught by `bash -n` alone: `&>>`, `;;&`, `coproc`, and `[[ -v var ]]`. The remainder fail only when the line executes: `${var^^}` and `${var,,}` as `bad substitution`, `mapfile` and `readarray` as `command not found`, `declare -n` and `wait -n` and `read -N` as invalid options, `shopt -s globstar` as an invalid option name, `${var@Q}` as a bad substitution, a negative array index as `bad array subscript`, `EPOCHSECONDS` as unbound, and `printf '%(fmt)T'` as an invalid format character. A construct sitting in a branch the tests never take is therefore invisible to any runtime check, which is why the guard needs a static pass as well as a bash-3.2 run.

The rest of the repository already meets this floor. Every shell script bundled inside a skill passes a bash 3.2 syntax check and uses no bash-4 construct, and the charter guardrail hook declares `#!/bin/sh`. Outside the deploy script the only offenders are two eval graders, `tests/agent_spinner/evals/grade.sh` and `tests/git_commit/evals/grade.sh`, each of which reads a command's output through a single `mapfile -t` call.

Regression coverage lives in `tests/deployment/script_tests/`, whose `run.sh` and `style_run.sh` both resolve the script into `DEPLOY_SCRIPT` and execute it directly, letting the shebang pick the interpreter. Two assertions in `style_run.sh` bind the map's current shape: one greps the script for the literal string `declare -A STYLE_MAP`, and after sourcing the script and calling `parse_deployment_conf` another checks `[[ "${STYLE_MAP[claude]:-}" == "natural-language" ]]`, so both fail by construction once the map changes shape.

Static enforcement has to be built rather than configured. The Makefile's `lint-sh` target runs `shellcheck` over `SH_FILES`, and shellcheck 0.11.0 offers no bash-version target: its `-s` flag selects a dialect from `sh`, `bash`, `dash`, `ksh`, and `busybox`, none of which expresses a version floor.

`deployment/README.md` states that the script targets Bash on macOS and Linux and lists its external tools, without naming a version, so a reader cannot tell that the stock macOS interpreter is in or out of scope.

## Approach

Replace the five associative arrays with indexed arrays, distinguishing the three sets from the two tables. Encode `DISALLOW_MAP`, `cleared_roots`, and `backed_up` as indexed arrays of their bare former keys — for `DISALLOW_MAP` that keeps the existing `tool|pattern` strings and the append form `${current_tool}|${disallowed}` unchanged — and encode `ASSET_FOLDERS` and `STYLE_MAP` as indexed arrays of `key|value` entries, keeping `ASSET_FOLDERS` a literal `folder|type` list so its iteration site still reads as a table. Compare with exact `[[ ... == ... ]]` scans rather than testing membership by pattern-matching a delimited accumulator string, so a directory path containing a space, a newline, or the delimiter itself keeps behaving as it does today. For the three sets, replace the `+x` membership probe with a small helper that scans `"${array[@]}"` and returns success on an exact hit; never iterate `"${!array[@]}"` for those sets. For the two tables, replace the subscript read with the same scan returning the value part after the first `|`. Rewrite `is_disallowed`'s pattern loop that today iterates `"${!DISALLOW_MAP[@]}"` so it iterates the indexed entries `"${DISALLOW_MAP[@]}"` and recovers tool and pattern by splitting each entry on the first `|`.

Replace both case-modification comparisons with a bracket-class glob, `[[ "$bname" == [Rr][Ee][Aa][Dd][Mm][Ee]* ]]`, which bash 3.2 supports and which needs no global shell option. The `nocasematch` shell option would also work and is deliberately left aside, because it changes matching for every comparison in its scope rather than the one being fixed.

Add a static check to the Makefile's shell lint so the floor survives future edits. The check scans the same `SH_FILES` set with plain shell and `grep` for this fixed greppable token and expansion set, and fails with the offending file and construct named: `declare -A`, `${var^^}` / `${var,,}`, `mapfile`, `readarray`, `declare -n`, `wait -n`, `read -N`, `shopt -s globstar`, `${var@Q}`, `&>>`, `;;&`, `coproc`, `[[ -v`, `EPOCHSECONDS`, and `printf '%(fmt)T'` (and equivalent greppable forms of those same constructs). Leave negative-array-index coverage to the bash-3.2 execution proofs alone; grep cannot reliably detect that class. Keep the check a plain shell and `grep` step, since the repo's standing rules hold the toolchain to Make, shell, and Markdown with jq, git, and Python 3 as the accepted standing dependencies.

Parameterize the deployment script tests so they invoke the script through an explicit `/bin/bash` interpreter, and rewrite both `style_run.sh` STYLE_MAP assertions — the grep for `declare -A STYLE_MAP` and the post-`parse_deployment_conf` check `[[ "${STYLE_MAP[claude]:-}" == "natural-language" ]]` — so each asserts the replacement structure by that structure's own form, with the consumer check still proving that `claude` resolves to `natural-language`. Locate the bash≥5 interpreter for the behaviour-identity check as the first `bash` on `PATH` whose major version is at least 5 and whose resolved path differs from `/bin/bash`; when `/bin/bash` itself is already bash≥5, that single interpreter satisfies both sides of the check. When neither holds, the identity check is not runnable and the `/bin/bash` dry-run Acceptance items alone carry the behaviour proof for that host. The static check and the bash-3.2 run cover different failure classes, so both are delivered: the static pass reaches constructs on untaken branches, and the run proves the taken paths.

Rewrite the two graders' `mapfile -t` calls as a `while IFS= read -r` loop appending to an array.

Rewrite the shell-requirement passage of `deployment/README.md` in place so it states the bash 3.2 floor and the reason the floor exists, superseding the present unversioned sentence rather than adding a second one beside it.

**Out of scope:**

- Declaring a bash 4 floor and failing fast instead of rewriting. Every other tool the script needs already resolves to a stock macOS binary, so a declared floor would leave the script unusable in exactly the shells that motivated this task while the rewrite removes the dependency outright.
- Re-executing the script under a newer bash discovered elsewhere on the machine. This keeps the bash-4 constructs alive behind interpreter-discovery logic and still fails where no newer bash is installed.
- Encoding the shell floor as a rule inside the portability skill, which the sibling task [shell version floor rule](ai-dev_shell-version-floor-rule.md) owns.
- A `make` target that installs missing tooling, which the sibling task [make install dependency floor](../toolchain_make-install-dependency-floor.md) owns.

## Acceptance

- `/bin/bash deployment/deployment.sh --clear-backups --dry-run` completes and prints its run summary, where it currently exits non-zero on an unbound-variable error before any output.
- `/bin/bash deployment/deployment.sh --global --dry-run` completes and prints its per-artefact plan.
- When the Approach locator yields a qualifying bash≥5 interpreter, the output of `--global --dry-run` under `/bin/bash` and under that interpreter is identical, confirming the rewrite changed no behaviour. When it yields none, the identity check is not run and the `/bin/bash` dry-run Acceptance items alone carry the behaviour proof for that host.
- A staged fixture shell file containing `declare -A m=()` is flagged by the new static check, naming the file and the construct; a second fixture containing `${v^^}` is flagged the same way; both fixtures are removed before the tree is final.
- The lint recipe that implements the static check (Makefile / shell-lint step text) includes each greppable pattern Approach names: `declare -A`, `${var^^}` / `${var,,}`, `mapfile`, `readarray`, `declare -n`, `wait -n`, `read -N`, `shopt -s globstar`, `${var@Q}`, `&>>`, `;;&`, `coproc`, `[[ -v`, `EPOCHSECONDS`, and `printf '%(fmt)T'`.
- The new static check reports no finding over the repository's tracked shell files as they stand after the rewrite.
- `tests/deployment/script_tests/run.sh` and `tests/deployment/script_tests/style_run.sh` pass with the deploy script invoked through `/bin/bash`.
- No assertion in `tests/deployment/script_tests/style_run.sh` greps for the literal `declare -A STYLE_MAP` or evaluates `${STYLE_MAP[claude]}` (or any other associative `STYLE_MAP` subscript), and the assertions that replaced those checks name the new structure's own label and prove that the rewritten table or helper yields `natural-language` for `claude`.
- `/bin/bash -n` succeeds on `tests/agent_spinner/evals/grade.sh` and `tests/git_commit/evals/grade.sh`, and neither file calls `mapfile` or `readarray`.
- `deployment/README.md` states the bash 3.2 floor and why it exists, and no remaining passage in that file describes the shell requirement without a version.
