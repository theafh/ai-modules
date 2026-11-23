---
description: "Reset the request-concurrency-queue token cursor when a compaction rewrites the transcript, so the first post-compaction primary request is charged its real new context."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T11:04:36Z
status: ready
reported-by: Andreas Hoffmann
---

# Charge the real context after a compaction

## Goal

After a compaction rewrites a session's transcript, the next primary request is charged its full prompt as new context instead of a non-positive delta against the pre-compaction body. A title or generate request leaves the cursor where it is, so it cannot inflate the next primary's charge.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts`:

- `bodyMeasure` holds each session's last admitted request size and survives turn boundaries by design.
- `estimateRequestCost(request, sessionID, safetyFactor, fresh)` computes `newText = max(0, measured.textBytes - previous.textBytes)`, and its `commit` writes the cursor only when `fresh` is false.
- The caller passes `fresh = event.kind !== "primary"`, so compaction, title, and generate all skip the cursor update.
- The estimate is taken before admission and `commit` runs after it, so a primary that queues on a slot, estimates before a compaction, and is admitted after it re-writes the pre-compaction body over any reset the compaction performed.

Compaction replaces the transcript with a summary plus a kept tail. The next primary request's body is unrelated to the body the cursor still holds, and when it is smaller — the usual case — the delta is zero and the request spends no budget. The comment above `estimateRequestCost` says the cursor is not moved "so the next primary request's delta still measures against the conversation it continues", which does not hold once the conversation has been rewritten.

A title or generate request carries its own small prompt and does not represent the conversation, so it must keep the current no-move behaviour; clearing the cursor for it would charge the next primary its whole body.

Verified by reading the code above. Baseline: `bun test` and `bunx tsc --noEmit` pass in the package.

**Decision recorded:** a retried prompt is charged when it is admitted, so a retry re-sending the same body spends zero additional new tokens. That is intentional and stays; the retry path is not part of this change.

## Approach

- Pass the request kind into `estimateRequestCost` instead of a boolean. The zero baseline stays for `compaction`, `title`, and `generate`; only the cursor handling differs per kind.
- For `kind === "compaction"`, clear the session's `bodyMeasure` entry when the request is admitted, and bump a separate per-session reset-generation map. Delete that session's reset-generation entry in `releaseSession`'s `session.deleted`/`dispose` branch alongside `bodyMeasure`.
- For `title` and `generate`, keep the cursor untouched.
- For `primary`, keep committing the measured body, but capture the session's reset generation when the estimate is taken and skip the commit when that generation has moved by admission time. That closes the race where a queued primary would re-write the pre-compaction cursor.
- Update the comment above `estimateRequestCost` so it states the compaction reset and no longer claims the cursor always measures the continuing conversation.

**Out of scope:** Changing the retry charging rule, the per-image charge, or the token-estimate constants.

## Acceptance

- A token-accounting test passes: after a primary, a compaction, and a second primary whose body is smaller than the first, the second primary is charged its whole body — observed as the drop in `tokensAvailable` from the status snapshot, not as an internal cursor value.
- A token-accounting test passes: the `tokensAvailable` drop across a compaction equals that compaction's whole-prompt charge. This is a regression guard for the zero baseline the task preserves.
- A code-state check passes: `releaseSession`'s `session.deleted`/`dispose` branch deletes the session's reset-generation entry alongside `bodyMeasure`.
- A token-accounting test passes: after a primary, a title request, and a second primary, the second primary is charged the delta between the two primary bodies. This is a regression guard for the behaviour the Goal preserves.
- A token-accounting test passes: after a primary, a generate request, and a second primary, the second primary is charged the delta between the two primary bodies.
- A token-accounting test passes: a primary queued on a slot across a compaction does not re-write the cursor, so the primary admitted after it is still charged its whole body.
- The `estimateRequestCost` comment describes the compaction reset and the reset-generation guard, and no passage claims the cursor always measures the continuing conversation.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/` and this task file.
