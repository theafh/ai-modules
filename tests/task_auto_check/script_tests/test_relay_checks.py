#!/usr/bin/env python3
"""Mutation checks for the new relay-based behavioral graders."""

import importlib.util
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


if __name__ == "__main__":
    unittest.main()
