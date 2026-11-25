---
description: Deploy the output style to Codex by re-deriving per-model base instructions at deploy time, swapping the style-owned sections for the style prose, and pointing the instructions-file key at the result.
scope: deployment
created: 2026-08-07T21:39:03Z
updated: 2026-11-25T12:00:20Z
status: checked
reported-by: Andreas Hoffmann
---

# Deploy the output style to Codex

## Goal

Codex receives the repository's output style as a synthesized style-layer replacement rather than an appended rule, so the style displaces Codex's own personality and formatting guidance instead of arguing with it. The deploy re-derives Codex's current base instructions from the installed build on every run, substitutes the style sections, writes the result to a file, and points the instructions-file configuration key at it. Re-deriving on every run is what keeps the generated file from going stale as Codex updates.

## Context

This builds on [the Claude groundwork task](archive/deployment_output-style-claude-groundwork.md), which shipped the repo-root source directory, the `style` artefact type, and the deploy-log restore behaviour. This task adds one target, and the configuration key it sets needs the prior-value capture and restore that the groundwork task delivers. The groundwork's Claude arm serves both scopes; this task rejects project scope for Codex for the reasons in **Out of scope**.

The wiki records the mechanism on its [OpenAI Codex](../wiki/entities/openai-codex.md) page and in [system prompt substitution across harnesses](../wiki/comparisons/system-prompt-substitution-across-harnesses.md). The essentials: Codex carries exactly one instructions slot whose provenance is either generated from the model's template or explicitly configured, nothing composes the two, and there is no keep-the-original flag. Setting the key therefore replaces the whole slot, and the configured value is documented as surviving model changes unchanged. Tool schemas travel separately and are not lost. Three facts make the synthesis viable, all recorded on the wiki's OpenAI Codex page with the verification date. The installed Codex renders its model catalog as JSON including the resolved base instructions and the instructions template per model, so the current text needs no committed copy. The resolved text is ordinary Markdown with named sections covering personality, working with the user, rules for getting work done, destructive actions, and skills. And the on-disk model cache carries no base instructions, so invoking the binary is required rather than optional.

Two constraints follow from the same block. The text differs per model and so does its size, so the generator reads the configured model rather than assuming one. And the section names are undocumented internal structure, so a generator that cannot find an expected heading fails loudly instead of appending and hoping.

## Approach

Locate the Codex binary by feature detection rather than assuming it is on the executable search path, since it can ship inside an application bundle. Probe the sources in this fixed order and use the first that exists: a `CODEX_BIN` environment variable naming an explicit binary, then the bundle's `Contents/Resources/codex-cli/bin/codex` under the active home directory's `Applications`, then the same bundle path under `/Applications`. `CODEX_BIN` ranks first so an explicit binary from a staged test or an unusual install is honoured rather than silently outranked, and the home-directory bundle ranks ahead of the system one so a scratch `HOME` stays isolated from a Codex installed for the whole machine. When it is absent, skip the Codex target with a clear message rather than failing the whole deploy.

The Codex arm acts only on the style named by `style:<name>` under `#codex` in `deployment/deployment.conf`, resolved through the same `STYLE_MAP` lookup the Claude arm already uses, because the style type runs once per `styles/*.md` file and a second style file would otherwise write a second generated file and merge the key twice, last one winning. A style file that is not the active one is skipped with a message and writes no file and no key. Add `style:natural-language` under `#codex`, and refresh the passages that call the directive Claude-only: the `style:<name>` doc comment at the head of `deployment/deployment.sh`, the matching comment in `deployment/deployment.conf`, and the `style:<name>` row plus its following paragraph in `deployment/README.md`'s Per-Tool Configuration section, so each names both the Claude and Codex arms.

Read the configured model from the Codex user configuration file, render the model catalog as JSON through the binary's debug facility, and take the resolved base instructions for that model. When the user configuration sets no `model` key, skip the Codex style with a warning and write no file and no key, matching how the style arm already treats an absent active-style line rather than deriving from an arbitrary catalog entry.

Classify every heading in the derived text into exactly one role from this table, substitute the style-owned roles with the generated style prose, and keep the operating roles as derived:

| Role | Recorded heading names | Disposition |
| --- | --- | --- |
| Personality and writing style | `personality`, `writing style` | Substitute with the style prose |
| Talking to the user, including how a final answer is formatted | `working with the user`, `how to talk to the user`, `how to format a final answer` | Substitute with the style prose; the formatting guidance lives under this role rather than under a separate formatting heading |
| Editing and autonomy | `rules for getting work done`, `editing and autonomy` | Keep as derived |
| Destructive actions | `destructive actions` | Keep as derived |
| Skill use | `skills`, `skill use` | Keep as derived |

These recorded names are the match set. A heading matching no role, and a role with no matching heading, both take the fail-loudly path below, naming the heading or role that was not found and the Codex version it was looked for in, so a whole-slot replacement never ships with a role silently absent and no formatting guidance survives under a kept heading.

Write the result into the Codex configuration tree as a generated instructions file. Then set `model_instructions_file` in the Codex user configuration (`config.toml` in the Codex configuration tree) with a TOML-aware top-level edit rather than a JSON merge or a line append: read the file with a TOML parser, replace the key when it already exists and otherwise insert it above the first table header, leave every other key, table, and comment in place, and reject the result without writing when it does not parse as TOML.

Generate the file from the style body rather than from the style file: strip the Claude frontmatter, which Codex does not read, and replace the `<engineering_behavior>` element, whose text names Claude's `keep-coding-instructions` mechanism, with a clause stating that the wording rules govern prose while coding, tool-use, and verification behaviour come from the Codex operating sections kept from the derived text.

Record the prior `model_instructions_file` value, or `@absent` when the key is missing, in the deploy log's existing fifth field, and teach both readers of a logged prior the TOML branch: `remove_logged_path` restores the value from a TOML-aware branch beside its JSON branch, and `json_key_uninstall_succeeded`, which the uninstall loop calls immediately after it, verifies the restored value through that same branch and the same file-identity discriminator, so uninstall returns the original value, strips only a key this deploy created, and reports the entry removed rather than failed.

Fail loudly when an expected section heading is missing from the derived text, naming the heading that was not found and the Codex version it was looked for in, and write nothing. A silent fallback to appending would produce the weak behaviour this whole target exists to avoid. Scope every derivation failure to the Codex style alone: a catalog read that fails — the render exiting non-zero, or the configured model absent from the catalog — skips the Codex style with a warning naming the cause, while a missing expected heading fails the Codex style with its named-heading message. Either way every other target and artefact still deploys.

Record in the generated file's own header which model and which Codex version it was derived from, so a stale file is diagnosable by reading it. Re-running the deploy after a model change or a Codex update re-derives and overwrites it, which is the intended way to heal drift.

**Out of scope:**

- Project-scoped deployment under `--project-dir`, which this task rejects outright rather than defers. A project `.codex/config.toml` can set the instructions-file key, so the rejection is a judgement rather than a limitation: a committed whole-slot replacement changes the operating instructions for everyone who works in that repository, not only the person who deployed it, and the generated text is pinned to one model and one Codex version so it is wrong for every contributor on a different one. Codex also loads project layers only for a trusted project, so the placement would silently do nothing until trust is granted. Skip the Codex style actions with a warning under `--project-dir`.
- The additive alternative of writing a marked block into the Codex global rules file, which reaches a weaker outcome and is not what this task delivers.
- The personality setting and the profile layer, neither of which can carry repository prose: the first is a closed vendor enum and the second needs a launch flag rather than a persisted key.

## Acceptance

- A dry run restricted to the style type and the Codex target reports one generated-file write and one configuration key merge, and reports a clean skip with a message when no Codex binary is found.
- With `PATH` stripped of any `codex` and `CODEX_BIN` naming a stub executable staged at an application-bundle-shaped path inside the scratch tree, the deploy finds and uses that stub: the stub answers `--version` and the model-catalog debug call with fixture text, the generated file's header names the version the stub reported, and the run reports the generated-file write and the configuration merge instead of the no-binary skip.
- With `PATH` stripped of any `codex` and `CODEX_BIN` unset, the deploy finds and uses a stub staged at `$HOME/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex` inside a scratch `HOME` that also carries a Codex `config.toml` setting `model = "<slug>"`: the stub answers `--version` and the model-catalog debug call with fixture text, the generated file's header names the version the stub reported, and the run reports the generated-file write and the configuration merge instead of the no-binary skip.
- A real deploy produces a generated instructions file in which every heading of the derived base instructions is classified into exactly one role of the Approach table, the kept roles (editing and autonomy, destructive actions, skill use) match the derived text byte-for-byte, and the substituted roles (personality and writing style, talking to the user including final-answer formatting) carry the style prose instead of the originals.
- The generated file's header names the model and the Codex version it was derived from.
- A deploy against a scratch configuration whose `config.toml` sets `model = "<slug>"` produces a header naming that slug, and one whose `config.toml` sets no `model` key skips the Codex style with a warning and writes no file and no key.
- A deploy over an existing generated file replaces it: under a scratch `HOME`, after one run, overwrite the generated file with sentinel text and a header naming a different model and Codex version, run the deploy again, and confirm the file's content is the freshly derived text and its header names the current model and Codex version.
- The Codex user configuration parses as valid TOML after the merge and points `model_instructions_file` at the generated file, and a scratch configuration seeded with another top-level key, a `[table]` section, and a comment still carries all three after the merge.
- Running the deploy against a scratch configuration that already sets the instructions-file key, then uninstalling, restores the original value rather than deleting the key, reports the logged entry removed rather than failed, and leaves the deploy log with no line for it.
- A deploy run against a derived text with a renamed or missing expected section fails with a message naming the missing heading and the Codex version, and writes no file and no key. The same run still reports its other targets' deploys. Prove this on a staged fixture holding a derived text with one expected heading removed.
- A deploy run against a scratch Codex configuration whose catalog read fails — a catalog render that exits non-zero, or a catalog that omits the configured model — skips only the Codex style with a warning naming the cause, and the same run still reports the other targets' deploys. Prove this by sourcing the deploy script with `DEPLOYMENT_SH_SKIP_MAIN=1`, as `tests/deployment/script_tests/style_run.sh` does, and calling the derivation function with the failing catalog path.
- The generated file carries no Claude output-style keys and no reference to Claude's flag mechanism: a search of the generated file for `keep-coding-instructions` and `force-for-plugin` finds neither, and its `<engineering_behavior>` clause states that the wording rules govern prose while coding and tool-use behaviour come from the Codex operating sections kept from the derived text.
- `deployment/README.md` gains a Codex row in the Generated Formats style section naming the derivation source, the substituted sections, the fail-loudly behaviour, and the fact that the configured value does not re-derive on a model change without a redeploy, and its existing Target Layout Styles cell for Codex no longer reads `not yet`.
- A deploy restricted to the style type and the Codex target against a scratch copy of the tree whose `styles/` holds a second, non-active style file reports exactly one generated-file write and one configuration key merge, for the style named by `style:<name>` under `#codex`, and a skip message for the other file.
- The `style:<name>` documentation no longer calls the directive Claude-only: the head comment in `deployment/deployment.sh`, the comment in `deployment/deployment.conf`, and the `style:<name>` row and its following paragraph in `deployment/README.md` name both the Claude and Codex arms, and `#codex` in `deployment.conf` carries `style:natural-language`.
