---
description: Trigger git_commit's context consumption by blob byte/token size instead of file count, and give it a read recipe every harness can run, not only a Read tool.
scope: plugins/ai_dev/skills/git_commit
created: 2026-06-28T17:45:21
updated: 2026-06-28T17:45:21
status: open
reported-by: Andreas Hoffmann
---

# Make git_commit's consume-context contract size-triggered and harness-portable

## Goal

The `git_commit` skill reads the prepared context blob, then composes the commit message from it. Today its consumption contract chooses a read strategy by **file count** and names a **single reading tool**, and both choices break on the actual constraints agents hit. Reframe the one consume-context passage so it: (1) picks full-read vs. paginated-read vs. ordered slicing from the blob's **byte/token size against the agent's file-reading limits**, not from a file-count threshold; and (2) names a reading mechanism **every supported harness actually has**, so an agent without a dedicated Read tool gets a sanctioned recipe rather than improvising.

This is the general behaviour the contract should have, with the reported failures as its motivation rather than point-fixes: the deliverable is a corrected, single, canonical consume-context contract — not a patch for one observed changeset size.

## Context

The whole contract lives in `SKILL.md` under the `<consume_context>` element, with the bundled scripts and `references/manual_fallback.md` mirroring it. The passages that carry the two defects:

- `<consume_context>`'s `<slicing_fallback>` reserves `grep`/`awk`/`sed` slicing for changesets it describes as "typically 1000+ file changesets", and `<full_read>` calls a whole-file read the default for "any normal-sized commit". The binding constraint is not file count: a single agent read is capped by bytes and tokens (for example, on the order of a couple hundred KB or a few tens of thousands of tokens per read on one common harness), so a diff-dense or large-but-few-file blob overflows the cap far below 1000 files. When the byte cap denies even a paginated read, the contract leaves **no sanctioned path**, and the agent falls into the sample-by-filename indexing that `<hard_rules>` exists to forbid.
- `<full_read>` and `<paginated_read>` instruct the agent to "Use the `Read` tool" and to re-call it with `offset`/`limit`. On a harness with no such tool the directive names something that does not exist, so the agent reads the blob through shell viewers with no in-skill recipe and, on a large blob, thrashes through overlapping re-slices.
- The same instruction is printed at runtime: `prepare_commit_context.sh` emits a stdout consumption directive beginning "Read this entire file with the Read tool. Do NOT re-run git diff…". This directive and the `<consume_context>` prose must stay in step — a fix to one without the other splits the contract.
- `references/manual_fallback.md` restates the consume guidance for the post-failure path; it has to match the reframed contract so the scripted and manual paths do not diverge.
- The skill already establishes the precedent that one harness needs its own carve-out: the `<codex_agent_only>` element special-cases sandbox-escalation behaviour for that harness while the primary workflow stays unchanged for others. The portability clause below belongs in that same carve-out.
- The sibling [git_commit drift-guard task](ai-dev_git-commit-concurrent-session-staging.md) edits a **different** passage (`<commit_scope>` / `<execution_default>` / `<pause_conditions>` and the staging mechanism) but touches the **same** four artifacts — `SKILL.md`, `prepare_commit_context.sh`, `commit_with_message.sh`, and `references/manual_fallback.md`. Whichever lands second reconciles against the first rather than re-deriving those files, so the two contracts stay consistent and neither introduces a competing mechanism.

## Approach

Author the corrected contract **once** in `<consume_context>`, then bring the script's stdout directive and `references/manual_fallback.md` into agreement so prose, runtime directive, and fallback all state one thing.

- **Retrigger on size, not count.** Rewrite `<slicing_fallback>` so ordered slicing becomes a sanctioned path whenever a full or paginated read cannot cover the blob — including the case where the byte cap denies the read outright — framed against the file-reading tool's byte/token caps rather than a "1000+ file changesets" count. Keep `<full_read>` as the default for blobs that fit one read, now defined by fitting under the cap rather than by being "normal-sized".
- **Give a deterministic page heuristic.** For a page that overflows the token/byte cap, prescribe starting from a conservative line span and **halving on overflow** until it fits, rather than guessing a new `offset`/`limit` by hand and retrying ad hoc.
- **Add a harness-portability clause in `<codex_agent_only>`.** State that where the agent has no Read tool, the shell is the **sanctioned** reader for the blob, not a last resort, and give an ordered fixed-span recipe: read the line count first, then read consecutive non-overlapping spans that cover every byte, in order, never sampling by filename — the same whole-context discipline the Read path enforces.
- **Make the runtime directive harness-neutral.** Rewrite the stdout directive in `prepare_commit_context.sh` so it stops naming the Read tool as the only mechanism (for example, "read this entire file — with a Read tool, or ordered shell slices on a harness without one"), keeping the existing "do not re-derive with git diff/status/log" and "cover every byte in order" guarantees.
- **Emit the blob size.** Have `prepare_commit_context.sh` print the context blob's byte size alongside the path on stdout, so the consumer can choose full-read vs. slicing up front instead of discovering the cap through a failed read. This is the cheap mechanism that makes the size-based trigger actionable.
- **Preserve the guardrails verbatim.** The reframed contract keeps `<hard_rules>` intact: iterate every `<file_change>` section in order, never sample by filename, and never re-derive the context with `git diff`/`git status`/`git log`.

Non-goals: this task does not change commit-message composition, the whole-tree `git add -A` staging scope (owned by the drift-guard sibling), or the fallback-trigger semantics (`<fallback_trigger>` still fires only on a non-zero script exit).

## Acceptance

- `<consume_context>` chooses its read strategy from the blob's byte/token size against the file-reading tool's caps; the "1000+ file changesets" / "normal-sized commit" file-count framing is superseded, and one canonical size-based trigger statement remains in `<slicing_fallback>` and `<full_read>`.
- `<consume_context>` carries a deterministic page-size heuristic (conservative span, halve on overflow) for a page that exceeds the cap.
- A harness-portability clause in `<codex_agent_only>` names the shell as the sanctioned blob reader where no Read tool exists and gives an ordered, non-overlapping, count-then-span recipe; it preserves the no-sampling-by-filename discipline.
- The stdout directive emitted by `prepare_commit_context.sh` no longer names a Read tool as the sole mechanism — verifiable by running the script in a dirty repo and inspecting its stdout (or grepping the script's directive string) — and still forbids git re-derivation.
- `prepare_commit_context.sh` prints the context blob's byte size on stdout; running it on a staged changeset shows the size next to the path.
- `references/manual_fallback.md`'s consume guidance matches the reframed contract (size trigger, page heuristic, portability) with no statement that contradicts `SKILL.md`.
- The `<hard_rules>` guardrails — iterate every `<file_change>` in order, never sample by filename, never re-derive via `git diff`/`git status`/`git log` — remain stated once and intact.
