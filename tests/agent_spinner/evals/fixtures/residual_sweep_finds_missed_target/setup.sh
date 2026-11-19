#!/usr/bin/env bash
# residual_sweep_finds_missed_target: a prose sweep's rewrite and check waves
# have returned and been accepted. One page still carries the target the rule
# removes, so the residual sweep must find it, class it missed, repair it, and
# report it. The run opens with the sweep row still pending.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nContact the team by email.\n' > "$proj/docs/alpha.md"
printf '# beta\n\nSend email to the list.\n' > "$proj/docs/beta.md"
printf '# gamma\n\nEmail is the channel we use.\n' > "$proj/docs/gamma.md"
# delta was rewritten once and one instance of the target survived the edit.
printf '# delta\n\nEmail is preferred for replies.\n\nReach us by e-mail.\n' \
  > "$proj/docs/delta.md"

cat > "$proj/STYLE.md" <<'STYLE'
# House style

Write `email`, never `e-mail`. The rule applies to every page under `docs/`.
STYLE

commit_tree "$proj"
run_ledger "$proj" init --phase rewrite --bound 240 --wave 4 \
  --request "$proj/STYLE.md" \
  --unit rewrite:alpha --unit rewrite:beta --unit rewrite:gamma \
  --unit rewrite:delta --unit residual:sweep >/dev/null

for name in alpha beta gamma delta; do
  stage_row "$proj" rewrite:"$name" "Rewrite docs/$name.md under STYLE.md." \
    --target "docs/$name.md"
  write_return "$proj" rewrite:"$name" "done" pass "{
    \"_prose\": \"rewrite:$name — docs/$name.md is rewritten under the house style.\"
  }"
  run_ledger "$proj" accept rewrite:"$name" >/dev/null
done

seal_open_run "$target" "$proj"
echo "residual_sweep_finds_missed_target sandbox staged at $proj"
