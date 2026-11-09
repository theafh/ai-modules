---
description: Replace live-home deploy backups with rsync that skips sockets and FIFOs and treats vanished sources as success, add a jq/perl/rsync PATH gate, and prove both in the script tests.
scope: deployment
created: 2026-10-06T11:50:51Z
updated: 2026-10-06T13:59:58Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Back up live harness homes with rsync and fail loud on missing runtime tools

## Goal

Global deploy currently snapshots each activated harness home with `cp -a`. That copy aborts the run when a live Unix socket, FIFO, or vanished sqlite WAL/SHM file sits in the tree, even though the snapshot is meant to keep the whole home (config, session logs, and artefacts). Deliver a backup that still copies that whole tree, omits sockets, FIFOs, and device nodes, and continues when a source file disappears mid-copy. The copy stays a single-process tree walk, so a multi-gigabyte home remains a usable step of `make deploy`.

The same script also uses `jq`, `perl`, and `rsync`. Deliver a startup PATH gate that aborts before any backup or deploy work when one of those three is missing, naming the binary in the error.

The user-visible outcome is that a live global deploy completes through homes that hold sockets and busy sqlite files, the backup still holds ordinary files and symlinks (including paths with spaces), and a machine missing `jq`, `perl`, or `rsync` fails immediately with that name rather than later with an opaque command-not-found.

## Context

`backup_app_dir` in `deployment/deployment.sh` currently copies `$app_dir` into `$HOME/<name>_<timestamp>` with `cp -a`. The header comment block above `copy_path_with_replacements` is not the backup path; the backup is this wholesale home snapshot, documented today under `## Platform Notes` in `deployment/README.md` as relying on `cp` among the stock Unix tools.

Live harness homes routinely contain Unix sockets and sqlite sidecar files that appear and vanish while the harness is running. Those nodes are not the backup's payload. Ordinary files, directories, and symlinks are.

`jq` and `perl` are already required by the script body. `rsync` becomes required once backups use it. There is no check at startup today: a missing extra fails at the first invocation. The live task [make install dependency floor](../toolchain_make-install-dependency-floor.md) still owns declaring a tool floor and turning `make install` into environment preparation. That task currently claims a stock machine already satisfies the runtime extras and does not list `rsync`. This task records the runtime extras as `jq`, `perl`, and `rsync` in that file and leaves the install target itself there.

The standing repo rule that keeps the toolchain to Make, shell, and Markdown, with jq, git, and Python 3 as accepted standing dependencies, still governs: this change adds `rsync` as a runtime extra the deploy script requires on PATH, the same class as `jq` and `perl`, rather than as a new language or package-manager stack.

## Approach

Add `copy_tree_for_backup` in `deployment/deployment.sh` and have `backup_app_dir` call it instead of `cp -a`. The helper `mkdir -p`s the destination, then runs `rsync -rlptgo "$source/" "$dest/"`. Those flags are archive without devices/specials, so sockets, FIFOs, and device nodes are omitted while regular files, directories, and symlinks copy. Treat rsync exit `0` and exit `24` as success. Treat exit `23` as success only when every captured error line reports `No such file or directory`, which is how openrsync reports a vanished source. Any other exit calls `err` with the `backup-copy` label and fails the backup. Comment at the helper that Samba rsync uses 24 for a vanished source, that openrsync uses 23 with that vanished-file wording, that `-a` includes `-D` on both Samba rsync and openrsync, and that current macOS ships openrsync as `/usr/bin/rsync`.

After the existing explicit-scope validation, loop `jq`, `perl`, and `rsync` through `command -v` and abort with `Error: <name> is required for deployment but was not found on PATH.` Rewrite the header comment that currently lists only stock tools so it states those three are required at startup.

Rewrite the `## Platform Notes` paragraph in `deployment/README.md` so the tool list includes `jq`, `perl`, and `rsync`, the startup abort is stated, and the backup sentence states wholesale copy, `rsync -rlptgo`, omitted specials, Samba exit 24 as success, and openrsync exit 23 as success only on vanished-file stderr.

Add two regressions to `tests/deployment/script_tests/run.sh`, keeping them on the existing `run_all.sh` path:

- A `--global` backup against a scratch `HOME` whose Claude tree holds a regular file in a spaced directory name, a symlink, a FIFO, and a Unix socket. Assert the backup directory exists, the file and symlink round-trip, and the socket and FIFO are absent.
- `assert_startup_requires` for each of `jq`, `perl`, and `rsync`: a PATH that contains `dirname` plus the other two extras, run `--global --dry-run`, expect a non-zero exit and the missing name in the required-for-deployment message.

Rewrite the runtime-floor passages of that live make-install task so they list `jq`, `perl`, and `rsync` as required runtime tools, drop the claim that a stock machine already satisfies them, record that a Mac whose `/usr/bin/rsync` resolves must not be brew-installed over, and record that the deploy script's startup `command -v` gate is already shipped and is not a substitute for the manifest.

**Out of scope:**

- Turning `make install` into environment preparation, declaring a versioned manifest, or detaching the `install: deploy` alias, which [make install dependency floor](../toolchain_make-install-dependency-floor.md) owns.
- Narrowing backups to artefact directories only.
- A Python copy helper inside the shell script.
- A per-file `find` plus `cp` backup walk.
- Installing or overwriting rsync when `/usr/bin/rsync` already resolves.

## Acceptance

- `copy_tree_for_backup` in `deployment/deployment.sh` creates the destination with `mkdir -p`, copies with `rsync -rlptgo`, returns success on exit 0, exit 24, and exit 23 whose captured errors are all vanished-file reports, and fails through `err` `backup-copy` on any other exit. `backup_app_dir` calls that helper and no longer uses `cp -a` for the live-home snapshot.
- After scope validation, `deployment/deployment.sh` aborts with `Error: <name> is required for deployment but was not found on PATH.` when `jq`, `perl`, or `rsync` is absent from PATH, and the header comment names those three as required at startup.
- `deployment/README.md` `## Platform Notes` lists `jq`, `perl`, and `rsync` beside the stock Unix tools, states the named-binary startup abort, and states that global backups remain wholesale trees copied with `rsync -rlptgo`, omitting sockets, FIFOs, and device nodes, treating Samba rsync exit 24 as success and openrsync exit 23 as success only when every captured error line reports a vanished source.
- `tests/deployment/script_tests/run.sh` contains the backup fixture and the three `assert_startup_requires` calls described in Approach. `bash tests/deployment/run_all.sh` prints `Backup skip of sockets and FIFOs regression passed` and `Startup gate for jq, perl, and rsync regression passed` and exits 0.
- The live make-install task's runtime-floor text lists `jq`, `perl`, and `rsync` as required, does not claim a stock machine already satisfies the runtime floor, and states that a present `/usr/bin/rsync` is left in place.
- `make clean` followed by `make deploy` (or the current `install` alias of deploy) on a machine whose harness homes contain live sockets completes with a zero exit and a summary that reports a backup for each activated target, with no `backup-copy` error.
