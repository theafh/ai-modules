---
description: Move deployment.sh per-machine state (deploy log + user conf) out of the repo into $HOME, shipping shared defaults as a committed .template.
scope: deployment
created: 2026-06-02T18:58:04
updated: 2026-06-13T01:47:36
status: open
---

# Relocate deployment.sh per-machine state (conf + log) to $HOME

## Goal

`deployment/deployment.sh` currently keeps both its per-tool config and its uninstall manifest *inside the repo tree*, derived from `SCRIPT_DIR`:

- `DEPLOYMENT_CONF="${SCRIPT_DIR}/deployment.conf"` in `deployment.sh`
- `DEPLOYED_ARTIFACTS_LOG="${SCRIPT_DIR}/deployed_artefacts.log"` in `deployment.sh`

This script is bundled into several repos. Two problems follow:

1. **The conf is committed and machine-specific edits dirty the repo.** `deployment.conf` is git-tracked; a user's local tweaks show up as a permanent `M deployment/deployment.conf` (exactly the current working-tree state).
2. **The log is per-script-copy state.** Each bundled copy writes its own `deployed_artefacts.log` next to itself, so `--uninstall` run from repo A is blind to artifacts deployed from repo B — even though both deployed into the same global config dirs.

Deliver a change where **per-machine state lives in `$HOME`** (consistent with backups, which already land in `$HOME` — the `Backups land in $HOME` behavior in `deployment.sh`) and the repo carries only a committed `.template` of shared defaults. Outcome: a clean repo working tree, a single machine-wide uninstall manifest, and a fresh checkout that still deploys with sane defaults.

## Context

Relevant code in `deployment/deployment.sh`:

- The `DEPLOYED_ARTIFACTS_LOG` and `DEPLOYMENT_CONF` definitions (both off `SCRIPT_DIR`).
- The log append + dedupe helpers `append_deployed_artifact_log` and `dedupe_deployed_artifact_log`; `trap dedupe_deployed_artifact_log EXIT` writes the log.
- `parse_deployment_conf`; tolerates a missing conf (`[[ -f "$DEPLOYMENT_CONF" ]] || return 0`).
- `uninstall_logged_artifacts`; the only reader of the log. Already filters by active target and type.
- The `Config:` banner line that echoes the conf path.

Current conf (`deployment/deployment.conf`) is **not purely user-specific** — it mixes shared architectural policy with personal overrides:

- `#claude` / `disallow:**` — "Claude is served via the marketplace, not these symlinks." This applies to *everyone* using the repo.
- `*legacy*` excludes under each tool — shared default.

So the conf is really **shared defaults + a thin user-override layer**. Moving it wholesale to `$HOME` as the only source would lose those defaults on a fresh checkout. The committed `.template` is what carries them.

Other references that hardcode the old paths and must move in lockstep:

- `deployment/README.md` names `deployment/deployed_artefacts.log` and `deployment.conf`.
- Root `README.md` lists `deployment.conf` in the layout tree.
- `.gitignore` ignores `deployment/deployed_artefacts.log` (becomes obsolete once the log leaves the tree).
- `CLAUDE.md` references `make uninstall` relying on the deployment log.

Prior-art scan (Tier 1) found only incidental hits — other tasks invoke `deployment.sh --global --dry-run` as an acceptance check; none addresses conf/log relocation. This work is novel.

## Approach

Relocate both files into a single hidden state directory in the user's home: **`~/.ai_asset_deploy/`**, containing:

- `~/.ai_asset_deploy/config` — the per-machine conf (replaces in-repo `deployment.conf`).
- `~/.ai_asset_deploy/deployed.log` — the uninstall manifest (replaces in-repo `deployed_artefacts.log`).

Grouping the two under one dot-dir keeps the home directory tidy and reads more naturally than a log sitting at the top level of `$HOME`.

Handle the two files according to what each one is:

- **Log → `~/.ai_asset_deploy/deployed.log`.** It is pure machine state and the cross-repo uninstall manifest, so it always lives in home. Create it there on first write when it is absent. This gives one machine-wide manifest, so `--uninstall` from any bundled copy of the script sees every artifact deployed on the machine.
- **Conf → `~/.ai_asset_deploy/config`** for the user's live config, with the committed `.template` in the repo as the read-only fallback so a fresh checkout deploys with the shared defaults.

Resolution precedence:

1. **Log** — read and write `~/.ai_asset_deploy/deployed.log`.
2. **Conf** — read `~/.ai_asset_deploy/config` when present; otherwise fall back to the bundled `.template`.

### The committed template

Ship `deployment/ai_asset_deploy.conf.template` (the `.template` suffix is an unmistakable "copy me, don't edit me live" signal). Its content mirrors the **original default conf** — the usage-comment header carried over verbatim, then every tool section present with `disallow:*legacy*` as the worked example, and **no Claude-specific rule**:

```text
# ai_asset_deploy config — per-tool deployment configuration
#
#   #tool                  Section heading — tool identifier (vscode, cursor, claude, codex, gemini, antigravity)
#   disallow:path          Local repo path relative to repo root (e.g. agents/check_spec_codex.md)
#                         Glob patterns supported (* matches within a segment, ** matches across segments)
#   replace:path VAR=value Force copied deployment for matching assets and replace $VAR$
#                         inside the deployed copy only. A trailing slash applies to a whole subtree.
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

#gemini
disallow:*legacy*

#antigravity
disallow:*legacy*
```

The template is the generic starting point. The `#claude disallow:**` rule (marketplace-served, skip symlinks) is **this user's local customization**, not a shared default — it belongs in the home conf, not the template.

### One-time migration of the current setup (required)

The point of this task is that the current working setup is **retained**, not reset. On the relocation:

1. **Copy the current live log into home.** `deployment/deployed_artefacts.log` (~16 KB of real entries on this machine) must be **copied to `~/.ai_asset_deploy/deployed.log`** so every already-deployed artifact stays uninstallable. Do this before removing it from the repo.
2. **Seed the home conf from the current live conf, not the template.** `~/.ai_asset_deploy/config` must be created from the *current* `deployment/deployment.conf` — which includes the `#claude disallow:**` rule as it stands today — so the user's actual behavior carries over unchanged. (The template, by contrast, ships without that rule.)
3. **Stop tracking the in-repo files.** `git rm` the tracked `deployment.conf`, remove the in-repo `deployed_artefacts.log`, commit the `.template`, and drop the now-obsolete `.gitignore` entry for the log (nothing left in the tree to ignore).

The script may automate the seeding on first run (if no home conf/log exists but the in-repo ones do, copy them up), or it can be a documented one-time manual step — but the end state for this machine is: home conf with the Claude rule present, home log carrying all current entries.

### Guardrails

- Keep the toolchain to Make + shell, per the CLAUDE.md authoring convention.
- Keep the conf a single flat robots.txt-style file: home replaces repo, bootstrapped from the template. (Template-base + home-override *layering* stays a deferred option — see below.)

When implementing, confirm with the user that the machine-wide log is the intended behavior: `--uninstall` from any bundled copy of the script will clean every artifact recorded in the shared manifest across all repos. This is the natural consequence of one home-level log and is almost certainly what is wanted; document it in `deployment/README.md` as the expected behavior.

### Explored but deferred alternatives

Considered and set aside for this task; revisit only if asked:

- **Two loose dotfiles** (`~/.ai_asset_deploy.conf` + `~/.ai_asset_deploy.log`). Workable; the single dot-dir groups the state more cleanly.
- **XDG base dirs** (`$XDG_CONFIG_HOME` / `$XDG_STATE_HOME`). Stronger on Linux, but heavier and split across two trees; the single dot-dir stays simpler.
- **Flag / env-var overrides** (`--config PATH` / `--log PATH`, `AI_ASSET_DEPLOY_CONF` / `AI_ASSET_DEPLOY_LOG`). Useful later to make the `tests/` harness hermetic and add explicit control; defer until a test or a use case calls for it.
- **Template + home-override layering.** Merge a committed base conf with home overrides. Defer in favor of the simpler "home replaces repo" model.

## Acceptance

- Conf and log resolve to `~/.ai_asset_deploy/config` and `~/.ai_asset_deploy/deployed.log`, with documented precedence (home → template fallback for conf only; log always home).
- `deployment.conf` and `deployed_artefacts.log` are no longer in the repo; a committed `deployment/ai_asset_deploy.conf.template` carries the generic defaults — every tool section with `disallow:*legacy*` and **no** Claude-specific rule.
- The current live log is **copied** to `~/.ai_asset_deploy/deployed.log` so the setup is retained: verify the pre-relocation entries are present and that `--uninstall` cleanly removes a previously-deployed artifact afterward.
- `~/.ai_asset_deploy/config` on this machine retains the `#claude disallow:**` rule exactly as the current `deployment.conf` has it — confirm a `--dry-run` still excludes Claude after relocation.
- A fresh checkout with no home conf falls back to the template and deploys with the generic defaults (`*legacy*` skipped for every tool, Claude **not** excluded) — confirm via `./deployment/deployment.sh --global --dry-run`.
- `deployment/README.md`, root `README.md`, and `.gitignore` updated to the new paths; no stale references to `deployment/deployed_artefacts.log` or in-repo `deployment.conf` remain.
- `./deployment/deployment.sh --global --dry-run` runs without error and shows the resolved `~/.ai_asset_deploy/` conf/log paths in its banner.
- Working tree is clean after a deploy (no `M deployment/deployment.conf`).
