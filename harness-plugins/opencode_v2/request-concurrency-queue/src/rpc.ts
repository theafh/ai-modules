import type { Rpc } from "@opencode/schema/rpc"
import type { SubagentStatus } from "./subagents.js"

/** One configured provider's current concurrency state. */
export interface ProviderStatus {
  readonly providerID: string
  readonly active: number
  readonly queued: number
  /** The effective maximum, which adaptive control may lower and raise. */
  readonly max: number
  /** The configured maximum that adaptive control never exceeds. */
  readonly ceiling: number
  /** `active / max`, as a number from 0 to 1; 0 when `max` is 0. */
  readonly utilization: number
  /** `(active + queued) / max`, an unbounded load factor; 0 when `max` is 0. */
  readonly demand: number
  /** Whole new-context tokens the provider's bucket currently holds. */
  readonly tokensAvailable: number
  /** The bucket's capacity; 0 when the provider has no token budget. */
  readonly tokensCapacity: number
  /** Epoch milliseconds until which a provider `Retry-After` pauses requests; 0 when not paused. */
  readonly tokensPausedUntil: number
  /** Total context tokens in flight, when a context cap is configured. */
  readonly contextInFlight?: number
  /** The context cap, when configured. */
  readonly contextCapacity?: number
  /** The provider's stalled-attempt circuit: closed, open, or half-open. */
  readonly breaker: "closed" | "open" | "half-open"
  /** Milliseconds until the circuit allows a probe; 0 when closed. */
  readonly breakerRetryAfterMs: number
  /** Consecutive stalled attempts counted toward the threshold. */
  readonly stalls: number
}

/** One provider's editable new-context allowance. */
export interface TokenConfig {
  capacity: number
  refillPerMinute: number
  safetyFactor: number
}

/** The editable admission settings. */
export interface SchedulerConfigSnapshot {
  contextCapacity: number
  contextCeiling: number
  reserveShare: number
  smallShare: number
  agingMs: number
  queueDeadlineMs: number
  breaker: { threshold: number; cooldownMs: number; mode: "fail" | "wait" }
}

/** Everything the settings form reads and writes. */
export interface ConfigSnapshot {
  providers: Record<string, number>
  tokens: Record<string, TokenConfig>
  scheduler: SchedulerConfigSnapshot
  /** `max: 0` means fan-out gating is off. */
  subagents: { max: number; hostAware: boolean }
  adaptive: boolean
}

/** What a save reports back to the form. */
export interface SaveResult {
  ok: boolean
  errors: string[]
  restartRequired: boolean
}

/**
 * The count-changing transitions the limiter records. One buffer entry carries
 * one kind; a release handoff records a `released` entry for the releasing
 * session and an `acquired` entry for the waiter.
 */
export type TransitionKind = "acquired" | "queued" | "released" | "dequeued"

/**
 * One recent count-changing transition. It holds identifiers and counts only:
 * a session ID is an identifier, never prompt, message, or tool payload.
 */
export interface TransitionRecord {
  /** Milliseconds since the Unix epoch, from `Date.now()`. */
  readonly timestamp: number
  readonly providerID: string
  readonly kind: TransitionKind
  readonly sessionID: string
  /** The provider's active count after the transition. */
  readonly active: number
  /** The provider's queued count after the transition. */
  readonly queued: number
}

/** The status snapshot the server part serves and the GUI reads. */
export interface StatusSnapshot {
  readonly providers: readonly ProviderStatus[]
  /** Recent transitions in append order, oldest first. */
  readonly transitions: readonly TransitionRecord[]
  /** The live-child-session gate, when fan-out gating is configured. */
  readonly subagents?: SubagentStatus
}

const providerStatusSchema = {
  type: "object",
  properties: {
    providerID: { type: "string" },
    active: { type: "integer", minimum: 0 },
    queued: { type: "integer", minimum: 0 },
    max: { type: "integer", minimum: 0 },
    ceiling: { type: "integer", minimum: 0 },
    utilization: { type: "number", minimum: 0, maximum: 1 },
    demand: { type: "number", minimum: 0 },
    tokensAvailable: { type: "integer", minimum: 0 },
    tokensCapacity: { type: "integer", minimum: 0 },
    tokensPausedUntil: { type: "integer", minimum: 0 },
    contextInFlight: { type: "integer", minimum: 0 },
    contextCapacity: { type: "integer", minimum: 0 },
    breaker: { type: "string", enum: ["closed", "open", "half-open"] },
    breakerRetryAfterMs: { type: "integer", minimum: 0 },
    stalls: { type: "integer", minimum: 0 },
  },
  required: [
    "providerID",
    "active",
    "queued",
    "max",
    "ceiling",
    "utilization",
    "demand",
    "tokensAvailable",
    "tokensCapacity",
    "tokensPausedUntil",
    "breaker",
    "breakerRetryAfterMs",
    "stalls",
  ],
  additionalProperties: false,
} as const

const transitionSchema = {
  type: "object",
  properties: {
    timestamp: { type: "integer", minimum: 0 },
    providerID: { type: "string" },
    kind: { type: "string", enum: ["acquired", "queued", "released", "dequeued"] },
    sessionID: { type: "string" },
    active: { type: "integer", minimum: 0 },
    queued: { type: "integer", minimum: 0 },
  },
  required: ["timestamp", "providerID", "kind", "sessionID", "active", "queued"],
  additionalProperties: false,
} as const

const subagentStatusSchema = {
  type: "object",
  properties: {
    live: { type: "integer", minimum: 0 },
    queued: { type: "integer", minimum: 0 },
    max: { type: "integer", minimum: 0 },
    capacity: { type: "integer", minimum: 0 },
  },
  required: ["live", "queued", "max", "capacity"],
  additionalProperties: false,
} as const

const tokenConfigSchema = {
  type: "object",
  properties: {
    capacity: { type: "integer", minimum: 1 },
    refillPerMinute: { type: "integer", minimum: 1 },
    safetyFactor: { type: "number", minimum: 0.1, maximum: 10 },
  },
  required: ["capacity", "refillPerMinute", "safetyFactor"],
  additionalProperties: false,
} as const

const schedulerConfigSchema = {
  type: "object",
  properties: {
    contextCapacity: { type: "integer", minimum: 0 },
    contextCeiling: { type: "integer", minimum: 0 },
    reserveShare: { type: "number", minimum: 0, maximum: 1 },
    smallShare: { type: "number", minimum: 0, maximum: 1 },
    agingMs: { type: "integer", minimum: 0 },
    queueDeadlineMs: { type: "integer", minimum: 0 },
    breaker: {
      type: "object",
      properties: {
        threshold: { type: "integer", minimum: 1 },
        cooldownMs: { type: "integer", minimum: 0 },
        mode: { type: "string", enum: ["fail", "wait"] },
      },
      required: ["threshold", "cooldownMs", "mode"],
      additionalProperties: false,
    },
  },
  required: [
    "contextCapacity",
    "contextCeiling",
    "reserveShare",
    "smallShare",
    "agingMs",
    "queueDeadlineMs",
    "breaker",
  ],
  additionalProperties: false,
} as const

const configSnapshotSchema = {
  type: "object",
  properties: {
    providers: { type: "object", additionalProperties: { type: "integer", minimum: 1 } },
    tokens: { type: "object", additionalProperties: tokenConfigSchema },
    scheduler: schedulerConfigSchema,
    subagents: {
      type: "object",
      properties: {
        max: { type: "integer", minimum: 0 },
        hostAware: { type: "boolean" },
      },
      required: ["max", "hostAware"],
      additionalProperties: false,
    },
    adaptive: { type: "boolean" },
  },
  required: ["providers", "tokens", "scheduler", "subagents", "adaptive"],
  additionalProperties: false,
} as const

const saveResultSchema = {
  type: "object",
  properties: {
    ok: { type: "boolean" },
    errors: { type: "array", items: { type: "string" } },
    restartRequired: { type: "boolean" },
  },
  required: ["ok", "errors", "restartRequired"],
  additionalProperties: false,
} as const

const emptyObjectSchema = {
  type: "object",
  properties: {},
  additionalProperties: false,
} as const

/**
 * The one RPC definition both parts import: the server part registers it with
 * `ctx.rpc.register`, and the GUI reads the routed session's server through
 * `client.rpc(statusRpc)`. Plain JSON Schema keeps it portable across both
 * sides without a runtime schema dependency.
 */
export const statusRpc = {
  id: "request-concurrency-queue",
  methods: {
    status: {
      input: emptyObjectSchema,
      output: {
        type: "object",
        properties: {
          providers: { type: "array", items: providerStatusSchema },
          transitions: { type: "array", items: transitionSchema },
          subagents: subagentStatusSchema,
        },
        required: ["providers", "transitions"],
        additionalProperties: false,
      },
    },
    config: {
      input: emptyObjectSchema,
      output: configSnapshotSchema,
    },
    save: {
      input: configSnapshotSchema,
      output: saveResultSchema,
    },
  },
  events: {
    changed: { schema: emptyObjectSchema },
  },
} satisfies Rpc.PortableDefinition
