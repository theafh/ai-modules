---
description: Move deployment.sh per-machine state (deploy log + user conf) out of the repo into $HOME, shipping shared defaults as a committed .template.
scope: deployment
created: 2026-06-02T18:58:04
updated: 2026-10-09T18:48:19
status: open
reported-by: Andreas Hoffmann
---

# Relocate deployment.sh per-machine state (conf + log) to $HOME

## Goal

`deployment/deployment.sh` currently keeps both its per-tool config and its uninstall manifest *inside the repo tree*, derived from `SCRIPT_DIR`:

- `DEPLOYMENT_CONF="${SCRIPT_DIR}/deployment.conf"` in `deployment.sh`
- `DEPLOYED_ARTIFACTS_LOG="${DEPLOYED_ARTIFACTS_LOG:-${SCRIPT_DIR}/deployed_artefacts.log}"` in `deployment.sh`, where an environment variable of the same name overrides that default

This script is bundled into several repos. Two problems follow:

1. **The conf is committed and machine-specific edits dirty the repo.** `deployment.conf` is git-tracked; a user's local tweaks show up as a permanent `M deployment/deployment.conf`.
2. **The log is per-script-copy state.** Each bundled copy writes its own `deployed_artefacts.log` next to itself, so `--uninstall` run from repo A is blind to artifacts deployed from repo B, even though both deployed into the same global config dirs.

Deliver a change where **per-machine state lives in `$HOME`** (consistent with backups, which already land in `$HOME`, per the `Backups land in $HOME` behavior in `deployment.sh`) and the repo carries only a committed `.template` of shared defaults. Outcome: a clean repo working tree, a single machine-wide uninstall manifest, and a fresh checkout that still deploys with sane defaults.

## Context

Relevant code in `deployment/deployment.sh`:

- The `DEPLOYED_ARTIFACTS_LOG` and `DEPLOYMENT_CONF` definitions (both off `SCRIPT_DIR`). Since 9 October 2026 an environment variable named `DEPLOYED_ARTIFACTS_LOG` overrides the log path, and `print_usage` documents it under `Environment:`.
- The log append + dedupe helpers `append_deployed_artifact_log` and `dedupe_deployed_artifact_log`; `trap dedupe_deployed_artifact_log EXIT` writes the log.
- `parse_deployment_conf`; tolerates a missing conf (`[[ -f "$DEPLOYMENT_CONF" ]] || return 0`).
- `uninstall_logged_artifacts`; the only reader of the log. Already filters by active target and type.
- The `Config:` banner line that echoes the conf path.

The sibling task [bash 3.2 floor](archive/deployment_bash-32-floor.md) rewrites the two associative arrays `parse_deployment_conf` fills into indexed arrays, so whichever of the two lands second builds on the other's shape rather than the one quoted here.

Current conf (`deployment/deployment.conf`) is **not purely machine state**. It carries shared defaults every checkout needs:

- `disallow:*legacy*` under each tool section, a shared default.
- `style:<name>` under `#claude`, naming the active output style the Claude deploy merges into that tool's settings.

So the conf is really **shared defaults plus whatever override layer a machine adds**. Moving it wholesale to `$HOME` as the only source would lose those defaults on a fresh checkout. The committed `.template` is what carries them.

The eval micro-deployment depends on both files. `tests/lib/micro_deploy.py` runs this script for every eval pass with `HOME` set to a scratch home and `DEPLOYED_ARTIFACTS_LOG` set to a log inside it, so a test deploy never writes the machine's log, and `tests/lib/test_micro_deploy.py` checks that the machine's log stays byte-identical across a micro-deployment. Each micro-deployment also reads the in-repo `deployment.conf`, whose `style:natural-language` line under `#claude` is what sets `outputStyle` when the `natural_language` harness deploys its style; the Claude arm of the style branch is the only reader of a `style:` line. Once the conf lives in home, a scratch `HOME` holds no conf, so the script falls back to the template, which carries no `style:` rule, and the style deploys without `outputStyle`.

Other references that hardcode the old paths and must move in lockstep, all of which `git grep -n -e 'deployed_artefacts' -e 'deployment\.conf' -- ':!tasks' ':!wiki/log.md' ':!CHANGELOG.md'` lists:

- `deployment/README.md` names `deployment/deployed_artefacts.log` and `deployment.conf`.
- Root `README.md` lists `deployment.conf` in the layout tree, and names it again as the file that carries the active style.
- `.gitignore` ignores `deployment/deployed_artefacts.log` (becomes obsolete once the log leaves the tree).
- `tests/deployment/script_tests/run.sh` and `style_run.sh` copy the in-repo log aside, run the script against it, and restore it on exit, and `style_run.sh` reads its entries.
- `tests/lib/test_micro_deploy.py` guards the in-repo log as the machine's log through its `DEPLOY_LOG` constant.
- `wiki/concepts/deployment-model.md` names both in-repo paths.
- Every standing repo instruction file describes `make uninstall` as removing deployed artefacts via the deployment log.

Prior-art scan (Tier 1) found only incidental hits: other tasks invoke `deployment.sh --global --dry-run` as an acceptance check, but none addresses conf/log relocation. This work is novel.

## Approach

Relocate both files into a single hidden state directory in the user's home: **`~/.ai_asset_deploy/`**, containing:

- `~/.ai_asset_deploy/config`: the per-machine conf (replaces in-repo `deployment.conf`).
- `~/.ai_asset_deploy/deployed.log`: the uninstall manifest (replaces in-repo `deployed_artefacts.log`).

Grouping the two under one dot-dir keeps the home directory tidy and reads more naturally than a log sitting at the top level of `$HOME`.

Handle the two files according to what each one is:

- **Log → `~/.ai_asset_deploy/deployed.log`.** It is pure machine state and the cross-repo uninstall manifest, so it lives in home, apart from a run that points `DEPLOYED_ARTIFACTS_LOG` elsewhere. Create it there on first write when it is absent. This gives one machine-wide manifest, so `--uninstall` from any bundled copy of the script sees every artifact deployed on the machine.
- **Conf → `~/.ai_asset_deploy/config`** for the user's live config, with the committed `.template` in the repo as the read-only fallback so a fresh checkout deploys with the shared defaults.

Resolution precedence:

1. **Log**: read and write the path `DEPLOYED_ARTIFACTS_LOG` names when that variable is set, and `~/.ai_asset_deploy/deployed.log` otherwise. The override stays, because the eval micro-deployment and the deploy script tests keep each test deploy's log in a scratch tree through it.
2. **Conf**: read `~/.ai_asset_deploy/config` when present; otherwise fall back to the bundled `.template`.

### The committed template

Ship `deployment/ai_asset_deploy.conf.template` (the `.template` suffix is an unmistakable "copy me, don't edit me live" signal). Its content mirrors the **original default conf**, with the usage-comment header carried over verbatim, then every tool section present with `disallow:*legacy*` as the worked example, and **no Claude-specific rule**:

```text
# ai_asset_deploy config — per-tool deployment configuration
#
#   #tool                  Section heading — tool identifier (vscode, cursor, claude, codex, antigravity, opencode)
#   disallow:path          Local repo path relative to repo root (e.g. agents/check_spec_codex.md)
#                         Glob patterns supported (* matches within a segment, ** matches across segments)
#   replace:path VAR=value Replace $VAR$ inside matching deployed copies. A trailing slash
#                         applies to a whole subtree.
#   style:<name>           Active output-style name for that tool (merged into the tool's settings)
#
# Assets not listed under a tool section are deployed to that tool.
# Assets listed under disallow: are skipped for that tool.
# Multiple replace: lines can apply to the same path.

#cursor
disallow:*legacy*

#vscode
disallow:*legacy*

#claude
disallow:*legacy*

#codex
disallow:*legacy*

#antigravity
disallow:*legacy*

#opencode
disallow:*legacy*
```

The template is the generic starting point. Any per-tool rule a machine adds beyond these defaults is **that machine's local customization**, not a shared default, so it belongs in the home conf and not the template.

### One-time migration of the current setup (required)

The point of this task is that the current working setup is **retained**, not reset. On the relocation:

1. **Copy the current live log into home.** `deployment/deployed_artefacts.log`, carrying this machine's real entries, must be **copied to `~/.ai_asset_deploy/deployed.log`** so every already-deployed artifact stays uninstallable. Do this before removing it from the repo.
2. **Seed the home conf from the current live conf, not the template.** `~/.ai_asset_deploy/config` must be created from `deployment/deployment.conf` exactly as it stands at migration time, so the machine's actual behaviour carries over unchanged, including any rule the generic template does not ship.
3. **Stop tracking the in-repo files.** `git rm` the tracked `deployment.conf`, remove the in-repo `deployed_artefacts.log`, commit the `.template`, and drop the now-obsolete `.gitignore` entry for the log (nothing left in the tree to ignore).

The script may automate the seeding on first run (if no home conf/log exists but the in-repo ones do, copy them up), or it can be a documented one-time manual step, but the end state for this machine is: home conf carrying the live conf's content unchanged, home log carrying all current entries.

### Test deploys

Seed each scratch home before a micro-deployment runs the script: in `tests/lib/micro_deploy.py`, write `<scratch home>/.ai_asset_deploy/config` from the committed template, with a `style:<name>` line under `#claude` for the style the pass's declaration names, if it names one. The scratch `HOME` makes that file the conf the script reads, so the style deploy still sets `outputStyle`, and test deploys stop depending on this machine's live conf. Point `DEPLOY_LOG` in `tests/lib/test_micro_deploy.py` at `~/.ai_asset_deploy/deployed.log` under the real home. In `tests/deployment/script_tests/run.sh` and `style_run.sh`, replace the copy-aside of the in-repo log with a scratch log that `DEPLOYED_ARTIFACTS_LOG` names, and read entries from that log.

### Guardrails

- Keep the toolchain to Make + shell, per the repo rules' authoring convention.
- Keep the conf a single flat robots.txt-style file: home replaces repo, bootstrapped from the template. (Template-base + home-override *layering* stays a deferred option; see below.)

When implementing, confirm with the user that the machine-wide log is the intended behavior: `--uninstall` from any bundled copy of the script will clean every artifact recorded in the shared manifest across all repos. This is the natural consequence of one home-level log and is almost certainly what is wanted; document it in `deployment/README.md` as the expected behavior.

### Explored but deferred alternatives

Considered and set aside for this task; revisit only if asked:

- **Two loose dotfiles** (`~/.ai_asset_deploy.conf` + `~/.ai_asset_deploy.log`). Workable; the single dot-dir groups the state more cleanly.
- **XDG base dirs** (`$XDG_CONFIG_HOME` / `$XDG_STATE_HOME`). Stronger on Linux, but heavier and split across two trees; the single dot-dir stays simpler.
- **Further flag / env-var overrides** (`--config PATH` / `--log PATH`, a conf override variable). The log already has one, `DEPLOYED_ARTIFACTS_LOG`, which the eval micro-deployment brought in on 9 October 2026. A conf override stays deferred, because a scratch `HOME` already gives a test run its own home conf.
- **Template + home-override layering.** Merge a committed base conf with home overrides. Defer in favor of the simpler "home replaces repo" model.

## Acceptance

- Conf and log resolve to `~/.ai_asset_deploy/config` and `~/.ai_asset_deploy/deployed.log`, with documented precedence: the conf reads home, then the template; the log uses `DEPLOYED_ARTIFACTS_LOG` when it is set, and home otherwise.
- `deployment.conf` and `deployed_artefacts.log` are no longer in the repo; a committed `deployment/ai_asset_deploy.conf.template` carries the generic defaults: every tool section with `disallow:*legacy*` and **no** Claude-specific rule.
- The current live log is **copied** to `~/.ai_asset_deploy/deployed.log` so the setup is retained: verify the pre-relocation entries are present and that `--uninstall` cleanly removes a previously-deployed artifact afterward.
- `~/.ai_asset_deploy/config` on this machine reproduces the live `deployment.conf` byte-for-byte at migration time; confirm a `--dry-run` produces the same per-tool exclusions and the same active style after relocation as before it.
- A fresh checkout with no home conf falls back to the template and deploys with the generic defaults (`*legacy*` skipped for every tool, Claude **not** excluded); confirm via `./deployment/deployment.sh --global --dry-run`.
- `deployment/README.md`, root `README.md`, `.gitignore`, and `wiki/concepts/deployment-model.md` (edited through the wiki skill family) are updated to the new paths, and none of them still names `deployment/deployed_artefacts.log` or the in-repo `deployment.conf`.
- `./deployment/deployment.sh --global --dry-run` runs without error and shows the resolved `~/.ai_asset_deploy/` conf/log paths in its banner.
- `python3 tests/lib/test_micro_deploy.py` passes with `DEPLOY_LOG` naming `~/.ai_asset_deploy/deployed.log`, and its check that a Claude micro-deployment of `natural-language` sets `outputStyle` holds against a scratch home whose `.ai_asset_deploy/config` the helper seeded.
- `bash tests/deployment/run_all.sh` passes, and neither `script_tests/run.sh` nor `script_tests/style_run.sh` names `deployment/deployed_artefacts.log`.
- Working tree is clean after a deploy (no `M deployment/deployment.conf`).
