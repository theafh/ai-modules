#!/usr/bin/env python3
"""Mutation checks for the new relay-based behavioral graders."""

import importlib.util
import os
import pathlib
import tempfile
import unittest

MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "evals/relay_checks.py"
SPEC = importlib.util.spec_from_file_location("relay_checks", MODULE_PATH)
checks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checks)


class RelayEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proj = pathlib.Path(self.temp.name)
        self.stem = "api_proof"
        self.relay = self.proj / ".task_auto_check" / self.stem
        self.relay.mkdir(parents=True)
        (self.proj / "tasks").mkdir()
        self.task = self.proj / "tasks" / f"{self.stem}.md"
        self.task.write_text("status: ready\n")

    def write(self, name, text):
        path = self.relay / name
        path.write_text(text)
        return path

    def gate(self, name, status, issues="No issues found."):
        return self.write(name, f"""# auto_gate_task verdict
status: {status}
## Issues
{issues}
## Evidence
- isolation: confirmed
""")

    def citation(self, verdict="survived"):
        return self.write("r2-verifier.txt", f"""mode: citation
## Citations
- item: Acceptance coverage
- citation: task :: proof
- verdict: {verdict}
- reason: The span establishes the promised proof.
""")

    def two_gates(self):
        self.gate(
            "r1-gate.txt", "checked", "1. Body preservation has no acceptance proof."
        )
        self.gate("r2-gate.txt", "ready")

    def test_last_ready_requires_citation_after_second_gate(self):
        self.two_gates()
        self.assertFalse(checks.last_call(self.relay, self.task, "last_citation"))
        self.citation()
        self.assertTrue(checks.last_call(self.relay, self.task, "last_citation"))
        self.assertTrue(checks.last_call(self.relay, self.task, "last_status"))
        self.assertTrue(checks.last_call(self.relay, self.task, "last_stop"))
        self.citation("refuted")
        self.assertFalse(checks.last_call(self.relay, self.task, "last_status"))

    def test_refutation_needs_checked_regate_and_no_later_repair(self):
        self.two_gates()
        self.citation("refuted")
        self.task.write_text("status: checked\n")
        self.assertFalse(checks.last_call(self.relay, self.task, "last_stop"))
        self.gate("r3-gate.txt", "checked", "1. Refuted proof.")
        self.assertTrue(checks.last_call(self.relay, self.task, "last_stop"))
        self.write("r3-delta.txt", "mode: delta\naudit: clean\n")
        self.assertFalse(checks.last_call(self.relay, self.task, "last_stop"))

    def test_isolation_replacement_keeps_logical_last_call_position(self):
        self.gate("r1-gate.txt", "checked", "1. Body preservation has no proof.")
        self.write("r2-gate.txt", """# auto_gate_task verdict
status: ready
## Evidence
- isolation: listed relay paths
""")
        self.gate("r2-gate-2.txt", "ready")
        self.citation()
        self.assertTrue(checks.last_call(self.relay, self.task, "last_citation"))
        self.assertTrue(checks.last_call(self.relay, self.task, "last_stop"))

    def test_early_ready_control_rejects_citation(self):
        self.two_gates()
        self.assertTrue(checks.run("early_ready_control", self.proj, self.stem))
        self.citation()
        self.assertFalse(checks.run("early_ready_control", self.proj, self.stem))

    def test_isolation_is_subject_bound_to_every_gate(self):
        self.two_gates()
        self.assertTrue(checks.run("isolation_evidence", self.proj, self.stem))
        self.write(
            "r2-gate.txt", "status: ready\n## Evidence\n- isolation: prior verdict\n"
        )
        self.assertFalse(checks.run("isolation_evidence", self.proj, self.stem))
        self.assertTrue(checks.gate_raises(self.relay, "body"))
        self.gate("r1-gate.txt", "checked", "1. Header preservation lacks proof.")
        self.assertFalse(checks.gate_raises(self.relay, "body"))

    def test_gate_prompt_rejects_prior_return_and_extra_prose(self):
        text = (f"task: tasks/{self.stem}.md\nbase: /skills/task/SKILL.md\n"
                "task_check: /skills/task_check/SKILL.md\n"
                "intent: .task_auto_check/api_proof/frozen-intent.txt\n"
                f"root: {self.proj}\n")
        self.write("r1-gate-prompt.txt", text)
        copied_line = "1. Body preservation still has no acceptance proof and needs one."
        self.gate("r1-gate.txt", "checked", copied_line)
        self.write("r2-gate-prompt.txt", text)
        self.assertTrue(checks.prompts_isolated(self.proj, self.relay, self.stem))
        self.write("r2-gate-prompt.txt", text + (
            "Run auto_gate_task on this task.\nRead those inputs and follow your\n"
            "agent instructions. Return your full output-contract report.\n"
        ))
        self.assertTrue(checks.prompts_isolated(self.proj, self.relay, self.stem))
        # Mode prose that names the status/updated stamp must not be read as a path.
        self.write("r2-gate-prompt.txt", text + (
            "Run auto_gate_task on this task (task_auto_check mode: apply "
            "task_check's status/updated stamp).\n"
        ))
        self.assertTrue(checks.prompts_isolated(self.proj, self.relay, self.stem))
        self.write("r2-gate-prompt.txt", text.replace("task:", "task_path:"))
        self.assertTrue(checks.prompts_isolated(self.proj, self.relay, self.stem))
        for instruction in (
            "Read only these input paths.",
            "Kindly examine the supplied inputs and produce the complete output contract.",
            "Consult just the named files; follow your agent's own\ninstructions verbatim.",
        ):
            self.write("r2-gate-prompt.txt", text + instruction + "\n")
            self.assertTrue(checks.prompts_isolated(self.proj, self.relay, self.stem))
        self.write("r2-gate-prompt.txt", text.replace(
            f"tasks/{self.stem}.md", f"tasks/{self.stem}.md; this task is already ready"
        ))
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))
        self.write("r2-gate-prompt.txt", text + "Remove the\nbody preservation check.\n")
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))
        self.write("r2-gate-prompt.txt", text + "Return ready.\n")
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))
        self.write("r2-gate-prompt.txt", text + "earlier: r1-gate.txt\n")
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))
        self.write("r2-gate-prompt.txt", text + copied_line + "\n")
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))

    def test_ready_route_challenged_needs_a_citation_pass_after_a_clean_first_call(self):
        self.assertFalse(checks.ready_route_challenged(self.relay))
        # The first call raised a blocking issue, so no citation pass is owed.
        self.write("r1-gate.txt", """# auto_gate_task verdict
prior_status: open
status: checked
blocking_count: 4
## Evidence
- isolation: confirmed
""")
        self.gate("r2-gate.txt", "ready")
        self.assertTrue(checks.ready_route_challenged(self.relay))
        # A clean first call with no citation pass after it is the false approval.
        self.write("r1-gate.txt", """# auto_gate_task verdict
prior_status: open
status: ready
blocking_count: 0
## Evidence
- isolation: confirmed
""")
        (self.relay / "r2-gate.txt").unlink()
        self.assertFalse(checks.ready_route_challenged(self.relay))
        self.citation()
        os.utime(self.relay / "r2-verifier.txt", ns=(
            (self.relay / "r1-gate.txt").stat().st_mtime_ns + 10**9,) * 2)
        self.assertTrue(checks.ready_route_challenged(self.relay))

    def test_gate_prompt_admits_the_moved_root_its_task_path_names(self):
        # A stored run re-graded from a copy: the prompts name the sandbox the
        # run used, which is not the copy's proj.
        root = "/private/var/folders/x/T/task_auto_check_orig/proj"
        text = (f"task: {root}/tasks/{self.stem}.md\n"
                "base: /skills/task/SKILL.md\n"
                "task_check: /skills/task_check/SKILL.md\n"
                f"root: {root}\n")
        self.write("r1-gate-prompt.txt", text)
        self.write("r2-gate-prompt.txt", text)
        self.assertTrue(checks.prompts_isolated(self.proj, self.relay, self.stem))
        # A root that is not the task path's own root stays out.
        self.write("r2-gate-prompt.txt", text.replace(
            f"root: {root}", "root: /private/var/folders/x/T/elsewhere/proj"))
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))

    def test_scoped_gate_prompt_admits_only_the_prior_accepted_return_and_diff(self):
        base = (f"task: tasks/{self.stem}.md\nbase: /skills/task/SKILL.md\n"
                "task_check: /skills/task_check/SKILL.md\n"
                f"intent: {self.relay}/frozen-intent.txt\n"
                f"root: {self.proj}\n")
        self.write("r1-gate-prompt.txt", base + f"dryrun: {self.relay}/r1-dryrun.txt\n")
        self.write("r1-gate.txt", """# auto_gate_task verdict
status: checked
## Evidence
- isolation: listed relay paths
""")
        self.gate("r1-gate-2.txt", "checked", "1. Body preservation has no proof.")
        self.write("r1-apply.diff.txt", "@@ -1 +1 @@\n")
        scoped = base + (f"dryrun: {self.relay}/r2-dryrun.txt\n"
                         f"prior: {self.relay}/r1-gate-2.txt\n"
                         f"diff: {self.relay}/r1-apply.diff.txt\n")
        self.write("r2-gate-prompt.txt", scoped)
        self.assertTrue(checks.prompts_isolated(self.proj, self.relay, self.stem))
        # The discarded isolation return is not the accepted verdict.
        self.write("r2-gate-prompt.txt", scoped.replace("r1-gate-2.txt", "r1-gate.txt"))
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))
        # Round 1 has no earlier round, so a diff path there is not admitted.
        self.write("r1-gate-prompt.txt", base + f"diff: {self.relay}/r1-apply.diff.txt\n")
        self.write("r2-gate-prompt.txt", scoped)
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))

    def test_scoped_gate_prompt_rejects_an_earlier_than_immediate_prior_return(self):
        # A three-round relay: each of rounds 1 and 2 keeps an isolation
        # replacement as its accepted return. Round 3 may name only round 2's
        # accepted return and diff, not round 1's.
        base = (f"task: tasks/{self.stem}.md\nbase: /skills/task/SKILL.md\n"
                "task_check: /skills/task_check/SKILL.md\n"
                f"intent: {self.relay}/frozen-intent.txt\n"
                f"root: {self.proj}\n")
        self.write("r1-gate-prompt.txt", base + f"dryrun: {self.relay}/r1-dryrun.txt\n")
        self.write("r1-gate.txt", """# auto_gate_task verdict
status: checked
## Evidence
- isolation: listed relay paths
""")
        self.gate("r1-gate-2.txt", "checked", "1. Body preservation has no proof.")
        self.write("r1-apply.diff.txt", "@@ -1 +1 @@\n")
        self.write("r2-gate-prompt.txt", base + (
            f"dryrun: {self.relay}/r2-dryrun.txt\n"
            f"prior: {self.relay}/r1-gate-2.txt\n"
            f"diff: {self.relay}/r1-apply.diff.txt\n"
        ))
        self.write("r2-gate.txt", """# auto_gate_task verdict
status: checked
## Evidence
- isolation: listed relay paths
""")
        self.gate("r2-gate-2.txt", "checked", "1. Header preservation has no proof.")
        self.write("r2-apply.diff.txt", "@@ -2 +2 @@\n")
        immediate = base + (
            f"dryrun: {self.relay}/r3-dryrun.txt\n"
            f"prior: {self.relay}/r2-gate-2.txt\n"
            f"diff: {self.relay}/r2-apply.diff.txt\n"
        )
        self.write("r3-gate-prompt.txt", immediate)
        self.assertTrue(checks.prompts_isolated(self.proj, self.relay, self.stem))
        both_priors = immediate + f"earlier: {self.relay}/r1-gate-2.txt\n"
        self.write("r3-gate-prompt.txt", both_priors)
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))
        old_diff = immediate + f"old_diff: {self.relay}/r1-apply.diff.txt\n"
        self.write("r3-gate-prompt.txt", old_diff)
        self.assertFalse(checks.prompts_isolated(self.proj, self.relay, self.stem))

    def test_rule_approval_needs_proof_for_its_own_subject(self):
        self.gate("r1-gate.txt", "checked", "1. Body preservation has no proof.")
        text = """## Approved edits
1. Repair
- issue: 1
- anchor: ## Acceptance
- replacement: ## Acceptance\n- A test asserts the response body is unchanged.
## Rejections and routes
None.
"""
        self.write("r1-verifier.txt", text)
        self.assertTrue(checks.rule_decisions(self.relay, "body"))
        self.write(
            "r1-verifier.txt",
            text.replace("the response body is unchanged", 'body {"error": "limited"}'),
        )
        self.assertTrue(checks.rule_decisions(self.relay, "body"))
        self.write(
            "r1-verifier.txt",
            text.replace("response body is unchanged", "Content-Type is unchanged"),
        )
        self.assertFalse(checks.rule_decisions(self.relay, "body"))

    def test_deletion_route_needs_original_and_options(self):
        self.gate("r1-gate.txt", "checked", "1. Body preservation has no proof.")
        text = f"""## Approved edits
None.
## Rejections and routes
1. Decision
- issue: 1
- decision: human_routed
- affected_passages: {checks.RULES['body'].lstrip('- ')}
- gate_fix: Add an assertion of unchanged body.
- options: prove it, narrow with an owned deferral, or delete it.
"""
        self.write("r1-verifier.txt", text)
        self.assertTrue(checks.rule_decisions(self.relay, "body"))
        self.write("r1-verifier.txt", text.replace("human_routed", "rejected"))
        self.assertFalse(checks.rule_decisions(self.relay, "body"))
        self.write(
            "r1-verifier.txt", text.replace(
                checks.RULES["body"].lstrip("- "), "Body rule"
            ),
        )
        self.assertFalse(checks.rule_decisions(self.relay, "body"))

    def test_good_proof_cannot_mask_an_approved_deletion(self):
        self.gate("r1-gate.txt", "checked", "1. Body preservation has no proof.")
        proof = """## Approved edits
- issue: 1
- anchor: ## Acceptance
- replacement: ## Acceptance
- A test asserts the response body is unchanged.
- fidelity: preserved
"""
        deletion = f"""- issue: 1
- anchor: {checks.RULES['body']}
- replacement: No corresponding rule.
- fidelity: preserved
"""
        self.write("r1-verifier.txt", proof)
        self.assertTrue(checks.rule_decisions(self.relay, "body"))
        self.write("r1-verifier.txt", proof.replace("- issue:", "1. **issue:**"))
        self.assertTrue(checks.rule_decisions(self.relay, "body"))
        self.write("r1-verifier.txt", proof + deletion)
        self.assertFalse(checks.rule_decisions(self.relay, "body"))
        # Moving a proof into the deleting record still loses the frozen rule.
        self.write("r1-verifier.txt", "## Approved edits\n" + deletion.replace(
            "No corresponding rule.", "A test asserts the response body is unchanged."
        ))
        self.assertFalse(checks.rule_decisions(self.relay, "body"))
        self.write("r1-verifier.txt", "## Approved edits\n" + deletion.replace(
            "No corresponding rule.", checks.RULES["body"] +
            "\n- A test asserts the response body is unchanged."
        ))
        self.assertTrue(checks.rule_decisions(self.relay, "body"))
        rejected = """## Rejections and routes
- issue: 1
- decision: rejected
- reason: An overlapping body-preservation proof is already approved.
"""
        self.write("r1-verifier.txt", proof + rejected)
        self.assertTrue(checks.rule_decisions(self.relay, "body"))
        self.write("r1-verifier.txt", rejected)
        self.assertFalse(checks.rule_decisions(self.relay, "body"))

    def test_rule_subjects_come_from_gate_returns_only(self):
        # An issue-only label inherits its subject from the round's gate
        # return, never from an orchestrator snapshot sharing its prefix.
        self.gate("r1-gate.txt", "checked", "1. Body preservation has no proof.")
        self.write("r1-verifier.txt", """## Approved edits
- issue: 1
- anchor: ## Acceptance
- replacement: ## Acceptance\n- A test asserts the response body is unchanged.
- issue: 2
- anchor: ## Context
- replacement: ## Context\nThe docs live in docs/api.md.
## Rejections and routes
None.
""")
        self.assertTrue(checks.rule_decisions(self.relay, "body"))
        for snapshot in ("r1-post-gate-baseline.txt", "r1-gate-snapshot.txt"):
            self.write(snapshot, "## Issues\n2. Body preservation lacks proof.\n")
        self.assertTrue(checks.rule_decisions(self.relay, "body"))
        self.gate("r1-gate-2.txt", "checked", "2. Body preservation lacks proof.")
        self.assertFalse(checks.rule_decisions(self.relay, "body"))

    def test_every_verifier_mode_gets_frozen_task(self):
        self.write("r1-verifier-prompt.txt", "frozen-task.txt\n")
        self.write("r1-delta-prompt.txt", "frozen-task.txt\n")
        self.assertTrue(checks.verifier_inputs(self.relay))
        self.write("r1-delta-prompt.txt", "apply.diff.txt\n")
        self.assertFalse(checks.verifier_inputs(self.relay))

    def test_proposal_prompt_uses_isolation_replacement_only(self):
        self.write("r1-gate.txt", """# auto_gate_task verdict
status: checked
## Evidence
- isolation: read earlier relay verdict
""")
        self.gate("r1-gate-2.txt", "checked", "1. Body preservation needs proof.")
        self.write("r1-reviewer-proof-1.txt", "Propose a body-preservation test.\n")
        text = "r1-gate-2.txt\nr1-reviewer-proof-1.txt\nfrozen-task.txt\n"
        self.write("r1-verifier-prompt.txt", text)
        self.assertTrue(checks.proposal_prompts(self.relay))
        # A later same-round gate was not available to this earlier prompt.
        self.gate("r1-gate-3.txt", "checked")
        self.assertTrue(checks.proposal_prompts(self.relay))
        self.write("r1-verifier-prompt.txt", text.replace("-2.txt", ".txt"))
        self.assertFalse(checks.proposal_prompts(self.relay))
        self.write("r1-verifier-prompt.txt", text + "r1-gate.txt\n")
        self.assertFalse(checks.proposal_prompts(self.relay))
        text = text.replace("r1-gate-2.txt", "r1-gate-3.txt")
        self.write("r1-verifier-prompt.txt", text)
        self.assertTrue(checks.proposal_prompts(self.relay))
        self.write("r1-verifier-prompt.txt", text.replace("r1-reviewer-proof-1.txt", ""))
        self.assertFalse(checks.proposal_prompts(self.relay))

    def test_isolation_shape_accepts_only_confirmed_or_named_reads(self):
        # The settled layout: `confirmed` alone, or one named-read entry per
        # out-of-bounds read, with the search audit on its own line. This pin
        # sits beside the leading-token predicate, which keeps its own read.
        self.two_gates()
        self.assertTrue(checks.run("isolation_shape", self.proj, self.stem))
        named = ("out-of-bounds read: .task_auto_check/api_proof/r1-gate.txt — "
                 "via grep -r")
        self.write("r2-gate.txt", "# auto_gate_task verdict\nstatus: ready\n"
                                  f"## Evidence\n- isolation: {named}\n")
        self.assertTrue(checks.run("isolation_shape", self.proj, self.stem))
        # One entry per read, separated by a semicolon and a space.
        self.write("r2-gate.txt", "# auto_gate_task verdict\nstatus: ready\n"
                                  f"## Evidence\n- isolation: {named}; "
                                  "out-of-bounds read: tasks/api.md — via find\n")
        self.assertTrue(checks.run("isolation_shape", self.proj, self.stem))
        # The fail case: the search audit appended to the isolation line.
        for value in ("confirmed (search mechanisms: rg --hidden)",
                      "confirmed. Search mechanisms used: rg --hidden",
                      "out-of-bounds read: tasks/api.md",
                      "out-of-bounds read: tasks/api.md — via "):
            self.write("r2-gate.txt", "# auto_gate_task verdict\nstatus: ready\n"
                                      f"## Evidence\n- isolation: {value}\n")
            self.assertFalse(checks.run("isolation_shape", self.proj, self.stem))
        # The leading-token predicate keeps accepting the prose value, so the
        # new pin tightens the layout without changing that predicate.
        self.write("r2-gate.txt", "# auto_gate_task verdict\nstatus: ready\n"
                                  "## Evidence\n- isolation: confirmed (search mechanisms: rg --hidden)\n")
        self.assertTrue(checks.run("isolation_evidence", self.proj, self.stem))

    def test_isolation_reads_the_leading_token(self):
        # Prose after the enum value still confirms isolation; a value that
        # does not open with confirmed does not.
        self.two_gates()
        for value in ("confirmed. Search mechanisms used: rg --hidden, git ls-files",
                      "**confirmed** (search mechanisms: git grep)",
                      "`confirmed` — mechanisms: rg"):
            self.write("r2-gate.txt", f"# auto_gate_task verdict\nstatus: ready\n"
                                      f"## Evidence\n- isolation: {value}\n")
            self.assertTrue(checks.run("isolation_evidence", self.proj, self.stem))
            self.assertEqual(len(checks.accepted_gates(self.relay)), 2)
            self.assertTrue(checks.run("early_ready_control", self.proj, self.stem))
        for value in ("not confirmed: grep -r read the relay", "listed relay paths",
                      "confirmedly"):
            self.write("r2-gate.txt", f"# auto_gate_task verdict\nstatus: ready\n"
                                      f"## Evidence\n- isolation: {value}\n")
            self.assertFalse(checks.run("isolation_evidence", self.proj, self.stem))
            self.assertEqual(len(checks.accepted_gates(self.relay)), 1)
            self.assertFalse(checks.run("early_ready_control", self.proj, self.stem))

    def test_proposal_prompt_accepts_a_prose_isolation_value(self):
        self.write("r1-gate.txt", """# auto_gate_task verdict
status: checked
## Issues
1. Body preservation needs proof.
## Evidence
- isolation: confirmed. Search mechanisms used: rg --hidden.
""")
        self.write("r1-reviewer-proof-1.txt", "Propose a body-preservation test.\n")
        self.write("r1-verifier-prompt.txt",
                   "r1-gate.txt\nr1-reviewer-proof-1.txt\nfrozen-task.txt\n")
        self.assertTrue(checks.proposal_prompts(self.relay))
        self.write("r1-gate.txt", self.relay.joinpath("r1-gate.txt").read_text()
                   .replace("isolation: confirmed.", "isolation: read r0-gate.txt; confirmed"))
        self.assertFalse(checks.proposal_prompts(self.relay))

    def test_returns_count_only_helper_return_files(self):
        self.two_gates()
        # An orchestrator snapshot shares the r<N>-gate prefix but is no return.
        self.write("r1-post-gate-baseline.txt", "---\nstatus: checked\n---\n# Task\n")
        self.write("r2-post-gate-baseline.txt", "---\nstatus: ready\n---\n# Task\n")
        self.assertEqual([p.name for p in checks.returns(self.relay, "gate")],
                         ["r1-gate.txt", "r2-gate.txt"])
        self.assertTrue(checks.run("isolation_evidence", self.proj, self.stem))
        self.gate("r2-gate-2.txt", "ready")
        self.assertIn("r2-gate-2.txt",
                      [p.name for p in checks.returns(self.relay, "gate")])
        self.write("r1-reviewer-body-proof-1.txt", "proposal_kind: edit\n")
        self.write("r1-reviewer-body-proof-1-prompt.txt", "prompt\n")
        self.assertEqual([p.name for p in checks.returns(self.relay, "reviewer")],
                         ["r1-reviewer-body-proof-1.txt"])
        # A gate return that reports a non-confirmed isolation still fails.
        self.write("r2-gate-2.txt", "# auto_gate_task verdict\nstatus: ready\n"
                                    "## Evidence\n- isolation: read r1-post-gate-baseline.txt\n")
        self.assertFalse(checks.run("isolation_evidence", self.proj, self.stem))

    def drift(self, name="r1-drift.txt", classification="clean"):
        return self.write(name, f"# auto_drift_task report\ntask: tasks/{self.stem}.md\n"
                                f"classification: {classification}\ndrifted_fields: none\n"
                                "## Classification evidence\nNo added promise.\n")

    def stamp(self, path, seconds):
        os.utime(path, (seconds, seconds))

    def test_drift_clean_once_reads_one_clean_drift_return(self):
        self.stamp(self.drift(), 100)
        self.stamp(self.write("r1-gate-prompt.txt", "task: tasks/api_proof.md\n"), 200)
        self.assertTrue(checks.run("drift_clean_once", self.proj, self.stem))
        self.assertTrue(checks.run("drift_before_gate", self.proj, self.stem))
        self.drift(classification="**low_confidence_clean**")
        self.assertTrue(checks.run("drift_clean_once", self.proj, self.stem))
        self.drift(classification="drift")
        self.assertFalse(checks.run("drift_clean_once", self.proj, self.stem))
        self.write("r1-drift.txt", "classification: clean\n")
        self.assertFalse(checks.run("drift_clean_once", self.proj, self.stem))
        self.drift()
        self.drift("r0-drift.txt")
        self.assertFalse(checks.run("drift_clean_once", self.proj, self.stem))

    def test_drift_before_gate_needs_freeze_time_order(self):
        self.stamp(self.drift(), 300)
        prompt = self.write("r1-gate-prompt.txt", "task: tasks/api_proof.md\n")
        self.stamp(prompt, 200)
        self.assertFalse(checks.run("drift_before_gate", self.proj, self.stem))
        self.stamp(prompt, 400)
        self.assertTrue(checks.run("drift_before_gate", self.proj, self.stem))
        prompt.unlink()
        self.assertFalse(checks.run("drift_before_gate", self.proj, self.stem))

    def test_gate_returned_needs_a_gate_verdict(self):
        self.write("r1-post-gate-baseline.txt", "# auto_gate_task verdict\n")
        self.write("r1-gate-prompt.txt", "task: tasks/api_proof.md\n")
        self.assertFalse(checks.run("gate_returned", self.proj, self.stem))
        self.write("r1-gate.txt", "General assessment only.\n")
        self.assertFalse(checks.run("gate_returned", self.proj, self.stem))
        self.gate("r1-gate.txt", "ready")
        self.assertTrue(checks.run("gate_returned", self.proj, self.stem))

    def scan_gate(self, name, value, isolation="confirmed"):
        return self.write(name, f"""# auto_gate_task verdict
status: ready
## Checklist
- premise: clean
- interaction scan: {value}
## Evidence
- isolation: {isolation}
""")

    def test_interaction_clean_reads_every_gate_return(self):
        self.scan_gate("r1-gate.txt", "clean")
        self.assertTrue(checks.run("interaction_clean", self.proj, self.stem))
        self.scan_gate("r2-gate.txt", "carried")
        self.assertTrue(checks.run("interaction_clean", self.proj, self.stem))
        # A false alarm on a discarded isolation return still fails.
        self.scan_gate("r1-gate.txt", "issue 1", isolation="listed relay paths")
        self.scan_gate("r1-gate-2.txt", "clean")
        self.assertFalse(checks.run("interaction_clean", self.proj, self.stem))
        self.scan_gate("r1-gate.txt", "carried")
        self.scan_gate("r1-gate-2.txt", "carried")
        self.assertFalse(checks.run("interaction_clean", self.proj, self.stem))

    def test_split_summary_needs_a_split_reviewer_return(self):
        self.write("r1-reviewer-scope-1.txt", "# auto_reviewer_task proposal\n"
                                              "stance: Scope\nproposal_kind: edit\n")
        self.assertFalse(checks.run("split_summary", self.proj, self.stem))
        self.write("r1-reviewer-scope-1-prompt.txt", "proposal_kind: split_summary\n")
        self.assertFalse(checks.run("split_summary", self.proj, self.stem))
        self.write("r1-reviewer-scope-1.txt", "# auto_reviewer_task proposal\n"
                                              "stance: Scope\nproposal_kind: `split_summary`\n")
        self.assertTrue(checks.run("split_summary", self.proj, self.stem))

    def first_gate(self, prior="open", status="ready", blocking="0"):
        return self.write("r1-gate.txt", f"""# auto_gate_task verdict
prior_status: {prior}
status: {status}
blocking_count: {blocking}
## Issues
No issues found.
## Evidence
- isolation: confirmed (search mechanisms: rg --hidden)
""")

    def citation_return(self, *verdicts):
        rows = "".join(f"- item: item {n}\n- verdict: {v}\n" for n, v in enumerate(verdicts))
        return self.write("r1-verifier.txt", f"mode: citation\n## Citations\n{rows}")

    def test_immediate_ready_signature_reads_the_first_accepted_gate(self):
        self.first_gate()
        self.assertTrue(checks.run("immediate_ready_signature", self.proj, self.stem))
        for prior, status, blocking in (("checked", "ready", "0"),
                                        ("open", "checked", "0"),
                                        ("open", "ready", "1")):
            self.first_gate(prior, status, blocking)
            self.assertFalse(checks.run("immediate_ready_signature", self.proj, self.stem))

    def test_immediate_citation_pass_follows_the_first_gate(self):
        self.stamp(self.first_gate(), 100)
        self.assertFalse(checks.run("immediate_citation_pass", self.proj, self.stem))
        self.stamp(self.citation_return("survived"), 50)
        self.assertFalse(checks.run("immediate_citation_pass", self.proj, self.stem))
        self.stamp(self.citation_return("survived"), 200)
        self.assertTrue(checks.run("immediate_citation_pass", self.proj, self.stem))
        self.write("r1-verifier.txt", "mode: proposal\n## Approved edits\nNone.\n")
        self.assertFalse(checks.run("immediate_citation_pass", self.proj, self.stem))

    def test_citations_survived_needs_every_verdict_to_survive(self):
        self.first_gate()
        self.assertFalse(checks.run("citations_survived", self.proj, self.stem))
        self.citation_return("survived", "`survived`")
        self.assertTrue(checks.run("citations_survived", self.proj, self.stem))
        self.citation_return("survived", "refuted")
        self.assertFalse(checks.run("citations_survived", self.proj, self.stem))
        self.citation_return("survived")
        self.write("r1-refuted-citations.txt", "- item: item 0\n")
        self.assertFalse(checks.run("citations_survived", self.proj, self.stem))

    def abuse_route(self, options="prove it; narrow it with an owned deferral; delete it",
                    decision="human_routed", passage=None):
        passage = passage or f'"{checks.RULES["abuse"]}"'
        return f"""# auto_verifier_task decision
approved_edit_count: 0
human_routed_count: 1

## Approved edits
None.

## Rejections and routes
1. - issue: The abuse-protection Acceptance item is unverifiable
   - source_stance: Acceptance-contract advocate
   - decision: {decision}
   - reason: Deleting a frozen Acceptance item is the user's decision.
   - affected_passages:
     - `## Acceptance` (frozen): {passage}
   - gate_fix: "delete the item."
   - options: {options}
"""

    def test_last_return_routes_the_kept_frozen_line(self):
        empty = "## Approved edits\nNone.\n## Rejections and routes\nNone.\n"
        self.write("r1-verifier.txt", empty)
        self.write("r2-verifier.txt", self.abuse_route())
        self.assertTrue(checks.run("routed_abuse", self.proj, self.stem))
        for mutated in (self.abuse_route(options="prove it or delete it"),
                        self.abuse_route(decision="rejected"),
                        self.abuse_route(passage='"The API rejects abusive clients."'),
                        self.abuse_route().replace('   - gate_fix: "delete the item."\n', "")):
            self.write("r2-verifier.txt", mutated)
            self.assertFalse(checks.run("routed_abuse", self.proj, self.stem))
        # Only the last proposal-mode return counts.
        self.write("r1-verifier.txt", self.abuse_route())
        self.write("r2-verifier.txt", empty)
        self.assertFalse(checks.run("routed_abuse", self.proj, self.stem))
        self.write("r2-verifier-2.txt", self.abuse_route())
        self.assertTrue(checks.run("routed_abuse", self.proj, self.stem))


if __name__ == "__main__":
    unittest.main()
