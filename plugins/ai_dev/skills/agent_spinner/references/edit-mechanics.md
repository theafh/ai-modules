# Edit mechanics

This reference holds the kind notes. A kind note is a short note that `brief`
attaches to an item brief, and it tells the helper how one class of text
changes. Each section below is one class of text, written as the note the
helper reads.

## Pointers and claims

A pointer is a path, an identifier, a link target, or a slug. Scripted
replacement may touch a pointer. Every other occurrence is a claim, and a claim
changes only through a writer, a helper that edits whole sentences. Read the
item's diff for a pointer change, and hand every claim change to a writer.

## Hard-wrapped prose

Hard-wrapped prose carries line breaks inside its paragraphs, so one sentence
can span several lines. Span each edit across the whole sentence, across line
breaks, then reflow the paragraph and re-read it. Run a wrap-seam check that
finds sentences an edit split or joined at a wrap.

## Verbatim text

Quotations, archived records, and pinned commands and anchors stay
byte-identical. Re-grep each one after the run.

## Append-only records

After each write the record grew by exactly its entry, and the diff only adds
lines. Assert the growth after every write to the record.

## Moves

A move listing gives each moved path with its rename status and similarity, as
version control reports them. An add-plus-delete pair counts as a finding.
