---
description: "Read the real VM page size in request-concurrency-queue's macOS free-memory probe so hostAware fan-out is not throttled by a fourfold undercount on Apple Silicon."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T14:15:27Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: "Andreas Hoffmann"
design-extended: false
---

# Free-memory probe must use the real page size

## Goal

`readFreeMemoryGB` reports the machine's actual free-plus-inactive memory on macOS by using the page size `vm_stat` reports, so the `hostAware` critical-memory floor is not triggered while several GiB are genuinely free.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/subagents.ts`: `readFreeMemoryGB` parses `Pages free:` and `Pages inactive:` from `vm_stat` and multiplies the page count by a hardcoded `4096`.

On this machine `vm_stat` reports `page size of 16384 bytes` and `sysctl -n hw.pagesize` returns `16384`, so the function undercounts free memory fourfold. Measured on 2026-11-23 with `vm_stat` and `sysctl -n hw.pagesize`: 699837 free-plus-inactive pages, which the current code reports as about 2.67 GiB and the real page size reports as about 10.68 GiB.

The impact runs through `hostCapacity`: `byMemory` is `freeMemoryGB < 1 ? 1 : max`, so the undercount only lowers fan-out when the reported value falls below 1 GiB while the true value is at or above 1 GiB. A machine with 2 GiB up to just under 4 GiB genuinely free can therefore have `hostAware` collapse its ceiling to 1. The comment above `hostCapacity` states that a healthy Mac with a large inactive cache must not be mistaken for a full one, which this undercount can still cause.

The two-second metric cache lives in `readHostMetrics`, not in `readFreeMemoryGB`.

Baseline: `bun test` and `bunx tsc --noEmit` pass in the package.

## Approach

- Extract a pure helper with the signature `(vmStatOutput, fallbackPageSize)` that returns free-plus-inactive GiB, so the page size is injected and the parsing is testable without running a command.
- Give `readFreeMemoryGB` one injected command runner used for both commands, defaulting to `execFileSync`, plus an optional platform override. It runs `vm_stat`, parses the page size from the header (`page size of N bytes`), and passes that capture and page size to the helper. Only when the header is absent or unparseable does it ask the same runner for `sysctl -n hw.pagesize`; when both are unavailable it uses `4096`.
- Keep the existing fallback to `os.freemem()` when `vm_stat` fails, and keep the two-second cache in `readHostMetrics`.

**Out of scope:** Changing the `hostCapacity` thresholds or adding a second host metric.

## Acceptance

- A unit test passes on a fixture containing `Mach Virtual Memory Statistics: (page size of 16384 bytes)` and known page counts: the helper returns `pages * 16384 / 1024**3`.
- A unit test passes on a fixture whose header reports 4096-byte pages: the helper returns `pages * 4096 / 1024**3`.
- A unit test passes on output with no page-size header: the helper uses the injected fallback page size rather than assuming 4096.
- A unit test passes: `readFreeMemoryGB` with an injected runner returning a 16384-byte `vm_stat` capture returns `pages * 16384 / 1024**3`, proving the header page size reaches the helper.
- A unit test passes: `readFreeMemoryGB` with an injected runner returning a header-less capture and a `sysctl` page size uses the runner's page size in the result.
- A unit test passes: when the injected runner makes `vm_stat` throw, `readFreeMemoryGB` returns the `os.freemem()` value.
- The hardcoded `(pages * 4096) / 1024 ** 3` multiplication no longer stands in `readFreeMemoryGB`, and one canonical page-size statement remains in the function.
- `## Implementation notes` records the machine measurement: one `vm_stat` capture, the page size that capture reports, and `readFreeMemoryGB()` compared with `pages * pageSize / 1024**3` for that same capture. The pre-change 4096 figure is recorded only as the before/after contrast; no failure branch keys on it, and a 4096-byte host cannot distinguish the two paths.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/` and this task file.

## Implementation notes

Filled in at implementation time with the measurement protocol above.

Implemented 2026-11-23 on the reporting machine. `freeMemoryGBFromVmStat(vmStatOutput, fallbackPageSize)` is the new pure helper; `readFreeMemoryGB(options?)` takes an injected `run` command runner (default `execFileSync`) and an optional `platform` override, reads the page size from the `vm_stat` header, and asks the same runner for `sysctl -n hw.pagesize` only when the header is missing or unparseable, with `4096` as the last resort. The `os.freemem()` fallback and the two-second cache in `readHostMetrics` are unchanged.

Measurement (one capture, `vm_stat` header `Mach Virtual Memory Statistics: (page size of 16384 bytes)`, `sysctl -n hw.pagesize` = 16384):

- `Pages free: 183917` plus `Pages inactive: 593289` → 777206 pages in this capture.
- `pages * pageSize / 1024**3` = 777206 × 16384 / 1024³ = **11.8592 GiB**.
- `freeMemoryGBFromVmStat(capture, 4096)` on that same capture = **11.859222412109375 GiB**, which matches the computed figure exactly because the capture's own header supplies the 16384-byte page size.
- `readFreeMemoryGB({ platform: "darwin", run: () => capture })` on that same capture = **11.859222412109375 GiB** (the same exact match, proving the header page size reaches the helper).
- A live `readFreeMemoryGB()` run moments later = **11.85272216796875 GiB**, differing only by memory churn between captures.
- Before/after contrast only: the pre-change 4096 constant reports the same capture as 777206 × 4096 / 1024³ = **2.9648 GiB**, a fourfold undercount. No failure branch keys on that figure, and a 4096-byte host cannot distinguish the two paths.
