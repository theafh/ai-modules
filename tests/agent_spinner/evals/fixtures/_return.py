#!/usr/bin/env python3
"""Write one ledger return file from a small spec.

Usage:
    _return.py <out> <label> <token> <status> <verdict> <extras-json>

``extras-json`` is an object merged over the required return keys. A ``_prose``
member becomes the prose before the fenced block and is not written into the
JSON.
"""

import json
import sys

out, label, token, status, verdict, extras = sys.argv[1:7]

data = {
    "label": label,
    "brief": token,
    "status": status,
    "verdict": verdict,
    "examined": [],
    "checklist": [],
    "findings": [],
    "forks": [],
    "objections": [],
    "beyond_brief": [],
    "incidents": [],
    "own_authority": [],
    "alternatives": [],
    "brief_corrections": [],
    "dropped_suspicions": [],
    "notes": "",
}
if extras.startswith("@"):
    with open(extras[1:], encoding="utf-8") as fh:
        extras = fh.read()
data.update(json.loads(extras))
prose = data.pop("_prose", "")
for key in data.pop("_late", []):
    if key in data:
        data[key] = data.pop(key)

with open(out, "w", encoding="utf-8") as fh:
    if prose:
        fh.write(prose + "\n\n")
    fh.write("```json\n" + json.dumps(data, indent=2) + "\n```\n\nEND " + label + "\n")
