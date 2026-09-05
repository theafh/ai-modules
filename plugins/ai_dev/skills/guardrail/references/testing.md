# TESTING.md: general template and rules

The tier-2 verified guardrail for verification methodology: what counts as tested in this repository, the discipline tests follow, and how the suite runs. It sits at the verified-rule strength of the enforcement spectrum: consulted whenever work writes or audits tests, with a divergence between the work and the doc surfaced as a finding before the work claims done. Its purpose is to keep every agent session verifying to the same bar, so "the suite is green" means the same thing regardless of who, or what, ran it.

## Base template

```markdown
# Testing

## Test Design Principles

<The discipline tests follow here, stated as checkable rules grounded in
the general rules below and tightened to this repo.>

## Test Organization

<Where tests live, how files and cases are named, where fixtures live and how
they are used.>

## Stack and Runner

<The test framework(s) and versions, the runner, and any harness layers.>

## Coverage Expectations

<What every unit of work must cover, and any thresholds that gate a change.>

## Running Tests

<The exact commands: the full standard suite, focused subsets, and any
opt-in surfaces (live/external tests), each copy-runnable.>

## Test Integrity

<The rule for changing existing tests: what justifies it and who decides,
building on the direction-of-fit default that code is developed to pass the
tests, never tests adjusted to pass the code.>
```

## General rules

These are the durable defaults that hold across repositories; the doc tightens or adapts them with local specifics rather than repeating them:

- **Test observable behaviour through public contracts.** Assert on outcomes such as exit codes, outputs, state changes, and error types, so tests stay stable across refactors that preserve behaviour. Behaviour coverage beats line coverage: a metric can be satisfied by tests that assert nothing.
- **Deterministic and isolated.** Every test is independent, order-independent, and parallel-safe: per-test temporary state, no shared mutable resources, no reliance on execution order. The standard suite runs offline and deterministically; tests needing live external services are separated behind an explicit opt-in and skip cleanly without it.
- **Complete per behaviour.** Each behaviour covers the happy path, the edge cases, the error conditions, and the security scenarios where the behaviour touches a guarded surface. A fail branch is explicit: a test proves the failure case fails correctly, not only that the hoped-for direction passes.
- **Structured error assertions.** Verify errors by type, code, or variant first, with partial key-term matches on message text, never full-string message matching that breaks on rewording.
- **Spend tests where the toolchain is blind.** Focus test effort on behaviour the compiler, type system, linter, or framework cannot already guarantee: runtime boundaries, external input parsing, state round-trips, error classification, numeric logic. Prioritise the checks that would catch silent correctness bugs. A test that restates a toolchain guarantee adds run time, not safety.
- **Fixture hygiene.** Fixtures are shared, read-only source material, named after what they represent, copied into per-test scratch space rather than mutated in place.
- **Mock at infrastructure boundaries.** Stub the HTTP endpoint, the database, the external process rather than internal seams, so tests exercise the real code paths between boundaries.
- **Name by behaviour.** Test files and cases lead with the behaviour under test, then the scenario, and stay free of implementation-stage or internal-structure references, so names survive refactors and reorganisation.
- **Code rises to the tests, never the reverse.** Tests encode the intended behaviour, and the code is developed until it passes them; a test is never written or bent to ratify whatever the code currently does, and a failing test is never weakened, skipped, or removed to get a suite green. When an existing test looks wrong or outdated, surface it with the reasoning before changing it. Fixing the code or the environment comes first, and the test changes only when the behaviour it pinned is genuinely superseded. Every test stays active in the standard suite.
- **Runnable as written.** Every command the doc names is copy-runnable in the repo today.

## Tailoring

The general rules are the durable half; the repo supplies the fluid half: stack, runner, layout, naming, thresholds, commands. Language-specific test idioms stay with the repo's language conventions rather than being restated here. Verification looks different per nature: a software system documents its test suite; a knowledge repository documents its verification surface (linters, link checkers, schema and consistency checks) and what a clean run means; a meta-repository shipping components documents its regression harnesses and behavioural evals. The doc earns its place by recording the methodology an agent could not infer from the code alone.

## Consumption

Work that writes tests reads the doc before choosing the test shape; work that audits reads it before judging the test surface. An acceptance-stated but missing or failing test is a gap finding, weighed with the same rigour as the feature work. When absent, consumers continue with repo context alone.
