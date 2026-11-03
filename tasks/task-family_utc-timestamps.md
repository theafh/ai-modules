---
description: "Make the task linter report every non-UTC created/updated value as fixable, and give task_fix a locale-ask protocol that converts them to UTC without bumping updated."
scope: plugins/ai_dev/skills/task
created: 2026-11-03T13:26:31
updated: 2026-11-03T13:26:31
status: open
reported-by: Andreas Hoffmann
---

# Heal Task Timestamps to UTC

## Goal

The task linter reports every `created` or `updated` frontmatter value that is not a UTC timestamp as a fixable finding, and `task_fix` carries a timestamp-correction protocol that asks the user which locale produced the reported times, converts each reported value to its UTC instant, and rewrites the files until the linter reports none. The conversion is a format change: it preserves the instant, so it does not bump `updated`. The behaviour ships in the task skill and `task_fix`, so every repository carrying a deployed task tree heals the same way, and this repository's live and archived task files are the first tree it heals.

## Context

- **The linter.** `plugins/ai_dev/skills/task/scripts/lint.py` holds the date check in `check_frontmatter`, under the `for date_field in ("created", "updated")` loop, and its `DATETIME_RE` accepts an optional `Z` or `[+-]HH:MM` designator. The check warns only on a non-ISO shape, so a naive local value and a non-zero-offset value both pass clean today.
- **The convention.** The base `task` skill's `<frontmatter>` tells every writer to run `date +%Y-%m-%dT%H:%M:%S` and copy its output, which is local time with no designator. Every current task file follows it: `grep -h '^updated:' tasks/*.md tasks/archive/*.md` returns 272 values, and none carries a designator.
- **The no-bump rule.** The base `task` skill's `<bump_updated>` and the linter's inline note that legacy provenance backfill does not bump `updated` say a content fix bumps `updated`. The archived [trustworthy-timestamps task](archive/task-family_trustworthy-timestamps.md) established the wall-clock `date` command that produced the local convention; this task keeps that command's wall-clock rule and changes the form it writes to UTC.
- **The consumer.** `plugins/ai_dev/skills/task_fix/SKILL.md` owns the mechanical remediation in its **Remediate.** step and the report shape in its `<output_contract>`. It is interactive, so it can ask the locale. Its escalated writer `auto_shaper_task` reads `task_fix` before editing, so the protocol reaches both paths.
- **The tests.** `tests/task/script_tests/run.sh` covers the linter mechanically, and `tests/task/evals/` covers the skill prose through the eval runner.
- Python 3 is a standing dependency and `zoneinfo` is stdlib from 3.9, so the conversion adds no dependency.

## Approach

1. **Report non-UTC values.** In `check_frontmatter`'s date loop in `lint.py`, replace the format-only test with a UTC test. A value is clean when it carries `Z` or a zero offset (`+00:00` or `+0000`); it is reported when it carries no designator or a non-zero offset. Report it as a warn whose message names the value, the UTC target, and the no-bump rule, matching the inline note shape the provenance findings already use. Keep the existing non-ISO warning for a value that is not a datetime at all.

2. **Make UTC the written form.** In the base `task` skill's `<frontmatter>`, change the timestamp instruction to obtain UTC with `date -u +%Y-%m-%dT%H:%M:%SZ` and state that the canonical form carries the `Z` designator. In `<bump_updated>`, add the timestamp-normalization exception: converting a timestamp's representation to UTC preserves the instant, so it does not bump `updated`, and this is the one format change the exception covers.

3. **Give `task_fix` the protocol.** In `task_fix/SKILL.md`, add a **Timestamp correction protocol** passage under the **Remediate.** step. It collects the linter's non-UTC findings, asks the user for the zone that produced the naive values (an IANA name such as `Europe/Berlin`, or a fixed offset), converts a non-zero-offset value directly, converts a naive value with `zoneinfo`, writes the `Z` form, leaves `updated` un-bumped, re-lints archive-inclusive to zero, and reports each converted file with the zone used. It carries these snippets:

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

4. **Heal this repository.** Run the protocol over `tasks/` and `tasks/archive/` with the zone the user supplies, convert every `created` and `updated` value, and re-lint archive-inclusive to zero non-UTC findings.

**Out of scope:** date-only values (`YYYY-MM-DD`), which carry no time to convert and stay accepted, and any timestamp outside task frontmatter.

## Acceptance

- `lint.py` reports a warn on a staged task file whose `updated:` is naive local time and on one whose `updated:` carries a non-zero offset, and reports nothing for `Z` and `+00:00`; each warn names the no-bump rule.
- A new `tz*` group in `tests/task/script_tests/run.sh` proves the four linter cases and the conversion snippets: a naive value with a named zone and a non-zero offset each convert to the expected UTC string, and a naive value converts to its own instant rather than the current time, which proves `updated` was not bumped.
- The base `task` skill's `<frontmatter>` instructs the UTC form and `<bump_updated>` names the timestamp-normalization exception; the prior local-time instruction and the content-fix-bumps reading are superseded, so one canonical statement remains.
- `task_fix/SKILL.md` carries the timestamp-correction protocol with the three snippets, the locale ask, the resolution rule, and the no-bump rule.
- A `task_fix` behavioral eval in `tests/task/evals/` stages a task file with a known naive timestamp and a named zone, and grades that the run asks for the locale, rewrites the value to the expected UTC instant, leaves `updated` un-bumped, and re-lints clean.
- After the healing run, `python3 plugins/ai_dev/skills/task/scripts/lint.py --include-archive --quiet` reports zero non-UTC timestamps over `tasks/` and `tasks/archive/`, and `make lint` stays clean.
