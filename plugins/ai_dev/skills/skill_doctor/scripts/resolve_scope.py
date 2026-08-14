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

A family run reports what its own resolution cannot vouch for rather than
presenting a guess as fact: the payload groups the resolved set by owning
plugin under `by_plugin`, and `warnings` carries a prefix set spanning more
than one plugin, a prefix sibling the hub's block omits, and a block entry
naming no discovered skill.

Prints JSON on stdout. Edits nothing.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Load the shared discovery module by sibling name. A script run by absolute
# path already has its own directory first on the import path, while the
# `importlib.util.spec_from_file_location` form the script tests use adds no
# such entry, so inserting it here satisfies both load paths.
_SCRIPT_DIR = str(Path(__file__).resolve().parent)
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

from skill_discovery import (  # noqa: E402
    LAYOUT_DESCRIPTIONS,
    SKILL_FILE_RE,
    VENDOR_CONFIG_DIRS,
    classify_layout,
    die,
    discover_skills,
    find_plugin_host,
    parse_family_block_names,
    pick_skill_file,
    read_frontmatter_name,
    rel_or_abs,
    resolve_family_set,
    shares_family_name,
    split_frontmatter,
)

# The discovery surface a caller loading this script by file location reaches
# from here. `parse_family_block_names`, `shares_family_name` and
# `split_frontmatter` are re-exports rather than call sites: the block-parse
# tests reach them through this module, so moving them must not move where
# they answer from.
__all__ = [
    "LAYOUT_DESCRIPTIONS",
    "SKILL_FILE_RE",
    "VENDOR_CONFIG_DIRS",
    "classify_layout",
    "die",
    "discover_skills",
    "find_plugin_host",
    "parse_family_block_names",
    "pick_skill_file",
    "read_frontmatter_name",
    "rel_or_abs",
    "resolve_family",
    "resolve_family_set",
    "resolve_skill",
    "shares_family_name",
    "split_frontmatter",
]


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


def describe_plugin_groups(
    skills: list[dict[str, object]],
    by_plugin: dict[str, list[str]],
) -> str:
    """The orientation lead's target set, grouped by owning plugin.

    A flat list hides a cross-plugin split, so hosted members read under the
    plugin that owns them and unhosted ones follow under their own label.
    """
    parts = [
        "{directory} [{names}]".format(directory=directory, names=", ".join(names))
        for directory, names in by_plugin.items()
    ]
    loose = [str(s["name"]) for s in skills if not s.get("plugin_host")]
    if loose:
        parts.append("no plugin manifest [{names}]".format(names=", ".join(loose)))
    return "; ".join(parts) if parts else "none"


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


def skill_ref(skill: dict[str, object]) -> dict[str, str]:
    return {"name": str(skill["name"]), "path": str(skill["path"])}


def group_by_plugin(skills: list[dict[str, object]]) -> dict[str, list[str]]:
    """The resolved set keyed by the plugin that owns each member.

    A skill whose `plugin_host` is None stays in the flat `skills` array and
    is omitted here, since it has no owning plugin to group under.
    """
    grouped: dict[str, list[str]] = {}
    for skill in skills:
        host = skill.get("plugin_host")
        if not host:
            continue
        directory = str(host["directory"])  # type: ignore[index]
        grouped.setdefault(directory, []).append(str(skill["name"]))
    return {directory: sorted(names) for directory, names in sorted(grouped.items())}


def family_warnings(
    token: str,
    prefix_set: list[dict[str, object]],
    block_names: list[str] | None,
    by_name: dict[str, dict[str, object]],
) -> list[dict[str, object]]:
    """Every way a resolved family set could be wrong, stated rather than
    assumed.

    All three findings stay at `warning`: the harness loads every one of
    these skills, and a hub may deliberately omit a deprecated sibling, so
    none of them is a mechanical load failure.
    """
    warnings: list[dict[str, object]] = []

    # A same-prefix skill in another plugin stays in the resolved set and is
    # reported. A genuine cross-plugin family is a real case that the block's
    # union serves, so dropping the member would assume the coincidence
    # reading; keeping it and naming the split leaves that reading to the
    # reader. The span is measured on the prefix set, because the block's
    # union is the deliberate declaration rather than the heuristic at issue.
    hosted: dict[str, list[dict[str, object]]] = {}
    for skill in prefix_set:
        host = skill.get("plugin_host")
        if not host:
            continue
        hosted.setdefault(str(host["directory"]), []).append(skill)  # type: ignore[index]
    if len(hosted) > 1:
        by_directory = [
            (directory, sorted(members, key=lambda m: str(m["name"])))
            for directory, members in sorted(hosted.items())
        ]
        warnings.append(
            {
                "severity": "warning",
                "code": "family_spans_plugins",
                "message": (
                    f"family token '{token}' resolves by name prefix across "
                    f"{len(by_directory)} plugins: "
                    + "; ".join(
                        "{directory} [{names}]".format(
                            directory=directory,
                            names=", ".join(str(m["name"]) for m in members),
                        )
                        for directory, members in by_directory
                    )
                ),
                "plugins": [
                    {
                        "directory": directory,
                        "skills": [skill_ref(m) for m in members],
                    }
                    for directory, members in by_directory
                ],
                "skills": [
                    skill_ref(m) for _, members in by_directory for m in members
                ],
            }
        )

    # The remaining two findings compare the hub's declaration against the
    # tree, so a hub with no parsed block produces neither.
    if block_names is None:
        return warnings

    declared = set(block_names)
    for skill in sorted(prefix_set, key=lambda s: str(s["name"])):
        name = str(skill["name"])
        # The hub is not a prefix sibling whose absence warns: a block
        # enumerating the front ends it delegates to is ordinary authoring.
        if name == token or name in declared:
            continue
        warnings.append(
            {
                "severity": "warning",
                "code": "family_block_omits_sibling",
                "message": (
                    f"hub '{token}' <family> block omits prefix sibling "
                    f"'{name}' ({skill['path']}), so the hub's documentation "
                    "reads as behind the tree"
                ),
                "skills": [skill_ref(skill)],
            }
        )

    hub = by_name.get(token)
    for name in block_names:
        if name in by_name:
            continue
        warnings.append(
            {
                "severity": "warning",
                "code": "family_block_entry_unknown",
                "entry": name,
                "message": (
                    f"hub '{token}' <family> block names '{name}', which the "
                    "walk found no skill for, so the entry reads as a member "
                    "renamed or removed"
                ),
                "skills": [skill_ref(hub)] if hub is not None else [],
            }
        )

    return warnings


def resolve_family(
    root: Path,
    token: str,
    all_skills: list[dict[str, object]],
) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    """The family a token selects, with everything its resolution cannot
    vouch for reported alongside it.

    Membership comes from the shared `resolve_family_set`, which
    discovery_safety.py derives its comparison grouping from as well, so the
    two agree on what a family is by construction.
    """
    by_name = {s["name"]: s for s in all_skills}
    resolution = resolve_family_set(root, token, all_skills)
    warnings = family_warnings(
        token,
        resolution.prefix_set,
        resolution.block_names,
        by_name,
    )
    return resolution.members, warnings


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
    warnings: list[dict[str, object]] = []
    if args.skill:
        mode = "skill"
        skills, substitution = resolve_skill(root, args.skill, all_skills)
        selector = args.skill
    elif args.family:
        mode = "family"
        skills, warnings = resolve_family(root, args.family, all_skills)
        selector = args.family
        if not skills:
            die(f"no skills found for family token: {args.family}", code=1)
    else:
        mode = "all"
        skills = all_skills
        selector = "*"

    by_plugin = group_by_plugin(skills)
    payload = {
        "mode": mode,
        "selector": selector,
        "count": len(skills),
        "root": str(root),
        "layouts": describe_layouts(skills),
        "by_plugin": by_plugin,
        "vendor_substitution": substitution,
        "warnings": warnings,
        "skills": skills,
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    layout_names = ", ".join(entry["layout"] for entry in payload["layouts"])
    print(
        "Resolved target set ({count}) in layout {layouts} by plugin: "
        "{groups}".format(
            count=len(skills),
            layouts=layout_names or "none",
            groups=describe_plugin_groups(skills, by_plugin),
        ),
        file=sys.stderr,
    )
    for warning in warnings:
        print(
            "Family warning [{code}]: {message}".format(
                code=warning["code"],
                message=warning["message"],
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
