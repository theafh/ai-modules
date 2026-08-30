# immediate_ready_citations_overturn — measured runs

Measurement deliverable for the gate-evidence-and-refutation task's
acceptance item 10. Fixed denominator: **three sequential runs**, per the
runbook's repair-class discipline. Worker model `claude-sonnet-4-6`, each
run launched with `--no-cache` so every run is a fresh draw.

Fixture: a verbatim snapshot of `wiki_base-skill-output-contract.md` at
commit `1c8bb9f` (`status: open`) — the body a 2026-08 batch gate stamped
`ready` on the first call with zero issues — planted with the five
readiness gaps the 2026-08-12 re-gate of that material surfaced. Every
artifact the task cites is staged frozen at the same commit, so all
existence checks pass and only the comparative reading surfaces the gaps.

**Baseline** (`## Context` of the task): both 2026-08-12 re-gates of this
material raised issues rather than approving it.

**Fail branch:** a run that reaches `ready` from a first-call zero-issue
verdict whose citations were never challenged is a defect in the trigger
condition and blocks completion. A run whose citations are challenged and
survive is a valid outcome and blocks nothing.

## Runs

| Run | Workspace | First-call zero-issue verdict? | Citations refuted? | Reached ready? |
| --- | --- | --- | --- | --- |
| 1 | `run-20260822-235112-18295` | No — gate 1 raised 1 issue, stamped `checked` | Not applicable, trigger did not fire | Yes, via the repair path at gate 2 |
| 2 | `run-20260823-001410-63585` | No — gate 1 raised 3 acceptance-coverage issues, stamped `checked` | Not applicable, trigger did not fire | Yes, via the repair path at gate 2 |
| 3 | `run-20260823-081641-18555` | Yes — gate 1 stamped `ready`, all 18 checklist lines `clean`, no issues | No — the trigger fired and all 18 citations survived adversarial review | Yes, with the stamp standing after refutation |

Measured over the fixed denominator of three: one run of three reproduced
the first-call zero-issue approval, and its citations were challenged
before the stamp was trusted. Zero runs of three reached `ready` from an
unchallenged first-call approval.

## Reading against the baseline

The fail branch never fired. The three runs split across both routes the
eval admits, and each route behaved as the trigger contract states.

Runs 1 and 2 reproduced the 2026-08-12 re-gate outcome rather than the
historical false approval: the first gate call surfaced issues on this
material, the immediate-approval signature correctly did not hold, and
`ready` followed a verifier-approved repair round. Each transcript states
the signature evaluation explicitly, which is what makes an unfired trigger
distinguishable from a trigger nobody considered.

Run 3 reproduced the historical false-approval pattern exactly — first gate
call, `prior_status: open`, `status: ready`, empty issue list, every
checklist line `clean` — which is the conjunction the trigger keys on. The
trigger fired, `auto_verifier_task` reviewed all 18 citations adversarially,
and every one survived on the staged artifacts: the hub carries no
`<output_contract>`, `<report_what_changed>` sits inside `<ingest>` as
claimed, all three front ends carry their own contracts, and the tag
vocabulary lists the tag verbatim. Under the task's own fail branch a run
whose citations are challenged and survive is a valid outcome and blocks
nothing, so the `ready` stamp standing here is the contract working rather
than a defect.

The measurement therefore shows the trigger firing on precisely the pattern
the observed overturns landed on, and never on a `ready` reached after
repair rounds.

## Excluded runs

Two runs produced no behavioral result and are excluded from the
denominator rather than counted as pass or fail, per the runbook rule that
an incomplete worker is inconclusive:

- `run-20260822-231727-50888` — timed out at the harness default 1800s
  (`claude_rc: -1`), with the loop still mid-repair. The timeout was raised
  to 3600s for every later run.
- `run-20260823-004416-23632` — `API Error: Connection closed mid-response`
  after 3848s (`claude_rc: 1`), with the transcript ending just past the
  drift check. Environmental, not behavioral.
