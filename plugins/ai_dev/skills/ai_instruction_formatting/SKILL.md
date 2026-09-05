---
name: ai_instruction_formatting
description: Organize AI-consumed content (prompts, rules, skills, commands, agents, system instructions) into pseudo-XML by wrapping each semantic concern in a dedicated tag for role, policy, inputs, and output contract. Use when structuring or reorganizing the body of a SKILL.md, agent or sub-agent definition, command file, rules document (.mdc), CLAUDE.md, AGENTS.md, or GEMINI.md configuration, prompt template, or system prompt into semantic tags, when choosing tag boundaries, or when checking whether an instruction file follows the pseudo-XML convention. This is the structure-and-tags skill; its sibling ai_instruction_writing governs the wording.
version: 3.4.2
author: Andreas F. Hoffmann
license: MIT
---

# ai_instruction_formatting

Organize any LLM-consumed content into pseudo-XML, a lightweight tagging format where self-describing tag names encode the semantic role and organizational structure of information. Tags exist purely to label meaning (e.g., `<policy>`, `<scoring_criteria>`, `<after_spec_execution>`); they carry plain text inside and work directly as LLM-readable structure. Apply to system prompts, rules, skills, commands, agent definitions, instruction sets, and any other artifact an LLM reads at inference time.

## When to Apply

Use pseudo-XML structuring for any document where an LLM is the primary consumer: prompt templates with placeholders, static rule files, skill definitions, agent personas, routing instructions, and multi-step workflows. Apply the format equally to parameterized templates (with `{placeholder}` values) and fixed instructional content.

## File Shape

A pseudo-XML artifact lives inside a host file — a `SKILL.md`, an agent definition, a command file, a rules document, or a snippet. Four document shapes are valid, and this skill's bundled linter (`scripts/lint_pseudo_xml.py`) recognizes all four:

| Shape | Where it appears | Body content |
| :--- | :--- | :--- |
| Prose-only markdown | Writing and formatting skills | Markdown sections, no pseudo-XML in the body |
| XML-instruction body | Self-contained instruction skills | A single root pseudo-XML element spans the entire body after the H1 |
| Tutorial with examples | Documentation pages explaining the format | Markdown prose with pseudo-XML inside ` ```xml ` fenced examples |
| Mixed-agent | Agent definitions | Multiple top-level pseudo-XML wrappers (`<role>`, `<objective>`, `<protocol>`...) interspersed with markdown prose |

Whenever the host file is a `SKILL.md` or agent definition, keep the YAML frontmatter and the H1 heading regardless of body shape: the frontmatter `name:` matches the directory name, and the H1 matches `name:`. The XML rules below apply to whichever pseudo-XML the file contains; prose-only files skip them entirely.

## Rule Strength

Two tiers of guidance live in this skill: **mechanical rules** that are bugs when violated, and **stylistic guidance** that names well-tested defaults. The bundled linter enforces only the mechanical rules; an artifact that satisfies them while shaping content differently from the stylistic recommendations is correct, not deviant.

- **Mechanical rules (linter-enforced, bugs when violated)**: frontmatter `name:` matches the directory name; H1 is present and is a casing-or-spacing variant of `name:` (so `# Auto Shaper Wiki` matches `name: auto_shaper_wiki` — only genuine name drift is flagged); ASCII snake_case tag names; no attributes, no entities, no self-closing tags; balanced opening and closing tags with a recognized file shape; max nesting depth five (covers the canonical workflow shape `<wrapper> → <section_group> → <named_phase> → <list_parent> → <list_item>`; deeper is flagged); no duplicate siblings outside the repeating-tags allowlist; trailing newline.
- **Stylistic guidance (defaults, not violations)**: which named container holds which kind of content (see "Section Separation"), the relative order of objective / tools / policy / output_contract, and which tags from the standard vocabulary appear at all. Apply the defaults when authoring from scratch; deviate when the artifact's own structure carries the meaning more clearly. An artifact whose tag names are fully self-describing (e.g., `<commit_message_multi_file>`, `<scoring_criteria>`) often needs less wrapper ceremony than one whose children share a generic name like `<rule>` or `<step>`.

## Core Format

Wrap the entire artifact in a descriptive outer tag. Nest semantic sections inside it. Select section tags from the reference vocabulary below, or invent new tags that fit the artifact's specific concerns. The tags listed here are starting points; extend them with any tag the content needs.

```xml
<task_block>
  <role>Who the model is in this context.</role>
  <objective>What the model must accomplish.</objective>
  <inputs>
    <input_a>{placeholder_a}</input_a>
    <input_b>{placeholder_b}</input_b>
  </inputs>
  <context>
    Background knowledge, definitions, or reference material the model needs.
  </context>
  <policy>
    <rule>First constraint or decision rule.</rule>
    <rule>Second constraint or decision rule.</rule>
    <default>Fallback behavior when no rule matches.</default>
  </policy>
  <steps>
    <step>First action the model takes.</step>
    <step>Second action the model takes.</step>
  </steps>
  <examples>
    <example>
      <input>Sample input.</input>
      <output>Expected output.</output>
    </example>
  </examples>
  <output_contract>
    <format>Expected response structure.</format>
    <wrapper_tag>tag-name</wrapper_tag>
    <validation>How to verify correctness of the response.</validation>
  </output_contract>
</task_block>
```

## What Makes a Pseudo-XML Tag

Encode every semantic distinction in the tag name itself. Each tag is a self-describing label: the name alone communicates the full purpose.

- **Encode meaning in the tag name**: write `<scope_boundary_discipline>`, where the tag name carries the full semantic. Move every descriptive label into the tag name itself.
- **Match each distinct concept to its own tag name**: write `<after_spec_execution>` for that specific concern. Two concerns with genuinely different semantics carry different tag names; two list items of the same kind repeat the same tag — see "Repeating Tags".
- **Use ASCII snake_case for tag names**: `<output_contract>`, `<scoring_criteria>`, `<triage_agent>`. Tag names match `[a-z][a-z0-9_]*`. Capitals, hyphens, dots, colons, and HTML entities like `&amp;` never appear in tag names.
- **Carry no attributes on tags**: write `<output_contract>` instead of `<output type="contract">`. Pseudo-XML carries every distinction in the tag name itself, so attribute syntax has no role; move the attribute meaning into the tag name.
- **Place all content between explicit opening and closing tags**: use plain text or nested child tags inside. Self-closing forms (`<tag/>`) are unused — a tag with no content carries no meaning, so omit it entirely.

## Named Tags First

Each child gets its own self-describing tag whenever the concept has a natural name. Named tags are the default shape: they read as random-access semantic anchors (`<resolve_project_name>`, `<enumerate_dates>`, `<ensure_header>`) instead of forcing the reader to scan prose to identify which sibling is which.

```xml
<procedure>
  <resolve_project_name>...</resolve_project_name>
  <enumerate_dates>...</enumerate_dates>
  <ensure_header>...</ensure_header>
</procedure>
```

Sibling tags with **distinct** semantic roles always carry distinct tag names, even when they live under the same parent:

```xml
<inputs>
  <document>{document_text}</document>
  <style_guide>{style_guide_text}</style_guide>
</inputs>
```

Numeric or alphabetic suffixes (`<rule_1>`, `<rule_2>`, `<step1>`) inject artificial distinction without naming anything — they are neither named tags nor a clean homogeneous list. Replace them with either real names or the homogeneous-list shape below.

## Repetition as the Exception

Some siblings genuinely belong in a homogeneous list, where repeating the same tag inside a list parent encodes "list of the same kind of item" more cleanly than inventing names per entry would:

```xml
<policy>
  <rule>First constraint.</rule>
  <rule>Second constraint.</rule>
  <rule>Third constraint.</rule>
</policy>
```

The decisive question is **unit vs. anchor**: are the children read as a unit (an ordered sequence or group consumed together) or as anchors a reader (or LLM) might jump to and reference individually? Unit favors repetition; anchor favors named tags. Different content alone is not the signal — addressability is.

Reach for repetition when the unit signals all hold:

- The group is consumed as a whole; individual children are rarely referenced in isolation.
- Each child body is short (a sentence or fragment), not a developed phase worth recalling by name.
- The visual rhythm of identical siblings communicates "homogeneous list" at a glance.

When any child is something a reader would land on independently — a named procedure phase, a uniquely-scoped rule, a specific concern with its own identity — promote that child to a self-describing tag instead. Worked cases: `<rule>` items inside a `<policy>` are a unit (the policy applies as a whole). `<example>` items inside `<examples>` are a unit (collectively demonstrate). Four micro-substeps inside a single loop iteration are a unit (always read in order, every iteration). Five top-level procedure phases the artifact references by name are anchors.

The repeatable-pair allowlist:

| Parent | Repeatable child | Pattern |
| :--- | :--- | :--- |
| `<policy>` | `<rule>` | Constraints and decision rules |
| `<rules>` | `<rule>` | Standalone rule list |
| `<steps>` | `<step>` | Ordered workflow |
| `<substeps>` | `<substep>` | Substeps inside a named phase |
| `<examples>` | `<example>` | Demonstrations |
| `<scoring_criteria>` | `<criterion>` | Scoring rubric |
| `<validations>` | `<validation>` | Output checks |

If two siblings under the same parent share a tag name and the pair is not on the allowlist, treat the duplicate as a violation: either the two encode genuinely distinct concepts (rename one) or they are list items (wrap them in a list parent and repeat the singular child). The bundled linter emits an `info`-severity hint at every allowlisted repetition site so this judgment is made explicitly each time, rather than defaulted into.

## Tag Vocabulary

Start from these common semantic sections, and create additional domain-specific tags whenever the content calls for them. Include the subset each artifact requires.

| Tag | Purpose | Include when |
| :--- | :--- | :--- |
| `<role>` | Identity and perspective | The model acts as a specific persona or expert |
| `<objective>` | Goal statement | The artifact has a clear deliverable |
| `<inputs>` | Dynamic or static data | The model receives variable data or fixed reference material |
| `<context>` | Background and definitions | The model needs domain knowledge to reason correctly |
| `<policy>` | Constraints and decision rules | Behavior follows explicit boundaries |
| `<steps>` | Ordered workflow | The task follows a fixed sequence |
| `<examples>` | Input/output pairs | Demonstrations clarify expected behavior |
| `<output_contract>` | Response shape and validation | The output matches a specific format |

## Section Separation

When the children inside a section share a generic tag name (e.g., several `<rule>` items, several `<step>` items), group them under a named container that carries the section's meaning:

- **Intent**, define what to do: `<role>`, `<objective>`
- **Knowledge**, supply what to know: `<context>`, `<inputs>`
- **Decision rules**, specify how to decide: `<policy>`, `<rule>`, thresholds, `<default>`
- **Procedure**, order what to follow: `<steps>`
- **Demonstration**, show what good looks like: `<examples>`
- **Output contract**, lock the response shape: `<output_contract>`, `<format>`, `<validation>`

When each child already carries its full semantic in its own tag name (e.g., `<commit_message_multi_file>`, `<file_line_quality>`, `<execution_default>`), the section wrapper is optional — the tag name already serves the segmentation that the wrapper would otherwise provide. Apply this guidance as a default for content that benefits from grouping, not as a forced shape.

## Cross-Artefact References

When an artifact references content owned by a different skill, agent, command, or hook, use a delimited placeholder for the path rather than prose. Three orthogonal patterns cover the cases:

| Reference kind | Form | Example |
| :--- | :--- | :--- |
| Cross-skill asset path | `$<SLUG>_SKILL/path/within/skill` | `$WIKI_SKILL/references/raw_taxonomy.md` |
| Sibling artefact name (no path) | bare slug in backticks | `` `auto_shaper_wiki` `` |
| Within-artifact path | relative path in backticks | `` `references/lint_checks.md` `` |

The `$<SLUG>_SKILL/...` form makes cross-skill paths visually spotable (the `$` sigil stands out from surrounding prose), keeps boundaries unambiguous (the placeholder ends at the next whitespace or path separator), and stays orthogonal to pseudo-XML tags so the two conventions never collide. It is also greppable for tooling — `grep -r '\$[A-Z_]\+_SKILL/'` enumerates every cross-skill dependency in the codebase.

Why the `_SKILL` suffix on the slug: it keeps skill-install paths visually distinct from content/data shell variables that an agent or skill may already define (e.g., `$WIKI` resolved to the user's wiki location is a different thing from `$WIKI_SKILL` resolved to the wiki skill's install location). The suffix is self-documenting — the placeholder identifies as a skill path on sight, with no risk of conflating skill code with the data it operates on.

Apply this convention in `<policy>` lines, `<steps>` instructions, `<output_contract>` entries, reference lists, and any other structured section where the path is the meaningful payload. Free-flowing explanatory prose (e.g., "see the `wiki` skill for the full ingest flow") stays in prose — the rule covers paths, not every mention of a sibling. When in doubt: if the line is telling the model *where to read*, use the placeholder; if it is telling the model *what concept lives elsewhere*, prose is fine.

## Constraint-First Ordering

Place the constraints that bound the procedure before the procedure itself, so the model reads its boundaries before the open-ended instructions. The relative order of intent (`<objective>`), resources (`<tools>`, `<inputs>`), and constraints (`<policy>`, `<output_contract>`) is flexible — what matters is that whatever shapes how the model executes `<steps>` appears before `<steps>`. Encode default behavior and edge-case handling as explicit tagged rules inside `<policy>` or `<output_contract>`.

## Deterministic Structure

Define fixed wrapper tags, fixed fields, and explicit transformation instructions to strengthen response consistency. Reuse the same tag names across artifacts for the same semantic role (e.g., always `<output_contract>` for response shape, always `<policy>` for decision rules).

## Authoring Guidelines

- Write plain language inside tags; apply predictable XML structure outside.
- Choose self-descriptive tag names that match the section's semantic role. Invent new tags freely; encode the concept directly in the tag name (e.g., `<scoring_criteria>`, `<guardrails>`, `<persona>`).
- Nest tags where there is a true parent-child relationship (e.g., `<inputs>` > individual input fields).
- Limit nesting depth to five levels from the root. Five is the depth of the canonical workflow shape `<wrapper> → <section_group> → <named_phase> → <list_parent> → <list_item>` (e.g., `<skill> → <procedure> → <day_loop> → <steps> → <step>`) and the canonical examples shape `<wrapper> → <examples> → <example> → <input> → <inner_field>`. Beyond five, flatten by extracting the leaf concept into a sibling tag or moving detail into prose.
- Add `<validation>` entries in output contracts so the model knows what correctness looks like.
- Mark dynamic content with `{placeholder}` syntax inside tags; write static instructions as literal text.
- For static documents (rules, skills), write content directly inside the relevant section tags.

## Examples

### Prompt Template (parameterized)

```xml
<summarize>
  <role>Technical writer producing concise summaries.</role>
  <objective>Summarize the input document in three bullet points.</objective>
  <inputs>
    <document>{document_text}</document>
  </inputs>
  <output_contract>
    <format>Markdown unordered list, three items, one sentence each.</format>
    <validation>Each bullet captures a distinct key point from the source.</validation>
  </output_contract>
</summarize>
```

### Rule (static instructions)

```xml
<code_review_rule>
  <objective>Enforce consistent error handling across the codebase.</objective>
  <policy>
    <rule>Use specific exception types with descriptive messages.</rule>
    <rule>Log errors at the point of origin before re-raising.</rule>
    <rule>Return structured error responses at API boundaries.</rule>
    <default>When uncertain about error handling strategy, prefer explicit over silent.</default>
  </policy>
</code_review_rule>
```

### Agent Definition (persona + workflow)

```xml
<triage_agent>
  <role>Support triage specialist that classifies incoming tickets.</role>
  <objective>Assign priority and route each ticket to the correct team.</objective>
  <context>
    Teams: platform, frontend, data_pipeline, security.
    Priority levels: P0 (outage), P1 (degraded), P2 (bug), P3 (request).
  </context>
  <policy>
    <rule>Assign P0 when the ticket mentions downtime or data loss.</rule>
    <rule>Route security-related tickets to the security team regardless of priority.</rule>
    <default>Assign P3 and route to the team matching the affected component.</default>
  </policy>
  <steps>
    <step>Read the ticket summary and description.</step>
    <step>Determine priority using the policy rules.</step>
    <step>Identify the responsible team from the context.</step>
    <step>Output the classification.</step>
  </steps>
  <output_contract>
    <format>JSON with fields: priority, team, reasoning.</format>
    <validation>Priority is one of P0-P3; team is one of the four defined teams.</validation>
  </output_contract>
</triage_agent>
```

## Mechanical Validation

Run `scripts/lint_pseudo_xml.py` from this skill to validate any host file mechanically. Invoke it on one or more paths, or with no arguments to auto-discover `SKILL.md` and `agents/*.md` files under the current working directory:

```bash
python3 scripts/lint_pseudo_xml.py path/to/SKILL.md
python3 scripts/lint_pseudo_xml.py path/to/plugins/
python3 scripts/lint_pseudo_xml.py            # walk CWD for SKILL.md + agents
python3 scripts/lint_pseudo_xml.py --quiet    # issues only, suppress good list
```

The linter auto-detects the file shape from the four shapes above, reports what it detected, applies the rules to whatever pseudo-XML the file contains, and emits prose suggestions for every violation. When a file passes cleanly, it lists the checks that confirmed the file is in good shape. The script exits non-zero only when error-severity findings are present, so warnings stay actionable without blocking surrounding workflows.

Output is split into two sections: **Issues** (errors and warnings — mechanical violations) and **Hints** (info-severity prompts that surface judgment calls, like the named-phases-vs-repetition decision above). Hints never gate the build and never block PASS; they exist so the LLM weighs each repetition site rather than defaulting into the canonical pattern.
