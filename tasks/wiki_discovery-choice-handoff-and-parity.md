---
description: Give wiki discovery a deterministic exit-2 choice handoff: distinct usage-error exit code, positional path support, agent wording aligned to the script interface, and shell/Python hidden-dir parity.
scope: plugins/knowledge_management
created: 2026-07-19T18:51:20
updated: 2026-07-19T18:51:20
status: open
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

1. **Distinct usage-error exit code.** Give unrecognized flags their own exit code (documented in the header comment and `--help`), keeping 0 = resolved, 1 = `--check` miss, 2 = ambiguous-with-candidates.
2. **Positional path handoff.** Accept an optional positional path in `discover_wiki.sh`: validate it (directory exists, or exists-check deferred to `--check` semantics), print it, and exit accordingly — the same contract the two Python tools already offer. This gives every caller, including the agent, a scripted way to say "the user chose this".
3. **Align the agent's wording.** Rewrite the `<discover_wiki>` step in `auto_shaper_wiki.md` so that after the user picks a candidate the agent adopts that path directly (mirroring the skill's `<proceed_with_operation>`), passing it positionally when it re-invokes any bundled tool; keep the `.no_wiki` marker offer, and drop the unconditional "re-run discovery against that choice" instruction that loops when markers are declined.
4. **Hidden-dir parity.** Make `lint.py`'s discovery skip dot-directories in its child scan, matching the shell (hidden directories are already excluded from the page walk elsewhere, so skipping is the consistent behavior), and state in both implementations' doc comments that they mirror each other.

**Out of scope:**

- Walk-up semantics, candidate ordering, and the 2-of-3 marker predicate — settled by the archived discovery task above; this task changes only the choice handoff, usage-error signaling, and the hidden-dir divergence.

## Acceptance

1. `discover_wiki.sh <existing-wiki-path>` prints the path and exits 0; with `--check` and a missing path it exits 1; an unrecognized flag exits with the new usage code, not 2, and prints no candidate list.
2. `rg "re-run discovery against that choice" ../plugins/knowledge_management/agents/auto_shaper_wiki.md` returns no match; the rewritten step adopts the user's pick directly and still offers the `.no_wiki` markers, and a declined-markers walkthrough of the step text reaches a resolved `$WIKI` without repeating the candidate prompt.
3. On a fixture tree containing a dot-named directory that satisfies the wiki predicate, `discover_wiki.sh` and `python3 lint.py` (no positional argument) resolve to the same wiki.
4. The script's header comment and `--help` document the full exit-code set including the usage code, and the SKILL `<tools>` snippet's exit-code case handling still parses cleanly against the new codes.
5. Script unit tests under `tests/wiki/` cover the positional path, the usage exit code, and the dot-directory parity case; `tests/wiki/run_all.sh` passes.
