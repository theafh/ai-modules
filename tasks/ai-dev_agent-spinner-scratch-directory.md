---
description: "Give agent_spinner orchestrator scratch a named, git-hidden home inside the run directory, and make status and close name stray untracked paths."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T22:33:19Z
updated: 2026-11-14T22:33:19Z
status: open
reported-by: Andreas Hoffmann
---

# Give agent_spinner scratch a named home inside the run directory

## Goal

An orchestrator that needs somewhere to keep intermediate files has a named, git-hidden home, `.agent_spinner/scratch/`, created by `init`. Both doctrine passages that tell the orchestrator where scratch goes name that path. A run that leaves scratch in the working root surfaces the stray path in `status` with the home named, and `close` names the same home when it refuses the path.

## Context

Everything here lives under `plugins/ai_dev/skills/agent_spinner/`.

- **The doctrine names no place.** `SKILL.md`'s writer rule says "Keep scratch files in the run directory" without naming a subdirectory, and `references/run-protocol.md`'s `## Run directory` section lists the layout and says "Its own `.gitignore` hides it from git" but lists no scratch area. `cmd_init` in `scripts/run_ledger.py` creates `access`, `kinds`, `items`, `briefs`, `returns`, `baseline`, `snapshots`, `diffs`, `gates`, `outbound`, `controls`, and `history`, none of them scratch. An orchestrator holding reviewer returns and per-source registration fragments therefore has to invent a path.
- **The 2026-11-14 run invented one in the working root.** That run kept its reviewer returns and per-source registration fragments under a `.agent_review/` directory at the repository root. The directory was untracked, and the user had to add it to the repository's `.gitignore` after the fact. `close` condition 5 would have caught it, but `status` printed no stray-path line while the run was open, so the first report of it was the user's.
- **The guard exists only at `close`.** `close_open_items` in `scripts/run_ledger.py` builds `current` from `git_status(led.root)` minus paths under the run directory, subtracts the recorded changes and the baseline status, and reports every remainder as "condition 5: tree guard sees <path> with no disposition". The message names no remedy. `cmd_status` prints run state, rows, gates, the repair list, stamped paths, packets, blind rows, resume data, and intervals, and prints no tree-guard line at all.

## Approach

1. Add `"scratch"` to the subdirectory tuple in `cmd_init`, so `init` creates `.agent_spinner/scratch/` beside the existing directories. The run directory's own `.gitignore` already hides it from git.
2. Rewrite in place `SKILL.md`'s "Keep scratch files in the run directory" sentence so it names `.agent_spinner/scratch/`, keeping the rule in its one canonical place.
3. Add `scratch/` to the layout list in `references/run-protocol.md`'s `## Run directory` section, so the documented directory set matches what `init` creates.
4. Add a `stray paths:` block to `cmd_status` that lists working-root paths `git_status` reports as untracked (`??`) and that lie outside the run directory and outside the baseline status file. When the block is non-empty, print `.agent_spinner/scratch/` as the home for orchestrator scratch. Print `none` when the block is empty, matching the other `status` blocks.
5. Append the same home to `close_open_items`'s condition 5 message for an undisposed path, so a refusal names where the scratch belongs.

**Out of scope:** a new `scratch` ledger verb, since a directory the orchestrator writes directly needs no access path through the ledger; and deleting `scratch/` at `close`, since the run directory is discarded as a whole.

## Acceptance

- A `ledger_run.sh` scenario runs `init` and asserts that `.agent_spinner/scratch` exists as a directory.
- A `ledger_run.sh` scenario runs `init`, writes a stray untracked file in the working root, runs `status`, and asserts that its output carries a `stray paths:` block naming both that file and `.agent_spinner/scratch/`.
- A `ledger_run.sh` scenario writes the same stray untracked file and runs `close`; the command exits 3 and its refusal names `.agent_spinner/scratch/` alongside condition 5.
- A grep of `SKILL.md` and `references/run-protocol.md` finds `.agent_spinner/scratch/` in both, and the old sentence "Keep scratch files in the run directory" no longer appears as written.
