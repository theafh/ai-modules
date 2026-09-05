---
name: format_rust
description: Apply clippy-aligned Rust practices when writing or editing Rust code (.rs). Covers procedural flow, clippy-driven clarity improvements, minimal imports, Result/Option idioms, the error-versus-invariant model with panic discipline and clippy unwrap_used enforcement, fallible builders following the error idiom by consumer, string prefix/suffix handling, borrowing clarity, iteration style, string building, and function signature grouping.
version: 1.3.2
author: Andreas F. Hoffmann
license: MIT
---

# format_rust

## Preferred style

Use clear, procedural flow with small, single‑purpose functions and explicit data flow; keep names concrete so intent is obvious at a glance.

## Clippy‑driven improvements

Write code that naturally satisfies clippy by choosing the simplest correct form, and treat clippy warnings as signals to improve clarity, safety, and maintainability.

## Imports

Use only necessary imports and prefer direct module paths; remove unused imports promptly to keep warnings clean.

## Errors versus broken invariants

Treat a failure the world causes, such as a missing file, malformed input, a value that does not parse, or a timeout, as a `Result` the caller handles with `?`. Treat a failure that means one of the program's own guarantees is false as a panic, because continuing would compute on state already known to be void. Reach for `unwrap` only in that second category: it is an assertion, not a fallback. At each fallible call, decide whether failure there means the world is wrong or the code is wrong, and route accordingly. Using `unwrap` because writing the error type is tedious claims a broken invariant while actually sitting in an unhandled error.

## Fallible builders

Route fallible builder APIs through `Result` and the error idiom the consumer of that API selects under **Error idiom follows the consumer**, returning that error type from the builder rather than panicking.

## Panic discipline across a trust boundary

On any path reachable from input the process does not control, return a typed error the caller handles. The constructs that panic on failure are `unwrap`, `expect`, direct indexing and slicing, and arithmetic that can overflow; treat each as a defect on that path, because an input that reaches one is a remotely triggerable denial of service.

## An expect message names the invariant

Where a panic is the correct outcome, write an `expect` whose message names the invariant the site rests on rather than the symptom, and leave bare `unwrap` behind. That message makes the claim reviewable: a reader can check the stated invariant, while a bare `unwrap` cannot distinguish a proven claim from a skipped error path.

## Error idiom follows the consumer

Use `anyhow` for a failure an operator reads, such as startup, CLI, scaffolding, or configuration, so context chains stay the right shape for a human reading a log. Use a typed `thiserror` enum for a failure a caller must act on programmatically, choosing between a status code, a fallback, and a degraded result, so the caller matches a variant. Carry both idioms in one codebase as a deliberate split by consumer. Put severity classification in the error type so one class of failure stays fatal or a warning consistently across call sites, and let the public response follow the variant rather than the error's text: the type picks what a caller outside the process is told, while the `Display` string stays on the operator channel.

## Downcasting to classify is the signal for a typed boundary

When recovering a concrete error class by downcasting a boxed error at several call sites, introduce a typed enum at that boundary, because a class no caller recognises falls through to the default arm silently. Prefer a `thiserror` derive over a hand-rolled `Display` and `Error` impl pair.

## Every panic has an owner

Treat a catch-panic layer as covering only the stack it wraps, and give every surface outside it its own containment. For spawned work, retain the join handle, or collect handles in a join set, and log the resulting join error, so a panicking background task fails loudly instead of quietly ceasing to do its job while the process keeps serving.

## Structural enforcement through clippy

Deny `clippy::unwrap_used` while leaving `clippy::expect_used` allowed so every intentional panic must carry a message someone can check. Wire both as a `[lints.clippy]` table in `Cargo.toml`. They are allow-by-default restriction lints, so a `-D warnings` build alone passes over them and review would otherwise carry the rule. Opt test code out explicitly: `#![cfg_attr(test, allow(clippy::unwrap_used))]` at the crate root for unit tests, and `#![allow(clippy::unwrap_used)]` at the head of each integration-test file. That table applies to every target, so the opt-outs are what keep test helpers usable.

## What denying unwrap does not buy

Keep a catch-panic layer either way: denying `unwrap` removes few panic sources, because out-of-bounds indexing, division by zero, debug-build overflow, a double `RefCell` borrow, stack exhaustion that cannot be caught at all, and every dependency all still panic. The lint stops that layer from being used as an error strategy; what it buys is no *unexplained* panics rather than fewer panics. Leave two related levers unused on purpose: `clippy::indexing_slicing` covers the indexing half of the trust-boundary rule and is noisy enough to fight an author daily, and for arithmetic prefer `overflow-checks = true` on the release profile over a lint because it turns a silent wrong number into a caught panic.

## Option predicates

Use idiomatic Option helpers such as `is_some_and` to express predicates clearly and keep intent obvious.

## String prefix handling

Use `strip_prefix` or `strip_suffix` to handle fixed prefixes and suffixes for safe, readable string handling.

## Borrowing clarity

Return or pass references directly so lifetimes remain clear and borrow scopes stay minimal.

## Iteration style

Use loop forms that match iterator intent and keep borrow scopes minimal, choosing the form that supports safe consumption.

## String building

Use `push` for single characters and `push_str` for multi-character segments to keep string construction clear.

## Function signatures

Group related parameters into structs or configuration types to keep function signatures concise and maintainable.
