---
description: Give format_rust an error and panic model: errors versus broken invariants, trust-boundary panic discipline, anyhow/thiserror by consumer, panic ownership, and clippy unwrap_used wiring.
scope: plugins/ai_dev/skills/format_rust
created: 2026-08-09T14:17:31
updated: 2026-08-09T14:17:31
status: open
reported-by: Andreas Hoffmann
---

# Anchor the Rust Error and Panic Model in format_rust

## Goal

`format_rust` carries the decision model an agent applies when a Rust operation can fail, so failures get routed by category rather than by whichever construct is shortest to type. The skill states when a failure is a value and when it is a broken invariant, which panicking constructs are defects on a path fed by input the process does not control, which error idiom fits which consumer, who owns a panic raised outside a catch-panic layer, and how the discipline holds structurally through clippy rather than through an author remembering it.

## Context

- The skill is `plugins/ai_dev/skills/format_rust/SKILL.md`. Two sections touch this ground today and neither settles it. `## Results and Options` says only "Return results directly and keep control flow simple, using the minimal wrapping needed for clear error propagation", and `## Fallible builders` says to "Use the project-standard error type and Result flow for fallible builder APIs" and to "convert builder failures into the error type used in this codebase and return them instead of panicking". Neither tells an agent how to choose between returning and panicking, and panics, `unwrap`, `expect`, and clippy's restriction lints appear nowhere in the file.
- The `format_*` family is plain markdown: a `## <Topic>` heading carrying one sentence or a short bullet list, with no pseudo-XML. `format_python` follows that shape at roughly 171 lines against this skill's 54, so there is room to add without restructuring.
- This material is general Rust knowledge that an agent needs while writing Rust in other repositories, so it belongs in the skill rather than in this repo's wiki, per the standing repo rule on where durable knowledge lives.
- The authoring rules for the edit itself are the standing repo rules on positive action-oriented language and on writing a skill `description` for both the router and a browsing user.

## Approach

Rewrite the two affected sections in place and add the missing ones, so one canonical statement of error-idiom choice remains in the file rather than a new section competing with the two that already gesture at it. Fold `## Results and Options` into the error-model statement, and rewrite `## Fallible builders` so it defers to the idiom-by-consumer rule instead of restating "the project-standard error type" as an independent instruction. Keep the family's plain-markdown `## <Topic>` shape, and keep each statement general: the skill states the rule, and worked examples stay out.

The skill states these rules:

- **Errors versus broken invariants.** A failure the world causes — a missing file, malformed input, a value that does not parse, a timeout — is a `Result` the caller handles with `?`. A failure meaning one of the program's own guarantees is false is a panic, because continuing computes on state already known to be void. `unwrap` belongs to that second category: it is an assertion, not a fallback. Reaching for it because writing the error type is tedious claims a broken invariant while actually sitting in an unhandled error, and that substitution is the failure mode rather than `unwrap` itself. The question at each fallible call is whether a failure there means the world is wrong or the code is wrong.
- **Panic discipline across a trust boundary.** On any path reachable from input the process does not control, the constructs that panic on failure — `unwrap`, `expect`, direct indexing and slicing, and arithmetic that can overflow — are defects, because an input that reaches one is a remotely triggerable denial of service. Such a path returns a typed error the caller handles.
- **An `expect` message names the invariant.** Where a panic is the correct outcome, the site carries an `expect` whose message names the invariant it rests on rather than the symptom, and a bare `unwrap` is the form to leave behind. That message is what makes the claim reviewable: a reader can check the stated invariant, while a bare `unwrap` cannot distinguish a proven claim from a skipped error path.
- **Error idiom follows the consumer.** A failure an operator reads — startup, CLI, scaffolding, configuration — carries `anyhow`, whose context chains are the right shape for a human reading a log. A failure a caller must act on programmatically, choosing between a status code, a fallback, and a degraded result, carries a typed `thiserror` enum so the caller matches a variant. Two idioms in one codebase is a deliberate split by consumer rather than inconsistency. Severity classification belongs in the error type, so one class of failure cannot be fatal at one call site and a warning at another, and the public response follows the variant rather than the error's text: the type picks what a caller outside the process is told, while the `Display` string stays on the operator channel.
- **Downcasting to classify is the signal for a typed boundary.** Recovering a concrete error class by downcasting a boxed error at several call sites means that boundary wants a typed enum, because a class no caller recognises falls through to the default arm silently. A hand-rolled `Display` and `Error` impl pair is what a `thiserror` derive replaces.
- **Every panic has an owner.** A catch-panic layer covers only the stack it wraps, so every surface outside it owns its own containment. Spawned work retains its join handle, or collects handles in a join set, and logs the resulting join error, so a panicking background task fails loudly instead of quietly ceasing to do its job while the process keeps serving.
- **Structural enforcement through clippy.** `clippy::unwrap_used` and `clippy::expect_used` are allow-by-default restriction lints, so a `-D warnings` build passes over both and review alone carries the rule. Denying `unwrap_used` while leaving `expect_used` allowed makes the discipline structural: every intentional panic then has to carry a message someone can check. Wire it as a `[lints.clippy]` table in `Cargo.toml`. That table applies to every target, so test code opts out explicitly, with `#![cfg_attr(test, allow(clippy::unwrap_used))]` at the crate root for unit tests and `#![allow(clippy::unwrap_used)]` at the head of each integration-test file.
- **What denying `unwrap` does not buy.** It removes few panic sources: out-of-bounds indexing, division by zero, debug-build overflow, a double `RefCell` borrow, stack exhaustion that cannot be caught at all, and every dependency all still panic. A catch-panic layer stays necessary either way, and the lint stops that layer from being used as an error strategy. What it buys is no *unexplained* panics rather than fewer panics. Two related levers stay deliberately unused: `clippy::indexing_slicing` covers the indexing half of the trust-boundary rule and is noisy enough to fight an author daily, and for arithmetic `overflow-checks = true` on the release profile beats a lint because it turns a silent wrong number into a caught panic.

**Out of scope:**

- Applying the model to any particular repository's Rust code, since the skill states the rule and each project's own guardrails and backlog carry its alignment work.
- An equivalent error model for `format_python` or any other `format_*` sibling.
- Bundled scripts, references, or a lint fixture inside the skill; the deliverable is the skill body's prose.

## Acceptance

- The skill states the error-versus-invariant split, and `rg 'unwrap' plugins/ai_dev/skills/format_rust/SKILL.md` returns the passage naming `unwrap` as an assertion rather than a fallback, where it returns nothing today.
- The skill states the trust-boundary rule and names all four panicking construct classes it covers: `unwrap`, `expect`, direct indexing and slicing, and overflow-capable arithmetic.
- The skill states that a sanctioned panic carries an `expect` message naming its invariant rather than the symptom.
- The skill states the `anyhow`-versus-`thiserror` split by consumer, and states that severity classification and the public response both follow the error type rather than the call site or the `Display` text.
- The skill names downcasting-to-classify as the signal that a boundary wants a typed enum.
- The skill states panic ownership for spawned work, naming the retained join handle and the logged join error.
- The skill states the clippy wiring completely enough to apply it: `unwrap_used` denied with `expect_used` left allowed, both allow-by-default so a `-D warnings` build passes over them, the `[lints.clippy]` table in `Cargo.toml`, and the two test opt-out attributes.
- The skill states what denying `unwrap` does not buy, naming panic sources outside `unwrap` and dependencies, and names the two deliberately unused levers with the reason each stays out.
- `rg 'minimal wrapping' plugins/ai_dev/skills/format_rust/SKILL.md` returns nothing, and the `## Fallible builders` passage no longer stands as a second, independent instruction on which error type to use — one canonical statement of error-idiom choice remains in the file.
- The frontmatter `description` names the added coverage — the error model, panic discipline, and lint enforcement — alongside the topics it already lists.
