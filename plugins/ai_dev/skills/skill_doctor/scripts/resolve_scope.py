#!/usr/bin/env python3
"""Resolve skill_doctor check scope to concrete skill directories.

Modes:
  --skill NAME|PATH   one skill
  --family TOKEN      family-name set union optional hub <family> names
  --all               every skill the walk finds under the repo root

The walk discovers the layout instead of requiring one: it finds every
skill file under --root, case-insensitively as the harness matches it, and
classifies each hit as a plugin layout, a repo-root skills/ tree, a vendor
configuration skills/ tree, a single-skill repo, or a nested layout. An
empty walk is its own failure, reported identically in all three modes, so
a selector never reads as a miss inside a tree that is not there.

Prints JSON on stdout. Edits nothing.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

FAMILY_BLOCK_RE = re.compile(
    r"<family>(.*?)</family>",
    re.DOTALL | re.IGNORECASE,
)
BACKTICK_NAME_RE = re.compile(r"`([a-z][a-z0-9_]*)`")
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


def die(message: str, code: int = 2) -> None:
    print(f"resolve_scope: {message}", file=sys.stderr)
    raise SystemExit(code)


def split_frontmatter(text: str) -> tuple[str | None, str]:
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return None, text
    return text[4:end], text[end + len("\n---\n") :]


def read_frontmatter_name(skill_md: Path) -> str | None:
    try:
        text = skill_md.read_text(encoding="utf-8")
    except OSError as exc:
        die(f"cannot read {skill_md}: {exc}")
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


def discover_skills(root: Path) -> list[dict[str, object]]:
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
                "name": read_frontmatter_name(skill_md) or skill_dir.name,
                "directory": rel_or_abs(root, skill_dir),
                "path": rel,
                "layout": classify_layout(rel_parts),
                "plugin_host": host,
            }
        )
    return skills


def shares_family_name(skill_name: str, token: str) -> bool:
    return skill_name == token or skill_name.startswith(f"{token}_")


def parse_family_block_names(skill_md: Path) -> list[str]:
    try:
        text = skill_md.read_text(encoding="utf-8")
    except OSError as exc:
        die(f"cannot read {skill_md}: {exc}")
    _, body = split_frontmatter(text)
    match = FAMILY_BLOCK_RE.search(body)
    if not match:
        return []
    names: list[str] = []
    seen: set[str] = set()
    for hit in BACKTICK_NAME_RE.findall(match.group(1)):
        if hit not in seen:
            seen.add(hit)
            names.append(hit)
    return names


def vendor_substitution(
    selector: str,
    selector_path: Path,
) -> dict[str, str] | None:
    """The skill name a vendor-deployed selector stands for.

    A deployed copy under a harness configuration directory is a build
    output rather than a target, so the caller resolves the repository
    source of the same name and names the substitution.
    """
    parts = selector_path.parts
    vendor_index = next(
        (
            i
            for i in range(len(parts) - 1, -1, -1)
            if parts[i] in VENDOR_CONFIG_DIRS
        ),
        None,
    )
    if vendor_index is None:
        return None
    tail = [p for p in parts[vendor_index + 1 :] if not SKILL_FILE_RE.match(p)]
    if not tail:
        return None
    return {
        "selector": selector,
        "vendor_dir": parts[vendor_index],
        "skill_name": tail[-1],
    }


def describe_layouts(skills: list[dict[str, object]]) -> list[dict[str, str]]:
    seen: list[str] = []
    for skill in skills:
        layout = str(skill["layout"])
        if layout not in seen:
            seen.append(layout)
    return [
        {"layout": layout, "shape": LAYOUT_DESCRIPTIONS[layout]}
        for layout in seen
    ]


def resolve_skill(
    root: Path,
    selector: str,
    all_skills: list[dict[str, object]],
) -> tuple[list[dict[str, object]], dict[str, str] | None]:
    by_name = {s["name"]: s for s in all_skills}
    by_path = {s["path"]: s for s in all_skills}
    selector_path = Path(selector)
    looks_like_path = (
        selector_path.is_absolute()
        or "/" in selector
        or SKILL_FILE_RE.match(selector_path.name) is not None
    )

    if looks_like_path:
        path = selector_path if selector_path.is_absolute() else root / selector
        substitution = None
        if SKILL_FILE_RE.match(path.name):
            skill_dir, skill_md = path.parent, path
        else:
            skill_dir, skill_md = path, pick_skill_file(path)
        if skill_md is None or not skill_md.is_file():
            # A selector under a vendor configuration directory names a
            # deploy output. Substitute the repository source rather than
            # rejecting the path or checking the build artifact.
            substitution = vendor_substitution(selector, path)
            if substitution and substitution["skill_name"] in by_name:
                return (
                    [by_name[substitution["skill_name"]]],
                    substitution,
                )
            die(f"skill path not found: {selector}")
        try:
            rel_md = str(skill_md.resolve().relative_to(root.resolve()))
        except ValueError:
            substitution = vendor_substitution(selector, skill_md)
            if substitution and substitution["skill_name"] in by_name:
                return [by_name[substitution["skill_name"]]], substitution
            die(f"skill path escapes repo root: {selector}")
        if rel_md in by_path:
            return [by_path[rel_md]], None
        rel_parts = Path(rel_md).parts
        return (
            [
                {
                    "name": read_frontmatter_name(skill_md) or skill_dir.name,
                    "directory": rel_or_abs(root, skill_dir),
                    "path": rel_md,
                    "layout": classify_layout(rel_parts),
                    "plugin_host": find_plugin_host(root, skill_dir),
                }
            ],
            None,
        )

    if selector in by_name:
        return [by_name[selector]], None
    die(f"skill not found: {selector}")
    raise AssertionError("unreachable")


def resolve_family(
    root: Path,
    token: str,
    all_skills: list[dict[str, object]],
) -> list[dict[str, object]]:
    by_name = {s["name"]: s for s in all_skills}
    selected: dict[str, dict[str, object]] = {}

    for skill in all_skills:
        if shares_family_name(str(skill["name"]), token):
            selected[str(skill["name"])] = skill

    hub = by_name.get(token)
    if hub is not None:
        hub_md = root / str(hub["path"])
        for name in parse_family_block_names(hub_md):
            if name in by_name:
                selected[name] = by_name[name]

    return [selected[k] for k in sorted(selected)]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Resolve skill_doctor scope to skill directories."
    )
    parser.add_argument(
        "--root",
        required=True,
        help="Repository root to walk for skill files",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--skill", help="One skill name or SKILL.md / skill dir path")
    mode.add_argument("--family", help="Family token (hub name / token_*)")
    mode.add_argument(
        "--all",
        action="store_true",
        help="Every skill the walk finds under the repo root",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path(args.root).resolve()
    if not root.is_dir():
        die(f"root is not a directory: {root}")

    # Walk once, before mode dispatch. An empty walk means the repository
    # ships no skill file at all, which is its own failure with its own
    # remedy: a selector cannot miss inside a tree that does not exist, so
    # reporting it as an unknown name would send the reader after a typo.
    all_skills = discover_skills(root)
    if not all_skills:
        die(f"no SKILL.md found under {root}", code=1)

    substitution: dict[str, str] | None = None
    if args.skill:
        mode = "skill"
        skills, substitution = resolve_skill(root, args.skill, all_skills)
        selector = args.skill
    elif args.family:
        mode = "family"
        skills = resolve_family(root, args.family, all_skills)
        selector = args.family
        if not skills:
            die(f"no skills found for family token: {args.family}", code=1)
    else:
        mode = "all"
        skills = all_skills
        selector = "*"

    payload = {
        "mode": mode,
        "selector": selector,
        "count": len(skills),
        "root": str(root),
        "layouts": describe_layouts(skills),
        "vendor_substitution": substitution,
        "skills": skills,
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    layout_names = ", ".join(entry["layout"] for entry in payload["layouts"])
    print(
        "Resolved target set ({count}) in layout {layouts}: {names}".format(
            count=len(skills),
            layouts=layout_names or "none",
            names=", ".join(str(s["name"]) for s in skills),
        ),
        file=sys.stderr,
    )
    if substitution:
        print(
            "Vendor deploy substitution: selector {selector} under "
            "{vendor_dir}/ checked as repository source {path}".format(
                selector=substitution["selector"],
                vendor_dir=substitution["vendor_dir"],
                path=skills[0]["path"],
            ),
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
