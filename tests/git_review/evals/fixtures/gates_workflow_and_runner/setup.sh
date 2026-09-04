#!/usr/bin/env bash
# A repository with a test suite and a workflow definition that agree on the
# gate command, so the report can say which gates ran locally and which the
# workflow runs.

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
python3 - <<'PY'
import sys
sys.path.insert(0, "src")
from calc import add
assert add(2, 2) == 4
print("calc tests: 1 passed")
PY
SH
chmod +x tests/run_tests.sh
plant_makefile "$repo" "./tests/run_tests.sh"
plant_workflow "$repo" "make test"
git add -A
git commit --quiet -m "seed calculator, its test, and the gate wiring"
git push --quiet origin main

git checkout --quiet -b add-subtract
printf 'def add(a, b):\n    return a + b\n\n\ndef subtract(a, b):\n    return a - b\n' > src/calc.py
git add -A
git commit --quiet -m "src/calc.py -> add a subtract helper beside add"
git push --quiet -u origin add-subtract
printf '%s\n' "$repo"
