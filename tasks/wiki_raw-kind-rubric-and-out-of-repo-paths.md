---
description: Document the `raw/<kind>/` selection rubric and extend `source_path:` to cover out-of-repo local files in the wiki SCHEMA template and skill.
scope: plugins/knowledge_management
created: 2026-05-28T19:25:04
updated: 2026-06-02T20:57:24
status: open
---

# Document the `raw/` kind rubric and out-of-repo `source_path:` semantics

## Goal

The wiki convention for ingesting raw artifacts grows two documented rules so different authors pick the same `raw/<kind>/` slot and represent local out-of-repo files consistently:

1. A **`raw/<kind>/` selection rubric** that says exactly which kind covers which artifact type.
2. **Extended `source_path:` semantics** that permit absolute or `~`-prefixed paths for local files outside the repo, with a portability caveat.

## Context

This is one of a family of **generalisable refinements** to the wiki skills + `wiki_auto_shaper` agent. The trigger was a concrete friction point during the 2026-05-26 audit of `wiki/todos/bet-assistant-updates.md` in the `ai-assets` repo, but the rule is stated globally so it applies to every user of the wiki skills, not just the originating case.

Two adjacent gaps in the raw-artifact convention surfaced during that ingest:

- **Kind selection ambiguity.** Kinds are `articles | assets | meetings | notes | papers`. A chat-session transcript could plausibly land under `meetings` or `notes`. Different authors will pick differently, fragmenting the convention.
- **No documented field for out-of-repo local files.** `source_path:` is documented for in-repo mirrors; `source_url:` is documented for external URLs. A local file outside the repo (e.g., `~/.claude/projects/.../session.jsonl`) fits neither. The 2026-05-26 ingest used `source_path:` with an absolute `~`-prefixed path, which works but is undocumented and non-portable across machines.

Files involved:

- [plugins/knowledge_management/skills/wiki/SKILL.md](../plugins/knowledge_management/skills/wiki/SKILL.md) — or the SCHEMA template the skill writes.
- Target-wiki `SCHEMA.md` template inside the wiki skill bundle — extend `source_path:` documentation and add the rubric.

Related task: [wiki_provenance-via-raw-and-sources.md](wiki_provenance-via-raw-and-sources.md) (this task supplies the kind-picking rubric that task assumes).

## Approach

1. **`plugins/knowledge_management/skills/wiki/SKILL.md` (or the SCHEMA template)** — document the `raw/<kind>/` selection rubric:
   - `articles` — published web articles, blog posts, news.
   - `papers` — academic papers, RFCs, formal specs.
   - `meetings` — recorded meetings, calls, chat sessions, interviews; **any multi-turn dialogic source**.
   - `notes` — unstructured text artifacts: personal notes, scratch pads, internal drafts, in-repo doc mirrors.
   - `assets` — non-text artifacts: images, audio, video, diagrams.
2. **SCHEMA frontmatter docs** — extend `source_path:` semantics to permit:
   - Repo-relative paths (existing behaviour, for in-repo mirrors).
   - Absolute paths (`/Users/...`, `/home/...`).
   - `~`-prefixed paths (`~/.claude/projects/.../session.jsonl`).

   Document the use case. Note that such paths are non-portable across machines, so the sidecar body must carry enough excerpted content to be useful without the original file.
3. **SCHEMA template** — optionally add a note that out-of-repo local sources should mark their host machine in the body, e.g., "Local file on the author's workstation; full transcript excerpted below."

## Acceptance

- Both the wiki skill and the wiki SCHEMA template carry the rubric and the extended `source_path:` semantics.
- Chat-session ingestion fixture through `wiki_import` with no kind hint → lands under `raw/meetings/` per the rubric, uses `source_path:` for an out-of-repo absolute path, body excerpt large enough to stand on its own.
- `make lint` clean on all edited files.
- `tests/wiki/run_all.sh --layer2` passes.
