---
description: Add SKILL.md guidance to use Read (not Bash grep/cat/tail) when staging an Edit, and to resolve sources:/source_path: values against the wiki root when opening them.
scope: plugins/knowledge_management
created: 2026-05-28T20:05:29
updated: 2026-06-10T22:05:12
status: open
---

# File-access guidance: Read to stage edits; resolve `sources:` against the wiki root

## Goal

The wiki authoring contract steers the agent to use the right tool for two recurring file-access patterns, eliminating two predictable round-trips: (1) locating an edit target with `Read` (which satisfies the Edit precondition) instead of a Bash `grep`/`cat`/`tail` that does not; and (2) resolving a `sources:` / `source_path:` value against the wiki root before opening it, instead of treating it as a CWD-relative path.

## Context

Two distinct but small failure modes recur during wiki editing, both fixable with a sentence of guidance in the skill prose:

1. **Bash-locate then Edit fails the read-precondition.** When the agent locates the span to change with a Bash command (`grep -n`, `cat`, `tail`) and then calls `Edit`, the edit fails with "File has not been read yet" because the Edit tool requires a prior `Read` of *that* file in the session — a Bash grep does not satisfy it. The agent then has to `Read` and re-`Edit`: a three-call round-trip where one `Read` + one `Edit` would do. The skill's editing/log guidance currently leans on Bash inspection idioms ([skills/wiki/SKILL.md:684](../plugins/knowledge_management/skills/wiki/SKILL.md) and nearby) without flagging that they do not prepare an Edit.

2. **`sources:` paths read as CWD-relative.** By convention, `sources:` / `source_path:` entries are paths relative to the **wiki root** (the linter resolves them that way — see the source-path existence check in [skills/wiki/scripts/lint.py](../plugins/knowledge_management/skills/wiki/scripts/lint.py)). But nothing in the agent-facing prose says so, so when the agent reads a `sources:` value literally (e.g. `raw/notes/<slug>.md`) it opens the wrong path, gets "file does not exist", and falls back to a `find` to locate the real `<wiki>/raw/notes/<slug>.md`. A one-line note removes the failed-Read-then-find detour.

This task is the *read-time* counterpart to the provenance tasks. [wiki_provenance-via-raw-and-sources.md](wiki_provenance-via-raw-and-sources.md) and [wiki_raw-kind-rubric-and-out-of-repo-paths.md](wiki_raw-kind-rubric-and-out-of-repo-paths.md) define how provenance is *written* (the `raw/` sidecar + `sources:` convention and `source_path:` semantics); this task only adds the guidance for correctly *opening* those paths and for staging edits. Keep the write-side conventions in those tasks; do not duplicate them here.

Files involved:

- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — editing/log guidance (~684) and the provenance/`sources:` description (~471-472).
- [plugins/knowledge_management/agents/wiki_auto_shaper.md](../plugins/knowledge_management/agents/wiki_auto_shaper.md) — mirror both notes wherever it stages edits or opens `sources:` paths.

## Approach

1. **Read-to-stage-edits note.** In the editing guidance, add a short rule: to locate a span you intend to `Edit`, use `Read` (it both shows the content and satisfies Edit's read requirement); reserve Bash `grep`/`cat`/`tail` for counting and log-offset work, not for preparing an edit. Pair this with the entry-aware log retrieval from [wiki_log-rotation-and-retrieval.md](wiki_log-rotation-and-retrieval.md) so the log case is covered consistently.
2. **`sources:` resolution note.** Near the provenance description (~471-472), add one line: `sources:` / `source_path:` entries are paths relative to the **wiki root**; prefix with `$WIKI/` (or the wiki dir) when opening one with `Read`. Mirror the same note in the auto-shaper.
3. Keep both additions to a sentence or two each — these are tool-use clarifications, not new conventions. Respect the no-meta-in-body and minimal-addition postures established elsewhere in the family.

## Acceptance

- SKILL.md (and the auto-shaper) state that `Read` is the way to stage an `Edit`, and that Bash grep/cat/tail do not satisfy the Edit precondition.
- SKILL.md (and the auto-shaper) state that `sources:` / `source_path:` values resolve against the wiki root and must be prefixed accordingly when opened.
- The additions are short prose only; no new lint check is required (though a fixture walkthrough confirming no "File has not been read yet" and no failed `sources:` Read is welcome).
- `tests/wiki/run_all.sh` passes.
