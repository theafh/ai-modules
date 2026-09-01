#!/usr/bin/env bash
# Shared helpers for git_commit eval fixtures.
#
# Each fixture sources this file, then calls `init_sandbox "$1"` to get
# a fresh git repo at the target dir with one seed commit.

set -euo pipefail

init_sandbox() {
    local target="$1"
    if [[ -z "$target" ]]; then
        echo "init_sandbox: target dir is required" >&2
        return 2
    fi
    rm -rf "$target"
    mkdir -p "$target"
    (
        cd "$target"
        git init --quiet --initial-branch=main
        git config user.email "evals@example.com"
        git config user.name "Evals"
        printf 'seed\n' > seed.txt
        git add seed.txt
        git commit --quiet -m "seed"
    )
}

# Stage a sandbox scaffold that plants one agent-directed pre-commit
# obligation, then commit it so the only dirty path left is whatever
# change the calling fixture makes afterwards.
#
#   plant_obligation_scaffold <target> <gate_name> <rule_paragraph>
#
# Writes and commits:
#   AGENTS.md            the standing rule, addressed to the agent
#   tools/<gate>.sh      observable stand-in for the real gate: it records
#                        that it ran by writing its epoch second to
#                        .eval/markers/<gate>
#   .gitignore           keeps .eval/ out of git status and out of the commit
#   docs/handbook.md     the documentation surface a fixture can edit
#   src/app.py           the Python surface a fixture can edit
#
# The marker is the whole observation: grade.sh reads its presence to tell
# whether the pre-flight relevance test ran or skipped the obligation, and
# its epoch second to tell that a run happened before the commit landed.
plant_obligation_scaffold() {
    local target="$1" gate="$2" rule="$3"
    if [[ -z "$target" || -z "$gate" || -z "$rule" ]]; then
        echo "plant_obligation_scaffold: target, gate name and rule are required" >&2
        return 2
    fi
    (
        cd "$target"
        mkdir -p tools docs src

        printf '.eval/\n' > .gitignore

        cat > AGENTS.md <<AGENTS_EOF
# Sandbox project rules

This repository holds a small Python package under \`src/\` and its handbook
under \`docs/\`.

## Before every commit

$rule
AGENTS_EOF

        cat > "tools/$gate.sh" <<GATE_EOF
#!/usr/bin/env bash
# Observable stand-in for the real gate: it records that it ran.
set -euo pipefail
root="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "\$root/.eval/markers"
date +%s > "\$root/.eval/markers/$gate"
echo "$gate: ok"
GATE_EOF
        chmod +x "tools/$gate.sh"

        printf '# Handbook\n\nHow this project is used.\n' > docs/handbook.md
        printf 'def main():\n    return "ok"\n' > src/app.py

        git add .gitignore AGENTS.md "tools/$gate.sh" docs/handbook.md src/app.py
        git commit --quiet -m "scaffold: standing pre-commit rule and its gate"
    )
}
