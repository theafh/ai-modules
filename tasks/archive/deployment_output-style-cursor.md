---
description: Deploy the output style to Cursor as a project always-apply .mdc rule; on --global report that no print-mode-injecting machine-wide file path exists and name the settings User Rules paste.
scope: deployment
created: 2026-08-07T21:39:03Z
updated: 2026-10-07T07:14:15Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Deploy the output style to Cursor as a project always-apply rule

## Goal

Cursor receives the repository's output style as a generated always-apply `.mdc`
rule under the project's `.cursor/rules/` directory, deployed by the same `style`
artefact type the groundwork task adds. Under `--project-dir` that write is the
deliverable and ships unconditionally. Under `--global` the run reports that
Cursor has no print-mode-injecting machine-wide rule-file path and names the
manual Customize → Rules paste, because the home `rules/` folder and a user-local
plugin's always-apply rule both failed injection on the settled probe.

## Context

This builds on [the Claude groundwork task](deployment_output-style-claude-groundwork.md),
which created the repo-root source directory, the `style` artefact type, and the
deploy-log restore behaviour. This task adds one target and no new machinery.

The wiki records the harness facts on its [Cursor](../../wiki/entities/cursor.md)
page, in [output style delivery design](../../wiki/concepts/output-style-delivery-design.md),
and in [system prompt substitution across harnesses](../../wiki/comparisons/system-prompt-substitution-across-harnesses.md).
Rules are append-only: an applied rule is included at the start of context and
replaces nothing. Cursor has no `keep-coding-instructions` flag; when
`alwaysApply` is `true`, `description` and `globs` are ignored, so they cannot
stand in for a prose-versus-code split. The style body's `<prose>` and
`<verbatim_content>` clauses already name that split; the Cursor variant must
rewrite `<engineering_behavior>` so it no longer names Claude's flag.

Print-mode probes on 6 October 2026 against agent CLI `2026.10.01` settled the
global question
([probes](../../wiki/raw/notes/cursor-style-injection-probes-2026-10-06.md)):

- Project `.cursor/rules/*.mdc` with `alwaysApply: true` injects.
- The same file under the user configuration tree's `rules/` folder does not.
- A user-local plugin under `plugins/local/` delivers its skills and does not
  inject its always-apply rule file.

Account User Rules in Customize → Rules remain the documented machine-wide
communication-style slot, and a deploy step cannot write them.

## Approach

Under `--project-dir`, generate a Cursor variant of the style as an `.mdc` file
with frontmatter setting `alwaysApply: true` and write it into that project's
rules directory (`$CURSOR_DIR/rules/<name>.mdc`). Resolve the destination from
the script's existing Cursor directory variable rather than a hardcoded path.
A one-line `description` may label the rule in Customize; it does not scope an
always-apply rule.

Under `--global`, do not write a home-directory rule file and do not install a
user-local plugin for this style. Report that Cursor has no deployable
machine-wide rule-file path that print mode injects, and name the manual
alternative: paste the generated body into Customize → Rules (User Rules).

Generate the variant rather than copying. Strip the Claude frontmatter. Emit
Cursor frontmatter with `alwaysApply: true`. In that same generation step, rewrite
the style body's `<engineering_behavior>` clause so it states that the wording
rules govern the named prose surfaces, leave coding and tool-use behaviour to
Cursor's defaults, and that this harness only appends.

**Out of scope:**

- Deliverables named in Context, owned by [the Claude groundwork task](deployment_output-style-claude-groundwork.md).
- Cursor's team rules and its settings-stored User Rules, neither of which a
  deploy step can write.
- Writing `~/.cursor/rules/` or a user-local plugin `rules/` tree as a global
  carrier, both ruled out for print-mode injection by the settled probe.
- Using `globs` or Apply Intelligently as a stand-in for Claude's
  `keep-coding-instructions` flag.

## Acceptance

- A dry run under `--project-dir` restricted to the style type and the Cursor
  target reports one rule-file write into that project's `.cursor/rules/`
  directory as an `.mdc` file, and touches nothing under the home directory.
- A real deploy under `--project-dir` produces a rule file in that project's
  rules directory that parses as Markdown with YAML frontmatter and carries
  `alwaysApply: true`.
- A `--global` run reports that Cursor has no deployable machine-wide rule-file
  path that print mode injects, names the Customize → Rules paste, and writes no
  style rule under the user `rules/` folder or under `plugins/local/`.
- The deployed project file contains no Claude output-style frontmatter keys,
  verified by searching it for `keep-coding-instructions` and `force-for-plugin`
  and finding neither.
- The deployed body contains no reference to Claude's keep-coding-instructions
  mechanism, and the `<engineering_behavior>` clause states that the wording
  rules govern the named prose surfaces, leave coding and tool-use behaviour to
  Cursor's defaults, and that this harness only appends.
- Uninstalling removes the deployed project rule file and leaves any
  pre-existing rule files in the same folder untouched.
- In `deployment/README.md`, rewrite the Target Layout Styles cell for Cursor
  from `not yet` to name the project `.mdc` path and state that `--global` has
  no injecting file write, and add a Generated Formats row for `style`|Cursor
  stating that Cursor appends rather than replaces, so adherence is weaker than
  on Claude.
