---
description: Widen the task linter to every in-repo markdown link in any repo markdown file, silence outbound links, wire the remit, and land this repository blocking-clean.
scope: plugins/ai_dev/skills/task
created: 2026-09-12T17:31:37
updated: 2026-10-08T21:56:59
status: ready
reported-by: Andreas Hoffmann
---

# Lint every in-repo link from every markdown file, ignore every link that leaves it, wire the remit into the artefacts that state it, and land this repository blocking-clean

## Goal

`lint.py` resolves and reports every markdown link whose target is a file inside
the repository, written in any markdown file under the repo root and whatever
kind of file that link points at. A link that dangles is then caught by the tool
that owns link integrity, rather than surviving until some other linter happens
to look or until a reader follows it. Links that leave the repository stay
silent: an internet URL, a `mailto:`, and a path resolving outside the repo root
draw no finding and no warning, so widening the remit costs no noise. The skills
and agents that consume the linter state the widened remit, so an agent repairing
links knows every markdown file in the repo is in scope. This repository lands
blocking-clean under that widened check.

## Context

Two restrictions in `plugins/ai_dev/skills/task/scripts/lint.py` bound what the
linter can see today. Both are visible in `check_local_links` and in
`iter_task_files`, which feeds it.

**The walk covers task files only.** `iter_task_files` yields live `tasks/*.md`,
extends to `tasks/archive/` under `--include-archive`, and narrows to one file
under `--file`. A link written in any other repo file is never examined, so a
link *into* the tasks tree is unchecked in the direction that breaks most often:
when `task_finish` moves a file to `tasks/archive/`, every outside pointer to it
goes stale at once.

The worked case that prompted this. In a consuming repo, a wiki page carried
`](../../tasks/elcp-intro_stress-test-epoch-boundaries.md)`. `task_finish`
archived that task and re-pointed the inbound links it could see, which is the
tasks tree alone, exactly as
[task-family_archive-inbound-link-scan](archive/task-family_archive-inbound-link-scan.md)
specified. The wiki link dangled for several commits and surfaced only because
that repo also runs a wiki linter with its own broken-link check. A repo
carrying tasks and no wiki linter would keep the dangling link indefinitely.

**Only `.md` targets are checked.** `check_local_links` skips any target that
does not end `.md`, so a task body pointing at a script, a chapter source, a
data file, or a directory gets no check at all. Renaming or moving such a target
breaks the pointer silently. Task bodies in consuming repos do link these: a
tooling script, a `.tex` chapter, a `.bib` bibliography.

What is already settled and stays. Resolution tries the linking file's own
directory and then the project root, which
[task-family_link-resolution-project-root-fallback](archive/task-family_link-resolution-project-root-fallback.md)
established; `://` and `mailto:` targets are already skipped; `#` fragments and
trailing titles are already stripped before resolving. The repeated-link warn
from
[task-family_cross-link-hygiene](archive/task-family_cross-link-hygiene.md)
keeps its current per-file behaviour.

The artefacts that state the linter's remit in prose are the base `task` skill
(the family-wide statement), `task_fix` (a repair pass fixes in-repo links
wherever they live), and `auto_shaper_task` (the escalated writer that runs the
archive-inclusive linter and repairs links). Every other `task_*` sibling and
`auto_*_task` agent inherits that remit through `<authority>` or by citing
those skills, and is rewritten only when it restates a conflicting narrower
remit. `task_finish` inherits the base `<archive>` inbound-scan passage through
`<authority>` and is rewritten only when it restates the inbound scan.
Bundled-script behaviour is tested by `tests/task/script_tests/run.sh`, whose
`l*` group already covers `check_local_links` body-link resolution and is the
group this work extends.

## Approach

Change the linter first, then the prose that describes it.

**Widen the walk to the repository.** Keep every per-file check other than the
link check on task files alone via `iter_task_files`. On the default invocation
and under `--include-archive`, run link resolution over every markdown file
under the repo root. When the repo-root Makefile defines `EXCLUDE`, the
markdown inventory matches `find . $(EXCLUDE) -type f -name '*.md' -print` (the
same derivation `MD_FILES` uses). When the root has no Makefile or that
Makefile defines no `EXCLUDE`, skip only `.git/`. Under `--file`, keep link
checks scoped to the named task file so the archive close-out contract still
sees findings only for that file.
Report a finding against the file that carries the link, so the report says
where to edit. Markdown under `wiki/` stays in that walk.

**Widen the target filter from `.md` to any in-repo path.** Resolve the target
the same way, and treat existence under either root as the test. A target that
resolves to a directory counts as present.

**Make leaving the repo the silence rule.** A target draws no finding when it
carries `://`, starts with `mailto:`, is empty or fragment-only, or resolves
outside the repo root once normalised, which covers an absolute path elsewhere
on the machine and a relative path climbing past the root. State the rule once
in the function's docstring so the exclusion is readable next to the check.

**Rewrite the linter's own remit prose.** Rewrite in place `lint.py`'s module
docstring and the argparse `description=` string that today frame the tool as a
tasks-directory health-check, so both state the widened link-check remit
(repo-wide markdown sources on a default or `--include-archive` run, any in-repo
target, silence outside) while the other per-file checks remain task-scoped as
they are today.

**Scrub fences and inline code before resolving links.** Run the widened link
check over body text with fenced code blocks and inline code removed, reusing
`_scrub_code` (already used by the footnote and wikilink checks), so a markdown
link that appears only inside a fenced example or an inline-code span draws no
finding. That matches the wiki linter's broken-link check, which already skips
both surfaces.

**Wire the remit into the consumers.** In the base `task` skill, `task_fix`,
and `auto_shaper_task`, state that, on a default or `--include-archive` run, the
link check covers every in-repo markdown link from every markdown file under the
repo and ignores everything outside, and that under `--file` the link check
stays scoped to the named task file alone. Leave every other `task_*` sibling
and every other `auto_*_task` agent to inherit that remit through `<authority>`
with no remit copy, rewriting them only when they restate a conflicting narrower
remit. In the base `task` skill, also rewrite in place the `<lint>`
default-iteration passage (the sentence that today frames the default walk as
live `tasks/*.md` only) and the `<markdown_policy>` **Local cross-references**
bullet (the sentence that today limits blocked broken targets to relative `.md`
links among task files under `tasks/` or `tasks/archive/`), so each states the
widened link-check remit (repo-wide markdown sources on a default or
`--include-archive` run, any in-repo target, silence outside; under `--file`,
link checks stay scoped to the named task file) rather than the narrower
tasks-and-`.md`-only wording. Two surfaces carry more than that description:
`task_fix` owns tree repair and states that a repair pass fixes in-repo links
wherever they live, and
the base `task` skill's `<archive>` inbound-scan passage (the sentence that
today tells the closer to scan the whole tasks tree for inbound links to the
moving file) is rewritten in place so archiving re-points inbound links across
the repository rather than across the tasks tree alone, superseding the
tasks-tree-only wording the archived inbound-link-scan task named in Context put
there. `task_finish` inherits that passage through `<authority>` and is
rewritten only when it restates the inbound scan.

**Cover the behaviour in the script tests.** Extend the `l*` group in
`tests/task/script_tests/run.sh` with the cases Acceptance names, following the
scratch-fixture pattern its neighbours use.

**Land this repository blocking-clean.** Clear every reported blocking
`broken-link` finding under the widened check by re-pointing or otherwise
repairing the link. Scrub every illustrative skill example whose live markdown
link would produce a blocking `broken-link` finding under the widened check.
Reserve the Makefile `EXCLUDE` rule already named above for deliberate
dangling-link fixture trees only; prune or exclude those trees from the
markdown inventory so they contribute no finding. A default or
`--include-archive` run over this repository ends with zero blocking
`broken-link` findings.

**Out of scope:**

- Changing the wiki linter at
  `plugins/knowledge_management/skills/wiki/scripts/lint.py`, a separate tool
  with its own link check and its own repo walk; its findings stay its own.
- Whether a resolving link points at the *right* file. This task checks that a
  target exists, not that the prose around it is accurate.
- Liveness of external URLs and DOIs, which stay out by the silence rule above.
- Changing how `scope:` frontmatter resolves, which keeps the behaviour the
  archived project-root-fallback task named in Context settled.

## Acceptance

- A staged fixture under `wiki/` where a page links a path under `tasks/` that
  does not exist produces one blocking `broken-link` finding naming that wiki
  page on a default run, where the current linter reports nothing.
- A staged fixture where a non-task `.md` file under the repo root with no task
  frontmatter produces no findings from any per-file check other than the link
  check on a default run; the fixture carries footnote, wikilink, soft-pointer,
  and repeated-link surfaces that would fire if those checks ran on that file.
- A staged fixture where a task body links an existing non-`.md` in-repo file
  produces no finding, and one where it links a missing non-`.md` in-repo file
  produces one blocking `broken-link` finding, where the current linter reports
  nothing in both cases.
- A staged fixture carrying an `https://` URL, a `mailto:` target, an absolute
  path outside the repo root, and a relative path climbing above the root
  produces no finding of any severity for those four links.
- A staged fixture where a link resolves to an existing directory produces no
  finding.
- A staged fixture where the root Makefile's `EXCLUDE` prunes a uniquely named
  directory and a dangling in-repo link sits under that directory produces no
  finding for that link on a default or `--include-archive` run.
- A staged fixture whose project root has no Makefile `EXCLUDE` and that
  carries a dangling in-repo link outside `.git/` produces one blocking
  `broken-link` finding for that link on a default or `--include-archive` run.
- Under `--file` naming one task, a dangling in-repo link in a different repo
  markdown file produces no finding, while a dangling in-repo link in the named
  file still produces its finding.
- A staged fixture where a fenced code block contains a markdown link to a
  missing in-repo path produces no finding.
- A staged fixture where an inline-code span contains a markdown link to a
  missing in-repo path produces no finding.
- `check_local_links`'s docstring states the silence rule: a target that carries
  `://`, starts with `mailto:`, is empty or fragment-only, or resolves outside
  the repo root draws no finding.
- `lint.py`'s module docstring and argparse description supersede the
  tasks-directory-only remit wording: each states the widened link-check remit
  above while still describing the task-scoped per-file checks.
- `tests/task/script_tests/run.sh` covers each of the staged-fixture cases above
  in its `l*` group and passes.
- Every illustrative skill example in this repository whose live markdown link
  would produce a blocking `broken-link` finding under the widened check is
  scrubbed so that link is no longer a live dangling markdown link (its target
  exists, or the markdown link is removed or confined to a fenced/inline-code
  surface the widened check already ignores).
- Every deliberate dangling-link tree in this repository is pruned from the
  markdown inventory via the root Makefile `EXCLUDE` (or removed from the tree)
  so it contributes no finding on a default or `--include-archive` run.
- Running the linter over this repository (default or `--include-archive`)
  produces zero blocking `broken-link` findings.
- The base `task` skill, `task_fix`, and `auto_shaper_task` each state that, on
  a default or `--include-archive` run, the link check covers every in-repo
  markdown link from every markdown file under the repo and ignores every target
  outside the repo, and that under `--file` the link check stays scoped to the
  named task file alone.
- The base `task` skill's `<lint>` default-iteration passage and
  `<markdown_policy>` **Local cross-references** bullet each supersede their
  tasks-tree / `.md`-only remit wording with the widened link-check remit above.
- `task_fix` states that a repair pass fixes in-repo links wherever they live,
  and the base `task` skill's `<archive>` inbound-scan passage supersedes its
  tasks-tree-only wording with repository-wide re-pointing (`task_finish`
  inherits that passage through `<authority>` and is rewritten only when it
  restates the inbound scan).
