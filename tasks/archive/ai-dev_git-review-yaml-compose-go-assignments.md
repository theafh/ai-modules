---
description: "Make git_review's credential scan match unquoted YAML and Compose assignments and Go := declarations, while type annotations, templated values, and Go expressions draw no hit."
scope: plugins/ai_dev/skills/git_review
created: 2026-10-18T21:53:52
updated: 2026-10-18T22:08:10
status: finished
reported-by: Andreas Hoffmann
implemented-by: Andreas Hoffmann
design-extended: false
---

# Match unquoted YAML, Compose, and Go `:=` assignments in the git_review credential scan

## Goal

The git_review credential scan reports the assignment shapes that config files and Go code most often use for a committed secret, and keeps type annotations and templated values out. Each line of this block appears under `credential_pattern_hits:` as `path:line:content`, with its indentation as shown, except that the Go `password` declaration is indented with one tab:

```text
      POSTGRES_PASSWORD: supersecret123
      - POSTGRES_PASSWORD=supersecret123
  - "API_TOKEN=quotedlist123"
  db_password: hunter2hunter2
DB_PASSWORD: hunter2hunter2
  - password: s3cretpass1
  password: Tr0ub4dor&3 # rotated
password := "hunter2hunter2"
token := "ghx0123456789abcd"
```

In order, these are a Compose environment map entry, two Compose environment list items, YAML mapping entries indented and at the first column, a YAML list item that opens with a mapping entry, a YAML entry with a trailing comment, and two Go short variable declarations.

Each line of this block draws no hit:

```text
    password: Optional[str] = None
    password: SecretStr
    token: str
  password: !vault |
  token: ${{ secrets.DEPLOY_TOKEN }}
  secret: db-credentials
token := os.Getenv("API_TOKEN")
```

In order, these are three Python annotations, a YAML tag, a templated value, a resource name, and a Go expression.

Every line the scan reports today stays reported, and every no-hit line it carries today stays a no-hit.

## Context

`CREDENTIAL_PATTERN` in `plugins/ai_dev/skills/git_review/scripts/collect_review_evidence.sh` is one heredoc line read by `read -r CREDENTIAL_PATTERN`. The comment block above it, which opens with "One assignment each, identical to the strings in references/manual_fallback.md.", describes each branch. `references/manual_fallback.md` carries the same string in its scan block, and `s29_secret_scan_patterns_match_manual_fallback` checks that the collector holds the string once and the fallback holds it too. Grepping the pattern over the Goal hit lines on 2026-10-18 matched none of them, for three reasons:

- The unquoted `.env` branch opens with `^(export[[:space:]]+)?`, so it matches `KEY=value` only from the first column, and a Compose list item never reaches it.
- The two spaced branches accept the single operator `[:=]`, so Go's `:=` leaves `=` where the value must start.
- Every branch that accepts a colon requires the value to open with a quote or another non-alphanumeric character, so an unquoted YAML value draws no hit.

The range-mode scenario `s25_secret_scan_locates_every_shape` in `tests/git_review/script_tests/run.sh` places the scan's hit lines in `creds.txt` and its no-hit lines in files such as `kwargs.py`, `kwargs_multiline.py`, `routes.ts`, and `docs/home/dave/notes.txt`. It asserts each hit as `path:line:content` with `assert_contains` and each no-hit with `assert_absent`, and it runs the manual fallback's scan block under bash and zsh against the collector's hits. Its no-hit lines (keyword arguments, task slugs, hyphenated prose) set the scan's precedent of rejecting noisy non-secret shapes even where a looser pattern would report more, and this task's value rules follow that precedent.

[ai-dev_git-review-assignment-key-names.md](ai-dev_git-review-assignment-key-names.md) edits the same assignment branches and the same scenario so suffixed and camelCase key names match. Whichever task lands second applies its key-name or operator edit to every assignment branch the first one left, including the colon branch this task adds, and keeps the other task's hit and no-hit lines in `s25`.

## Approach

Rewrite `CREDENTIAL_PATTERN` in place with three changes, keeping it one contiguous heredoc line and the identical string in the manual fallback:

1. **Compose list item.** Widen the unquoted `.env` branch's optional prefix from `(export[[:space:]]+)?` to `([[:space:]]*-[[:space:]]+"?|export[[:space:]]+)?`. A `- KEY=value` or `- "KEY=value"` item then matches at any indentation, while an indented keyword argument, which carries no dash, still draws no hit.
2. **Go `:=`.** In the two spaced branches, replace the operator `[[:space:]]*[:=][[:space:]]*` with `[[:space:]]*(:=|[:=])[[:space:]]*`. A quoted value after `:=` then matches, and an unquoted Go expression after `:=` draws no hit, as it does after `=` today.
3. **Unquoted colon value.** Add one branch for a YAML-style line: optional indentation, an optional list dash (a `-` and a space), a key built from the same key-name class and keyword alternation the other assignment branches use, a colon and at least one space, then a bare value that runs to the end of the line, optionally followed by whitespace and a `#` comment. The value opens with a letter or digit, holds at least eight characters, uses no whitespace, quote, `$`, bracket, brace, parenthesis, angle bracket, `|`, `,`, `;`, or `#`, and contains at least one digit or one of `!@%^&*+=~`. ERE has no lookahead, so express the length and the required character as alternatives that each guarantee both, for example `([[:alnum:]]C{6,}DC*|[[:alnum:]]C*DC{6,}|[0-9]C{7,})`, where `C` is the allowed value class and `D` the required class. The required digit or symbol keeps type names such as `SecretStr` out, the excluded brackets and `|` keep `Optional[str]` and `str|None` out, and the leading letter or digit keeps `${{ … }}` and `!vault` out.

Rewrite the comment block above the pattern in place so it states each form once: the list-item prefix on the unquoted branch, the `:=` operator on the spaced branches, and the colon branch with its value rules. The sentence that says the unquoted form matches a `KEY=value` that starts in the first column becomes the list-item statement.

Add the Goal lines to `s25`: the Compose and YAML lines in a `compose.yml`, the Go lines in a `main.go`, and the Python annotation lines in a `settings.py`. Assert each hit line with `assert_contains` as `path:line:content` at the line where the scenario placed it, and each no-hit line with `assert_absent`. Extend the `git_review/` coverage passages in `tests/README.md` and `tests/CLAUDE.md`, which enumerate the scan's located shapes, to name the Compose, YAML, and Go `:=` hits, and extend the no-hit list in the `tests/README.md` passage to name the annotation and templated-value lines, as the standing repo rules for tests require.

**Out of scope:** suffixed and camelCase key names, which ai-dev_git-review-assignment-key-names.md owns. Letters-only unquoted colon values such as `password: changeme`, since a grep-only scan cannot tell such a value from a type name. An external secret scanner, since the scan stays within the collector's shell, awk, and grep toolchain.

## Acceptance

- In `s25`, each Goal hit line appears under `credential_pattern_hits:` as `path:line:content` for the file and line where the scenario placed it.
- In `s25`, each Goal no-hit line is absent from `secret_scan.txt`.
- `s25` still passes every hit and no-hit assertion it carried before this task, and its manual-fallback runs under bash and zsh still match the collector's hits.
- `s29` passes: `CREDENTIAL_PATTERN` is one contiguous heredoc line present once in the collector and verbatim in `references/manual_fallback.md`.
- The comment block above `CREDENTIAL_PATTERN` describes the list-item prefix, the `:=` operator, and the colon branch, and the sentence limiting the unquoted form to a `KEY=value` that starts in the first column is gone.
- The `git_review/` passages in `tests/README.md` and `tests/CLAUDE.md` name the Compose, YAML, and Go `:=` hits among the scan's located shapes, and `tests/README.md` names the annotation and templated-value lines among its no-hit shapes.
