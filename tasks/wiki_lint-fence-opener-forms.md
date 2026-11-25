---
description: "Point every fence consumer in the wiki lint.py at the fence_delimiter/FENCE_OPEN_RE state machine so four-backtick and tilde fences hide their content, pinned by layer-1 scenarios."
scope: plugins/knowledge_management/skills/wiki
created: 2026-11-25T06:11:12Z
updated: 2026-11-25T08:07:53Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Make every fence consumer in the wiki lint honour four-backtick and tilde fence openers

## Goal

Every body scanner in `plugins/knowledge_management/skills/wiki/scripts/lint.py` treats a fence opened by three or more backticks or three or more tildes, with any info string, as a code block and leaves its content unread. A wiki page that documents a deprecated body `Sources` heading, a wikilink-style reference, and a footnote-style reference inside a four-backtick example lints clean, while the same lines outside a fence still draw their `sources-section`, `wikilink`, and `footnote` findings.

One fence definition serves the whole file. The narrow `FENCE_RE` matcher is superseded by the `FENCE_OPEN_RE` / `fence_delimiter` state machine that `check_heading_label` already uses, and `strip_fenced_blocks` is rebuilt on that state machine so its own consumers inherit the fix.

This is a pre-existing defect in a shared matcher, not a regression from recent work: the consumer lines are unmodified at HEAD.

## Context

`plugins/knowledge_management/skills/wiki/scripts/lint.py` carries two competing notions of a fence.

The narrow one is `FENCE_RE = re.compile(r"^```(\w*)\s*$")`. It matches a three-backtick opener carrying an optional word-only info string and nothing else, so a four-backtick opener, a tilde opener, a longer fence, and an opener whose info string carries non-word characters such as `c++` or `objective-c` all fail to match.

The accurate one is the `FENCE_OPEN_RE = re.compile(r"^(?P<run>`{3,}|~{3,})(?P<info>.*)$")` pattern plus the `fence_delimiter` state machine beside it. It tracks the opener's character and run length and closes only on the same character at an equal or longer run, so a four-backtick block, a tilde block, and a triple-backtick example nested inside a longer fence all stay content. `check_heading_label` already drives its line loop through `fence_delimiter`, which is why headings and bold labels inside those fences are already skipped.

The consumers still on `FENCE_RE` are:

- `iter_lint_section_lines`, the `## Lint` section scan of `SCHEMA.md`.
- `check_taxonomy_style`, over the `## Tag Taxonomy` block.
- `strip_fenced_blocks`, which `strip_code` builds on, so `check_links_and_orphans`, `check_index_completeness`, and `check_synthesis_citation` reach it through `strip_code`.
- `check_sources_section`.
- `check_footnote_syntax`.
- `check_wikilink_syntax`.
- `check_markdown_style`, which uses the match's group as the language identifier for its missing-language finding and as the toggle for its blank-line, bullet, and heading-level checks.

The failure reproduces by loading the module and calling `strip_code` on a page whose four-backtick `markdown` block holds the three example lines below: all three survive into the stripped text. A page documenting those forms inside a four-backtick example therefore draws `sources-section`, `wikilink`, and `footnote` findings against its own documentation.

The fixture content, shown as the lines a staged page carries inside its fence:

```text
## Sources
[[wiki link]]
[^fn]
```

The blast radius covers every scanner above plus the graded scenarios that depend on them, which is why this work needs its own session rather than riding along with an adjacent change.

## Approach

1. **Keep one opener definition and delete the other.** `FENCE_OPEN_RE` plus `fence_delimiter` is the definition this file keeps. Remove `FENCE_RE` and rebuild `strip_fenced_blocks` on the state machine, so the text-level stripper and every per-line scanner agree on where a fence starts and ends. Rewrite the `strip_fenced_blocks` docstring in place: its claim to mirror the body scanners becomes a statement that it drives the shared state machine.

2. **Point each per-line consumer at the state machine.** Replace each `FENCE_RE.match(line.strip())` toggle in `iter_lint_section_lines`, `check_taxonomy_style`, `check_sources_section`, `check_footnote_syntax`, and `check_wikilink_syntax` with the `in_fence, is_delimiter = fence_delimiter(line, in_fence)` step `check_heading_label` already performs, keeping each scanner's existing skip order so a delimiter line is dropped and fenced content is skipped before any per-line scrubbing runs.

3. **Carry the language-identifier check across.** `check_markdown_style` needs the opener's info string, which `fence_delimiter` does not return. Read it from `FENCE_OPEN_RE`'s `info` group when the state machine reports a delimiter that opens a block, and keep the existing behaviour: an opener with an empty info string still draws the missing-language `md-style` finding, a closing delimiter draws nothing, and a four-backtick opener with an info string such as `markdown` draws nothing.

4. **Reuse the helper rather than duplicating it.** `check_heading_label` already calls `fence_delimiter`; leave that call as it is and add no second fence regex, no parallel state machine, and no per-consumer copy of the opener pattern.

5. **Pin the behaviour in the layer-1 harness.** Add scenarios to `tests/wiki/layer1/run.sh` in the existing `l*` shape, registering each with a `scenario` line and writing its body next to the neighbouring `l*` helpers. Stage a page whose four-backtick, tilde, and five-backtick fences hold the three example lines from `## Context` plus consecutive blank lines, plus a control page carrying the same lines unfenced, plus the coverage set step 6 names.

6. **Cover every named consumer in the fixture set.** The scenarios exercise the `## Lint` section scan through a staged `SCHEMA.md`, `check_taxonomy_style` through a fenced `## Tag Taxonomy` block, `strip_fenced_blocks` through `strip_code`, and the syntax checks plus `check_markdown_style` through page bodies, so each consumer named in `## Context` is proven on a four-backtick or tilde fence rather than only on the shared helper.

7. **Re-run the graded surfaces and read the verdicts.** The shared matcher changes what every fence-aware scenario sees, so the full layer-1 run and the lint-dependent layer-2 set both need a fresh pass, as `## Acceptance` states.

**Out of scope:** Changing what counts as a finding, adding a new check, or changing any scanner's severity. This task changes only where a fence begins and ends. Rewriting pages or fixtures that currently rely on the narrow matcher, and the fence conventions documented in the wiki skill's prose, both stay out because the shipped behaviour after this task is the one those documents already describe.

## Acceptance

- A layer-1 fixture page whose four-backtick `markdown` fence holds the three example lines from `## Context` plus two consecutive blank lines draws none of `sources-section`, `wikilink`, `footnote`, or `md-style`.
- A control page carrying those same lines outside any fence still draws `sources-section`, `wikilink`, and `footnote`, so the suppression is fence-scoped rather than global.
- A tilde fence and a five-backtick fence holding the same lines draw none of those findings, and a triple-backtick run nested inside a four-backtick fence stays content rather than closing it.
- An opener whose info string carries non-word characters, such as a `c++` or `objective-c` fence, opens a block: its content is skipped and no missing-language `md-style` finding fires against it.
- The fixture set proves each consumer named in `## Context` individually: the `## Lint` section scan on a staged `SCHEMA.md`, `check_taxonomy_style` on a fenced taxonomy block, `strip_fenced_blocks` through `strip_code`, `check_sources_section`, `check_footnote_syntax`, `check_wikilink_syntax`, and `check_markdown_style`.
- `grep -n "FENCE_RE" plugins/knowledge_management/skills/wiki/scripts/lint.py` returns no match, and `fence_delimiter` with `FENCE_OPEN_RE` is the only fence opener definition left in the file, so the prior narrow matcher is superseded and no second definition accumulates.
- `bash tests/wiki/layer1/run.sh` passes with the new scenarios registered and every pre-existing scenario green, including the lint scenarios that pin wikilink, deprecated-Sources, footnote, code-fence, fenced-acceptance, log-scope, fenced-declare, and citation-example behaviour.
- The lint-dependent layer-2 scenarios pass, selected at implementation time from `tests/wiki/layer2/evals.json` by the scenarios whose request, constraints, or assertions name lint behaviour, at the `passes` count that file declares. The run's printed verdict table is the record, and a scenario that regresses is reported with its failing assertion rather than repaired by relaxing the grader or the scenario.
