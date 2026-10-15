# Eval cache key granularity comparison

Captured before/after the content_key formula change for Acceptance 8 of
`tasks/tests_eval-cache-key-granularity.md`.

Vendor: default Cursor (`agent -p` / model `auto`) per TESTING.md.

## baseline

### baseline: git_commit

Run `run-20261014-202238`.

```text
  eval-1: PASS
  eval-2: PASS
  eval-3: PASS
  eval-4: PASS
  eval-5: PASS
  eval-6: PASS
  eval-7: PASS
  eval-8: PASS
  eval-9: PASS
```

### baseline: skill_doctor

Run `run-20261014-203007`.

```text
  scope_hub_family: PASS
  scope_prefix_only: PASS
  discovery_risky_sibling: PASS
  scope_single_skill_clean: PASS
  scope_whole_repo: PASS
  scope_unresolvable_selector: PASS
  registration_no_manifest: PASS
  verification_repo_checks: PASS
```

### baseline: guardrail_audit

Run `run-20261014-203722`.

```text
  presence_gate: PASS
  doc_vs_doc: PASS
  doc_vs_code: PASS
  direction_target: FAIL
  missing_testing: PASS
  nature_mismatch: PASS
```

### baseline: task_create

Run `run-20261014-204328`.

```text
  reconcile-recorded: PASS
  labeled-why-open: FAIL
  guardrail-bound-surface: PASS
```

### baseline: task_fix

Run `run-20261014-204812-67652`.

```text
  regroup_live_skip_archived: PASS
  regroup_state_and_edit_site: PASS
  surfaced_acceptance_contract: PASS
  regroup_same_paragraph: PASS
```

### baseline: agent_spinner

Run `run-20261014-205337`.

```text
  probe_definitions_no_spawn: PASS
  inline_floor: FAIL
  phase_plan_announcement: PASS
  governed_stop: PASS
  diagnostic_inline: PASS
  residual_selector: PASS
  containment_one_path: FAIL
  depth_one_level: FAIL
  charter_conflict: PASS
  failure_taxonomy: PASS
  unreturned_bound: FAIL
  roster_partial_stop: PASS
  uncited_clean_reroute: PASS
  planted_defect: FAIL
  clean_corpus: FAIL
  duplicate_finding_union: PASS
  confirmation_provenance: PASS
  one_remediation_round: PASS
  payload_cap: PASS
  judgement_surfaced: FAIL
  report_rederivation: PASS
```

### baseline: task

Run `run-20261014-213607`.

```text
  create: PASS
  check: PASS
  standing_rules_create: PASS
  standing_rules_check: PASS
  standing_rules_check_control: PASS
  explain: FAIL
  select: PASS
  implement: PASS
  implement_dep_gate: PASS
  select_inbound_dep: PASS
  select_dep_regression: PASS
  audit_gaps: PASS
  audit_clean: PASS
  audit_reopen: PASS
  finish: PASS
  fix: PASS
  query: PASS
  update: PASS
  update_contract: PASS
  triage: PASS
  lossless_split: PASS
  lossless_single: PASS
  check_boundary_contradiction: PASS
  check_boundary_clean: PASS
  implement_boundary_cross: PASS
  implement_boundary_agree: PASS
  create_scope_trim: PASS
  create_regroup_owner_account: PASS
  auto_check_boundary: PASS
  check_exclusion_requirement: PASS
  check_exclusion_requirement_control: PASS
  check_exclusion_waiver: PASS
  check_exclusion_waiver_control: PASS
  check_commit_proof_surface: PASS
  check_commit_proof_surface_control: PASS
  check_count_stable: PASS
  finish_arch_extended: PASS
  finish_arch_declined: FAIL
  finish_arch_absent: PASS
  fix_coherence: PASS
  fix_coherence_reconcile_escalated: PASS
  fix_coherence_reconcile_inline_staleness: PASS
  fix_coherence_selector_scope: PASS
  fix_coherence_selector_explicit_list: PASS
  fix_coherence_selector_whole_tree: PASS
```

### baseline: git_review

Run `run-20261014-224209`.

```text
  eval-1: PASS
  eval-2: PASS
  eval-3: PASS
  eval-4: PASS
  eval-5: PASS
  eval-6: PASS
  eval-7: PASS
  eval-8: PASS
  eval-9: PASS
  eval-10: PASS
  eval-11: PASS
  eval-12: PASS
  eval-13: PASS
  eval-14: PASS
  eval-15: PASS
  eval-16: PASS
  eval-17: PASS
  eval-18: PASS
  eval-19: PASS
  eval-20: PASS
  eval-21: PASS
  eval-22: PASS
  eval-23: PASS
  eval-24: PASS
  eval-25: PASS
  eval-26: PASS
  eval-27: PASS
  eval-28: PASS
  eval-29: PASS
  eval-30: PASS
  eval-31: PASS
  eval-32: PASS
  eval-33: PASS
  eval-34: PASS
  eval-35: PASS
  eval-36: PASS
  eval-37: PASS
  eval-38: PASS
  eval-39: PASS
  eval-40: PASS
  eval-41: PASS
  eval-42: PASS
  eval-43: PASS
  eval-44: FAIL
  eval-45: PASS
  eval-46: PASS
  eval-47: PASS
  eval-48: PASS
```

### baseline: task_auto_check

Run `run-20261015-002453-25414`.

```text
  mechanical_lint_ready: PASS
  mechanical_lint_link: PASS
  mechanical_lint_frontmatter: PASS
  mechanical_lint_markdown: PASS
  mechanical_lint_oversized_surface: PASS
  already_ready: PASS
  intent_drift_human_route: FAIL
  drift_gate_narrowing_clean: PASS
  drift_gate_refinement_clean: PASS
  drift_gate_broadening_drift: FAIL
  drift_gate_committed_broadening_clean: PASS
  repair_to_ready: FAIL
  relay_by_path: FAIL
  stray_hunk_reverted: PASS
  scope_split_stuck: FAIL
  fidelity_rejects_drift: FAIL
  no_verified_fix: PASS
  cap_override: PASS
  gate_failure_user_stop: PASS
  drift_failure_user_stop: PASS
  verifier_failure_user_stop: PASS
  guard_rebaseline_after_gate: FAIL
  interaction_scan_surfaces: PASS
  immediate_ready_citations_survive: PASS
  immediate_ready_citations_overturn: PASS
  interaction_scan_no_false_alarm: PASS
  regroup_via_reviewer: PASS
  regroup_immediate_ready: PASS
  regroup_same_paragraph_ready: PASS
  committed_rule_deletion_routed: PASS
  last_call_ready_refuted: PASS
  regate_isolated: FAIL
```

These are the verdicts recorded in `run-20261015-002453-25414`.
`baseline-task_auto_check.log` interleaves that run's output with the
concurrent `run-20261015-000646-60928`, which drew different verdicts for
several ids on the same prompts, skills, and grader.

## after

Each suite's after verdicts come from its first full run after the key-formula
change, read from the results recorded in that run directory: each eval's
grading summary, worker exit code, and both read checks. Every eval in those
runs spawned a fresh worker; none was a cached replay. Each diverging id was
then re-run once, forced, between 05:23 and 05:45 on 2026-10-15, in the run
directory named under its suite. The later forced draws at 06:22 to 06:42 and
the cache replays at 09:54 to 10:03 fall outside this protocol, and no verdict
below rests on them. Run directories sit under each harness's gitignored
`workspace/`.

### after: git_commit

After run `run-20261015-011443`; bounded re-run `run-20261015-052347`.

```text
  eval-1: PASS
  eval-2: PASS
  eval-3: PASS
  eval-4: PASS
  eval-5: FAIL
  eval-6: PASS
  eval-7: PASS
  eval-8: PASS
  eval-9: PASS
```

Transient misses (the bounded re-run matched the baseline):

- `eval-5`: after `FAIL`, re-run `PASS` (baseline `PASS`); treated as
  matching.

Comparison: match after one bounded re-run.

### after: skill_doctor

After run `run-20261015-012030`.

```text
  scope_hub_family: PASS
  scope_prefix_only: PASS
  discovery_risky_sibling: PASS
  scope_single_skill_clean: PASS
  scope_whole_repo: PASS
  scope_unresolvable_selector: PASS
  registration_no_manifest: PASS
  verification_repo_checks: PASS
```

Comparison: match.

### after: guardrail_audit

After run `run-20261015-012611`; bounded re-run `run-20261015-052559`.

```text
  presence_gate: PASS
  doc_vs_doc: PASS
  doc_vs_code: PASS
  direction_target: PASS
  missing_testing: PASS
  nature_mismatch: PASS
```

Remaining divergences after the bounded re-run:

- `(direction_target, FAIL, PASS)`: the re-run also returned `PASS`. LLM
  nondeterminism on an unchanged prompt/grader; the cache-key formula change
  does not explain the flip, because the key decides only whether a worker
  runs and this draw ran a fresh worker.

### after: task_create

After run `run-20261015-013153`; bounded re-run `run-20261015-052640`.

```text
  reconcile-recorded: FAIL
  labeled-why-open: PASS
  guardrail-bound-surface: FAIL
```

Transient misses (the bounded re-run matched the baseline):

- `reconcile-recorded`: after `FAIL`, re-run `PASS` (baseline `PASS`);
  treated as matching.
- `labeled-why-open`: after `PASS`, re-run `FAIL` (baseline `FAIL`); treated
  as matching.
- `guardrail-bound-surface`: after `FAIL`, re-run `PASS` (baseline `PASS`);
  treated as matching.

Comparison: match after one bounded re-run.

### after: task_fix

After run `run-20261015-013453-12736`.

```text
  regroup_live_skip_archived: PASS
  regroup_state_and_edit_site: PASS
  surfaced_acceptance_contract: PASS
  regroup_same_paragraph: PASS
```

Comparison: match.

### after: agent_spinner

After run `run-20261015-013833`; bounded re-run `run-20261015-053138`.

```text
  probe_definitions_no_spawn: PASS
  inline_floor: FAIL
  phase_plan_announcement: PASS
  governed_stop: PASS
  diagnostic_inline: PASS
  residual_selector: PASS
  containment_one_path: FAIL
  depth_one_level: PASS
  charter_conflict: PASS
  failure_taxonomy: PASS
  unreturned_bound: PASS
  roster_partial_stop: PASS
  uncited_clean_reroute: PASS
  planted_defect: FAIL
  clean_corpus: FAIL
  duplicate_finding_union: PASS
  confirmation_provenance: PASS
  one_remediation_round: PASS
  payload_cap: PASS
  judgement_surfaced: PASS
  report_rederivation: PASS
```

Remaining divergences after the bounded re-run (each re-run also returned
`PASS`):

- `(depth_one_level, FAIL, PASS)`: LLM nondeterminism on an unchanged
  prompt/grader; the cache-key formula change does not explain the flip,
  because the key decides only whether a worker runs and this draw ran a fresh
  worker.
- `(unreturned_bound, FAIL, PASS)`: LLM nondeterminism on an unchanged
  prompt/grader; the cache-key formula change does not explain the flip, for
  the same reason.
- `(judgement_surfaced, FAIL, PASS)`: LLM nondeterminism on an unchanged
  prompt/grader; the cache-key formula change does not explain the flip, for
  the same reason.

### after: task

After run `run-20261015-021117`; bounded re-run `run-20261015-053953`.

```text
  create: PASS
  check: PASS
  standing_rules_create: PASS
  standing_rules_check: PASS
  standing_rules_check_control: PASS
  explain: PASS
  select: PASS
  implement: PASS
  implement_dep_gate: PASS
  select_inbound_dep: PASS
  select_dep_regression: PASS
  audit_gaps: PASS
  audit_clean: PASS
  audit_reopen: PASS
  finish: PASS
  fix: PASS
  query: PASS
  update: PASS
  update_contract: PASS
  triage: PASS
  lossless_split: PASS
  lossless_single: PASS
  check_boundary_contradiction: PASS
  check_boundary_clean: PASS
  implement_boundary_cross: PASS
  implement_boundary_agree: PASS
  create_scope_trim: PASS
  create_regroup_owner_account: PASS
  auto_check_boundary: PASS
  check_exclusion_requirement: PASS
  check_exclusion_requirement_control: PASS
  check_exclusion_waiver: PASS
  check_exclusion_waiver_control: PASS
  check_commit_proof_surface: PASS
  check_commit_proof_surface_control: PASS
  check_count_stable: PASS
  finish_arch_extended: PASS
  finish_arch_declined: PASS
  finish_arch_absent: PASS
  fix_coherence: FAIL
  fix_coherence_reconcile_escalated: PASS
  fix_coherence_reconcile_inline_staleness: PASS
  fix_coherence_selector_scope: PASS
  fix_coherence_selector_explicit_list: PASS
  fix_coherence_selector_whole_tree: PASS
```

Remaining divergences after the bounded re-run:

- `(explain, FAIL, PASS)`: the baseline draw's worker exited with rc 1 before
  completing, and the re-run returned `PASS`. LLM-worker nondeterminism on an
  unchanged prompt/grader; the cache-key formula change does not explain the
  flip, because the key decides only whether a worker runs and this draw ran a
  fresh worker.
- `(finish_arch_declined, FAIL, PASS)`: the re-run returned `PASS`. LLM
  nondeterminism on an unchanged prompt/grader; the cache-key formula change
  does not explain the flip, for the same reason.
- `(fix_coherence, PASS, FAIL)`: the re-run returned `FAIL` on the same
  check, the double-owned `severity_label` edit as an alter finding. LLM
  nondeterminism on an unchanged prompt/grader; the cache-key formula change
  does not explain the flip, for the same reason.

### after: git_review

After run `run-20261015-031335`; bounded re-run `run-20261015-054533`.

```text
  eval-1: PASS
  eval-2: PASS
  eval-3: PASS
  eval-4: PASS
  eval-5: PASS
  eval-6: PASS
  eval-7: PASS
  eval-8: PASS
  eval-9: PASS
  eval-10: PASS
  eval-11: PASS
  eval-12: PASS
  eval-13: PASS
  eval-14: PASS
  eval-15: PASS
  eval-16: PASS
  eval-17: PASS
  eval-18: PASS
  eval-19: PASS
  eval-20: PASS
  eval-21: PASS
  eval-22: PASS
  eval-23: PASS
  eval-24: PASS
  eval-25: PASS
  eval-26: FAIL
  eval-27: PASS
  eval-28: PASS
  eval-29: PASS
  eval-30: PASS
  eval-31: PASS
  eval-32: PASS
  eval-33: PASS
  eval-34: PASS
  eval-35: PASS
  eval-36: PASS
  eval-37: PASS
  eval-38: PASS
  eval-39: PASS
  eval-40: PASS
  eval-41: PASS
  eval-42: PASS
  eval-43: PASS
  eval-44: FAIL
  eval-45: PASS
  eval-46: PASS
  eval-47: PASS
  eval-48: PASS
```

Transient misses (the bounded re-run matched the baseline):

- `eval-26`: after `FAIL` (every grader check passed; the artefact read check
  failed on an out-of-set read of the skill's `SKILL.md`), re-run `PASS`
  (baseline `PASS`); treated as matching.

Comparison: match after one bounded re-run.

After this run, the `dependencies` maps of evals 30 and 41 gained
`reviewer_side_edits` under Approach **Stage selection.** That edit moves every
git_review key, because `evals.json` is a whole harness path, but it changes
only `dependencies` maps, which neither the worker prompt nor the grader reads
(`stage.sh` takes only the fixture and prompt fields, and `grade.sh` reads no
`evals.json`), so it cannot reach any git_review verdict, and under
`TESTING.md` `## Re-run Economy` the after run `run-20261015-031335` with its
bounded re-run `run-20261015-054533` stays the evidence.

### after: task_auto_check

A key-identity proof stands in for a fresh after run, as Acceptance 8 allows.
On the current tree, each eval's content key computed with the pre-change
helper (`git show HEAD:tests/lib/eval_cache.py`) equals the key computed with
the working-tree helper for all 32 ids, from each eval's real runner inputs:
its source roots, the harness directory, model `auto`, the eval id, and the
staged prompt. The new formula reduces to the old one here because no eval
carries a `dependencies` map and the splitter cannot determine this
`grade.sh`'s `case "$eval_id"` structure, so the whole file joins every key.

The recorded after run `run-20261015-064637-91978` therefore replays cached
draws from the two baseline-launched runs rather than measuring the change. A
forced
re-run on identical inputs would only resample LLM noise, which `TESTING.md`
`## Re-run Economy` calls waste, so the proof stands in for the after run and
the baseline verdicts above stay the suite's record.

## Key stability after the recorded runs

After the runs above, the grader arm-split learned POSIX `(id)` arms and glob
or `$` arms, and only the harness's own top-level `grade.sh` is split.
Recomputing every content key of every Pattern A suite before and after that
fix (176 keys across 9 suites) moved no key, so the fix cannot reach any
recorded verdict, and under `TESTING.md` `## Re-run Economy` the after
verdicts above stay evidence. The later fix that reads a `#` as a comment only
at a word start outside quotes and `${...}` also moved none of those 176 keys,
so the recorded verdicts stay evidence after it too, and the task_auto_check
key-identity proof still holds under the final helper. The fail-closed
whitelist splitter that replaced that parser, together with hashing
`grade.sh` and declared `SKILL.md` files from raw bytes, also moved none of
the 176 keys, so the recorded verdicts and the key-identity proof stay
evidence after it as well. Making bash's own parse the arbiter of every split,
with the id-binding preconditions, moved none of the 176 keys either, under
bash 5.3 and under macOS `/bin/bash` 3.2, so the recorded verdicts and the
key-identity proof stay evidence after that change too, and the same holds
after the split also required that no positional change runs before the
binding outside a `-`-literal guard and that every sourced file resolves and
stays free of rebinding: none of the 176 keys moved under either bash. The
checks that read command words after quote removal and reject constructed
names, aliases, POSIX mode, and re-entry spellings moved none of them either,
under either bash. The same round's rewrite of `tests/git_review/evals/README.md`
moved all 48 git_review keys, because that README is a harness path, but
neither `stage.sh`, `grade.sh`, nor the worker prompt reads it, so it cannot
reach any git_review verdict, and under `TESTING.md` `## Re-run Economy` the
after run `run-20261015-031335` with its bounded re-run `run-20261015-054533`
stays the evidence.

## Acc8 summary

Call-site tree check: every Pattern A `evals/run.py` that calls
`content_key()` forwards the optional declaration, proven by
`every content_key caller forwards dependencies` in
`tests/lib/test_eval_cache.py`.

Suite comparison:

- `git_commit`: match after one bounded re-run (`eval-5` transient).
- `skill_doctor`: match.
- `guardrail_audit`: one residual divergence with a nondeterminism disposition.
- `task_create`: match after one bounded re-run (all three ids transient).
- `task_fix`: match.
- `agent_spinner`: three residual divergences with nondeterminism
  dispositions.
- `task`: three residual divergences with nondeterminism dispositions.
- `git_review`: match after one bounded re-run (`eval-26` transient).
- `task_auto_check`: key-identity proof in place of a fresh after run.
