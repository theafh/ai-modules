---
description: "Build language_humanizer in ai_editorial: a self-contained SKILL.md that writes or rewrites prose into clear, coherent first-read text, with a ledger pass proving no load-bearing meaning drops."
scope: "ai_editorial plugin"
created: 2026-07-30T20:42:30
updated: 2026-07-30T21:04:12
status: open
reported-by: Andreas Hoffmann
---

# Build the language_humanizer skill

## Goal

Add the `language_humanizer` skill to the `ai_editorial` plugin. It delivers human-facing text — a goal statement, spec, proposal, report, status update, README section, or any workplace document — that the intended audience understands on the first read: coherent from beginning to end, carried in language that is easy to take in, and clear and pleasant to read. It works along two paths, and states which one it is on:

- **Optimizing existing text**, where a draft already exists and the job is to make the whole of it more understandable, better ordered, and plainer while keeping what it says.
- **Writing new text**, where the input is supplied material — notes, bullets, findings, source facts, a brief — and the job is to produce the document that says all of it in that same clear and coherent form.

The guarantee across both paths is the skill's distinguishing commitment. Readability tools drift toward brevity and lose the qualifier, the modal strength, the threshold, or the causal joint that the sentence was carrying. This skill holds both ends at once: every load-bearing element of the input reaches the delivered text intact, while on the rewrite path that text never runs longer than the draft it replaces and a padded or repetitive draft comes out markedly shorter. It reaches that by taking its reduction out of form — filler, restatement, nominalized phrasing, hedging padding — rather than out of content, backed by an explicit fidelity mechanism of an inventory taken before writing and verified after, so the delivered text cannot quietly drop a condition, flatten a requirement into a suggestion, generalize a specific into a vague noun, or compress a connected argument into disconnected stubs.

## Context

- Depends on the plugin shell: build [ai-editorial_plugin-scaffold.md](ai-editorial_plugin-scaffold.md) first. This skill lands in `plugins/ai_editorial/skills/language_humanizer/`.
- **Single self-contained file.** The skill ships as one `SKILL.md` carrying everything it needs: no `scripts/`, no `references/` directory, no external URLs, and no outside standard cited as its authority. Should the body outgrow one coherent unit, split content into a follow-up task rather than adding a reference directory.
- **Rules carry the guidance without worked examples.** Write each rule so it stands on its own statement, and keep before/after pairs and sample passages out of the body. The demonstrating work belongs in the eval fixtures instead, where a scenario is run and graded rather than read.
- **Plugin domain is human-facing prose.** Word the `description:` so it stays distinct from the machine-facing `ai_instruction_*` skills: this skill's subject is text meant for people to read, not instructions written for a model to follow.
- **Router boundary against a plugin sibling.** [ai-editorial_ghost-writer-skill.md](ai-editorial_ghost-writer-skill.md) also writes and edits prose, so the two `description:` fields must make the split legible to a router. Split them by what the work optimizes rather than by whether text already exists: `ghost_writer` works toward a target genre's craft standard — what a good essay, case study, or social post is — while `language_humanizer` works toward comprehension and coherence for a named reader, on whatever material it is handed. This task owns the `language_humanizer` side of that wording.
- **Authoring authorities.** The skill's instruction text follows `ai_instruction_writing` for positive, action-oriented carriers and `ai_instruction_formatting` for the pseudo-XML body. This matters more than usual here: much of the skill's substance consists of preservation guarantees, which invite a wall of prohibitions. State each guarantee as what the delivered text carries through, and keep a negative only where it names a banned form the positive cannot imply.
- The standing repo rules own the generic skill-authoring checklist — frontmatter shape, directory/`name:`/H1 alignment, the two-audience `description:`, the lint gate, and plugin registration. This task supplies the `language_humanizer`-specific role, workflow, fidelity contract, and output contract.

## Approach

Author `plugins/ai_editorial/skills/language_humanizer/SKILL.md` with frontmatter `name: language_humanizer`, a matching H1, and a pseudo-XML body carrying the sections below.

### Role, activation, and modes

The skill acts as an editor and writer of reader-facing text. It activates when a user asks to make a document easier to understand, simplify wording, cut jargon, unpack a dense paragraph, spell out abbreviations, sharpen a goal or decision so readers can act on it, check whether a draft will land with a particular audience, or turn notes, bullets, or findings into a document a reader can follow.

Three modes, with a stated selection rule:

- **Review** returns findings and leaves the text untouched.
- **Rewrite** returns the edited version of an existing draft.
- **Write** returns a new document produced from supplied material.

Select rewrite when the user hands over a draft and asks for it improved; select write when the input is material to turn into a document rather than a draft to fix; select review when they ask what is wrong with a draft, whether it reads clearly, or want to keep authorship of the wording. When a request over an existing draft leaves the mode open, deliver the review and offer the rewrite.

Establish the intended reader and that reader's task before judging anything, drawing on the request and the document itself. When neither names a reader, state the assumed reader in the output so the author can correct it.

### The three passes

Structure the workflow as three ordered passes, each a named section in the body.

**Pass one — inventory what the delivered text is accountable for.** Before writing a word, list the load-bearing elements of the input: the existing draft on the rewrite path, the supplied material on the write path. Enumerate the item classes the ledger covers:

- the central claim, ask, decision, or finding, plus its current placement when the input already has one;
- every actor and owner named or implied, and who must do what;
- every number, date, deadline, quantity, unit, threshold, metric, version, and identifier;
- every product, system, and technical term that carries precision;
- requirement strength as written — must, should, may, will, might, committed, proposed — plus any hedge marking genuine uncertainty;
- conditions, exceptions, scope limits, and qualifiers such as "only when", "except", "up to", and "for X but not Y";
- the causal and logical joints carrying the argument — because, therefore, unless, so that, even though;
- risks, constraints, dependencies, commitments, and open questions;
- ordering wherever sequence is meaning, as in steps, precedence, and priority.

**Pass two — produce the text for first-read comprehension.** Apply these moves on both paths:

- lead with the main point, putting the ask, decision, or finding first;
- order the whole so each part follows from the one before it, grouping related material and letting the transitions carry the logic that joins the parts;
- carry one idea per sentence on a real verb, and turn an abstract noun back into the verb hiding inside it;
- name the actor in active voice wherever the actor matters;
- choose the common word where it is exactly as precise as the rare one, and keep the technical term where replacing it would cost precision, adding a short gloss on first use when the named reader may not carry that term;
- unpack a stacked clause chain — em-dash pileups, nested parentheticals — into separate sentences;
- spell out an abbreviation on first use, then use the short form;
- phrase positively wherever the positive says the same thing;
- give longer text descriptive headings, and set genuinely parallel points as a list or table;
- cut a clause that only restates what its own sentence already said.

**Pass three — verify the delivered text against the ledger.** Walk the ledger item by item against the text about to be returned and confirm each item is present with its strength and scope unchanged, restoring anything missing before returning it. Where first-read comprehension and fidelity pull apart, fidelity decides and the room comes from elsewhere in the text: split the overloaded sentence, then pay for that split by cutting filler, restatement, and nominalized phrasing rather than by letting the text grow.

### The fidelity contract

Give these rules their own body section; they are the skill's load-bearing content and each states what the delivered text keeps:

- Keep every qualifier, condition, and exception, splitting a sentence to accommodate them rather than trimming them to fit.
- Keep requirement strength exactly as written: a must stays a must, a should stays a should, and a hedge marking real uncertainty stays a hedge.
- Keep every specific specific: a named team stays named, a number keeps its value and unit, and a threshold keeps both sides of its comparison.
- Keep the reason beside the claim, so a sentence carrying both a what and a why still carries both afterward.
- Keep the argument's connective tissue by writing full sentences with their articles, verbs, and joining words. This rules out telegraphic or steno phrasing, and a cascade of ever-shorter bullets that splinters one argument into disconnected stubs.
- Keep a coherent paragraph as prose whenever its transitions are doing the arguing, and reserve the list form for genuinely parallel items.
- Keep the reader's open questions visible: where the source is genuinely ambiguous, name the competing readings and route the choice to the author, and where a term needs a definition the source never supplies, flag that term for the author. This rules out silently picking one reading or inventing a definition.
- Keep risks, commitments, and constraints at full force, changing tone only when the user asks for a different tone.
- Keep a rewrite within the length of the draft it replaces. This is the skill's one hard length rule, it governs the rewrite path, and it is measured over the whole delivered text rather than sentence by sentence, so a first-use gloss or a spelled-out abbreviation is paid for by cutting filler elsewhere.
- Keep no floor under that ceiling: a padded, repetitive, or over-hedged draft comes out markedly shorter, and every word of that reduction is taken from filler, restatement, nominalized phrasing, and hedging padding rather than from any ledger item.
- Keep a newly written document as long as its content needs and no longer, since the write path has no draft length to measure against: the ledger sets what must be said, and the same filler, restatement, and padding stay out from the first draft onward.

### Output contract

- **Review mode** returns one entry per finding, giving the location as a quoted phrase or named section, what blocks the first read, what the reader loses, and a concrete replacement. It closes with the open items — genuine ambiguities and terms needing a definition — phrased as questions for the author, plus the assumed reader when the source named none.
- **Rewrite mode** returns the rewritten text first, complete and ready to use, then a short preservation note naming the ledger items that were at risk, confirming they carried through, and pointing at any place where fidelity forced a longer sentence. The same open items and assumed-reader line follow.
- **Write mode** returns the new document first, complete and ready to use, then the same preservation note taken over the supplied material: which ledger items reached the page, and what the material left open for the author to supply.
- Every mode keeps meta-commentary out of the delivered text: the text states its content, and observations about the document live in the note.

**Out of scope:**

- Flagging AI-writing tells in a draft, owned by [ai-editorial_slop-catch-skill.md](ai-editorial_slop-catch-skill.md).
- Genre craft standards — what a good essay, case study, or social post looks like — owned by [ai-editorial_ghost-writer-skill.md](ai-editorial_ghost-writer-skill.md).
- Translating between natural languages, and restyling text toward a tone or brand voice.

## Acceptance

- `plugins/ai_editorial/skills/language_humanizer/SKILL.md` exists and is the skill directory's only file, with no `scripts/` or `references/` directory beside it and no external URL in its body.
- The body is pseudo-XML in the XML-instruction-body shape and passes `ai_instruction_formatting`'s bundled `scripts/lint_pseudo_xml.py`, with the directory name, frontmatter `name:`, and H1 in agreement.
- The body carries the three passes as distinct named sections — the pre-edit ledger, the production moves, and the verification of the delivered text against that ledger — with the ledger's item classes enumerated rather than described in the abstract.
- The body carries all three modes with the rule that selects between them, and pass one names both inputs a ledger can be built from: an existing draft and supplied material.
- Every rule in the fidelity-contract section leads with a positive carrier naming what the delivered text keeps, verified by applying `ai_instruction_writing`'s delete-the-negative self-check to each rule: a negative survives only where it names a banned form the positive cannot imply.
- The fidelity-contract section carries all three length rules as stated rules — the hard rewrite ceiling, its no-floor companion, and the write-path clause that sets length by content — each stated outright rather than left to be inferred.
- The body carries no before/after pair and no illustrative sample text: every rule stands on its own statement.
- Behaviour evals for this skill exist under the repo's regression-harness layout and are run, with graded results recorded, covering four scenarios:
  - a padded fidelity fixture whose load-bearing items are counted up front — two named actors, one deadline, two thresholds with units, one `must` and one `should`, one exception clause, and one causal joint — wrapped in filler and restatement, asserting that the rewrite reads plainly, comes out shorter in words than the fixture, and carries all nine items at unchanged strength and scope;
  - a compression-trap fixture consisting of one long paragraph whose argument lives in its transitions and one hedged uncertain claim, asserting that the rewrite runs no longer than the fixture, keeps the paragraph as connected prose rather than a bullet list of stubs, and keeps the hedge on the uncertain claim;
  - a write-path fixture supplying unordered material — loose notes carrying two named owners, one deadline, one threshold with a unit, and one `must` — asserting that the produced document states all five, opens with its main point, reads as connected prose, and introduces no filler or restatement;
  - a trigger scenario asserting that a bare "make this document easier to understand" request routes to `language_humanizer` rather than to `ghost_writer` or the machine-facing `ai_instruction_*` skills.
- `./deployment/deployment.sh --global --dry-run` previews `language_humanizer` without error.
