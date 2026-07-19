---
description: Rewrite the re-ingest drift instruction to compare fresh content against the recorded sha256 via the hash helper's report-only mode before any sidecar write, so drift is detected rather than erased.
scope: plugins/knowledge_management
created: 2026-07-19T18:51:20
updated: 2026-07-19T18:51:20
status: open
reported-by: Andreas Hoffmann
---

# Make re-ingest drift detection compare before it writes

## Goal

Re-ingesting a source actually detects drift: the skip-or-drift decision is made by comparing the freshly fetched content against the sidecar's recorded `sha256` while that recording still exists, and the sidecar body is rewritten only after drift is established. The template's promise — the hash "lets a future re-ingest of the same source skip processing when content is unchanged, and flag drift when it has changed" — becomes true as instructed, instead of depending on a command sequence that either always reports "ok" or erases its own evidence.

## Context

The instruction appears twice with the same wording: the `<capture_raw_source>` bullet in [skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) and the `<capture_raw>` policy in [skills/wiki_import/SKILL.md](../plugins/knowledge_management/skills/wiki_import/SKILL.md) both say "On re-ingest of the same source: run the same command, skip if it reports `ok`, flag drift if it reports `update`" — where "the same command" is `compute_sha256.py` in its default **write** mode.

That procedure cannot work in either reading. If the sidecar body has not been overwritten with the fresh fetch, the command hashes the old disk content and always reports `ok`, so the skip decision says nothing about whether the source changed. If the body was overwritten first, the raw layer was mutated before the drift decision, and the same invocation immediately rewrites the recorded hash — erasing the mismatch that the linter's `drift` check would otherwise catch, leaving "flag drift" to one console line in the moment. The script already ships the mode built for this: `--check` ("exit 1 if any file would change; write nothing") and `--print`, per the usage block in [skills/wiki/scripts/compute_sha256.py](../plugins/knowledge_management/skills/wiki/scripts/compute_sha256.py) — and no skill or agent instruction references either mode today.

Co-edit note: [wiki_front-end-skill-dir-resolution.md](wiki_front-end-skill-dir-resolution.md) rewrites the script-invocation form inside the same `<capture_raw>` block of `wiki_import` — coordinate wording so the block is edited coherently whichever lands first.

## Approach

Rewrite the re-ingest sentence in both homes to a compare-before-write protocol:

1. Capture the freshly fetched or converted content to a session-local temporary file (outside the wiki tree).
2. Compare its body hash against the sidecar's recorded `sha256` — via `compute_sha256.py --print` on the temporary capture, or `--check` semantics against the recorded value — while the recorded value is still intact.
3. On a match: skip, leaving the sidecar untouched (no body rewrite, no hash rewrite, no log entry).
4. On a mismatch: this is drift — rewrite the sidecar body to what the source now says (the sanctioned re-ingest update), run the default write mode to refresh the hash, and surface the drift to the user and the log entry for the ingest.

Keep the first-ingest instruction ("compute and write the hash with `compute_sha256.py`") unchanged; only the re-ingest branch changes.

**Out of scope:**

- Changes to `compute_sha256.py` itself — its existing modes already provide the needed comparison; the defect is the instruction sequence, not the tool.
- The agent's `<fix_source_drift>` remediation in `auto_shaper_wiki.md` — it acts after a lint `drift` warn already established the mismatch, so its recompute-after-update ordering is coherent as is.

## Acceptance

1. `rg "skip if it reports" ../plugins/knowledge_management/skills/wiki/SKILL.md ../plugins/knowledge_management/skills/wiki_import/SKILL.md` shows the old sentence superseded in both files by the compare-before-write protocol, and the rewritten instructions name the report-only mode (`--check` or `--print`) — which today has zero references from any skill.
2. The rewritten protocol in both files orders the steps as: obtain fresh content → compare against the recorded `sha256` → skip with no sidecar write on match / rewrite body, refresh hash, and surface drift on mismatch.
3. A behavior scenario in the wiki test harness re-ingests an unchanged source against a fixture sidecar and asserts the sidecar is byte-identical afterward; a second scenario re-ingests a changed source and asserts drift is surfaced and the recorded hash changes only together with the body rewrite. Both scenarios fail against the current instruction text's always-`ok` reading and pass with the rewrite.
4. `tests/wiki/run_all.sh` passes.
