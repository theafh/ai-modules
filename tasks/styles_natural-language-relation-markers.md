---
description: Rewrite the natural-language style so a rewrite keeps each source relation's marker, even when it moves or splits the claim, and record a baseline and refined five-pass Claude measurement.
scope: styles
created: 2026-10-09T23:16:07
updated: 2026-10-09T23:16:07
status: open
reported-by: Andreas Hoffmann
---

# Make the natural-language style keep relation markers through rewrites and measure it against its eval bar

## Goal

Rewrite the relation rules in `styles/natural-language.md` so that a worker restyling a text keeps each contrast's "but" or "yet" and each cause's "because" or "since", including when the rewrite moves the claim to another paragraph or section or splits its sentence. The `connected_rewrite` scenario of the `natural_language` harness then meets the bar the style shipped against, with every assertion holding on all five passes of both scenarios. When it still misses, a recorded five-pass measurement names the rate and the diverging assertions, and the user decides what follows. For the user, rewrites under the style stop turning a source's "X, but Y" into "X and still Y", into a cause, or into a counterfactual.

## Context

- **The shipped rule and how it fails.** `<keep_the_relations>` in `styles/natural-language.md` already tells a worker to keep a source's "but" or "yet" in the sentence that carries the contrast, and the contrast `<validation>` in `<output_contract>` repeats the check. Workers still drop the marker from the contrast sentence that `tests/natural_language/evals/fixtures/connected_rewrite/setup.sh` stages: "The new build can pass every automated check in the gate, but a quiet failure in one client library still reaches users who never opted into the trial." Three Claude runs on 9 October failed `contrast_kept` on it:
  - `run-20261009-222235` wrote "and still fail quietly in one client library, and that failure reaches users".
  - `run-20261009-143216` wrote the same "and still" form and let the failure only "would then reach" those users.
  - `run-20261009-142349` turned the contrast into a cause: "because those checks miss failures in the client library".

  The sentence beginning "Swap but for and still" in `<keep_the_relations>` names exactly the "and still" and counterfactual shapes these workers wrote, as exceptions for a source that used them.
- **Rules that pull a claim away from its marker.** Two of the three failures moved the claim out of the opening section into the later section on why passing checks is not enough. `<report_once>` tells a restyling to leave each section's conclusion in that section rather than previewing it earlier, and `<one_theme>` gives each paragraph one theme, so both invite that move, while no rule says what a moved claim keeps. `<one_idea>` already lets a split sentence carry its relation into the next one with "But", "So" or "That is why". `plugins/ai_editorial/skills/language_humanizer/SKILL.md` states the missing rule for its own rewrites in the passage beginning "When a move relocates a claim or splits its sentence": every joint attached to the claim travels with it into the same sentence or the next one, opened by the joining word that names the link, and a contrast keeps both sides in one sentence or two adjacent ones.
- **Measured state.** [The archived style task](archive/styles_natural-language-connected-prose.md) shipped the current wording on 6 October, defined the bar, and handed any miss to the user. `## Protocol runs` in `tests/natural_language/results/measurement-protocol.md` records its last refined run, `run-20261005-192444`, at 2/5 on `connected_rewrite`, with `contrast_kept` at 4/5 and `two_reasons_kept` at 3/5, and `chat_brevity` at 5/5. Six single-pass Claude runs on 9 October passed `connected_rewrite` once: `contrast_kept` failed in three of them, and `two_reasons_kept`, `paragraphs_open_with_point`, `arithmetic_opens_with_conclusion` and `term_referent` failed in one or two each. The per-run `run-*.{json,md}` files are gitignored, so that tracked note is the record.
- **The grader is deliberately strict.** The `contrast_kept` rubric in `tests/natural_language/evals/judge.py` accepts the two sides joined in one sentence or across a clear opposition by "but" or "yet", and it fails a bare "still" and a counterfactual "would". The grader-edit table in `measurement-protocol.md` records that strictness as a restored strength, so the failures above are true positives.
- **How a run measures the style.** The runner micro-deploys the checkout's `styles/natural-language.md` into each pass's sandbox project, so the next run measures an edit without a deploy. A `--style` file replaces that copy through `stage_style` in `tests/natural_language/evals/run.py`, which lets a baseline measure the shipped wording while the checkout holds the rewrite. `## The recorded measurement` in `tests/natural_language/RUNBOOK.md` gives both commands with `--vendor claude`, while the commands under `## Protocol` in `measurement-protocol.md` predate that flag. A five-pass run of both scenarios is ten Claude worker passes plus their judge calls, and the standing repo rules on Claude runs govern them.

## Approach

1. **Measure the baseline first.** Before editing the style, save the shipped wording (`git show HEAD:styles/natural-language.md`) to a scratch file and run the baseline under `## Protocol`, so the baseline and the refined run share the Claude Code version, the harness route and the graders.
2. **Rewrite the relation rules in place.** Rewrite `<keep_the_relations>` and the contrast `<validation>` in `<output_contract>` so that the style says the following:
   - A claim that the rewrite moves to another paragraph or section, or splits, keeps its contrast and cause markers, in the same sentence or in the next one opened by the marker. This brings the substance of the `language_humanizer` relocation rule into the style and agrees with `<one_idea>`.
   - The contrast instruction states the action to take: write the source's "but" or "yet", and keep a source's own "and still" as written. This replaces the sentence beginning "Swap but for and still", because the style's own `<policy>` asks for the positive form and that sentence names the shapes the failing workers wrote.
   - Every other rule keeps its meaning, each rule stays stated once, and the new wording stays general, carrying none of the fixture's phrases.
3. **Measure the rewrite.** Run the refined measurement under `## Protocol` with `tests/natural_language/evals/` left as it is, so the measured change is the style's. Add a baseline row and a refined row to `## Protocol runs`, each with its `run-<ts>` id, both scenarios' rates over five passes, and the diverging assertions. A refined run below the bar ends the pass: record it, report its rates and diverging assertions, and hand the disposition to the user, who may accept the rate or ask for another wording. Each wording keeps its one measured run.
4. **Bring the protocol commands in line.** Rewrite the `run.py` commands under `## Protocol` in `measurement-protocol.md` in place so each names `--vendor claude`, as the RUNBOOK's commands do.

**Out of scope:**

- Editing `plugins/ai_editorial/skills/language_humanizer/SKILL.md`, which already states the relocation rule this task brings into the style.

## Acceptance

- `git diff styles/natural-language.md` rewrites `<keep_the_relations>` and the contrast `<validation>` in place. `<keep_the_relations>` states that a moved or split claim keeps its contrast and cause markers and states the contrast marker as the action to take, `rg -n 'Swap but for and still' styles/natural-language.md` prints nothing, no second statement of the contrast rule appears elsewhere in the file, and `git diff -U0 styles/natural-language.md | rg '^\+' | rg -i 'automated check|client library|quiet failure|opted into|shadow share'` prints nothing.
- `## Protocol runs` in `tests/natural_language/results/measurement-protocol.md` holds a baseline row for the shipped wording and a refined row for the rewrite, each naming its `run-<ts>` id, its `connected_rewrite` and `chat_brevity` rates over five passes, and its diverging assertions. The rows come from `python3 tests/natural_language/evals/run.py --vendor claude --run-label baseline --style <copy of the shipped style>` and `python3 tests/natural_language/evals/run.py --vendor claude --run-label refined`, and this task's diff leaves `tests/natural_language/evals/` unchanged.
- The refined row meets the bar, with every assertion holding on all five passes of both scenarios. When it misses, the row records the measured rates and diverging assertions, the report hands the disposition to the user, and the table holds one refined row per wording.
- `rg -n 'evals/run\.py' tests/natural_language/results/measurement-protocol.md | rg -v -- '--vendor claude'` prints nothing.
