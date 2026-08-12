---
description: Exclude __pycache__ directories and stray .pyc files from every deployed artifact so a working tree that ran bundled skill scripts stops pushing Python bytecode into vendor config dirs.
scope: deployment
created: 2026-08-10T23:01:29
updated: 2026-08-12T22:44:15
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Exclude Python bytecode from deployed artifacts

## Goal

A deploy copies a skill directory verbatim, so a `__pycache__/` directory sitting in a source skill's `scripts/` folder lands in every vendor config directory the deploy reaches. Deliver the opposite: a deployed artifact carries the skill's real files and no Python bytecode, whatever build residue the working tree happens to hold at deploy time.

This is an observed leak, not a hypothetical one. At the time of writing, three source skills carried a `scripts/__pycache__/` directory, and the two whose bytecode predated the most recent deploy had been copied into six vendor skill roots, each holding a `lint.cpython-314.pyc` stamped with that deploy's timestamp. One of those source `.pyc` files was roughly two months stale, so it had been riding along on every deploy since. The bytecode is gitignored, so it never reaches a commit and no review catches it.

The user-visible outcome is that a deployed skill directory holds only the artifact's own files. A deploy run from a tree that has executed bundled skill scripts produces a destination byte-identical to one run from a clean checkout.

## Context

The single leak site is the directory branch of `copy_path_with_replacements()` in `deployment/deployment.sh`, which copies a directory source with `cp -R "$source" "$target"` and a file source with `cp "$source" "$target"`. `cp -R` copies the tree wholesale and BSD `cp` offers no exclusion flag, so every gitignored artifact inside the source directory travels with it. That function is the copy path for skill directories, established when the deploy dropped symlinks in favour of copies: see [deployment_copy-not-symlink.md](deployment_copy-not-symlink.md) for the four call sites it consolidated and why copy became the sole mode.

Two facts bound the work, both read from the current script:

- The function already clears the destination before copying, taking `rm -f` on a symlink or file and `rm -rf` on a directory. So the fix needs no separate cleanup pass over destinations that already hold bytecode: the next deploy after the fix removes each stale `__pycache__` along with the destination directory it sits in.
- `remove_logged_path()` already does `rm -rf` for a logged directory, so `--uninstall` cleans a deployed skill directory whatever it contains. Uninstall needs no change.

Single-file copy paths carry no exposure, because bytecode leaks as a directory member rather than as an artifact the discovery step would pick up on its own. Hooks (`copy_file`), generated agent files, and the merged JSON configs are all outside this task.

The deploy's documented discovery rules live in `deployment/README.md` under the **Plugin asset folders** heading, whose passage beginning `Hidden files and` states what discovery skips today. That passage describes artifact selection rather than copy contents, so this task's exclusion needs its own statement there rather than an edit to that sentence.

## Approach

Prune the bytecode from the destination immediately after the directory copy in `copy_path_with_replacements()`, before `maybe_apply_replacements` runs, using `find` plus `rm` rather than reaching for a copy tool with an exclude flag. The standing repo rule keeping the toolchain to Make, shell, and Markdown with jq, git, and Python 3 as the accepted standing dependencies settles this: adding `rsync` for its `--exclude` flag would introduce a new dependency, and the macOS default `rsync` has diverged from the GNU flag surface, so `find` and `rm` on the already-copied tree is both portable and dependency-free. Remove `__pycache__` directories and any remaining `*.pyc` file, so a stray bytecode file outside a `__pycache__` directory is covered too.

Keep the dry-run branch reporting what it reports now. The preview reports the copy action rather than the resulting file list, so its output does not change.

State the new behaviour in `deployment/README.md` near the **Plugin asset folders** discovery rules, so the copy contract is documented alongside what discovery selects.

**Out of scope:**

- A general, configurable ignore-list mechanism for deployed artifacts. This task hardcodes Python bytecode, which is the residue the repo's own bundled scripts generate; a rule covering `.DS_Store`, `node_modules`, or a user-supplied pattern set is separate work nothing yet calls for.
- Deleting the `__pycache__` directories that already sit in the source tree under `plugins/`. They are gitignored build residue that reappears whenever the scripts run, and the fix makes their presence harmless.

## Acceptance

1. A source skill directory staged with both a `scripts/__pycache__/` directory holding a `.pyc` file and a stray `scripts/*.pyc` file outside it deploys to a destination that contains the skill's real files, no `__pycache__` directory, and no `.pyc` file. Stage the source and target under a scratch directory and deploy with `--project-dir` so the check touches no global config directory. Compare that destination's full recursive listing and per-file checksums against the same skill deployed from a source tree with no bytecode residue; the two destinations are byte-identical.
2. Re-running that same deploy over a destination that already holds a `__pycache__` directory leaves no `__pycache__` directory and no `.pyc` file behind, which proves the already-shipped bytecode self-heals rather than needing a separate migration.
3. A deployed skill directory whose source carries no bytecode is byte-identical before and after the change, so the prune removes nothing else. Compare a full recursive listing and per-file checksums of one such destination across the two script versions.
4. `./deployment/deployment.sh --global --dry-run` exits 0 and reports the same count of copy actions as before the change, confirming the preview path is untouched.
5. The scenarios proving items 1 through 3 are added to `tests/deployment/script_tests/run.sh` and pass there, alongside the harness's existing scenarios.
6. `deployment/README.md` states that a deployed artifact excludes Python bytecode, placed with the **Plugin asset folders** discovery rules, and a reader of that section can tell that the exclusion applies to copy contents rather than to artifact selection.
