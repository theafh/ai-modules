---
description: "Give agent_spinner orchestrator scratch a named, git-hidden home inside the run directory, and make status and close name stray untracked paths."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T22:33:19Z
updated: 2026-11-18T13:32:24Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Give agent_spinner scratch a named home inside the run directory

## Goal

An orchestrator that needs somewhere to keep intermediate files has a named, git-hidden home, `.agent_spinner/scratch/`, created by `init`. Every doctrine passage that tells the orchestrator where scratch goes names that path. A run that leaves scratch in the working root surfaces the stray path in `status` with the home named, and `close` names the same home when it refuses the path.

## Context

Everything here lives under `plugins/ai_dev/skills/agent_spinner/`.

- **The doctrine names no place.** `SKILL.md`'s writer rule says "Keep scratch files in the run directory" without naming a subdirectory, and `references/run-protocol.md`'s `## Run directory` section lists the layout and says "Its own `.gitignore` hides it from git" but lists no scratch area. `cmd_init` in `scripts/run_ledger.py` creates `access`, `kinds`, `items`, `briefs`, `returns`, `baseline`, `snapshots`, `diffs`, `gates`, `outbound`, `controls`, and `history`, none of them scratch. An orchestrator holding reviewer returns and per-source registration fragments therefore has to invent a path.
- **The 2026-11-14 run invented one in the working root.** That run kept its reviewer returns and per-source registration fragments under a `.agent_review/` directory at the repository root. The directory was untracked, and the user had to add it to the repository's `.gitignore` after the fact. `close` condition 5 would have caught it, but `status` printed no stray-path line while the run was open, so the first report of it was the user's.
- **The guard exists only at `close`.** `close_open_items` in `scripts/run_ledger.py` builds `current` from `git_status(led.root)` minus paths under the run directory, subtracts the recorded changes and the baseline status, and reports every remainder as "condition 5: tree guard sees <path> with no disposition". The message names no remedy. `cmd_status` prints run state, rows, gates, the repair list, stamped paths, packets, blind rows, resume data, and intervals, and prints no tree-guard line at all.

## Approach

1. Add `"scratch"` to the subdirectory tuple in `cmd_init`, so `init` creates `.agent_spinner/scratch/` beside the existing directories. The run directory's own `.gitignore` already hides it from git.
2. Rewrite in place each passage that sends the orchestrator to scratch so it names `.agent_spinner/scratch/`: `SKILL.md`'s "Keep scratch files in the run directory" sentence, keeping the rule in its one canonical place, and `references/recipes/prose-sweep.md`'s Scout step, whose "plant a known target instance in a scratch file under the run directory" becomes a scratch file under `.agent_spinner/scratch/`.
3. Rewrite in place the directory list in `references/run-protocol.md`'s `## Run directory` section so it names `.agent_spinner/scratch/` as the orchestrator scratch area beside `briefs/`, `returns/`, `snapshots/`, and the other subdirectories. The rewrite edits that list only and leaves its other entries as they stand.
4. Add a `stray paths:` block to `cmd_status` that lists working-root paths `git_status` reports as untracked (`??`) and that lie outside the run directory, outside the paths the run recorded in `changes`, and outside the baseline status file — the same recorded-change subtraction `close_open_items` applies for condition 5, so `status` does not report a recorded deliverable as stray. When the block is non-empty, print `.agent_spinner/scratch/` as the home for orchestrator scratch. Print `none` when the block is empty, matching the other `status` blocks. Rewrite in place the two published enumerations of what `status` prints so each names the new block: the `status` argparse `description` in `scripts/run_ledger.py` and the `### status` section of `references/run-protocol.md`. In `tests/agent_spinner/script_tests/ledger_run.sh`, extend the existing `status --help names the blind rows listing` scenario so it also asserts that the help output names the stray paths block.
5. Append the same home to `close_open_items`'s condition 5 message for an undisposed path, so a refusal names where the scratch belongs.

**Out of scope:** a new `scratch` ledger verb, since a directory the orchestrator writes directly needs no access path through the ledger; and deleting `scratch/` at `close`, since the run directory is discarded as a whole; and helper scratch directories, since this task names the orchestrator's own intermediate-file home and each helper keeps the scratch its own brief grants under the run directory (`references/recipes/prose-sweep.md`'s writer brief and `references/recipes/option-panel.md`'s Design phase).

## Acceptance

- A `ledger_run.sh` scenario runs `init` and asserts that `.agent_spinner/scratch` exists as a directory.
- A `ledger_run.sh` scenario runs `init`, writes a stray untracked file in the working root, runs `status`, and asserts that its output carries a `stray paths:` block naming both that file and `.agent_spinner/scratch/`; a second `ledger_run.sh` scenario runs `init` with no stray path and asserts that the block prints `none`.
- A `ledger_run.sh` scenario records a new untracked working-root file with `diff` and leaves a second untracked file unrecorded; `status` lists the unrecorded file in its `stray paths:` block and does not list the recorded one.
- A `ledger_run.sh` scenario writes the same stray untracked file and runs `close`; the command exits 3 and its refusal names `.agent_spinner/scratch/` alongside condition 5.
- A grep of `references/run-protocol.md`'s `### status` section finds `stray paths` named among the blocks it lists.
- `ledger_run.sh`'s `status --help` scenario asserts that the help output names the stray paths block beside the blind rows listing.
- A grep of `plugins/ai_dev/skills/agent_spinner/` for `scratch` finds `.agent_spinner/scratch/` named in `SKILL.md`, in `references/run-protocol.md`, and in `references/recipes/prose-sweep.md`'s Scout step, and finds no orchestrator-facing hit that locates scratch at the run directory without naming the home apart from the helper-scratch passages the `**Out of scope:**` block records; the old sentence "Keep scratch files in the run directory" and the old Scout phrase "plant a known target instance in a scratch file under the run directory" no longer appear as written.
- A `ledger_run.sh` scenario runs `init`, writes a file into `.agent_spinner/scratch/`, and asserts that `git status --porcelain` in the working root reports no path under `.agent_spinner/`.
