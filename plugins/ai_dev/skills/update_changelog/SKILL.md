---
name: update_changelog
description: Create or update a day-grouped CHANGELOG.md from git commit history. Use when asked to generate, refresh, or maintain a repository changelog. Produces newest-first day sections with status markers ([active], [changed later], [superseded]) and processes one day at a time to stay within context limits.
version: 3.0.0
author: Andreas F. Hoffmann
license: MIT
---

# update_changelog

<update_changelog_skill>
  <objective>Create or update a `CHANGELOG.md` in the repository root: a human-readable, day-grouped history derived from git commits, newest day first, with per-entry status markers reflecting current code state.</objective>
  <command_intent>build CHANGELOG.md, refresh changelog from git history, add the missing days to the changelog</command_intent>
  <tools>
    <prepare_changelog_day>Run `scripts/prepare_changelog_day.sh YYYY-MM-DD` from this skill when it is available. The script emits one structured context blob for a single calendar day with the day's commit subjects and bodies, the deduplicated repo-relative file list, and per-file net diffs for the day, plus generic placeholders for binary files. Exits 1 with `no commits on <date>` when the date has no commits — skip silently.</prepare_changelog_day>
  </tools>
  <output_contract>
    <header>The file always begins with the H1 `# CHANGELOG — {Project Name}`, then a blank line, then the status-marker legend line that names `[active]` (present in current code), `[changed later]` (still present but evolved), and `[superseded]` (replaced or removed), then the line stating that entries are grouped strictly by day and kept on their original implementation dates. Substitute `{Project Name}` from the repo directory name, `package.json`, `Cargo.toml`, or the README's H1.</header>
    <day_section>One `## YYYY-MM-DD — {Day theme}` heading per calendar day that has commits, ordered newest-first. `{Day theme}` is a 2-5 word editorial summary of that day's dominant focus. End every day section with a horizontal rule (`---`).</day_section>
    <entry_line>One bullet per logical change inside the day section in the format `- [status] **Category:** Plain-English summary of the change.`.</entry_line>
    <status_markers>`[active]` — described behavior or code is present and current. `[changed later]` — still present but meaningfully evolved since this entry was written. `[superseded]` — replaced, removed, or made obsolete by later work.</status_markers>
    <categories>`Implementation/runtime` for new user-facing features or runtime behavior. `Refactor` for structural code reorganization without behavior change. `Refactor/perf` or `Perf/runtime` for performance-motivated changes. `Refactor/runtime reliability` for reliability and resilience improvements. `Docs/specs-only` for documentation or specification changes with no code effect.</categories>
    <files_changed_line>End every day section with a files-changed bullet listing every path the day touched, repo-relative, backtick-wrapped, comma-separated, deduplicated. Shape: a `- **Files changed:**` prefix followed by each path wrapped in single backticks and separated by a comma plus a space.</files_changed_line>
  </output_contract>
  <policy>
    <context_safety>Process one day at a time and append each completed day section to `CHANGELOG.md` before moving to the next. Treat already-written days as committed output and let them fall out of working context. Repository histories can exceed any context window when read at once.</context_safety>
    <newest_first>Maintain strict newest-first day ordering. When updating an existing changelog, insert new day sections directly after the header.</newest_first>
    <one_entry_per_logical_change>Squash related commits into a single bullet. Write one entry per logical change, not per commit.</one_entry_per_logical_change>
    <date_immutability>Keep entries on their original implementation date forever. Update the status marker on later runs; never move the entry.</date_immutability>
    <summary_style>Write summaries in plain English, past tense, describing what was done. Leave why and how out of the summary. Stay concise but specific enough that a reader unfamiliar with the codebase understands the scope.</summary_style>
    <preserve_existing>Preserve existing day sections in place. Add new sections and update status markers; do not rewrite prior summaries.</preserve_existing>
    <model_authority>The model owns summarization, day-theme composition, category assignment, and status-marker evaluation. Use script output as evidence and execution support.</model_authority>
    <workflow_authority>Treat this skill as the source of truth for `/update_changelog` workflow, output format, and entry style.</workflow_authority>
  </policy>
  <procedure>
    <resolve_project_name>Resolve `{Project Name}` from the repository directory name, an existing project title in the README's H1, the `name` field of `package.json` or `Cargo.toml`, or another canonical project metadata file.</resolve_project_name>
    <enumerate_dates>Run `git log --reverse --format='%ad' --date=short --no-merges | sort -u` to list every distinct commit date in the repository, oldest-first. When updating an existing changelog, drop dates already covered by the most recent day section in `CHANGELOG.md`.</enumerate_dates>
    <ensure_header>If `CHANGELOG.md` does not exist, create it with the header block. If it exists, leave the header in place.</ensure_header>
    <day_loop>
      For each remaining date, oldest-first:
      <substeps>
        <substep>Run `scripts/prepare_changelog_day.sh YYYY-MM-DD` to fetch that day's context blob in one call. If the script exits 1, skip the date silently.</substep>
        <substep>Read every `<commit>` and `<file_change>` block. Aggregate related changes into logical entries, choose categories, compose a 2-5 word day theme, and assign status markers by checking each entry against the current state of the codebase.</substep>
        <substep>Build the day section from the day theme, the entry bullets, and the `- **Files changed:** ...` bullet using the paths from `<files_changed>`. End the section with `---`.</substep>
        <substep>Insert the completed day section directly after the header block in `CHANGELOG.md`. Flush to disk before composing the next day so prior detail can fall out of working context.</substep>
      </substeps>
    </day_loop>
    <status_re_evaluation>After all new days are written, re-evaluate status markers on every existing entry section-by-section. Promote `[active]` entries to `[changed later]` when the behavior is still present but has evolved, and to `[superseded]` when later work replaced or removed it. Leave entry text and dates unchanged.</status_re_evaluation>
  </procedure>
</update_changelog_skill>
