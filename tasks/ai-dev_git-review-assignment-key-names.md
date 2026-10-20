---
description: "Make git_review's credential scan match suffixed and camelCase key names, including an AWS secret access key, and reject the named non-secret assignments."
scope: plugins/ai_dev/skills/git_review
created: 2026-10-18T16:37:59
updated: 2026-10-20T16:25:42
status: audited
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Match suffixed and camelCase key names in the git_review credential scan

## Goal

The credential assignment scan reports a hit when the key name ends with a credential keyword, including bare `key`/`KEY`/`Key` and camelCase `Secret` and `Key`. `aws_secret_access_key=wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY`, `SECRET_KEY = "django-insecure-abcdefghijklmnop"`, `apiKey: "abcdefghijklmnop"`, and `clientSecret = "abcdefghijklmnop"` each appear under `credential_pattern_hits:` as `path:line:content`. `token_count=12345678` and `password_hash = "not-a-secret-value"` draw no hit. The shapes the scan already matches stay matches.

## Context

`CREDENTIAL_PATTERN` in `plugins/ai_dev/skills/git_review/scripts/collect_review_evidence.sh` is one heredoc, copied as the same string in `references/manual_fallback.md`. Each assignment branch already treats the keyword as the end of the key name, but it matches only the all-lowercase and all-uppercase keyword forms and omits bare `key`/`KEY`/`Key`, so `aws_secret_access_key`, `SECRET_KEY`, `apiKey`, and `clientSecret` fall through. The AWS secret access key is the half of an AWS credential pair that the `AKIA` rule does not see.

[ai-dev_git-review-secret-scan-gaps.md](archive/ai-dev_git-review-secret-scan-gaps.md) shipped the current branches and their enumerated shapes. The range-mode scenario `s25_secret_scan_locates_every_shape` in `tests/git_review/script_tests/run.sh` places those shapes and the no-hit lines, and `s29_secret_scan_patterns_match_manual_fallback` checks that the collector and the fallback carry the same pattern string.

## Approach

Rewrite the assignment branches of `CREDENTIAL_PATTERN` so a credential keyword remains the terminal token of the key name: letters, digits, underscores, and hyphens may appear only before that terminal keyword, and `_`, `-`, or name-start must precede lowercase `key` and uppercase `KEY` only, so English-word names such as `monkey` stay non-hits; treat camelCase `Key` and `Secret` as capital-led keyword spellings that may follow `[a-z]` (so `apiKey` and `clientSecret` hit); match bare `key`/`KEY`/`Key` and camelCase `Secret` and `Key` in addition to today's all-lowercase and all-uppercase forms. Keep the pattern one contiguous greppable string, identical in the manual fallback.

Add the four hit lines, the two no-hit lines, and a `monkey = "not-a-secret-value"` no-hit line to the range-mode scenario that already places the scan's shapes. Keep today's hits and today's no-hit lines in that scenario.

Rewrite the `git_review/` coverage passages in `tests/README.md` and `tests/CLAUDE.md`, which enumerate the scan's located shapes, so they name suffixed and camelCase assignment hits beside the Compose, YAML, and Go `:=` hits they already list, and extend the no-hit list in the `tests/README.md` passage to name assignments whose names continue after a credential keyword (the Goal's `token_count` and `password_hash` shapes).

**Out of scope:** an external secret scanner, since the scan stays in the collector's shell, awk, and grep toolchain. The home-path pattern, since this task changes assignment key names.

## Acceptance

- In the range-mode scenario, `aws_secret_access_key=wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY`, `SECRET_KEY = "django-insecure-abcdefghijklmnop"`, `apiKey: "abcdefghijklmnop"`, and `clientSecret = "abcdefghijklmnop"` each appear under `credential_pattern_hits:` as `path:line:content` for the file and line where the scenario placed them.
- In that scenario, `token_count=12345678`, `password_hash = "not-a-secret-value"`, and `monkey = "not-a-secret-value"` do not appear in `secret_scan.txt`.
- That scenario still passes for the shapes it already required, including its no-hit lines.
- The credential pattern remains one contiguous assignment, and the same string is present in `references/manual_fallback.md`.
- The `git_review/` passages in `tests/README.md` and `tests/CLAUDE.md` name suffixed and camelCase assignment hits among the scan's located shapes, and `tests/README.md` names assignments whose names continue after a credential keyword among its no-hit shapes.
