---
description: "Say what an agent_spinner checking pass checks when the request names no acceptance contract: claims against their source, with omissions left to a completeness critic unless asked."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T23:45:46Z
updated: 2026-11-17T10:06:07Z
status: open
reported-by: Andreas Hoffmann
---

# Say what a checking pass checks when the request names no contract

## Goal

A request such as "run a checking pass over these pages against the tool" gets the same checklist on every draw. The skill says what the acceptance contract is when the request names none: every claim the artifact makes, checked against the source it describes. A missing claim is a completeness question, which goes to a completeness critic only when the request asks what is missing, so a checking pass over an accurate corpus reports zero findings.

## Context

- **The rule assumes a contract.** SKILL.md `<checking>` says "Build the checklist from the artifact's acceptance contract, one line per item, testing the required form present and the old form absent", and `references/checks.md` repeats the term, but neither says where the contract comes from when the request names none. SKILL.md `<selector>` keeps omissions apart: "A finished body needing a what-is-missing read: a completeness critic."
- **What happened.** `clean_corpus` asks for a checking pass over two accurate pages against `bin/tool.sh`, and expects zero findings. After its fixture was repaired on 2026-11-15, the Cursor run passed 12 of 12 checks. A Claude run (`opus` at high effort) said "Neither page under docs/ says anything false about bin/tool.sh", yet wrote its own rubric including omissions and reported five minor findings, such as the status page never giving its success exit code. Earlier Claude runs of the same eval reported omissions too.

The run's other two failures belong elsewhere: its verifier returns were rejected on shape ([the brief-contract task](ai-dev_agent-spinner-ledger-brief-contract.md)), and its opening sentence missed the tier and counts (the report-and-packet task).

## Approach

1. Rewrite the SKILL.md `<checking>` sentence in place so it names the default contract: when the request names no acceptance contract, the checklist holds one line per claim the artifact makes, each tested against the source the request names. State that a missing claim is a completeness finding, raised only when the request asks what is missing, and point at the completeness-critic row.
2. Make the matching passage in `references/checks.md` say the same, and have the checker template in `references/role-prompts.md` carry the default when the brief names no contract.

## Acceptance

- SKILL.md `<checking>` and `references/checks.md` state the default contract and where omissions go, and the old sentence no longer stands without it.
- `clean_corpus` and `planted_defect` run on the default vendor, with verdicts recorded in `tests/agent_spinner/evals/README.md`. `clean_corpus` reports zero findings and `planted_defect` still names its planted defect. If a run still reports omissions on `clean_corpus`, the record quotes the rubric line it used and the task stays open.
