# tests/skill_doctor

Local Pattern A harness for the `skill_doctor` skill.

```text
tests/skill_doctor/
├── README.md
├── RUNBOOK.md
├── run_all.sh                   # bundled-script unit tests entrypoint
├── script_tests/run.sh          # resolve_scope + discovery_safety + SKILL contract
├── evals/
│   ├── README.md
│   ├── evals.json
│   ├── run.py                   # sonnet-pinned worker runner
│   ├── stage.sh                 # stage one fixture + checksum manifest
│   ├── grade.sh                 # deterministic grader
│   └── fixtures/<id>/setup.sh
└── workspace/                   # run output (gitignored)
```

## Surfaces

- **script_tests** gives deterministic coverage of:
  - `scripts/resolve_scope.py` layout discovery: the plugin layout, a
    repo-root `skills/` tree, a `<vendor-config-dir>/skills/` tree, a
    single-skill repo whose `SKILL.md` sits at the root, and a lowercase
    `skill.md` filename, each resolving under `--skill`, `--family` and
    `--all` and each reporting the layout it resolved. Alongside them:
    version-control, dependency and cache directories pruned from the
    walk; a selector under a harness configuration directory outside the
    root substituting the repository source and naming the swap; the
    nearest plugin manifest above a skill recorded as its `plugin_host`;
    and the ignore filter from both sides: a walk rooted at a repository
    toplevel drops ignored paths (this suite's own scratch fixtures are
    the case that matters), while a walk rooted inside some other
    repository keeps its own skills instead of inheriting that repo's
    ignore rules;
  - `scripts/resolve_scope.py` family resolution: hub-with-`<family>`
    union (including a non-prefix name from the block) and prefix-only
    (no `<family>` block);
  - the empty-walk failure, reported identically in all three scope
    modes as `no SKILL.md found under <root>` with the walked root
    substituted, and absent from both shipped surfaces in its superseded
    `no skills found under plugins/*/skills/` form;
  - the skill file the harness would load: a file that does not stat as a
    regular file blocks (a symlink resolving to a regular file does not,
    since the harness stats through the link), a file past the harness
    plugin-skill byte limit blocks with the limit named, and a directory
    holding more than one skill file blocks. The limit is probed out of
    the installed harness CLI's own `Skipping plugin skill ... byte
    limit` message; the probed value outranks the recorded fallback the
    script carries with provenance (the fallback keeps the check alive
    on hosts with no readable CLI, and a probe that disagrees with it
    reports the drift so the recording gets refreshed), and the
    resolution is unit-tested on both branches as a pure function; the
    ambiguity decision is unit-tested as a pure function of the directory
    listing because a case-insensitive filesystem cannot stage both
    spellings, with the end-to-end fixture running only where it can;
  - the info tier: an absent `version:` reports at info with a blocking
    count of zero, cites this repository's own version rule by name when
    checked here, and says the rule files state none when checked in a
    staged repo that has no such rule;
  - `scripts/discovery_safety.py` risky sibling-description outlier
    (typographic punctuation, risky punctuation, workflow leak) plus
    dual-audience gap cases;
  - `description_typographic_punctuation` and
    `sibling_typographic_punctuation_outlier` over the narrowed character
    set: one fixture per mark (em dash, en dash, both curly single quotes,
    both curly double quotes, ellipsis), an accented-letter pair proving
    the codepoint boundary at 127 is no longer the axis, a carrier-free set
    drawing no sibling finding, and a two-of-four set proving the sibling
    message reports the measured count and names its carriers rather than
    claiming the others are clean;
  - the two description-length findings, kept apart because they answer
    different questions: the absolute `description_listing_budget_length`
    warning fires per skill (single target with no siblings, a whole set
    over the threshold with no sibling outlier among them, and the
    recorded 1047/887/781/624/591 incident where the sibling comparison
    misses the entry the harness actually dropped), while
    `sibling_length_outlier` keeps firing on a spread set at unchanged
    code and severity. Fixtures come from `write_skill_desc_len`, which
    composes a parse-safe description of an exact length. Verified by
    mutation: neutering the threshold constant fails the three
    detection checks and nothing else;
  - the severity line, from all three sides: every blocking class the
    `SKILL.md` promises gets a fixture that proves it still blocks
    (absent frontmatter, unparseable frontmatter, an absent `name` or
    `description`, a parser-hostile character, a byte-identical sibling
    purpose, and the three skill-file states above), while typographic
    punctuation and the dual-audience judgements warn and a
    convention-owned fact reports at info. The name/directory mismatch is
    keyed to the harness behaviour recorded in `severity_records` rather
    than to a fixed expectation, so a later re-test that moves the record
    moves the assertion with it;
  - false-positive regression guards over six real shipped description
    shapes (em-dash lead, `Import ...` purpose verb, crisp short
    purpose sentence, `Covers a, b, c` tail, plural artefact nouns with
    no trigger clause, bare file type). Each shape carries two
    assertions: no blocking finding, and no dual-audience warning code.
    The second is the one that bites: `blocking_count == 0` alone
    cannot catch a reverted purpose or trigger heuristic, since the
    severity split means such a finding surfaces as a warning. Verified
    by mutation: reverting the purpose floor, the typographic-punctuation
    severity, the file-type path, or the plural nouns each fails a named
    check;
  - a self-check that `skill_doctor` clears its own gate;
  - static `SKILL.md` contract anchors from the task acceptance list.
- **evals** are staged prompts for family scope resolution,
  discovery-safety-first ordering, and the two behaviours that come from
  the checked repository rather than from this one: `registration_no_manifest`
  stages a repo-root `skills/` tree with no manifest, no marketplace and no
  naming or version convention, and grades that every registration surface
  reports as not applicable while the absent `version:` lands at info;
  `verification_repo_checks` stages a repo whose only gates are a mise
  `lint` task and a `.pre-commit-config.yaml`, and grades that the
  verification summary names those two commands and reaches for no entry
  point the repo never exposed. Run by `evals/run.py` (one sonnet-pinned
  `claude -p` worker per eval, deterministic `grade.sh` on top). See
  `evals/README.md`; `run_all.sh` drives only the script tests.
