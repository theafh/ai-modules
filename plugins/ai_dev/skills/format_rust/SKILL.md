---
name: format_rust
description: Apply clippy-aligned Rust practices when writing or editing Rust code (.rs). Covers procedural flow, clippy-driven clarity improvements, minimal imports, Result/Option idioms, fallible builders with project error types, string prefix/suffix handling, borrowing clarity, iteration style, string building, and function signature grouping.
version: 1.3.0
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

## Results and Options

Return results directly and keep control flow simple, using the minimal wrapping needed for clear error propagation.

## Fallible builders

Use the project-standard error type and Result flow for fallible builder APIs; convert builder failures into the error type used in this codebase and return them instead of panicking.

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
