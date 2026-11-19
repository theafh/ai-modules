#!/usr/bin/env bash
# family_job_post_write_check: the user names agent_spinner on a job the mock
# notes family owns. The run is open at the approval gate with one read-only
# finder per page. The fixture registers the family's one gate, notes_lint, and
# maps the pointer-only page notes/beta.md to it, so the post-write check on
# that page is a gate result rather than a check row.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/family/mock_notes" "$proj/notes"

cat > "$proj/family/mock_notes/SKILL.md" <<'SKILL'
---
name: mock_notes_family
description: Repair the notes pages under notes/.
---

# mock_notes_family

Hand the job to the `notes_repairer` agent. Its scope is every page under
`notes/`; do not narrow that scope unless the user supplies a narrower one.
The family's one gate is `notes_lint`; run it after every write.
Do not re-list the agent's checks; the agent owns them.
SKILL

cat > "$proj/notes_lint.sh" <<'LINT'
#!/usr/bin/env bash
# notes_lint.sh — the mock family's three checks over notes/ and any directory
# named on the command line (the ledger's known-positive control).
set -uo pipefail
exec python3 - "$@" <<'PY'
import os, re, sys

dirs = ["notes"] + [d for d in sys.argv[1:] if d]
rc = 0
for directory in dirs:
    if not os.path.isdir(directory):
        continue
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(directory, name)
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        last = None
        for line in text.splitlines():
            match = re.match(r"^(#+) ", line)
            if not match:
                continue
            level = len(match.group(1))
            if last is not None and level > last + 1:
                print("NOTES_CHECK_HEADINGS: %s: %d -> %d" % (path, last, level))
                rc = 1
            last = level
        for link in re.findall(r"\]\(([^)#]+)", text):
            if "://" in link or link.startswith("mailto:"):
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), link))
            if not os.path.exists(resolved):
                print("NOTES_CHECK_LINKS: %s: %s" % (path, link))
                rc = 1
        if re.search(r"\bTODO\b|CONTROL_MARKER", text):
            print("NOTES_CHECK_PLACEHOLDERS: %s" % path)
            rc = 1
sys.exit(rc)
PY
LINT
chmod +x "$proj/notes_lint.sh"

cat > "$proj/notes/alpha.md" <<'PAGE'
# Alpha

### Overview

The alpha workspace holds the release notes.
PAGE

cat > "$proj/notes/beta.md" <<'PAGE'
# Beta

See [the install guide](../INSTALL.md) for installation.
PAGE

cat > "$proj/notes/gamma.md" <<'PAGE'
# Gamma

See [the migration notes](missing-page.md) before upgrading.
PAGE

cat > "$proj/notes/delta.md" <<'PAGE'
# Delta

#### Details

The delta workspace lists the supported hosts.
PAGE

cat > "$proj/notes/epsilon.md" <<'PAGE'
# Epsilon

TODO: write this section.

See [the changelog](../CHANGELOG.md).
PAGE

printf '# Setup\n\nInstall the tool, then run it.\n' > "$proj/setup.md"
printf '# Changelog\n\nRelease history.\n' > "$proj/CHANGELOG.md"

commit_tree "$proj"
run_ledger "$proj" init --phase find --bound 600 --wave 5 \
  --gate "notes_lint=bash notes_lint.sh {controls}" \
  --owned-target notes/beta.md:mock_notes_family:notes_lint \
  --unit find:alpha --unit find:beta --unit find:gamma \
  --unit find:delta --unit find:epsilon >/dev/null

seal_open_run "$target" "$proj"
echo "family_job_post_write_check sandbox staged at $proj"
