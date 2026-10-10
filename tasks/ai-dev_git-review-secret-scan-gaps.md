---
description: Make git_review's secret scan report each hit's file and line, read every added line, catch the credential and home-path shapes it misses, and match the manual fallback.
scope: plugins/ai_dev/skills/git_review
created: 2026-10-06T13:25:39
updated: 2026-10-09T18:10:40
status: open
reported-by: Andreas Hoffmann
---

# Locate hits and close the gaps in the git_review secret scan

## Goal

The credential and home-path scan in the `git_review` evidence collector writes each hit to `secret_scan.txt` with the changed file's path and the hit's line number on the new side of its diff, so a review report can cite where a suspected credential or home path sits. The scan reads every added content line of the collected diff in range mode and in uncommitted mode. Its patterns keep every shape they catch today and add the shapes listed under **Patterns** in Approach, while the shapes that list marks as no-hit still draw none. The manual fallback in `references/manual_fallback.md` runs the same extraction and patterns, so a review that cannot run the collector looks for the same shapes.

This task refines the existing pattern scan, which stays a cheap first pass beside the reviewer's own reading of the diff.

## Context

`collect_secret_scan` in `plugins/ai_dev/skills/git_review/scripts/collect_review_evidence.sh` reads `full_diff.txt` in range mode, or `worktree_diff.txt` in uncommitted mode, keeps the lines that match `^\+` except those that match `^+++`, and writes them to a temporary added-lines file. Two `grep -nE` passes over that file fill the `credential_pattern_hits:` and `hardcoded_home_path_hits:` sections of `secret_scan.txt`, and each section reads `none` when its pass finds nothing. The scan has three gaps:

- **Hits carry no location.** The `grep -n` number counts positions in the temporary file, so a hit such as `10:+aws_key = "AKIAIOSFODNN7EXAMPLE"` names neither the file nor its line, and the number shifts whenever another file in the diff gains added lines.
- **Some added lines are never scanned.** The `^+++` filter that removes the `+++ b/<path>` header also removes every added content line that begins with `++`, so the added line `++ /home/bob/.ssh/id_rsa` draws no hit.
- **Common shapes pass silently.** The `sk-` pattern needs 20 letters or digits straight after `sk-`, so Anthropic `sk-ant-...` and OpenAI `sk-proj-...` keys slip past it, and GitHub fine-grained `github_pat_...` tokens, Stripe `sk_live_...` keys, and Google `AIza...` keys match no pattern at all. The generic assignment pattern matches lowercase key names only, and only where optional spaces and a `:` or `=` follow the key name and a quoted value of eight or more characters comes next, so `PASSWORD="..."`, an unquoted `.env` value such as `DB_PASSWORD=hunter2hunter2`, and a JSON member such as `"password": "..."` all pass. The home-path pattern needs a slash after the user name and matches only the escaped `C:\\Users\\` form, so `"/Users/alice"` at the end of a value and a plain `C:\Users\carol\AppData` pass too.

The manual fallback in `references/manual_fallback.md`, under "The credential and home-path scan over the added lines:", runs a shorter pattern list (AWS key IDs, private-key headers, and the two Unix home-path shapes) behind the same `grep -v '^\+\+\+'` filter, so it has already drifted from the script.

The skill's `<evidence_set>` names the scan. Eval 20 runs the skill on the `secrets_and_home_path` fixture, whose single changed file `src/settings.py` adds an `AKIA` key and a `/home/alice/.cache/widget` path, and its expectations name both findings in `src/settings.py`. The `20)` case in `tests/git_review/evals/grade.sh` checks for the credential and the `/home/alice` path but not for the file. The script test `s9_secret_scan_finds_both_shapes` asserts the `AKIAIOSFODNN7EXAMPLE` and `/home/alice/` hits on the `cfg.py` that `fresh_repo` adds.

## Approach

Rewrite `collect_secret_scan` in three parts, keeping the two sections of `secret_scan.txt` and their `none` lines.

**Extraction.** Replace the `^\+` and `^+++` filter pair with one pass over the diff file that emits each added content line with its location. Treat a line that starts with `---` or `+++` as a header only between a file's `diff --git` line and its first content line, so an added line that begins with `++` stays a content line. Take the path from the `+++ b/<path>` header and the starting line number from the `+c` field of each `@@ -a,b +c,d @@` hunk header, then advance the number on every context line and every added line. An untracked file in uncommitted mode has a synthesized header and no hunk header, so its numbering starts at 1. [ai-dev_git-review-size-profile-overcount.md](archive/ai-dev_git-review-size-profile-overcount.md) introduces the same header rule in `collect_size_profile`, so when that pass is already in the collector, factor the shared header handling into one helper both functions use. In uncommitted mode, a path that both sides of an unresolved merge changed arrives as a combined diff instead: a `diff --cc <path>` opener, the same `---` and `+++` header pair, `@@@ -a,b -c,d +e,f @@@` hunk headers whose last range starts the result's numbering, and two prefix columns per line, where the first column compares against `HEAD` and a line holding `-` in either column is absent from the result. [ai-dev_git-review-size-profile-conflicted-headers.md](ai-dev_git-review-size-profile-conflicted-headers.md) rewrites each `diff --cc` opener into the `diff --git` form for the size profile, so whichever task lands second can reuse that rewrite, and git quotes a non-ASCII name in these headers as well, as in `+++ "b/\303\244.txt"`.

**Output.** Match both patterns against each added line's content alone, so a file path never draws a hit, and write each hit under its section as `<path>:<line>:<content>`, where `<content>` is the added line without its leading `+`.

**Patterns.** Define the credential pattern and the home-path pattern once each, in variables beside `GENERATED_PATTERN`. Rewrite them so they keep every shape the current patterns catch, read from the script as it stands before this change, and add these shapes:

- Anthropic `sk-ant-api03-...` and OpenAI `sk-proj-...` keys.
- GitHub fine-grained `github_pat_...` tokens, Stripe `sk_live_...` keys, and Google `AIza...` keys.
- A quoted assignment with an uppercase key name such as `PASSWORD="..."`, an unquoted `.env` assignment such as `DB_PASSWORD=hunter2hunter2`, and a JSON member such as `"password": "..."`.
- A Unix home path that ends a value without a trailing slash, such as `"/Users/alice"`, and a single-backslash Windows path such as `C:\Users\carol\AppData`.

These no-hit shapes must still draw no hit: a variable reference such as `TOKEN=${TOKEN}` or `API_KEY=$API_KEY`, a function call such as `password = get_password()`, and an empty value such as `password: ""`.

**Manual fallback.** Rewrite the scan passage under "The credential and home-path scan over the added lines:" in `references/manual_fallback.md` in place, so it runs the script's extraction and carries both pattern strings verbatim in place of its shorter list and its `grep -v '^\+\+\+'` filter.

**Tests.** Add these checks to `tests/git_review/script_tests/run.sh`, giving each new scenario its own sandbox and the next free `s<N>` id:

- A range-mode scenario whose feature branch adds, across at least two files, every shape the current patterns catch, every shape added under **Patterns**, and every no-hit shape, with one added home path on a line that begins with `++` and the no-hit shapes in a file under a `docs/home/dave/` directory, so a match against the path would show as a hit.
- An uncommitted-mode scenario with an added shape in a staged edit and another in an untracked file.
- A check that fails when `references/manual_fallback.md` lacks either pattern string from the script verbatim.

Add a check to the `20)` case in `grade.sh` that the report names `src/settings.py`, which eval 20's expectations already require. Keep the `git_review/` entries in `tests/README.md` and `tests/CLAUDE.md` current with the added coverage, per the standing testing rules.

**Out of scope:** running an external secret scanner such as gitleaks, since the scan stays within the collector's shell, awk, and grep toolchain under the standing repo rules.

## Acceptance

- A search of `collect_review_evidence.sh` for `grep -v '^+++'` returns no match, and the credential and home-path patterns each appear once, as variables that `collect_secret_scan` reads.
- In the new range-mode scenario, every shape the pre-change patterns catch and every shape added under **Patterns** appear in `secret_scan.txt`, each as `<path>:<line>:` naming the file and new-side line where the sandbox placed it.
- In the same scenario, the home path on the added line that begins with `++` appears as a hit.
- In the same scenario, no no-hit shape from **Patterns** appears in `secret_scan.txt`, and no hit names the file under `docs/home/dave/`.
- In the new uncommitted-mode scenario, the staged shape and the untracked shape appear with their paths and line numbers, the untracked one counted from the first line of its file.
- The fallback check passes, and it fails when either pattern string is removed from a copy of `references/manual_fallback.md`.
- The scan passage in `references/manual_fallback.md` runs the header-aware extraction, and a search of that file for `grep -v '^\+\+\+'` and for the prior alternation `AKIA[0-9A-Z]{16}|-----BEGIN` returns no match.
- The `20)` case in `grade.sh` checks that the report names `src/settings.py`, and eval 20 passes on a fresh `python3 tests/git_review/evals/run.py 20` run.
- The `git_review/` entries in `tests/README.md` and `tests/CLAUDE.md` name the located secret-scan hits among the covered behaviours, and the `tests/README.md` scenario count equals the number of `scenario` registrations in `script_tests/run.sh`.
