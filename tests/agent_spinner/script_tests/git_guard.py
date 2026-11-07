#!/usr/bin/env python3
"""Check that a Python file runs only read-only git subcommands.

The ledger may read git; it may never write a ref, index, tree, commit, object,
or the working tree. This guard parses every list literal that names ``git`` and
rejects a state-changing subcommand. ``stash list`` is the only stash form the
ledger may run.

Usage:
    python3 git_guard.py <file>
"""

import ast
import sys


FORBIDDEN = {
    "add",
    "am",
    "apply",
    "branch",
    "checkout",
    "cherry-pick",
    "clean",
    "commit",
    "commit-tree",
    "fetch",
    "gc",
    "hash-object",
    "init",
    "merge",
    "mv",
    "prune",
    "pull",
    "push",
    "rebase",
    "reset",
    "restore",
    "revert",
    "rm",
    "switch",
    "tag",
    "update-ref",
    "write-tree",
}

STASH_FORBIDDEN = {"push", "pop", "drop", "apply", "save", "clear"}


def string_list(node):
    if not isinstance(node, ast.List):
        return None
    values = []
    for element in node.elts:
        if isinstance(element, ast.Constant) and isinstance(element.value, str):
            values.append(element.value)
        else:
            values.append(None)
    return values


def subcommand(values):
    if "git" not in values:
        return None, None
    rest = values[values.index("git") + 1:]
    index = 0
    while index < len(rest):
        token = rest[index]
        if token is None:
            index += 1
            continue
        if token in ("-C", "-c", "--git-dir", "--work-tree"):
            index += 2
            continue
        if token.startswith("-"):
            index += 1
            continue
        return token, rest[index + 1:]
    return None, None


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: git_guard.py <file>\n")
        return 2
    tree = ast.parse(open(argv[1], encoding="utf-8").read())
    for node in ast.walk(tree):
        values = string_list(node)
        if not values:
            continue
        command, rest = subcommand(values)
        if not command:
            continue
        if command in FORBIDDEN:
            print("state-changing git subcommand: %s" % command)
            return 1
        if command == "stash":
            form = rest[0] if rest else ""
            if form not in ("list",):
                print("state-changing git stash form: %s" % (form or "none"))
                return 1
    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
