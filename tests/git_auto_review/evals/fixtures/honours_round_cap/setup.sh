#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_repo "$target"
seed_in_scope_change "$target"
(
  cd "$target/repo"
cat > "$target/repo/alpha.py" <<'EOF'
def alpha_value():
    return 1
EOF
cat > "$target/repo/beta.py" <<'EOF'
def beta_value():
    return 1
EOF
cat > "$target/repo/gamma.py" <<'EOF'
def gamma_value():
    return 1
EOF
cat > "$target/repo/delta.py" <<'EOF'
def delta_value():
    return 1
EOF
cat > "$target/repo/epsilon.py" <<'EOF'
def epsilon_value():
    return 1
EOF
  git add alpha.py beta.py gamma.py delta.py epsilon.py
  git commit --quiet -m "seed round targets"
  git update-ref refs/remotes/origin/main HEAD
)
cat > "$target/repo/report.py" <<'EOF'
def total(items):
    """Sum the item values."""
    return sum(items) + 10
EOF
seed_task_file "$target" tasks/demo_rounds.md

record_head "$target"
record_index "$target"

# The prompt names tasks/demo_rounds.md, so the sandbox carries that path:
# the worker resolves it in its own working directory instead of searching
# the host checkout for it.
stem="$(stem_for tasks/demo_rounds.md)"
preseed_gate "$target" "$stem" 1 "$HERE/gate-r1.txt"
preseed_gate "$target" "$stem" 2 "$HERE/gate-r2.txt"
preseed_gate "$target" "$stem" 3 "$HERE/gate-r3.txt"
preseed_gate "$target" "$stem" 4 "$HERE/gate-r4.txt"
preseed_gate "$target" "$stem" 5 "$HERE/gate-r5.txt"
