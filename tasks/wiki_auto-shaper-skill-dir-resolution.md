---
description: Make the wiki_auto_shaper agent resolve its own skill directory ($WIKI_SKILL) before any scripts/ call, so cold-start runs stop failing with exit 127.
scope: plugins/knowledge_management
created: 2026-05-28T20:05:29
updated: 2026-06-13T01:47:36
status: open
---

# Resolve `$WIKI_SKILL` before the auto-shaper runs any bundled script

## Goal

The `wiki_auto_shaper` agent reliably locates its own skill directory at the very start of a run and exports it as `$WIKI_SKILL` before invoking any bundled script. Cold-start runs stop wasting turns hunting for `discover_wiki.sh` / `lint.py` and stop failing with "No such file or directory" (exit 127).

## Context

[agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) references `$WIKI_SKILL` more than a dozen times to locate its bundled assets — e.g. `$WIKI_SKILL/SKILL.md`, `$WIKI_SKILL/scripts/`, the canonical templates, and `python3 $WIKI_SKILL/scripts/lint.py "$WIKI"`. But **`$WIKI_SKILL` is never defined**. Nothing in the agent resolves it before use.

Worse, the `<discover_wiki>` step runs the discovery script with a **bare relative path** — `WIKI=$(scripts/discover_wiki.sh --check)` — which only works if the process happens to be sitting in the skill's `scripts/` directory. On a cold start the working directory is the target repo, so the relative path misses, the script exits 127, and the agent burns several turns probing the filesystem (`find /`, plugin-cache guesses, `ls -d`) before stumbling onto the real location. This happens on every cold auto-shaper run.

The agent is deployed through several equal paths (marketplace, `make deploy` symlinks into user config dirs, `--project-dir` symlinks, in-place from a checkout), so the skill directory location varies. The resolution must try the realistic locations rather than hard-coding one.

Files involved:

- [plugins/knowledge_management/agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — `<orient>` / `<discover_wiki>` and every `$WIKI_SKILL` reference.

## Approach

1. **Add a `<resolve_skill_dir>` step at the very top of `<orient>`**, before `<discover_wiki>` and before any `scripts/` invocation. It resolves the wiki skill directory and exports `$WIKI_SKILL`. Resolution order should cover the deployment-agnostic reality:
   - The directory of the agent/skill bundle if the runtime exposes it.
   - A deployed location under the user config dir (e.g. a `skills/wiki` symlink target).
   - The plugin cache location.
   - A bounded `find` from a sensible root as a last resort (never an unbounded `find /`).
   Validate the candidate by checking for `$WIKI_SKILL/SKILL.md` and `$WIKI_SKILL/scripts/lint.py`; only accept a directory that contains them.
2. **Replace the bare-relative discovery call.** Change `scripts/discover_wiki.sh` in `<discover_wiki>` to `"$WIKI_SKILL/scripts/discover_wiki.sh"` so it works regardless of CWD. Audit the whole agent for any other bare `scripts/...` reference and qualify it with `$WIKI_SKILL`.
3. **State the failure mode explicitly** in the new step: if `$WIKI_SKILL` cannot be resolved, stop and report rather than guessing — a wrong skill dir silently lints against stale templates.
4. Coordinate with [wiki_discovery-from-inside-wiki-dir.md](archive/wiki_discovery-from-inside-wiki-dir.md) (implemented): discovery now succeeds even when the agent's CWD is the wiki itself, but `$WIKI_SKILL` (the *skill* dir, distinct from the *wiki* dir) still has to be resolved separately — the two are unrelated paths.

## Acceptance

- A cold-start auto-shaper run (CWD = a target repo, no prior skill-dir knowledge) resolves `$WIKI_SKILL` in its first orientation step and runs `discover_wiki.sh` / `lint.py` without an exit-127 / "No such file" detour.
- No bare relative `scripts/...` invocations remain in the agent; all are `$WIKI_SKILL/scripts/...`.
- The skill-dir resolution validates `SKILL.md` + `scripts/lint.py` presence and halts with a clear message if it cannot find a valid bundle.
