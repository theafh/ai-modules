# Degradation examples

One job worked at each available row of the capability tier table: the inline
floor, batch delivery, and notice delivery. The quality contract is identical;
the mechanism is not. Read these alongside `<degradation>` in the skill body
and the tier table in `references/run-protocol.md`.

## The job

Nine markdown files under `docs/` have drifted from the commands they
document. The ask: find the drift and report it, changing nothing.

## At the inline floor

1. **Probe.** No delegation surface is callable. Every other capability
   resolves to absent. The opening sentence names the inline floor.
2. **Announce.** Three phases, nine items, a four-minute per-helper bound,
   nine included and two excluded (`docs/CHANGELOG.md` is generated,
   `docs/index.md` documents no command).
3. **Roster.** Nine rows, written before the first pass, each with its
   identifier, its one path, and its state.
4. **Survey.** Nine separately prompted passes in this context. Each pass
   opens on its own brief file and closes on its own return file before the
   next brief is read: `brief` writes the brief, the pass runs against that
   file, and `accept` takes its return. Nothing carries over between passes
   except what the roster records.
5. **Check.** One refute-by-default pass per finding that raised one, prompted
   separately from its own brief and returning through `accept` the same way.
   It receives the producing pass's return as text read from its file rather
   than as remembered context.
6. **Synthesise.** The orchestrator unions the cleared findings, keys them by
   identifier, re-derives the one claim the verdict rests on, and writes the
   closing report.

## Under batch delivery

1. **Probe.** A delegation surface is callable and the probe records batch
   delivery: a batch of spawns returns together inside the turn. Enforced
   read-only, a depth pin, and concurrent fan-out are recorded as the probe
   establishes them, each on its own.
2. **Announce.** The same three phases, the same nine items, the same bound,
   the same inclusions and exclusions, now with a wave size.
3. **Roster.** The same nine rows before the first dispatch.
4. **Survey wave.** For each row, `brief` writes the brief and `dispatch`
   sends the helper. The batch returns together inside the turn, and `accept`
   takes each return, or `accept --stdin` takes a read-only helper's final
   message. The wave closes with `diff --add-checks`, which adds one check row
   per changed path.
5. **Check wave.** One checker per finding that raised one, briefed against
   its producer's return by path, dispatched as its own batch and accepted the
   same way. Every checker's verdict waits for the whole wave.
6. **Synthesise.** Identical to the floor. The re-derivation step still runs,
   because a batch of helpers can share the same prior as one context.

## Under notice delivery

1. **Probe.** A delegation surface is callable and the probe records notice
   delivery: a spawn returns at once and its completion arrives later as a
   notice, with or without its result.
2. **Announce.** The same three phases, the same nine items, the same bound,
   the same inclusions and exclusions, now naming how completion arrives.
3. **Roster.** The same nine rows, each dispatch recording the host's
   identifier for its spawn.
4. **Survey.** For each row, `brief` writes the brief and `dispatch
   --helper-id` sends the helper and records the host's id for it. Each
   file-writing helper creates its `returns/<label>.start` marker first and its
   return file last, which is the file handshake. Bounded `accept --wait` polls
   run inside the turn, and a late notice re-runs `accept`, which changes
   nothing on an accepted row.
5. **Check.** The same per-finding checkers, dispatched the same way. A notice
   is a hint to run `status`, and only an accepted return counts as completion.
6. **Synthesise.** Identical to the other two rows. The orchestrator still
   re-derives the one claim the verdict rests on.

## What the floor gives up, stated out loud

The floor buys the same coverage at a different cost, so name the difference
rather than implying equivalence:

- A pass can recall an earlier pass's reasoning instead of re-deriving it, so
  a finding the checking pass was shown reads as recall-confirmed and carries
  less weight.
- No process boundary holds a reading pass to reads, so the read-only
  contract rests on the prompt alone, which `<prompt_assembly>` writes as an
  action for exactly this reason.
- The passes run one after another, so the run takes longer. The skill claims
  no wall-clock benefit from fan-out either way, because no concurrency
  contract is established for any host.
- At spawned roles, each of enforced read-only, a depth pin, and concurrent
  fan-out adds to the tier only where the probe establishes it. A run that
  reaches spawned roles without one of them states that absence, and its
  guarantees still hold at the floor.

## The governed exception

Where a named skill governs the run and states its own stop-and-ask boundary
for a host with no spawn surface, the inline floor does not apply to that run.
Offer that skill's manual routes, perform no helper role inline, and say which
boundary held. The two rungs are still the only tiers: the run does not invent
a third one to describe what the governing skill requires.
