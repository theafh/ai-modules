---
description: State once in the wiki hub that a chosen AVAILABLE candidate sets $WIKI to <level>/wiki, route every pick, adoption, init, and handoff site through it, and prove it in layer 2.
scope: plugins/knowledge_management
created: 2026-10-01T16:28:06Z
updated: 2026-10-03T15:41:17Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Set `$WIKI` to `<level>/wiki` for a chosen `AVAILABLE` candidate

## Goal

When wiki discovery exits 2 and a candidate is chosen, one rule in the hub decides the wiki path. An `EXISTING:` pick names the wiki itself, so `$WIKI` is that path. An `AVAILABLE:` pick names the level that will hold a new wiki, so `$WIKI` is `<level>/wiki`, and `init_wiki.sh` scaffolds it there. Every place that sets `$WIKI` from a pick follows this rule: the user's choice, an adoption the user named in the request, the init step, the positional handoff to bundled tools, and the `auto_shaper_wiki` agent's discovery step. An agent that initializes a wiki after an ambiguous discovery then scaffolds at `<level>/wiki` and leaves the level directory itself untouched.

This task delivers the general rule, with one layer-2 run as its motivating case. On 2026-10-01, one of seven passes of scenario L2-4 scaffolded `SCHEMA.md`, `index.md`, `log.md`, and the page tree directly into the project directory `proj` instead of `proj/wiki`. Later discovery cannot find a wiki placed like that, because the wiki predicate requires `wiki` in the directory's basename.

## Context

The hub is [the wiki skill](../../plugins/knowledge_management/skills/wiki/SKILL.md). When `discover_wiki.sh` exits 2, each `AVAILABLE:` candidate names a directory level with no wiki yet, and each `EXISTING:` candidate names a wiki. The hub never states which wiki path an `AVAILABLE:` pick settles. Several passages read the chosen candidate itself as the wiki path:

- The chosen-path handoff paragraph in `<discover_wiki>` says a caller hands back the candidate the user chose, "an `AVAILABLE:` level included". Given that level, `discover_wiki.sh` prints it and exits 0, and `<run_discovery>` adopts an exit-0 path as `$WIKI`.
- The `AVAILABLE` bullet in `<present_candidates>` says selecting the level "creates one there via `init_wiki.sh`".
- `<proceed_with_operation>` scaffolds "if the chosen path needs it" and then proceeds against `$WIKI`, without saying how `$WIKI` follows from the pick.
- `<adopt_when_user_named_the_path>` says to "adopt that path without prompting".
- The init step in `<initializing_a_new_wiki>` runs `init_wiki.sh "$WIKI"` "against the chosen path".

The `<level>/wiki` convention is already settled. [The name-and-marker predicate task](wiki_discovery-from-inside-wiki-dir.md) kept creation exact-name, so an available candidate means a wiki created at `<level>/wiki`. Auto-resolution follows the same convention when it prints `$HOME/wiki`. The convention never reached the hub's flow text.

The handoff wording comes from [the choice-handoff task](wiki_discovery-choice-handoff-and-parity.md). It gave `discover_wiki.sh` a positional path that answers for any existing directory without the wiki predicate, mirroring `lint.py`, and it described the use as handing back an `AVAILABLE:` level. The positional behavior stays correct for a scaffolded `<level>/wiki`, so only the description of what gets handed back is wrong. The same description sits in the script's header comment, its `--help` text, and the comment above its positional-mode branch. The label of layer-1 scenario `d22` also calls a positional non-wiki path an "AVAILABLE choice". The docstring of `discover_wiki` in `lint.py` speaks of "a path the user chose" and stays as it is.

The [auto_shaper_wiki agent](../../plugins/knowledge_management/agents/auto_shaper_wiki.md) sets `$WIKI` "to the chosen path itself" in its `<discover_wiki>` step and says this mirrors the hub's `<proceed_with_operation>`. The step stops on an `AVAILABLE:` pick without scaffolding, so its behavior is safe today, but its mirror claim breaks once the hub states the rule. `wiki_import` and `wiki_wrapup` resolve `$WIKI` through the hub's discovery flow, so the hub rule reaches them unedited. `wiki_fix` delegates discovery to the agent.

The hub's `<output_contract>` cites `<present_candidates>` and `<adopt_when_user_named_the_path>`. Its layer-1 checker `hub_output_contract.py` runs as scenario `a3`. It fails when the contract shares a six-word run with a cited block, or when a cited block's wording appears twice in the hub.

Scenario L2-4 stages a bare `HOME/proj` through `stage_L2-4` in `tests/wiki/layer2/setup_scenarios.sh`, and discovery there exits 2 with two `AVAILABLE:` candidates. L2-4 cannot prove the rule, because its extra constraints tell the worker to "scaffold the wiki at <CWD>/wiki". The prompt builder shows the worker each scenario's `id`, `name`, `user_request`, and `extra_constraints`, plus a generic `init_wiki.sh <target>` line. A scenario whose shown fields carry no target leaves the init target to the hub.

## Approach

1. **State the rule once in `<proceed_with_operation>`.** Rewrite the block in place so it sets `$WIKI` from the chosen path before scaffolding. An `EXISTING:` path is the wiki, so `$WIKI` is that path. An `AVAILABLE:` path is the level that will hold the new wiki, so `$WIKI` is `<chosen path>/wiki`, and `init_wiki.sh "$WIKI"` scaffolds it. The operation then proceeds against `$WIKI`. "Chosen path" keeps meaning the candidate as discovery printed it, because `<offer_no_wiki_markers>` measures its marker range from that candidate.
2. **Route the other hub sites through the rule.** Rewrite each passage below in place so it cites `<proceed_with_operation>` for how `$WIKI` follows from a pick.
   - The `AVAILABLE` bullet in `<present_candidates>` tells the user that the pick creates the wiki at `<level>/wiki`.
   - `<adopt_when_user_named_the_path>` sets `$WIKI` from an adopted candidate the way `<proceed_with_operation>` does.
   - The init step in `<initializing_a_new_wiki>` runs against `$WIKI` as `<proceed_with_operation>` sets it.
   - The chosen-path handoff paragraph in `<discover_wiki>` hands back the `$WIKI` a pick settles. For an `AVAILABLE:` pick that path exists only after `init_wiki.sh` scaffolds it, and a positional call before then exits 1.
3. **Align the agent.** Rewrite the sentence in the agent's `<discover_wiki>` step that sets `$WIKI` "to the chosen path itself", so it sets `$WIKI` the way the hub's `<proceed_with_operation>` does. The step keeps its `.no_wiki` marker offer and keeps stopping on an `AVAILABLE:` pick.
4. **Align the script's documentation.** In [discover_wiki.sh](../../plugins/knowledge_management/skills/wiki/scripts/discover_wiki.sh), rewrite the "Chosen-path handoff" paragraph of the header comment, the matching `--help` paragraph, and the comment above the positional-mode branch. Each describes handing back the wiki path a pick settles, which for an `AVAILABLE:` pick is the level's `wiki/` child once scaffolded. In `tests/wiki/layer1/run.sh`, rename the `d22` scenario label so it describes a positional non-wiki path without calling it an `AVAILABLE` choice, and keep its function body.
5. **Add a discriminating layer-2 scenario.** Add one `L2-*` scenario to `tests/wiki/layer2/evals.json`. Stage it with its own function in `setup_scenarios.sh` that mirrors `stage_L2-4`, and list it in `ALL_SCENARIOS`. The user request asks to initialize a wiki for the project and names the working-directory candidate as the pick. The fields the worker sees name no init target, so the hub's rule alone must supply `<level>/wiki`. The scenario asserts these facts:
   - `init_target` ends with `<scenario id>/HOME/proj/wiki`.
   - `SCHEMA.md`, `index.md`, and `log.md` exist under `HOME/proj/wiki`.
   - `HOME/proj/SCHEMA.md` does not exist.
   - The sandbox-escape and real-home-wiki guards hold, as in every `L2-*` scenario.
6. **Measure baseline-first.** Run the new scenario against the current hub text before the rule and routing rewrites land, then against the rewritten hub. Use five passes per side through the runner's `--passes` override, since the harness default is two.

**Out of scope:**

- Changing the candidate line format. `AVAILABLE:<level>` keeps naming the level, which the `.no_wiki` marker offer and user-named adoption match against.
- Changing what the positional path argument of `discover_wiki.sh` or `lint.py` accepts.
- Handling an `AVAILABLE:` level whose `wiki/` child already exists as a non-wiki directory, which keeps the behavior `init_wiki.sh` gives it today.

## Acceptance

1. `<proceed_with_operation>` in the hub states that an `EXISTING:` pick sets `$WIKI` to the chosen path, and that an `AVAILABLE:` pick sets `$WIKI` to `<chosen path>/wiki`, which `init_wiki.sh` scaffolds.
2. `<present_candidates>`, `<adopt_when_user_named_the_path>`, `<initializing_a_new_wiki>`, and the chosen-path handoff paragraph in `<discover_wiki>` each cite `<proceed_with_operation>`. The `AVAILABLE` bullet in `<present_candidates>` states that the pick creates the wiki at `<level>/wiki`. Within the hub, the mapping from pick to `$WIKI` is stated only in `<proceed_with_operation>`, apart from that bullet's user-facing `<level>/wiki` consequence. The chosen-path handoff paragraph in `<discover_wiki>` states the hand-back rule **Route the other hub sites through the rule** already names: the caller hands back the `$WIKI` `<proceed_with_operation>` settles, and for an `AVAILABLE:` pick that path exists only after `init_wiki.sh` scaffolds it (a positional call before then exits 1).
3. The stale wording is gone from the plugin. This search matches today and returns nothing after the rewrites:

   ```bash
   rg -n -U 'level included|AVAILABLE: level the user chose|candidate the\s+user picked|creates one\s+there|against the chosen path' plugins/knowledge_management
   ```

4. The header comment's "Chosen-path handoff" paragraph, the matching `--help` paragraph, and the comment above the positional-mode branch in `discover_wiki.sh` each say that for an `AVAILABLE:` pick the caller hands back the level's `wiki/` child once scaffolded.
5. The agent's `<discover_wiki>` step cites the hub's `<proceed_with_operation>` for `$WIKI`, still offers `.no_wiki` markers, and still stops on an `AVAILABLE:` pick. This search returns nothing:

   ```bash
   rg -n -F 'set `$WIKI` to the chosen path itself' plugins/knowledge_management/agents/auto_shaper_wiki.md
   ```

6. The `<offer_no_wiki_markers>` block and the `d22_positional_non_wiki_path` function body are byte-identical to their current state, and `grep -n '^scenario d22' tests/wiki/layer1/run.sh` prints a label without `AVAILABLE`.
7. `tests/wiki/layer2/evals.json` holds the new scenario with the assertions **Add a discriminating layer-2 scenario** lists, and `setup_scenarios.sh` stages it and lists it in `ALL_SCENARIOS`. Its `user_request` names the working-directory candidate as the pick. Its `name`, `user_request`, and `extra_constraints` name no init target, and none of them contains `/wiki`.
8. Both sides of the baseline-first measurement are recorded in their runs' `grading_summary.json` and `benchmark.json` under `tests/wiki/layer2/workspace/`, over a fixed five-pass denominator per side. The change counts as working when the rewrite side reaches 5/5. When the rewrite side scores below 5/5, or the baseline side also reaches 5/5 so the scenario shows no discrimination, report both rates with each failing pass's `init_target` and diverging assertions. Leave the disposition to the user rather than re-running for a better draw.
