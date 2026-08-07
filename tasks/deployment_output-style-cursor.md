---
description: Test whether Cursor loads rules from a home-directory rules folder, then deploy the output style there as an always-applied rule file or fall back to project scope.
scope: deployment
created: 2026-08-07T23:39:03
updated: 2026-08-07T23:39:03
status: open
reported-by: Andreas Hoffmann
---

# Deploy the output style to Cursor as an always-applied rule

## Goal

Cursor receives the repository's output style as a generated rule file, deployed by the same `style` artefact type the groundwork task adds. The task opens by settling one unverified question, because the answer decides whether Cursor is a machine-wide target or a project-scoped one, and both outcomes are in scope: the deploy either writes a global rule file or writes a project rule file and documents the manual step for the global case.

## Context

This builds on [the Claude groundwork task](deployment_output-style-claude-groundwork.md), which creates the repo-root source directory, the `style` artefact type, and the deploy-log restore behaviour. Ship that first; this task adds one target and no new machinery.

The `harness_portability` skill records what is known, in the `<cursor_counterparts>` block of its `<claude_output_styles>` section. The essentials: rules are Markdown with frontmatter selecting one of four activation modes, an applied rule is included at the start of the model context rather than replacing anything, and `alwaysApply: true` is the mode corresponding to a standing voice. Cursor is therefore an append-only target, so the deployed prose competes with Cursor's own default guidance instead of displacing it as a Claude style does. Say so in the docs rather than presenting the variant as equivalent.

The open question is whether a rules file in a home-directory `rules` folder under Cursor's user configuration tree is loaded. Two Cursor documentation pages describe user-level rules as living in the application's settings rather than as files, and an exhaustive enumeration of every path on the customization help page returns only project-scoped paths plus `AGENTS.md`, `CLAUDE.md`, and the legacy `.cursorrules`. Against that, the directory exists on at least one machine running Cursor, and the reporting user believes it works. Neither settles it, so the task starts by testing it.

## Approach

Begin with the empirical check. Place a Markdown rule file carrying `alwaysApply: true` and a distinctive, easily observed instruction in the home-directory rules folder under Cursor's user configuration tree, start a fresh Cursor chat in a project that has no rules of its own, and observe whether the instruction takes effect. Record the result in the task's implementation notes and in the harness skill's `<cursor_counterparts>` block, replacing the current unverified wording with the finding and the date, so the next reader inherits evidence rather than the same question.

When the check confirms the folder is loaded, deploy there: generate a Cursor variant of the style as an `.mdc` file with frontmatter setting `alwaysApply: true`, and write it into that folder as a global deposit needing no activation key. When the check shows it is not loaded, deploy instead into a project's own rules directory during a project-scoped deploy run, and document that the machine-wide equivalent is a manual paste into Cursor's settings, which no deploy step can write.

Either way the variant is generated rather than copied. Strip the Claude frontmatter, which Cursor does not implement, and emit Cursor's own frontmatter in its place. Rewrite the one clause in the style body that names Claude's `keep-coding-instructions` mechanism, since that mechanism does not exist here; the existing per-tool substitution facility in `deployment/deployment.conf` is the intended way to vary that clause per target.

**Out of scope:**

- The source directory, the `style` artefact type, and the log restore behaviour, all owned by [the Claude groundwork task](deployment_output-style-claude-groundwork.md).
- Cursor's team rules and its settings-stored user rules, neither of which a deploy step can write.

## Acceptance

- The empirical result for the home-directory rules folder is recorded in the harness portability skill's `<cursor_counterparts>` block with the date and the Cursor version tested, replacing the current unverified wording rather than sitting beside it.
- A dry run restricted to the style type and the Cursor target reports the file write the recorded result implies, at the scope that result selects.
- A real deploy produces a rule file that parses as Markdown with YAML frontmatter and carries `alwaysApply: true`.
- The deployed file contains no Claude output-style frontmatter keys, verified by searching it for `keep-coding-instructions` and `force-for-plugin` and finding neither.
- The deployed body contains no reference to Claude's keep-coding-instructions mechanism, and the clause that named it reads correctly for a harness that only appends.
- Uninstalling removes the deployed rule file and leaves any pre-existing rule files in the same folder untouched.
- `deployment/README.md` gains a Cursor row for the style type naming the deploy path the recorded result selected, and states that Cursor appends rather than replaces, so adherence is weaker than on Claude.
