#!/usr/bin/env bash
# A repository with a documented task runner and no continuous-integration
# definition at all, so the gate list comes from the second source alone.

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
plant_makefile "$repo" "./tests/run_tests.sh"
plant_standing_instructions "$repo" 'Run `make test` before every commit. This project has no CI; the local target
is the only gate.'
git add -A
git commit --quiet -m "seed calculator and the only gate this project has"
git push --quiet origin main

git checkout --quiet -b add-multiply
printf 'def add(a, b):\n    return a + b\n\n\ndef multiply(a, b):\n    return a * b\n' > src/calc.py
git add -A
git commit --quiet -m "src/calc.py -> add a multiply helper beside add"
git push --quiet -u origin add-multiply
printf '%s\n' "$repo"
