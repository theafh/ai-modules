---
name: ai_instruction_writing
description: Write AI-consumed content using positive, action-oriented language as the primary carrier of every instruction. Use when creating or editing any artifact an AI reads at inference time — SKILL.md files, .mdc rule files, CLAUDE.md/AGENTS.md/GEMINI.md configuration, prompt templates, system prompts, commands, agent and sub-agent definitions, instruction sets, and persona definitions.
version: 3.0.0
author: Andreas F. Hoffmann
license: MIT
---

# ai_instruction_writing

<ai_instruction_writing>
  <objective>
    Write AI-consumed content so every instruction's primary carrier is a positive, action-oriented statement that tells the LLM what to do, what something is, or how it should be. Allow negative or contrastive supplements only as a catch-all for what positive guidance cannot enumerate.
  </objective>

  <core_rule>
    Every instruction's primary carrier is a positive statement that tells the LLM what to do, what something is, or how it should be. A negative or contrastive supplement ("don't X", "avoid Y", "X instead of Y", double negatives, implicit negation by comparison) earns its place only when listing every positive case is infeasible — the negative then names a broader class as a catch-all for what falls outside the positive guidance. When the positive set is fully enumerable, the negative restates the inverse and adds nothing; cut it.
  </core_rule>

  <self_check>
    <procedure>Delete the negative or contrastive portion of a rule, then apply the matching outcome below.</procedure>
    <when_positive_is_empty_or_vague>The rule is inverted. Rewrite the positive carrier first.</when_positive_is_empty_or_vague>
    <when_positive_is_complete>The negative just restates the inverse. Drop the negative — it is redundant.</when_positive_is_complete>
    <when_negative_names_a_broader_class>Keep the negative. It covers a long tail that no single positive could enumerate.</when_negative_names_a_broader_class>
  </self_check>

  <applicability>
    This rule governs the model's *output*. In meta or teaching context — including this skill — contrastive pairs, ❌/✅ examples, and "X replaces Y" patterns are legitimate when they illustrate how to transform inputs.
  </applicability>

  <authoring_guidelines>
    <start_with_action_verbs>Use, Write, Create, Define, Implement, Apply.</start_with_action_verbs>
    <be_specific>Tell exactly what to do with concrete details.</be_specific>
    <use_imperative_mood>Write commands that tell the LLM what to do.</use_imperative_mood>
    <lead_with_the_positive_carrier>Put the actionable instruction first; layer supplements after.</lead_with_the_positive_carrier>
    <preserve_technical_precision>Keep specific details, error codes, and identifiers when transforming.</preserve_technical_precision>
    <enhance_rather_than_replace>Add specificity, rationale, and context on top of existing positive rules.</enhance_rather_than_replace>
  </authoring_guidelines>

  <positive_only_examples>
    <when_to_apply>These enumerate their full positive set, so no catch-all negative is needed — see catch_all_negative for the cases where the long tail forces one.</when_to_apply>
    <examples>
      <example>Use specific exception types like `except ValueError:`.</example>
      <example>Use absolute imports like `from package.module import function`.</example>
      <example>Define named functions for reusable logic.</example>
      <example>Write one statement per line for readability.</example>
      <example>Implement error handling with specific exception types.</example>
      <example>Apply consistent formatting throughout the codebase.</example>
      <example>Write clear, descriptive error messages that guide users.</example>
      <example>Provide specific examples for each concept.</example>
    </examples>
  </positive_only_examples>

  <catch_all_negative>
    <principle>
      A negative supplement earns its place when listing the positive cases exhaustively is infeasible. The negative names a broader class as a catch-all for what falls outside the positive guidance. When the positive set is finite and enumerable, no negative is needed.
    </principle>
    <valid_catch_all>
      <pattern>Positive carrier plus catch-all for the long tail.</pattern>
      <examples>
        <example>"Use ASCII characters in identifiers; don't include Unicode symbols, emoji, or non-printing characters." The positive is one finite class; Unicode is too broad to enumerate, so the negative names the excluded class.</example>
        <example>"Open every section with an action verb (Use, Write, Create, Define, Implement, Apply); don't lead with passive voice or noun phrases." The positives are partial; the negative catches the long tail of non-action openings.</example>
      </examples>
    </valid_catch_all>
    <invalid_negative_only>
      <pattern>Negative-only, no positive carrier.</pattern>
      <examples>
        <example>"Don't use relative imports." Rewrite: "Use absolute imports like `from package.module import function`."</example>
        <example>"Avoid unused imports." Rewrite: "Import only modules you actively use; remove unused imports immediately to prevent F401 errors."</example>
      </examples>
    </invalid_negative_only>
    <invalid_redundant_negative>
      <pattern>Negative just inverts an enumerable positive (noise).</pattern>
      <examples>
        <example>"Use 4-space indentation; don't use tabs or 2-space indents." Drop the negative: "Use 4-space indentation."</example>
      </examples>
    </invalid_redundant_negative>
  </catch_all_negative>

  <transformation_patterns>
    <when_to_use>Apply these patterns when rewriting existing negative rules into positive ones. The pairs show the transform; the model's output is the positive half, optionally with supplemental context.</when_to_use>
    <action_focused>"Use X" replaces "Don't use Y".</action_focused>
    <outcome_focused>"Ensure X" replaces "Avoid Y".</outcome_focused>
    <solution_focused>"Implement X" replaces "Prevent Y".</solution_focused>
    <guidance_focused>"Follow X" replaces "Never Y".</guidance_focused>
    <success_focused>"Apply X" replaces "Stop Y".</success_focused>
  </transformation_patterns>

  <good_vs_poor_transformations>
    <principle>Both rows take a negative input and produce a positive output. The good versions preserve the technical precision the poor ones discard.</principle>
    <poor>
      <issue>Deletes important information.</issue>
      <examples>
        <example>"Never import unused modules" → "Import only what you use".</example>
        <example>"Don't assign unused variables" → "Use variables only when needed".</example>
      </examples>
    </poor>
    <good>
      <strength>Preserves and enhances information.</strength>
      <examples>
        <example>"Never import unused modules" → "Import only modules you actively use; remove unused imports immediately to prevent F401 errors".</example>
        <example>"Don't assign unused variables" → "Assign variables only when you need them; use `_` for intentionally unused values to prevent F841 errors".</example>
      </examples>
    </good>
  </good_vs_poor_transformations>

  <enhancement_strategies>
    <when_to_apply>Apply these when improving existing positive rules — layer value on top rather than rewriting.</when_to_apply>
    <add_specificity>Include error codes, specific examples, concrete details.</add_specificity>
    <expand_context>Add rationale, benefits, and when to apply.</expand_context>
    <enhance_examples>Provide more detailed, actionable examples.</enhance_examples>
    <improve_clarity>Make the action more specific without losing content.</improve_clarity>
  </enhancement_strategies>

  <content_layout>
    <lead_with_positive>Always start sections with what to do.</lead_with_positive>
    <allocate_most_space_to_positive_guidance>The positive form is the carrier; supplements stay short.</allocate_most_space_to_positive_guidance>
    <end_with_positive>Conclude with positive reinforcement when wrapping a section.</end_with_positive>
  </content_layout>
</ai_instruction_writing>
