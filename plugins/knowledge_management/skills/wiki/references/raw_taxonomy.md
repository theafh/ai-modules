# Raw Source Taxonomy

Reference for the `raw/` subtree — what each canonical bucket is for, and how to classify a source into one of them. Consulted by the wiki skill on ingest and by the `auto_shaper_wiki` agent when it surfaces extra `raw/<kind>/` subdirectories for the user to route.

The canonical *set* of buckets is whatever `scripts/init_wiki.sh` materializes today (it is the script that creates a new wiki's raw subtree, and the set evolves with the skill). This file defines *what each bucket means* and how to pick between them.

## Buckets

| Bucket | What lives here | Typical origin | Body shape |
| --- | --- | --- | --- |
| `raw/articles/` | Externally-published written content — blog posts, news, opinion pieces, vendor write-ups, online essays. | Public URL to the original article, in `source_url:`. | Long-form prose; one author or editorial voice. |
| `raw/papers/` | Academic and technical papers — arxiv, conference proceedings, journal articles, vendor white papers, formal technical reports. | Public URL to the PDF or paper page in `source_url:` (`arxiv.org/abs/...`, doi, etc.). | Structured prose with abstract, sections, citations. |
| `raw/meetings/` | Meeting notes, interviews, recorded calls, and spoken-word transcripts — podcasts, talks, conference recordings, video interviews. | Recording URL in `source_url:` when external; a repo-tracked recording or transcript takes a repo-relative `source_path:`; an internal meeting with no stored file takes neither. | Speaker turns, timestamps, Q&A markers, or verbatim spoken language. |
| `raw/notes/` | Internal memos, discussion writeups, ad-hoc observations, internal docs not published externally. | Usually neither field — an internal doc the repo tracks takes a repo-relative `source_path:`; a memo with no stored file takes neither and is captured by the body excerpt. | Memo / writeup framing; author voice; no speaker turns. |
| `raw/assets/` | Binary attachments referenced by other raw files — images, diagrams, slide exports, PDFs that are illustrations rather than content. | Optional. | Not text; frontmatter optional. |

## Classification heuristics

Apply in order. The first match wins. "A remote `source_url:`" below means an externally-published
source reached by a real remote URL; an in-repo source instead carries a repo-relative `source_path:`,
and an out-of-repo local file carries neither field (see the origin contract in `template_schema.md`).
The origin field never overrides body shape: an in-repo or path-less source is bucketed by what its
body *is*, exactly as an external one is.

1. **Binary file** (image, slides, diagram, illustration PDF) → `raw/assets/`.
2. **A remote `source_url:` to a podcast, talk, conference, recorded interview, or video** → `raw/meetings/`.
3. **A remote `source_url:` to a PDF, arxiv page, or formal paper** → `raw/papers/`.
4. **A remote `source_url:` to a published article, blog post, news item, vendor write-up, or online essay** → `raw/articles/`.
5. **No remote `source_url:` (an in-repo `source_path:`, or neither field for an out-of-repo local file), body framed as speaker turns or a verbatim transcript** → `raw/meetings/` (the spoken-word *medium* is what matters; an internal meeting transcript still belongs here).
6. **No remote `source_url:` (an in-repo `source_path:`, or neither field), body framed as a memo, writeup, observation, or summary** → `raw/notes/`.

## Edge cases and disambiguation

- **A transcript of a private internal meeting** → `raw/meetings/`. The medium (spoken word) determines the bucket; the publication status does not.
- **A written-up summary of a private meeting** → `raw/notes/`. A summary in the author's voice is a writeup, not the raw spoken record.
- **An article that embeds an interview transcript** → `raw/articles/`. The primary published form is the article; the embedded transcript is part of it.
- **A vendor white paper that is also a marketing piece** → `raw/papers/` if it has formal sections and citations; otherwise `raw/articles/`.
- **A paste of unknown provenance** → classify by *body shape* (prose → articles, transcript → meetings, memo → notes). File the bucket by content kind, not by the fact that it was pasted.
- **A file that genuinely fits two buckets equally** → surface to the user rather than pick. Forced bucketing makes the source harder to re-find later.

## Adding a new bucket

A new canonical bucket means three coordinated edits, in this order:

1. Add the `mkdir` line to `scripts/init_wiki.sh` so new wikis materialize the bucket.
2. Add the bucket row to the **Buckets** table above and update the classification heuristics if the new bucket changes precedence.
3. Run `python3 scripts/lint.py` against a test wiki and confirm no new findings.

The `auto_shaper_wiki` agent reads `init_wiki.sh` to learn the current canonical set and reads this file for the *meaning* of each bucket; both sources update together.
