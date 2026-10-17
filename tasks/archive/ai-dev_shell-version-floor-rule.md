---
description: "Give harness_portability a concrete shell interpreter floor plus wiki evidence: bash 3.2 why, bash 4+ constructs with substitutes, non-login PATH trap, and dated wiki verification."
scope: plugins/ai_dev/skills/harness_portability
created: 2026-09-18T19:48:56
updated: 2026-10-16T22:53:04
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Give harness_portability a concrete shell interpreter floor and wiki evidence page

## Goal

The `harness_portability` skill already carries the principle that covers interpreter versions, in the policy rule beginning `Use POSIX shell features for shell scripts unless the script declares and checks for a stronger shell requirement such as Bash.` What it does not carry is any concrete shell fact: which bash version a bundled script may assume, why that version and not a newer one, which constructs sit above the floor, and what replaces each of them. An agent applying the skill today can satisfy the rule's letter by writing bash-4 code and declaring bash 4, which is exactly the outcome the rule exists to prevent for a script that ships into other people's repositories.

After this task the skill states the floor and the reasoning behind it, so a review catches a bash-4 construct in a bundled script at authoring time rather than when a user's shell resolves to a stock interpreter. The skill gains the version floor with its justification, the verified list of constructs that sit above it paired with portable substitutes, and the environment trap that makes the floor bite. The `<review_checklist>` entry for shell portability, which today reads `Shell syntax, utilities, and flags work on macOS and Linux or are guarded with fallbacks.`, gains the interpreter-version dimension it currently leaves implicit. The dated evidence behind the facts lands in the repository's wiki, where the skill's own `<where_snapshots_live>` guidance sends a verified harness fact.

## Context

Three facts carry the rule, each verified on a current macOS build rather than recalled. The skill carries the operative floor, a one-clause durable why, the construct-to-substitute list, and the PATH trap; the wiki carries the dated verification of those facts.

macOS ships bash 3.2.57 as `/bin/bash` and has not moved off it, because later bash releases carry a licence the vendor does not ship. A `#!/usr/bin/env bash` shebang therefore resolves to that build whenever no newer bash precedes it on `PATH`.

The skill states the stock version and that one-clause licence why; the dated licence and vendor evidence stay on the wiki page.

A newer bash on macOS normally arrives through a package manager whose `PATH` entry is contributed by a login-shell profile. A non-login shell never reads that profile, so it resolves `bash` to the stock interpreter. Agent harnesses commonly spawn exactly such shells for the commands they run, which turns an interpreter assumption that holds in a developer's terminal into a failure in every harness-driven run of the same command.

Sixteen constructs fail on the stock interpreter, each with its own diagnostic, verified by executing each one under that build. Four fail at parse time and are caught by `bash -n` without executing: `&>>`, `;;&`, `coproc`, and `[[ -v var ]]`. The rest fail only when the line runs: `${var^^}` and `${var,,}` report a bad substitution, `mapfile` and `readarray` are not found, `declare -n` and `wait -n` and `read -N` report an invalid option, `shopt -s globstar` reports an invalid option name, `${var@Q}` reports a bad substitution, a negative array index reports a bad array subscript, `EPOCHSECONDS` is unbound, and `printf '%(fmt)T'` reports an invalid format character. Associative arrays deserve their own note because they fail in two different ways: a bare `declare -A m` reports `declare: -A: invalid option`, while a populated `declare -A m=([k]=v)` is read as an arithmetic subscript, so it aborts under `set -u` with an unbound-variable error naming the key and silently degrades to an indexed array without it.

The skill pairs each construct with its portable substitute; per-construct diagnostics and the verification method stay on the wiki page.

The skill's existing surfaces set where each piece belongs. The policy rule quoted under **Goal** is the passage the floor extends. The `<review_checklist>` shell entry quoted there is the reviewer-facing counterpart. The `<failure_modes>` entry, `Missing dependency, unsupported OS, unsupported shell, and missing config errors are actionable for a future agent.`, already demands that an unsupported-shell error be actionable, which the floor makes concrete. The policy rule beginning `Use feature detection for external commands, optional tools, shells, package managers, and OS-specific utilities` covers detection of the interpreter once a script genuinely needs a stronger one.

Per the standing repo rules on skill-versus-wiki placement and on routing wiki writes, dated verification for this floor lands in this repository's wiki. The skill's own `<where_snapshots_live>` names the wiki first and `references/` as fallback; this skill currently has no `references/` directory. The wiki's concept pages carry no interpreter or shell-portability page today, so this finding arrives as a new concept page.

## Approach

Rewrite the policy rule beginning `Use POSIX shell features for shell scripts` in place so it states the floor and the one-clause licence why rather than only the principle: a bundled runtime script targets bash 3.2 as the interpreter floor because later bash releases carry a licence the vendor does not ship, and a script needing more declares the requirement and detects it, failing with a message naming the required version and the interpreter actually running. Keep the rule's existing sentence that begins `Use Python standard-library APIs`, which is unaffected.

Add the construct list and its substitutes to the skill in the form a reviewer can apply directly, pairing each banned construct with what replaces it at the floor:

- associative array (`declare -A`): indexed array of delimited entries with an exact-match scan
- case modification (`${var^^}`, `${var,,}`): bracket-class glob or `tr`
- `mapfile` / `readarray`: `while IFS= read -r` loop
- `&>> file`: `>>file 2>&1`
- `;;&` (case fallthrough): shared function called from each matching arm, or duplicated arm bodies
- `coproc`: background job (`command &`) with a FIFO (`mkfifo`) or temp files for the two streams
- `[[ -v var ]]`: `[ -n "${var+set}" ]`
- `declare -n` (nameref): `${!name}` for indirect expansion, or pass the value via arguments/stdout
- `wait -n`: `wait` on an explicit PID, or poll with `kill -0` until a chosen child exits
- `read -N`: `dd bs=1 count=N 2>/dev/null` (or `head -c N`) into a variable
- `shopt -s globstar`: `find` for recursive path walks
- `${var@Q}`: `printf %q "$var"`
- negative array index: compute a non-negative index from `${#arr[@]}` before subscripting
- `EPOCHSECONDS`: `date +%s`
- `printf '%(fmt)T'`: `date +fmt` with the matching format string

Keep the list inside the skill rather than in a reference file, because it is the operative content of the rule rather than a perishable harness fact, and the skill has to carry it into repositories that have no wiki.

State the non-login shell trap as its own rule, since it is the mechanism that makes an interpreter assumption fail in a harness while passing in a terminal, and it generalizes past bash to any tool reached only through a package manager's `PATH` entry. Pair it with the consequence for scripts: prefer what the operating system ships, and detect anything else.

Extend the `<review_checklist>` shell portability entry in place so it asks whether the interpreter version the script assumes is at or above the floor, and whether a stronger requirement is declared and detected.

Record the dated, sourced evidence in the repository's wiki as the concept of interpreter and tool-path portability: the stock version and the reason it stays, the login-shell `PATH` mechanism, the verified construct behaviours, and the date and method of verification. Keep the skill's own text free of the dated snapshot, so a portability review costs the rules rather than the evidence.

**Out of scope:**

- Rewriting `deployment/deployment.sh` onto the floor, which the sibling task [bash 3.2 floor](deployment_bash-32-floor.md) owns.
- Renaming this skill, which an archived deferred task already weighed and parked.
- Auditing the other bundled scripts for conformance. Each already passes a bash 3.2 syntax check and uses no construct above the floor, so this task adds the rule rather than a migration.

## Acceptance

- The skill's policy rule on shell features names bash 3.2 as the interpreter floor for bundled runtime scripts and states what a script does when it genuinely needs more, including the failure-message contract the opening Approach paragraph requires, and no remaining passage states the shell requirement without a version.
- The skill's policy rule on shell features states the one-clause licence why for the bash 3.2 floor.
- The skill's policy rule on shell features still carries the sentence that begins `Use Python standard-library APIs`.
- The skill carries every construct recorded under **Context** paired with the portable substitute named for that construct under **Approach**, and a reader can determine from the skill alone what replaces an associative array at the floor.
- The skill states the login-shell `PATH` mechanism and its consequence for interpreter and tool assumptions.
- The `<review_checklist>` shell portability entry asks about the assumed interpreter version and whether a stronger requirement is declared and detected, where it currently asks only about syntax, utilities, and flags across the two operating systems.
- A wiki page carries the stock interpreter version, the licence reason it stays, the login-shell `PATH` mechanism, the verified construct behaviours, and the verification date and method, and the wiki index lists it.
- The skill body carries no dated snapshot of the facts recorded on that wiki page.
