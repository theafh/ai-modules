#!/usr/bin/env bash
# Stage the priming_basics fixture: one source document and the terms a
# faithful SPR must not invent.
set -euo pipefail

target="${1:?target dir required}"
mkdir -p "$target"

cat > "$target/source.md" <<'SOURCE'
# Priming and Recall

Priming is the process by which a cue activates related knowledge before a
task begins. In language models the cue is a token sequence, and the activated
state is a distribution over likely continuations. A good cue narrows that
distribution without closing it.

Retrieval practice strengthens recall more than rereading does. A learner who
attempts to recall a fact and fails, then checks the answer, remembers it
better than a learner who reads the same fact twice. The effort of retrieval,
not the exposure, produces the gain.

Spacing spreads practice across time. The same total study time produces more
durable memory when it is divided into sessions separated by sleep or by other
work. Massed practice feels more productive because it produces fluency during
the session, but that fluency fades quickly.

Interleaving mixes related problem types instead of blocking one type at a
time. It feels harder and produces more errors during practice, yet it improves
the learner's ability to choose the right method later. The benefit comes from
practising discrimination, not from repetition alone.
SOURCE

cat > "$target/forbidden.txt" <<'FORBIDDEN'
Ebbinghaus forgetting curve
spaced repetition software
ninety percent retention
FORBIDDEN
