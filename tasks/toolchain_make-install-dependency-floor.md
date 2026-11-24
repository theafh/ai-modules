---
description: "Declare the repository's load-bearing tool floor in one file and make `make install` report it, freeing the name from the deploy alias."
scope: "repo toolchain"
created: 2026-09-18T11:48:56Z
updated: 2026-11-24T05:56:40Z
status: checked
reported-by: Andreas Hoffmann
---

# Make `make install` report the declared tool floor

## Goal

`make install` is currently an alias for `make deploy`. The repository declares its load-bearing tool floor in one plain-text manifest: the tools the repository, the deploy script, and the shipped plugin scripts genuinely need, and that a standard macOS or Linux machine does not guarantee at the version the work requires. Each record carries the tool, how to detect it, the minimum version where a version matters, and the command that installs it on macOS and on Linux.

`make install` walks the manifest and reports every tool with its status — satisfied, missing, or present below its minimum — naming the version found and required, and printing the install command for anything missing or too old. It exits non-zero while a required tool is missing or below its minimum, so a caller can rely on its status.

`make install` reports; it does not install. The repository is not building an auto-installer: when a tool is needed, the operator installs it and the manifest gains the record. The deploy keeps its own entry points (`make deploy`, `make global`, `make update`), and the standing documentation stops presenting `install` as a third name for the deploy.

The floor is a minimum, not a lock: a newer tool satisfies it, and the list grows when the repository needs something new.

## Context

- The deploy script aborts at startup when `jq`, `perl`, or `rsync` is missing from `PATH` (`deployment/deployment.sh`). That gate is a fail-loud PATH lookup; this task owns the declared floor, the report, and freeing the `install` name.
- The floor covers what the repository's own targets and shipped scripts need: `jq` for the deploy and lint paths, `markdownlint`, `shellcheck`, and `python3` for `make lint` (the frontmatter gate runs `python3 scripts/lint_frontmatter.py`), and `python3` for `make test`. A tool that ships at a sufficient version on every supported machine stays out of the manifest.
- `perl` and `rsync` ship on macOS and typical Linux; `jq` is often absent on Linux and old on older macOS. `markdownlint` and `shellcheck` are never stock.
- The name collision is recorded in the Makefile's `install: deploy` alias, the alias sentence in each standing repo instruction file that carries it, the README's target listing comment, the README layout-tree line for the Makefile, and the Makefile header comment. Those are the edit sites; find the instruction files by the sentence they carry rather than by a count.
- The repository's toolchain is Make, shell, and Markdown, with jq, git, and Python 3 as standing dependencies. The manifest is plain text a `while IFS= read -r` loop can read, so no parser and no new dependency enters the repository.

## Approach

1. Add the manifest as a plain-text file the Makefile reads, one record per tool: name, detection command, minimum version (empty when no version matters), and the macOS and Linux install commands. Keep it readable by a plain shell read loop.
2. Pin a minimum only where the version matters: `markdownlint`, `shellcheck`, and `jq` carry one; a record whose version has never mattered leaves the field empty. Choose a minimum at or below the version this repository runs today, so a working machine stays green.
3. Name one install command per platform per record, using Homebrew on macOS and one named package command on Linux; leave the field empty where the tool is stock on that platform, so a present stock tool reports satisfied and an absent one is named for the operator. Report the package manager itself when a command needs one that is absent.
4. Replace the `install: deploy` alias with an `install` recipe that walks the manifest, prints one status line per tool, prints the install command for anything missing or below its minimum, and exits non-zero while a required tool is missing or below its minimum. Detect the platform with `uname` and treat an unknown platform as the no-install-command case.
5. Read each minimum-bearing tool's version from its own `--version` output, taking the first dotted number, and compare it with `sort -V`; report a below-minimum tool as its own status carrying the version found and the version required.
6. Keep `global` as the deploy alias. Rewrite the alias sentence in every standing repo instruction file that carries it, the README target listing, the README passage that tells the reader to install the lint tools by hand, the README layout-tree line for the Makefile, and the Makefile header comment, so each names the new `install` meaning.
7. Add `make install` to the instruction files' Common tasks list, replacing the alias bullet.

**Out of scope:**

- Running installs. `make install` reports and prints commands; installing stays the operator's act.
- Separate runtime and development floors. One floor, reported as one list.
- Replacing the deploy script's startup `command -v` gate.
- Adopting a version manager or package-manager manifest format as a new prerequisite.
- Pinning exact versions, or a linter configuration to stabilise the check set.
- Installing the agent CLI the skill evals drive.
- Refreshing the wiki toolchain summary, which is a separate knowledge update.
- Continuous integration.

## Acceptance

1. A manifest exists in the repository, one record per tool, carrying name, detection command, minimum, and per-platform install commands; the Makefile recipe reads it rather than restating the tool list.
2. `make install` on a machine with every declared tool present prints one status line per tool, reports every tool satisfied, prints no install command, and exits 0.
3. With `jq` made unresolvable through a scratch `PATH`, `make install` reports `jq` missing, prints its install command without running it, and exits non-zero, while `perl` and `rsync` still report satisfied.
4. With a minimum-bearing tool stubbed to report a version below its declared minimum, `make install` reports it under a distinct status naming the version found and the version required, prints its install command, and exits non-zero.
5. Each minimum-bearing tool's extracted version equals the first dotted number in that tool's own `--version` output, checked for every minimum-bearing record.
6. A record with no install command for the current platform is reported with what the operator should do, and no command is run.
7. `make install` no longer runs the deploy, and `make deploy`, `make global`, and `make update` still deploy.
8. `make help` lists `install` with its environment-preparation description, and the Makefile header comment matches.
9. No standing repo instruction file, README target listing, or README layout-tree line presents `install` as an alias of `make deploy`, and each lists `make install` as the environment-preparation target.
10. The README passage that today tells the reader to install the lint tools by hand points at `make install`, and no remaining README passage instructs a manual install of a tool the manifest declares.
