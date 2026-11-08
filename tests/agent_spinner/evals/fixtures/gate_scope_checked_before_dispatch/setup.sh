#!/usr/bin/env bash
# gate_scope_checked_before_dispatch: the lint gate lists files with find and
# prunes no run directory. Before the first item brief the gate line records
# whether the gate reported the planted known positive and says it dropped
# run-directory findings. `init` refuses the auto-fix gate.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"

cat > "$proj/lint.sh" <<'SH'
#!/usr/bin/env bash
# Lists every file under the working root, run directory included.
status=0
while IFS= read -r f; do
  if grep -q 'CONTROL_DEFECT' "$f" 2>/dev/null; then
    echo "$f: control defect"
    status=1
  fi
done < <(find . -type f)
exit "$status"
SH
chmod +x "$proj/lint.sh"

# Prove the refusal before the worker opens the real run.
mkdir -p "$proj/.agent_spinner"
if run_ledger "$proj" init --auto-fix-gate lint \
  --gate "lint=./lint.sh" 2> "$proj/.agent_spinner/auto_fix_refused.txt"; then
  echo "gate_scope fixture: init unexpectedly accepted an auto-fix gate" >&2
  exit 1
fi

seal "$target" "$proj"
echo "gate_scope_checked_before_dispatch sandbox staged at $proj"
