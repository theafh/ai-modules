#!/usr/bin/env python3
"""Count the named phases an announcement states.

This is the grader helper behind `grade.sh`'s phase-count assertion. It reads
the property both the inline_floor and phase_plan_announcement evals state: the
announcement names two to four phases. It counts distinct phase names rather
than looking for any mention of a phase, so a single phase or five phases fail.
A bulleted list, and a bare numbered list, counts only when a phase header or
sentence introduces it, so an unrelated list of two to four items, such as the
numbered checks a recipe has the announcement list, does not pass as a plan.
A `Phase N:` line counts wherever it appears. An indented line that follows a
numbered or bulleted item continues that item, so a wrapped item counts once
and its name reads whole.

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
    intro = re.compile(r"\bphases?\b.*:\s*(?:\*\*)?\s*$", re.I)
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
    last_was_item = False
    for line in text.splitlines():
        match = numbered.match(line)
        if match and (match.group(1) or in_phase_section):
            name = match.group(3).strip()
            if name:
                names.append(name)
            in_phase_section = True
            last_was_item = True
            continue
        match = listed.match(line) or prose.search(line)
        if match:
            names.extend(split_names(match.group(1)))
            in_phase_section = True
            last_was_item = False
            continue
        if header.match(line) or intro.search(line):
            in_phase_section = True
            last_was_item = False
            continue
        if numbered.match(line):
            last_was_item = False
            continue
        match = bullet.match(line)
        if match:
            if in_phase_section:
                name = match.group(1).strip().strip(".").strip()
                if name:
                    names.append(name)
                    last_was_item = True
            continue
        if line.strip():
            if last_was_item and names and line[:1].isspace():
                names[-1] = names[-1] + " " + line.strip()
                continue
            in_phase_section = False
            last_was_item = False
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
