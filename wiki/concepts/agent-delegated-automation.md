---
title: Agent-delegated automation
created: 2026-08-29
updated: 2026-10-12
type: concept
tags: [skill, agent, authoring, repo-structure]
sources: [raw/notes/agent-spinner-run-evidence-2026-09.md]
confidence: high
---

# Agent-delegated automation

## Definition

Some jobs in this repository run unattended across a whole set of interlinked
files. Auditing the task backlog, repairing it, and driving one task to
readiness are the worked examples. The repository does this by having a thin,
user-facing front-end skill hand the job to one or more spawned agents. The
agents that assess a file only read it. Exactly one agent writes. A verifier
tries to refute each proposed edit before it lands, and any genuine judgement
call goes back to the human instead of being settled in place.

The task family is the fully decomposed form of the pattern. It uses separate
agents for drift, gate, review, verification, and writing. The wiki family is
the collapsed form, where one agent does the assessing, the repairing, and the
verifying. Both are the same shape at different sizes. Both take their rules from
a base skill that the agents cite rather than copy.

## Current state of knowledge

### The front end delegates a whole-artifact job

A front-end skill is the part a user invokes, and it stays thin. `wiki_fix` does
no work of its own. It invokes the `auto_shaper_wiki` agent and passes the
agent's report straight back. `task_auto_check` drives one task from open to
ready by running a bounded loop over four task agents and applying the edits they
bless. `task_fix` repairs the whole backlog inline for mechanical fixes, and
hands the harder judgement calls to a writer agent when the user opts in or the
tree is large enough to need it.

The agents share one loop shape. They orient on the rules and the target, assess
what is wrong, remediate it, then verify the result. The roles carry stable
names. A gate applies the one readiness bar. A drift agent detects intent that
moved before repair started. A reviewer proposes the smallest repair for one
issue. A verifier keeps or rejects each proposal. A shaper is the single agent
that writes.

### Readers fan out, one writer holds the graph

The reviewer, verifier, and drift agents carry read-only levers, and the gate
writes only `task_check`'s status stamp. A lever holds only where its harness
enforces it ([agent definition portability](agent-definition-portability.md),
[Cursor](../entities/cursor.md)), and a callable shell gets around it. So the
single-writer claim also rests on each agent's body contract. Coverage comes
from running several readers. Integrity comes from letting only one agent write.

Serialization matters because the artifacts form a link graph. Task files
cross-link each other, wiki pages link each other, and an index lists them all.
Two agents writing at once would race on that shared graph and lose edits. So
file creation, moves, cross-reference rewrites, and frontmatter stamps all stay
with the one writer, which re-reads a target after any move before it edits
again. The wiki writer may still farm independent page reads out to read-only
subagents and merge their findings, because read parallelism is safe where write
parallelism is not.

### The verifier refutes by default

The verifier approves a proposal only when the task text and the recorded issue
prove the edit is needed. It rejects by default and gives a grounded reason for
each rejection. It keeps an edit only when the edit is real, is the minimum that
works, resolves the stated issue, and preserves the task's frozen intent.

The readiness loop hands each helper its inputs by path through run-local relay
files and stores each return byte for byte. The verifier therefore reads the
gate's verdict and the reviewers' own proposals rather than an orchestrator's
summary. Approved edits carry ids and exact anchored replacements.

After an approved edit group lands, the loop writes a unified diff and invokes
the verifier in delta mode. That audit maps every hunk to an approved edit id,
the timestamp stamp, or a mechanically fixable linter finding, and checks that
every approved id landed. The loop removes an unlicensed hunk or applies a
missing edit before continuing, and restores the pre-apply snapshot when the
delta cannot be verified.

The readiness gate carries the same stance in its evidence. A verdict that marks
a checklist line clean has to cite what it read. It names the artifact and the
verbatim span that settled the item. An existence check cannot clear a content
line on its own, because finding that a file exists or that a quote appears is
not the same as reading the cited passage against the claim. This closes a real
failure. A batch of tasks once stamped ready on the first pass with every line
clean, and re-checking two of them surfaced several real readiness issues each.
The fast verdict had confirmed the existence claims and skipped the comparative
reading. Making the verdict cite its evidence makes it contestable, so the loop
challenges both a first-call ready with nothing raised and a ready reached on
the last permitted gate call. A ready after repairs but before the cap takes no
citation pass. At the cap, refuted citations get one re-gate and a stuck report,
with no further body repair. Each gate walks the current task from admitted
inputs and checklist-reached code; earlier verdicts and helper transcripts stay
outside its evidence. Its isolation declaration makes an out-of-bounds read
visible and causes one fresh replacement assessment.

### Nothing is resolved silently

What makes an agent safe to run unattended is that it fabricates nothing and
settles no genuine ambiguity on its own. The readiness loop routes one class
to the user at either scale: removing most of the body or a load-bearing section,
collapsing either to a summary, and deleting or narrowing any frozen requirement,
rule, constraint, promise, or Acceptance item. A smaller edit cannot silently
win by promising less. The complete frozen task supplies the comparison, and
the route carries the original passages, the gate's fix, and the options to
prove the commitment, narrow it with an owned deferral or explicit rejection,
or delete it. Code-moved detail refreshes, required interaction supersessions,
and edits to text added during the run remain ordinary repairs. Picking one
side of a real fork or resolving an unsettled contradiction also belongs to the
user. The wiki
agent marks a contradiction between pages as contested and reports both sides
rather than choosing. The task writer reconciles only findings the user already
accepted and leaves the rest human-owned.

Every layer also freezes the task's title and goal before it touches anything,
and gates each edit on fidelity to them. The drift agent exists for one case the
others cannot see. It catches intent that already broadened past the last
committed goal before repair began, and it routes that drift to the human. An
autonomous writer validates the repository's `CHARTER.md` before it writes and
stops the run on a violation.

### The shape scales from one agent to a fan-out

The template is the same across both families. A base skill owns the rules. A
front end named for the user delegates to agents. The agents run the orient,
assess, remediate, verify loop. Readers fan out and one writer commits. Genuine
judgement calls surface to the human.

The one thing that varies is how far the assessing side is split. The task family
breaks it into four agents feeding a writer, which pays off on a large tree. The
wiki family keeps it in one agent with optional read-only page readers. The task
writer states the reuse in the open. Coverage comes from diverse proposals,
precision comes from verification, and agreement among agents is never counted as
truth. The naming reflects who invokes what, and [skill family
architecture](skill-family-architecture.md) owns that rule. A spawned agent reads
`auto_<role>_<family>`, and a front end keeps its plain family name unless it
sits beside a manual sibling, which makes it `<family>_auto_<rest>`.

### It is a mechanism, not an instruction

The verifier and the single writer are structural mechanisms, not prose telling
an agent to be careful. That is the same move [instruction-defect
classes](instruction-defect-classes.md) reaches for at its limit. Once no
instruction misdirects, a property that must always hold needs a mechanism that
carries it by construction rather than another sentence. A read-only reviewer
cannot write a bad edit, and a refute-by-default verifier cannot pass one it did
not check. The architecture spends agents to buy the property that instruction
text alone leaves sampled.

### The general rule lives in a skill, the instances keep their own runs

Everything above describes the shape as this repository runs it, and this page
is the reasoning behind it. The harness-independent form of the rule ships
separately, as the `agent_spinner` skill under
`plugins/ai_dev/skills/agent_spinner/`, with its prompt templates, worked
report shapes, degradation examples, and lower-frequency variants in that
skill's `references/`. The split follows this wiki's own dividing test: a rule
an agent needs while working in another repository has to travel with the
artefact, because the wiki travels nowhere else.

The skill is advisory, and the direction is one-way. It states the general
shape, cites the shipped surfaces by name as worked instances, and restates no
rule those surfaces already state. `task_auto_check`, `task_fix`, and
`wiki_fix` keep authority over their own runs: where one of them states its own
loop bounds, helper-failure policy, verification standard, aggregation rule, or
stop-and-ask boundary, that contract wins inside that run and the skill adds
nothing to it. The skill likewise carries none of the per-harness facts a
delegation surface rests on, which stay with the portability review that owns
them and re-verifies each one.

What the skill adds beyond this page is a floor. Every guarantee it states is
written to hold with no spawn surface at all, as a sequence of separately
prompted passes in one context, so the quality contract reads the same whether
the host fans helpers out or not. This page's architecture never had to answer
that, because the families it describes run where the spawn surface exists.

## Open questions

Whether the decomposed task-family form outperforms the collapsed wiki form is
not measured. Both ship and both work, but nothing here records what the extra
agents buy against their cost. The choice between the two rests on the size of
the tree rather than on a measured verdict.

How much an unattended verifier can catch is bounded by what it can read. The
loop reads only the verdict text an agent returns, refuses to introspect a
model's reasoning trace, and declines to pin a worker to one model, because none
of those is portable across harnesses. In three `task_auto_check` runs on Cursor
in September 2026, the way the orchestrator relayed text set that cap.
Verifiers judged paraphrases or partial reviewer text. One gate finding
bypassed them. Committed rule clusters were deleted with no user decision ([run
evidence](../raw/notes/agent-spinner-run-evidence-2026-09.md)). The frozen-task
comparison and explicit deletion route make that choice visible, while isolated
gates keep a fresh readiness assessment from inheriting an earlier conclusion.

## Related concepts

- [Skill family architecture](skill-family-architecture.md), for the base-skill
  rules the agents cite and the naming that marks a spawned agent.
- [Verification surfaces for a shipped skill](verification-surfaces.md), for the
  test-time counterpart to this run-time verification.
- [Instruction-defect classes](instruction-defect-classes.md), for why a
  must-hold property needs a mechanism rather than an instruction.
- [Guardrail documents as normative rules](guardrail-documents-as-rules.md), for
  the `CHARTER.md` fence an autonomous writer checks before it writes.
- [The ai-modules repository](../summaries/ai-modules-repository.md), for where
  these families sit among the shipped components.
- [Orchestration failure families](orchestration-failure-families.md), for the
  run evidence behind the recipes proposed for `agent_spinner`.

## Derived from

- The `agent_spinner` skill and its `references/`, which carry the general,
  harness-independent form of the rule this page reasons about.
- The `task_auto_check`, `task_fix`, and `wiki_fix` front-end skills, and the
  `auto_drift_task`, `auto_gate_task`, `auto_reviewer_task`,
  `auto_verifier_task`, `auto_shaper_task`, and `auto_shaper_wiki` agents under
  `plugins/`.
- The base `task` skill and the wiki `SCHEMA.md`, which own the rules the agents
  cite.
- Two archived backlog tasks, on the readiness gate's evidence and refutation and
  on the backlog-coherence assessment, for the observed first-pass overturns.
