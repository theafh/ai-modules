---
description: "Say what an agent_spinner checking pass checks when the request names no acceptance contract: claims against their source, with omissions left to a completeness critic unless asked."
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-11-14T23:45:46Z
updated: 2026-11-18T09:21:23Z
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Say what a checking pass checks when the request names no contract

## Goal

A request such as "run a checking pass over these pages against the tool" gets the same checklist on every draw. The skill says what the acceptance contract is when the request names none: every claim the artifact makes, checked against the source it describes. A missing claim is a completeness question, which goes to a completeness critic only when the request asks what is missing, so a checking pass over an accurate corpus reports zero findings.

## Context

- **The rule assumes a contract.** SKILL.md `<checking>` says "Build the checklist from the artifact's acceptance contract, one line per item, testing the required form present and the old form absent", and `references/checks.md` repeats the term, but neither says where the contract comes from when the request names none. SKILL.md `<selector>` keeps omissions apart: "A finished body needing a what-is-missing read: a completeness critic."
- **What happened.** `clean_corpus` asks for a checking pass over two accurate pages against `bin/tool.sh`, and expects zero findings. After its fixture was repaired on 2026-11-15, the Cursor run passed 12 of 12 checks. A Claude run (`opus` at high effort) said "Neither page under docs/ says anything false about bin/tool.sh", yet wrote its own rubric including omissions and reported five minor findings, such as the status page never giving its success exit code. Earlier Claude runs of the same eval reported omissions too.

The run's other two failures belong elsewhere: its verifier returns were rejected on shape ([the brief-contract task](../ai-dev_agent-spinner-ledger-brief-contract.md)), and its opening sentence missed the tier and counts (the report-and-packet task).

## Approach

1. Rewrite the SKILL.md `<checking>` sentence in place so it names the default contract: when the checking brief names none of C1 step 4's three contract sources (the item brief, an approved-edit list, an acceptance list), the checklist holds one line per claim the artifact makes, in artifact order, each tested against the source it describes, which the request's named source identifies. State that a missing claim is a completeness finding, raised only when the request asks what is missing and otherwise recorded as a dropped suspicion, and name the `<completeness_critic>` block. State that a brief naming any of those three sources is outside the default, so a write run's paired refute check, whose brief names the item brief, keeps its hunk mapping.
2. Make `references/checks.md` C2 items 1–2 say the same, with item 2 keeping the old-form test only for rewrite items, the pairing `references/recipes/multi-file-task.md` already states, and item 1's `brief --acceptance PATH[#Heading]` renderer sentence scoped to a brief that names an acceptance source, since `--acceptance` is optional in `scripts/run_ledger.py`. Have the `## Checking pass` template in `references/role-prompts.md` name what its checklist is built from when the brief names no contract.
3. Pin the shipped sentences in `tests/agent_spinner/script_tests/run.sh`, one check per fact: the default contract with its claim unit and artifact order in `<checking>`, the same in C2, the old `<checking>` sentence absent, and the template's contract source inside its `## Checking pass` block. Give each check the scratch-copy negative control that file already uses, so a green run proves it can fail.

## Acceptance

- SKILL.md `<checking>` and `references/checks.md` C2 items 1–2 state the default contract, its claim unit and artifact order, and where omissions go (a missing claim recorded as a dropped suspicion, routed to `<completeness_critic>` only when the request asks), key the default on a brief naming none of C1 step 4's three contract sources (the item brief, an approved-edit list, an acceptance list), so a write run's checker brief naming only the item brief stays outside the default, and a grep finds the old `<checking>` sentence absent; C2 item 2's old-form test now applies to rewrite items alone, and C2 item 1's `brief --acceptance` renderer sentence is scoped to a brief that names an acceptance source.
- The `## Checking pass` template in `references/role-prompts.md` names what its checklist is built from when the brief names no contract, and a brief rendered from it with no contract named carries that sentence rather than a bare `1. [check one]`.
- The new `script_tests` checks pass on the shipped files and fail on a scratch copy carrying the old sentence, a checklist with no claim unit or order, or the bare template line.
- `clean_corpus` and `planted_defect` run on the default vendor as a regression guard, with verdicts recorded in `tests/agent_spinner/evals/README.md` beside their pre-change runs (`run-20261115-002747`, `run-20261111-111927`); `clean_corpus` reports zero findings and `planted_defect` still names its planted defect. If a default-vendor `clean_corpus` run still reports omissions, the record quotes the rubric line the checker used and the task stays unimplemented.
