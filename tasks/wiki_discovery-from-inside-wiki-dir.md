---
description: Fix wiki discovery so running from inside the wiki root resolves cleanly instead of "undecided", and correct lint.py's wrong --wiki-path hint.
scope: plugins/knowledge_management
created: 2026-05-28T20:06:23
updated: 2026-05-28T20:07:08
status: open
---

# Resolve the wiki when CWD is the wiki dir; fix the wrong `--wiki-path` hint

## Goal

When a user or agent runs the linter (or the discovery script) from *inside* the wiki directory itself, discovery resolves to that wiki silently instead of failing with "wiki location is undecided". The genuine-ambiguity path (a real choice between distinct candidate wikis) is preserved exactly as today. Separately, `lint.py`'s undecided-error message and docstrings stop telling the caller to pass a flag that does not exist.

## Context

Both `scripts/discover_wiki.sh` and the mirrored resolver in `scripts/lint.py` walk *up* from the current working directory looking for a child `wiki/` directory. When CWD is already the wiki root (e.g. `<proj>/wiki`), the walk produces two candidates that resolve to the **same** path:

- Level `<proj>/wiki`: no child `<proj>/wiki/wiki` exists → recorded as an `available` creation candidate.
- Level `<proj>` (parent): child `<proj>/wiki` exists → recorded as the `existing` wiki, walk stops.

The resolver only auto-resolves when `candidates[0]` is `existing`. Here index 0 is the `available` entry, so it falls through to the "undecided" exit even though both candidates point at one directory — a false ambiguity. The agent's learned workaround is to `cd` to the parent and re-run, costing turns on every invocation made from inside a wiki.

Two coupled defects compound it, both in [skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py):

1. **Wrong remediation hint.** The undecided exit message (around line 109) and the module docstrings (around lines 19 and 56) instruct the caller to "pass an explicit `--wiki-path`". `argparse` defines only a *positional* `wiki_path` argument and `--quiet` (around lines 1199-1204); there is no `--wiki-path` option. A caller that follows the hint gets `unrecognized arguments: --wiki-path` and must retry with the positional form.
2. **Ambiguity conflated with lint failure.** `lint.py`'s resolver raises via `sys.exit(<string>)`, which exits with code 1 — the same family of exit code used for "lint found blocking issues". Callers running `lint.py --quiet` as the normal blocking-only check (documented at [skills/wiki/SKILL.md:639](../plugins/knowledge_management/skills/wiki/SKILL.md)) cannot tell a discovery problem from a real lint failure. `discover_wiki.sh` already uses a dedicated exit code (2) for ambiguity; `lint.py` does not mirror it.

**Do not break the intentional ambiguity behaviour.** When discovery faces a *real* choice between distinct paths (e.g. an `EXISTING` parent wiki and a separate `AVAILABLE` location), it must still stop and surface candidates so the user chooses — silent upstream adoption is a confidentiality/scoping mistake, stated at [skills/wiki/SKILL.md:769](../plugins/knowledge_management/skills/wiki/SKILL.md) and `<resolving_the_wiki_location>`. The fix targets only the degenerate case where every candidate resolves to one path.

Files involved:

- [plugins/knowledge_management/skills/wiki/scripts/discover_wiki.sh](../plugins/knowledge_management/skills/wiki/scripts/discover_wiki.sh) — walk-up resolver (logic described around lines 7-9 / 69-71; undecided message around line 179).
- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py) — mirrored resolver (`discover_wiki`, around lines 64-111), hint string (~109), docstrings (~19, ~56), argparse (~1199-1204).

## Approach

1. **Dedupe candidates by resolved path in both scripts.** Before declaring "undecided", collapse the candidate list on the absolute resolved path. If all entries point to a single directory, resolve to it (treat it as the existing wiki) and exit success. Apply the identical rule in `discover_wiki.sh` and in `lint.py`'s `discover_wiki` so the two stay in lockstep.
2. **Alternatively / additionally, detect CWD-is-wiki-root directly.** Before the walk-up, if the current directory itself contains the wiki markers (`SCHEMA.md` and `index.md`, optionally `log.md`), resolve to CWD immediately. This is the most direct signal that "we are standing in the wiki" and avoids the two-candidate construction entirely. Pick one mechanism or layer both; keep behaviour identical across the shell and Python implementations.
3. **Fix the `lint.py` hint and docstrings.** Replace "pass an explicit `--wiki-path`" with the real usage: pass the wiki path as the first positional argument, e.g. `python3 lint.py /path/to/wiki`. Update the message at ~109 and both docstrings (~19, ~56).
4. **Give discovery-ambiguity its own exit code in `lint.py`.** Make the genuine-ambiguity exit distinct from lint-finding failures — exit 2 (mirroring `discover_wiki.sh`) rather than the bare `sys.exit(<string>)` exit-1 — so callers and the agent can distinguish "couldn't locate the wiki" from "lint found blocking issues". Keep the human-readable candidate listing.

Bump the skill and plugin versions per the repo's one-bump-per-commit rule at commit time, not while iterating.

## Acceptance

- Running `python3 scripts/lint.py` and `scripts/discover_wiki.sh` from *inside* a wiki root (a dir containing `SCHEMA.md` + `index.md`) resolves to that wiki and exits 0; no "undecided" output.
- A genuinely ambiguous layout (a real `EXISTING` parent wiki plus a distinct `AVAILABLE` sibling location) still stops and lists candidates for the user — the confidentiality guard is intact.
- `lint.py`'s undecided message and docstrings name the positional argument; following the message verbatim succeeds with no `unrecognized arguments` error.
- `lint.py` exits with a discovery-specific code (2) on genuine ambiguity, distinct from the blocking-findings exit (1).
- Script unit tests under `tests/wiki/` cover: CWD-is-wiki-root (resolves), genuine ambiguity (stops), and the corrected hint text.
- `make lint` clean; `tests/wiki/run_all.sh` passes with no regression.
