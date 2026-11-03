---
description: "Make the task linter report every non-UTC created/updated value as fixable, and give task_fix a locale-ask protocol that converts them to UTC without bumping updated."
scope: plugins/ai_dev/skills/task
created: 2026-11-03T13:26:31
updated: 2026-11-03T23:26:25
status: ready
reported-by: Andreas Hoffmann
---

# Heal Task Timestamps to UTC

## Goal

The task linter reports every `created` or `updated` frontmatter value that is not a UTC timestamp as a fixable finding, and `task_fix` carries a timestamp-correction protocol that asks the user which locale produced the reported times, converts each reported value to its UTC instant, and rewrites the files until the linter reports none. The conversion is a format change: it preserves the instant, so it does not bump `updated`. The behaviour ships in the task skill and `task_fix`, so every repository carrying a deployed task tree heals the same way, and this repository's live and archived task files are the first tree it heals.

## Context

- **The linter.** `plugins/ai_dev/skills/task/scripts/lint.py` holds the date check in `check_frontmatter`, under the `for date_field in ("created", "updated")` loop, and its `DATETIME_RE` accepts an optional `Z` or `[+-]HH:MM` designator. The check warns only on a non-ISO shape, so a naive local value and a non-zero-offset value both pass clean today.
- **The convention.** The base `task` skill's `<frontmatter>` tells every writer to run `date +%Y-%m-%dT%H:%M:%S` and copy its output, which is local time with no designator. Every value that `grep -h '^updated:' tasks/*.md tasks/archive/*.md` returns lacks a designator.
- **The no-bump rule.** The base `task` skill's `<bump_updated>` and the linter's inline note that legacy provenance backfill does not bump `updated` say a content fix bumps `updated`. The archived [trustworthy-timestamps task](archive/task-family_trustworthy-timestamps.md) established the wall-clock `date` command that produced the local convention; this task keeps that command's wall-clock rule and changes the form it writes to UTC.
- **The consumer.** `plugins/ai_dev/skills/task_fix/SKILL.md` owns the mechanical remediation in its **Remediate.** step and the report shape in its `<output_contract>`. It is interactive, so it can ask the locale. Its escalated writer `auto_shaper_task` reads `task_fix` before editing.
- **The tests.** `tests/task/script_tests/run.sh` covers the linter mechanically, and `tests/task/evals/` covers the skill prose through the eval runner.
- Python 3 is a standing dependency and `zoneinfo` is stdlib from 3.9, so the conversion adds no dependency.

## Approach

1. **Report non-UTC values.** In `check_frontmatter`'s date loop in `lint.py`, replace the format-only test with a UTC test. A value is clean when it carries `Z`, a zero offset (`+00:00` or `+0000`), or a date with no time part (`YYYY-MM-DD`); it is reported when it carries a time with no designator or a non-zero offset. Report it as a warn whose message names the value and the no-bump rule, plus the UTC target when the value carries an explicit non-zero offset; for a naive value the message says the value is naive local time and names the zone ask in place of a target. Match the inline note shape the provenance findings already use. Keep the existing non-ISO warning for a value that is not a datetime at all. Add a **UTC timestamp normalization** entry to the base `task` skill's `<lint>` **mechanically fixable lint finding set**, as its own bullet after **Frontmatter and lifecycle mechanics**: convert a `created` or `updated` value whose UTC instant is determinable to the `Z` form, converting an explicit non-zero offset directly and a naive value once its zone is known, so the entry asks for the zone when the value is naive and surfaces the finding when no zone is available; the conversion preserves the instant, so `<bump_updated>`'s timestamp-normalization exception applies and `updated` stays un-bumped. Amend the set's closing paragraph in place so its "bumps `updated` once for a content-changing edit group" sentence names that exception instead of contradicting it.

2. **Make UTC the written form.** In the base `task` skill's `<frontmatter>`, rewrite two passages in place: the frontmatter example's `created: 2026-05-28T19:49:23` and `updated: 2026-05-28T19:49:23` values to `2026-05-28T19:49:23Z`, and the timestamp command `date +%Y-%m-%dT%H:%M:%S        # local time, e.g. 2026-05-28T19:49:23` to `date -u +%Y-%m-%dT%H:%M:%SZ        # UTC, e.g. 2026-05-28T19:49:23Z`, stating that the canonical form carries the `Z` designator. In `<bump_updated>`, add the timestamp-normalization exception: converting a timestamp's representation to UTC preserves the instant, so it does not bump `updated`, and this is the one format change the exception covers. State that exception in `<bump_updated>` alone, and have the passages this task edits cite it rather than restate it. Rewrite each live copy of the naive command in place to cite the base `<frontmatter>` timestamp command rather than restate it, so one canonical statement remains as the `CHARTER.md` invariant that family rules live in the family base skill requires: `plugins/ai_dev/skills/task_create/SKILL.md` `**Timestamp.**`, `plugins/ai_dev/skills/task_auto_check/SKILL.md` `<apply_repairs>` and `<finalize_mechanical_lint>`, and both `updated` stamps in `plugins/ai_dev/agents/auto_shaper_task.md` `<remediate>`. In `plugins/ai_dev/skills/task_fix/SKILL.md`, the **Remediate.** bump sentence that begins "Bump `updated` from `date` on every changed file" becomes a citation naming both exceptions, with the command taken from the base `<frontmatter>`, and the `<authority>` parenthetical that begins "bump `updated` from `date`" cites `<bump_updated>` instead of restating the command.

3. **Give `task_fix` the protocol.** In `task_fix/SKILL.md`, add a **Timestamp correction protocol** passage under the **Remediate.** step. Cite the `<lint>` **UTC timestamp normalization** entry that the **Report non-UTC values.** step adds, so a sibling that reads the fixable set treats the finding as fixable. State there that the repair is inline-only because it needs the zone ask: `task_fix` applies it inline, and the escalated `auto_shaper_task` surfaces a non-UTC finding rather than converting it. It collects the linter's non-UTC findings, asks the user for the zone that produced the naive values (an IANA name such as `Europe/Berlin`, or a fixed offset), converts a non-zero-offset value directly, converts a naive value with `zoneinfo`, writes the `Z` form, leaves `updated` un-bumped, re-lints archive-inclusive to zero, and reports each converted file with the zone used. It carries these snippets:

   ```bash
   # Naive local value plus an IANA zone.
   python3 - <<'PY'
   from datetime import datetime, timezone
   from zoneinfo import ZoneInfo
   naive = datetime.fromisoformat("2026-11-03T13:26:31")
   utc = naive.replace(tzinfo=ZoneInfo("Europe/Berlin")).astimezone(timezone.utc)
   print(utc.strftime("%Y-%m-%dT%H:%M:%SZ"))
   PY
   ```

   ```bash
   # Naive local value plus a fixed offset, here UTC+1.
   python3 - <<'PY'
   from datetime import datetime, timezone, timedelta
   naive = datetime.fromisoformat("2026-11-03T13:26:31")
   utc = (naive - timedelta(hours=1)).replace(tzinfo=timezone.utc)
   print(utc.strftime("%Y-%m-%dT%H:%M:%SZ"))
   PY
   ```

   ```bash
   # An explicit non-zero offset converts without asking.
   python3 - <<'PY'
   from datetime import datetime, timezone
   value = datetime.fromisoformat("2026-11-03T13:26:31+01:00")
   print(value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
   PY
   ```

   State the resolution rule: `zoneinfo` resolves an ambiguous or nonexistent local time at its default `fold`, and a fixed offset is the fallback when the user names an offset instead of a zone.

4. **Keep the test surfaces in step.** In `tests/task/script_tests/run.sh`, change every existing `date +%Y-%m-%dT%H:%M:%S` fixture stamp to `date -u +%Y-%m-%dT%H:%M:%SZ`, so `c1_fully_valid_task_is_clean` and `fs4_conflicting_flags_and_file_only` keep reporting a clean tree while `f4_non_iso_datetime_warns` keeps proving the preserved non-ISO warning; a `tz*` case that needs a naive value writes that value as a literal rather than through this command. In `tests/task/evals/fixtures/_common.sh` and `tests/task_create/evals/fixtures/_common.sh`, change `now_iso()` to the UTC command. In `tests/task/evals/grade.sh` and `tests/task_create/evals/grade.sh`, widen `iso_epoch` to parse a `Z` value as UTC with `date -j -u -f "%Y-%m-%dT%H:%M:%SZ"` before its local fallback, and widen `tests/task/evals/grade.sh`'s `ISO_RE` to accept a `Z` or offset designator on the time while still accepting a date-only value. In `tests/task/evals/evals.json`, change the `create` expectation that names `date +%Y-%m-%dT%H:%M:%S` to name `date -u +%Y-%m-%dT%H:%M:%SZ`. In `tests/task_fix/evals/fixtures/*/setup.sh` and `tests/task_auto_check/evals/fixtures/*/setup.sh`, plus `tests/task_auto_check/evals/fixtures/immediate_ready_citations_overturn/assets/task_snapshot.md`, convert every seeded `created` and `updated` literal to the `Z` form at its own instant (for example `2026-01-01T00:00:00` becomes `2026-01-01T00:00:00Z`), since these fixtures write literals directly and carry no `now_iso()` helper; the deliberately non-ISO `created: 2026/01/01` in `mechanical_lint_frontmatter` stays as the non-ISO case it stages. Move each seeded-value comparison to the converted literal in the same pass: `tests/task_fix/evals/grade.sh`'s three `updated_bumped` checks and `tests/task_auto_check/evals/grade.sh`'s `updated_changed` and `updated_unchanged` checks compare `updated` to the literal its fixture seeds, so each comparison moves to that literal's `Z` form (`2026-01-01T00:00:00Z` or `2026-01-02T00:00:00Z`); a comparison left on the old literal makes `updated_bumped` pass even when the run never bumps and makes `updated_unchanged` fail on every converted file. Re-run every eval set that reaches these fixtures and helpers — the `task` hub evals that grade `created` or `updated`, the `task_create` evals, the `task_fix` evals, and the `task_auto_check` evals — per the blast-radius rule in `TESTING.md`.

5. **Heal this repository.** Run the protocol over `tasks/` and `tasks/archive/` with the zone the user supplies, convert every `created` and `updated` value, and re-lint archive-inclusive to zero non-UTC findings.

**Out of scope:** date-only values (`YYYY-MM-DD`), which carry no time to convert and stay accepted, and any timestamp outside task frontmatter.

## Acceptance

- `lint.py` reports a warn on a staged task file whose `updated:` is naive local time and on one whose `updated:` carries a non-zero offset, and reports nothing for `Z` and `+00:00`; each warn names the no-bump rule; the non-zero-offset warn names its UTC target, and the naive warn names the zone ask in place of a target.
- A new `tz*` group in `tests/task/script_tests/run.sh` proves the linter cases, including a date-only value (`YYYY-MM-DD`) that draws no UTC warn, and the conversion snippets: a naive value with a named zone and a non-zero offset each convert to the expected UTC string, and a naive value converts to its own instant rather than the current time, which proves `updated` was not bumped.
- The base `task` skill's `<frontmatter>` instructs the UTC form and `<bump_updated>` names the timestamp-normalization exception, while the content-fix bump rule stays in force for genuine content fixes; the prior local-time instruction is the only passage superseded, and `task_fix`'s **Remediate.** bump sentence and `<authority>` parenthetical cite `<bump_updated>` instead of restating it, so one canonical statement remains.
  - `grep -rn 'date +%Y-%m-%dT%H:%M:%S' plugins/ai_dev/` returns no match, and each writer named in Approach's **Make UTC the written form.** step cites the base `<frontmatter>` timestamp command instead.
  - The base `<frontmatter>` example's `created:` and `updated:` values both carry the `Z` form.
- `task_fix/SKILL.md` carries the timestamp-correction protocol with the three snippets, the locale ask, the resolution rule, the inline-only routing that leaves conversion to the inline path, and the no-bump rule.
- A `task_fix` behavioral eval in `tests/task/evals/` stages a task file with a known naive `updated` value and carries `Europe/Berlin` in the prompt as the user's answer to the locale ask, which is the state the protocol runs in after that ask, and grades that the run rewrites the value to the expected UTC instant, leaves `updated` un-bumped, and re-lints clean. Item 4 proves the protocol text carries the locale ask.
- After the healing run, `python3 plugins/ai_dev/skills/task/scripts/lint.py --include-archive --quiet` reports zero non-UTC timestamps over `tasks/` and `tasks/archive/`, and `make lint` stays clean.
  - `plugins/ai_dev/skills/task/SKILL.md` `<lint>`'s **mechanically fixable lint finding set** carries a **UTC timestamp normalization** entry that states the zone ask, the surface-when-no-zone rule, and the no-bump pointer; the set's closing paragraph names that exception; and `grep -n 'UTC timestamp normalization' plugins/ai_dev/skills/task_fix/SKILL.md` finds the protocol's citation of it.
  - `grep -n 'date +%Y-%m-%dT%H:%M:%S' tests/task/script_tests/run.sh` returns no hit and `bash tests/task/script_tests/run.sh` passes with `c1_fully_valid_task_is_clean`, `fs4_conflicting_flags_and_file_only`, and `f4_non_iso_datetime_warns` green.
  - Both `_common.sh` `now_iso()` helpers emit the `Z` form; both `iso_epoch` helpers return the UTC epoch for `2026-11-03T13:26:31Z` with no local-offset shift; `tests/task/evals/grade.sh`'s `ISO_RE` matches `2026-11-03T13:26:31Z`; the `create` expectation in `tests/task/evals/evals.json` names `date -u +%Y-%m-%dT%H:%M:%SZ`; `grep -rEn '^(created|updated): [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$' tests/task_fix/evals/fixtures tests/task_auto_check/evals/fixtures` returns no match; the deliberate `created: 2026/01/01` in `mechanical_lint_frontmatter` stays non-ISO; each seeded-value comparison in `tests/task_fix/evals/grade.sh` and `tests/task_auto_check/evals/grade.sh` reads the `Z` form of the literal its fixture seeds (`2026-01-01T00:00:00Z` or `2026-01-02T00:00:00Z`); and the `task` hub, `task_create`, `task_fix`, and `task_auto_check` eval sets that reach these fixtures and helpers re-run green.
