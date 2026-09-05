"""Skill discovery shared by skill_doctor's bundled scripts.

Carries one implementation of the walk, the frontmatter name read, the
plugin-host lookup, the `<family>` block parse, family resolution over a
token, and the comparison grouping the sibling checks compare within.

Both `resolve_scope.py` and `discovery_safety.py` load this module, so the
two cannot drift apart: each used to carry its own `split_frontmatter` and
`SKILL_FILE_RE`, which had already diverged in text while staying equivalent
only because `Path.read_text` normalises line endings before either copy
ran. Deriving the grouping here also keeps `discovery_safety.py` correct with
no grouping argument from its caller, where an argument copied out of the
resolver payload would put every family run's correctness behind a prose
step and degrade silently whenever that step was missed.

Reads files. Edits nothing.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

# A hub's <family> block is located structurally rather than by first
# occurrence: the opening tag owns its line, tolerating leading indentation
# and a trailing HTML comment, and the search runs over a probe copy whose
# code spans are blanked. A positional `<family>(.*?)</family>` match instead
# started at the first literal mention anywhere in the body, so a hub that
# documents its own tag in prose contaminated the family set.
FAMILY_OPEN_LINE_RE = re.compile(
    r"^[ \t]*<family>[ \t]*(?:<!--.*?-->[ \t]*)?$",
    re.IGNORECASE | re.MULTILINE,
)
FAMILY_CLOSE_RE = re.compile(r"</family>", re.IGNORECASE)
# A member is the leading backticked token of a block list item, not every
# backticked word in the block: an entry reading ``- `x`: bumps `updated` ``
# declares `x` alone.
FAMILY_ENTRY_RE = re.compile(r"^[ \t]*[-*+][ \t]+`([a-z][a-z0-9_]*)`", re.MULTILINE)
FENCE_OPEN_RE = re.compile(r"^[ \t]*(`{3,}|~{3,})")
FENCE_CLOSE_RE = re.compile(r"^[ \t]*(`{3,}|~{3,})[ \t]*$")
INLINE_CODE_RE = re.compile(r"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)")
FRONTMATTER_NAME_RE = re.compile(
    r"^name:\s*(.+?)\s*$",
    re.MULTILINE,
)
# The harness matches the skill file case-insensitively (`/^skill\.md$/i`
# over the basename), so the walk matches it the same way rather than
# pinning the uppercase spelling this repository happens to use.
SKILL_FILE_RE = re.compile(r"^skill\.md$", re.IGNORECASE)
# Preferred spelling when one directory holds more than one skill file. The
# harness picks one and logs the ambiguity; resolution stays deterministic
# here and discovery_safety.py reports the ambiguity as a finding.
PREFERRED_SKILL_FILE = "SKILL.md"

# Version-control, dependency, build, and cache directories hold no skill a
# repository authors. Pruning them keeps the walk cheap and keeps a vendored
# copy of someone else's skill out of the target set.
SKIP_DIRS = frozenset(
    {
        ".git",
        ".hg",
        ".svn",
        ".bzr",
        "node_modules",
        "bower_components",
        "vendor",
        ".venv",
        "venv",
        ".tox",
        ".nox",
        "__pycache__",
        ".mypy_cache",
        ".pytest_cache",
        ".ruff_cache",
        ".cache",
        ".gradle",
        ".terraform",
        "dist",
        "build",
        "target",
        ".next",
        ".nuxt",
        ".svelte-kit",
        ".turbo",
        ".parcel-cache",
    }
)

# Directories a supported harness keeps its own configuration in. A skill
# under one of these outside the repo root is a deploy output, so a selector
# pointing at it substitutes the repository source it came from.
VENDOR_CONFIG_DIRS = frozenset(
    {
        ".claude",
        ".codex",
        ".agents",
        ".cursor",
        ".antigravity",
        ".gemini",
        ".opencode",
        ".windsurf",
        ".vscode",
    }
)

# Manifest files that mark the directory above a skill as a plugin host. The
# registration step needs that association, so the walk records it.
PLUGIN_MANIFESTS = (
    ".claude-plugin/plugin.json",
    ".codex-plugin/plugin.json",
)

LAYOUT_PLUGIN = "plugin"
LAYOUT_REPO_SKILLS = "repo_skills"
LAYOUT_VENDOR_CONFIG = "vendor_config_skills"
LAYOUT_SINGLE_SKILL = "single_skill"
LAYOUT_NESTED = "nested"

LAYOUT_DESCRIPTIONS = {
    LAYOUT_PLUGIN: "plugins/<plugin>/skills/<skill>/SKILL.md",
    LAYOUT_REPO_SKILLS: "skills/<skill>/SKILL.md at the repo root",
    LAYOUT_VENDOR_CONFIG: "<vendor-config-dir>/skills/<skill>/SKILL.md",
    LAYOUT_SINGLE_SKILL: "a single SKILL.md at the repo root",
    LAYOUT_NESTED: "a nested layout below the repo root",
}

# The label a comparison group carries for a member no plugin manifest owns.
NO_PLUGIN_LABEL = "no plugin manifest"


def die(message: str, code: int = 2) -> None:
    """Report a fault under the running script's own name, then exit.

    Both callers are scripts the reader invokes by absolute path, so
    `sys.argv[0]` names the one whose message this is; an embedded
    interpreter run (`python3 -`) carries no such name and falls back to
    this module's own.
    """
    stem = Path(sys.argv[0]).stem
    prefix = stem if stem.isidentifier() else "skill_discovery"
    print(f"{prefix}: {message}", file=sys.stderr)
    raise SystemExit(code)


def split_frontmatter(text: str) -> tuple[str | None, str]:
    """The YAML frontmatter block and the body that follows it.

    Accepts both line endings on its own rather than relying on the caller
    having normalised them, so a file read as bytes elsewhere parses here
    identically.
    """
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return None, text
    if text.startswith("---\r\n"):
        search_from = 5
        marker = "\r\n---\r\n"
        alt = "\n---\n"
    else:
        search_from = 4
        marker = "\n---\n"
        alt = "\r\n---\r\n"
    end = text.find(marker, search_from)
    if end == -1:
        end = text.find(alt, search_from)
        if end == -1:
            return None, text
        closer_len = len(alt)
    else:
        closer_len = len(marker)
    return text[search_from:end], text[end + closer_len :]


def read_skill_text(skill_md: Path, strict: bool = True) -> str | None:
    """One skill file's text, or None when a tolerant caller may skip it.

    A selector the caller pointed at reads strictly, so an unreadable target
    fails loudly with its own message. A whole-tree scan reads tolerantly,
    because one unreadable file elsewhere in the repository is no reason to
    abandon a check of the files the caller actually named.
    """
    try:
        return skill_md.read_text(encoding="utf-8")
    except OSError as exc:
        if strict:
            die(f"cannot read {skill_md}: {exc}")
        return None


def read_frontmatter_name(skill_md: Path, strict: bool = True) -> str | None:
    text = read_skill_text(skill_md, strict)
    if text is None:
        return None
    fm, _ = split_frontmatter(text)
    if fm is None:
        return None
    match = FRONTMATTER_NAME_RE.search(fm)
    if not match:
        return None
    return match.group(1).strip().strip("\"'")


def classify_layout(rel_parts: tuple[str, ...]) -> str:
    """Name the layout a discovered skill file sits in."""
    if len(rel_parts) == 1:
        return LAYOUT_SINGLE_SKILL
    if (
        len(rel_parts) == 5
        and rel_parts[0] == "plugins"
        and rel_parts[2] == "skills"
    ):
        return LAYOUT_PLUGIN
    if len(rel_parts) == 3 and rel_parts[0] == "skills":
        return LAYOUT_REPO_SKILLS
    if (
        len(rel_parts) == 4
        and rel_parts[0] in VENDOR_CONFIG_DIRS
        and rel_parts[1] == "skills"
    ):
        return LAYOUT_VENDOR_CONFIG
    return LAYOUT_NESTED


def find_plugin_host(root: Path, skill_dir: Path) -> dict[str, object] | None:
    """The nearest directory above a skill that carries a plugin manifest."""
    current = skill_dir.parent
    while True:
        found = [
            manifest
            for manifest in PLUGIN_MANIFESTS
            if (current / manifest).is_file()
        ]
        if found:
            return {
                "directory": rel_or_abs(root, current),
                "manifests": [
                    rel_or_abs(root, current / manifest) for manifest in found
                ],
            }
        if current == root or current == current.parent:
            return None
        current = current.parent


def rel_or_abs(root: Path, path: Path) -> str:
    try:
        rel = path.resolve().relative_to(root.resolve())
    except ValueError:
        return str(path)
    return str(rel) if str(rel) != "." else "."


def pick_skill_file(directory: Path) -> Path | None:
    """The skill file in one directory, preferring the uppercase spelling."""
    try:
        entries = sorted(p.name for p in directory.iterdir())
    except OSError:
        return None
    matches = [name for name in entries if SKILL_FILE_RE.match(name)]
    if not matches:
        return None
    if PREFERRED_SKILL_FILE in matches:
        return directory / PREFERRED_SKILL_FILE
    return directory / matches[0]


def git_output(root: Path, args: list[str], stdin: str | None = None) -> str | None:
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), *args],
            input=stdin,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode not in (0, 1):
        return None
    return proc.stdout


def filter_git_ignored(root: Path, rel_paths: list[str]) -> list[str]:
    """Drop paths the repository at this root ignores.

    An ignored tree holds build output and local-only fixtures rather than
    shipped skills, and a local test fixture carrying its own SKILL.md would
    otherwise land in a whole-repo target set. The filter applies only when
    the root is the repository toplevel: rooted at a subdirectory, or at a
    directory that merely sits inside some repository, a containing repo's
    ignore rules would drop skills the caller pointed the walk at. Falls back
    to the unfiltered list whenever git cannot answer.
    """
    if not rel_paths:
        return rel_paths
    toplevel = git_output(root, ["rev-parse", "--show-toplevel"])
    if not toplevel or not toplevel.strip():
        return rel_paths
    try:
        if Path(toplevel.strip()).resolve() != root.resolve():
            return rel_paths
    except OSError:
        return rel_paths
    proc_out = git_output(root, ["check-ignore", "--stdin"], "\n".join(rel_paths))
    if proc_out is None:
        return rel_paths
    ignored = {line.strip() for line in proc_out.splitlines() if line.strip()}
    if not ignored:
        return rel_paths
    return [p for p in rel_paths if p not in ignored]


def discover_skills(root: Path, strict: bool = True) -> list[dict[str, object]]:
    """Every skill the walk finds under the repo root, in path order."""
    found: dict[str, Path] = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        matches = [name for name in sorted(filenames) if SKILL_FILE_RE.match(name)]
        if not matches:
            continue
        directory = Path(dirpath)
        name = (
            PREFERRED_SKILL_FILE
            if PREFERRED_SKILL_FILE in matches
            else matches[0]
        )
        skill_md = directory / name
        found[str(skill_md.relative_to(root))] = skill_md

    kept = filter_git_ignored(root, sorted(found))
    skills: list[dict[str, object]] = []
    for rel in kept:
        skill_md = found[rel]
        skill_dir = skill_md.parent
        rel_parts = Path(rel).parts
        host = find_plugin_host(root, skill_dir)
        skills.append(
            {
                "name": read_frontmatter_name(skill_md, strict) or skill_dir.name,
                "directory": rel_or_abs(root, skill_dir),
                "path": rel,
                "layout": classify_layout(rel_parts),
                "plugin_host": host,
            }
        )
    return skills


def shares_family_name(skill_name: str, token: str) -> bool:
    return skill_name == token or skill_name.startswith(f"{token}_")


def blank_run(text: str) -> str:
    """Same-length blanks. Newlines survive so line offsets stay usable."""
    return "".join("\n" if ch == "\n" else " " for ch in text)


def blank_fenced_blocks(text: str) -> str:
    """A same-length copy with fenced code blocks blanked."""
    out: list[str] = []
    fence: str | None = None
    for line in text.splitlines(keepends=True):
        if fence is None:
            opening = FENCE_OPEN_RE.match(line)
            if opening:
                fence = opening.group(1)
                out.append(blank_run(line))
                continue
            out.append(line)
            continue
        out.append(blank_run(line))
        closing = FENCE_CLOSE_RE.match(line)
        if (
            closing
            and closing.group(1)[0] == fence[0]
            and len(closing.group(1)) >= len(fence)
        ):
            fence = None
    return "".join(out)


def blank_inline_code(text: str) -> str:
    """A same-length copy with inline code spans blanked.

    Substitution runs line by line, so an unpaired backtick blanks nothing
    beyond its own line.
    """
    return "".join(
        INLINE_CODE_RE.sub(lambda m: blank_run(m.group(0)), line)
        for line in text.splitlines(keepends=True)
    )


def parse_family_block_names(skill_md: Path, strict: bool = True) -> list[str] | None:
    """The member names a hub's `<family>` block declares.

    Returns None when the body carries no block at all, which separates a
    hub that declares nothing from one declaring an empty block and gates
    the drift warnings that only make sense against a parsed block.

    The block is located structurally rather than by first occurrence: the
    opening tag must own its line in a probe whose fenced blocks and inline
    code spans are blanked, so a hub may document `<family>` in prose or
    show it in a fenced example without contributing members. Both tags are
    required, so an opening tag with no closing tag yields no block rather
    than a span running to end of body.
    """
    text = read_skill_text(skill_md, strict)
    if text is None:
        return None
    _, body = split_frontmatter(text)
    defenced = blank_fenced_blocks(body)
    probe = blank_inline_code(defenced)
    opening = FAMILY_OPEN_LINE_RE.search(probe)
    if opening is None:
        return None
    closing = FAMILY_CLOSE_RE.search(probe, opening.end())
    if closing is None:
        return None
    # Harvest from the fenced-blanked copy with inline code intact: member
    # names are themselves backticked and would vanish under the probe mask,
    # while a fenced example inside a genuine block would otherwise
    # contribute its sample names.
    inner = defenced[opening.end() : closing.start()]
    names: list[str] = []
    seen: set[str] = set()
    for hit in FAMILY_ENTRY_RE.findall(inner):
        if hit not in seen:
            seen.add(hit)
            names.append(hit)
    return names


class FamilyResolution(NamedTuple):
    """One family token resolved against a walk.

    `members` is what a family request selects. `prefix_set`, `block_names`,
    and `hub` are the inputs that produced it, kept so a caller can report
    on the resolution — the cross-plugin span is measured on the prefix set,
    because the block's union is the deliberate declaration rather than the
    heuristic at issue — without parsing the hub's block a second time.
    """

    members: list[dict[str, object]]
    prefix_set: list[dict[str, object]]
    block_names: list[str] | None
    hub: dict[str, object] | None


def resolve_family_set(
    root: Path,
    token: str,
    all_skills: list[dict[str, object]],
    strict: bool = True,
) -> FamilyResolution:
    """The family a token resolves to: its name-prefix set, unioned with any
    members the hub's `<family>` block declares.

    A hub is optional. With no hub, or with a hub carrying no block, the
    prefix set alone is the family.
    """
    by_name = {str(s["name"]): s for s in all_skills}
    prefix_set = [s for s in all_skills if shares_family_name(str(s["name"]), token)]
    selected: dict[str, dict[str, object]] = {
        str(skill["name"]): skill for skill in prefix_set
    }

    hub = by_name.get(token)
    block_names: list[str] | None = None
    if hub is not None:
        block_names = parse_family_block_names(root / str(hub["path"]), strict)
        for name in block_names or []:
            if name in by_name:
                selected[name] = by_name[name]

    return FamilyResolution(
        members=[selected[k] for k in sorted(selected)],
        prefix_set=prefix_set,
        block_names=block_names,
        hub=hub,
    )


def family_token(name: str) -> str:
    """The family-name token a skill name implies: its leading segment.

    `shares_family_name` accepts every underscore prefix of a name, so
    `format_markdown` implies `format` and `format_markdown` alike. The
    leading segment is the broadest of them and the one a family request
    uses, which keeps a hubless prefix family whole — a longest-match rule
    would resolve every member to its own name and split the family into
    groups of one. A name whose leading segment is empty keeps the whole name,
    so an unconventional `_leading` name reads as itself rather than as blank.
    """
    return name.split("_", 1)[0] or name


def plugin_label(skill: dict[str, object] | None) -> str:
    """The plugin that owns a skill, or the label for owning none."""
    host = skill.get("plugin_host") if skill else None
    return str(host["directory"]) if host else NO_PLUGIN_LABEL  # type: ignore[index]


def group_label(token: str, plugin: str | None) -> str:
    """How one comparison group reads inside a finding's message."""
    return f"{token} family" if plugin is None else f"{token} family ({plugin})"


def declaring_hubs(
    root: Path,
    all_skills: list[dict[str, object]],
) -> dict[str, str]:
    """Which hub's `<family>` block declares each skill name.

    A block binds a member whose own name shares no prefix with the family,
    so the declaration is what carries that member's family. Where several
    hubs declare one name — every front end of a family repeats its hub's
    block — a hub whose own name is a family-name token of the declared name
    wins, and name order settles the rest, so the answer is deterministic.
    """
    declared: dict[str, list[str]] = {}
    for skill in sorted(all_skills, key=lambda s: str(s["name"])):
        hub_name = str(skill["name"])
        names = parse_family_block_names(root / str(skill["path"]), strict=False)
        for name in names or []:
            declared.setdefault(name, []).append(hub_name)
    resolved: dict[str, str] = {}
    for name, hubs in declared.items():
        prefixed = [hub for hub in hubs if shares_family_name(name, hub)]
        resolved[name] = prefixed[0] if prefixed else hubs[0]
    return resolved


def comparison_groups(
    root: Path | None,
    targets: list[dict[str, str]],
    all_skills: list[dict[str, object]] | None = None,
) -> dict[str, str]:
    """The comparison group each target belongs to, keyed by its own path.

    A sibling comparison is only about siblings when a deliberate
    declaration binds the skills it measures against each other, so the
    group is computed from the given names rather than from whatever set a
    run selected. Each name implies a family token under `family_token`,
    that token resolves against the walk at `root` the way a family request
    resolves it, and a same-prefix member another plugin hosts is split into
    its own group unless the hub's `<family>` block names it. Splitting
    needs a second plugin to split into, so a token whose prefix set is
    hosted by at most one plugin stays a single group.

    A given path the walk does not list — a gitignored fixture, a path
    outside the root — still classifies, from its own frontmatter name and
    its own plugin host. A skill no declaration binds to another is a group
    of one, which draws no sibling finding at all.
    """
    if root is None:
        return {
            target["path"]: group_label(family_token(target["name"]), None)
            for target in targets
        }
    if all_skills is None:
        all_skills = discover_skills(root, strict=False)

    walked: dict[str, dict[str, object]] = {}
    for skill in all_skills:
        try:
            walked[str((root / str(skill["path"])).resolve())] = skill
        except OSError:
            continue

    declaring = declaring_hubs(root, all_skills)

    def token_of(name: str) -> str:
        return declaring.get(name, family_token(name))

    classified: list[dict[str, str]] = []
    for target in targets:
        given = Path(target["path"])
        try:
            walk_entry = walked.get(str(given.resolve()))
        except OSError:
            walk_entry = None
        if walk_entry is None:
            # A given path the walk never listed still classifies, from its
            # own frontmatter name and its own plugin host.
            walk_entry = {
                "name": target["name"],
                "plugin_host": find_plugin_host(root, given.parent),
            }
        name = str(walk_entry["name"])
        classified.append(
            {
                "path": target["path"],
                "name": name,
                "plugin": plugin_label(walk_entry),
                "token": token_of(name),
            }
        )

    resolutions: dict[str, tuple[set[str], str | None, set[str]]] = {}
    for token in {entry["token"] for entry in classified}:
        resolution = resolve_family_set(root, token, all_skills, strict=False)
        declared = set(resolution.block_names or [])
        if resolution.hub is not None:
            declared.add(token)
        hosted = {
            plugin_label(skill)
            for skill in resolution.prefix_set
            if skill.get("plugin_host")
        }
        # A given path outside the walk widens the span too, so a staged
        # cross-plugin coincidence splits whether or not the walk lists it.
        hosted |= {
            entry["plugin"]
            for entry in classified
            if entry["token"] == token
            and entry["name"] not in declared
            and entry["plugin"] != NO_PLUGIN_LABEL
        }
        hub_plugin = plugin_label(resolution.hub) if resolution.hub else None
        resolutions[token] = (declared, hub_plugin, hosted)

    groups: dict[str, str] = {}
    for entry in classified:
        declared, hub_plugin, hosted = resolutions[entry["token"]]
        if len(hosted) < 2:
            groups[entry["path"]] = group_label(entry["token"], None)
            continue
        plugin = (
            hub_plugin
            if entry["name"] in declared and hub_plugin is not None
            else entry["plugin"]
        )
        groups[entry["path"]] = group_label(entry["token"], plugin)
    return groups
