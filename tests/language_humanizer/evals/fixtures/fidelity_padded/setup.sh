#!/usr/bin/env bash
# setup.sh — stage the fidelity_padded fixture (rewrite path).
#
# Usage: setup.sh <target_dir>
#
# Writes a padded status update into <target_dir>/proj/draft.md. The draft
# carries nine load-bearing items wrapped in filler and restatement:
#
#   1. actor    Priya Raman
#   2. actor    the Billing squad
#   3. deadline 14 March
#   4. threshold 200 ms (committed p95 checkout latency)
#   5. threshold 99.5% (availability floor during the migration)
#   6. must     Priya ships the latency fix / availability stays at the floor
#   7. should   the Billing squad migrates its retry logic
#   8. exception enterprise tenants keep retries on the dedicated worker
#   9. causal joint  the deadline holds *because* the commitment is contractual
#
# Those nine items plus the connective prose needed to carry them fit in
# well under half the draft's words, so a faithful rewrite has room to come
# in under the 75% ceiling without dropping anything.

set -euo pipefail

target="${1:?target dir required}"
mkdir -p "$target/proj"
proj="$(cd "$target/proj" && pwd)"

cat >"$proj/draft.md" <<'EOF'
# Q1 Checkout Reliability Workstream — Status and Next Steps

As we continue to move forward on the checkout reliability workstream, it is
important to note that there are a number of considerations that the team will
need to take into account over the coming weeks. At a high level, the overall
picture is one where performance has not yet reached the place where we would
like it to be, and where a certain amount of remediation work will be required
in order to bring things back into alignment with expectations.

With respect to latency, the current situation is that the p95 checkout latency
is presently sitting at approximately 340 ms, which, as most people on the team
are already aware, is meaningfully above the 200 ms figure that we have
committed to externally. It is therefore the case that a fix is needed, and in
terms of ownership, Priya Raman must be the one to ship that fix, with a target
date of 14 March being the deadline that we are working towards, precisely
because the commitment we made is a contractual one rather than an aspirational
one.

Separately, and in parallel with the above, there is the question of the retry
logic. The current thinking is that the Billing squad should undertake a
migration of its retry logic onto the shared queue within the same general
window of time, which would bring a degree of consistency to the overall
architecture. That said, an exception does apply here: enterprise tenants are a
special case, and for those tenants the retries should be left on the dedicated
worker for the time being, at least until such time as the relevant contracts
have been renegotiated.

Finally, on the subject of availability, it goes without saying that
availability is something we care a great deal about. The requirement here is a
hard one: availability must remain at or above 99.5% for the duration of the
migration work, and there is no flexibility whatsoever on that particular
number.

In summary, and to reiterate the points that have been made above, there is
latency work to be done, there is retry migration work to be done, and there is
an availability bar that has to be respected throughout. The team will need to
keep all of these considerations in mind as we proceed through the quarter.
EOF

printf '%s\n' "$proj"
