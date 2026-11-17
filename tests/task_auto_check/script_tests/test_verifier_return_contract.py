#!/usr/bin/env python3
"""Pass and fail cases for the shared proposal-mode verifier return contract.

The contract helper moved out of `evals/grade.sh` into
`tests/lib/verifier_return_contract.sh` so it loads without the grader's own
arguments or case block. These cases prove it sources cleanly, accepts the
stated proposal-mode layout including a fenced value and the approval
`reason:`, and still fails a return that breaks the layout.
"""

import pathlib
import subprocess
import tempfile
import unittest

HELPER = pathlib.Path(__file__).resolve().parents[2] / "lib" / "verifier_return_contract.sh"

PROPOSAL = """# auto_verifier_task decision
task: tasks/api_proof.md
approved_edit_count: 1
human_routed_count: 1

## Approved edits
1. id: e1
- issue: 1
- source_stance: Acceptance proof advocate
- base_rule_cited: Acceptance coverage
- anchor:
  ```text
  ## Acceptance
  ```
- replacement:
  ````text
  ## Acceptance
  - A test asserts `Retry-After` equals the window.
  ````
- edit: anchored replacement
- fidelity: preserved
- reason: Adds the proof the gate named in tasks/api_proof.md.

## Rejections and routes
1. issue: 2
- source_stance: Scope
- decision: human_routed
- reason: The proposal widens the task beyond its frozen Goal.
"""


class VerifierReturnContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.relay = pathlib.Path(self.temp.name) / ".task_auto_check" / "api_proof"
        self.relay.mkdir(parents=True)
        self.write("r1-reviewer-proof-1.txt",
                   "# auto_reviewer_task proposal\nstance: Acceptance proof advocate\n")
        self.write("r1-reviewer-scope-1.txt",
                   "# auto_reviewer_task proposal\nstance: Scope\n")
        self.return_path = self.write("r1-verifier.txt", PROPOSAL)

    def write(self, name, text):
        path = self.relay / name
        path.write_text(text)
        return path

    def bash(self, script):
        return subprocess.run(
            ["bash", "-c", script, "_", str(HELPER), str(self.relay)],
            capture_output=True,
        ).returncode

    def contract_holds(self):
        return self.bash('. "$1"; verifier_returns_keep_contract "$2"') == 0

    def test_helper_sources_without_the_grader_arguments(self):
        self.assertEqual(self.bash('. "$1"; declare -F verifier_returns_keep_contract'), 0)

    def test_stated_layout_with_fenced_value_and_reason_passes(self):
        self.assertTrue(self.contract_holds())

    def test_missing_approval_reason_fails(self):
        text = PROPOSAL.replace(
            "- reason: Adds the proof the gate named in tasks/api_proof.md.\n", ""
        )
        self.return_path.write_text(text)
        self.assertFalse(self.contract_holds())

    def test_item_opening_must_carry_its_first_field(self):
        self.return_path.write_text(
            PROPOSAL.replace("1. id: e1", "1. Approach rewrite\n- id: e1")
        )
        self.assertFalse(self.contract_holds())

    def test_trailing_prose_after_the_last_item_fails(self):
        self.return_path.write_text(
            PROPOSAL + "\nThe decision rested on the files above.\n"
        )
        self.assertFalse(self.contract_holds())


if __name__ == "__main__":
    unittest.main()
