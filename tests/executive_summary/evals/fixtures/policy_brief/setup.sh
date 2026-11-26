#!/usr/bin/env bash
# Stage the policy_brief fixture: one source document and the terms a faithful
# summary must not invent.
set -euo pipefail

target="${1:?target dir required}"
mkdir -p "$target"

cat > "$target/source.md" <<'SOURCE'
# Coastal Resilience Programme: Midpoint Review

## What this document is

This report reviews the first eighteen months of the Coastal Resilience
Programme, a joint effort by four municipalities to reduce flood damage along
the lower estuary. It sets out the problem the programme addresses, the
measures taken so far, the evidence collected, and the decisions the steering
group must make before the next funding round.

## The problem

The lower estuary floods more often than it did thirty years ago. Tide gauges
show a mean sea-level rise of eleven centimetres since 1994, and the estuary's
marshes, which once absorbed storm surges, have lost roughly a fifth of their
area to development and erosion. During the 2021 spring tide, water reached
eleven streets that had never flooded, and the combined repair bill for the
four municipalities exceeded nine million euros. The programme's purpose is to
keep that bill from growing while protecting the homes and businesses that sit
below the five-metre contour.

## What has been done

The programme chose a mixed approach rather than a single sea wall. Three
measures are underway. First, two managed-retreat sites have been created by
breaching old embankments and letting the marsh re-establish; these sites now
flood deliberately during high tides and take pressure off the town defences.
Second, the four municipalities have raised and widened the eastern flood
bank, which protects the industrial zone. Third, a forecasting system now
combines tide, wind, and rainfall data and issues warnings forty-eight hours
ahead, giving residents time to move vehicles and ground-floor belongings.

## Evidence so far

Monitoring suggests the managed-retreat sites are working. Sediment
accumulation at the northern site has averaged three centimetres a year, close
to the design assumption, and bird counts have risen. The eastern bank held
during the 2023 autumn storm, when water came within twenty centimetres of its
crest. The forecasting system issued timely warnings for four of the five
major tides in the period, though the fifth arrived faster than forecast.

The evidence is not uniformly positive. The southern retreat site has
accumulated less sediment than expected, and the programme's own reviewers
attribute this to a channel that redirects flow away from the site. Repairing
the channel would cost an estimated two hundred thousand euros. The review also
found that uptake of the voluntary home-retrofit scheme has been low: only one
hundred and forty households have applied, against a target of four hundred.

## Costs and funding

The programme has spent six of its twelve million euro budget. Most of the
remainder is committed to the eastern bank's second phase and to monitoring.
The steering group has not yet allocated money for the channel repair or for a
second retrofit campaign.

## Decisions requested

The steering group is asked to decide three things. It should decide whether
to fund the channel repair at the southern site now, before the next planting
season, or to wait for a second year of monitoring. It should decide whether to
re-launch the retrofit scheme with a higher subsidy and a simpler application,
since the current design appears to deter the households it was meant to reach.
Finally, it should decide whether to extend the forecasting system's contract,
which expires next year, and whether to add river-gauge data that would improve
warning times for the fastest tides.

## Recommendation

The reviewers recommend funding the channel repair now, because a second
planting season lost would delay the site's maturity by a year, and recommend
relaunching the retrofit scheme with a higher subsidy. They recommend extending
the forecasting contract but deferring the river-gauge addition until its cost
is better understood.
SOURCE

cat > "$target/forbidden.txt" <<'FORBIDDEN'
fourteen million
Q3 2027
Northgate Consortium
seventy-two percent
FORBIDDEN
