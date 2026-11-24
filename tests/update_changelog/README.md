# update_changelog regression harness

Regression checks for the `update_changelog` skill. The harness is
committed and runs locally; it does not ship inside the plugin.

`script_tests/run.sh` verifies the deterministic parts of the incremental day
boundary: the skill text carries the last-recorded-day-inclusive instructions,
the documented date query reopens the newest recorded day, the bundled
`prepare_changelog_day.sh` sees later same-day commits, older days stay out of an
incremental run, and first-run date enumeration still covers the full history.

`s1` also pins the provenance invariant the skill owns: the `<source_of_truth>`
clause carries committed-history-only provenance, the working-tree exclusion, and
the never-hand-author-or-hand-edit prohibition, while `<run_scope>` stays scoped
to which days a run rebuilds and defers provenance to that clause.

`s7` covers the repo-agnostic verification step: `<verify>` sits inside
`<procedure>` after `<land_new_days>`, discovers the target repo's own lint
tooling in priority order, states an outcome for each of the three branches
(no tooling, clean, findings), scopes its verdict to `CHANGELOG.md`, keeps the
written file in place, and rules out network-fetched linters and default
rulesets that override the repo's config.
