#!/usr/bin/env python3
"""Check that a Python file runs only read-only git subcommands.

The ledger may read git; it may never write a ref, index, tree, commit, object,
or the working tree. This guard parses every list literal that names ``git`` and
every ``git([...])`` helper call, and rejects a state-changing subcommand.
``stash list`` is the only stash form the ledger may run.

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


def helper_subcommand(node):
    """Return the subcommand of a ``git([...])`` call, or None.

    The ledger reaches git through ``git(args, root)``, which builds the
    command around the caller's list, so the subcommand is the first element
    of that list rather than a token beside a literal ``"git"``.
    """
    if not isinstance(node, ast.Call):
        return None, None
    func = node.func
    if not (isinstance(func, ast.Name) and func.id == "git"):
        return None, None
    if not node.args:
        return None, None
    values = string_list(node.args[0])
    if not values or not values[0]:
        return None, None
    return values[0], values[1:]


def violation(command, rest):
    if command in FORBIDDEN:
        return "state-changing git subcommand: %s" % command
    if command == "stash":
        form = rest[0] if rest else ""
        if form not in ("list",):
            return "state-changing git stash form: %s" % (form or "none")
    return None


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: git_guard.py <file>\n")
        return 2
    tree = ast.parse(open(argv[1], encoding="utf-8").read())
    for node in ast.walk(tree):
        values = string_list(node)
        if values:
            command, rest = subcommand(values)
            message = violation(command, rest) if command else None
            if message:
                print(message)
                return 1
        command, rest = helper_subcommand(node)
        message = violation(command, rest) if command else None
        if message:
            print(message)
            return 1
    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
