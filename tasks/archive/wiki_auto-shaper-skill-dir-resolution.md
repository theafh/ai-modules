---
description: Make auto_shaper_wiki resolve $WIKI_SKILL and $WIKI as run-local paths before bundled tool calls, avoiding stale environment or hook state.
scope: plugins/knowledge_management
created: 2026-05-28T20:05:29
updated: 2026-06-15T23:15:13
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
---

# Resolve auto-shaper runtime paths locally

## Goal

The `auto_shaper_wiki` agent resolves both runtime paths it needs at the start of every audit and uses those paths locally for bundled tool calls:

- `$WIKI_SKILL` is the installed wiki skill bundle that contains `SKILL.md`, `scripts/`, and `references/`.
- `$WIKI` is the target wiki selected for the current repository/session by the wiki discovery script.

Cold-start runs stop wasting turns hunting for `discover_wiki.sh` / `lint.py` and stop failing with "No such file or directory" (exit 127). The agent remains portable across Codex, Claude, macOS, Linux, sandboxed runs, and different repository sessions by treating these values as run-local orientation state rather than durable environment configuration.

## Context

[agents/auto_shaper_wiki.md](../../plugins/knowledge_management/agents/auto_shaper_wiki.md) references `$WIKI_SKILL` more than a dozen times to locate its bundled assets: `$WIKI_SKILL/SKILL.md`, `$WIKI_SKILL/scripts/`, the canonical templates, and `python3 $WIKI_SKILL/scripts/lint.py "$WIKI"`. But `$WIKI_SKILL` is never defined, so nothing in the agent establishes the location of the installed wiki skill bundle before use.

The `<discover_wiki>` step also runs the discovery script with a bare relative path: `WIKI=$(scripts/discover_wiki.sh --check)`. That only works when the process happens to be sitting in the wiki skill directory. On a cold start the working directory is normally the target repo, so the relative path misses, the script exits 127, and the agent spends turns probing the filesystem before finding the real bundle.

The two variables point at different things and must be resolved independently. `$WIKI_SKILL` is a tool bundle path. `$WIKI` is a content location selected from the current working directory by `discover_wiki.sh`. A new session, a different repo, or a different current working directory can legitimately change `$WIKI`; a plugin update, symlinked deployment, or local checkout can legitimately change `$WIKI_SKILL`.

Harness portability decision: keep both values run-local. Use shell variables inside the command block that needs them, or restate the resolved absolute paths in the agent's orientation state. Avoid user-level environment variables, session-start hooks, plugin-wide config, or cross-session caches for these paths. Durable state risks stale paths when the user switches repos, worktrees, plugin versions, or harnesses. Hooks are also provider-specific and trust-gated, so they are the wrong dependency for making this agent's first orientation step reliable.

Files involved:

- [plugins/knowledge_management/agents/auto_shaper_wiki.md](../../plugins/knowledge_management/agents/auto_shaper_wiki.md) — `<orient>` / `<discover_wiki>` and every `$WIKI_SKILL` reference.

## Approach

1. Add a `<resolve_runtime_paths>` step at the top of `<orient>`, before `<discover_wiki>` and before every bundled script invocation. It establishes run-local `$WIKI_SKILL` first, then derives run-local `$WIKI` by invoking the discovery script from that skill bundle.
2. Resolve `$WIKI_SKILL` from documented or observable bundle locations rather than from the target repo CWD. Use this resolution order:
   - The directory of the active agent/skill bundle when the harness exposes it in the loaded artefact path.
   - A sibling wiki skill directory in the same installed plugin bundle as `agents/auto_shaper_wiki.md`, when running from a plugin checkout or plugin cache.
   - A deployed user skill location such as `~/.codex/skills/wiki`, following symlinks when present.
   - A bounded search under the user's agent configuration roots and the current repo checkout as a last resort. Keep the search bounded; never run an unbounded `find /`.
3. Validate every `$WIKI_SKILL` candidate before accepting it. A valid candidate contains `SKILL.md`, `scripts/discover_wiki.sh`, `scripts/lint.py`, and `references/template_schema.md`. If no valid candidate is found, stop with a clear message that the wiki skill bundle could not be resolved.
4. Resolve `$WIKI` only after `$WIKI_SKILL` is valid, by running `"$WIKI_SKILL/scripts/discover_wiki.sh" --check` from the audit's current working directory. Preserve the existing `discover_wiki.sh` exit-code behavior: an unscaffolded selected path stops the audit, and an ambiguous path list is presented to the user for selection.
5. Use both values as run-local state. Prefer same-shell command blocks or explicit absolute paths over durable `export`. If a child process in the same shell block needs the values, exporting inside that block is acceptable; the agent instructions must not rely on exported values surviving across future tool calls, sessions, repos, or harnesses.
6. Replace bare script calls in the agent's command instructions. `scripts/discover_wiki.sh`, `python3 scripts/lint.py`, and other bundled wiki helper invocations become `"$WIKI_SKILL/scripts/discover_wiki.sh"`, `python3 "$WIKI_SKILL/scripts/lint.py" "$WIKI"`, and equivalent quoted absolute paths.
7. Keep `$WIKI` and `$WIKI_SKILL` separate in the prose. `$WIKI_SKILL` locates the published skill assets. `$WIKI` locates the user's current wiki content. Coordinate with [wiki_discovery-from-inside-wiki-dir.md](wiki_discovery-from-inside-wiki-dir.md) (implemented): that task improved wiki-content discovery, while this task fixes skill-bundle discovery.

## Acceptance

- A cold-start auto-shaper run from a target repo with no prior runtime path knowledge resolves `$WIKI_SKILL` first, resolves `$WIKI` through `"$WIKI_SKILL/scripts/discover_wiki.sh" --check`, and runs `discover_wiki.sh` / `lint.py` without an exit-127 / "No such file" detour.
- The agent document states that `$WIKI_SKILL` and `$WIKI` are run-local orientation state and does not instruct users or agents to persist them through user-level environment variables, startup hooks, plugin config, or cross-session caches.
- The `$WIKI_SKILL` resolution validates `SKILL.md`, `scripts/discover_wiki.sh`, `scripts/lint.py`, and `references/template_schema.md`, then halts with a clear message if no valid bundle can be found.
- No command instruction in the agent invokes wiki skill helpers through bare relative `scripts/...`; helper calls use quoted `$WIKI_SKILL/scripts/...` paths.
- The wiki discovery ambiguity behavior remains intact: when `discover_wiki.sh` exits 2, the agent still presents candidates to the user rather than silently adopting a parent wiki.
