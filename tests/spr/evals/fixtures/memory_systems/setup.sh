#!/usr/bin/env bash
# Stage the memory_systems fixture: one source document and the terms a
# faithful SPR must not invent.
set -euo pipefail

target="${1:?target dir required}"
mkdir -p "$target"

cat > "$target/source.md" <<'SOURCE'
# Memory Systems in the Brain

Working memory holds a small amount of information for a short time. It is
limited to roughly four chunks, and it decays within seconds unless the
information is rehearsed or refreshed. Working memory supports reasoning by
keeping the current problem in view.

Long-term memory divides into explicit and implicit forms. Explicit memory
covers facts and events and depends on the hippocampus and the surrounding
cortex. Implicit memory covers skills and habits and depends on the basal
ganglia and the cerebellum. The two systems can be damaged independently.

Consolidation turns a fragile trace into a stable one. During sleep the
hippocampus replays sequences to the cortex, and the cortex gradually takes
over the representation. This is why sleep after learning improves retention
more than an equal amount of waking rest.

Forgetting is not only decay. Interference from similar material impairs
retrieval, and retrieval itself can weaken competing memories. The brain
appears to trade detail for generalisation, keeping the gist of many
experiences rather than every instance.
SOURCE

cat > "$target/forbidden.txt" <<'FORBIDDEN'
seven chunks
prefrontal cortex ablation
REM sleep only
FORBIDDEN
