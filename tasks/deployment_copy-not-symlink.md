---
description: Copy every skill and command on deploy instead of symlinking the unaltered ones, and delete the now-dead symlink-creation path so no symlinks land in the target config dirs.
scope: deployment
created: 2026-07-21T12:52:26
updated: 2026-07-21T13:06:44
status: open
reported-by: Andreas Hoffmann
---

# Deploy every artifact as a real file copy instead of a symlink

## Goal

`deployment/deployment.sh` deploys most artifacts as copies already, but it still **symlinks** the unaltered ones: a skill or markdown command that matches no `replace:` rule is linked into the target config dir, while only `replace:`-substituted artifacts are copied. Those symlinks — for example the entries under `~/.claude/skills/` — resolve back into the repo and are awkward to inspect and debug in practice.

Make **copy the sole deployment mode** so every deployed artifact is a standalone real file or directory: skills copy as real directory trees, markdown commands as real files, alongside the hooks that already copy today. The user-visible outcome is that a deployed artifact is a self-contained copy that resolves and debugs like an ordinary file, with no symlink indirection into the source repo, and the "altered vs. unaltered" split disappears at the mechanism level — `replace:` then only layers `$VAR$` substitution on top of a copy every artifact already receives.

The tradeoff this accepts, and must document: a symlink reflected source edits live, whereas a copy is a snapshot. After this change, editing a source skill or command means re-running `make deploy` to refresh the deployed copy.

## Context

The copy-vs-symlink decision lives in `install_for_app()` in `deployment/deployment.sh`. Four branches currently fall back to a symlink, each shaped as `if [[ ${#replacement_specs[@]} -gt 0 ]]` then `copy_path_with_replacements` `else` `create_symlink`:

- the `command` type for `vscode`, for `codex`, and for the default (`claude` / `cursor`) case;
- the `skill` type (one shared branch; a skill's destination is a directory).

`create_symlink()` (under the `# Symlink creation` comment) is reached only from those four sites — no other caller exists — so once the fallbacks become copies it is dead code, and this task removes it. `copy_path_with_replacements()` is the copy path they already use for the `replace:` case: it `cp -R`s a directory source and `cp`s a file source, and with an empty replacement list it copies without substitution (its `maybe_apply_replacements` returns early when it gets zero specs). So an unconditional `copy_path_with_replacements` call covers both the skill-directory and the command-file case with or without `replace:` rules.

Paths that already avoid symlinks and stay unchanged: hooks (`copy_file`), agents and the Gemini/Antigravity commands (generated files), and the merged JSON configs (`merge_json_key`).

Uninstall is already copy-safe and needs no change: `remove_logged_path()` does `rm -rf` for a directory and `rm -f` for a file or symlink, so a copied skill *directory* uninstalls as cleanly as a symlink did.

Removing the symlink mechanism means removing the code that *creates* a symlink, not stripping every `-L` test from the script. The removal, overwrite, and uninstall guards that check `-L` before deleting a destination — in `copy_file`, `copy_path_with_replacements`, the generated-file writers, and `remove_logged_path` — stay: the first deploy after this change overwrites the symlinks earlier deploys left behind, and `--uninstall` must still clean any symlink already recorded in the log. What goes is the branch that makes a new one.

Documentation that describes the current symlink mechanism and goes stale with this change:

- `deployment/README.md` — the deployment matrix rows that read `via symlink` for commands and skills across the tools; the live-edit passage `Symlinked artifacts reflect repo changes immediately`; the two `replace:` descriptions phrased as `Force a copied (not symlinked)` deployment; and the note `Symlink installs refuse to overwrite an existing non-symlink path`.
- Root `README.md` — the phrases `symlink it into vendor config dirs` and `symlinks the skills`.
- Root `CLAUDE.md` — the `make deploy` line `symlink components into vendor config dirs`.
- In-tree comments — the `deployment.conf` line `replace:path VAR=value` described as `Force copied deployment`, and the script comments `# Symlink creation` and `# Copy a file (used where a target's file watcher does not follow symlinks)`.

The `replace:` mechanism keeps working but its meaning narrows: because every artifact is now copied, `replace:` no longer needs to *force a copy* — it only requests `$VAR$` substitution inside the copy. The conf/README wording reduces to that substitution-only meaning.

Companion, not a prerequisite: [deployment_relocate-state-to-home.md](deployment_relocate-state-to-home.md) co-edits the same `deployment.conf` `replace:` comment — it ships an `ai_asset_deploy.conf.template` carrying that header verbatim. Whichever lands second reconciles the comment wording; neither blocks the other.

## Approach

Replace each of the four `create_symlink` fallback branches in `install_for_app()` with a single unconditional `copy_path_with_replacements "$source_abs" "$dest" "$app_id" "$type" "${replacement_specs[@]}"`, collapsing the `if replacements / else symlink` fork to one copy call. A skill then `cp -R`s as a real directory tree, a markdown command copies as a real file, and a `replace:` match still layers substitution on top for the paths it names.

With no caller left, delete the symlink-creation mechanism: remove `create_symlink()` and its `# Symlink creation` section, including the `is not a symlink — refusing to overwrite` skip that lived inside it. Copy is then the only deployment mode, so the `# Copy a file (used where a target's file watcher does not follow symlinks)` comment loses its contrast and reduces to describing a plain copy. Keep the defensive `-L` guards named in Context — they migrate over and uninstall old symlinks rather than create new ones.

Rewrite the stale documentation passages named in Context in place, so each states copy-based deployment and one canonical description remains. In particular, supersede the `Symlinked artifacts reflect repo changes immediately` passage with the re-deploy-to-refresh workflow (every artifact is a copy; re-run `make deploy` after editing a source), turn the matrix `via symlink` cells into copy, and reduce the `replace:` wording to the substitution-only meaning.

**Out of scope:**

- This task adds no watch or auto-redeploy mechanism to offset the loss of live editing; the workflow after editing a source artifact is to re-run `make deploy`.
- This task does not change which artifacts deploy or how `disallow:` / `replace:` matching selects them — only the copy-vs-symlink mechanism for the ones that already deploy.
- Relocating the deploy conf and log into `$HOME` is owned by [deployment_relocate-state-to-home.md](deployment_relocate-state-to-home.md).

## Migration

Future deploys produce copies, but the symlinks already on this machine (under `~/.claude`, `~/.codex`, `~/.cursor`, `~/.gemini`) need a one-time migration after implementation. No custom script is needed: the deploy script's removal guards already overwrite a symlink with a copy in place, and `--uninstall` already removes logged artifacts and prunes their log entries. Order the migration between implementation and audit so the skills stay available throughout:

1. `task_implement` edits `deployment.sh` and the docs; the existing symlinked skills keep working, and the scratch `--project-dir` checks in Acceptance verify the new behaviour without touching the live global dirs.
2. In a terminal, run the migration, then restart the agent. `make deploy --global` (the `deploy` / `global` / `install` target, `./deployment/deployment.sh --global`) overwrites every active symlink with a real copy in place — gap-free, and enough when only the current skill set matters. `make uninstall && make deploy --global` is the fuller sweep that also clears symlinks orphaned by renamed or removed skills: `make uninstall` (`--uninstall`, a no-scope maintenance mode) removes every logged artifact and prunes the log, then the redeploy recreates the current set as copies; run it as one command so the no-skills window is momentary. Either path leaves the deploy conf and its `disallow:` / `replace:` rules untouched — the manifest that points at deployed artifacts is the deploy log, which `--uninstall` prunes, not the conf.
3. After the restart, the agent reloads its skills from the copies, and `task_audit` confirms the deployed artifacts are real files and directories — for example, `find` over the managed target dirs reports no managed symlinks.

`make deploy` is user-gated by the standing repo rules, so this real-global migration is an operator step run by the user, not an implementer acceptance check; Acceptance proves the mechanism on a throwaway `--project-dir` instead.

## Acceptance

- `install_for_app()` deploys every `command` and `skill` branch through `copy_path_with_replacements`, and `create_symlink()`, its `# Symlink creation` section, and the `refusing to overwrite` non-symlink skip no longer appear anywhere in `deployment/deployment.sh` — a grep for the function name and the skip message finds nothing. The defensive `-L` guards in the copy, generated-file, and `remove_logged_path` removal paths remain.
- `./deployment/deployment.sh --global --dry-run` reports `would-copy` for a representative skill and a representative markdown command that previously reported `would-link`, and no `would-link` line appears for any artifact in the run.
- A deploy into a throwaway `--project-dir` scratch directory produces a regular directory for a skill (`test -d` true, `test -L` false at the deployed path) and a regular file for a markdown command (`test -f` true, `test -L` false) — neither is a symlink.
- Deploying into a scratch destination path that already holds a symlink replaces it with the real copy: place a symlink at a dest path, deploy, and confirm the dest is afterward a regular file or directory. This proves the migration path that a re-deploy takes over the user's existing symlinked targets.
- `--uninstall` scoped to that scratch deployment removes a copied skill directory and a copied command file recorded in the log, leaving both target paths absent.
- `deployment/README.md` no longer presents symlink as the mechanism for commands or skills: the matrix rows read as copy, the `Symlinked artifacts reflect repo changes immediately` passage is superseded by the re-deploy-to-refresh statement, and the `replace:` description drops `Force a copied (not symlinked)` for the substitution-only meaning — a grep for the superseded phrases returns nothing outside historical or uninstall context.
- Root `README.md` (`symlink it into vendor config dirs`, `symlinks the skills`) and root `CLAUDE.md` (`symlink components into vendor config dirs`) are reworded to copy-based deployment, with the stale phrasing gone.
- The `deployment.conf` `replace:` comment and the script's surviving `# Copy a file (…does not follow symlinks)` comment are reworded to the copy-only mechanism (the `# Symlink creation` section is gone per the first item, not reworded).
