---
description: Give wiki discovery a deterministic exit-2 choice handoff: distinct usage-error exit code, positional path support, agent wording aligned to the script interface, and shell/Python hidden-dir parity.
scope: plugins/knowledge_management
created: 2026-07-19T18:51:20
updated: 2026-08-12T21:15:32
status: ready
reported-by: Andreas Hoffmann
---

# Make wiki discovery hand off an exit-2 choice deterministically

## Goal

When wiki discovery ends ambiguous (exit 2) and the user picks a candidate, the flow incorporates that choice deterministically: `discover_wiki.sh` accepts the chosen path the way the sibling Python tools already do, a usage error no longer shares the ambiguity exit code, the `auto_shaper_wiki` discovery step matches the script's real interface instead of prescribing an impossible re-run, and the shell and Python discovery implementations recognize the same set of wikis.

## Context

Three coherence defects across [skills/wiki/scripts/discover_wiki.sh](../plugins/knowledge_management/skills/wiki/scripts/discover_wiki.sh), the discovery mirror in [skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py), and [agents/auto_shaper_wiki.md](../plugins/knowledge_management/agents/auto_shaper_wiki.md):

- **Usage errors collide with the ambiguity code.** The script's argument handling answers any unrecognized argument with "unknown argument" and exit 2 — the same code that means "candidates on stdout, ask the user". Verified: passing a path argument exits 2 with empty stdout, so a caller following the documented `case $rc in 2) candidates="$output"` pattern from the SKILL's `<tools>` block receives an empty candidate list. The collision is easy to trigger precisely because `lint.py` and `compute_sha256.py` both accept a positional wiki path while `discover_wiki.sh` alone rejects one.
- **The agent prescribes a re-run the script cannot perform.** The agent's `<discover_wiki>` step says, after the user picks a candidate, "re-run discovery against that choice using `$WIKI_SKILL/scripts/discover_wiki.sh`" — but the script takes no path, so the re-run only converges when the user accepted every offered `.no_wiki` marker and picked an `EXISTING` candidate. The wiki skill's `<offer_no_wiki_markers>` explicitly allows declining ("On no, leave them untouched"), in which case the re-run reproduces the identical exit-2 list — a protocol loop. The skill's own flow has the correct shape already: `<proceed_with_operation>` adopts the chosen path directly without any re-run.
- **Hidden-directory parity is broken despite a parity claim.** The shell child scan (`for child in "$level"/*/`) never sees dot-directories, while `lint.py`'s `sorted(level.iterdir())` includes them and sorts them first — directly under a comment claiming "lexical order, to match lint.py". A dot-named directory that satisfies the wiki predicate resolves differently between the two tools.

Prior decisions to honor: [archive/wiki_discovery-from-inside-wiki-dir.md](archive/wiki_discovery-from-inside-wiki-dir.md) (finished) established the name+marker predicate and the current exit-code scheme — read it before changing exit semantics. This task also co-edits `lint.py` alongside [archive/wiki_lint-blind-spots-and-false-positives.md](archive/wiki_lint-blind-spots-and-false-positives.md) (finished) (disjoint functions — discovery here, checks there); coordinate if both land near each other.

## Approach

1. **Distinct usage-error exit code (exit 3).** Give unrecognized flags and unsupported argv shapes exit **3** (documented in the header comment and `--help`), keeping **0** = resolved path on stdout, **1** = existence miss under `--check`, **2** = ambiguous-with-candidates on stdout — the **0/1/2** scheme from [archive/wiki_discovery-from-inside-wiki-dir.md](archive/wiki_discovery-from-inside-wiki-dir.md). Follow the repo convention of reserving **3** for a distinct caller signal (`git_commit` uses **3** for drift refusal).
2. **Positional path handoff.** Extend `discover_wiki.sh` to mirror `lint.py`'s optional positional `wiki_path`: supported forms are `discover_wiki.sh`, `discover_wiki.sh --check`, `discover_wiki.sh WIKI_PATH`, and `discover_wiki.sh WIKI_PATH --check`. With `WIKI_PATH`, mirror `lint.py`'s positional `wiki_path`: when the path exists on disk, print its canonical path and exit **0**; when it does not exist, exit **1** with an error on stderr — without requiring the wiki predicate, so an `AVAILABLE:` choice works. `WIKI_PATH --check` follows the same existence rule. Any other argv shape or unknown flag exits **3** on stderr with no candidate list — never **2**. Callers (including the agent) pass the user's chosen path positionally instead of re-running bare discovery.
3. **Align the agent's wording.** Rewrite the `<discover_wiki>` step in `auto_shaper_wiki.md` so that after the user picks a candidate the agent sets `$WIKI` from that pick directly (mirroring the skill's `<proceed_with_operation>`), passing it positionally when re-invoking bundled tools; keep the `.no_wiki` marker offer, and remove the instruction to re-run bare `discover_wiki.sh` against the choice.
4. **Hidden-dir parity.** Make `lint.py`'s discovery skip dot-directories in its child scan, matching the shell (hidden directories are already excluded from the page walk elsewhere, so skipping is the consistent behavior), and state in both implementations' doc comments that they mirror each other.
5. **Keep the SKILL `<tools>` contract valid.** Update the wiki skill's `<tools>` bash snippet comments (and any exit-code prose beside it) so the existing `case $rc in 2) … ;; *) exit "$rc" ;; esac` branch still matches the documented **0/1/2/3** set — exit **3** stays a hard failure, not an ambiguity prompt.

**Out of scope:**

- Walk-up semantics, candidate ordering, and the 2-of-3 marker predicate — settled by the archived discovery task above; this task changes only the choice handoff, usage-error signaling, and the hidden-dir divergence.

## Acceptance

1. `discover_wiki.sh <existing-wiki-path>` prints the path and exits **0**; `discover_wiki.sh <existing-non-wiki-path>` (an `AVAILABLE:` choice) prints its canonical path and exits **0**; `discover_wiki.sh <missing-path>` exits **1**; `discover_wiki.sh <missing-path> --check` exits **1**; an unrecognized flag (e.g. `--bogus`) exits **3**, not **2**, with a usage message on stderr and no candidate list on stdout.
2. `rg "discovery against that choice using" ../plugins/knowledge_management/agents/auto_shaper_wiki.md` returns no match; the rewritten `<discover_wiki>` step sets `$WIKI` from the user's pick directly, still offers `.no_wiki` markers for unchosen `AVAILABLE` candidates, and a declined-markers walkthrough reaches a resolved `$WIKI` without repeating the candidate prompt.
3. On a fixture tree containing a dot-named directory that satisfies the wiki predicate, `discover_wiki.sh` and `python3 lint.py` (no positional argument) resolve to the same wiki.
4. Discovery doc comments in `discover_wiki.sh` and `lint.py` each state they mirror the sibling implementation.
5. The script's header comment and `--help` document exit codes **0**, **1**, **2**, and **3**; the wiki skill's `<tools>` snippet still parses cleanly and treats exit **3** as a non-ambiguous failure (`*) exit "$rc"`), not as exit **2**'s candidate prompt.
6. Script unit tests under `tests/wiki/` cover the positional forms (`WIKI_PATH`, `WIKI_PATH --check`), including a non-wiki existing path for both forms, exit **3** on usage error, and the dot-directory parity case; `tests/wiki/run_all.sh` passes.
