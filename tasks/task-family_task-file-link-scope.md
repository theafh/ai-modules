---
description: "Restrict the task linter's link check to links written in task files, so it never judges links in any other markdown file in the repository."
scope: plugins/ai_dev/skills/task
created: 2026-10-31T15:51:33
updated: 2026-10-31T15:51:33
status: open
reported-by: Andreas Hoffmann
---

# Restrict the Task Linter's Link Check to Task Files

## Goal

`lint.py` checks the links written in task files and only those. Every link in a task file is still resolved and reported when broken, whether it points at another task (live or archived) or at any other in-repo resource outside `tasks/`, such as a source file, a script, a directory, or a document. A markdown file outside the tasks tree is never read by the link check, so a wiki page, a README, or a site's content pages draw no finding from the task linter, whatever they link to. The skills and agents that state the linter's remit say the same, so no agent repairs links outside task files on the linter's behalf.

## Context

- The current remit comes from the archived [task-family_repo-wide-link-integrity](archive/task-family_repo-wide-link-integrity.md), which widened the link walk from task files to every markdown file under the repository root, taking its inventory from `git ls-files` and filtering it by a prune-shaped Makefile `EXCLUDE`. This task reverses that walk and keeps the rest of its work: checking links to non-`.md` targets, silence for links that leave the repository, the repository-root reading of a leading-`/` destination, and skipping fenced code and inline code.
- The widened walk misjudges markdown that is not repository documentation. A website engine's host content links site routes such as `/posts/first-post/`, which the engine resolves from page paths and slugs at request time. The linter reads them as repository-root paths and reports each one as a blocking `broken-link`, so a consuming repository had to add a Makefile `EXCLUDE` solely to silence them. Whether a non-task markdown file's links are valid belongs to that file's own tooling, such as a wiki linter or a host validator.
- In `plugins/ai_dev/skills/task/scripts/lint.py`, `main` builds `link_pages` from `iter_repo_markdown_files(tasks.parent)` on a default or `--include-archive` run and from the scoped file under `--file`, while the other per-file checks iterate `pages` from `iter_task_files`. The inventory helpers behind `iter_repo_markdown_files` are `parse_makefile_exclude`, `is_find_prune_exclude`, `_git_ignores`, `_list_git_markdown_files`, `_list_rglob_markdown_files`, and `_list_find_markdown_files`.
- The remit is stated in prose in the module docstring, the `argparse` description, the `--include-archive` help text, and the `check_local_links` docstring of `lint.py`; in the base `task` skill's `<lint>` passage and its `<markdown_policy>` **Local cross-references are standard markdown links.** bullet; in `task_fix`'s `<authority>` block and its **Remediate.** step ("including broken in-repo links wherever they live"); and in the `auto_shaper_task` rule that begins "Read the base `task` skill and `task_fix` before editing."
- `tests/task/script_tests/run.sh` covers `check_local_links` in its `l*` group, including the repository-wide cases the archived task added.

## Approach

- **Link pages are task files.** Set the link check's page set to the task files the run covers: `iter_task_files(tasks, include_archive=args.include_archive)` on a default or `--include-archive` run, so live task files by default and the archive as well under `--include-archive`, and the scoped file under `--file` as today. This matches the iteration every other per-file check uses, and archive-inclusive link maintenance stays with `task_fix`, the owner of `--include-archive`.
- **Keep link resolution unchanged.** `check_local_links` keeps resolving each link from the linking file's directory and then the project root, checks targets of any file type and directories, treats a leading-`/` destination that does not exist as an absolute path as repository-root-relative, and stays silent for `://`, `mailto:`, empty or fragment-only targets, and paths resolving outside the repository.
- **Remove the repository inventory.** Delete `iter_repo_markdown_files` and every inventory helper only it calls, so the linter no longer reads the Makefile `EXCLUDE` or runs `git ls-files` for link pages. A helper another check still calls stays.
- **Rewrite the remit prose in place.** Supersede the repository-wide wording at every site Context names with the task-file remit stated in Goal, and add no second statement beside the old one.
- **Rewrite the tests.** Turn the `l*` cases that expect findings from non-task markdown files into cases that expect silence, drop the cases that exist only to exercise the Makefile `EXCLUDE` and gitignore inventory, and keep every task-file case.
- Bump the plugin versions this change touches as the repository's standing release rules require.

**Out of scope:**

- The base `task` skill's `<archive>` inbound scan, which re-points links in other repository files when `task_finish` moves a task; it is a close-out edit rather than a linter judgement and stays as it is.
- Removing Makefile `EXCLUDE` entries in this or any consuming repository; `EXCLUDE` keeps serving the repository's own lint targets.

## Acceptance

- A staged fixture whose repository carries a non-task markdown file (for example `wiki/page.md` and `site/content/index.md`) with a dangling relative link and a leading-`/` link to a missing path produces no finding on a default run or an `--include-archive` run, where the current linter reports blocking `broken-link` findings for both.
- A staged live task file that links a missing in-repo non-`.md` file outside `tasks/` produces one blocking `broken-link` finding, and one that links an existing file, an existing directory, a live task, and an archived task produces no finding.
- A staged archived task file with a dangling in-repo link produces one blocking `broken-link` finding under `--include-archive` and none on a default run.
- A staged task file carrying an `https://` URL, a `mailto:` target, and a relative path climbing above the repository root produces no finding for those links.
- Under `--file` naming one task, a dangling link in that task still produces its finding, and a dangling link in another task file does not.
- `rg -n 'iter_repo_markdown_files|parse_makefile_exclude|is_find_prune_exclude' plugins/ai_dev/skills/task/scripts/lint.py` returns nothing.
- `rg -n 'every markdown file under|wherever they live|every in-repo markdown link from every' plugins/ai_dev` returns nothing, and each prose site Context names states that the link check covers the links written in task files only.
- `tests/task/script_tests/run.sh` covers each staged case above in its `l*` group and passes.
