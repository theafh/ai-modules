#!/usr/bin/env python3
"""Count the named phases an announcement states.

This is the grader helper behind `grade.sh`'s phase-count assertion. It reads
the property both the inline_floor and phase_plan_announcement evals state: the
announcement names two to four phases. It counts distinct phase names rather
than looking for any mention of a phase, so a single phase or five phases fail.

Usage:
    python3 phase_plan.py <announcement-file>
"""

import re
import sys


def phase_names(text):
    names = []
    numbered = re.compile(
        r"^\s*(?:phase\s+(\d+)|(\d+)[.)])\s*[:.\-]?\s*(.+)$", re.I
    )
    listed = re.compile(r"^\s*phases?\s*[:=]\s*(.+)$", re.I)
    for line in text.splitlines():
        match = numbered.match(line)
        if match:
            name = match.group(3).strip()
            if name:
                names.append(name)
            continue
        match = listed.match(line)
        if match:
            for part in re.split(r",|\band\b", match.group(1)):
                part = part.strip()
                if part:
                    names.append(part)
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
