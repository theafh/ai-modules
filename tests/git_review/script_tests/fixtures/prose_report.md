I reviewed `abc1234` on `feature/export` and left the tree clean. The change is
approvable once the network export is removed. The forge layer is unavailable.
The diff changes three files with no binary or generated files. The local
`make test` gate passed; no forge checks ran. Discussion counts are unavailable.

## What the changes do and implement

The branch adds an export command.

## What it retires

The legacy table is removed.

## What of the existing workflow changes

The test target discovers tests automatically.

## What is critical

**`src/export.py:12`: network export crosses the charter (`inferred`).**

`CHARTER.md` restricts the tool to local conversion:

```markdown
### DOES

Convert local files.

### DOES NOT

Send data over the network.
```

The new `urlopen(url)` call transmits data outside the local process.
Fix: remove the network call, with output selection settled in the decisions section.

## Bugs it may introduce

**`src/export.py:20`: empty input divides by zero (`verified`, `non-blocking`).**

Calling `mean([])` raises `ZeroDivisionError`, so an empty export fails.
Fix: return the documented empty result before dividing.

## What should be fixed though it is not a clear bug

**`docs/export.md:8`: obsolete documentation heading (`inferred`, `non-blocking`).**

The documentation still describes the removed table under `### Legacy format`:

> ### Legacy format
>
> Use the legacy table for export.

That sends readers to a removed interface.
Fix: describe the current output format.

## Decisions the implementer must make before fixing

**Choose the local output for `src/export.py:12`.** The implementer chooses
between standard output and a file path. Suggested default: standard output,
because callers can redirect it to a file.

## Can it be structurally merged as it is

**Yes.** The test merge against `main` is conflict-free, the branch is one ahead
and zero behind, and no CI check states are available.
Protection-policy context is unavailable without the forge layer.
