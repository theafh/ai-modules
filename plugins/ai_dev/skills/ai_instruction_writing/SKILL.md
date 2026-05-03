---
name: ai_instruction_writing
description: Write AI-consumed content using positive, action-oriented language as the primary carrier of every instruction. Use when creating or editing any artifact an AI reads at inference time — SKILL.md files, .mdc rule files, CLAUDE.md/AGENTS.md/GEMINI.md configuration, prompt templates, system prompts, commands, agent and sub-agent definitions, instruction sets, and persona definitions.
version: 2.0.0
author: Andreas F. Hoffmann
license: MIT
---

# ai_instruction_writing

## Core Rule

Every instruction's primary carrier is a positive statement that tells the LLM what to do, what something is, or how it should be. A negative or contrastive supplement ("don't X", "avoid Y", "X instead of Y", double negatives, implicit negation by comparison) earns its place only when listing every positive case is infeasible — the negative then names a broader class as a catch-all for what falls outside the positive guidance. When the positive set is fully enumerable, the negative restates the inverse and adds nothing; cut it.

**Self-check:** Delete the negative or contrastive portion of a rule.

- If the remaining positive is empty or vague, the rule is inverted. Rewrite the positive carrier first.
- If the remaining positive is complete and the negative just stated its inverse, drop the negative — it's redundant.
- Keep the negative when it names a broader class than any single positive could enumerate.

This rule governs your *output*. In meta or teaching context — including this skill — contrastive pairs, ❌/✅ examples, and "X replaces Y" patterns are legitimate when they illustrate how to transform inputs.

## Guidelines for Writing Rules

- **Start with action verbs**: Use, Write, Create, Define, Implement, Apply
- **Be specific**: Tell exactly what to do with concrete details
- **Use the imperative mood**: Write commands that tell the LLM what to do
- **Lead with the positive carrier**: Put the actionable instruction first; layer supplements after
- **Preserve technical precision**: Keep specific details, error codes, and identifiers when transforming
- **Enhance rather than replace**: Add specificity, rationale, and context on top of existing positive rules

## Positive Language Examples

These stand alone — no contrast needed:

- "Use specific exception types like `except ValueError:`"
- "Use absolute imports like `from package.module import function`"
- "Define named functions for reusable logic"
- "Write one statement per line for readability"
- "Implement error handling with specific exception types"
- "Apply consistent formatting throughout the codebase"
- "Write clear, descriptive error messages that guide users"
- "Provide specific examples for each concept"

## Layering a Catch-All Negative

A negative supplement earns its place when listing the positive cases exhaustively is infeasible. The negative names a broader class as a catch-all for what falls outside the positive guidance. When the positive set is finite and enumerable, no negative is needed.

Valid — positive carrier + catch-all for the long tail:

- ✅ "Use ASCII characters in identifiers; don't include Unicode symbols, emoji, or non-printing characters." (positive is one finite class; Unicode is too broad to enumerate, so the negative names the excluded class)
- ✅ "Open every section with an action verb (Use, Write, Create, Define, Implement, Apply); don't lead with passive voice or noun phrases." (positives are partial; the negative catches the long tail of non-action openings)

Invalid — negative-only, no positive carrier:

- ❌ "Don't use relative imports." → "Use absolute imports like `from package.module import function`."
- ❌ "Avoid unused imports." → "Import only modules you actively use; remove unused imports immediately to prevent F401 errors."

Invalid — negative just inverts an enumerable positive (noise):

- ❌ "Use 4-space indentation; don't use tabs or 2-space indents." → "Use 4-space indentation."

## Transformation Patterns (meta — for rewriting negative inputs)

Use these patterns when rewriting existing negative rules into positive ones. The pairs show the transform; your *output* is the positive half, optionally with supplemental context.

- **Action-focused**: "Use X" replaces "Don't use Y"
- **Outcome-focused**: "Ensure X" replaces "Avoid Y"
- **Solution-focused**: "Implement X" replaces "Prevent Y"
- **Guidance-focused**: "Follow X" replaces "Never Y"
- **Success-focused**: "Apply X" replaces "Stop Y"

## Good vs. Poor Transformations

Both rows take a negative input and produce a positive output. The good versions preserve the technical precision the bad ones discard.

**Poor transformation** (deletes important information):

- ❌ "Never import unused modules" → "Import only what you use"
- ❌ "Don't assign unused variables" → "Use variables only when needed"

**Good transformation** (preserves and enhances information):

- ✅ "Never import unused modules" → "Import only modules you actively use; remove unused imports immediately to prevent F401 errors"
- ✅ "Don't assign unused variables" → "Assign variables only when you need them; use `_` for intentionally unused values to prevent F841 errors"

## Enhancement Strategies

When improving existing positive rules, layer value on top:

- **Add specificity**: Include error codes, specific examples, concrete details
- **Expand context**: Add rationale, benefits, when to apply
- **Enhance examples**: Provide more detailed, actionable examples
- **Improve clarity**: Make the action more specific without losing content

## Content Guidelines

- **Lead with positive**: Always start sections with what to do
- **Allocate most space to positive guidance**: The positive form is the carrier; supplements stay short
- **End with positive**: Conclude with positive reinforcement when wrapping a section
