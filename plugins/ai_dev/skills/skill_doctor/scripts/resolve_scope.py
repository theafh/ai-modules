#!/usr/bin/env python3
"""Resolve skill_doctor check scope to concrete skill directories.

Modes:
  --skill NAME|PATH   one skill
  --family TOKEN      family-name set union optional hub <family> names
  --all               every plugins/*/skills/*/SKILL.md under the repo root

Every mode requires a plugins/*/skills/ tree holding at least one SKILL.md.
An absent tree is its own failure, reported identically in all three modes,
so a selector never reads as a miss inside a tree that is not there.

Prints JSON on stdout. Edits nothing.
"""

from __future__ import annotations

import argparse
import json
import re
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


def discover_skills(root: Path) -> list[dict[str, str]]:
    skills: list[dict[str, str]] = []
    plugins = root / "plugins"
    if not plugins.is_dir():
        return skills
    for skill_md in sorted(plugins.glob("*/skills/*/SKILL.md")):
        skill_dir = skill_md.parent
        name = read_frontmatter_name(skill_md) or skill_dir.name
        skills.append(
            {
                "name": name,
                "directory": str(skill_dir.relative_to(root)),
                "path": str(skill_md.relative_to(root)),
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


def resolve_skill(
    root: Path,
    selector: str,
    all_skills: list[dict[str, str]],
) -> list[dict[str, str]]:
    by_name = {s["name"]: s for s in all_skills}
    selector_path = Path(selector)

    if selector_path.is_absolute() or "/" in selector or selector.endswith(
        "SKILL.md"
    ):
        path = selector_path if selector_path.is_absolute() else root / selector
        if path.name == "SKILL.md":
            skill_dir = path.parent
            skill_md = path
        else:
            skill_dir = path
            skill_md = skill_dir / "SKILL.md"
        if not skill_md.is_file():
            die(f"skill path not found: {selector}")
        name = read_frontmatter_name(skill_md) or skill_dir.name
        try:
            rel_dir = str(skill_dir.resolve().relative_to(root.resolve()))
            rel_md = str(skill_md.resolve().relative_to(root.resolve()))
        except ValueError:
            die(f"skill path escapes repo root: {selector}")
        return [{"name": name, "directory": rel_dir, "path": rel_md}]

    if selector in by_name:
        return [by_name[selector]]
    die(f"skill not found: {selector}")


def resolve_family(
    root: Path,
    token: str,
    all_skills: list[dict[str, str]],
) -> list[dict[str, str]]:
    by_name = {s["name"]: s for s in all_skills}
    selected: dict[str, dict[str, str]] = {}

    for skill in all_skills:
        if shares_family_name(skill["name"], token):
            selected[skill["name"]] = skill

    hub = by_name.get(token)
    hub_family_names: list[str] = []
    if hub is not None:
        hub_md = root / hub["path"]
        hub_family_names = parse_family_block_names(hub_md)
        for name in hub_family_names:
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
        help="Repository root that contains plugins/",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--skill", help="One skill name or SKILL.md / skill dir path")
    mode.add_argument("--family", help="Family token (hub name / token_*)")
    mode.add_argument(
        "--all",
        action="store_true",
        help="Every skill under plugins/*/skills/",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path(args.root).resolve()
    if not root.is_dir():
        die(f"root is not a directory: {root}")

    # Walk once, before mode dispatch. An empty walk means the layout every
    # mode expects is absent, which is its own failure with its own remedy:
    # a selector cannot miss inside a tree that does not exist, so reporting
    # it as an unknown name would send the reader after a typo instead.
    all_skills = discover_skills(root)
    if not all_skills:
        die("no skills found under plugins/*/skills/", code=1)

    if args.skill:
        mode = "skill"
        skills = resolve_skill(root, args.skill, all_skills)
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
        "skills": skills,
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    print(
        "Resolved target set ({count}): {names}".format(
            count=len(skills),
            names=", ".join(s["name"] for s in skills),
        ),
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
