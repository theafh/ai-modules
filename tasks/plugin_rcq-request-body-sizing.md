---
description: "Rebuild request-concurrency-queue's cheap request-body measurement by counting streamed UTF-8 bytes, keeping image detection, and parsing only when a body may carry an image."
scope: harness-plugins/opencode_v2/request-concurrency-queue
created: 2026-11-23T10:01:27Z
updated: 2026-11-23T18:48:55Z
status: implemented
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: true
---

# Request sizing: count UTF-8 bytes, parse only when a body may carry an image

## Goal

A text-only request body that carries no `content-length` header is measured by counting its streamed UTF-8 bytes, without building a decoded string or calling `JSON.parse`, and a body with an embedded image keeps its image accounting whichever side of the scan threshold it falls on. Only a body above the threshold, or one whose bytes look like a base64 payload, is decoded and parsed. Every path reports its size in the same unit.

## Context

`harness-plugins/opencode_v2/request-concurrency-queue/src/index.ts`:

- `measureBody` returns the declared length only when `request.headers.get("content-length")` parses to a positive number at or below `IMAGE_SCAN_BYTES` (256000). Every other body is cloned, read fully into a string, and passed to `measureText`, which `JSON.parse`s it. A body with no body at all returns zeros early.
- `measureText`'s non-image text count is the sum of each string value's `length`, a count of UTF-16 code units, while `estimateTokens` treats its argument as bytes (`BYTES_PER_TOKEN` is documented as bytes per token). A small body measured in bytes followed by a large body measured in code units can make the per-session delta negative, so the later turn is charged zero new tokens.
- `measureBody` is module-private; the package exports no byte-count or cost accessor.

Verified in Bun on this repository's toolchain: `new Request(url, { method: "POST", body }).headers.get("content-length")` is `null`, so the cheap path is dead code unless the runtime supplies the header, which is unverified. The package README's limitations bullet says "A body under 256000 bytes is charged by its declared length; a larger one is read once and scanned for image payloads", and the `measureBody` doc comment says the same.

Reading a clone still tees the unread original branch into memory, so this change reduces decoding and parsing for small text bodies but does not lower peak memory for a large one.

Baseline: `bun test` and `bunx tsc --noEmit` pass in the package.

## Approach

- Export `measureBody` from `src/index.ts` as the test seam, as the package already exports its other testable helpers, and put the tests in `test/index.test.ts`.
- Clone the request once, read the clone's body in `Uint8Array` chunks, and keep a running raw byte total. Retain the chunks up to `IMAGE_SCAN_BYTES`; once the threshold is crossed, keep appending the remaining chunks so the parse path can see the whole body.
- Report `textBytes` as raw UTF-8 body bytes minus the bytes of every image payload, on the streamed small and parsed large paths. That single formula keeps a small and a large measurement comparable, so the delta between two requests stays meaningful. The declared-length shortcut is a separate path that returns `images: 0` without subtraction.
- Below the threshold, match over the retained `Uint8Array` bytes with no text projection: an ASCII match for `;base64,` and for a run of 2048 base64 bytes, skipping the two-byte `\n`, `\r`, and `\/` escape sequences as it goes. When neither matches, return `{ textBytes: total, images: 0 }` with no decode and no parse. When one matches, fall through to the buffered parse so the payload keeps its image charge. A body of exactly `IMAGE_SCAN_BYTES` takes the below-threshold path.
- Above the threshold, concatenate the retained chunks with the remainder, decode once, and pass the full text and the raw total to `measureText`.
- On the parsed path, subtract each image payload's UTF-8 byte length from the raw total. When the JSON is malformed, return the raw byte total instead.
- Keep the declared-length shortcut only when the declared value is at or below `IMAGE_SCAN_BYTES`; an above-threshold declared length still streams and scans.
- Keep the failure path: an unreadable body returns `{ textBytes: 0, images: 0 }` and logs.
- Rewrite the `measureBody` doc comment, the `IMAGE_SCAN_BYTES` doc comment, the `estimateRequestCost` comment, and the package README's limitations bullet to the counted-bytes behaviour, removing every "charged by its declared length" claim and stating the prefilter's detection boundary.

**Out of scope:** Changing `IMAGE_SCAN_BYTES`, `IMAGE_TOKENS`, `BYTES_PER_TOKEN`, or the delta-based new-token accounting.

## Acceptance

- A measurement test passes: a small JSON body in a `Request` built without a `content-length` header returns `textBytes` equal to its raw UTF-8 byte length and `images: 0`.
- A measurement test passes: the small text-only path builds no string projection, proven by spies on `JSON.parse`, `TextDecoder.prototype.decode`, and `Buffer.prototype.toString`.
- A measurement test passes: a body below `IMAGE_SCAN_BYTES` containing a base64 image returns `images: 1` and a `textBytes` that excludes the image bytes, proving the prefilter falls through to the parse path.
- A measurement test passes: a body below `IMAGE_SCAN_BYTES` containing a JSON-escaped, line-wrapped base64 blob carrying a `+`, `/`, or `=` character (no `;base64,` marker and no contiguous run in the raw bytes) still returns `images: 1`; the fixture is a `ReadableStream` body that splits the blob across two chunks, so the chunk-spanning claim is actually exercised.
- A measurement test passes: a body above `IMAGE_SCAN_BYTES` containing a base64 image returns `images: 1` and the exact text byte count derived from the fixture, and the same text measured below the threshold reports the same `textBytes`, so the two paths agree on quantity.
- A measurement test passes: a body above `IMAGE_SCAN_BYTES` whose JSON is malformed returns its raw UTF-8 byte length rather than zero.
- A measurement test passes: an unreadable body returns `{ textBytes: 0, images: 0 }` and logs.
- A measurement test passes: a request carrying an explicit `content-length` above `IMAGE_SCAN_BYTES` still streams and scans, and one at or below the threshold uses the declared length.
- The `measureBody` doc comment, the `IMAGE_SCAN_BYTES` doc comment, the `estimateRequestCost` comment, and the package README's limitations bullet state the counted-bytes behaviour and the prefilter's detection boundary (escaped line breaks are covered; `\uXXXX`-escaped payloads are not), and no passage still says a body under the threshold is charged by its declared length.
- The diff this task produces touches no tracked file outside `harness-plugins/opencode_v2/request-concurrency-queue/` and this task file.
