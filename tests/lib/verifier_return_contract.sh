#!/usr/bin/env bash
# Proposal-mode verifier return contract check for the task_auto_check evals.
#
# The grader and the script tests both source this file and call
# `verifier_returns_keep_contract <relay dir>`. Nothing runs at source time, so
# the helper loads without the grader's own arguments or case block.
#
# Usage from a grader at tests/<name>/evals/grade.sh:
#
#     # shellcheck source=../../lib/verifier_return_contract.sh
#     . "$HERE/../../lib/verifier_return_contract.sh"
#
# Usage from a script test:
#
#     bash -c '. "$1"; verifier_returns_keep_contract "$2"' _ "$helper" "$relay"

# verifier_returns_keep_contract <relay dir> -> every saved proposal-mode
# verifier return r<N>-verifier[-k].txt carries the agent's proposal-mode output
# contract in full. `## Approved edits` and `## Rejections and routes` each read
# "None." or list items, an approved item opening at its `id:` field and a
# rejection at its `issue:` field, and every item carries each field the
# contract gives it, with a rejection's decision one the contract names. A
# missing section, and one summarized into a line with no items behind it, fail.
# A rejection item may also carry the route fields affected_passages, gate_fix,
# and options, which the contract gives a human_routed decision; they are
# optional because a rejected or unassessable item omits them.
# The contract's value forms are read as the agent states them: a one-line
# value sits raw after its field name, and a value written as a fenced block on
# the lines after the field name is unwrapped to the block's content, which is
# the exact text. A fenced value therefore reads as present and whole, and its
# fence lines never stand in for an item or end a section.
# Inside a section, a numbered line at any indentation and every other column-0
# line must open an item at the section's lead field, set a contract field its
# item still lacks, or continue an open anchor, replacement, affected_passages,
# or gate_fix value, the fields that copy task or gate text verbatim; the None
# form before any item is the one other column-0 line allowed. Any other such line is a pointer or summary standing
# in for items and fails, also after real items. The header's
# approved_edit_count must equal the approved items and its human_routed_count
# the human_routed rejections, so a dropped item fails even when every
# remaining item is whole. Indented continuation lines belong to the field
# above them, so a wrapped replacement or reason reads as one value. Stance
# accounting: every saved reviewer return of that round contributes its
# `stance:` value, and each must appear among the verifier return's
# `source_stance:` values (approved or rejection), after the same normalize
# (lowercase, drop markdown punctuation and a trailing "advocate", fold
# non-alphanumerics to "-") with substring match so a merged source_stance
# covers each named stance. That catches a return that keeps one rejection
# and elides the rest behind an indented pointer, or that replaces every
# rejection with "None." while reviewer returns remain. A citation-mode
# return keeps its own shape and is skipped.
verifier_returns_keep_contract() {
  python3 - "$1" <<'PY'
import pathlib
import re
import sys

relay = pathlib.Path(sys.argv[1])
key_line = re.compile(r"^\s*(?:[0-9]+[.)]\s+)?(?:[-*]\s+)?\**([a-z_]+)\**\s*:\**\s*(.*?)\s*$")
item_line = re.compile(r"^\s*[0-9]+[.)]\s")
column0 = re.compile(r"^\S")
none_lead = re.compile(r"""^\s*["'`*]*none\b""", re.I)
fence_open = re.compile(r"^\s*(`{3,}|~{3,})[^`~]*$")
approved_fields = ("id", "issue", "source_stance", "base_rule_cited", "anchor",
                   "replacement", "edit", "fidelity", "reason")
rejection_fields = ("issue", "source_stance", "decision", "reason")
route_fields = ("affected_passages", "gate_fix", "options")
verbatim_fields = ("anchor", "replacement", "affected_passages", "gate_fix")
decisions = {"rejected", "human_routed", "unassessable"}


def bare(value):
    return value.strip("`*\"' ")


def normalize_stance(value):
    text = bare(value).lower()
    text = re.sub(r"[`*_\[\]()'\".,:;]+", "", text)
    text = re.sub(r"\s+advocate\s*$", "", text)
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")


def section(body, heading):
    # Split on level-2 headings that sit outside a fenced block, so a fenced
    # anchor or replacement that carries a `## ` line stays inside its section.
    found, current, fence = {}, None, None
    for line in body.splitlines():
        if fence:
            if re.match(rf"^\s*{re.escape(fence[0])}{{{len(fence)},}}\s*$", line):
                fence = None
            if current is not None:
                found[current].append(line)
            continue
        opener = fence_open.match(line)
        if opener:
            fence = opener.group(1)
            if current is not None:
                found[current].append(line)
            continue
        match = re.match(r"^## (.+?)\s*$", line)
        if match:
            current = match.group(1)
            found.setdefault(current, [])
            continue
        if current is not None:
            found[current].append(line)
    return found.get(heading)


def header_count(body, key):
    head = re.split(r"(?m)^## ", body, maxsplit=1)[0]
    for line in head.splitlines():
        match = key_line.match(line)
        if match and match.group(1) == key:
            return int(bare(match.group(2))) if bare(match.group(2)).isdigit() else None
    return None


def fenced_content(lines, start, opener):
    # lines[start] is the opening fence. The block runs to the next fence of
    # the same character at least as long as the opener, and its content is the
    # exact text between them. Return the content and the index after the close.
    fence = opener.group(1)
    close = re.compile(rf"^\s*{re.escape(fence[0])}{{{len(fence)},}}\s*$")
    body, index = [], start + 1
    while index < len(lines):
        if close.match(lines[index]):
            return body, index + 1
        body.append(lines[index])
        index += 1
    return body, index


def items(lines, lead, fields, optional=()):
    found, current, last = [], None, None
    known = fields + optional
    index = 0
    while index < len(lines):
        line = lines[index]
        index += 1
        if not line.strip():
            continue
        match = key_line.match(line)
        name = match.group(1) if match and match.group(1) in known else None
        fresh = current is not None and name is not None and name not in current
        if name == lead:
            current, last = {}, None
            found.append(current)
        elif last in verbatim_fields:
            pass
        elif item_line.match(line):
            return None
        elif column0.match(line) and not fresh:
            if current is None and none_lead.match(line):
                continue
            return None
        if current is None:
            continue
        if name and name not in current:
            value = match.group(2)
            current[name], last = [value], name
            if not value.strip():
                # A multi-line value, or one containing a backtick, is a fenced
                # block on the lines after the field name.
                following = index
                while following < len(lines) and not lines[following].strip():
                    following += 1
                opener = fence_open.match(lines[following]) if following < len(lines) else None
                if opener:
                    content, index = fenced_content(lines, following, opener)
                    current[name] = content or [""]
        else:
            current[last].append(line.strip())
    return [{k: " ".join(v).strip() for k, v in item.items()} for item in found]


def keeps(lines, lead, fields, optional=()):
    if lines is None:
        return False
    found = items(lines, lead, fields, optional)
    if found is None:
        return False
    if not found:
        content = [line for line in lines if line.strip()]
        return bool(content) and bool(none_lead.match(content[0]))
    return all(all(field in item for field in fields) for item in found)


def reviewer_stances(round_n):
    found = []
    for path in relay.glob(f"r{round_n}-reviewer*.txt"):
        if "-prompt" in path.name:
            continue
        if not re.fullmatch(rf"r{round_n}-reviewer-.+\.txt", path.name):
            continue
        match = re.search(r"(?m)^stance:\s*(.+?)\s*$", path.read_text())
        if match:
            found.append(match.group(1))
    return found


def source_stances(approved_items, rejection_items):
    values = []
    for item in approved_items + rejection_items:
        values.append(item.get("source_stance", ""))
    return values


def stances_accounted(reviewer, sources):
    norms = [normalize_stance(s) for s in sources if normalize_stance(s)]
    for stance in reviewer:
        want = normalize_stance(stance)
        if not want:
            continue
        if not any(want in have for have in norms):
            return False
    return True


returns = [
    path for path in relay.glob("r*-verifier*.txt")
    if re.fullmatch(r"r[0-9]+-verifier(?:-[0-9]+)?\.txt", path.name)
]
proposal = [
    path for path in returns
    if not re.search(r"(?m)^mode:\s*citation\s*$", path.read_text())
]
if not proposal:
    raise SystemExit(1)
for path in proposal:
    text = path.read_text()
    round_n = re.fullmatch(r"r([0-9]+)-verifier(?:-[0-9]+)?\.txt", path.name).group(1)
    approved = section(text, "Approved edits")
    rejections = section(text, "Rejections and routes")
    if not keeps(approved, "id", approved_fields) or not keeps(
        rejections, "issue", rejection_fields, route_fields
    ):
        raise SystemExit(1)
    approved_items = items(approved, "id", approved_fields)
    rejection_items = items(rejections, "issue", rejection_fields, route_fields)
    routed = 0
    for item in rejection_items:
        decision = bare(item["decision"]).lower()
        if decision not in decisions or not item["reason"]:
            raise SystemExit(1)
        routed += decision == "human_routed"
    if header_count(text, "approved_edit_count") != len(approved_items):
        raise SystemExit(1)
    if header_count(text, "human_routed_count") != routed:
        raise SystemExit(1)
    if not stances_accounted(
        reviewer_stances(round_n),
        source_stances(approved_items, rejection_items),
    ):
        raise SystemExit(1)
PY
}
