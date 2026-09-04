#!/usr/bin/env bash
# The workflow definition and the documented task-runner target name different
# commands for the same gate, so a contributor who runs the documented command
# passes a check the merge then fails.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$HERE/../_common.sh"

target="${1:?target directory required}"
repo="$(init_remote_repo "$target" main)"

cd "$repo"
mkdir -p src tests
printf 'def add(a, b):\n    return a + b\n' > src/calc.py
cat > tests/run_tests.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "calc tests: 1 passed"
SH
chmod +x tests/run_tests.sh
# The documented entry point runs the fast subset.
plant_makefile "$repo" "./tests/run_tests.sh --fast"
# The workflow runs the strict superset, which the documented command omits.
plant_workflow "$repo" "./tests/run_tests.sh --strict --coverage-min 90"
git add -A
git commit --quiet -m "seed calculator with a fast local gate and a strict workflow gate"
git push --quiet origin main

git checkout --quiet -b add-divide
printf 'def add(a, b):\n    return a + b\n\n\ndef divide(a, b):\n    return a / b\n' > src/calc.py
git add -A
git commit --quiet -m "src/calc.py -> add a divide helper beside add"
git push --quiet -u origin add-divide
printf '%s\n' "$repo"
