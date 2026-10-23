---
description: "Make git_review's credential scan skip subscripts, unquoted code values, and bare lowercase key names, and match camelCase Token and Password key names."
scope: plugins/ai_dev/skills/git_review
created: 2026-10-20T17:01:49
updated: 2026-10-23T15:40:19
status: implemented
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Reject subscripts, unquoted value starts, and bare lowercase key in the git_review credential scan, and match camelCase Token and Password

## Goal

The credential assignment scan reports quoted assignments and stops reporting code that only resembles one. Each line of this block draws no hit, with its indentation as shown:

```text
    fields[key] = "\n".join(block)
        data[key] = _decode_quoted_scalar(value)
    fields[token] = "abcdefghijk"
password = _secret_value_here
token = {"access": "abcdef"}
<li key={item.id}>
    raise ValueError(f"no parent key: {line!r}")
A spawned agent ends with its family token: `auto_<role>_<family>`.
  "key": "first-contentful-paint",
```

In order, these are three subscript writes, a value that opens with `_`, a value that opens with `{`, a JSX attribute, an f-string, a Markdown line with inline code, and a JSON member named `key`.

A lowercase `key` counts as a credential key name only after `_` or `-`, while a bare `KEY` and a bare `Key` still count, so `KEY = "abcdefghijklmnop"` appears under `credential_pattern_hits:` as `path:line:content`. camelCase `Token` and `Password` join `Key` and `Secret` as key-name endings, so `accessToken = "abcdefghijklmnop"` and `dbPassword = "abcdefghijklmnop"` each appear there too. Every hit and no-hit line that the range-mode scenario carries today keeps its verdict.

## Context

`CREDENTIAL_PATTERN` in `plugins/ai_dev/skills/git_review/scripts/collect_review_evidence.sh` is one heredoc line read by `read -r CREDENTIAL_PATTERN`, and `references/manual_fallback.md` carries the same string. The comment block above it, which opens with "One assignment each, identical to the strings in references/manual_fallback.md.", describes each branch.

The false positives come from the first unanchored assignment branch, the one whose key name is followed by `[^[:alnum:][:space:]]?` and whose value opens with `[^[:alnum:][:space:]:=$]`. The optional character after the name exists for the closing quote of a JSON member such as `"password": "hunter2xx"`, and the value's first character exists for its opening quote. Both classes accept any non-alphanumeric character, so the `]` of a subscript passes after the name, and `_`, `{`, and a backtick pass as the value's first character. The comment block's sentence "A quoted assignment after =, :, or Go's := matches a value of eight or more characters, and that value may contain spaces" describes the spaced quoted branch (`["'][^"'$][^"']{7,}`), which already accepts only `["']` before its value. The first unanchored branch has no dedicated comment sentence of its own today. On 2026-10-20 every tracked-file hit that a quote-only form of this branch removes was ordinary code or prose, and the range-mode scenario still passed with that form in a scratch copy.

[ai-dev_git-review-assignment-key-names.md](archive/ai-dev_git-review-assignment-key-names.md) ships the key-name rule this task builds on: suffixed names, bare `key`/`KEY`/`Key`, and camelCase `Key` and `Secret` after a lowercase letter, written as `Key|secret|SECRET|Secret` in the keyword alternation of every assignment branch. Its bare `key` and camelCase `Key` multiplied the subscript false positives, which is what surfaced this task. Implement this task on top of that one, and keep the hit and no-hit lines it added.

The range-mode scenario `s25_secret_scan_locates_every_shape` in `tests/git_review/script_tests/run.sh` places hit lines in `creds.txt` and no-hit lines in other files, asserts each hit with `assert_contains` as `path:line:content` and each no-hit with `assert_absent`, and runs the manual fallback's scan block under bash and zsh against the collector's hits. `s29_secret_scan_patterns_match_manual_fallback` checks that the collector holds the pattern once and the fallback holds the same string. The `git_review/` coverage passage in `tests/README.md` enumerates the scan's located shapes and its no-hit shapes. The `git_review/` row in `tests/CLAUDE.md` names "suffixed and camelCase key-name assignments", which already covers the new hits.

## Approach

Rewrite `CREDENTIAL_PATTERN` in place, keeping it one contiguous heredoc line and the identical string in `references/manual_fallback.md`:

1. **Quote-only JSON-style branch.** In the first unanchored assignment branch, replace the optional character after the key name, `[^[:alnum:][:space:]]?`, with `["']?`, and replace the value's first-character class, `[^[:alnum:][:space:]:=$]`, with `["']`, the same quote set the spaced quoted branch accepts. Keep the rest of the branch as it is.
2. **No bare lowercase key.** In each assignment branch, rewrite the key-name alternative `([A-Za-z0-9_-]*[_-])?(key|KEY)` so a lowercase `key` requires a preceding `_` or `-` while `KEY` keeps its optional prefix, for example `[A-Za-z0-9_-]*[_-]key|([A-Za-z0-9_-]*[_-])?KEY`. A bare `Key` already matches through the keyword alternation and stays a hit. After the quote-only narrowing, a JSON member named `key` is the main noise source left, since it usually carries an identifier, which is why the bare lowercase form goes.
3. **camelCase Token and Password.** In each assignment branch's keyword alternation, extend `Key|secret|SECRET|Secret` to `Key|secret|SECRET|Secret|Token|Password`, so the capital-led `Token` and `Password` may follow a lowercase letter the way `Key` and `Secret` do.

Rewrite the comment block above the pattern in place:

- The sentence that says a lowercase key or an uppercase KEY follows _, -, or the start of the name, so that "aws_secret_access_key, SECRET_KEY, and a bare key match", becomes one that says a lowercase `key` follows `_` or `-`, while `KEY` may also start the name.
- The sentence about the capital-led `Key` and `Secret`, which ends "so camelCase apiKey and clientSecret match", becomes one sentence that names `Key`, `Secret`, `Token`, and `Password`, with `accessToken` and `dbPassword` among its examples.
- Add a sentence for the first unanchored assignment branch that states only a closing quote may stand between the name and the operator and that the value opens with `"` or `'`, so a subscript such as `fields[key]` and a value that opens with `_`, `{`, or a backtick stay out. Leave the spaced-quoted sentence ("A quoted assignment after =, :, or Go's := matches a value of eight or more characters, and that value may contain spaces") unchanged for that branch.

In `s25`, add the `KEY` hit line, the bare `Key` hit line, and the two camelCase hit lines to `creds.txt` and assert each with `assert_contains` as `path:line:content` at the line where the scenario placed it. Add the Goal's no-hit lines to no-hit files in the same scenario, such as a Python file for the code lines, a Markdown file for the prose line, and a JSON file for the `key` member, and assert each with `assert_absent` against `secret_scan.txt`. Keep every hit and no-hit line `s25` already carries.

Rewrite the `git_review/` passage in `tests/README.md` in place, so its hit list names camelCase `accessToken` and `dbPassword` beside `apiKey` and `clientSecret`, and its no-hit list names subscript writes, values that open with `_`, `{`, or a backtick, and JSON members named `key`.

**Out of scope:** an external secret scanner, since the scan stays within the collector's shell, awk, and grep toolchain. A subscript with a string key such as `config["password"] = "hunter2hunter2"`, which draws no hit today either.

## Acceptance

- In `s25`, each Goal no-hit line appears in the scenario's scanned input files and is absent from `secret_scan.txt`.
- In `s25`, `KEY = "abcdefghijklmnop"`, `Key = "abcdefghijklmnop"`, `accessToken = "abcdefghijklmnop"`, and `dbPassword = "abcdefghijklmnop"` each appear under `credential_pattern_hits:` as `path:line:content` for the file and line where the scenario placed them.
- `s25` still passes every hit and no-hit assertion it carried before this task, and its manual-fallback runs under bash and zsh still match the collector's hits.
- `s29` passes: `CREDENTIAL_PATTERN` is one contiguous heredoc line present once in the collector and verbatim in `references/manual_fallback.md`.
- The comment block above `CREDENTIAL_PATTERN` names `Key`, `Secret`, `Token`, and `Password`, with `accessToken` and `dbPassword` among its examples, states that a lowercase `key` follows `_` or `-`, and states the quote-only rule for the name's trailing character and the value's first character. A search of the collector for "so camelCase apiKey and clientSecret match" and for "and a bare key match" returns no match.
- A search of the collector for "A quoted assignment after =, :, or Go's := matches a value of eight or more" and for "characters, and that value may contain spaces" each returns a match.
- The `git_review/` passage in `tests/README.md` names `accessToken` and `dbPassword` among the located hits, and names subscript writes, values that open with `_`, `{`, or a backtick, and JSON members named `key` among the no-hit shapes.
