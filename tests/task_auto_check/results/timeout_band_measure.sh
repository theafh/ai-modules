#!/usr/bin/env bash
# Sequential repair-class timing band measurement for tests_eval-runner-timeout-crash.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
OUT_DIR="$ROOT/tests/task_auto_check/results"
LOG="$OUT_DIR/timeout_band_measure.log"
CSV="$OUT_DIR/timeout_band_measure.csv"
EVALS=(
  repair_to_ready
  relay_by_path
  stray_hunk_reverted
  guard_rebaseline_after_gate
  interaction_scan_surfaces
  immediate_ready_citations_overturn
)
DRAWS=2
TIMEOUT=3600
: >"$LOG"
echo "eval_id,draw,run_dir,duration_s,worker_rc,vendor,model,graded" >"$CSV"
echo "Measurement start $(date -Iseconds) timeout=$TIMEOUT draws=$DRAWS vendor=cursor(default)" | tee -a "$LOG"

for eval_id in "${EVALS[@]}"; do
  for draw in $(seq 1 "$DRAWS"); do
    echo "" | tee -a "$LOG"
    echo "=== $eval_id draw=$draw start $(date -Iseconds) ===" | tee -a "$LOG"
    # Capture run.py stdout to find Run dir
    tmpout="$(mktemp)"
    set +e
    python3 tests/task_auto_check/evals/run.py --force --timeout "$TIMEOUT" "$eval_id" >"$tmpout" 2>&1
    rc=$?
    set -e
    cat "$tmpout" | tee -a "$LOG"
    run_dir="$(rg -o 'Run dir: .*' "$tmpout" | head -1 | sed 's/^Run dir: //')"
    timing="$run_dir/$eval_id/timing.json"
    grading="$run_dir/$eval_id/grading.txt"
    duration=""
    worker_rc=""
    vendor=""
    model=""
    graded=""
    if [[ -f "$timing" ]]; then
      duration="$(python3 -c "import json; t=json.load(open('$timing')); print(t.get('duration_s',''))")"
      worker_rc="$(python3 -c "import json; t=json.load(open('$timing')); print(t.get('worker_rc',''))")"
      vendor="$(python3 -c "import json; t=json.load(open('$timing')); print(t.get('vendor') or 'cursor')")"
      model="$(python3 -c "import json; t=json.load(open('$timing')); print(t.get('model') or '')")"
    fi
    if [[ -f "$grading" ]]; then
      graded="$(rg -o '^(PASS|FAIL|INCONCLUSIVE).*' "$grading" | head -1 || true)"
    fi
    echo "$eval_id,$draw,$run_dir,$duration,$worker_rc,$vendor,$model,\"$graded\"" >>"$CSV"
    echo "=== $eval_id draw=$draw done rc=$rc duration_s=$duration worker_rc=$worker_rc graded=$graded ===" | tee -a "$LOG"
    rm -f "$tmpout"
    if [[ "$worker_rc" != "0" ]]; then
      echo "NONZERO worker_rc for $eval_id draw=$draw — will need ceiling raise / retry" | tee -a "$LOG"
    fi
  done
done

echo "" | tee -a "$LOG"
echo "Measurement end $(date -Iseconds)" | tee -a "$LOG"
python3 - <<'PY' | tee -a "$LOG"
import csv, pathlib
p = pathlib.Path("tests/task_auto_check/results/timeout_band_measure.csv")
rows = list(csv.DictReader(p.open()))
print("\nCompleting draws (worker_rc==0):")
durs = []
for r in rows:
    if r.get("worker_rc") == "0" and r.get("duration_s"):
        d = float(r["duration_s"])
        durs.append(d)
        print(f"  {r['eval_id']} draw={r['draw']}: {d:.1f}s vendor={r['vendor']} model={r['model']}")
if durs:
    print(f"\nBand: {min(durs):.0f} .. {max(durs):.0f}s")
    print(f"Default candidate: stay 1800 if max<=1800 else {max(durs)+300:.0f}")
else:
    print("No completing draws!")
PY
