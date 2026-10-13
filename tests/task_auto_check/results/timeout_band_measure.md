# Timing-band re-measurement (complete)

Campaign for `tasks/tests_eval-runner-timeout-crash.md`.

- **When:** 2026-10-12T23:07 – 2026-10-13T02:11 (first five evals); resume
  2026-10-13T09:31 – 10:06 (`immediate_ready_citations_overturn`)
- **Vendor:** Cursor default (`agent -p`, model `auto`)
- **Protocol:** each repair-class eval solo and sequential, `--force`,
  measurement ceiling 3600s so no draw was cut off
- **Raw logs / CSV:** `timeout_band_measure.log`,
  `timeout_band_measure_resume.log`, `timeout_band_measure.csv`

## Completing draws (`worker_rc` 0)

| Eval | Draw 1 `duration_s` | Draw 2 `duration_s` | Run dirs |
| --- | ---: | ---: | --- |
| `repair_to_ready` | 860.2 | 774.6 | `run-20261012-230730-57365`, `run-20261012-232202-97692` |
| `relay_by_path` | 1178.1 | 575.7 | `run-20261012-233508-33567`, `run-20261012-235458-85491` |
| `stray_hunk_reverted` | 699.4 | 685.1 | `run-20261013-000445-11881`, `run-20261013-001636-43658` |
| `guard_rebaseline_after_gate` | 1417.4 | 1045.2 | `run-20261013-002812-74895`, `run-20261013-005201-37054` |
| `interaction_scan_surfaces` | 1671.9 | 2005.0 | `run-20261013-010937-83170`, `run-20261013-013740-56238` |
| `immediate_ready_citations_overturn` | 1062.1 | 1057.2 | `run-20261013-093113-44130`, `run-20261013-094910-3627` |

Band: **576s … 2005s** (~10 to 33 min).
Harness default `--timeout`: upper end + 300 = **2305**.

Per-eval effective ceilings after the change (declaration if present, else
default 2305) all clear each eval's observed max + 300. No repair-class
`evals.json` `"timeout"` needed updating: `immediate_ready_citations_overturn`
stays at 3600; the others inherit 2305.
