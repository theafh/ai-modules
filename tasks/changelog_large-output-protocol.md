---
description: Stop prepare_changelog_day.sh from overflowing the tool buffer — write the blob to a file and add a git_commit-style paginated-consume protocol.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-02T20:06:20
updated: 2026-06-13T01:47:36
status: open
reported-by: Andreas Hoffmann
---

# Give update_changelog a large-output protocol like git_commit's

## Goal

Stop `prepare_changelog_day.sh` output from overflowing the tool-result channel
and forcing the agent into lossy workarounds. Today the script prints the full
per-file diff for the whole day to **stdout**, so any busy day blows past the
result limit; the agent then either re-greps the persisted overflow file (wasted
turns) or — worse — pipes the script through `head -200` and composes the day
section from a **truncated** view of the diffs (silent missing-commit / missing-file
bugs). Adopt the proven `git_commit` pattern: the script hands back a file path, and
the skill prescribes an ordered, paginated read that never re-derives and never
truncates.

## Context

- Script: `plugins/ai_dev/skills/update_changelog/scripts/prepare_changelog_day.sh`. Its `print_diffs()` runs `git --no-pager diff` per changed file and writes everything to stdout, wrapped in `<changelog_day>…</changelog_day>`.
- Reference implementation **for whoever builds this task — not to be cited in the shipped skill**: the `git_commit` skill in the same plugin. Its `scripts/prepare_commit_context.sh` writes the structured blob to a file under the system tmp dir and prints exactly two stdout lines — the **absolute context-file path** and a one-line consumption directive. Its `SKILL.md` then drives consumption with a `<consume_context>` block:
  - `<full_read>` — `Read` the whole file (default path).
  - `<paginated_read>` — if it overflows the Read window, call `Read` again with `offset`/`limit` and continue **in sequence** until every byte is covered.
  - `<slicing_fallback>` — only for enormous changesets, chunk with `grep`/`awk`/`sed` into **ordered slices** and read each in order — never sample by filename.
  - `<hard_rules>` — never re-derive with `git diff`/`git status`/`git log`; iterate every section in order.
- Evidence this hurts in practice (from session-transcript audit, 2026-06-02):
  - `413ad030`: day 2026-05-09 emitted ~100 KB → only a 2 KB preview reached the model; agent burned 3 extra Bash calls clawing content back, then defensively `| head -200`-truncated day 2 and lost the closing tag.
  - `6866e0db`: day 2026-05-28 emitted **244 KB** → same re-grep dance.
  - `df256b21`: 29.8 KB persisted.
- The redundant manual `git log` re-derivation seen in the same sessions (including the `--since=DATE --until=DATE` same-day footgun that returns nothing) is the **same root cause** — the agent doesn't trust the script as the sole per-day source once its output overflowed. The `<hard_rules>` line below fixes both.
- Interaction: the script's trailing `<entry_instruction>` heredoc references the `[status]` marker, which [changelog_immutable-entries-redesign.md](changelog_immutable-entries-redesign.md) reworks — sequence the two so the `<entry_instruction>` text is edited once; whichever lands second rebases on the first.

## Approach

Two coordinated changes, script + prose:

1. **Script — hand back a file, not a stdout dump.** Rework `prepare_changelog_day.sh` to write the full `<changelog_day>` blob to a file under the system tmp dir (mirror `prepare_commit_context.sh`), and print on stdout only the **absolute path** to that file plus a one-line consumption directive. Keep the `no commits on <date>` → exit 1 contract on stderr unchanged. The blob's internal structure (`<commits>`, `<files_changed>`, `<diffs>`/`<file_change>`, `<entry_instruction>`) stays the same — only its delivery moves from stdout to a file.
2. **Skill — add a consume protocol.** Add a `<consume_context>` block to `update_changelog/SKILL.md` modeled on `git_commit`'s: default `Read` of the path; paginated `Read` with `offset`/`limit` in sequence until the whole file is covered; ordered `grep`/`awk` slicing only as a last resort for huge days; and a hard rule — **never** re-derive the day with `git log`/`git diff`/`git status` (the script is the sole per-day source), **never** truncate the blob with `head`, and iterate every `<file_change>` in order rather than sampling.
3. Update the `<tools>`/`<prepare_changelog_day>` description and `<procedure>` substeps so they reference the file-path return and the consume protocol instead of "fetch the context blob in one call".
4. Keep the `<consume_context>` block **self-contained** — describe the read protocol inline, in full. Do **not** add a runtime pointer to `git_commit` (or any sibling) in the shipped skill: an agent running `update_changelog` gains nothing from being told to go look at another skill and is more likely to get distracted than helped. `git_commit` is only the implementer's model (see `## Context`); the protocol it demonstrates gets copied into this skill's own prose, not referenced from it.
5. If `tests/update_changelog/` has script unit tests, extend them to assert the script prints a path (not the blob) and that the file contains the expected sections; otherwise note the gap (don't grow the harness in the shipping commit per the repo rules).

Non-goals: don't change which commits a day selects — that's [changelog_incremental-day-boundaries.md](changelog_incremental-day-boundaries.md); the script's `--after/--before` day window is correct and stays as-is. Don't add a compact/diffs-off mode unless the file-handoff alone proves insufficient — the file path plus paginated read should remove the overflow entirely, matching how `git_commit` handles 1000-file commits.

## Acceptance

- `prepare_changelog_day.sh` prints an absolute file path (+ directive) on stdout and writes the blob to that file; running it on a known-busy day produces no oversized tool-result overflow.
- `SKILL.md` carries a `<consume_context>` block with full-read → paginated-read → ordered-slicing and a hard rule against re-deriving via `git log`/`git diff`/`git status` and against `head`-truncating the blob.
- The `<tools>` description and `<procedure>` reference the file-path handoff, not a stdout blob.
- The `<consume_context>` block is self-contained and does **not** reference `git_commit` or any other sibling skill — the protocol is spelled out inline.
