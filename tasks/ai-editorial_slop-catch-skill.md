---
description: "Build slop_catch in ai_editorial: a ported Python detector plus a structural-tell ruleset that score a draft's AI-tell density and return replacements, run as the humanizer's check pass."
scope: "ai_editorial plugin"
created: 2026-06-01T23:31:06
updated: 2026-10-17T13:50:32
status: open
reported-by: Andreas Hoffmann
---

# Build the slop_catch skill

## Goal

Add the `slop_catch` skill to the `ai_editorial` plugin. Given a draft, it returns the AI tells the text carries, what to put in their place, and how heavily the text is loaded with them overall.

Three commitments shape what the skill delivers:

- **It hands back replacements, not just flags.** Every tell it reports arrives with what to write instead — a plainer word, a rewrite direction, or the instruction to cut the passage where it carries nothing.
- **It reads density, not incidents.** One slop word in a page of prose is ordinary human writing; the signal is accumulation. The skill therefore leads with a weighted density read over the whole draft and reports single hits as material for the replacement list rather than as defects.
- **It runs as the writing skills' check pass.** Its primary use is verifying text `language_humanizer` or `ghost_writer` has just produced, confirming the delivered prose is free of the tells before it reaches a reader. It serves a standalone review of any draft on the same mechanics.

The skill delivers that through two detection layers that stay distinct end to end:

- A **literal layer**, carried by a bundled Python detector ported from the `ai_slop_detector` browser extension, which finds tells decidable from the characters on the page — slop vocabulary, phrase templates, and typographic anomalies — and returns exact spans, replacements, and the density score.
- A **judgement layer**, carried by a reference ruleset the agent reads the draft against, which finds tells that live in sentence shape, framing, and rhythm rather than in any fixed string — the "it is not X, but Y" construction and its relatives.

## Context

- The plugin shell is built (`ai-editorial_plugin-scaffold.md`, archived). This skill lands in `plugins/ai_editorial/skills/slop_catch/`.
- **Source to port.** The literal layer's detection data lives in the `ai_slop_detector` browser extension — a separate repository checked out beside this one, reachable as `../ai_slop_detector` from this repo root. Its `content.js` carries two top-level definitions: `const SLOP_TERMS`, an array of case-insensitive global regexes split by the in-file comment markers `=== SINGLE WORDS ===` and `=== MULTI-WORD PHRASES ===`, and `const FORMAT_PATTERNS`, an object of eight named character-class regexes. The same repo's `notes/slop_vocab.md` carries the vocabulary as a plain term-and-phrase list, which reads more cleanly than the regexes for the port's word data. Should that checkout be absent, ask the user for those two files rather than reconstructing the lists from memory; the pattern inventory this task records below fixes what a complete port contains, while the terms themselves come from the source.
- **What the source contains, as the port's completeness contract.** `SLOP_TERMS` holds 67 patterns: 35 single-word entries and 32 multi-word phrase entries. A single-word entry carries the term with its morphological variants in one alternation, so `delve` ships as `delve|delves|delving` and `facilitate` as `facilitate|facilitates|facilitated|facilitating|facilitation`. A phrase entry tolerates variable whitespace between tokens, and several also tolerate apostrophe and dash variants, so `in today's fast-paced world` matches across straight and curly apostrophes and across the whole dash family. The extension emits one record per match carrying the pattern identity, the layer it came from, the matched text, and the offset.
- **The eight `FORMAT_PATTERNS` classes, recorded here as codepoints** because their character sets are the part of the source that resists reconstruction, and because several of them are invisible on screen or near-identical to their plain-ASCII counterparts:
  - `unusualDashes` — `U+2013`, `U+2014`, `U+2053`, `U+301C` (en dash, em dash, swung dash, wave dash)
  - `unusualQuotes` — `U+2018`, `U+2019`, `U+201C`, `U+201D` (curly single and double quotes)
  - `unusualSpaces` — `U+2000`–`U+200A`, `U+202F`, `U+205F`, `U+3000` (en quad through hair space, narrow and medium mathematical spaces, ideographic space)
  - `specialDashes` — `U+2010`, `U+2011`, `U+2012`, `U+2015` (hyphen, non-breaking hyphen, figure dash, horizontal bar)
  - `invisibleChars` — `U+200B`–`U+200D`, `U+FEFF` (zero-width space, zero-width non-joiner, zero-width joiner, byte-order mark)
  - `suspiciousBackticks` — a run of 15 or more non-newline characters enclosed in plain backticks
  - `exoticBackticks` — `U+02CB`, `U+02C8`, `U+2035`, `U+2032`, `U+2033`, `U+2034` (modifier grave accent, modifier vertical line, reversed prime, prime, double prime, triple prime)
  - `exoticPunctuation` — `U+2026`, `U+2022`, `U+2023`, `U+2043`, `U+204C`, `U+204D` (ellipsis, bullet, triangular bullet, hyphen bullet, black leftwards bullet, black rightwards bullet)
- **Why the port changes context, not content.** The extension highlights live web pages, where every hit is worth a colour and a lone curly quote costs nothing. This skill judges a draft about to reach a reader, where the same curly quote most often came from a word processor and where the author needs to know whether the text is broadly slopped or merely carries one reachable word. The port keeps every pattern and adds the tiering, scoring, and replacement data the Approach defines.
- Write the skill `description:` so it triggers both on checking text a writing skill just delivered and on reviewing any draft for AI tells, and so a router can tell it from the two prose skills beside it: this skill diagnoses, scores, and proposes replacements while leaving the text untouched, and the other two deliver rewritten text.
- **Authoring authorities.** The `SKILL.md` and the reference ruleset are instructions an AI consumes, so they follow `ai_instruction_writing` for positive, action-oriented carriers and `ai_instruction_formatting` for the pseudo-XML body. A tell entry describes a pattern to recognize and what to write instead, which keeps those entries positive without strain.
- Follow the standing repo rules for skill authoring and for bundling a skill's helper scripts; this task supplies the `slop_catch`-specific detector workflow, source-port contract, scoring model, tell set, and Python style-guide requirement.

## Approach

Build three artefacts under `plugins/ai_editorial/skills/slop_catch/`.

### 1. The detector — `scripts/detect_slop.py`

Port both `SLOP_TERMS` and `FORMAT_PATTERNS` into Python, preserving every pattern and its case-insensitive matching, and hold the ported table as a module-level data structure so the script stays one self-contained file. The script adheres to the `format_python` style guide.

**Input.** Accept an optional path argument naming the draft file, and read the draft from standard input when no path is given.

**Output.** Emit one JSON document on standard output holding a list of findings, a replacement list, and a score block. Each finding carries the tell identifier, the layer it came from (`vocabulary`, `phrase`, or `formatting`), its confidence tier, the 1-based line and column where it starts, the matched text, and the replacement guidance below. The replacement list groups findings by tell so an author sees each swap once with its occurrence count.

**Exit behaviour.** Exit 0 whenever the scan completed, with findings or without them, since a finding is a result rather than a failure. Reserve a non-zero exit for a usage or I/O error, and write that diagnosis to standard error.

**Replacement data, carried per pattern in the ported table.** Each of the 35 vocabulary entries carries one or more plain alternatives, or the marker `cut` where the term earns nothing in any context. Each of the 32 phrase entries carries a rewrite direction rather than a fixed swap, since a phrase template is replaced by saying the thing directly. Each formatting class carries a normalization action: delete for `invisibleChars`, and the plain-ASCII equivalent for the typographic classes.

**Confidence tiers.** Every finding carries one of three tiers, assigned by how strongly the pattern implicates machine authorship in a human-written draft:

- **strong** — the `invisibleChars` class and the assistant self-reference phrases such as `as an AI language model` and `I do not have personal data`, which a person writing prose has no reason to produce.
- **moderate** — the slop vocabulary and the phrase templates, which a person writes occasionally and an AI writes constantly.
- **weak** — the typographic classes `unusualDashes`, `unusualQuotes`, `unusualSpaces`, `specialDashes`, `exoticBackticks`, `exoticPunctuation`, and `suspiciousBackticks`, which any word processor or typesetting pass also produces.

**The density score.** The score block turns the findings into one accumulation read, so that a lone hit stays low and a text loaded with tells stands out:

- Weight each finding by tier: **strong** counts 5, **moderate** counts 1, and **weak** counts 0, staying out of the score and reporting as advisory normalization work.
- Sum the weights and express the total per 1000 words, dividing by the draft's whitespace-separated word count with that count floored at 250, so a short draft cannot be pushed up by a single hit.
- Band the result: **clean** below 3, **watch** from 3 up to 8, and **heavy** above 8. On a 1000-word draft that puts two slop words in clean, five in watch, and a dozen in heavy, and it puts one strong finding on its own in watch.
- Emit the band, the density figure, the weighted total, and the word count alongside the findings.

Treat these thresholds as the starting calibration this task sets. The eval fixtures below exercise them; where a fixture and a threshold disagree, adjust the threshold and record what moved and why.

### 2. The structural-tell ruleset — `references/structural_tells.md`

Write the tells the judgement layer covers. Each entry names the tell, states the shape it takes with one compact illustration that fixes its meaning, states why a reader registers it as machine-written, and gives the rewrite direction that removes it. Cover these four groups.

**Sentence shape.**

- **Negation antithesis** — a claim built as a rejected first half and an elevated second: `it is not X, but Y`, `this isn't just a tool — it's a partner`, `less a rewrite, more a rethink`.
- **Correlative escalation** — `not only X, but also Y`, reaching for weight the content does not carry.
- **Tricolon habit** — three parallel items everywhere, in adjectives, clauses, and list lengths alike, regardless of how many the subject actually has.
- **Participial trailing clause** — a sentence that closes on a floating `-ing` clause of benefit: `…, ensuring seamless collaboration`, `…, allowing teams to focus on what matters`.
- **Uniform rhythm** — sentences and paragraphs of near-identical length across the whole draft, with no short sentence for emphasis and no long one for a complex thought.

**Framing and stance.**

- **Prompt restatement** — an opening sentence that hands the question back before answering it.
- **Sycophantic opener** — `Great question!`, `You're absolutely right`, and their relatives.
- **Structure announcement** — `Let's dive in`, `In this article, we'll explore…`, narrating the document instead of writing it.
- **False balance** — `While X offers real benefits, it also presents challenges`, with neither side developed.
- **Weasel attribution** — `studies show`, `experts agree`, `many argue`, with no source behind them.
- **Hollow hedging** — stacked modals and qualifiers that leave no claim standing.

**Closing moves.**

- **Recap conclusion** — `In conclusion` or `To sum up` followed by a restatement of what the reader just read.
- **Uplift closer** — `the future of X is bright`, `one thing is clear`, `it remains to be seen`, or a call to action nobody asked for.

**Texture and layout.**

- **Empty intensifiers** — `significantly`, `truly`, `incredibly`, `game-changing`, `robust`, `comprehensive`, doing the work a specific would do.
- **Metaphor inflation** — `journey`, `landscape`, `backbone`, `cornerstone`, `north star`, reached for where a plain noun fits.
- **Decorated list uniformity** — every bullet as `**Term** — explanation`, emoji or checkmark bullets, all items the same length.
- **Definitional filler** — a paragraph defining an obvious term before the point arrives.
- **Flat coverage** — every section given the same depth regardless of what matters.

**The layer boundary, stated once in the ruleset.** The literal layer owns whatever a fixed string decides, and the judgement layer owns whatever needs the surrounding text. One family crosses that line by design: the detector carries a candidate pattern for the negation-antithesis skeleton (`isn't just … it's`, `not X, but Y` and their variants), and the ruleset's negation-antithesis entry instructs the agent to confirm or dismiss each candidate against its context, because the construction is also good human prose when the contrast is real. Confirmed candidates report as tells, and dismissed ones stay out of the report entirely. Every other tell reports from exactly one layer.

**How structural tells reach the score.** The script scores the literal layer alone, and the agent adds its confirmed structural tells on top: it raises the band one step when three or more distinct structural tells hold across the draft, and states which ones drove the raise. The band moves up only, so the script's read is the floor.

### 3. The skill file — `SKILL.md`

Frontmatter `name: slop_catch`, a matching H1, and a pseudo-XML body carrying the role, the activation triggers, the check-and-report workflow, and the output contract. The workflow runs the detector over the draft, reads the ruleset against the same draft, resolves the negation-antithesis candidates, applies the band raise, and merges both layers into one report.

The output contract leads with the verdict — the band, the density figure, and the word count it was measured over — so the author reads the accumulation before any individual hit. The replacement list follows as the actionable body: one entry per tell, giving what to write instead, the occurrence count, and each occurrence located by a quoted phrase. Confirmed structural tells follow with their rewrite directions. Weak formatting findings close the report as grouped per-class counts framed as normalization work, with instances listed where the author asks. The report leaves the draft untouched.

**Out of scope:**

- Rewriting the flagged prose. [ai-editorial_language-humanizer-skill.md](archive/ai-editorial_language-humanizer-skill.md) and [ai-editorial_ghost-writer-skill.md](ai-editorial_ghost-writer-skill.md) produce and rewrite prose; this skill checks what they produced and returns replacements for them to apply. The handoff needs nothing on their side, since the skill takes delivered text as its input, so build this one to be invocable that way rather than reaching into either skill's workflow. Keep the structural-tell ruleset readable as a standalone reference, because `ghost_writer`'s task weighs referencing it directly to keep the two consistent.
- Wiring this check into either writing skill's own workflow, which changes that skill's contract and belongs to its task; this task delivers `slop_catch` so it can be invoked that way.
- Changing the `ai_slop_detector` extension, which is read-only input to this port.
- Scoring whether a text was machine-generated, whether by statistical means such as perplexity and burstiness or by watermark detection. The density score rates how heavily a draft carries known tells, for an author to act on, rather than issuing an authorship verdict.

## Acceptance

- `plugins/ai_editorial/skills/slop_catch/` holds `SKILL.md`, `scripts/detect_slop.py`, and `references/structural_tells.md`.
- `detect_slop.py` carries the full ported inventory as a module-level table: 35 single-word vocabulary patterns, 32 multi-word phrase patterns, and all eight named formatting classes with the codepoint sets this task's Context records, each matching case-insensitively and each single-word entry carrying its morphological variants.
- Every entry in that table carries its replacement data per the Approach's **Replacement data** rule — plain alternatives or `cut` for a vocabulary term, a rewrite direction for a phrase template, a normalization action for a formatting class — and every finding the script emits carries the replacement guidance for the pattern that fired.
- `detect_slop.py` reads a draft from a path argument and from standard input, emits the JSON findings, replacement list, and score block the Approach defines, exits 0 on a completed scan with or without findings, and exits non-zero with a message on standard error for a usage or I/O error.
- The score block carries the band, the density figure, the weighted total, and the word count, computed by the Approach's **The density score** rule: tier weights of 5, 1, and 0; a per-1000-words denominator floored at 250 words; and the clean/watch/heavy bands at 3 and 8. Where an eval fixture and a threshold disagree, the shipped threshold and the record of what moved and why reflect that adjustment.
- `detect_slop.py` adheres to the `format_python` style guide.
- `references/structural_tells.md` carries an entry for every tell this task's `### 2. The structural-tell ruleset` section names, each stating the tell's shape with one compact illustration, why it reads as machine-written, and the rewrite direction that removes it; it states the layer boundary including the negation-antithesis crossing and its confirm-or-dismiss step, and the band-raise rule for three or more distinct structural tells.
- `SKILL.md` is pseudo-XML in the XML-instruction-body shape and passes `ai_instruction_formatting`'s bundled `scripts/lint_pseudo_xml.py`.
- `SKILL.md` documents how it invokes the script and how the script's JSON becomes reader-facing feedback, and carries the output contract in the Approach's order — verdict first, then the replacement list with occurrence counts and quoted locations, then the confirmed structural tells, then the grouped weak counts — along with the band-raise-only rule and the guarantee that the draft is left untouched.
- The skill `description:` states both trigger contexts — checking text a writing skill just delivered, and reviewing any draft for AI tells — and states the diagnose-score-and-propose axis that tells it apart from the two rewriting siblings in the plugin.
- Script unit tests exist under the repo's regression-harness layout and assert the ported inventory counts, one firing match per formatting class, replacement data present on every table entry, the JSON findings/replacement/score shape, tier assignment across all three tiers, the band boundaries including the 250-word denominator floor, and both exit paths.
- Behaviour evals for this skill exist under the repo's regression-harness layout, covering three scenarios:
  - a **tell-dense fixture** carrying a counted set of tells — three slop-vocabulary terms, one phrase template, one zero-width character, and three named structural tells drawn from three different groups — asserting the report lands in the heavy band, names all eight, assigns each to the right layer and tier, gives a replacement for each, and locates each by a quoted phrase from the fixture;
  - a **sparse-hit fixture** of otherwise plain human prose of at least 400 words carrying exactly two slop-vocabulary terms and nothing else, asserting the verdict lands in the clean band, that both terms still appear in the replacement list with their swaps, and that the report frames them as available improvements rather than as evidence the text is AI-written;
  - a **false-positive fixture** of human-written prose that uses em-dashes and curly quotes throughout and carries one genuine `not X, but Y` contrast where the opposition is real, asserting the verdict lands in the clean band, that the typographic hits report as grouped weak counts contributing nothing to the score, and that the negation candidate is dismissed rather than reported as a tell.
- Each eval scenario is run over a fixed denominator of five passes, and the recorded per-scenario pass rate over that denominator is the deliverable. The bar is every assertion holding on all five passes; when a scenario misses it, the report carries the measured rate and the diverging assertions and hands the disposition to the user rather than re-running for a better draw.
- `./deployment/deployment.sh --global --dry-run` previews `slop_catch` without error.
