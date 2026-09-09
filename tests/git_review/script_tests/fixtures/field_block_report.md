# Review of feature/export

Reviewed commit: `abc1234`.
Tree state: clean.

## What is critical

### Network export crosses the charter

**Location:** `src/export.py:12`

**Label:** inferred

**Decides:** implementer

The new network call crosses the charter's local-only boundary.
Suggested default: standard output.
Fix: remove the network call.

## Decisions the implementer must make before fixing

### Choose local output

The implementer chooses standard output or a file path.
Suggested default: standard output.

## Can it be structurally merged as it is

Yes, the test merge is conflict-free.
