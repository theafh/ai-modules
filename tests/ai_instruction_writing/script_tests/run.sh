#!/usr/bin/env bash
# Deterministic content-contract tests for ai_instruction_writing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/ai_dev/skills/ai_instruction_writing/SKILL.md"
RESULTS="$SCRIPT_DIR/../results/script_tests.log"

mkdir -p "$(dirname "$RESULTS")"

python3 - "$SKILL" <<'PY' 2>&1 | tee "$RESULTS"
from pathlib import Path
import re
import sys

skill_path = Path(sys.argv[1])
text = skill_path.read_text(encoding="utf-8")
errors = []


def require(condition, message):
    if not condition:
        errors.append(message)


def block(name):
    pattern = re.compile(rf"<{name}>(.*?)</{name}>", re.DOTALL)
    match = pattern.search(text)
    require(match is not None, f"missing <{name}> block")
    return match.group(1) if match else ""


require("name: ai_instruction_writing" in text, "frontmatter name is present")
require("# ai_instruction_writing" in text, "H1 matches the skill name")

self_check = block("self_check")
require(
    "<when_positive_is_complete_but_negative_is_load_bearing>" in self_check,
    "self_check has the load-bearing-negative branch",
)
if "<when_positive_is_complete>" in self_check and "<when_positive_is_complete_but_negative_is_load_bearing>" in self_check:
    require(
        self_check.index("<when_positive_is_complete>")
        < self_check.index("<when_positive_is_complete_but_negative_is_load_bearing>"),
        "load-bearing branch follows the redundant-inverse branch",
    )

load_branch = block("when_positive_is_complete_but_negative_is_load_bearing")
require(
    "positive can read complete" in load_branch
    and "listed exclusions still carry information" in load_branch,
    "load-bearing branch distinguishes itself from a merely complete positive",
)
require(
    "reader learns a banned form" in load_branch
    and "downstream tool acts on the exact named set" in load_branch,
    "load-bearing branch states the discriminator",
)

catch_all = block("catch_all_negative")
require("<invalid_redundant_negative>" in catch_all, "invalid redundant block exists")
require("<valid_load_bearing_negative>" in catch_all, "valid load-bearing block exists")
if "<invalid_redundant_negative>" in catch_all and "<valid_load_bearing_negative>" in catch_all:
    require(
        catch_all.index("</invalid_redundant_negative>")
        < catch_all.index("<valid_load_bearing_negative>"),
        "valid load-bearing block appears immediately after invalid redundant block",
    )

load_block = block("valid_load_bearing_negative")
require(
    load_block.count("<example>") == 2,
    "valid load-bearing block has exactly two worked examples",
)
require(
    "`:N` path suffix" in load_block
    and "bare `line N`" in load_block
    and "`around lines N-M` range" in load_block,
    "keep example names the soft-pointer banned shapes",
)
require(
    "mirror the linter's exact check" in load_block,
    "keep example names parity with the mechanical check",
)
require(
    "Use 4-space indentation; don't use tabs" in load_block
    and "positive already implies the excluded cases" in load_block,
    "cut example contrasts the redundant inverse",
)
require(
    "reader learns a banned form they could not derive from the positive" in load_block
    and "downstream tool acts on the exact named set" in load_block,
    "new guidance states the discriminator test",
)

applicability = block("applicability")
require(
    "In production rules, negative specifications are legitimate" in applicability,
    "applicability recognizes production-rule negative specifications",
)

for phrase in [
    "only as a catch-all for what positive guidance cannot enumerate",
    "earns its place only when listing every positive case is infeasible",
    "When the positive set is fully enumerable, the negative restates the inverse and adds nothing; cut it.",
    "When the positive set is finite and enumerable, no negative is needed.",
]:
    require(phrase not in text, f"old absolute enumerable-cut phrase removed: {phrase}")

def admits_load_bearing_negative(section):
    return (
        "add information the positive carrier cannot imply" in section
        or "adds information the positive carrier cannot imply" in section
    )


for name in ["objective", "core_rule"]:
    require(
        admits_load_bearing_negative(block(name)),
        f"{name} admits load-bearing negative supplements",
    )
require(
    admits_load_bearing_negative(block("principle")),
    "catch_all_negative principle admits load-bearing negative supplements",
)

if errors:
    print("FAIL")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print("PASS ai_instruction_writing content contract")
PY

exit "${PIPESTATUS[0]}"
