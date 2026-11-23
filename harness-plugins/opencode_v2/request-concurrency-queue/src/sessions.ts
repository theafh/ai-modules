import type { SessionDetail, StatusSnapshot } from "./rpc.js"

/**
 * The session fields the describer needs. `ctx.session.get` returns a superset
 * of this shape, so the runtime value passes through without a cast.
 */
export interface SessionInfoLike {
  readonly title?: string
  readonly agent?: string
  readonly parentID?: string
  readonly location?: { readonly directory?: string }
}

export interface SessionDescriberOptions {
  /** How long a resolved detail stays fresh, in milliseconds. */
  ttlMs?: number
  now?: () => number
  /** Reports a failed lookup; that session falls back to its bare ID. */
  onError?: (sessionID: string, error: unknown) => void
}

/**
 * How long a session's title, agent, and directory are reused. The title is
 * generated after the first turn, so a detail fetched once and kept forever
 * would show an empty title for the rest of the run.
 */
export const DEFAULT_SESSION_DETAIL_TTL_MS = 30_000

/**
 * Attaches display metadata to the sessions the dialog names: the ones holding
 * a slot right now, plus the ones in the recent-transition feed, which is where
 * the dialog shows a session's name.
 *
 * The snapshot comes from the process-wide store, which knows only session IDs;
 * the runtime is the only place a title or a project directory can be read. A
 * session that cannot be read is still listed by its ID, so a failing lookup
 * never hides a request.
 */
export function createSessionDescriber(
  get: (sessionID: string) => Promise<SessionInfoLike>,
  options: SessionDescriberOptions = {},
): (snapshot: StatusSnapshot) => Promise<StatusSnapshot> {
  const ttl = options.ttlMs ?? DEFAULT_SESSION_DETAIL_TTL_MS
  const now = options.now ?? Date.now
  const cache = new Map<string, { detail: SessionDetail; fetchedAt: number }>()

  return async (snapshot) => {
    const ids = [
      ...new Set([
        ...snapshot.providers.flatMap((provider) => provider.activeSessionIDs ?? []),
        ...snapshot.transitions.map((transition) => transition.sessionID),
      ]),
    ]
    if (ids.length === 0) {
      cache.clear()
      return snapshot
    }

    const at = now()
    const details = await Promise.all(
      ids.map(async (sessionID) => {
        const cached = cache.get(sessionID)
        if (cached && at - cached.fetchedAt < ttl) return cached.detail
        try {
          const info = await get(sessionID)
          const detail: SessionDetail = {
            sessionID,
            ...(info.title ? { title: info.title } : {}),
            ...(info.agent ? { agent: info.agent } : {}),
            ...(info.parentID ? { parentID: info.parentID } : {}),
            ...(info.location?.directory ? { directory: info.location.directory } : {}),
          }
          cache.set(sessionID, { detail, fetchedAt: at })
          return detail
        } catch (error) {
          options.onError?.(sessionID, error)
          return { sessionID }
        }
      }),
    )

    // Drop the details of sessions that have left the in-flight set, once their
    // entry is older than the refresh window. A short grace keeps a session's
    // title stable across a release-and-acquire in the same turn.
    const live = new Set(ids)
    for (const [sessionID, cached] of cache) {
      if (!live.has(sessionID) && at - cached.fetchedAt > ttl) cache.delete(sessionID)
    }

    return { ...snapshot, sessionDetails: details }
  }
}
