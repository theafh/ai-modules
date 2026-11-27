---
description: "Build slop_catch in ai_editorial: a ported Python linter plus a structural-tell ruleset that list a draft's AI tells, score weighted density, and state the reduction target."
scope: "ai_editorial plugin"
created: 2026-06-01T21:31:06Z
updated: 2026-11-27T14:30:00Z
status: open
reported-by: Andreas Hoffmann
---

# Build the slop_catch skill

## Goal

Add the `slop_catch` skill to the `ai_editorial` plugin. Given a draft, it returns the AI tells the text carries, what to put in their place, how heavily the text is loaded with them overall, and the reduction target that says what to fix first.

Four commitments shape what the skill delivers:

- **It hands back replacements, not just flags.** Every tell it reports arrives with what to write instead — a plainer word, a rewrite direction, or the instruction to cut the passage where it carries nothing.
- **It reads density, not incidents.** No single tell proves AI authorship: one slop word in a page of prose is ordinary human writing, and the signal is accumulation. The skill therefore leads with a weighted density read over the whole draft, where more tells and stronger tells raise a likelihood reading rather than trigger a verdict. A lone hit is never reported as evidence that the text is AI-written.
- **It frames every tell as a reduction target.** The reader is an AI editing prose, so each reported tell reads as "reduce this", with the replacement or rewrite direction attached, and the report makes clear that working through the list lowers the density. The report asks the reader to reduce the tells rather than to judge authorship.
- **It runs as the writing skills' check pass.** Its primary use is verifying text `language_humanizer` or `ghost_writer` has just produced, confirming the delivered prose is free of the tells before it reaches a reader. It serves a standalone review of any draft on the same mechanics.

The skill delivers that through two detection layers that stay distinct end to end:

- A **literal layer**, carried by a bundled Python detector that ports an existing AI-slop term and format-pattern table, which finds tells decidable from the characters on the page — slop vocabulary, phrase templates, and typographic anomalies — and returns exact spans, replacements, and the density score.
- A **judgement layer**, carried by a reference ruleset the agent reads the draft against, which finds tells that live in sentence shape, framing, and rhythm rather than in any fixed string — the "it is not X, but Y" construction and its relatives.

## Context

- The plugin shell is built (`ai-editorial_plugin-scaffold.md`, archived). This skill lands in `plugins/ai_editorial/skills/slop_catch/`.
- **Source to port.** The literal layer's detection data is the `ai_slop_detector` extension's term-and-pattern table: a term list split into single-word entries and multi-word phrase entries, plus a format-pattern table of named character classes. The source's term list tolerates variable whitespace between phrase tokens and several apostrophe and dash variants, and it carries the term with its morphological variants in one alternation. The complete inventory is transcribed below, so the port reconstructs nothing from memory.
- **What the source contains, as the port's completeness contract.** The term table holds 67 patterns: 35 single-word entries and 32 multi-word phrase entries. A single-word entry carries the term with its morphological variants in one alternation, so `delve` ships as `delve|delves|delving` and `facilitate` as `facilitate|facilitates|facilitated|facilitating|facilitation`. A phrase entry tolerates variable whitespace between tokens, and several also tolerate apostrophe and dash variants, so `in today's fast-paced world` matches across straight and curly apostrophes and across the whole dash family. The detector emits one record per match carrying the pattern identity, the layer it came from, the matched text, and the offset. The exact source regex for every entry, its stable tell id, the eight formatting regexes, the character names, and the JS-to-Python translation rules are transcribed in **Source inventory — exact patterns** below, which is this port's fidelity contract.
- **The eight format-pattern classes, recorded here as codepoints** because their character sets are the part of the source that resists reconstruction, and because several of them are invisible on screen or near-identical to their plain-ASCII counterparts:
  - `unusualDashes` — `U+2013`, `U+2014`, `U+2053`, `U+301C` (en dash, em dash, swung dash, wave dash)
  - `unusualQuotes` — `U+2018`, `U+2019`, `U+201C`, `U+201D` (curly single and double quotes)
  - `unusualSpaces` — `U+2000`–`U+200A`, `U+202F`, `U+205F`, `U+3000` (en quad through hair space, narrow and medium mathematical spaces, ideographic space)
  - `specialDashes` — `U+2010`, `U+2011`, `U+2012`, `U+2015` (hyphen, non-breaking hyphen, figure dash, horizontal bar)
  - `invisibleChars` — `U+200B`–`U+200D`, `U+FEFF` (zero-width space, zero-width non-joiner, zero-width joiner, byte-order mark)
  - `suspiciousBackticks` — a run of 15 or more non-newline characters enclosed in plain backticks
  - `exoticBackticks` — `U+02CB`, `U+02C8`, `U+2035`, `U+2032`, `U+2033`, `U+2034` (modifier grave accent, modifier vertical line, reversed prime, prime, double prime, triple prime)
  - `exoticPunctuation` — `U+2026`, `U+2022`, `U+2023`, `U+2043`, `U+204C`, `U+204D` (ellipsis, bullet, triangular bullet, hyphen bullet, black leftwards bullet, black rightwards bullet)
- **Why the port changes context, not content.** A browser extension highlights live web pages, where every hit is worth a colour and a lone curly quote costs nothing. This skill judges a draft about to reach a reader, where the same curly quote most often came from a word processor and where the author needs to know whether the text is broadly slopped or merely carries one reachable word. The port keeps every pattern and adds the tiering, scoring, and replacement data the Approach defines.
- Write the skill `description:` so it triggers both on checking text a writing skill just delivered and on reviewing any draft for AI tells, and so a router can tell it from the two prose skills beside it: this skill diagnoses, scores, and proposes replacements while leaving the text untouched, and the other two deliver rewritten text.
- **Authoring authorities.** The `SKILL.md` and the reference ruleset are instructions an AI consumes, so they follow `ai_instruction_writing` for positive, action-oriented carriers and `ai_instruction_formatting` for the pseudo-XML body. A tell entry describes a pattern to recognize and what to write instead, which keeps those entries positive without strain.
- Follow the standing repo rules for skill authoring and for bundling a skill's helper scripts; this task supplies the `slop_catch`-specific detector workflow, source-port contract, scoring model, tell set, and Python style-guide requirement.

### Source inventory — exact patterns

**Provenance.** The source is the `ai_slop_detector` Chrome extension at commit `df0332d`, read from `content.js` (its detection tables, the source the sourcing rule below sends the implementer to), `notes/slop_vocab.md` (the human-readable term list), and `notes/ChatGPT-Watermark Detection Techniques.md` (the character-level research). `content.js` is the executable source of truth: every one of the 141 lines in `notes/slop_vocab.md` is matched by a source regex, while the table encodes `scaffold` and `supercharge` as stems rather than enumerating their forms. The table, not the prose list, is the contract. Every regex is transcribed verbatim from the source, including its duplicated characters, missing variants, and inconsistent quantifiers. Treat the transcription as the fidelity contract: the port reproduces each expression's matching behaviour, and the only permitted changes are the JS-to-Python translations listed under **Translation rules**.

**Sourcing rule for the exact patterns.** Read them from the source at implementation time rather than from a copy here. The source is the `ai_slop_detector` repository at commit `df0332d`; `content.js` holds three tables, and every regex the port carries is transcribed from them verbatim:

- `SLOP_TERMS` in `content.js`, the vocabulary and phrase entries together, each with its source regex literal, its flags, and any replacement data the table already carries.
- The format-pattern table that follows `SLOP_TERMS` in the same file, covering the eight formatting classes.
- `notes/slop_vocab.md`, the human-readable term list the tables encode, which the port uses to cross-check that no term was dropped.

The counts the Acceptance names (35 vocabulary entries, 32 phrase entries, 8 formatting classes) are what `content.js` at that commit contains; derive them from the file and assert them in the ported table rather than trusting this sentence. Where this task and `content.js` disagree, `content.js` at `df0332d` wins, and the divergence is recorded in the implementation report. Assign each entry a stable slug id so a report does not shift when the table is edited, and keep the source's array order out of the id scheme because it carries no meaning.

**Source quirks to preserve, not repair.** Each of these is deliberate port content:

- The apostrophe class is `[''\u2019\u2018]` — the ASCII apostrophe `U+0027` appears twice, followed by `U+2019` and `U+2018`. The duplicate is harmless and stays, so a later reader does not mistake it for a missing codepoint.
- The apostrophe is optional (`?`), so `todays` and `today's` both match; the dash run is optional and unlimited (`*`), so `fastpaced`, `fast-paced`, `fast—paced`, and `fast -- paced` all match.
- The dash class is `[\s\u002D\u2010\u2011\u2012\u2013\u2014\u2015\u2212\uFE63\uFF0D]`: whitespace, ASCII hyphen-minus, hyphen, non-breaking hyphen, figure dash, en dash, em dash, horizontal bar, minus sign, small hyphen-minus, and fullwidth hyphen-minus.
- `elevate` ships without `elevated`, and `notes/slop_vocab.md` omits it too. `embrace`, `foster`, `harness`, and `leverage` likewise carry no `-ment` or other derivations beyond those listed. The inventory is what the source ships, not a complete morphology.
- `unprecedented` includes the nonstandard adverb `unprecedently` alongside `unprecedentedly`. Both stay.
- `scaffold` uses `\bscaffold(?:ed|s|ing)?\b`, the only optional-suffix group; `supercharge` uses the stem form `\bsupercharg(?:e|ed|ing|es)\b`. Both shapes stay as written.
- `unfortunately[\s,;]*i\s+do...` and `sorry[\s,;]*but` use `*` where their neighbours use `+`, so a zero-character separator matches. Preserve each quantifier exactly.
- `rise-of-ai` accepts either `AI` or `artificial intelligence`, and the long form tolerates `[\s,;]+` between its words while `AI` is a contiguous token. Preserve the nested alternation.
- `\s` matches newlines, so a phrase can span a line break and a reported match can cover more than one line. The line-and-column output must handle that.
- `suspiciousBackticks` requires 15 or more non-backtick, non-newline characters between two plain backticks; shorter inline code stays out.
- The source's `unusualSpaces` class deliberately excludes `U+00A0` (the source comment reads "excluding common &nbsp;"). It includes `U+2003`, `U+2007`, and `U+3000`, which the extension then leaves unreplaced while it substitutes the other space codepoints. Keep both the class and the split.

**Character names and normalization actions.** The extension names each character for its tooltip and marks the small spaces for visual substitution. These names and actions become the port's normalization guidance.

| Class | Codepoint | Name | Normalization action |
| --- | --- | --- | --- |
| `invisibleChars` | `U+200B` | Zero-width space | delete |
| `invisibleChars` | `U+200C` | Zero-width non-joiner | delete |
| `invisibleChars` | `U+200D` | Zero-width joiner | delete |
| `invisibleChars` | `U+FEFF` | Byte order mark | delete |
| `unusualSpaces` | `U+2000` | En quad | substitute a normal space |
| `unusualSpaces` | `U+2001` | Em quad | substitute a normal space |
| `unusualSpaces` | `U+2002` | En space | substitute a normal space |
| `unusualSpaces` | `U+2003` | Em space | keep |
| `unusualSpaces` | `U+2004` | Three-per-em space | substitute a normal space |
| `unusualSpaces` | `U+2005` | Four-per-em space | substitute a normal space |
| `unusualSpaces` | `U+2006` | Six-per-em space | substitute a normal space |
| `unusualSpaces` | `U+2007` | Figure space | keep |
| `unusualSpaces` | `U+2008` | Punctuation space | substitute a normal space |
| `unusualSpaces` | `U+2009` | Thin space | substitute a normal space |
| `unusualSpaces` | `U+200A` | Hair space | substitute a normal space |
| `unusualSpaces` | `U+202F` | Narrow no-break space | substitute a normal space |
| `unusualSpaces` | `U+205F` | Medium mathematical space | substitute a normal space |
| `unusualSpaces` | `U+3000` | Ideographic space | keep |
| `unusualQuotes` | `U+2018` | Left single quotation mark | `'` |
| `unusualQuotes` | `U+2019` | Right single quotation mark | `'` |
| `unusualQuotes` | `U+201C` | Left double quotation mark | `"` |
| `unusualQuotes` | `U+201D` | Right double quotation mark | `"` |
| `unusualDashes` | `U+2013` | En dash | `-` |
| `unusualDashes` | `U+2014` | Em dash | `-` |
| `unusualDashes` | `U+2053` | Swung dash | `-` |
| `unusualDashes` | `U+301C` | Wave dash | `-` |
| `specialDashes` | `U+2010` | Hyphen | `-` |
| `specialDashes` | `U+2011` | Non-breaking hyphen | `-` |
| `specialDashes` | `U+2012` | Figure dash | `-` |
| `specialDashes` | `U+2015` | Horizontal bar | `-` |
| `exoticBackticks` | `U+02CB` | Modifier letter grave accent | `` ` `` |
| `exoticBackticks` | `U+02C8` | Modifier letter vertical line | `` ` `` |
| `exoticBackticks` | `U+2035` | Reversed prime | `` ` `` |
| `exoticBackticks` | `U+2032` | Prime | `` ` `` |
| `exoticBackticks` | `U+2033` | Double prime | `` ` `` |
| `exoticBackticks` | `U+2034` | Triple prime | `` ` `` |
| `exoticPunctuation` | `U+2026` | Horizontal ellipsis | `...` |
| `exoticPunctuation` | `U+2022` | Bullet | `-` |
| `exoticPunctuation` | `U+2023` | Triangular bullet | `-` |
| `exoticPunctuation` | `U+2043` | Hyphen bullet | `-` |
| `exoticPunctuation` | `U+204C` | Black leftwards bullet | `-` |
| `exoticPunctuation` | `U+204D` | Black rightwards bullet | `-` |

The extension supplies these names for `invisibleChars`, `unusualSpaces`, `unusualQuotes`, `exoticBackticks`, and `exoticPunctuation`; it falls through to a generic label for `unusualDashes` and `specialDashes`, so those two classes take their names from the Unicode character names. The "keep" rows come from the extension's `shouldReplace = false` branch, which leaves wide spaces untouched. The action column is the port's normalization guidance rather than the extension's visual one: the extension renders an en space (`U+2002`) in place of the small spaces it marks, while the port normalizes them to the plain space an author would type. `suspiciousBackticks` has no codepoint: its normalization action is to strip the two plain backticks and keep the enclosed text.

**Scan mechanics worth adapting.** The extension scans text nodes, not a raw document, and these rules translate to a draft scanner:

- **Prose-only selection.** It rejects text inside `script`, `style`, `noscript`, `head`, `meta`, `link`, and `template`, rejects its own overlays, and skips text under three trimmed characters. The draft equivalents to reject are YAML frontmatter, fenced code blocks, inline code spans, URLs and autolinks, Markdown link targets, and HTML tags and attributes, so a code sample's backticks and dashes never reach the score.
- **Overlap resolution.** Matches are sorted by start offset and a match is kept only when its start is at or after the previous kept match's end; a later overlapping match is dropped. This keeps one overlay per span and prevents double counting when a phrase contains a vocabulary term.
- **Match caps.** The source caps 50 vocabulary matches and 20 formatting matches per text node for live-page performance. A draft is one bounded document, so the port drops the caps and keeps the zero-length-match guard (`if match[0] is empty: advance`).
- **Separate counters.** The source tracks a total overlay count plus `vocabCount` and `formatCount`. The port reports the same split, extended to a count per tell and per formatting class.
- **Stateless re-scan.** The source resets each `g` regex's `lastIndex` after every text node because a JS global regex carries state between calls. Python `re` patterns are stateless, so `finditer` needs no reset; record this so the missing reset is not read as an omission.
- **Fixture corpus.** `simple_test.html` is a ready-made fixture set: 149 paragraphs grouped into one paragraph per vocabulary group covering every variant, phrase sections, one section per formatting class, five heavy-slop paragraphs, and a negative-test section that asserts `&nbsp;` and short inline code stay unmatched. Convert it to plain text or Markdown for the eval fixtures and keep its positive/negative split. Its "repeated dashes" case also settles the README discrepancy: a run of em dashes reports as one finding per character, not as a run rule.

**Source behaviour that does not port.** The DOM layer has no meaning for a text draft and stays out: visibility and ancestor-chain checks, off-screen rejection, overlay wrappers and restoration, `MutationObserver` rescanning, the 1.5-second settle delay, the 5-second debounce, the 500-character and 100-character mutation thresholds, the 2000-node and 5-second scan budgets, URL-change polling, per-host toggles, the icon and popup counters, highlight navigation and per-tab index persistence. None of it changes which strings the detector matches.

**Source material deliberately not carried.** Three items are recorded so a later reader knows they were considered rather than missed:

- The watermark note's bookmarklet adds `U+00A0` and `U+180E` to its suspicious-space list and flags every non-ASCII character above `U+007F`. The extension's table does not, and this port follows the extension. Adding them would change the inventory and push ordinary typography into the report.
- The same note carries a homoglyph map from Cyrillic and Greek lookalikes to ASCII (`а`→`a`, `Α`→`A`, `В`→`B`, `С`→`C`, `ϲ`→`c`, `ԁ`→`d`, `е`→`e`, `Ε`→`E`, `Ғ`→`F`, `ɡ`→`g`, `Н`→`H`, `Ι`→`I`, `Ј`→`J`, `Κ`→`K`, `Μ`→`M`, `Ν`→`N`, `О`→`O`, `ο`→`o`, `Р`→`P`, `ϱ`→`p`, `ԛ`→`q`, `ѕ`→`s`, `Т`→`T`, `υ`→`u`, `Ѵ`→`V`, `ѡ`→`w`, `Χ`→`X`, `у`→`y`, `Ζ`→`Z`). It is a character-level tell, but it belongs to the watermarking research the task's out-of-scope section excludes. Record it as an extension point; do not add it to the shipped table.
- `README.md` claims the extension detects "3+ consecutive" em-dashes, "5+ spaces", and "mixed quote styles within the same text block". `content.js` implements none of those: `unusualDashes` matches one character at a time, `unusualSpaces` matches single characters, and no mixed-quote rule exists. Do not port the README claims; the regex table is the contract.

**Translation rules (JavaScript to Python).** The port keeps matching behaviour identical rather than approximating it:

- Compile every pattern with `re.IGNORECASE | re.ASCII`. The `re.ASCII` flag reproduces JS `/i`'s ASCII-only case folding, verified against `s` versus `ſ` and `k` versus the Kelvin sign; without it Python folds Unicode letters that JS leaves unmatched.
- Translate every `\b` to the pair `(?<![A-Za-z0-9_])` and `(?![A-Za-z0-9_])`, because Python's `\b` is Unicode-aware while JS's is ASCII-only. `re.ASCII` alone cannot be relied on here, because it would also force `\s` to ASCII and lose the Unicode whitespace the phrase patterns accept.
- Translate every `\s` to the explicit JS whitespace class `[ \t\n\v\f\r\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]`, because JS `\s` includes `U+FEFF` and Python's does not. Keep `\s` inside the dash class as this same set.
- Keep `\u002D` in the dash class escaped or position it so it cannot open a range; the source uses the escape for exactly that reason.
- Report offsets in Python code points, not JS UTF-16 code units. A draft containing an astral character shifts every later JS offset by one per surrogate pair; the port's line and column are what the author sees.
- Preserve each alternation's order and membership, each quantifier (`*` versus `+` versus `?`), each optional group, and each nested alternation exactly as transcribed above.

## Approach

Build three artefacts under `plugins/ai_editorial/skills/slop_catch/`.

### 1. The detector — `scripts/detect_slop.py`

Port both the term table and the format-pattern table into Python, preserving every pattern and its case-insensitive matching, and hold the ported table as a module-level data structure so the script stays one self-contained file. The script adheres to the `format_python` style guide. Transcribe each pattern from the **Source inventory — exact patterns** section rather than from memory or from `notes/slop_vocab.md`, and apply the section's **Translation rules** for `\b`, `\s`, case folding, the escaped dash, and code-point offsets. Give every pattern the stable slug id the inventory assigns it, so a report never depends on array position. The script is the skill's linter: it lists every tell with its location and replacement, scores the density, and states the reduction target the agent works against.

**Input.** Accept an optional path argument naming the draft file, and read the draft from standard input when no path is given. Scan prose only: skip YAML frontmatter, fenced code blocks, inline code spans, URLs and autolinks, Markdown link targets, and HTML tags and attributes, following the extension's prose-only text-node rule recorded in the inventory's **Scan mechanics**.

**Output.** Emit one JSON document on standard output holding a list of findings, a replacement list, and a score block. Each finding carries the tell identifier, the layer it came from (`vocabulary`, `phrase`, or `formatting`), its confidence tier, the 1-based line and column where it starts, the matched text, and the replacement guidance below. Resolve overlaps the way the source does: sort matches by start offset and keep a match only when it begins at or after the previous kept match's end, so a phrase that contains a vocabulary term reports once rather than twice. A match that spans a line break reports its start position and its full text. The replacement list groups findings by tell so an author sees each swap once with its occurrence count, and the score block carries the reduction target defined below so the agent has a concrete list to work down.

**Exit behaviour.** Exit 0 whenever the scan completed, with findings or without them, since a finding is a result rather than a failure. Reserve a non-zero exit for a usage or I/O error, and write that diagnosis to standard error.

**Gate mode.** Accept `--gate BAND` where `BAND` is `clean`, `watch`, or `heavy`, so the script can serve as a lint gate for an agent or a CI run. Without the flag the exit behaviour above stands. With it, exit 0 when the script's band is no worse than the named band and exit 1 when it is worse, writing the band, the density, and the reduction target to standard error; an unknown band name is a usage error. The gate reads the literal layer only, because the structural raise happens in the agent after the script returns, so the gate's pass is a floor rather than a final clearance.

**Replacement data, carried per pattern in the ported table.** Each of the 35 vocabulary entries carries one or more plain alternatives, or the marker `cut` where the term earns nothing in any context. Each of the 32 phrase entries carries a rewrite direction rather than a fixed swap, since a phrase template is replaced by saying the thing directly. Each formatting class carries a normalization action: delete for `invisibleChars`, and the plain-ASCII equivalent for the typographic classes, using the per-codepoint names and actions in the inventory's **Character names and normalization actions** table. Follow that table's split for `unusualSpaces`: the small and exotic spaces become a normal space, while `U+2003`, `U+2007`, and `U+3000` stay as they are. `suspiciousBackticks` loses its two plain backticks and keeps the enclosed text.

**Confidence tiers.** Every finding carries one of three tiers, assigned by how strongly the pattern implicates machine authorship in a human-written draft:

- **strong** — the `invisibleChars` class and the assistant self-reference phrases such as `as an AI language model` and `I do not have personal data`, which a person writing prose has no reason to produce.
- **moderate** — the slop vocabulary and the phrase templates, which a person writes occasionally and an AI writes constantly.
- **weak** — the typographic classes `unusualDashes`, `unusualQuotes`, `unusualSpaces`, `specialDashes`, `exoticBackticks`, `exoticPunctuation`, and `suspiciousBackticks`, which any word processor or typesetting pass also produces.

**The density score.** The score block turns the findings into one accumulation read: a lone tell never proves machine authorship, while each additional weighted tell raises the figure and can move the band. It answers "how much slop is here to reduce", not "did an AI write this", so a lightly hit draft stays low and a text loaded with tells stands out:

- Weight each finding by tier: **strong** counts 5, **moderate** counts 1, and **weak** counts 0, staying out of the score and reporting as advisory normalization work.
- Sum the weights and express the total per 1000 words, dividing by the draft's whitespace-separated word count with that count floored at 250, so a short draft cannot be pushed up by a single hit.
- Band the result: **clean** below 3, **watch** from 3 up to 8, and **heavy** above 8. On a 1000-word draft that puts two slop words in clean, five in watch, and a dozen in heavy, and it puts one strong finding on its own in watch.
- Emit the band, the density figure, the weighted total, and the word count alongside the findings.

**The reduction target.** The score block carries the target the agent reduces against, which is what makes the report a linter rather than a description. It gives the current band, the next band down (or `null` when the draft is clean), and the smallest integer number of weighted points whose removal puts the density below the next band's boundary and below the clean boundary, computed from the same floored word count and the band thresholds. It also carries a `top_targets` list ordered by contribution — occurrence count × tier weight — giving each tell's id, count, tier, contribution, and replacement guidance, with the weak formatting classes contributing zero and staying in the advisory group. The agent works down that list and re-runs the detector after each pass. When the draft is already clean, the target reports zero points and names the nearest boundary, so the agent knows how much headroom remains.

Treat these thresholds as the starting calibration this task sets. The eval fixtures below exercise them; where a fixture and a threshold disagree, adjust the threshold and record what moved and why.

### 2. The structural-tell ruleset — `references/structural_tells.md`

Write the tells the judgement layer covers. Each entry names the tell, states the shape it takes with one compact illustration that fixes its meaning, states why a reader registers it as a tell rather than as plain prose, and gives the rewrite direction that removes it — the reduction the agent applies. Cover these four groups.

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

Frontmatter `name: slop_catch`, a matching H1, and a pseudo-XML body carrying the role, the activation triggers, the check-and-report workflow, and the output contract. The workflow is a reduce loop: run the detector over the draft, read the reduction target, apply the replacements to the highest-contribution tells, and re-run the detector; repeat until the band is clean or the author stops, reporting the previous band, the new band, and the points removed on each pass. It also reads the ruleset against the same draft, resolves the negation-antithesis candidates, applies the band raise, and merges both layers into one report.

The output contract leads with the accumulation read and the reduction target — the band, the density figure, the word count it was measured over, the points to the next band, and the top contributors in contribution order — so the author reads what to reduce first. It names the band as a likelihood and reduction read, never an authorship verdict, and it never presents one tell as evidence the text is AI-written. The replacement list follows as the actionable body: one entry per tell, giving what to write instead, the occurrence count, and each occurrence located by a quoted phrase, with the list introduced as the reduction that lowers the density. Confirmed structural tells follow with their rewrite directions. Weak formatting findings close the report as grouped per-class counts framed as normalization work, with instances listed where the author asks. The report leaves the draft untouched.

**Out of scope:**

- Rewriting the flagged prose. [ai-editorial_language-humanizer-skill.md](archive/ai-editorial_language-humanizer-skill.md) and [ai-editorial_ghost-writer-skill.md](ai-editorial_ghost-writer-skill.md) produce and rewrite prose; this skill checks what they produced and returns replacements for them to apply. The handoff needs nothing on their side, since the skill takes delivered text as its input, so build this one to be invocable that way rather than reaching into either skill's workflow. Keep the structural-tell ruleset readable as a standalone reference, because `ghost_writer` references it directly when the file exists, to keep the two consistent.
- Wiring this check into either writing skill's own workflow, which changes that skill's contract and belongs to its task; this task delivers `slop_catch` so it can be invoked that way.
- Changing the source extension the term and pattern tables come from, which is read-only input to this port.
- Scoring whether a text was machine-generated, whether by statistical means such as perplexity and burstiness or by watermark detection. The density score rates how heavily a draft carries known tells, for an author to act on, rather than issuing an authorship verdict.

## Acceptance

- `plugins/ai_editorial/skills/slop_catch/` holds `SKILL.md`, `scripts/detect_slop.py`, and `references/structural_tells.md`.
- `detect_slop.py` carries the full ported inventory as a module-level table: 35 single-word vocabulary patterns, 32 multi-word phrase patterns, and all eight named formatting classes with the codepoint sets this task's Context records, each matching case-insensitively and each single-word entry carrying its morphological variants.
- Every ported pattern reproduces the source regex transcribed in **Source inventory — exact patterns**, with the inventory's **Translation rules** applied: `re.IGNORECASE | re.ASCII`, `\b` replaced by the ASCII-boundary lookarounds, `\s` replaced by the explicit JS whitespace class, the escaped dash kept out of range position, and offsets reported in code points. Each pattern carries the inventory's stable slug id rather than a positional index, and every quirk the inventory lists under **Source quirks to preserve, not repair** is present in the port: the duplicated ASCII apostrophe, the optional apostrophe, the `*` dash run, the missing `elevated`, `unprecedently`, the two optional-suffix shapes, the `*`-versus-`+` separator difference, the nested `AI` alternation, and the multi-line match behaviour.
- The scanner reads prose only, skipping YAML frontmatter, fenced code blocks, inline code spans, URLs and autolinks, Markdown link targets, and HTML tags and attributes per the inventory's **Scan mechanics**, so a code sample's backticks and dashes cannot reach the findings or the score.
- Findings resolve overlaps the way the source does — sorted by start offset, a match kept only when it begins at or after the previous kept match's end — and a match spanning a line break reports its start line and column with its full text.
- The replacement data for the formatting classes uses the inventory's **Character names and normalization actions** table, including the `unusualSpaces` split that substitutes the small and exotic spaces and leaves `U+2003`, `U+2007`, and `U+3000` untouched, and the `suspiciousBackticks` action that strips the two plain backticks and keeps the enclosed text.
- Every entry in that table carries its replacement data per the Approach's **Replacement data** rule — plain alternatives or `cut` for a vocabulary term, a rewrite direction for a phrase template, a normalization action for a formatting class — and every finding the script emits carries the replacement guidance for the pattern that fired.
- `detect_slop.py` reads a draft from a path argument and from standard input, emits the JSON findings, replacement list, and score block the Approach defines, exits 0 on a completed scan with or without findings unless `--gate BAND` is set, in which case it exits 1 when the literal-layer band is worse than `BAND` and 0 otherwise, and exits non-zero with a message on standard error for a usage or I/O error, including an unknown band name.
- The score block carries the band, the density figure, the weighted total, and the word count, computed by the Approach's **The density score** rule: tier weights of 5, 1, and 0; a per-1000-words denominator floored at 250 words; and the clean/watch/heavy bands at 3 and 8. It also carries the Approach's **The reduction target**: the current band, the next band down (or `null` when clean), the weighted points to the next band and to clean, and a `top_targets` list ordered by contribution with each tell's id, count, tier, contribution, and replacement guidance, with the clean case reporting zero points and the nearest boundary. Where an eval fixture and a threshold disagree, the shipped threshold and the record of what moved and why reflect that adjustment.
- `detect_slop.py` adheres to the `format_python` style guide.
- `references/structural_tells.md` carries an entry for every tell this task's `### 2. The structural-tell ruleset` section names, each stating the tell's shape with one compact illustration, why it reads as a tell rather than as plain prose, and the rewrite direction that removes it; it states the layer boundary including the negation-antithesis crossing and its confirm-or-dismiss step, and the band-raise rule for three or more distinct structural tells.
- `SKILL.md` is pseudo-XML in the XML-instruction-body shape and passes `ai_instruction_formatting`'s bundled `scripts/lint_pseudo_xml.py`.
- `SKILL.md` documents how it invokes the script and how the script's JSON becomes reader-facing feedback, and carries the output contract in the Approach's order — the accumulation read and reduction target first (band, density, word count, points to the next band, top contributors), then the replacement list with occurrence counts and quoted locations, then the confirmed structural tells, then the grouped weak counts — along with the band-raise-only rule and the guarantee that the draft is left untouched.
- `SKILL.md` carries the reduce loop: run the detector, read the reduction target, apply the replacements to the highest-contribution tells, and re-run until the band is clean or the author stops, reporting the previous band, the new band, and the points removed on each pass.
- `SKILL.md` and the report state the accumulation principle in the reader's terms: no single tell means the text is AI-written, more tells and stronger tells raise the likelihood reading, and every reported tell is a reduction target whose removal lowers the density. The band is named as a likelihood and reduction read, never an authorship verdict, and no single item is presented as proof of machine authorship.
- The skill `description:` states both trigger contexts — checking text a writing skill just delivered, and reviewing any draft for AI tells — and states the diagnose-score-and-propose axis that tells it apart from the two rewriting siblings in the plugin.
- Script unit tests exist under the repo's regression-harness layout and assert the ported inventory counts, one firing match per formatting class, replacement data present on every table entry, the JSON findings/replacement/score shape, tier assignment across all three tiers, the band boundaries including the 250-word denominator floor, the reduction-target computation (points to the next band and to clean, `top_targets` ordering, the clean case), the `--gate` exit paths, and both default exit paths. They also assert one firing sample for every vocabulary and phrase id, the translation parity cases (`U+00A0` and `U+FEFF` inside a `\s` position, a Cyrillic letter immediately before `delve` that the ASCII boundary accepts while Python's native `\b` would reject, `fastpaced` and `fast—paced`, `todays` and `today's`, `unprecedently`, and `elevate` without `elevated`), the prose-only skips, and the overlap resolution rule.
- Behaviour evals for this skill exist under the repo's regression-harness layout, covering three scenarios:
  - a **tell-dense fixture** carrying a counted set of tells — three slop-vocabulary terms, one phrase template, one zero-width character, and three named structural tells drawn from three different groups — asserting the report lands in the heavy band, names all eight, assigns each to the right layer and tier, gives a replacement for each, locates each by a quoted phrase from the fixture, names the reduction target with the top contributors in contribution order, and frames the heavy band as a high density to reduce rather than as proof that an AI wrote the text;
  - a **sparse-hit fixture** of otherwise plain human prose of at least 400 words carrying exactly two slop-vocabulary terms and nothing else, asserting the accumulation read lands in the clean band, that both terms still appear in the replacement list with their swaps, that the report frames them as available reductions rather than as evidence the text is AI-written, that it states the density is a likelihood reading that falls when those terms are replaced, and that the reduction target reports zero points to clean;
  - a **false-positive fixture** of human-written prose that uses em-dashes and curly quotes throughout and carries one genuine `not X, but Y` contrast where the opposition is real, asserting the accumulation read lands in the clean band, that the typographic hits report as grouped weak counts contributing nothing to the score, that the negation candidate is dismissed rather than reported as a tell, that the reduction target reports zero points, and that the report never calls the text AI-written.
- Each eval scenario is run over a fixed denominator of five passes, and the recorded per-scenario pass rate over that denominator is the deliverable. The bar is every assertion holding on all five passes; when a scenario misses it, the report carries the measured rate and the diverging assertions and hands the disposition to the user rather than re-running for a better draw.
- The skill is registered in `plugins/ai_editorial/README.md`, both plugin manifests, the root `README.md`, and both marketplace files.
- `./deployment/deployment.sh --global --dry-run` previews `slop_catch` without error.
