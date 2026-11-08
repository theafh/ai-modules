#!/usr/bin/env python3
"""merge_log_preamble.py — converge a wiki log.md preamble to canonical text.

The ``log.md`` preamble is the H1 prelude the linter's
``check_verbatim_boilerplate`` compares against
``references/template_log.md``: everything above the first ``##`` heading.
This script reconciles that region unit by unit instead of restoring it
wholesale, so an owner-added line survives by construction.

The canonical unit set is declared once in ``CANONICAL_UNITS`` below. Each
entry carries a stable id, its current match anchor, and prior anchors
(aliases) that stay empty until a template rename ships one. A labeled unit's
anchor is its ``> Label:`` token; an unlabeled unit's anchor is a committed
stem string. Identity is decided here and nowhere else: a live unit is
canonical exactly when it resolves through an entry's current anchor or one of
its aliases.

Run against one wiki's ``log.md``::

    python3 merge_log_preamble.py /path/to/wiki/log.md

Exit codes:
    0  converged (or already converged; reports "no change")
    1  refused: template/table mismatch, a duplicate canonical unit, an
       ambiguous local rewrite, or undecidable drift inside a canonical unit.
       Nothing is written.
    2  usage or file error.

The template is resolved relative to this script's own directory, and the
preamble region is extracted with ``lint.extract_h1_prelude`` so the script
and the linter cannot disagree about what the region is.
"""

from __future__ import annotations

import difflib
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
REFERENCES_DIR = SCRIPTS_DIR.parent / "references"
TEMPLATE_LOG = REFERENCES_DIR / "template_log.md"

# Import the linter's region extractor directly. The script and the linter
# must share one definition of "the preamble", or a future edit could make
# them disagree about which lines this merge owns.
sys.path.insert(0, str(SCRIPTS_DIR))
from lint import extract_h1_prelude  # noqa: E402


# A live unit whose text is at least this similar to a missing canonical
# unit's text is treated as an ambiguous local rewrite of that unit rather
# than as an owner line. The guard fires only when the canonical unit is
# missing AND an unmatched live unit resembles it. 0.60 keeps a clearly
# distinct owner line from tripping the guard: a short local note against a
# long canonical rule scores far below it (the fixtures' owner line scores
# under 0.30 against every canonical unit), while a reworded near-copy of
# the rule — the genuinely undecidable case — scores above it. The measure
# is difflib.SequenceMatcher.ratio() over whitespace-collapsed unit text.
SIMILARITY_THRESHOLD = 0.60

# A labeled preamble unit starts with `> Label: ` where Label is a
# capitalized word token. This is a structural boundary rule, not the
# identity rule: it decides where one unit ends and the next begins, while
# CANONICAL_UNITS decides which units are canonical.
LABEL_RE = re.compile(r"^> ([A-Z][A-Za-z0-9_-]*): ")


@dataclass(frozen=True)
class CanonicalUnit:
    """One canonical preamble unit's declared identity.

    ``id`` is stable across anchor renames. ``anchor`` is the current match
    token (``Format:`` for a labeled unit, ``Chronological record`` for an
    unlabeled one). ``aliases`` holds prior anchors after a template rename.
    """

    id: str
    kind: str  # "labeled" | "unlabeled"
    anchor: str
    aliases: tuple[str, ...] = ()


# The canonical preamble unit inventory, derived from
# references/template_log.md at implementation time. Order is canonical
# order: the merge inserts a missing unit at its position in this sequence.
# Every entry is validated against the template on every run, so a template
# edit that renames or drops an anchor without updating this table fails
# loudly before it can reach a wiki.
CANONICAL_UNITS: tuple[CanonicalUnit, ...] = (
    CanonicalUnit("chronological-record", "unlabeled", "Chronological record"),
    CanonicalUnit("format", "labeled", "Format:"),
    CanonicalUnit("actions", "labeled", "Actions:"),
    CanonicalUnit("entries", "labeled", "Entries:"),
    CanonicalUnit("repair", "labeled", "Repair:"),
    CanonicalUnit("scope", "labeled", "Scope:"),
    CanonicalUnit("body", "labeled", "Body:"),
    CanonicalUnit("rotation", "unlabeled", "When this file exceeds"),
)


class MergeError(Exception):
    """A refusal that names the offending unit and writes nothing."""


def _unlabeled_anchors(specs: tuple[CanonicalUnit, ...]) -> tuple[str, ...]:
    anchors: list[str] = []
    for spec in specs:
        if spec.kind == "unlabeled":
            anchors.extend((spec.anchor, *spec.aliases))
    return tuple(anchors)


def _is_boundary(line: str, specs: tuple[CanonicalUnit, ...]) -> bool:
    """True when ``line`` starts a new preamble unit.

    A label-shaped blockquote line is a boundary even when it resolves to no
    canonical entry, so an owner's ``> Local:`` line becomes its own
    preserved unit instead of being swallowed by the unit above it.
    """
    if LABEL_RE.match(line):
        return True
    return any(line.startswith(f"> {stem}") for stem in _unlabeled_anchors(specs))


def _parse_region(
    region: str, specs: tuple[CanonicalUnit, ...]
) -> tuple[list[str], list[list[str]]]:
    """Split a preamble region into (header lines, ordered unit line-lists).

    The header is the H1 and the blank lines immediately after it. A unit is
    one blockquote or one plain paragraph, and it ends at a boundary, a blank
    line, or a transition between blockquote and plain text. Terminating on a
    blank line and on a non-continuation line is what keeps an owner's plain
    line from being absorbed into the canonical unit above it: without it the
    merge would replace the owner line with template text.

    A blank line is its own unit so it passes through as owner content and
    re-serialization stays byte-identical.
    """
    header: list[str] = []
    units: list[list[str]] = []
    current: list[str] | None = None

    def flush() -> None:
        nonlocal current
        if current is not None:
            units.append(current)
            current = None

    for line in region.splitlines():
        if _is_boundary(line, specs):
            flush()
            current = [line]
            continue
        if current is None:
            if not units and (line == "" or line.startswith("# ")):
                header.append(line)
                continue
            if line == "":
                units.append([""])
                continue
            current = [line]
            continue
        if line == "":
            flush()
            units.append([""])
            continue
        if current[0].startswith("> ") == line.startswith("> "):
            current.append(line)
        else:
            flush()
            current = [line]
    flush()
    return header, units


def _resolve(unit: list[str], specs: tuple[CanonicalUnit, ...]) -> str | None:
    """Return the canonical id a live unit resolves to, or None.

    Live units resolve through an entry's current anchor or one of its
    aliases, so a downstream wiki that still carries a prior anchor refreshes
    rather than duplicating.
    """
    first = unit[0]
    match = LABEL_RE.match(first)
    if match:
        token = f"{match.group(1)}:"
        for spec in specs:
            if spec.kind == "labeled" and token in (spec.anchor, *spec.aliases):
                return spec.id
        return None
    for spec in specs:
        if spec.kind != "unlabeled":
            continue
        for anchor in (spec.anchor, *spec.aliases):
            if first.startswith(f"> {anchor}"):
                return spec.id
    return None


def _resolve_current(unit: list[str], specs: tuple[CanonicalUnit, ...]) -> str | None:
    """Return the canonical id a *template* unit resolves to, or None.

    The template side resolves through current anchors only. An alias exists
    for live units a rename left behind, so accepting one here would let the
    canonical template drift onto its own alias while validation still
    passed, and the "current anchor appears exactly once" guarantee would be
    unenforced.
    """
    first = unit[0]
    match = LABEL_RE.match(first)
    if match:
        token = f"{match.group(1)}:"
        for spec in specs:
            if spec.kind == "labeled" and token == spec.anchor:
                return spec.id
        return None
    for spec in specs:
        if spec.kind != "unlabeled":
            continue
        if first.startswith(f"> {spec.anchor}"):
            return spec.id
    return None


def _owner_inserts(
    unit: list[str], template_unit: list[str], canonical_id: str
) -> list[str]:
    """Return the owner lines a resolving live unit adds to canonical text.

    A live blockquote line that carries no anchor is indistinguishable from a
    soft-wrapped continuation of the unit above it, so an owner line appended
    to (or inserted inside) a canonical unit would be replaced by template
    text on refresh. Aligning the live unit against the current template unit
    line by line separates the two possibilities that a line-count split
    cannot:

    * only ``equal`` opcodes: the unit already carries canonical text, and
      there is nothing to preserve.
    * ``equal`` plus ``insert`` opcodes: the unit is the canonical text with
      owner lines inserted, so those inserted lines are returned for the
      caller to keep byte-identically at their position inside the unit.
    * ``replace`` or ``delete`` opcodes: the unit is canonical drift, not
      owner content, so it is refreshed whole to current template text and no
      lines are returned. This is what keeps a drifted unit that grew past the
      template's line count from leaving a stale canonical tail behind.
    * ``replace``/``delete`` together with ``insert``: undecidable, because
      the extra lines could be owner content or stale canonical wording. The
      merge refuses loudly and writes nothing rather than guessing.

    Raises ``MergeError`` naming ``canonical_id`` for the undecidable case.
    """
    opcodes = difflib.SequenceMatcher(
        None, template_unit, unit, autojunk=False
    ).get_opcodes()
    tags = {tag for tag, *_ in opcodes}
    if tags <= {"equal", "insert"}:
        return [
            line
            for tag, _i1, _i2, j1, j2 in opcodes
            if tag == "insert"
            for line in unit[j1:j2]
        ]
    if "insert" in tags:
        raise MergeError(
            f"undecidable drift in canonical unit {canonical_id!r}: the live "
            f"unit both rewords canonical text and adds lines that could be "
            f"owner content or stale canonical wording (first line: "
            f"{unit[0]!r}); refusing to guess"
        )
    return []


def _reconcile_header(
    live_header: list[str], template_header: list[str]
) -> tuple[list[str], list[str]]:
    """Reconcile the live H1 block against the canonical one.

    The canonical H1 line and the blank line beneath it come from
    ``template_header``. The H1 slot is the live line byte-equal to the
    canonical H1 when one exists, so an owner ``# `` heading that sits above
    the canonical H1 keeps its position and its bytes. Only when no live line
    matches and exactly one live ``# `` line exists does that single line take
    the slot, which converges a reworded H1. Every other live ``# `` header
    line is owner content: it keeps its bytes and its order, so an owner's
    extra heading survives while a reworded H1 or a missing blank line beneath
    it converges. Returns ``(header, owner_lines)``.

    When no live line is byte-equal to the canonical H1 and more than one live
    ``# `` line exists, the shape is undecidable: an owner heading above a
    reworded H1 is indistinguishable from a reworded H1 above an owner
    heading, and picking the first would silently delete the owner line.
    Raises ``MergeError`` naming the ambiguous header in that case.
    """
    canonical_h1 = template_header[:1]
    canonical_blank = template_header[1:]

    live_h1: int | None = None
    if canonical_h1:
        live_h1 = next(
            (
                index
                for index, line in enumerate(live_header)
                if line == canonical_h1[0]
            ),
            None,
        )
    if live_h1 is None:
        heading_lines = [
            index
            for index, line in enumerate(live_header)
            if line.startswith("# ")
        ]
        if canonical_h1 and len(heading_lines) > 1:
            raise MergeError(
                f"ambiguous header: no live heading line equals the canonical "
                f"H1 {canonical_h1[0]!r} and the preamble carries "
                f"{len(heading_lines)} live '# ' lines "
                f"({[live_header[index] for index in heading_lines]!r}); "
                f"refusing to guess which one is the H1"
            )
        live_h1 = heading_lines[0] if heading_lines else None
    if live_h1 is None:
        return list(template_header), []

    header = list(live_header)
    header[live_h1 : live_h1 + 1] = canonical_h1
    if (
        header[live_h1 + 1 : live_h1 + 1 + len(canonical_blank)]
        != canonical_blank
    ):
        header[live_h1 + 1 : live_h1 + 1] = canonical_blank
    owner_lines = [
        line
        for index, line in enumerate(live_header)
        if index != live_h1 and line.startswith("# ")
    ]
    return header, owner_lines


def _serialize(header: list[str], units: list[list[str]]) -> str:
    lines = list(header)
    for unit in units:
        lines.extend(unit)
    return "\n".join(lines)


def validate_template(
    region: str, specs: tuple[CanonicalUnit, ...]
) -> list[list[str]]:
    """Parse the canonical template and validate it against the identity table.

    Template units resolve through current anchors only; an alias exists for
    live units a rename left behind and never satisfies the template side.

    Raises ``MergeError`` when a template unit resolves to no entry, when an
    entry's anchor is absent or repeated, when the template order differs
    from the table order, or when re-serializing the parsed units does not
    reproduce the region byte-identically. This is what makes a template edit
    in this repo that renames or drops an anchor without updating the table
    fail in the repo's own tests before it reaches a wiki.
    """
    header, units = _parse_region(region, specs)
    resolved: list[str] = []
    for unit in units:
        rid = _resolve_current(unit, specs)
        if rid is None:
            raise MergeError(
                f"template unit starting {unit[0]!r} resolves to no identity entry"
            )
        resolved.append(rid)

    counts = Counter(resolved)
    for spec in specs:
        seen = counts.get(spec.id, 0)
        if seen != 1:
            raise MergeError(
                f"template carries {seen} copies of canonical unit "
                f"{spec.id!r} (expected exactly one)"
            )

    expected_order = [spec.id for spec in specs]
    if resolved != expected_order:
        for position, (actual, expected) in enumerate(
            zip(resolved, expected_order)
        ):
            if actual != expected:
                raise MergeError(
                    f"template unit order differs from the identity table at "
                    f"position {position}: found {actual!r}, expected {expected!r}"
                )

    if _serialize(header, units) != region:
        raise MergeError(
            "template preamble does not re-serialize byte-identically from "
            "its parsed units"
        )
    return units


def _normalize(text: str) -> str:
    return " ".join(text.split())


def _unit_text(unit: list[str]) -> str:
    return _normalize(" ".join(unit))


def merge(
    live_region: str,
    template_header: list[str],
    template_units: list[list[str]],
    specs: tuple[CanonicalUnit, ...],
) -> tuple[str, list[list[str]]]:
    """Merge a live preamble against the canonical units.

    Returns ``(merged_region, owner_units)``. The canonical H1 line and the
    blank line beneath it come from ``template_header``, not from the live
    region, so the header is reconciled like every other canonical line: a live
    preamble that differs from canonical in its H1 or the blank line beneath it
    converges instead of merging to itself and reporting ``no change``. Any
    further live ``# `` header line is owner content and keeps its position.
    Owner units are the unmatched live units plus any owner lines inserted
    inside a canonical unit, kept so the caller can self-check their
    preservation. Raises ``MergeError`` on a duplicate canonical unit, an
    ambiguous local rewrite, or undecidable drift inside a canonical unit.
    """
    live_header, live_units = _parse_region(live_region, specs)
    header, owner_header = _reconcile_header(live_header, template_header)
    positions = {spec.id: position for position, spec in enumerate(specs)}

    live_resolved: list[str | None] = []
    owner_extras: list[list[str]] = []
    for unit in live_units:
        rid = _resolve(unit, specs)
        live_resolved.append(rid)
        if rid is None:
            owner_extras.append([])
            continue
        owner_extras.append(
            _owner_inserts(unit, template_units[positions[rid]], rid)
        )

    seen: Counter[str] = Counter()
    for unit, rid in zip(live_units, live_resolved):
        if rid is None:
            continue
        seen[rid] += 1
        if seen[rid] > 1:
            raise MergeError(
                f"duplicate canonical unit {rid!r} in the live preamble "
                f"(first line: {unit[0]!r})"
            )

    template_by_id = {
        spec.id: (position, template_units[position])
        for position, spec in enumerate(specs)
    }
    # Owner units in merged-output order: an unmatched live unit sits where it
    # sits, and a resolving unit's inserted owner lines sit inside that unit.
    # Building this list in output order (rather than all unmatched units first)
    # keeps ``self_check``'s single forward cursor valid when a mid-unit owner
    # line precedes a later unmatched owner unit.
    owner_units: list[list[str]] = []
    # A preserved owner `# ` header line sits above every unit, so it opens the
    # owner-unit list and keeps the self-check's forward cursor valid.
    if owner_header:
        owner_units.append(owner_header)
    for unit, rid, extras in zip(live_units, live_resolved, owner_extras):
        if rid is None:
            owner_units.append(unit)
        elif extras:
            owner_units.append(extras)

    # Near-duplicate guard: a missing canonical unit plus an unmatched owner
    # line that closely resembles it is the one genuinely ambiguous case —
    # did the owner rewrite this rule, or add a similar one? Refuse loudly
    # rather than insert a duplicate or silently keep both.
    for spec in specs:
        if seen.get(spec.id):
            continue
        canonical_text = _unit_text(template_by_id[spec.id][1])
        for owner in owner_units:
            ratio = difflib.SequenceMatcher(
                None, canonical_text, _unit_text(owner)
            ).ratio()
            if ratio >= SIMILARITY_THRESHOLD:
                raise MergeError(
                    f"ambiguous local rewrite: canonical unit {spec.id!r} is "
                    f"missing and an owner line closely resembles it "
                    f"(similarity {ratio:.2f}; first line: {owner[0]!r}); "
                    f"refusing to insert or overwrite"
                )

    merged_units: list[list[str]] = []
    emitted: set[str] = set()
    for unit, rid, extras in zip(live_units, live_resolved, owner_extras):
        if rid is None:
            merged_units.append(unit)
            continue
        position = template_by_id[rid][0]
        # Insert any canonical unit that canonically precedes this one and
        # has not been emitted yet. This places a missing unit at its
        # canonical position relative to the units that survived.
        for earlier in range(position):
            earlier_id = specs[earlier].id
            if earlier_id not in emitted:
                merged_units.append(template_units[earlier])
                emitted.add(earlier_id)
        merged_units.append(template_units[position])
        emitted.add(rid)
        if extras:
            # Owner lines inserted inside (or appended to) the canonical unit
            # keep their position. The live unit's equal blocks are already
            # byte-identical to the template, so emitting it whole preserves
            # both the owner line's offset and the canonical text; appending
            # the extras after the unit would relocate them to its end.
            merged_units[-1] = unit
            continue

    for position, spec in enumerate(specs):
        if spec.id not in emitted:
            merged_units.append(template_units[position])
            emitted.add(spec.id)

    return _serialize(header, merged_units), owner_units


def self_check(
    merged_region: str,
    template_units: list[list[str]],
    specs: tuple[CanonicalUnit, ...],
    owner_units: list[list[str]],
) -> None:
    """Assert the merged region satisfies the script's guarantees.

    Every canonical unit appears exactly once with its canonical text intact
    (the template lines in order, with any inserted owner lines at their
    positions), and every owner unit survives unchanged and in order. Raises
    ``MergeError`` naming the offending unit.
    """
    _, units = _parse_region(merged_region, specs)
    resolved = [_resolve(unit, specs) for unit in units]
    counts = Counter(rid for rid in resolved if rid is not None)
    owner_lines = {line for owner in owner_units for line in owner}

    for position, spec in enumerate(specs):
        seen = counts.get(spec.id, 0)
        if seen != 1:
            raise MergeError(
                f"self-check failed: canonical unit {spec.id!r} appears "
                f"{seen} times after the merge"
            )
        actual = next(
            unit for unit, rid in zip(units, resolved) if rid == spec.id
        )
        # The canonical template lines must appear exactly once and in order.
        # Owner lines may sit between them (an owner insert inside the unit),
        # so exact block equality is too strict; every line that is not the
        # next canonical line must be a known owner line, which keeps a stale
        # or otherwise non-template line from passing as an interleaving.
        cursor = 0
        for line in template_units[position]:
            while cursor < len(actual) and actual[cursor] != line:
                if actual[cursor] not in owner_lines:
                    raise MergeError(
                        f"self-check failed: canonical unit {spec.id!r} "
                        f"carries non-template, non-owner line "
                        f"{actual[cursor]!r} after the merge"
                    )
                cursor += 1
            if cursor >= len(actual):
                raise MergeError(
                    f"self-check failed: canonical unit {spec.id!r} does not "
                    f"carry current template text after the merge"
                )
            cursor += 1
        for line in actual[cursor:]:
            if line not in owner_lines:
                raise MergeError(
                    f"self-check failed: canonical unit {spec.id!r} carries "
                    f"non-template, non-owner line {line!r} after the merge"
                )

    merged_lines = merged_region.splitlines()
    cursor = 0
    for owner in owner_units:
        for line in owner:
            while cursor < len(merged_lines) and merged_lines[cursor] != line:
                cursor += 1
            if cursor >= len(merged_lines):
                raise MergeError(
                    f"self-check failed: owner line {line!r} from unit "
                    f"{owner[0]!r} is missing from the merged preamble"
                )
            cursor += 1


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(
            "usage: merge_log_preamble.py <path/to/wiki/log.md>",
            file=sys.stderr,
        )
        return 2

    log_path = Path(argv[1])
    if not log_path.is_file():
        print(f"merge_log_preamble: not a file: {log_path}", file=sys.stderr)
        return 2
    if not TEMPLATE_LOG.is_file():
        print(
            f"merge_log_preamble: canonical template missing: {TEMPLATE_LOG}",
            file=sys.stderr,
        )
        return 2

    try:
        template_region = extract_h1_prelude(
            TEMPLATE_LOG.read_text(encoding="utf-8")
        )
        template_units = validate_template(template_region, CANONICAL_UNITS)
        template_header, _ = _parse_region(template_region, CANONICAL_UNITS)
        text = log_path.read_text(encoding="utf-8")
        live_region = extract_h1_prelude(text)
        tail = text[len(live_region):]
        merged, owner_units = merge(
            live_region, template_header, template_units, CANONICAL_UNITS
        )
        self_check(merged, template_units, CANONICAL_UNITS, owner_units)
    except MergeError as exc:
        print(f"merge_log_preamble: {exc}", file=sys.stderr)
        return 1

    if merged == live_region:
        print("merge_log_preamble: no change")
        return 0

    # The template separates its region from the first ``##`` heading with a
    # blank line, and ``extract_h1_prelude`` strips that separation out of the
    # region into ``tail``. Restore it whenever the live tail does not carry
    # it: an empty or H1-less preamble leaves ``tail`` opening at the heading
    # itself, so without this the canonical region would be appended to the
    # heading and destroy it.
    if tail and not tail.startswith("\n\n"):
        tail = "\n\n" + tail.lstrip("\n")

    log_path.write_text(merged + tail, encoding="utf-8")
    print("merge_log_preamble: converged")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
