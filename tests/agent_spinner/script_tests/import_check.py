#!/usr/bin/env python3
"""Check that a Python file imports only the standard library.

Usage:
    python3 import_check.py <file>
"""

import ast
import importlib.util
import os
import sys
import sysconfig


def top_level_modules(path):
    tree = ast.parse(open(path, encoding="utf-8").read())
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                names.add(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            if node.level:
                continue
            if node.module:
                names.add(node.module.split(".")[0])
    return names


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: import_check.py <file>\n")
        return 2
    stdlib = os.path.realpath(sysconfig.get_paths().get("stdlib", ""))
    for name in sorted(top_level_modules(argv[1])):
        if name in ("__future__",) or name in sys.builtin_module_names:
            continue
        spec = importlib.util.find_spec(name)
        if spec is None:
            print("unresolved import: %s" % name)
            return 1
        origin = spec.origin or ""
        if origin in ("built-in", "frozen") or os.path.realpath(origin).startswith(stdlib):
            continue
        print("third-party import: %s (%s)" % (name, origin))
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
