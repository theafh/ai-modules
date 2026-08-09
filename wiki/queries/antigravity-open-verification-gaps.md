---
title: What remains unverified about Google Antigravity?
created: 2026-08-08
updated: 2026-08-09
type: query
tags: [antigravity, verification-gap, frontmatter, agent, discovery]
sources: []
confidence: high
---

# What remains unverified about Google Antigravity?

## The question

Which claims about [Google Antigravity](../entities/google-antigravity.md) rest
on absence of evidence, contradiction between official pages, or an inference
that nobody has tested, rather than on a documented statement?

## Synthesized answer

Four gaps survived the July and August 2026 verification passes and gate design
decisions here. Each is recorded as a gap because the documentation is genuinely
silent or self-contradictory, not because nobody looked. Two narrower unknowns sit
below them and are kept with their own mechanism, named at the end of this page.

### Frontmatter tolerance

Whether the loader rejects an unrecognised frontmatter key is unconfirmed, and
the available evidence leans tolerant. The subagents and skills pages say nothing
about unknown keys either way. The one documented validation gotcha is a bad
tool name causing a runtime hang rather than a load rejection. The
fixed-allowlist "unexpected fields" behaviour that circulates in secondary
sources traces to a `SKILL.md` editor linter in VS Code, which can raise a
cosmetic editor warning without being a runtime rejection, and which never names
Antigravity.

This is the gap that most changes design work, because
[agent definition portability](../concepts/agent-definition-portability.md)
classifies every target as ignore-unknown, strict-schema, or pass-through, and
that classification decides how aggressively a generated variant filters keys.
Until someone confirms it against the loader or empirically, the Google target
stays classified as pending verification rather than as strict.

### Whether plugin-bundled agents register

Official pages contradict each other. The subagents page names
`plugins/<plugin_name>/agents/` as a subagent location, while both the 2.0 and
the IDE plugins pages omit agents from the bundle component list entirely.
Confirm on the target product before shipping a plugin-bundled agent and
expecting it to register.

### Which of `GEMINI.md` and `AGENTS.md` wins

Both a project's `GEMINI.md` and its `AGENTS.md` are parsed for rule
constraints, and no page reviewed states which takes precedence when the two
disagree. Treat that precedence as unresolved, and avoid splitting one rule set
across the pair.

### Whether it reads another harness's directories

No page reviewed in July 2026, across settings, CLI settings, permissions, the
CLI reference, skills, subagents, or plugins, mentions discovering artefacts from
`.claude`, `.cursor`, or `.codex`, and none documents an environment variable or
configuration key that would scope such discovery.

The working assumption is own-roots-only loading, with the missing isolation
switch read as unnecessary rather than absent. That assumption rests on the
weakest evidence type in use here, which is silence, so it deserves a check on an
installed build. See
[foreign directory adoption](../concepts/foreign-directory-adoption.md) for what
every other harness in the set does.

### Two narrower questions kept elsewhere

Two further unknowns sit below the four above, and they live with the mechanism
they belong to rather than here: whether the subagents page and the hooks page
publish one tool namespace or two, and what an empty `tools` array actually
grants. Both are on
[Antigravity tool vocabulary](../concepts/antigravity-tool-vocabulary.md). They
are listed there rather than promoted here because neither gates a design
decision on its own; they shape what a generated variant may emit once the
frontmatter-tolerance question above is answered.

## Confidence and caveats

High on the report, and nil on the answers. Each gap is an accurate account of
what the documentation says and does not say as of 7 August 2026, checked across
every page listed on the entity page rather than inferred from one, which is why
this page carries high confidence: what it asserts is the state of the
documentation, and that was verified. What none of the four has is an answer, and
none has been tested on an installed build. The tolerance question is the one
worth spending a session on first, because it gates a design decision that is
already being made.

## Derived from

- `antigravity.google/docs`, the pages named on the entity page.
- `microsoft/vscode` issue 294520, for the editor-linter origin of the
  circulating unexpected-fields behaviour.
- The `harness_portability` skill in this repository, before its August 2026
  split.
