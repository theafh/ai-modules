#!/usr/bin/env bash
# Stage the technical_report fixture: one source document and the terms a
# faithful summary must not invent.
set -euo pipefail

target="${1:?target dir required}"
mkdir -p "$target"

cat > "$target/source.md" <<'SOURCE'
# Battery Thermal Management: Test Report

## Purpose

This report records the results of a twelve-week test programme on a
lithium-iron-phosphate battery pack intended for a light commercial vehicle.
The programme asked whether the pack's air-cooled thermal design keeps cell
temperatures within the manufacturer's window during repeated fast charging,
and whether a proposed duct change improves that margin enough to justify its
cost.

## Test setup

The pack contains ninety-six cells arranged in twelve modules. Each module
carries two thermocouples, one on the busbar and one on the cell can, and the
pack sits in a climate chamber that holds ambient temperature at either twenty
or thirty-five degrees Celsius. The test cycle charges the pack from twenty to
eighty percent state of charge at a rate of one hundred and twenty kilowatts,
rests for ten minutes, and discharges it on a simulated urban drive cycle. Each
run repeats the cycle six times. The baseline duct directs air from a single
inlet across the top of the modules; the proposed duct splits the flow and
delivers it to both the top and the bottom of each module.

## Results

At twenty degrees ambient, both ducts held every cell below the forty-five
degree limit. The hottest cell reached thirty-nine degrees with the baseline
duct and thirty-six with the split duct. At thirty-five degrees ambient, the
baseline duct exceeded the limit on the fifth and sixth cycles: the hottest
cell reached forty-eight degrees, and the pack controller derated charging on
the sixth cycle. The split duct held the hottest cell at forty-two degrees and
did not derate. The improvement was largest in the middle modules, which are
farthest from the inlet in the baseline design.

Cell-to-cell spread also narrowed. Under the baseline duct at thirty-five
degrees, the difference between the hottest and coolest cell reached nine
degrees; the split duct reduced it to four degrees. Busbar temperatures tracked
the cell temperatures closely in both designs, so the report treats the cell
measurements as the binding constraint.

## Durability and cost

The programme did not run a lifetime test, so it cannot state how the split
duct affects long-term degradation. The duct itself is a moulded part; the
supplier quotes eighteen euros per pack at a volume of ten thousand units, and
tooling would cost ninety thousand euros. Fitting the split duct adds about
four minutes to pack assembly.

## Limitations

The test used one pack and one climate chamber, so the results describe that
pack rather than the production population. Ambient humidity was not
controlled. The drive cycle is a simulation, not a road test. The controller
derated on only one run, so the report cannot say how often derating would
occur in service.

## Conclusions

The split duct removes the over-temperature and derating seen with the
baseline duct at thirty-five degrees ambient, and it narrows cell-to-cell
spread. The report recommends adopting the split duct for the next build,
provided the supplier's tooling quote is confirmed and a lifetime test is added
to the qualification plan. It does not recommend changing the cell chemistry or
the pack's charge rate on the evidence gathered.
SOURCE

cat > "$target/forbidden.txt" <<'FORBIDDEN'
nickel-manganese-cobalt
sixty kilowatts
twenty-eight euros
2029 production start
FORBIDDEN
