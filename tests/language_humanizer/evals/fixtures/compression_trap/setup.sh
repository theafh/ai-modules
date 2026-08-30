#!/usr/bin/env bash
# setup.sh — stage the compression_trap fixture (rewrite path).
#
# Usage: setup.sh <target_dir>
#
# Writes <target_dir>/proj/draft.md: one long paragraph whose argument lives
# in its transitions (but / because / whereas / unlike / so / even though /
# since / therefore) plus one hedged uncertain claim. The trap is that the
# obvious readability move — splintering the paragraph into short bullets —
# destroys the argument, and the obvious concision move — asserting the
# hedged claim flatly — destroys the uncertainty marker.

set -euo pipefail

target="${1:?target dir required}"
mkdir -p "$target/proj"
proj="$(cd "$target/proj" && pwd)"

cat >"$proj/draft.md" <<'EOF'
# Why the trial-conversion drop matters more than the signup dip

Signups fell 4% last quarter, and that number has drawn most of the attention
in review meetings, but it is not where the revenue risk actually sits, because
signups recovered within three weeks in each of the two previous quarters where
they dipped, whereas trial-to-paid conversion has now declined for three
consecutive quarters, from 18% to 14%, and unlike a signup dip a conversion
decline compounds: every cohort that converts below plan carries a smaller
paying base into the following quarter, so the gap widens even when acquisition
returns to normal. That compounding is the reason the conversion trend deserves
the remediation budget first, even though the signup number is the one
leadership asks about in every review. The drop-off may be driven by the new
onboarding step we shipped in the second week of the quarter, though we have
not isolated it from the pricing-page change that landed the same week, so that
reading remains unconfirmed for now. What we can say with confidence is that
the decline is concentrated in self-serve accounts rather than sales-assisted
ones, since sales-assisted conversion held flat across the same three quarters,
and therefore any remediation that targets the assisted funnel would address
the smaller half of the problem while leaving the compounding half untouched.
EOF

printf '%s\n' "$proj"
