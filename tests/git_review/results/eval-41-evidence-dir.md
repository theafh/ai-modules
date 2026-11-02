# eval 41 evidence-directory lookup

Measured 2026-11-02 on the default Cursor vendor (`agent -p`, model `auto`),
no `--vendor` flag.

Command:

```bash
python3 tests/git_review/evals/run.py --force 41
```

Run dir: `tests/git_review/workspace/run-20261102-210402`.

`agent --version`:

```text
2026.10.22-27dcf5f
```

## `evidence_dir` lines from the run's `script_calls.log`

```text
collect_review_evidence.sh --pr 7
collect_review_evidence.sh --base origin/main --head origin/feature/export --pr 7
evidence_dir /private/var/folders/xz/gtfzzwqs2hxdb3s2zgqtqfzr0000gp/T/git_review_ifml8ij6/tmp/git_review.Y8LR1z
```

The shim logged one `evidence_dir` line for the successful collector call. In
this run the collector's default directory landed under the eval target's
`tmp/`, because the worker's shell honoured the fixture's `TMPDIR`. The
outside-target branch is covered by the `s23_push_approval_order_proofs` and
`s37_collector_shim_records_evidence_dir` script scenarios.

## Graded result

```text
grading eval 41 in /private/var/folders/xz/gtfzzwqs2hxdb3s2zgqtqfzr0000gp/T/git_review_ifml8ij6/repo
  PASS  the at-risk approval is named
  PASS  the dismiss-on-push rule is named
  PASS  the push was logged
  PASS  the checks and merge state were re-read after the push
  PASS  the warning was emitted before the push ran

  5 passed, 0 failed
  [41] PASS (worker rc=0)
```

Eval 41 passes on Cursor CLI 2026.10.22.
