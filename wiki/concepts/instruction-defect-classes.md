---
title: Instruction-defect classes
created: 2026-08-15
updated: 2026-08-30
type: concept
tags: [skill, agent, authoring, verification-gap, experiment]
sources: []
confidence: medium
---

# Instruction-defect classes

## Definition

Three classes of defect recur in AI-consumed instructions, the skills, agents,
and standing rules this repository ships. Each shares one property: the rule
reads correctly to a human reviewer and fails only when an agent executes it.
Review reads a rule in isolation and passes it; the gap between "reads correctly"
and "acts correctly" opens at runtime. The three classes name where that gap
hides.

- **Reach.** The instruction names an analysis without requiring its result to
  be written down, so a shallower walk satisfies the wording while skipping the
  work the analysis exists to do. Two sub-shapes belong here. A selector or
  scope rule states what to include and never what to exclude, so an agent pulls
  in more than the caller asked for. A comparison rule scoped to the live or
  selected set ignores invariants already settled outside it, by archived work
  or by shipped code, which bind at least as hard as a live rule because they
  have already landed.
- **Disposition.** The instruction detects the right thing and then resolves it
  wrongly. Two sub-shapes. A classification verdict is allowed to end the
  inquiry without requiring the reason to be recorded, so a judgement that reads
  as "handled" leaves nothing behind for the next reader. A rule names one repair
  shape as the only allowed one where other shapes are equally valid, so
  following it produces a worse fix than the situation admits.
- **Intra-file contradiction.** Two rules in one instruction file, each sound
  alone, direct opposite actions on the same surface. An agent obeying one
  violates the other, and neither rule reads as wrong from where it sits, because
  the conflict is visible only when the two are read against each other.

## Current state of knowledge

### How the classes were found

Every instance was discovered by measurement, not by review. The three classes
come from building the backlog-coherence assessment the base `task` skill now
carries, where each defect sat in the shipped `<backlog_coherence>` block and
survived repeated reading. What surfaced them was running the behavioural evals
for that feature: an eval encoded the behaviour the instruction was meant to
produce, the agent followed the instruction literally, and the output missed the
mark. Each defect was then traced back to the rule that caused it and repaired in
place, so the block today is the worked example of all three and carries no known
instance.

This is the load-bearing lesson behind the taxonomy: for an AI-consumed
instruction, human review and agent execution test different things. Review
checks that each rule reads correctly; only execution checks that an agent
following it does the right thing. The three classes are the shapes of defect
that pass the first test and fail the second, which is why naming them helps an
author look for the specific gap rather than re-reading for general clarity.

### Why each class evades review

The evasion is structural, not a matter of care. A **reach** defect leaves the
wording complete, so a reviewer reading the rule finds nothing missing; only the
absent requirement to record the analysis shows at runtime, when the agent takes
the cheaper path the wording permits. A **disposition** defect gets the detection
right and dresses a wrong resolution in reasonable language, so it reads as sound
judgement on the page. An **intra-file contradiction** is invisible to any
single-rule read by construction: each rule is correct where it sits, and the
conflict appears only in a pairwise read of the rules governing one surface,
which ordinary review does not perform.

### The worked example of a contradiction

The sharpest instance is worth keeping, because a contradiction is the hardest of
the three to see from a description. In the base `task` skill, one rule required
"reciprocal coordination links" between two related task files while another rule
in the same file directed an author to drop a reverse-duplicate pointer whose
relationship the linked side already states. Both rules are sound in isolation.
They direct opposite edits on one surface. The conflict stayed hidden until an
agent followed the second rule and a check written against the first marked the
result wrong. The repair placed the link on the side whose work the relationship
changes, which is what the surviving rule already directed.

### The limit of repair: a sampled judgement needs a mechanism

Repairing the instruction is necessary and, measurably, not always sufficient.
The limit surfaced on the wiki agent's log-preamble drift fix, whose contract
requires an owner-added preamble line to survive every repair run. Three genuine
intra-file contradictions pulled toward deleting that line, and all three were
removed. The failure rate did not move: across the local Layer 2 harness runs of
2026-08-22, the scenario pass rate was 92% before the repairs and 90% after.
Roughly one pass in ten still rewrote the whole region and deleted the owner's
line, and every failing pass reasoned the same way, that the preamble should
equal the template.

The three classes above describe instructions that misdirect an agent, and
removing such a defect fixes the behaviour it caused. This limit is a different
thing. Once no instruction misdirects, what remains is a judgement the agent
re-makes on every run, and instruction text cannot make a judgement
deterministic; it only shifts the odds. The two cases separate by measurement:
a repaired defect moves the failure rate, while a residual judgement leaves it
where it was.

The repair that holds for a must-always-hold property removes the judgement
instead of instructing it: ship a mechanism that carries the property by
construction and reduce the instruction to invoking it. For the preamble case
that is a bundled merge script with no delete operation and a loud self-check,
so preserving the owner's line stops being sampled behaviour and becomes a
property of code; the task backlog carries that mechanism work. The
through-line matches how the classes themselves were found: reading located
the contradictions, and only measurement showed their removal changed nothing.

## Open questions

Whether to distill the taxonomy into a shipped authoring rule, in
`ai_instruction_writing`, is open and should follow evidence that the rubric
helps an author rather than enthusiasm for having found it. A task that would
merely name the three classes in that skill was filed and then withdrawn as
documentation dressed as work: the lessons were already applied where they
mattered, and a standing rule earns its place in the skill only once it is shown
to change authoring for the better. The knowledge lives here in the meantime,
which is the wiki's role as the evidence behind a rule that may or may not come.

Whether any of the three checks can be mechanized, in `skill_doctor` or
elsewhere, is unsettled. All three turn on reading intent rather than matching a
pattern, so whether a mechanical check is possible at all is a question the
hand-applied tests answer first.

Whether the taxonomy is complete, and how far it generalizes beyond the one block
it came from, is unverified. The pass that would apply it across every shipped
skill and agent has not run, so its reach past the single worked example is a
claim this page does not yet support. That is the `verification-gap` this page
carries.

## Related concepts

- [Verification surfaces for a shipped skill](verification-surfaces.md), for why
  measurement finds what review misses and how the evals that surfaced these
  defects are structured.
- [Skill family architecture](skill-family-architecture.md), for the
  rules-live-once-in-the-base-skill design the contradiction example sits inside.
- [The ai-modules repository](../summaries/ai-modules-repository.md), for where
  the shipped instruction artefacts sit among the repository's document sets.
- [Agent-delegated automation](agent-delegated-automation.md), for the verifier
  and single-writer mechanisms that carry a property the instruction only
  invokes.

## Derived from

- The shipped `<backlog_coherence>` block in `plugins/ai_dev/skills/task/SKILL.md`,
  the worked example of all three classes after their repair.
- The working session that implemented the backlog-coherence assessment, where
  each defect was surfaced by eval measurement and traced back to its rule. An
  ephemeral session with no committed artefact of its own.
- The re-audit session of 2026-08-22 that measured contradiction removal against
  the wiki agent's log-preamble fix in the local Layer 2 harness. An ephemeral
  session that left no committed record; the harness itself is committed, but
  a run of it produces only gitignored output.
