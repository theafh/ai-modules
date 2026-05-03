---
name: update_changelog
description: Create or update a day-grouped CHANGELOG.md from git commit history. Use when asked to generate, refresh, or maintain a repository changelog. Produces newest-first day sections with status markers ([active], [changed later], [superseded]) and processes one day at a time to stay within context limits.
version: 2.0.0
author: Andreas F. Hoffmann
license: MIT
---

# update_changelog

Create or update a `CHANGELOG.md` in the repository root. The changelog is a human-readable, day-grouped history derived from git commits.

## Output format

### Header

```markdown
# CHANGELOG — {Project Name}

Status markers: `[active]` = present in current code, `[changed later]` = still present but evolved, `[superseded]` = replaced or removed.
Entries are grouped strictly by day and kept on their original implementation dates.
```

Derive `{Project Name}` from the repository directory name or an existing project title (README heading, `Cargo.toml` name, `package.json` name, etc.).

### Day sections

Use one `## YYYY-MM-DD — {Day theme}` heading per calendar day that has commits. Order sections newest-first. End each section with a horizontal rule (`---`).

`{Day theme}` is a short (2-5 word) editorial summary of that day's dominant focus.

### Entries

Write each bullet inside a day section using this pattern:

```markdown
- [status] **Category:** Plain-English summary of the change.
```

**Status markers** — assign per entry and retroactively update on subsequent runs:

- `[active]` — the described behavior or code is present and current.
- `[changed later]` — still present but meaningfully evolved since this entry was written.
- `[superseded]` — replaced, removed, or made obsolete by later work.

**Categories** — pick the most specific match:

- `Implementation/runtime` — new user-facing features or runtime behavior.
- `Refactor` — structural code reorganization without behavior change.
- `Refactor/perf` or `Perf/runtime` — performance-motivated changes.
- `Refactor/runtime reliability` — reliability/resilience improvements.
- `Docs/specs-only` — documentation or specification changes with no code effect.

### Files-changed line

End every day section with a files-changed bullet:

```markdown
- **Files changed:** `file_a.rs`, `file_b.html`, `src/handlers.rs`
```

Write paths repo-relative, backtick-wrapped, comma-separated, and deduplicated across all commits of that day.

## Workflow

**Critical: context-safe iterative processing.** A full repository history can easily exceed any context window. Process and **write one day at a time** in a loop, flushing each day section to disk before moving on. Treat previously written days as committed output; let them fall out of working context.

### Creating a new changelog

1. List all distinct commit dates in chronological order:

   ```bash
   git log --reverse --format='%ad' --date=short | sort -u
   ```

2. Write the header block to `CHANGELOG.md`.
3. **Loop over each date, oldest-first:**
   1. Gather that day's commits and diffs:

      ```bash
      git log --after="YYYY-MM-DDT00:00:00" --before="YYYY-MM-DDT23:59:59" ...
      ```

   2. Analyze the diffs: aggregate related commits into logical changes, assign categories, collect changed files.
   3. Assign status markers by comparing each entry against the current state of the codebase.
   4. Compose the day-theme summary.
   5. **Append the completed day section to `CHANGELOG.md` immediately.** Flush to disk before composing the next day.
   6. Move to the next date. Release the previous day's details from working memory.
4. After all days are written, reverse the day sections in the file to achieve newest-first ordering. Alternatively, prepend each new day section directly after the header during the loop to build in newest-first order from the start.

### Updating an existing changelog

1. Determine the date of the most recent day section already in the file.
2. List all distinct commit dates after that date.
3. **Loop over each new date using the same day-at-a-time procedure** from step 3 of "Creating a new changelog." Insert each new day section after the header block to maintain newest-first order.
4. After all new days are added, re-evaluate status markers on **all** existing entries: scan the current codebase to check whether previously `[active]` entries should become `[changed later]` or `[superseded]`. Process this pass section-by-section to stay within context limits.

## Rules

- Write one entry per logical change, not per commit. Squash related commits into a single bullet.
- Keep entries on their **original implementation date** forever, even when their status changes.
- Write summaries in plain English, past tense, and describe *what* was done. Leave *why* and *how* out of the summary.
- Keep summaries concise but specific. A reader unfamiliar with the codebase should understand the scope of each change.
- Preserve existing entries in place. Add new sections and update status markers only.
- Maintain strict newest-first day ordering.
