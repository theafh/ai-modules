---
description: Move deployment.sh per-machine state (deploy log + user conf) out of the repo into $HOME, shipping shared defaults as a committed .template.
scope: deployment
created: 2026-06-02T16:58:04Z
updated: 2026-11-25T19:32:23Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
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

- The `DEPLOYED_ARTIFACTS_LOG` and `DEPLOYMENT_CONF` definitions (both off `SCRIPT_DIR`). Since 10 October 2026 an environment variable named `DEPLOYED_ARTIFACTS_LOG` overrides the log path, and `print_usage` documents it under `Environment:`.
- The log append + dedupe helpers `append_deployed_artifact_log` and `dedupe_deployed_artifact_log`; `trap dedupe_deployed_artifact_log EXIT` writes the log.
- `parse_deployment_conf`; tolerates a missing conf (`[[ -f "$DEPLOYMENT_CONF" ]] || return 0`).
- `uninstall_logged_artifacts` and `update_logged_artifacts`; both read the log, and uninstall also filters by scope since 2026-10-27.
- The script's own prose about those paths, each rewritten in place rather than supplemented: the header comment that says per-tool configuration "is loaded from deployment.conf", that `--uninstall` removes artifacts "from deployed_artefacts.log", that `--update` redeploys "every scope deployed_artefacts.log records", and that the script "Logs deployed artifacts to deployed_artefacts.log" (in `deployment/deployment.sh`); the `print_usage` `Environment:` text that says an unset override writes `deployment/deployed_artefacts.log` (in the same file); the header comment's closing sentence that a test deployment can "write inside its own scratch tree and leave the repo log untouched"; the two user-facing messages that name the conf file, the style-skip warning "[$name] no style:<name> in deployment.conf for $app_id" and the disallow notice "[$name] excluded for $app_id (deployment.conf)"; and the `Config:` banner line that echoes the conf path. Each passage states the new `~/.ai_asset_deploy/` conf and log paths (and the template fallback for the conf), and no in-repo path, no bare `deployed_artefacts.log` basename, and no claim of a repo log survives beside it.

The sibling task [bash 3.2 floor](archive/deployment_bash-32-floor.md) has shipped and rewrote the two associative arrays `parse_deployment_conf` fills into indexed arrays, so this task builds on that shipped shape rather than the one quoted here.

Current conf (`deployment/deployment.conf`) is **not purely machine state**. It carries shared defaults every checkout needs:

- `disallow:*legacy*` under each tool section, a shared default.
- `style:<name>` under `#claude`, naming the active output style the Claude deploy merges into that tool's settings.

So the conf is really **shared defaults plus whatever override layer a machine adds**. Moving it wholesale to `$HOME` as the only source would lose those defaults on a fresh checkout. The committed `.template` is what carries them.

The eval micro-deployment depends on both files. `tests/lib/micro_deploy.py` runs this script for every eval pass with `HOME` set to a scratch home and `DEPLOYED_ARTIFACTS_LOG` set to a log inside it, so a test deploy never writes the machine's log, and `tests/lib/test_micro_deploy.py` checks that the machine's log stays byte-identical across a micro-deployment. Each micro-deployment also reads the in-repo `deployment.conf`, whose `style:natural-language` line under `#claude` is what sets `outputStyle` when the `natural_language` harness deploys its style; the Claude arm of the style branch is the only reader of a `style:` line. Once the conf lives in home, a scratch `HOME` holds no conf, so the script falls back to the template, which carries no `style:` rule, and the style deploys without `outputStyle`.

Other references to the old state, grouped by what each one needs. Re-run `git grep -n -e 'deployed_artefacts' -e 'deployment\.conf' -- ':!tasks' ':!wiki/log.md' ':!CHANGELOG.md'` at implementation time and treat every file it returns as in scope, `deployment/deployment.sh` and the new template included; the path-hardcoding files move in lockstep, the instruction files below need only their prose kept true, and any further hit the selector returns joins the matching group:

- `deployment/README.md` names `deployment/deployed_artefacts.log` and `deployment.conf`.
- Root `README.md` lists `deployment.conf` in the layout tree, and names it again as the file that carries the active style.
- `.gitignore` ignores `deployment/deployed_artefacts.log` (becomes obsolete once the log leaves the tree).
- `tests/deployment/script_tests/run.sh`, `style_run.sh`, `update_run.sh`, and `description_round_trip_run.sh` copy the in-repo log aside or guard it as the real log, run the script against it, and restore it on exit, and `style_run.sh` reads its entries; every script the selector returns moves to a scratch log that `DEPLOYED_ARTIFACTS_LOG` names.
- `tests/lib/test_micro_deploy.py` guards the in-repo log as the machine's log through its `DEPLOY_LOG` constant.
- `tests/lib/micro_deploy.py` names `deployed_artefacts.log` only as the scratch log filename it passes through `DEPLOYED_ARTIFACTS_LOG`, so its log path needs no change; the conf seeding in `### Test deploys` still applies to it.
- `wiki/concepts/deployment-model.md` names both in-repo paths.
- Every standing repo instruction file describes `make uninstall` as removing deployed artefacts via the deployment log.

Prior-art scan (Tier 1) found only incidental hits: other tasks invoke `deployment.sh --global --dry-run` as an acceptance check, but none addresses conf/log relocation. This work is novel.

## Approach

Relocate both files into a single hidden state directory in the user's home: **`~/.ai_asset_deploy/`**, containing:

- `~/.ai_asset_deploy/config`: the per-machine conf (replaces in-repo `deployment.conf`).
- `~/.ai_asset_deploy/deployed.log`: the uninstall manifest (replaces in-repo `deployed_artefacts.log`).

Grouping the two under one dot-dir keeps the home directory tidy and reads more naturally than a log sitting at the top level of `$HOME`.

Handle the two files according to what each one is:

- **Log → `~/.ai_asset_deploy/deployed.log`.** It is pure machine state and the cross-repo uninstall manifest, so it lives in home, apart from a run that points `DEPLOYED_ARTIFACTS_LOG` elsewhere. Create it there on first write when it is absent. This gives one machine-wide manifest, so `--uninstall` and `--update` from any bundled copy of the script see every artifact deployed on the machine.
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
#   style:<name>           Active output-style name for that tool (read by the Claude arm only, which merges it as settings outputStyle)
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

**Ship order.** One live task consumes this conf and lands after this one: [the shadow-warning task](deployment_warn-shadowed-output-style.md) reads it through `merge_json_key "$DEPLOYMENT_CONF" …` in the Claude style arm.

### Validate the conf the script reads

The relocation turns the conf into a file a user edits by hand, so `parse_deployment_conf` reports a line it cannot use instead of dropping it. It warns, names the line, and continues with that line skipped, in two cases: a non-blank, non-comment line that is neither a `#tool` section heading nor a recognised directive, such as a misspelled `disalow:*legacy*`; and a recognised directive that appears above the first `#tool` section, where no tool owns it. Comment lines and section headings stay silent, so the file's own usage header raises nothing. A misspelled directive then surfaces as a warning rather than silently deploying the assets it meant to skip.

### One-time migration of the current setup (required)

The point of this task is that the current working setup is **retained**, not reset. On the relocation:

1. **Copy the current live log into home.** An existing installation's `deployment/deployed_artefacts.log`, carrying that installation's real entries, must be **copied to `~/.ai_asset_deploy/deployed.log`** so every already-deployed artifact stays uninstallable. Do this before removing it from the repo.
2. **Seed the home conf from the current live conf, not the template.** `~/.ai_asset_deploy/config` must be created from `deployment/deployment.conf` exactly as it stands at migration time, so the machine's actual behaviour carries over unchanged, including any rule the generic template does not ship.
3. **Stop tracking the in-repo files.** `git rm` the tracked `deployment.conf`, remove the in-repo `deployed_artefacts.log`, commit the `.template`, and drop the now-obsolete `.gitignore` entry for the log (nothing left in the tree to ignore).

All three steps land in one change, run by the implementer in the order listed: steps 1–2 copy the live log and conf into home while the in-repo files still exist in the working tree, and step 3 then removes them from the repo in that same change, leaving the tree at the state the Acceptance list records. The script ships no first-run seeding branch, because this checkout holds neither file after step 3, so such a branch could never fire here. The end state for an existing installation is: home conf carrying the live conf's content unchanged, home log carrying all current entries.

### Test deploys

Seed each scratch home before a run reads a conf from it: write `<scratch home>/.ai_asset_deploy/config` from the committed template, with a `style:<name>` line under `#claude` for the style that run deploys, if it deploys one. In `tests/lib/micro_deploy.py` that seeding runs before a micro-deployment, naming the style the pass's declaration names. In `tests/deployment/script_tests/style_run.sh`, seed `HOME_DIR` with `style:natural-language` before the style deploys, and run the closing `parse_deployment_conf` block under a scratch home seeded with a distinct style name (such as `style:scratch-only` under `#claude`), so the block proves it reads the seeded conf rather than the host's live one. The scratch `HOME` makes that file the conf the script reads, so the style deploy still sets `outputStyle`, and test deploys stop depending on the host's live conf. Point `DEPLOY_LOG` in `tests/lib/test_micro_deploy.py` at `~/.ai_asset_deploy/deployed.log` under the real home. In every `tests/deployment/script_tests/` script the Context selector returns — `run.sh`, `style_run.sh`, and `update_run.sh` today, plus `description_round_trip_run.sh`, whose real-log guard then reads the home log — replace the copy-aside of the in-repo log with a scratch log that `DEPLOYED_ARTIFACTS_LOG` names, and read entries from that log. Every invocation of `deployment.sh` in those files runs under a scratch `HOME` or with `DEPLOYED_ARTIFACTS_LOG` exported — the bare `--project-dir` deploys and `--uninstall` runs included — so no test run appends to or `sort -u`-rewrites the machine manifest at `~/.ai_asset_deploy/deployed.log`.

### Guardrails

- Keep the toolchain to Make + shell, per the repo rules' authoring convention.
- Keep the conf a single flat robots.txt-style file: home replaces repo, bootstrapped from the template. (Template-base + home-override *layering* stays a deferred option; see below.)

### Operator migration, recorded not run

The implementer delivered the code change without touching this machine's live state: `~/.ai_asset_deploy/` does not exist here, and the in-repo `deployment/deployment.conf` and `deployment/deployed_artefacts.log` stay on disk unchanged. Run this once, in order, to complete the one-time migration on an installation that still carries in-repo state:

```bash
mkdir -p ~/.ai_asset_deploy
cp deployment/deployment.conf ~/.ai_asset_deploy/config
cp deployment/deployed_artefacts.log ~/.ai_asset_deploy/deployed.log
git rm deployment/deployment.conf
rm deployment/deployed_artefacts.log
```

The first two copies retain the live config byte-for-byte and keep every already-deployed artifact uninstallable; the last two take the dead files out of the checkout. The migration and the uninstall behaviour are proven hermetically by the scratch-home scenarios in `tests/deployment/script_tests/run.sh` and `tests/lib/test_micro_deploy.py`.

### Open decision: should one uninstall reach every artefact on the machine?

`--uninstall` from any bundled copy of the script now cleans every artefact recorded in the shared manifest, across all repositories and scopes. The options:

- **Machine-wide (suggested default).** Keep the single home manifest as shipped, and `deployment/README.md` documents the behaviour. One log means one machine, and a scopeless run already covers every scope today, so the blast radius is a widening of the same rule.
- **Per-checkout manifests.** Restore a per-checkout log path so an uninstall reaches only what that checkout deployed. This gives up the cross-repo manifest the task exists to create and needs a new way to tell the copies apart.

It stays open because the task asks for the user's confirmation rather than a silent choice: the behaviour changes what a single uninstall run reaches on the user's machine, and no evidence in the repository settles how wide that reach should be. The suggested default is the shipped behaviour, so confirming it needs no code change; choosing per-checkout manifests does.

### Explored but deferred alternatives

Considered and set aside for this task; revisit only if asked:

- **Two loose dotfiles** (`~/.ai_asset_deploy.conf` + `~/.ai_asset_deploy.log`). Workable; the single dot-dir groups the state more cleanly.
- **XDG base dirs** (`$XDG_CONFIG_HOME` / `$XDG_STATE_HOME`). Stronger on Linux, but heavier and split across two trees; the single dot-dir stays simpler.
- **Further flag / env-var overrides** (`--config PATH` / `--log PATH`, a conf override variable). The log already has one, `DEPLOYED_ARTIFACTS_LOG`, which the eval micro-deployment brought in on 10 October 2026. A conf override stays deferred, because a scratch `HOME` already gives a test run its own home conf.
- **Template + home-override layering.** Merge a committed base conf with home overrides. Defer in favor of the simpler "home replaces repo" model.

## Acceptance

- Conf and log resolve to `~/.ai_asset_deploy/config` and `~/.ai_asset_deploy/deployed.log`, with documented precedence: the conf reads home, then the template; the log uses `DEPLOYED_ARTIFACTS_LOG` when it is set, and home otherwise.
- `deployment.conf` and `deployed_artefacts.log` are no longer in the repo; a committed `deployment/ai_asset_deploy.conf.template` carries the generic defaults: every tool section with `disallow:*legacy*` and **no** Claude-specific rule.
- The current live log is **copied** to `~/.ai_asset_deploy/deployed.log` so the setup is retained: verify the pre-relocation entries are present and that `--uninstall` cleanly removes a previously-deployed artifact afterward.
- `~/.ai_asset_deploy/config` on an installation that had a live `deployment.conf` reproduces that conf byte-for-byte at migration time; confirm a `--dry-run` produces the same per-tool exclusions and the same active style after relocation as before it.
- A fresh checkout with no home conf falls back to the template and deploys with the generic defaults (`*legacy*` skipped for every tool, Claude **not** excluded); confirm by running `HOME="$(mktemp -d)" ./deployment/deployment.sh --global --dry-run` against a scratch home that holds no `.ai_asset_deploy/`, so the template is the conf that run reads.
- `deployment/README.md`, root `README.md`, and `wiki/concepts/deployment-model.md` (edited through the wiki skill family) are updated to the new paths, `.gitignore` drops its now-obsolete `deployment/deployed_artefacts.log` entry, and none of them still names `deployment/deployed_artefacts.log` or the in-repo `deployment.conf`.
- `./deployment/deployment.sh --global --dry-run` runs without error and shows the resolved `~/.ai_asset_deploy/` conf/log paths in its banner; `./deployment/deployment.sh --help` and the script's header comment name the `~/.ai_asset_deploy/` conf and log paths in place of the in-repo ones, and neither passage still names `deployment.conf` or `deployed_artefacts.log`; the header's `DEPLOYED_ARTIFACTS_LOG` sentence describes a test deployment writing its own scratch log instead of leaving a repo log untouched, and `grep -nE '(warn|info) .*deployment\.conf' deployment/deployment.sh` returns nothing, so no user-facing message names the old conf file.
- A conf line the script cannot use draws a warning and the run continues: a misspelled `disalow:*legacy*` and a recognised directive placed above the first `#tool` section each print a warning naming the line, while the file's own comment header raises none, and a `tests/deployment/script_tests/run.sh` scenario stages both lines and pins the two warnings.
- `python3 tests/lib/test_micro_deploy.py` passes with `DEPLOY_LOG` naming `~/.ai_asset_deploy/deployed.log`, and its check that a Claude micro-deployment of `natural-language` sets `outputStyle` holds against a scratch home whose `.ai_asset_deploy/config` the helper seeded.
- `tests/deployment/script_tests/style_run.sh` passes: its Claude style deploy under the scratch `HOME` sets `outputStyle` to `natural-language` from the conf seeded there, and its closing `parse_deployment_conf` block, run under a scratch home seeded with a distinct style name, yields that name for Claude.
- `bash tests/deployment/run_all.sh` passes, and no script under `tests/deployment/script_tests/` names `deployment/deployed_artefacts.log` — `run.sh`, `style_run.sh`, `update_run.sh`, and `description_round_trip_run.sh` today — while each of those scripts reads the log from a scratch path that `DEPLOYED_ARTIFACTS_LOG` names.
- The test suite leaves the machine manifest untouched: `shasum -a 256 ~/.ai_asset_deploy/deployed.log` (or that file's continued absence) reads the same before and after `bash tests/deployment/run_all.sh`, so every script under `tests/deployment/script_tests/` sends the script's log writes to a scratch path instead of the live log.
- `git ls-files deployment/deployment.conf deployment/deployed_artefacts.log` returns nothing, so neither file is tracked, and the deploy log and the user conf both live under `$HOME` (`~/.ai_asset_deploy/deployed.log` and `~/.ai_asset_deploy/config`).
