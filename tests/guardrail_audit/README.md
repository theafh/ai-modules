# tests/guardrail_audit

Local Pattern A harness for the `guardrail_audit` skill (prose-only; no
bundled scripts).

```text
tests/guardrail_audit/
├── README.md
├── RUNBOOK.md
├── script_tests/run.sh          # static SKILL.md + registration contract
├── evals/
│   ├── evals.json
│   ├── stage.sh
│   ├── grade.sh
│   ├── run.py                   # sonnet-pinned worker runner
│   └── fixtures/<id>/setup.sh
└── workspace/                   # run output (gitignored)
```

## Surfaces

- **script_tests** — frontmatter, `<authority>`, `<audit_bound>`, no
  restated hub definitional content, hub forward-references intact,
  plugin / marketplace / README registration, plus
  `sandbox_git_isolation.sh` (fixture git cannot commit into the host
  checkout).
- **evals** — six staged fixtures covering presence-gating, doc-vs-doc,
  doc-vs-code (retrofit), an unreached `## Direction` target read as
  drive-toward work, grounded TESTING.md proposal, and multi-project
  nature mismatch. `grade.sh` always asserts the sandbox
  tree stays byte-identical (excluding `.git`); response markers are
  checked when a `response.txt` is supplied. Sandbox git is pinned with
  `GIT_DIR` / `GIT_WORK_TREE`; a blocked or failed `git init` aborts
  instead of walking up to the host repo.
