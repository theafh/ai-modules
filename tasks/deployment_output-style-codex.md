---
description: Deploy the output style to Codex by re-deriving its per-model base instructions at deploy time, swapping the personality and formatting sections, and pointing the instructions-file key at the result.
scope: deployment
created: 2026-08-07T23:39:03
updated: 2026-08-08T01:12:44
status: open
reported-by: Andreas Hoffmann
---

# Deploy the output style to Codex

## Goal

Codex receives the repository's output style as a synthesized style-layer replacement rather than an appended rule, so the style displaces Codex's own personality and formatting guidance instead of arguing with it. The deploy re-derives Codex's current base instructions from the installed build on every run, substitutes the style sections, writes the result to a file, and points the instructions-file configuration key at it. Re-deriving on every run is what keeps the generated file from going stale as Codex updates.

## Context

This builds on [the Claude groundwork task](deployment_output-style-claude-groundwork.md), which creates the repo-root source directory, the `style` artefact type, and the deploy-log restore behaviour. Ship that first; this task adds one target, and the configuration key it sets needs exactly the prior-value capture and restore that the groundwork task delivers.

The wiki records the mechanism on its [OpenAI Codex](../wiki/entities/openai-codex.md) page and in [system prompt substitution across harnesses](../wiki/comparisons/system-prompt-substitution-across-harnesses.md). The essentials: Codex carries exactly one instructions slot whose provenance is either generated from the model's template or explicitly configured, nothing composes the two, and there is no keep-the-original flag. Setting the key therefore replaces the whole slot, and the configured value is documented as surviving model changes unchanged. Tool schemas travel separately and are not lost.

Three facts make the synthesis viable, all recorded on the wiki's [OpenAI Codex](../wiki/entities/openai-codex.md) page with the verification date. The installed Codex renders its model catalog as JSON including the resolved base instructions and the instructions template per model, so the current text needs no committed copy. The resolved text is ordinary Markdown with named sections covering personality, working with the user, rules for getting work done, destructive actions, and skills. And the on-disk model cache carries no base instructions, so invoking the binary is required rather than optional.

Two constraints follow from the same block. The text differs per model and so does its size, so the generator reads the configured model rather than assuming one. And the section names are undocumented internal structure, so a generator that cannot find an expected heading fails loudly instead of appending and hoping.

## Approach

Locate the Codex binary by feature detection rather than assuming it is on the executable search path, since it can ship inside an application bundle. When it is absent, skip the Codex target with a clear message rather than failing the whole deploy.

Read the configured model from the Codex user configuration file, render the model catalog as JSON through the binary's debug facility, and take the resolved base instructions for that model. Substitute the personality and formatting sections with the generated style prose, keeping the operating sections that cover rules for getting work done, destructive actions, and skills. Write the result into the Codex configuration tree as a generated instructions file, and merge the instructions-file key into the Codex user configuration so the file takes effect.

Fail loudly when an expected section heading is missing from the derived text, naming the heading that was not found and the Codex version it was looked for in, and write nothing. A silent fallback to appending would produce the weak behaviour this whole target exists to avoid.

Record in the generated file's own header which model and which Codex version it was derived from, so a stale file is diagnosable by reading it. Re-running the deploy after a model change or a Codex update re-derives and overwrites it, which is the intended way to heal drift.

**Out of scope:**

- The source directory, the `style` artefact type, and the log restore behaviour, all owned by [the Claude groundwork task](deployment_output-style-claude-groundwork.md).
- Project-scoped deployment under `--project-dir`, which this task rejects outright rather than defers. A project `.codex/config.toml` can set the instructions-file key, so the rejection is a judgement rather than a limitation: a committed whole-slot replacement changes the operating instructions for everyone who works in that repository, not only the person who deployed it, and the generated text is pinned to one model and one Codex version so it is wrong for every contributor on a different one. Codex also loads project layers only for a trusted project, so the placement would silently do nothing until trust is granted. Skip the Codex style actions with a warning under `--project-dir`, matching how [the Claude groundwork task](deployment_output-style-claude-groundwork.md) skips its own.
- The additive alternative of writing a marked block into the Codex global rules file, which reaches a weaker outcome and is not what this task delivers.
- The personality setting and the profile layer, neither of which can carry repository prose: the first is a closed vendor enum and the second needs a launch flag rather than a persisted key.

## Acceptance

- A dry run restricted to the style type and the Codex target reports one generated-file write and one configuration key merge, and reports a clean skip with a message when no Codex binary is found.
- A real deploy produces a generated instructions file whose operating sections match the derived base instructions byte-for-byte, and whose personality and formatting sections carry the style prose instead of the originals.
- The generated file's header names the model and the Codex version it was derived from.
- The Codex user configuration parses as valid TOML after the merge and points the instructions-file key at the generated file.
- Running the deploy against a scratch configuration that already sets the instructions-file key, then uninstalling, restores the original value rather than deleting the key.
- A deploy run against a derived text with a renamed or missing expected section fails with a message naming the missing heading and the Codex version, and writes no file and no key. Prove this on a staged fixture holding a derived text with one expected heading removed.
- The generated file contains no Claude output-style frontmatter keys, verified by searching it for `keep-coding-instructions` and `force-for-plugin` and finding neither.
- `deployment/README.md` gains a Codex row for the style type naming the derivation source, the substituted sections, the fail-loudly behaviour, and the fact that the configured value does not re-derive on a model change without a redeploy.
