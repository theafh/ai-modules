---
title: Agent-delegated automation
created: 2026-08-29
updated: 2026-08-29
type: concept
tags: [skill, agent, authoring, repo-structure]
sources: []
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

The assessing agents are read-only by construction, not by convention. Their
frontmatter marks them read-only and restricts their tools to reading and
search, so the single-writer claim is enforced by the harness rather than
trusted. Coverage comes from running several readers. Integrity comes from
letting only one agent write.

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

The readiness gate carries the same stance in its evidence. A verdict that marks
a checklist line clean has to cite what it read. It names the artifact and the
verbatim span that settled the item. An existence check cannot clear a content
line on its own, because finding that a file exists or that a quote appears is
not the same as reading the cited passage against the claim. This closes a real
failure. A batch of tasks once stamped ready on the first pass with every line
clean, and re-checking two of them surfaced several real readiness issues each.
The fast verdict had confirmed the existence claims and skipped the comparative
reading. Making the verdict cite its evidence makes it contestable, so the loop
sends a first-pass ready approval back through the verifier before it trusts the
stamp.

### Nothing is resolved silently

What makes an agent safe to run unattended is that it fabricates nothing and
settles no genuine ambiguity on its own. A change that removes most of a body,
deletes a load-bearing section, picks one side of a real fork, or resolves a
contradiction is a decision for the user, not an approvable repair. The wiki
agent marks a contradiction between pages as contested and reports both sides
rather than choosing. The task writer reconciles only findings the user already
accepted and leaves the rest human-owned.

Every layer also freezes the task's title and goal before it touches anything,
and gates each edit on fidelity to them. The drift agent exists for one case the
others cannot see. It catches intent that already moved away from the first
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

## Open questions

Whether the decomposed task-family form outperforms the collapsed wiki form is
not measured. Both ship and both work, but nothing here records what the extra
agents buy against their cost. The choice between the two rests on the size of
the tree rather than on a measured verdict.

How much an unattended verifier can catch is bounded by what it can read. The
loop reads only the verdict text an agent returns, refuses to introspect a
model's reasoning trace, and declines to pin a worker to one model, because none
of those is portable across harnesses. That keeps the pattern portable and caps
how deeply it can verify, and where that cap falls has not been mapped.

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

## Derived from

- The `task_auto_check`, `task_fix`, and `wiki_fix` front-end skills, and the
  `auto_drift_task`, `auto_gate_task`, `auto_reviewer_task`,
  `auto_verifier_task`, `auto_shaper_task`, and `auto_shaper_wiki` agents under
  `plugins/`.
- The base `task` skill and the wiki `SCHEMA.md`, which own the rules the agents
  cite.
- Two archived backlog tasks, on the readiness gate's evidence and refutation and
  on the backlog-coherence assessment, for the observed first-pass overturns.
