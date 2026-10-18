---
title: Interpreter and tool-path portability
created: 2026-10-03
updated: 2026-10-18
checked: 2026-10-03
type: concept
tags: [portability, skill, authoring]
sources: [raw/notes/agent-delegation-host-observations-2026-09.md]
confidence: high
---

# Interpreter and tool-path portability

## Definition

Interpreter and tool-path portability is the gap between the shell and tools a
developer sees in a login terminal and the ones a bundled script actually gets
when an agent harness runs it. Together, these set the floor, the baseline a
portable bundled script must meet: the stock macOS bash and python3, the licence
reason bash stays at 3.2, the login-shell `PATH` mechanism that hides a newer
build from non-login shells, and the constructs that fail on the stock bash. A
bundled script runs under the interpreter its shebang line names. Two zsh
constructs and two zsh special parameters therefore form a separate case: they
misfire in command lines and snippets that an agent runs directly in its shell
tool.

The shipped `harness_portability` skill carries the bash floor, the rule for
`PATH` in non-login shells, and the list that pairs each failing construct with
a substitute. It has no rule yet on the stock python3's version or on the zsh
constructs and special parameters. The backlog carries the work to record those observations in the
skill's references. This page holds the dated evidence for both the rules and
the observations.
[Deciding where knowledge belongs](../procedures/deciding-where-knowledge-belongs.md)
is the routing rule that puts the evidence here and the rules in the skill.

## Current state of knowledge

### Stock interpreter and why it stays

macOS ships bash 3.2.57 as `/bin/bash`. A `#!/usr/bin/env bash` shebang resolves
to that build whenever no newer bash precedes it on `PATH`. The vendor has not
moved off 3.2 because later bash releases carry a licence it does not ship.
Verified on 3 October 2026 against `/bin/bash --version` on a current macOS
build reporting `GNU bash, version 3.2.57(1)-release`.

On a macOS workstation on 27 September 2026, the stock python3 reported version
3.9.6, and it has no `jsonschema` module. A bundled Python helper that must run
under it therefore keeps to the standard library. Neither `timeout` nor
`gtimeout` was found on that workstation, while BSD `xargs -P` ran
([host observations](../raw/notes/agent-delegation-host-observations-2026-09.md)).

### Login-shell PATH trap

A newer bash on macOS normally arrives through a package manager whose `PATH`
entry is contributed by a login-shell profile. A non-login shell never reads that
profile, so it resolves `bash` to the stock interpreter. Agent harnesses commonly
spawn exactly such shells for the commands they run. An interpreter assumption
that holds in a developer's login terminal therefore fails in every harness-driven
run of the same command. The same mechanism applies to any tool reached only
through a package-manager `PATH` entry.

Observed on 27 September 2026: a non-login `zsh -i` started from a bare
environment found neither markdownlint nor shellcheck. It found the stock system
builds of jq, python3, and bash, while a login `zsh -l` found the
package-manager builds
([host observations](../raw/notes/agent-delegation-host-observations-2026-09.md)).
Each harness's own page records whether its shells run non-login, as the
[Cursor](../entities/cursor.md) page does.

### Constructs above the floor

Sixteen constructs fail on the stock interpreter. Each was verified by executing
it under `/bin/bash` 3.2.57 on 3 October 2026. Four fail at parse time and are
caught by `bash -n` without executing: `&>>`, `;;&`, `coproc`, and
`[[ -v var ]]`. The rest fail only when the line runs:

| Construct | Diagnostic under bash 3.2.57 |
| --- | --- |
| `${var^^}`, `${var,,}` | bad substitution |
| `mapfile`, `readarray` | command not found |
| `declare -n`, `wait -n`, `read -N` | invalid option |
| `shopt -s globstar` | invalid option name |
| `${var@Q}` | bad substitution |
| negative array index | bad array subscript |
| `EPOCHSECONDS` | unbound variable |
| `printf '%(fmt)T'` | invalid format character |

Associative arrays fail in two ways. A bare `declare -A m` reports
`declare: -A: invalid option`. A populated `declare -A m=([k]=v)` is read as an
arithmetic subscript, so under `set -u` it aborts with an unbound-variable error
naming the key, and without `set -u` it silently degrades to an indexed array.

An empty array aborts under `set -u`. Bash before 4.4 treats `"${name[@]}"` on
an empty array as an unbound variable, so on the stock build a copy such as
`copy=("${name[@]}")` stops the script with `name[@]: unbound variable`
whenever the array holds nothing, while bash 5.3.9 copies it as an empty array.
The form `${name[@]+"${name[@]}"}` expands to no words for an empty array and
keeps every element intact otherwise, including elements that contain spaces or
tabs, and shellcheck 0.11.0 reports nothing on it. The form `"${name[@]:-}"`
also avoids the abort, but it yields one empty element that the consuming loop
has to skip. Verified under `/bin/bash` 3.2.57 on 9 and 13 October 2026.

An EXIT trap hides a `set -u` abort on the stock build. When a `set -u` error
stops `/bin/bash` 3.2.57 while an EXIT trap is installed, `$?` reads 0 inside
the trap and the shell exits with the status of the trap's last command. A
cleanup trap such as `trap 'rm -rf "$tmp_dir"' EXIT` therefore turns the abort
into exit 0, and a trap that saves `rc=$?` and exits with it still exits 0. The
same abort exits 1 when no EXIT trap is installed, and a command that fails
under `set -e` keeps its non-zero status under a trap. Bash 5.3.9 exits 1 in
each of these cases. A completion flag restores the failure on the stock build:
the script initializes the flag before it installs the trap and sets it as its
final statement, and the trap exits non-zero while the flag is still unset.
Verified on 9 and 13 October 2026.

The portable substitutes for every construct and `set -u` behaviour above live
in the `harness_portability` skill's shell-features policy rule, where a
reviewer applies them at authoring time. [Skill family architecture](skill-family-architecture.md) explains why
that operative content travels with the skill rather than only with this wiki.

### zsh constructs and special parameters that misfire

The agent shells observed on macOS run zsh, where two constructs misfire without
an error. The first is an ANSI-C quoted alternation for grep, such as
`$'a\|b'`. Under zsh it loses its backslash, so grep cannot match it. In one
orchestrated sweep on 5 September 2026, that form produced false zero counts.
The second is `${PIPESTATUS[0]}`, which expands to nothing under zsh
(15 September 2026,
[host observations](../raw/notes/agent-delegation-host-observations-2026-09.md)).
Verified on 4 October 2026: under `/bin/bash` 3.2.57 the alternation keeps its
backslash and grep matches, and `${PIPESTATUS[0]}` holds the first command's
status. Under zsh 5.9 the backslash drops and `${PIPESTATUS[0]}` stays empty.

Two zsh special parameters break a bash snippet outright when it uses their
names as ordinary variables. `status` is read-only in zsh, because it mirrors
`$?`, so `read -r -d '' status` stops the snippet with
`read-only variable: status`. `path` is the array zsh ties to `PATH`, so
`local path` or `path=…` inside a function empties `PATH`, and the function's
next external command fails with `command not found: git`. The second failure
is quiet when the snippet discards stderr, because the rest of its output still
looks complete. A snippet meant to run in an agent's shell tool therefore keeps
its variable names clear of zsh's special parameters. Verified on 18 October
2026 under zsh 5.9 on macOS, in a Claude Code session whose shell tool ran
`/bin/zsh`, where the same snippets ran correctly under `/bin/bash`.

## Open questions

None for the stock-interpreter floor itself. Whether every target harness's
spawned shell is non-login by default remains a per-harness observation rather
than a settled universal claim; the PATH trap still holds wherever a
package-manager entry depends on a login profile.

## Related concepts

- [Verification surfaces for a shipped skill](verification-surfaces.md), for how
  a floor is proven in the repository's test harnesses.
- [The deployment model](deployment-model.md), for the deploy script that first
  hit this floor in practice.
- [Deciding where knowledge belongs](../procedures/deciding-where-knowledge-belongs.md),
  for the skill-versus-wiki split this page instantiates.

## Derived from

- Direct execution under `/bin/bash` 3.2.57 on macOS (arm64-apple-darwin25),
  3 October 2026: version probe plus one invocation per construct above.
- Direct execution of the ANSI-C quoted alternation and `${PIPESTATUS[0]}` under
  `/bin/bash` 3.2.57 and zsh 5.9 on macOS, 4 October 2026.
- Direct execution of the git_review skill's `references/manual_fallback.md`
  blocks under `/bin/bash` and `zsh -f` on macOS, 18 October 2026, before and
  after their `status` and `path` variables were renamed; its script tests under
  `tests/git_review/script_tests/` now run those blocks under both shells.
- The bash licence and vendor-shipping constraint as stated in the macOS stock
  interpreter situation the deployment rewrite already relied on.
- Direct execution under `/bin/bash` 3.2.57 and bash 5.3.9 on macOS, 9 and
  13 October 2026: an empty-array copy, a `set -u` abort with and without an
  EXIT trap, a trap that saves and re-raises `$?`, a `set -e` failure under a
  trap, and a completion-flag trap.
- The git_commit skill's bundled `prepare_commit_context.sh`, whose empty-array
  copies and cleanup trap met both `set -u` behaviours, and its script tests
  under `tests/git_commit/script_tests/`, which run it under `/bin/bash`.
