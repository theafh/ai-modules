import { describe, expect, spyOn, test } from "bun:test"
import { Buffer } from "node:buffer"
import { measureBody } from "../src/index.js"

// Request sizing is measured in UTF-8 bytes, so every expected value here is a
// byte count, not a JavaScript string length.

const url = "https://example.test/chat"
const noLog = () => {}

/** A POST request that carries no declared length, so its body is counted. */
const request = (body: BodyInit) => new Request(url, { method: "POST", body })

const byteLength = (text: string) => Buffer.byteLength(text, "utf8")

/** A request body whose only variable part is the image payload. */
function bodyWithImage(payload: string): string {
  return JSON.stringify({
    model: "test",
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text: "hello" },
          { type: "image_url", image_url: { url: payload } },
        ],
      },
    ],
  })
}

const dataUri = (chars: number) => `data:image/png;base64,${"A".repeat(chars)}`

describe("a small text-only body is counted, not projected", () => {
  test("a body without a content-length header reports its raw UTF-8 bytes", async () => {
    const body = JSON.stringify({ text: "héllo → 世界" })
    const req = request(body)
    expect(req.headers.get("content-length")).toBeNull()
    // The fixture only proves byte counting if its code-unit length differs.
    expect(body.length).not.toBe(byteLength(body))

    expect(await measureBody(req, noLog)).toEqual({ textBytes: byteLength(body), images: 0 })
  })

  test("the text-only path builds no decoded string and parses nothing", async () => {
    const body = JSON.stringify({ text: "no image in this one" })
    const parse = spyOn(JSON, "parse")
    const decode = spyOn(TextDecoder.prototype, "decode")
    const toString = spyOn(Buffer.prototype, "toString")
    let measured
    try {
      measured = await measureBody(request(body), noLog)
      // Read the counts before restoring: `mockRestore` clears them.
      expect(parse).not.toHaveBeenCalled()
      expect(decode).not.toHaveBeenCalled()
      expect(toString).not.toHaveBeenCalled()
    } finally {
      parse.mockRestore()
      decode.mockRestore()
      toString.mockRestore()
    }

    expect(measured).toEqual({ textBytes: byteLength(body), images: 0 })
  })

  test("a body of exactly the scan threshold stays on the prefiltered path", async () => {
    // Spaces keep the fixture out of the base64 alphabet, so a match here would
    // mean the threshold itself was crossed rather than the prefilter matching.
    const body = " ".repeat(256_000)
    expect(byteLength(body)).toBe(256_000)
    const parse = spyOn(JSON, "parse")
    const decode = spyOn(TextDecoder.prototype, "decode")
    let measured
    try {
      measured = await measureBody(request(body), noLog)
      expect(parse).not.toHaveBeenCalled()
      expect(decode).not.toHaveBeenCalled()
    } finally {
      parse.mockRestore()
      decode.mockRestore()
    }

    expect(measured).toEqual({ textBytes: 256_000, images: 0 })
  })
})

describe("an image payload is excluded from the text count", () => {
  test("a data URI below the threshold is parsed and its bytes subtracted", async () => {
    const payload = dataUri(40_000)
    const body = bodyWithImage(payload)
    expect(byteLength(body)).toBeLessThan(256_000)

    const measured = await measureBody(request(body), noLog)
    expect(measured.images).toBe(1)
    expect(measured.textBytes).toBe(byteLength(bodyWithImage("")))
  })

  test("a JSON-escaped blob split across chunks is still recognised", async () => {
    // A base64 blob wrapped at 64 characters and encoded by JSON.stringify as
    // `\n` escapes, so the raw body has no contiguous 2048-character run. One
    // `/` is escaped as `\/`, the other escape shape the prefilter steps over.
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    let blob = ""
    for (let index = 0; index < 3_000; index += 1) blob += alphabet[index % alphabet.length]
    blob += "=="
    const lines: string[] = []
    for (let index = 0; index < blob.length; index += 64) lines.push(blob.slice(index, index + 64))
    const wrapped = lines.join("\n")
    const escaped = JSON.stringify({
      messages: [{ role: "user", content: [{ type: "image", data: wrapped }] }],
    }).replace("/", "\\/")

    expect(escaped).not.toContain(";base64,")
    expect(escaped).toContain("\\n")
    expect(/[A-Za-z0-9+/=]{2048}/.test(escaped)).toBe(false)
    expect(byteLength(escaped)).toBeLessThan(256_000)

    // Split inside the blob so the run the prefilter follows crosses the two
    // stream chunks.
    const bytes = new TextEncoder().encode(escaped)
    const blobStart = byteLength(escaped.slice(0, escaped.indexOf('"data":"') + '"data":"'.length))
    const blobEnd = byteLength(escaped.slice(0, escaped.lastIndexOf('"')))
    const cut = blobStart + Math.floor((blobEnd - blobStart) / 2)
    expect(cut).toBeGreaterThan(blobStart)
    expect(cut).toBeLessThan(blobEnd)

    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(bytes.slice(0, cut))
        controller.enqueue(bytes.slice(cut))
        controller.close()
      },
    })
    const req = new Request(url, { method: "POST", body: stream })
    expect(req.headers.get("content-length")).toBeNull()

    expect((await measureBody(req, noLog)).images).toBe(1)
  })

  test("the streamed and parsed paths report the same text bytes", async () => {
    const smallBody = bodyWithImage(dataUri(40_000))
    const largeBody = bodyWithImage(dataUri(300_000))
    expect(byteLength(smallBody)).toBeLessThan(256_000)
    expect(byteLength(largeBody)).toBeGreaterThan(256_000)

    const small = await measureBody(request(smallBody), noLog)
    const large = await measureBody(request(largeBody), noLog)

    expect(small.images).toBe(1)
    expect(large.images).toBe(1)
    // The two fixtures differ only in the payload length, so subtracting the
    // payload bytes leaves the same text on both paths.
    expect(large.textBytes).toBe(byteLength(bodyWithImage("")))
    expect(small.textBytes).toBe(large.textBytes)
  })

  test("malformed JSON above the threshold reports its raw byte length", async () => {
    const body = `{"messages":["${"x".repeat(300_000)}"`
    expect(byteLength(body)).toBeGreaterThan(256_000)

    expect(await measureBody(request(body), noLog)).toEqual({
      textBytes: byteLength(body),
      images: 0,
    })
  })
})

describe("a wrapped blob is measured the same on both sides of the threshold", () => {
  // The parser's floor is 2048 characters of the decoded payload, counting the
  // `\n` an escaped wrap turns into. The prefilter's run must count those
  // escapes too, or a payload the parser calls an image is missed below the
  // threshold and reported as text.
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  /** A bare base64 blob of `chars` characters, cycling the full alphabet. */
  const blob = (chars: number) => {
    let text = ""
    for (let index = 0; index < chars; index += 1) text += alphabet[index % alphabet.length]
    return text
  }
  /** A blob wrapped at 64 characters, so JSON writes a `\n` escape per line. */
  const wrap = (text: string) => {
    const lines: string[] = []
    for (let index = 0; index < text.length; index += 64) lines.push(text.slice(index, index + 64))
    return lines.join("\n")
  }
  const imageBody = (payload: string) =>
    JSON.stringify({ messages: [{ role: "user", content: [{ type: "image", data: payload }] }] })
  // Appending to the last line grows the payload without adding a line break,
  // so the escape overhead is identical and the text count is comparable.
  const FILLER = "A".repeat(260_000)

  test("a line-wrapped blob just under the run length is an image on both paths", async () => {
    const payload = wrap(blob(2_040))
    // The decoded payload clears the parser's 2048-character floor, while the
    // raw bytes hold no contiguous run of 2048 base64 characters.
    expect(payload.length).toBeGreaterThanOrEqual(2_048)
    expect(/[+/=]/.test(payload)).toBe(true)

    const below = imageBody(payload)
    const above = imageBody(payload + FILLER)
    expect(byteLength(below)).toBeLessThan(256_000)
    expect(byteLength(above)).toBeGreaterThan(256_000)
    expect(/[A-Za-z0-9+/=]{2048}/.test(below)).toBe(false)

    const small = await measureBody(request(below), noLog)
    const large = await measureBody(request(above), noLog)

    expect(small.images).toBe(1)
    expect(large.images).toBe(1)
    expect(small.textBytes).toBe(byteLength(below) - payload.length)
    expect(large.textBytes).toBe(byteLength(above) - (payload.length + FILLER.length))
    expect(large.textBytes).toBe(small.textBytes)
  })

  test("a wrapped blob with an escaped slash is an image on both paths", async () => {
    // 2017 base64 characters plus 31 wrap escapes make exactly 2048 decoded
    // characters. The one `/` is written as `\/`, so the raw run holds 2016
    // base64 bytes and only a scan that counts each escape reaches the floor.
    let base = ""
    for (let index = 0; index < 2_017; index += 1) base += letters[index % letters.length]
    base = `${base.slice(0, 1_000)}/${base.slice(1_001)}`
    const payload = wrap(base)
    expect(payload.length).toBe(2_048)
    expect(payload).toContain("/")

    const below = imageBody(payload).replace("/", "\\/")
    const above = imageBody(payload + FILLER).replace("/", "\\/")
    expect(below).toContain("\\/")
    expect(byteLength(below)).toBeLessThan(256_000)
    expect(byteLength(above)).toBeGreaterThan(256_000)
    expect(/[A-Za-z0-9+/=]{2048}/.test(below)).toBe(false)

    const small = await measureBody(request(below), noLog)
    const large = await measureBody(request(above), noLog)

    expect(small.images).toBe(1)
    expect(large.images).toBe(1)
    expect(small.textBytes).toBe(byteLength(below) - payload.length)
    expect(large.textBytes).toBe(byteLength(above) - (payload.length + FILLER.length))
    expect(large.textBytes).toBe(small.textBytes)
  })

  test("a bare blob of 2047 unwrapped characters is not an image on either path", async () => {
    // One character short of the parser's floor, and no escape to count, so the
    // prefilter must not reach its run on either path either.
    const base = blob(2_047)
    expect(base).toHaveLength(2_047)
    expect(/[+/=]/.test(base)).toBe(true)

    const below = imageBody(base)
    // The filler is a separate value so the payload stays one character short
    // while the body still crosses the threshold.
    const above = JSON.stringify({
      messages: [{ role: "user", content: [{ type: "image", data: base }] }],
      pad: FILLER,
    })
    expect(byteLength(below)).toBeLessThan(256_000)
    expect(byteLength(above)).toBeGreaterThan(256_000)

    expect(await measureBody(request(below), noLog)).toEqual({
      textBytes: byteLength(below),
      images: 0,
    })
    expect(await measureBody(request(above), noLog)).toEqual({
      textBytes: byteLength(above),
      images: 0,
    })
  })
})

describe("a declared length decides only the small path", () => {
  test("a declared length at or below the threshold is used as the text size", async () => {
    const body = JSON.stringify({ text: "hello" })
    const declared = (value: number) =>
      new Request(url, {
        method: "POST",
        body,
        headers: { "content-length": String(value) },
      })

    const parse = spyOn(JSON, "parse")
    const decode = spyOn(TextDecoder.prototype, "decode")
    let below
    try {
      below = await measureBody(declared(500), noLog)
      expect(parse).not.toHaveBeenCalled()
      expect(decode).not.toHaveBeenCalled()
    } finally {
      parse.mockRestore()
      decode.mockRestore()
    }

    expect(below).toEqual({ textBytes: 500, images: 0 })
    expect(await measureBody(declared(256_000), noLog)).toEqual({ textBytes: 256_000, images: 0 })
  })

  test("a declared length above the threshold still streams and scans", async () => {
    const body = bodyWithImage(dataUri(300_000))
    const declared = byteLength(body)
    expect(declared).toBeGreaterThan(256_000)
    const req = new Request(url, {
      method: "POST",
      body,
      headers: { "content-length": String(declared) },
    })

    const measured = await measureBody(req, noLog)
    // A declared-length shortcut would report `declared` text bytes and no
    // image; scanning reports the payload as one image instead.
    expect(measured.images).toBe(1)
    expect(measured.textBytes).toBe(byteLength(bodyWithImage("")))
  })
})

describe("a body that cannot be read", () => {
  test("measures as zero and logs", async () => {
    const logged: unknown[][] = []
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.error(new Error("broken body"))
      },
    })
    const measured = await measureBody(
      new Request(url, { method: "POST", body: stream }),
      (...args) => {
        logged.push(args)
      },
    )

    expect(measured).toEqual({ textBytes: 0, images: 0 })
    expect(logged).toHaveLength(1)
    expect(logged[0][0]).toBe("token estimate skipped")
  })
})
