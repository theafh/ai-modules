---
name: ai_instruction_formatting
description: Organize AI-consumed content (prompts, rules, skills, commands, agents, system instructions) into pseudo-XML by wrapping each semantic concern in a dedicated tag for role, policy, inputs, and output contract.
version: 2.0.0
author: Andreas F. Hoffmann
license: MIT
---

# ai_instruction_formatting

Organize any LLM-consumed content into pseudo-XML, a lightweight tagging format where self-describing tag names encode the semantic role and organizational structure of information. Tags exist purely to label meaning (e.g., `<policy>`, `<scoring_criteria>`, `<after_spec_execution>`); they carry plain text inside and work directly as LLM-readable structure. Apply to system prompts, rules, skills, commands, agent definitions, instruction sets, and any other artifact an LLM reads at inference time.

## When to Apply

Use pseudo-XML structuring for any document where an LLM is the primary consumer: prompt templates with placeholders, static rule files, skill definitions, agent personas, routing instructions, and multi-step workflows. Apply the format equally to parameterized templates (with `{placeholder}` values) and fixed instructional content.

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

Encode every semantic distinction in the tag name itself. Each tag is a unique, self-describing label: the name alone communicates the full purpose.

- **Encode meaning in the tag name**: write `<scope_boundary_discipline>`, where the tag name carries the full semantic. Move every descriptive label into the tag name itself.
- **Create a unique tag for each distinct concept**: write `<after_spec_execution>`. Each concept gets its own tag so the LLM parses meaning directly from structure.
- **Use snake_case for multi-word tag names**: `<output_contract>`, `<scoring_criteria>`, `<triage_agent>`.
- **Place all content between opening and closing tags**: use plain text or nested child tags inside. Encode every distinction in tag names and nesting structure.

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

Group concerns into stable categories:

- **Intent**, define what to do: `<role>`, `<objective>`
- **Knowledge**, supply what to know: `<context>`, `<inputs>`
- **Decision rules**, specify how to decide: `<policy>`, `<rule>`, thresholds, `<default>`
- **Procedure**, order what to follow: `<steps>`
- **Demonstration**, show what good looks like: `<examples>`
- **Output contract**, lock the response shape: `<output_contract>`, `<format>`, `<validation>`

## Constraint-First Ordering

Place constraints, thresholds, and validation expectations before open-ended instructions so the model reads boundaries first. Encode default behavior and edge-case handling as explicit tagged rules inside `<policy>` or `<output_contract>`.

## Deterministic Structure

Define fixed wrapper tags, fixed fields, and explicit transformation instructions to strengthen response consistency. Reuse the same tag names across artifacts for the same semantic role (e.g., always `<output_contract>` for response shape, always `<policy>` for decision rules).

## Authoring Guidelines

- Write plain language inside tags; apply predictable XML structure outside.
- Choose self-descriptive tag names that match the section's semantic role. Invent new tags freely; encode the concept directly in the tag name (e.g., `<scoring_criteria>`, `<guardrails>`, `<persona>`).
- Nest tags where there is a true parent-child relationship (e.g., `<inputs>` > individual input fields).
- Limit tag depth to three levels for readability.
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
