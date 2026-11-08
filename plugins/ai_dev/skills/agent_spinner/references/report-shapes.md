# Worked report shapes

The surfaces a run writes: the opening announcement before the first helper,
the inline-floor opening, the interim report while helpers are out, the stop
report, the reply to a completion notice, the closing report, and the
provenance tags those surfaces carry. The digest the synthesis pass reads is
keyed by ledger record id.

Every example is generic. Substitute the run's own items, paths, and record
ids.

## Opening announcement

Written before the first helper, after P1 returns and the plan is written.

```text
Capability tier: spawned roles, batch delivery. Established: a delegation
surface, a depth control, and a host-enforced read-only lever. Assumed absent:
concurrent execution beyond one batch. Continuation: one goal armed for this
run, whose completion condition is `close` exiting 0.

Shape matched: per-artifact fan-out. No recipe matched.

Phases:
1. Survey — one helper reads one named page and reports its contract.
2. Check — one helper refutes one survey report against the page.

Orchestrator steps (checks, not helpers): the orient reads, the deterministic
gate, the scripted merge, validation, and the report.

Models and effort: survey at the host default model, effort low; check at the
host default model, effort high.

Items: 5 of 8 candidates. Bound: 4 minutes per helper. Wave size: 2.
Exclusions: 3, each with its reason below.
Included: build, deploy, status, clean, verify.
Excluded: changelog (generated file), index (documents no command), migrate
(retired and not maintained).

Gate answers stated by the request: none open. The verification scope is the
five included pages.

Context estimate: about one fifth of the host window, against the window
harness_portability records; no session boundary expected. The fallback figure
for a host with no recorded window is unverified.

Helper estimate: 10 helpers, 5 survey and 5 check.
```

## Inline-floor opening

The same plan, stated at the floor. The tier sentence changes; the plan does
not.

```text
Capability tier: inline floor — no delegation surface is callable here, so
each pass below runs as its own separately prompted pass in this context.
Established: nothing beyond reads. Assumed absent: a delegation surface, a
host-enforced read-only lever, a depth control, and concurrent execution.
Continuation: re-entry through `status` and `attach`, since this session
offers no goal tool.

Shape matched: per-artifact fan-out. No recipe matched.

Phases, items, bound, wave size, exclusions, gate answers, context estimate,
and helper estimate: identical to the spawned form.
```

## Interim report

Written at a turn end while helpers are out or a gate is open.

```text
Interim at the spawned-roles tier. Two rows are open and one gate waits on you.

Open rows:
- survey:build — dispatched, bound deadline 12:04.
- survey:deploy — dispatched, bound deadline 12:04.

Open gate: gate-2, whether to widen the run to the three excluded pages.

Accepted so far: survey:status, survey:clean. The run stays open; `close` has
not run.
```

## Stop report

Built from `close --stopped`, which prints the tally block and the three row
lists. While any row is non-terminal it prints them and refuses, exiting
non-zero, so the stop report says so in its opening sentence.

```text
Stopped after 2 of 4 writers, at the spawned-roles tier, 2 dispatched against
2 returned. `close --stopped` exited 3, refusing while 2 rows were pending.

Modified: docs/setup.md, docs/deploy.md.
Untouched: docs/upgrade.md, docs/rollback.md.
Unknown at stop, now settled by reading: docs/upgrade.md, docs/rollback.md.

**Established.** Both modified pages carry the flag NOTES.txt records,
re-derived from the files after the stop.

**Found beyond the brief.** None.

**Decided on a helper's own authority, for your review.** None.

Yield: 2 helpers dispatched for 2 edits, against an estimate of 2.
```

## Reply to a completion notice

A notice is a hint to run `status`; the reply says what it accepted and what it
dispatched or opened next.

```text
Ran `status`, then accepted survey:deploy from its return file. The batch is
complete: 5 accepted, 0 open.

Dispatched the checker wave: check:build, check:deploy, check:status,
check:clean, check:verify. No gate opened; the run stays open until the
checkers return.
```

## Closing report

Built from the tally block `close` prints. Its opening sentence says whether
`close` exited 0.

```text
Five of the five surveyed pages hold their stated contract, reached at the
spawned-roles tier, 10 helpers dispatched against 10 returned, and `close`
exited 0.

The verdict rests on one claim: every page's documented flags match the
command's parser. Re-derived from the files rather than from the helper
reports.

**Established.** The build page documents --target and --jobs (measured by the
gate, record check:build). The deploy page documents --env (re-derived from
the file).

**Found beyond the brief.** The verify survey noted a stale line in the
changelog. Recall-confirmed by the checking pass, not independently surfaced,
so it carries less weight.

**Decided on a helper's own authority, for your review.** The status survey
treated a missing index link as out of scope rather than as a finding.

Verification: re-derived — the flag parser and the five pages. Taken on a
helper's word — the changelog line. Not run — the three excluded pages.

Confirmations: recall-confirmed — the changelog line. Independently surfaced —
the deploy page's --env example.

Requested and observed model and effort: survey, default model and low effort
requested, default model and low effort observed; check, default model and
high effort requested, default model and high effort observed.

Coverage narrowing: the three excluded candidates went unsurveyed, so contract
drift there would not have surfaced here. A second phase over those three
would surface it.

Yield: 10 helpers dispatched for 2 findings and 1 decision, against an estimate
of 8 helpers; the checking stage surfaced nothing the gate had not, which is a
thin return for the cost.
```

## Provenance tags

Every sentence in a report, reply, or log entry that asserts verification,
independence, completion, or coverage carries one of these tags and cites the
ledger row or check output it rests on. The tag says how the claim was
established.

```text
[measured: <check or gate record id>]     a tool produced the result
[re-derived: <row or record id>]          the orchestrator read the artifact
[taken on a helper's word: <row id>]      only a helper's return says so
```

Examples:

```text
The build page documents --jobs [re-derived: survey:build]. The lint gate
reports 2 warnings [measured: gate:lint]. The changelog line is stale [taken
on a helper's word: survey:verify].
```

A claim with no tag is unproven, and the report lint flags it. A verdict that
resisted re-derivation is reported as the helpers' finding, tagged `taken on a
helper's word`.

## Digest handed to synthesis

One record per ledger record id, in id order, under the item label that
produced it. The payload is capped at the stated size; a trimmed identifier is
listed below the cap line and its detail is re-read from the source.

```text
Payload cap: 4000 characters. Material below this line may be cut; any
load-bearing detail is re-read from the source. Trimmed: survey:verify,
survey:migrate.

survey:build
  finding survey:build:findings:0 — [major] the page documents --jobs; the
    command takes --workers.
    quote: "Run `tool.sh build --jobs 4`."
    anchor: docs/build.md, under "# build"
    provenance: independently surfaced

survey:deploy
  finding survey:deploy:findings:0 — [minor] the example omits --env.
    quote: "Run `tool.sh deploy`."
    anchor: docs/deploy.md, under "# deploy"
    provenance: recall-confirmed

survey:status
  no records. Examined and cleared: the heading, the example block, and the
  flag list.
```
