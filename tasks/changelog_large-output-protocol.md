---
description: Stop prepare_changelog_day.sh from overflowing the tool buffer — write the blob to a file and add a git_commit-style paginated-consume protocol.
scope: plugins/ai_dev/skills/update_changelog
created: 2026-06-02T20:06:20
updated: 2026-06-23T22:06:41
status: ready
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
- Interaction: [changelog_immutable-entries-redesign.md](archive/changelog_immutable-entries-redesign.md) has landed, so `update_changelog/SKILL.md` is status-free, but the script's trailing `<entry_instruction>` heredoc still references the `[status]` marker and current-state marker assignment. Rewrite that heredoc in place so the script's embedded instruction matches the immutable-entry format.

## Approach

Coordinated changes across script, skill prose, and local tests:

1. **Script — hand back a file, not a stdout dump.** Rework `prepare_changelog_day.sh` to write the full `<changelog_day>` blob to a fresh context file under the system tmp dir (mirror `prepare_commit_context.sh`), and print on stdout only the **absolute path** to that file plus a one-line consumption directive. Keep the context file separate from the script's trap-cleaned scratch `tmp_dir`: `tmp_dir` may still hold internal hash/path lists and be removed on exit, but the returned context file must remain readable after the script exits. Keep the `no commits on <date>` → exit 1 contract on stderr unchanged. The blob's tag structure (`<commits>`, `<files_changed>`, `<diffs>`/`<file_change>`, `<entry_instruction>`) stays the same — only its delivery moves from stdout to a file.
2. **Script — reconcile `<entry_instruction>` with immutable entries.** Rewrite the trailing `<entry_instruction>` heredoc so it matches the current immutable-entry format in `update_changelog/SKILL.md`: one bullet per logical change in the format `- **Category:** Plain-English summary.`, no `[status]` slot, and no instruction to assign status markers from current code state.
3. **Skill — add a consume protocol.** Add a `<consume_context>` block to `update_changelog/SKILL.md` modeled on `git_commit`'s: default `Read` of the path; paginated `Read` with `offset`/`limit` in sequence until the whole file is covered; ordered `grep`/`awk` slicing only as a last resort for huge days; and a hard rule — **never** re-derive the day with `git log`/`git diff`/`git status` (the script is the sole per-day source), **never** truncate the blob with `head`, and iterate every `<file_change>` in order rather than sampling.
4. Update the `<tools>`/`<prepare_changelog_day>` description and `<procedure>` substeps so they reference the file-path return and the consume protocol instead of "fetch the context blob in one call".
5. Keep the `<consume_context>` block **self-contained** — describe the read protocol inline, in full. Do **not** add a runtime pointer to `git_commit` (or any sibling) in the shipped skill: an agent running `update_changelog` gains nothing from being told to go look at another skill and is more likely to get distracted than helped. `git_commit` is only the implementer's model (see `## Context`); the protocol it demonstrates gets copied into this skill's own prose, not referenced from it.
6. Extend `tests/update_changelog/script_tests/run.sh` so the local harness asserts the script prints a path (not the blob), the path remains readable after script exit, and the context file contains the expected `<changelog_day>` sections plus the immutable-entry `<entry_instruction>` format.

Non-goals: don't change which commits a day selects — that's [changelog_incremental-day-boundaries.md](archive/changelog_incremental-day-boundaries.md); the script's `--after/--before` day window is correct and stays as-is. Don't add a compact/diffs-off mode unless the file-handoff alone proves insufficient — the file path plus paginated read should remove the overflow entirely, matching how `git_commit` handles 1000-file commits.

## Acceptance

- `prepare_changelog_day.sh` prints an absolute file path (+ directive) on stdout and writes the blob to that file; running it on a known-busy day produces no oversized tool-result overflow.
- The printed context-file path remains readable after `prepare_changelog_day.sh` exits; only the script's internal scratch files are cleaned on exit.
- The script's `<entry_instruction>` uses the immutable-entry bullet format and contains no `[status]` slot or current-state status-marker assignment.
- `SKILL.md` carries a `<consume_context>` block with full-read → paginated-read → ordered-slicing and a hard rule against re-deriving via `git log`/`git diff`/`git status` and against `head`-truncating the blob.
- The `<tools>` description and `<procedure>` reference the file-path handoff, not a stdout blob.
- The `<consume_context>` block is self-contained and does **not** reference `git_commit` or any other sibling skill — the protocol is spelled out inline.
- `tests/update_changelog/script_tests/run.sh` covers the file-path handoff, post-exit readability, context-file sections, and immutable-entry `<entry_instruction>` text; the update_changelog script-test harness passes.
