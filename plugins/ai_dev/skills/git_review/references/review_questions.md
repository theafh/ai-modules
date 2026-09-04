# Per-file review questions

Read this list once per changed file, in the order the name-status listing gives
them. Read the whole file rather than the hunk, sample nothing, and treat every
comment and docstring as a claim about the code rather than a description of it.

## Questions to ask of each changed file

1. What does this file do now that it did not do before, stated as behaviour
   rather than as a list of edited lines?
2. Which callers reach the changed code, and does each of them still hold after
   the change?
3. Which inputs does the changed code accept, and what does it do with the ones
   outside the range the author had in mind, meaning empty, absent,
   oversized, concurrent, or malformed?
4. Which error paths does the change add, and does each one leave the system in
   a state a later call can recover from?
5. What did the change delete or replace, and does anything still depend on the
   deleted behaviour?
6. Which invariant does the surrounding module rely on, and does the change keep
   it?
7. Where the change adds a test, does that test fail against the pre-change
   code? Where it changes a test, does the new assertion still describe the
   behaviour the user needs?
8. Which claim in the commit message, the pull request body, or an author reply
   does this file settle, confirm, or contradict?
9. Which documentation, standing instruction, or generated artifact names this
   file, and does that reference still hold after the change?

## Four lenses, selected by what the diff touches

Apply a lens when the diff carries its trigger, and leave it aside otherwise.
Every lens stays language-agnostic: a rule specific to one stack reaches the
review through the repository's own declared criteria instead of through this
list.

### Migration safety and reversibility

Trigger: the change alters stored data, a schema, a persisted format, or a
protocol two deployed versions must both speak.

Ask whether the old and new forms can coexist while the rollout runs, what a
partial application leaves behind, and how an operator reverses the change after
data has been written in the new form.

### Definition-versus-consumer drift

Trigger: the change edits a definition that something elsewhere in the tree
reads, such as a schema, an interface, a constant, a configuration key, or a
generated stub.

Find every consumer of the definition in the tree and state, per consumer,
whether it still agrees with the new definition. A consumer left on the old
shape is a required finding: name the consumer and the field or symbol that
diverged.

### Abstraction weighed against the actual requirement

Trigger: the change introduces an indirection with fewer than two distinct
callers in the tree, such as a base class, an interface, a plugin point, a
configuration layer, or a generic parameter.

Ask what the abstraction buys against the requirement the change actually
states. Report the gap as something for the author to weigh rather than as a
defect, since the second caller may be the next commit.

### Coupling introduced across a module boundary

Trigger: the change adds a reference from one module, package, or layer to
another it did not previously depend on.

Name the new edge, say which direction it runs, and state what it costs: whether
it inverts a declared dependency direction, closes a seam a test relied on, or
makes one module unshippable without the other.
