---
name: update_changelog
description: Create or update a day-grouped, add-only CHANGELOG.md from git commit history. Use when asked to generate, refresh, or maintain a repository changelog. Produces newest-first day sections while keeping existing entries immutable and processes one day at a time to stay within context limits.
version: 3.0.2
author: Andreas F. Hoffmann
license: MIT
---

# update_changelog

<update_changelog_skill>
  <objective>Create or update a `CHANGELOG.md` in the repository root: a human-readable, day-grouped, add-only history derived from git commits, newest day first. Record later committed changes as new entries or day sections while preserving existing entries as immutable historical facts.</objective>
  <command_intent>build CHANGELOG.md, refresh changelog from git history, add the missing days to the changelog</command_intent>
  <tools>
    <prepare_changelog_day>Run `scripts/prepare_changelog_day.sh YYYY-MM-DD` from this skill when it is available. The script emits one structured context blob for a single calendar day with the day's commit subjects and bodies, the deduplicated repo-relative file list, and per-file net diffs for the day, plus generic placeholders for binary files. Exits 1 with `no commits on <date>` when the date has no commits — skip silently.</prepare_changelog_day>
  </tools>
  <output_contract>
    <header>The file always begins with the H1 `# CHANGELOG — {Project Name}`, then a blank line, then the line stating that entries are grouped strictly by day, kept on their original implementation dates, and immutable once written. Substitute `{Project Name}` from the repo directory name, `package.json`, `Cargo.toml`, or the README's H1.</header>
    <day_section>One `## YYYY-MM-DD — {Day theme}` heading per calendar day that has commits, ordered newest-first. `{Day theme}` is a 2-5 word editorial summary of that day's dominant focus. End every day section with a horizontal rule (`---`).</day_section>
    <entry_line>One bullet per logical change inside the day section in the format `- **Category:** Plain-English summary of the change.`.</entry_line>
    <categories>`added` for new features or capabilities. `changed` for behavior that differs from before. `deprecated` for retired or removed behavior, or behavior kept only for legacy use. `refactored` for the same output from the same input with faster, more robust, or less buggy internals. `docs` for documentation- or specification-only changes. Express replacement or removal as a `deprecated` or `changed` entry on the date that later work happened.</categories>
    <files_changed_line>End every day section with a files-changed bullet listing every path the day touched, repo-relative, backtick-wrapped, comma-separated, deduplicated. Shape: a `- **Files changed:**` prefix followed by each path wrapped in single backticks and separated by a comma plus a space.</files_changed_line>
  </output_contract>
  <policy>
    <run_scope>Build each run from committed git history only; ignore uncommitted and untracked working-tree state. On incremental runs, treat the most recent recorded day as provisionally complete because commits can share that calendar day after its section was first written. Reopen that day and every later committed date; days older than the most recent recorded day are settled for that run.</run_scope>
    <context_safety>Process one day at a time and flush each completed day section to `CHANGELOG.md` before moving to the next. Treat already-written days as committed output and let them fall out of working context. Repository histories can exceed any context window when read at once.</context_safety>
    <newest_first>Maintain strict newest-first day ordering. When updating an existing changelog, insert new day sections directly after the header and update the reopened most recent recorded day in place.</newest_first>
    <one_entry_per_logical_change>Squash related commits into a single bullet. Write one entry per logical change, not per commit.</one_entry_per_logical_change>
    <date_immutability>Keep entries on their original implementation date forever. Treat each existing entry's date, text, and category as frozen once written. Record later committed changes only as new entries on the dates those changes happened.</date_immutability>
    <summary_style>Write summaries in plain English, past tense, describing what was done. Leave why and how out of the summary. Stay concise but specific enough that a reader unfamiliar with the codebase understands the scope.</summary_style>
    <preserve_existing>Preserve existing day sections and entries in place. Add new day sections or entries for later committed changes while keeping existing entry dates, text, and categories unchanged. For the reopened most recent recorded day, follow `<last_recorded_day_reconciliation>` instead of regenerating the section.</preserve_existing>
    <last_recorded_day_reconciliation>When an incremental run reprocesses the most recent recorded day, compare that day's committed history with the existing section. Keep every existing entry's date, category, and text unchanged; add entries for newly found logical changes, extend the `- **Files changed:**` line with missing paths, and revise the day theme only when the added commits change the day's dominant focus.</last_recorded_day_reconciliation>
    <model_authority>The model owns summarization, day-theme composition, and category assignment. Use script output as evidence and execution support.</model_authority>
    <workflow_authority>Treat this skill as the source of truth for `/update_changelog` workflow, output format, and entry style.</workflow_authority>
  </policy>
  <procedure>
    <resolve_project_name>Resolve `{Project Name}` from the repository directory name, an existing project title in the README's H1, the `name` field of `package.json` or `Cargo.toml`, or another canonical project metadata file.</resolve_project_name>
    <enumerate_dates>Build the date list from committed history. When `CHANGELOG.md` does not exist, run `git log --reverse --format='%ad' --date=short --no-merges | sort -u` to list every distinct commit date in the repository, oldest-first. When updating an existing changelog, read from the top only until the first `## YYYY-MM-DD` heading; because the changelog is newest-first, that heading is the most recent recorded day `D`. Then run `git log --reverse --format='%ad' --date=short --no-merges --since={D}T00:00:00 | sort -u` (or an equivalent committed-history query) to list `D` and every later distinct commit date. Keep `D` in the list because same-day commits can land after its section was written.</enumerate_dates>
    <ensure_header>If `CHANGELOG.md` does not exist, create it with the header block. If it exists, leave the header in place.</ensure_header>
    <day_loop>
      For each selected date, oldest-first:
      <substeps>
        <substep>Run `scripts/prepare_changelog_day.sh YYYY-MM-DD` to fetch that day's context blob in one call. If the script exits 1, skip the date silently.</substep>
        <substep>Read every `<commit>` and `<file_change>` block. Aggregate related changes into logical entries, choose categories, and compose a 2-5 word day theme.</substep>
        <substep>Build the day section from the day theme, the entry bullets, and the `- **Files changed:** ...` bullet using the paths from `<files_changed>`. End the section with `---`.</substep>
        <substep>For a new day, insert the completed day section directly after the header block in `CHANGELOG.md`. For the reopened most recent recorded day, reconcile the existing section in place per `<last_recorded_day_reconciliation>`. Flush to disk before composing the next day so prior detail can fall out of working context.</substep>
      </substeps>
    </day_loop>
  </procedure>
</update_changelog_skill>
