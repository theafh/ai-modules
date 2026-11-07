#!/usr/bin/env python3
"""Count the named phases an announcement states.

This is the grader helper behind `grade.sh`'s phase-count assertion. It reads
the property both the inline_floor and phase_plan_announcement evals state: the
announcement names two to four phases. It counts distinct phase names rather
than looking for any mention of a phase, so a single phase or five phases fail.
A bulleted list counts only when a phase header or sentence introduces it, so
an unrelated list of two to four items does not pass as a plan.

Usage:
    python3 phase_plan.py <announcement-file>
"""

import re
import sys


def split_names(text):
    names = []
    for part in re.split(r",|;|\band\b", text):
        part = part.strip().strip(".").strip()
        if part:
            names.append(part)
    return names


def phase_names(text):
    names = []
    numbered = re.compile(
        r"^\s*(?:phase\s+(\d+)|(\d+)[.)])\s*[:.\-]?\s*(.+)$", re.I
    )
    listed = re.compile(r"^\s*phases?\s*[:=]\s*(.+)$", re.I)
    prose = re.compile(
        r"\b(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten)"
        r"\s+phases?\b\s*(?:are\b|[:=])\s*(.*)$",
        re.I,
    )
    bullet = re.compile(r"^\s*[-*+]\s+(.+)$")
    header = re.compile(
        r"^\s*(?:#{1,6}\s*)?(?:\*\*)?phases?(?:\*\*)?\s*(?:are\s*[:=]?|[:=])?\s*$",
        re.I,
    )
    in_phase_section = False
    for line in text.splitlines():
        match = numbered.match(line)
        if match:
            name = match.group(3).strip()
            if name:
                names.append(name)
            in_phase_section = True
            continue
        match = listed.match(line) or prose.search(line)
        if match:
            names.extend(split_names(match.group(1)))
            in_phase_section = True
            continue
        if header.match(line):
            in_phase_section = True
            continue
        match = bullet.match(line)
        if match:
            if in_phase_section:
                name = match.group(1).strip().strip(".").strip()
                if name:
                    names.append(name)
            continue
        if line.strip():
            in_phase_section = False
    distinct = []
    for name in names:
        if name not in distinct:
            distinct.append(name)
    return distinct


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: phase_plan.py <announcement-file>\n")
        return 2
    text = open(argv[1], encoding="utf-8", errors="replace").read()
    names = phase_names(text)
    print("phases: %d" % len(names))
    for name in names:
        print("  %s" % name)
    return 0 if 2 <= len(names) <= 4 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
