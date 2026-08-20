---
description: Make the append-only wiki log tolerate breakage from a logged entry: heading uniqueness, a repair-not-rewrite carve-out, and a duplicate-heading lint check, rolled out to existing wikis.
scope: plugins/knowledge_management
created: 2026-06-18T19:33:04
updated: 2026-08-20T17:47:52
status: checked
reported-by: Andreas Hoffmann
---

# Let a wiki log entry be repaired when it breaks lint, and keep entry headings unique

## Goal

Make the append-only `log.md` contract tolerate the one situation it currently has no answer for: a logged entry that introduces a structural break, the canonical case being a heading byte-identical to an earlier same-day entry, which trips markdownlint MD024 (`no-duplicate-heading`) and can block a commit. The end state is:

- The log stays append-only **in substance**: past entries are never reworded, reordered, or deleted.
- An entry **may be edited to repair a structural or lint break it introduced** (disambiguate a colliding heading, fix malformed markdown), provided the repair preserves what the entry records and its position in the file.
- Going forward, log-entry headings are **unique by construction**: every new heading carries a timestamp (`## [YYYY-MM-DD HH:MM] …`), so two entries collide only in the rare same-minute case.
- Existing date-only entries stay valid as-is: the timestamp applies to **new** entries only, and legacy `## [YYYY-MM-DD] …` entries are never auto-rewritten. A unique legacy heading is clean. A **pre-existing duplicate** (which the old log could already contain, since uniqueness was never checked) is **surfaced** by the new check but not swept up automatically: it is repaired on demand (see below). The check never flags an entry merely for lacking the `HH:MM` component.
- **Surface, don't auto-fix history.** The duplicate check reports collisions at a non-driving severity so a routine `wiki_fix` pass does not rewrite a backlog of historical headings. Repair is invoked on demand: when an operator asks to clean duplicate headings, or when a duplicate actually blocks work (a commit failing markdownlint MD024). The repair disambiguates the colliding heading with a minimal non-time suffix and never fabricates a timestamp for a past entry.
- The format/prevention reaches **both new and existing wikis** on the next `wiki_fix` run with no per-wiki migration; the historical-duplicate cleanup is deliberately not automatic.

This task is the wiki-skill-source counterpart of a fix that was applied by hand in a downstream wiki: a `wiki_wrapup` session-wrapup entry collided with an earlier same-day wrapup heading and was disambiguated to clear MD024. The append-only rule as written gave no explicit permission to touch a prior entry and no convention to keep headings distinct, so the situation recurs across every wiki this plugin manages.

(All code references below anchor on a greppable label rather than a line number, per the backlog's soft-pointer convention.)

## Context

### What the rule says today and where it lives

The append-only-log idea is stated in several places; a coherent change touches all of them:

- `references/template_log.md` — the canonical `log.md` preamble copied into every wiki. The block beginning `> Chronological record of wiki changes. Append-only.` is the strongest statement, and the next line gives the heading format: `` > Format: `## [YYYY-MM-DD] action | subject` ``.
- `references/template_schema.md` — the conventions list, with the bullet beginning `` Every operation that creates or updates wiki files must be appended to `log.md` `` (the rule in the schema master).
- `skills/wiki/SKILL.md` — the architecture-diagram annotation `# Chronological action log (append-only, rotated yearly)`; the `<appending_to_log>` section, which defines "Append-only" as newest-at-bottom and how to anchor a new entry; two heading-format instantiations (`ingest | Source Title` in `<update_navigation>`, `lint | N blocking, N warn, N info` in `<inline_iteration_loop>`); and the `<rotate_log_at_500>` pitfall.

Two observations from that inventory:

1. **No rule addresses repairing a past entry.** The entire policy is append-a-new-entry-at-the-bottom. The closest text, `<appending_to_log>`, governs how to append without inverting order, not how to fix an entry already written. The two `## Update Policy` sections (in `template_schema.md` and the `<write_or_update_pages>` block of `SKILL.md`) are about reconciling contradictory **page** content and never mention the log.
2. **The heading convention guarantees no uniqueness.** The heading is built only from date, action, and subject. Two same-day entries with the same action and subject produce identical `## [...]` headings. Count-shaped subjects are the worst case: a `wiki_wrapup` entry like `## [2026-06-18] session-wrapup | 0 new, 2 extended, 0 contested` repeats verbatim whenever two wrapups in one day land on the same counts.

### Why duplicate headings are not caught or fixed today

- The wiki linter has **no duplicate-heading check** on `log.md`. `check_log_rotation` only counts `## [` lines and emits an info finding past 500 entries. `check_markdown_style` (the `HEADER_RE` header checks) covers level-skipping and trailing punctuation, not uniqueness. `check_verbatim_boilerplate` only compares the preamble above the first `##` heading, so entry headings are out of its scope. Duplicate-heading detection is therefore purely markdownlint's job (MD024).
- The only markdownlint config in the repo is `.markdownlint.jsonc` (`default: true`, overriding only MD033/MD013/MD041). MD024 runs at defaults (`siblings_only` unset) and `log.md` is not excluded. **A markdownlint-config tweak alone cannot fix this**: the log is a flat list of sibling `## [...]` headings, so `siblings_only: true` would not help (the colliding entries are already siblings). The only config-only escapes are disabling MD024 or excluding `log.md`, both of which discard the check rather than reconcile the breakage. The genuine fix is behavioral.
- The `auto_shaper_wiki` agent explicitly treats every dated entry as append-only and **out of scope for its scaffold diff** (the comment scoping the `log.md` diff to the preamble, and the "out of scope for the scaffold diff entirely" note), and its only log fix move, `<fix_log_preamble_drift>`, restores the preamble and leaves entries below as-is. So even where a collision exists, the agent will not touch it unless (a) the linter emits a finding the agent can act on through `<relint_until_clean>`, and (b) a fix move permits repairing an entry.

### The propagation reality (this answers "should it go in the schema master?")

Editing the **schema master alone does not reach existing wikis.** `init_wiki.sh` copies `template_schema.md` into the wiki as a standalone `SCHEMA.md` once at init (the `cp "$REFS/template_schema.md" "$WIKI/SCHEMA.md"` step) and then refuses to ever overwrite an established wiki (the `# Don't clobber an established wiki.` guard that exits with `refusing to overwrite existing wiki`). There is no `--update`/`--force`, no reconcile, and no checksum re-sync. After init every wiki owns its local `SCHEMA.md`, and the agent and linter read that local file, never the skill template. Any edit to the `SCHEMA.md` **body** (including the `Every operation that creates or updates wiki files must be appended` convention) is invisible to existing wikis.

What **does** reach existing wikis on the next `wiki_fix` run:

1. **Plugin code.** The `auto_shaper_wiki` agent prompt and `lint.py` ship with the plugin and run against every wiki regardless of its local files. A rule encoded there applies everywhere with no migration.
2. **The `log.md` preamble.** `lint.py`'s boilerplate check has a slot naming `template_log.md`, so it compares each wiki's `log.md` preamble (everything above the first `## [`) against the canonical template and flags drift; the agent's `<fix_log_preamble_drift>` then restores the preamble verbatim while leaving entries untouched. So a change to the `template_log.md` **preamble** propagates to existing wikis through this boilerplate-drift to fix path.

Consequence for placement: the carve-out and the uniqueness convention belong in the **`log.md` preamble plus plugin code (agent + linter)**, not (only) in the schema master. The schema-master edit is for new-wiki coherence; do not rely on it to reach existing wikis.

### Dedup and related work

No existing task covers append-only-log repair, heading uniqueness, duplicate-heading handling, or MD024. Distinct neighbors: [wiki_log-entries-only-on-changes.md](archive/wiki_log-entries-only-on-changes.md) (whether to write an entry at all, now shipped), [wiki_log-rotation-and-retrieval.md](wiki_log-rotation-and-retrieval.md) (rotation and entry-aware reads), [wiki_metadata-in-headings.md](wiki_metadata-in-headings.md) (heading vocabulary). [task-family_decided-general-positive-body.md](archive/task-family_decided-general-positive-body.md) already frames "append-only by design" surfaces as a carve-out from the rewrite-in-place rule, which supports the framing here.

Co-edit coordination: [wiki_log-action-enum-coverage.md](archive/wiki_log-action-enum-coverage.md) rewrites the `Actions:` line inside the same verbatim-enforced `template_log.md` preamble this task adds the heading format and the repair carve-out to. Every edit inside that slot makes each existing wiki's `log.md` preamble drift and costs it one boilerplate warn until its next audit realigns it — the designed propagation channel, so landing both preamble edits in one change spends it once instead of twice. Word this task's lines against whichever preamble text is current when it builds.

Co-edit coordination (settled order): two later siblings co-edit the same `template_log.md` preamble and the `<appending_to_log>` block this task's repair carve-out lives in, and **this task lands first**. [wiki_log-session-entry-consolidation.md](wiki_log-session-entry-consolidation.md) then scopes append-only to *settled* (prior-session) entries and lets a session consolidate its own in-progress entry; it supersedes this task's absolute "never reword, reorder, or delete a past entry's recorded content" phrasing (in Approach half 2) with the settled-entry-scoped form and composes it with this task's repair carve-out as one qualification. Word this task's carve-out so it stays composable once that scoping lands on top of it. [wiki_log-scope-wiki-changes-only.md](wiki_log-scope-wiki-changes-only.md) adds a subject-scope group to the same preamble. All three preamble edits share one boilerplate-drift channel, so landing them in one batch spends that drift once.

## Approach

Two coordinated halves: **prevent** (heading uniqueness) and **permit, detect, fix** (repair carve-out, lint check, agent fix move). Then place each half on the channel that reaches existing wikis.

1. **Timestamped heading format (prevention) — decision: scheme (C).** Add a time component to the log-entry heading so it is unique by construction: `## [YYYY-MM-DD HH:MM] action | subject` (24-hour, same timezone as the existing date, i.e. local). This was chosen over (A) a parenthetical disambiguator-on-collision and (B) a sequence counter because it removes the collision at the source for every action with no per-entry collision-checking. The accepted cost: the format string changes in every place a heading is written or documented, and every heading grows by six characters.

   Primary home for the convention is the `template_log.md` preamble (the `` > Format: `` line), which propagates to new wikis at init and to existing wikis via the boilerplate path (half 5). Then sweep every site that writes or documents a heading and add `HH:MM`. Enumerate them with `grep -rn '## \[' plugins/knowledge_management`; today they are:
   - `skills/wiki/references/template_log.md` — the `` > Format: `` line (and the `{{TODAY}}` seed entry below it; see caveat).
   - `skills/wiki/SKILL.md` — the `<appending_to_log>` section and the two instantiations (`ingest | Source Title` in `<update_navigation>`, `lint | N blocking, N warn, N info` in `<inline_iteration_loop>`).
   - `skills/wiki_wrapup/SKILL.md` — the `session-wrapup | N new, N extended, N contested` instantiation (the action behind the motivating collision).
   - `skills/wiki_import/SKILL.md` — the `import | Source Title — …` instantiation.
   - `agents/auto_shaper_wiki.md` — the `<append_audit_log_entry>` `audit | …` instantiation, plus the `## [YYYY-MM-DD]` references in its scaffold-diff comments.
   - `skills/wiki/references/lint_checks.md` — the `lint | …` example.
   - `skills/wiki/references/template_schema.md` — the `Every operation that creates or updates wiki files must be appended` bullet (no format string, but align any wording).

   Implementation caveats:
   - `lint.py` detects entries by `line.startswith("## [")`, which is unaffected by adding time inside the brackets, so keep date and time in one `[YYYY-MM-DD HH:MM]` bracket.
   - The incremental-audit scoping reads the newest prior `audit` entry (its `Audit baseline:` line) as prose when deriving the page-walk scope; a time component inside the bracket leaves that lookup intact as well — re-confirm it alongside the bare-`[YYYY-MM-DD]` assumption grep below.
   - `init_wiki.sh` fills the seed entry through a date-only `{{TODAY}}` substitution. Either leave the single seed entry date-only (no collision risk) or extend the substitution to a date+time stamp; pick one and apply it.
   - Before changing the format, grep the plugin for any code or regex that assumes a bare `[YYYY-MM-DD]` in a log heading; the map found none beyond the `## [` prefix check, but confirm.

2. **Repair carve-out (permission).** Home: the `template_log.md` preamble plus the `<appending_to_log>` section and the architecture-diagram annotation of `SKILL.md`. Add a precise rule: the log is append-only in substance, so never reword, reorder, or delete a past entry's recorded content; but an entry may be edited to repair a structural or lint break it introduced (for example disambiguating a colliding heading or fixing malformed markdown), as long as the repair does not change what the entry records or where it sits. Make the "repair the breakage" (allowed) versus "rewrite the substance" (forbidden) line explicit. Cross-reference the append-only-by-design framing in [task-family_decided-general-positive-body.md](archive/task-family_decided-general-positive-body.md). A later sibling scopes this "never reword, reorder, or delete" phrasing to settled entries; see the settled-order co-edit note in Context and keep the wording composable with it.

3. **Linter: add a duplicate-heading check on `log.md` (surface only, non-driving).** In `lint.py` add a check (e.g. `check_log_heading_uniqueness`) that scans `log.md` for repeated `## [` headings and emits a finding under the distinct finding key `log-heading` naming the collision; register it in the same run registry as `check_log_rotation`. Keep the key distinct from `check_log_rotation`'s `log` on purpose: the per-finding acceptance store in [wiki_lint-accepted-info-suppression.md](wiki_lint-accepted-info-suppression.md) whitelists `log` for its two-field (path-only) acceptance form on the premise that a `log` finding emits at most one Issue per path, and this check emits one per distinct collision, several per `log.md`, so reusing `log` would break that premise and let one acceptance swallow unrelated findings. Emit it at **`SEV_INFO`**, not `WARN`/blocking: INFO surfaces the collision in the report and the agent's audit log without failing the exit code or driving the `<relint_until_clean>` loop to auto-rewrite history. That loop's clean bar is rewritten by [wiki_auto-shaper-internal-contradictions.md](archive/wiki_auto-shaper-internal-contradictions.md), whose carve-out covers the contested-page warn only — so INFO stays the only non-driving level for this check whichever task lands first, and the choice needs no revisiting. This is the decided behaviour — the check reports duplicates (including pre-existing legacy ones) so they are visible, but it does not trigger an automatic mass-repair on a routine pass. A `WARN`/blocking severity would force the agent loop to rewrite the backlog and is explicitly rejected.

   Keep the check to **duplicate detection only**: compare full heading text and fire solely when two headings are byte-identical. It must NOT validate heading *format* — no rule that an entry must carry the `HH:MM` component — so a unique legacy heading stays clean regardless of whether it is date-only or timestamped, and an entry is never flagged for the format change alone. (The linter checks neither log-heading format nor uniqueness today; this task adds uniqueness surfacing only.) Generalizing to other malformed-markdown-in-entries detection is optional and can be deferred to stay atomic. Document the check in `references/lint_checks.md` and name it in the `SKILL.md` lint severity-bucket lists.

4. **Agent: add an on-demand log-entry repair move and narrow the append-only exclusion.** In `auto_shaper_wiki.md`, add a fix move as a sibling to `<fix_log_preamble_drift>` that disambiguates a colliding entry's heading by appending a minimal non-time suffix (e.g. `(2)`) without altering the entry body, the recorded substance, or the entry order. Do **not** fabricate a timestamp for a past entry whose real time is unknown. This move is **on demand, not loop-driven**: because the duplicate finding is INFO (half 3), a routine audit/relint pass does not invoke it; it runs only when explicitly requested (an operator asks to clean duplicate headings) or when a duplicate is actually blocking work. Add a narrow exception to the "entries are append-only, out of scope for the scaffold diff" language so this targeted repair is permitted while wholesale entry editing and any automatic sweep of historical entries stay out of scope.

5. **Rollout and placement (make the channels explicit in the implementation).**
   - The format/prevention and the surfacing check ship as plugin code (the agent prompt and `lint.py`) and apply to every wiki on its next `wiki_fix` run with no per-wiki migration: new entries are timestamped everywhere, and any duplicate is surfaced at INFO.
   - The repair move (half 4) also ships, but is **on demand by design**: surfacing a duplicate does not auto-repair it, so an established wiki's historical duplicates are reported, not rewritten, until someone asks or a duplicate blocks work.
   - Halves 1 and 2, written into the `template_log.md` **preamble** (above the first `## [`), propagate to new wikis at init and to existing wikis through the boilerplate-drift to `<fix_log_preamble_drift>` path. Keep the new lines above the first `## [` so they stay inside `lint.py`'s boilerplate-checked region; otherwise the propagation channel is lost.
   - The edit to the `Every operation that creates or updates wiki files must be appended` bullet in `template_schema.md` is for new-wiki coherence only.
   - Do **not** edit `.markdownlint.jsonc` to silence MD024 or exclude `log.md`; that discards the check instead of reconciling the breakage.

**Non-goals / follow-ups (kept out to keep this atomic):**

- Updating `wiki_wrapup`, `wiki_import`, and every other entry-writing site to emit the timestamp is **in scope** here, not a follow-up: scheme (C) makes the format universal, so all writers move together (see Approach half 1).
- **No heading-format-conformance check.** The linter must not require the timestamp on a heading or otherwise validate entry format; legacy date-only entries stay valid and unflagged for format. The only new log check is duplicate detection.
- **No automatic rewrite of historical duplicates.** The duplicate check is surface-only (INFO); a routine `wiki_fix` pass must not sweep and rewrite a backlog of pre-existing duplicate headings. Cleanup is on demand.
- A markdownlint-config change is rejected, not deferred.
- Log rotation and other log behaviors are untouched.

## Acceptance

- The `template_log.md` preamble states both (a) the timestamped heading format `## [YYYY-MM-DD HH:MM] action | subject` and (b) the repair-not-rewrite carve-out, and both sit above the first `## [` so they remain inside `lint.py`'s boilerplate-checked region.
- Every site that writes or documents a log heading carries the timestamp: the `<appending_to_log>` section and both instantiations of `SKILL.md` (`<update_navigation>` ingest, `<inline_iteration_loop>` lint), the `session-wrapup` example in `wiki_wrapup`, the `import` example in `wiki_import`, the `audit` example in `auto_shaper_wiki.md`, and the example in `lint_checks.md`. A `grep -rn '## \[' plugins/knowledge_management` shows the timestamped form at each. The `Every operation that creates or updates wiki files must be appended` bullet of `template_schema.md` is aligned.
- The `{{TODAY}}` seed-entry decision (date-only vs date+time) is made and applied in `init_wiki.sh`.
- `lint.py` has a registered check that emits a finding when `log.md` contains two identical `## [` headings, at **`SEV_INFO`** under the distinct finding key `log-heading` (non-blocking, non-driving); a bare `python3 scripts/lint.py` surfaces it and the exit code is unchanged.
- A legacy `log.md` of unique **date-only** entries lints clean: no format or missing-timestamp finding is raised. The new check fires only on an actual duplicate, never on the absence of `HH:MM`.
- A legacy `log.md` that already contains a duplicate heading is **surfaced** (one INFO finding) but **not auto-rewritten** by a routine `wiki_fix`/audit pass.
- `references/lint_checks.md` documents the check and the `SKILL.md` severity buckets name it.
- `auto_shaper_wiki.md` has an on-demand fix move that disambiguates a duplicate log heading with a minimal non-time suffix, without altering entry substance or order and without fabricating a timestamp; the append-only exclusion language permits this targeted repair while keeping wholesale entry editing and any automatic historical sweep out of scope.
- A fixture or manual check proves the on-demand path end to end: a `log.md` with two identical headings surfaces one INFO finding; a routine audit pass leaves it unchanged; an explicit repair disambiguates the later heading (body and order unchanged, no fabricated time) and relints clean.
