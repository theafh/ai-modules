---
description: Generalize wiki detection to a name + marker predicate so loosely-named and stood-in wikis resolve instead of "undecided"; fix lint.py's --wiki-path hint and give discovery its own exit code.
scope: plugins/knowledge_management
created: 2026-05-28T20:06:23
updated: 2026-06-09T00:05:37
status: implemented
---

# Detect a wiki by name-substring + marker files; resolve cleanly when standing in one; fix the `--wiki-path` hint

## Goal

Discovery recognises a directory as a wiki by a **name-and-structure predicate** rather than an exact folder name: the basename contains `wiki` (case-insensitive) **and** at least two of the three markers `SCHEMA.md`, `index.md`, `log.md` exist directly in it. The `.no_wiki` opt-out overrides the predicate everywhere (a directory carrying it is never treated as a wiki). With that predicate:

- Running the linter or the discovery script with the wiki itself as the working directory — including a topic-named root such as `ml-wiki/` or `wiki-research/` — resolves to it silently instead of failing with "wiki location is undecided".
- Standing in the *parent* of such a wiki auto-resolves to it, exactly as a child named `wiki/` resolves today.
- A *subdirectory* of a wiki (e.g. `ml-wiki/entities/`) is **not** itself a valid wiki location: it does not silently adopt the enclosing wiki, but follows the existing ask-the-user guard so the scoping decision stays with the user.
- A directory merely named `wiki` but lacking the markers — or any directory carrying `.no_wiki` — is **not** mistaken for a wiki (closing a false positive the exact-name probe has today, and honouring retire-in-place).

The genuine-ambiguity path (a real choice between an existing parent wiki and a distinct creation location) is preserved. Separately, `lint.py`'s undecided-error message and docstrings stop telling the caller to pass a flag that does not exist, and discovery ambiguity gets its own exit code distinct from lint failure.

## Context

Both `scripts/discover_wiki.sh` and the mirrored resolver in `scripts/lint.py` detect a wiki purely by **folder name**: each walks *up* from CWD and, at every level, probes for a child directory named exactly `wiki` (`discover_wiki.sh:147` `-d "$level/wiki"`; `lint.py:86` `(level / "wiki").is_dir()`). At each level a `.no_wiki` file opts that level out (`discover_wiki.sh:144`, `lint.py:84`). The marker files exist in the code — `lint.py:115` `SPECIAL_FILES = ("SCHEMA.md", "index.md", "log.md")` — but only to classify top-level files *while linting an already-located wiki*; discovery never reads them. The name `wiki` is also baked into creation (`available` candidates create at `<level>/wiki`), the opt-out marker (`.no_wiki`), and the global default (`$HOME/wiki`).

Two problems with name-only detection:

1. **Standing in the wiki root fails to resolve.** When CWD is the wiki itself (e.g. `<proj>/wiki`), the walk produces two candidates that resolve to the **same** path: level `<proj>/wiki` has no child `wiki/` → recorded `available`; level `<proj>` has child `<proj>/wiki` → recorded `existing`, walk stops. The resolver only auto-resolves when `candidates[0]` is `existing`; here index 0 is the `available` entry, so it falls through to "undecided" even though both point at one directory. The agent's learned workaround is to `cd` to the parent and re-run, costing turns on every invocation from inside a wiki.
2. **Loosely-named wikis are invisible, markerless `wiki/` dirs are false positives.** A user who names their wiki by topic (`ml-wiki/`, `wiki-notes/`) is never detected, and a non-wiki directory that happens to be named `wiki` (a vendored submodule, a project *about* wikis) is wrongly adopted.

**Chosen detection model.** Replace the exact-name probe with a shared wiki-ness predicate — basename contains `wiki` (case-insensitive) **and** ≥2 of `{SCHEMA.md, index.md, log.md}` — applied wherever the resolvers test a directory for an existing wiki. `init_wiki.sh:90-92` writes all three markers on creation, so a fresh wiki scores 3/3 and the 2-of-3 threshold has slack: one missing or renamed marker still resolves. The name token stays required (this is *not* full structure-only detection): a marker-bearing directory with no `wiki` in its name is not auto-discovered, keeping false positives low and creation name-anchored.

**`.no_wiki` overrides the predicate.** `.no_wiki` is the explicit opt-out and takes precedence over wiki-ness. Check it before scanning any candidate directory the resolver inspects — CWD in the short-circuit, and each directory examined during the walk (the level itself, as today, and any child tested as an existing wiki). A directory carrying `.no_wiki` is dropped: it neither resolves as an existing wiki nor (per the walk's existing per-level opt-out) becomes a creation candidate. This preserves the documented retire-in-place behaviour ("Place at an existing `<wiki-path>/.no_wiki` to retire that wiki dir without deleting it", `discover_wiki.sh:37-40`) and extends it so a retired wiki is also skipped when its parent is scanned.

Two coupled defects compound the original symptom, both in [skills/wiki/scripts/lint.py](../../plugins/knowledge_management/skills/wiki/scripts/lint.py):

1. **Wrong remediation hint.** The undecided exit message (around line 109) and the module docstrings (around lines 19 and 56) instruct the caller to "pass an explicit `--wiki-path`". `argparse` defines only a *positional* `wiki_path` argument and `--quiet` (around lines 1199-1204); there is no `--wiki-path` option. A caller that follows the hint gets `unrecognized arguments: --wiki-path` and must retry with the positional form.
2. **Ambiguity conflated with lint failure.** `lint.py`'s resolver raises via `sys.exit(<string>)`, which exits with code 1 — the same family of exit code used for "lint found blocking issues". Callers running `lint.py --quiet` as the normal blocking-only check (documented at [skills/wiki/SKILL.md:639](../../plugins/knowledge_management/skills/wiki/SKILL.md)) cannot tell a discovery problem from a real lint failure. `discover_wiki.sh` already uses a dedicated exit code (2) for ambiguity; `lint.py` does not mirror it.

**Do not break the intentional ambiguity behaviour.** When discovery faces a *real* choice between distinct paths — an `EXISTING` parent wiki and a separate `AVAILABLE` creation location, including the subdirectory-of-a-wiki case — it must still stop and surface candidates so the user chooses; silent upstream adoption is a confidentiality/scoping mistake, stated at [skills/wiki/SKILL.md:769](../../plugins/knowledge_management/skills/wiki/SKILL.md) and `<resolving_the_wiki_location>`. The predicate only changes *what counts as a wiki*, not *when to ask*: a single recognised wiki at CWD or directly under it auto-resolves; the vertical break-on-first walk and the ask-the-user path are unchanged.

Files involved:

- [plugins/knowledge_management/skills/wiki/scripts/discover_wiki.sh](../../plugins/knowledge_management/skills/wiki/scripts/discover_wiki.sh) — walk-up resolver (per-level `.no_wiki` ~144, name probe ~147; undecided message ~179).
- [plugins/knowledge_management/skills/wiki/scripts/lint.py](../../plugins/knowledge_management/skills/wiki/scripts/lint.py) — mirrored resolver (`discover_wiki`, ~64-111; `.no_wiki` ~84, name probe ~86; `SPECIAL_FILES` ~115), hint string (~109), docstrings (~19, ~56), argparse (~1199-1204).

## Approach

1. **Define one shared wiki-ness predicate, mirrored in both scripts.** `is_wiki(dir)` is true when the basename contains `wiki` case-insensitively **and** at least two of `SCHEMA.md`, `index.md`, `log.md` exist directly inside `dir`. Implement it identically in `discover_wiki.sh` (a small helper: lowercase-basename `*wiki*` test plus a marker count loop) and in `lint.py`'s discovery (reuse the existing `SPECIAL_FILES` tuple for the marker set). Keep the two in lockstep — same name rule, same 2-of-3 threshold, same marker list. `.no_wiki` is checked *before* the predicate for every candidate: a directory carrying it is dropped and never resolves.
2. **Short-circuit when CWD is itself a wiki (primary fix).** As the first step in both resolvers — before building the walk-up ladder and before the under-`$HOME` / outside-`$HOME` split — if `<CWD>/.no_wiki` is absent and `is_wiki(CWD)` holds, resolve to CWD and exit success. This handles standing in `wiki/` and in any topic-named root, and never constructs the misleading `available` "create a nested `wiki/`" candidate. If CWD carries `.no_wiki`, skip the short-circuit and fall through to the walk (which also skips the CWD level), so a retired wiki you are standing in is not resolved.
3. **Generalise the exact-name probe with the same predicate, preserving break-on-first.** Replace the exact `-d "$level/wiki"` / `(level / "wiki").is_dir()` check in the walk loop so that a child directory counts as an existing wiki when `is_wiki(child)` holds and the child does not carry `.no_wiki`. Keep the walk's break-on-first behaviour exactly: stop climbing at the first level that yields an existing wiki, and take the first matching child — in sorted (lexical) order, identically in both scripts — as the resolved wiki (the walk does not enumerate further matches; a second `*wiki*` sibling at the same level is deliberately not surfaced). Levels with no matching child remain `available` creation candidates and the walk continues up. Creation stays exact-name: an `available` candidate still means "create at `<level>/wiki`".
4. **Fix the `lint.py` hint and docstrings.** Replace "pass an explicit `--wiki-path`" with the real usage: pass the wiki path as the first positional argument, e.g. `python3 lint.py /path/to/wiki`. Update the message at ~109 and both docstrings (~19, ~56).
5. **Give discovery-ambiguity its own exit code in `lint.py`.** Make the genuine-ambiguity exit distinct from lint-finding failures — exit 2 (mirroring `discover_wiki.sh`) rather than the bare `sys.exit(<string>)` exit-1 — so callers and the agent can distinguish "couldn't locate the wiki" from "lint found blocking issues". Keep the human-readable candidate listing.

## Acceptance

- **Predicate.** A directory with `wiki` anywhere in its (case-insensitive) name **and** ≥2 of the three markers is recognised as a wiki; with only 1 marker it is not; with 3 markers but no `wiki` in the name it is not auto-discovered. Identical results from the `discover_wiki.sh` helper and `lint.py`.
- **`.no_wiki` overrides.** A directory that passes the predicate but carries `.no_wiki` is not resolved as a wiki — neither when it is CWD nor when it is found as a child during the walk (retire-in-place honoured).
- Running `python3 scripts/lint.py` and `scripts/discover_wiki.sh` with a recognised wiki as CWD — both a plain `wiki/` and a topic-named `ml-wiki/` (each with ≥2 markers) — resolves to that wiki and exits 0; no "undecided" output, and no `available` candidate offering to create a nested `wiki/`.
- Running from the *parent* of a topic-named `ml-wiki/` (with markers) auto-resolves to it, mirroring how a child `wiki/` resolves today.
- Running from a *subdirectory* of a wiki (e.g. `ml-wiki/entities/`) does **not** auto-resolve to the enclosing wiki — it follows the ask-the-user guard (candidates listed, exit 2), preserving the scoping decision.
- A directory named `wiki` but lacking the markers is **not** adopted as a wiki.
- A genuinely ambiguous layout (a real `EXISTING` parent wiki plus a distinct `AVAILABLE` creation location) still stops and lists candidates for the user — the confidentiality guard is intact.
- `lint.py`'s undecided message and docstrings name the positional argument; following the message verbatim succeeds with no `unrecognized arguments` error.
- `lint.py` exits with a discovery-specific code (2) on genuine ambiguity, distinct from the blocking-findings exit (1).
- Script unit tests under `tests/wiki/` cover: the predicate (name+marker positive, missing-name negative, 2-of-3 boundary), `.no_wiki` override (predicate-passing dir skipped), CWD-is-wiki for plain and topic-named roots (resolve), parent-of-topic-named (resolves), subdirectory-of-a-wiki (asks, not auto-resolved), genuine ambiguity (stops), and the corrected hint text.
- `make lint` clean; `tests/wiki/run_all.sh` passes with no regression.
