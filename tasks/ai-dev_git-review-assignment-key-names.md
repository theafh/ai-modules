---
description: "Make git_review's credential scan match suffixed and camelCase key names, including an AWS secret access key, and reject the named non-secret assignments."
scope: plugins/ai_dev/skills/git_review
created: 2026-10-18T16:37:59
updated: 2026-10-18T16:37:59
status: open
reported-by: Andreas Hoffmann
---

# Match suffixed and camelCase key names in the git_review credential scan

## Goal

The credential assignment scan reports a hit for a key name that continues after the keyword, and for a keyword in camelCase. `aws_secret_access_key = wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY`, `SECRET_KEY = "django-insecure-abcdefghijklmnop"`, `apiKey: "abcdefghijklmnop"`, and `clientSecret = "abcdefghijklmnop"` each appear under `credential_pattern_hits:` as `path:line:content`. `token_count=12345678` and `password_hash = "not-a-secret-value"` draw no hit. The shapes the scan already matches stay matches.

## Context

`CREDENTIAL_PATTERN` in `plugins/ai_dev/skills/git_review/scripts/collect_review_evidence.sh` is one heredoc, copied as the same string in `references/manual_fallback.md`. Each assignment branch requires the keyword to end the key name and to be all lowercase or all uppercase, so a suffix such as `_access_key` or `_KEY`, and camelCase such as `Key` or `Secret`, fall through. The AWS secret access key is the half of an AWS credential pair that the `AKIA` rule does not see.

[ai-dev_git-review-secret-scan-gaps.md](archive/ai-dev_git-review-secret-scan-gaps.md) shipped the current branches and their enumerated shapes. The range-mode scenario `s25_secret_scan_locates_every_shape` in `tests/git_review/script_tests/run.sh` places those shapes and the no-hit lines, and `s29_secret_scan_patterns_match_manual_fallback` checks that the collector and the fallback carry the same pattern string.

## Approach

Extend the assignment branches of `CREDENTIAL_PATTERN` so a keyword matches with a suffix of letters, digits, underscores, and hyphens, and so `secret`, `key`, and `token` match in camelCase as well as in the all-lowercase and all-uppercase forms the pattern matches today. Keep the pattern one contiguous greppable string, identical in the manual fallback.

Add the four hit lines and the two no-hit lines to the range-mode scenario that already places the scan's shapes. Keep today's hits and today's no-hit lines in that scenario.

**Out of scope:** an external secret scanner, since the scan stays in the collector's shell, awk, and grep toolchain. The home-path pattern, since this task changes assignment key names.

## Acceptance

- In the range-mode scenario, `aws_secret_access_key = wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY`, `SECRET_KEY = "django-insecure-abcdefghijklmnop"`, `apiKey: "abcdefghijklmnop"`, and `clientSecret = "abcdefghijklmnop"` each appear under `credential_pattern_hits:` as `path:line:` for the file and line where the scenario placed them.
- In that scenario, `token_count=12345678` and `password_hash = "not-a-secret-value"` do not appear in `secret_scan.txt`.
- That scenario still passes for the shapes it already required, including its no-hit lines.
- The credential pattern remains one contiguous assignment, and the same string is present in `references/manual_fallback.md`.
