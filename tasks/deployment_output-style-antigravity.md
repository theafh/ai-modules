---
description: "Deploy the output style to Antigravity as an always-on rule file, at global scope under the modular user rules directory and at project scope under the workspace rules directory."
scope: deployment
created: 2026-08-07T21:39:03Z
updated: 2026-11-25T10:58:51Z
status: open
reported-by: Andreas Hoffmann
---

# Deploy the output style to Antigravity

## Goal

Antigravity receives the repository's output style as an always-on rule, deployed by the same `style` artefact type the groundwork task adds, at whichever scope the run selects. Both scopes take the same shape, because current Antigravity reads rules from a `rules/` directory at each: under `--project-dir` the deploy writes one ordinary rule file into that project's `.agents/rules/`, and under `--global` it writes one ordinary rule file into the user-owned `~/.gemini/config/rules/`. Every rule file under a `rules/` directory carries `trigger: always_on` frontmatter, because Antigravity silently discards one that omits frontmatter or names an unrecognised trigger. Uninstall removes exactly the file the deploy wrote and leaves every other rule file byte-identical.

## Context

This builds on [the Claude groundwork task](archive/deployment_output-style-claude-groundwork.md), which shipped the repo-root source directory, the `style` artefact type, and the deploy-log restore behaviour. This task adds one target and no new machinery beyond the rule write described below.

The wiki records the mechanism in [system prompt substitution across harnesses](../wiki/comparisons/system-prompt-substitution-across-harnesses.md), with the paths on its [Google Antigravity](../wiki/entities/google-antigravity.md) page. The essentials, verified against `antigravity.google/docs` on 2026-11-25: the config-tree surfaces document no tone or output-format setting and no system-prompt-replacement feature, so the whole mapping runs through rules, while the Python SDK's `system_instructions` is a separate programmatic surface this deploy does not write. Rules are cumulative rather than replacement-based, so the deployed prose competes with default guidance instead of displacing it.

Antigravity ships as the Antigravity App, the Antigravity CLI (`agy`), the Antigravity IDE, and editor extensions. The docs at verification time were App v2.35.1, CLI v1.5.16, and IDE v2.8.0, and the documented CLI install runs `curl -fsSL https://antigravity.google/cli/install.sh | bash` into `~/.local/bin/agy`. A machine can run older builds, so the deploy resolves the documented locations and proves itself on a scratch tree rather than depending on the installed version.

Workspace rules are `<dir>/AGENTS.md`, `<dir>/GEMINI.md`, `<dir>/.agents/AGENTS.md`, `<dir>/.agents/GEMINI.md`, and `<dir>/.agents/rules/*.md`, read at the workspace folder and each parent folder up to the repository root, with the legacy `.agent/rules/*.md` still read. Global rules are the four standalone files `~/.gemini/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.gemini/config/AGENTS.md`, and `~/.gemini/config/GEMINI.md`, which need no frontmatter and stay always active, plus the modular `~/.gemini/config/rules/*.md`, where frontmatter is required. Antigravity scans each customization folder one level deep, so a rule file sits directly inside `rules/`; a nested file loads only when a `rules.json` manifest names it.

Two limits shape this task. Antigravity truncates any single rule file larger than 24,000 bytes, measured after `@[label](path)` includes expand, and all active global and `always_on` rules share a 20,000-token aggregate budget, over which Antigravity demotes the largest files to pointers. The style body is 14,628 bytes today, so it fits the byte cap; the deploy still measures the generated content against the live cap rather than assuming it fits, and fails with a clear message when it does not.

Antigravity is also the one non-Claude harness whose plugin bundle can carry rules, so a plugin-integrated route exists here beside the two config-tree scopes. This task takes the config-tree routes at both scopes and leaves the plugin bundle alone, since bundling ties the rule's reach to an installed plugin rather than to the tree the deploy writes.

## Approach

Generate the Antigravity variant once and write it by whichever shape the scope requires, resolving the destination from the script's existing Antigravity directory variables rather than hardcoded paths: `ANTIGRAVITY_DIR` is `<project>/.agents` under `--project-dir` and `~/.gemini/config` under `--global`, so the rule file lands at `"${ANTIGRAVITY_DIR}/rules/<name>.md"` in both modes.

Write one ordinary Markdown rule file per scope, carrying `trigger: always_on` frontmatter. The file belongs to the deploy, so redeploy replaces it and uninstall removes it outright. Leave every other rule file untouched, and write nothing into the four standalone `AGENTS.md` and `GEMINI.md` files: those belong to the user and carry no frontmatter, so a marked block there would need marker parsing that the modular directory makes unnecessary.

Check the generated content against the 24,000-byte per-file cap before writing, and fail with a message naming the actual size and the limit when it does not fit, rather than truncating or writing a file the harness will truncate. Report the generated size in the deploy output, because the file also competes for the shared 20,000-token `always_on` budget.

Generate rather than copy. Strip the Claude frontmatter and emit `trigger: always_on`; rewrite the `<engineering_behavior>` element that names Claude's `keep-coding-instructions` mechanism, following `generate_cursor_style_rule` in `deployment/deployment.sh`, which replaces that element wholesale. The style source carries no `$VAR$` token, so no `replace:` rule applies to it.

Refresh the Antigravity page in the wiki through the wiki skill family, which names the modular global directory beside one standalone file where the docs now list four.

**Out of scope:**

- The plugin bundle's rules component, which reaches only the sessions where that plugin is installed rather than every session in the tree the deploy writes.

## Acceptance

- A dry run under `--global` restricted to the style type and the Antigravity target reports one rule-file write into `~/.gemini/config/rules/` and no other file changes.
- A dry run under `--project-dir` reports one rule-file write into that project's `.agents/rules/` and no change under the home directory.
- A real deploy under `--project-dir` produces a Markdown rule file in that project's `.agents/rules/` carrying `trigger: always_on`, and uninstalling removes that file outright.
- A real deploy against a scratch global rules directory that already contains unrelated user files leaves those files byte-identical and adds one ordinary style file.
- Deploying twice in a row leaves exactly one style file.
- Uninstalling removes the deployed style file and leaves the surrounding user content byte-identical to its state before the first deploy.
- A deploy attempt with generated content exceeding 24,000 bytes fails with a message naming the actual size and the limit, and writes nothing.
- The deployed rule file carries `trigger: always_on` and no Claude output-style frontmatter keys, verified by checking its frontmatter for `keep-coding-instructions` and `force-for-plugin`.
- A global deploy leaves the four standalone `~/.gemini/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.gemini/config/AGENTS.md`, and `~/.gemini/config/GEMINI.md` byte-identical, whether or not each exists.
- The wiki's Google Antigravity page names all four standalone global rule files beside the modular `~/.gemini/config/rules/` directory.
- `deployment/README.md` replaces the Antigravity Styles cell's `not yet` with the modular global rules route, the `trigger: always_on` requirement at both scopes, the 24,000-byte cap, and the fact that this target appends rather than replaces.
