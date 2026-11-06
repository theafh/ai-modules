import type { Rpc } from "@opencode/schema/rpc"

/** One configured provider's current concurrency state. */
export interface ProviderStatus {
  readonly providerID: string
  readonly active: number
  readonly queued: number
  readonly max: number
  /** `active / max`, as a number from 0 to 1; 0 when `max` is 0. */
  readonly utilization: number
  /** `(active + queued) / max`, as a number from 0 to 1; 0 when `max` is 0. */
  readonly demand: number
}

/** The status snapshot the server part serves and the GUI reads. */
export interface StatusSnapshot {
  readonly providers: readonly ProviderStatus[]
}

const providerStatusSchema = {
  type: "object",
  properties: {
    providerID: { type: "string" },
    active: { type: "integer", minimum: 0 },
    queued: { type: "integer", minimum: 0 },
    max: { type: "integer", minimum: 0 },
    utilization: { type: "number", minimum: 0, maximum: 1 },
    demand: { type: "number", minimum: 0, maximum: 1 },
  },
  required: ["providerID", "active", "queued", "max", "utilization", "demand"],
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
        },
        required: ["providers"],
        additionalProperties: false,
      },
    },
  },
  events: {
    changed: { schema: emptyObjectSchema },
  },
} satisfies Rpc.PortableDefinition
