#!/usr/bin/env python3
"""run_ledger.py - keep one helper run's records on disk.

The ledger works through verbs, its subcommands. Every verb works on
``.agent_spinner/`` under its current directory, the working root. The ledger
records the spawns the orchestrator makes and launches no helper itself. It
imports only the standard library and needs Python 3.9 or newer.

The files are the contract. Their layout and formats define the ledger's
behaviour, so an orchestrator on a host that cannot run python3 can keep the
same files by hand.
"""

from __future__ import annotations

import argparse
import csv
import datetime
import difflib
import fnmatch
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

MIN_VERSION = (3, 9)
RUN_NAME = ".agent_spinner"

COLUMNS = [
    "label",
    "phase",
    "role",
    "item",
    "path",
    "kind",
    "state",
    "attempts",
    "brief_hash",
    "input_versions",
    "helper_id",
    "spawn_route",
    "model_req",
    "effort_req",
    "model_obs",
    "effort_obs",
    "dispatched_at",
    "start_marker_time",
    "returned_at",
    "source",
    "stamp_owner",
]

TERMINAL = ("accepted", "inability", "failed", "unreturned", "dropped")
RETURN_KEYS = [
    "label",
    "brief",
    "status",
    "verdict",
    "examined",
    "checklist",
    "findings",
    "forks",
    "beyond_brief",
    "incidents",
    "own_authority",
    "alternatives",
    "brief_corrections",
    "dropped_suspicions",
    "notes",
]
RECORD_LISTS = [
    "findings",
    "forks",
    "incidents",
    "own_authority",
    "alternatives",
    "brief_corrections",
    "dropped_suspicions",
    "confirmations",
    "gaps",
]
PLACEHOLDER_MARKERS = ("todo", "tbd", "fixme", "xxx")
STATE_VALUES = (
    "pending",
    "dispatched",
    "violation",
    "accepted",
    "inability",
    "failed",
    "unreturned",
    "unknown",
    "dropped",
)


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).replace(
        microsecond=0
    ).isoformat()


def die(message, code=2):
    sys.stderr.write("run_ledger.py: %s\n" % message)
    raise SystemExit(code)


def check_interpreter(version=None):
    version = version if version is not None else sys.version_info
    if tuple(version[:2]) < MIN_VERSION:
        die(
            "needs Python %d.%d or newer; running %d.%d"
            % (MIN_VERSION[0], MIN_VERSION[1], version[0], version[1])
        )


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_text(text):
    return sha256_bytes(text.encode("utf-8", "replace"))


def short_hash(text, n=8):
    return sha256_text(text)[:n]


def slugify(value):
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9._-]+", "-", value)
    value = value.strip("-._")
    return value or "item"


def read_text(path):
    try:
        with open(path, "rb") as fh:
            return fh.read().decode("utf-8", "replace")
    except FileNotFoundError:
        return ""


def atomic_write(path, data):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=parent or ".")
    try:
        with os.fdopen(fd, "wb") as fh:
            if isinstance(data, str):
                data = data.encode("utf-8", "replace")
            fh.write(data)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


class Lock(object):
    def __init__(self, path):
        self.path = path
        self.fh = None

    def __enter__(self):
        import fcntl

        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.fh = open(self.path, "a+")
        fcntl.flock(self.fh.fileno(), fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        import fcntl

        if self.fh is not None:
            fcntl.flock(self.fh.fileno(), fcntl.LOCK_UN)
            self.fh.close()
        return False


def repo_root(cwd):
    proc = subprocess.run(
        ["git", "--no-optional-locks", "-C", cwd, "rev-parse", "--show-toplevel"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode == 0:
        text = proc.stdout.decode("utf-8", "replace").strip()
        if text:
            return os.path.realpath(text), True
    return os.path.realpath(cwd), False


def norm_path(root, path):
    if os.path.isabs(path):
        target = os.path.realpath(path)
    else:
        target = os.path.realpath(os.path.join(root, path))
    try:
        rel = os.path.relpath(target, root)
    except ValueError:
        rel = target
    return rel.replace(os.sep, "/")


def git(args, root, check=False):
    cmd = ["git", "--no-optional-locks", "-C", root] + list(args)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and proc.returncode != 0:
        die(
            "git %s failed: %s"
            % (" ".join(args), proc.stderr.decode("utf-8", "replace").strip())
        )
    return proc


def git_status(root):
    proc = git(["status", "--porcelain", "-z", "--untracked-files=all"], root)
    if proc.returncode != 0:
        return []
    out = proc.stdout.decode("utf-8", "replace")
    entries = []
    parts = out.split("\0")
    i = 0
    while i < len(parts):
        entry = parts[i]
        i += 1
        if not entry:
            continue
        code = entry[:2]
        path = entry[3:]
        if code[:1] in ("R", "C") and i < len(parts):
            # The following NUL field is the rename or copy source. Consume it
            # so it is not read as another entry, and keep the new path the
            # entry already carries so the change is measured where it landed.
            i += 1
        entries.append((code, path))
    return entries


def git_head(root):
    proc = git(["rev-parse", "HEAD"], root)
    if proc.returncode != 0:
        return ""
    return proc.stdout.decode("utf-8", "replace").strip()


def git_stash_list(root):
    proc = git(["stash", "list"], root)
    return proc.stdout.decode("utf-8", "replace").strip()


def git_ignored(root):
    proc = git(["ls-files", "-z", "--others", "--ignored", "--exclude-standard"], root)
    if proc.returncode != 0:
        return []
    return sorted(p for p in proc.stdout.decode("utf-8", "replace").split("\0") if p)


def git_tracked(root):
    proc = git(["ls-files", "-z"], root)
    if proc.returncode != 0:
        return []
    return [p for p in proc.stdout.decode("utf-8", "replace").split("\0") if p]


def file_hash(path):
    try:
        with open(path, "rb") as fh:
            return sha256_bytes(fh.read())
    except (FileNotFoundError, IsADirectoryError):
        return ""


def under_run_dir(root, rel):
    run_rel = RUN_NAME
    return rel == run_rel or rel.startswith(run_rel + "/")


def parse_utc(text):
    if not text:
        return None
    try:
        return datetime.datetime.fromisoformat(text)
    except ValueError:
        return None


def read_rows(path):
    if not os.path.exists(path):
        return []
    rows = []
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh, delimiter="\t")
        for parts in reader:
            if not parts:
                continue
            row = {}
            for idx, name in enumerate(COLUMNS):
                row[name] = parts[idx] if idx < len(parts) else ""
            for name in COLUMNS:
                row.setdefault(name, "")
            rows.append(row)
    return rows


def write_rows(path, rows):
    lines = []
    for row in rows:
        values = [str(row.get(name, "")) for name in COLUMNS]
        lines.append("\t".join(values))
    atomic_write(path, "\n".join(lines) + ("\n" if lines else ""))


class Ledger(object):
    def __init__(self, cwd=None, require_run=True):
        self.cwd = os.path.realpath(cwd or os.getcwd())
        self.root, self.is_repo = repo_root(self.cwd)
        self.run_dir = os.path.join(self.root, RUN_NAME)
        self.run_json_path = os.path.join(self.run_dir, "run.json")
        self.roster_path = os.path.join(self.run_dir, "roster.tsv")
        self.ledger_path = os.path.join(self.run_dir, "ledger.jsonl")
        self.run = self.load_run()
        self.rows = read_rows(self.roster_path)
        if require_run and not self.run:
            die("no open run under %s; run init first" % self.run_dir)

    def path(self, *parts):
        return os.path.join(self.run_dir, *parts)

    def load_run(self):
        text = read_text(self.run_json_path)
        if not text.strip():
            return {}
        try:
            return json.loads(text)
        except ValueError:
            die("unreadable run.json")

    def save_run(self):
        atomic_write(self.run_json_path, json.dumps(self.run, indent=2, sort_keys=True) + "\n")

    def save_rows(self):
        write_rows(self.roster_path, self.rows)

    def lock(self):
        return Lock(self.path(".lock"))

    def append(self, record):
        record = dict(record)
        record.setdefault("at", now_utc())
        with open(self.ledger_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, sort_keys=True) + "\n")
        return record

    def records(self):
        text = read_text(self.ledger_path)
        out = []
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except ValueError:
                continue
        return out

    def find_row(self, label):
        for row in self.rows:
            if row.get("label") == label:
                return row
        die("no roster row labelled %s" % label)

    def row_or_none(self, label):
        for row in self.rows:
            if row.get("label") == label:
                return row
        return None

    def add_row(self, row):
        base = {name: "" for name in COLUMNS}
        base.update(row)
        self.rows.append(base)
        return base

    def save(self):
        self.save_run()
        self.save_rows()

    def state_counts(self):
        counts = {}
        for row in self.rows:
            state = row.get("state") or "pending"
            counts[state] = counts.get(state, 0) + 1
        return counts

    def records_of(self, label):
        return [
            rec
            for rec in self.records()
            if rec.get("label") == label or rec.get("row") == label
        ]

    def open_gates(self):
        answered = set()
        for rec in self.records():
            if rec.get("type") == "gate_answered":
                answered.add(rec.get("gate_id"))
        gates = []
        for rec in self.records():
            if rec.get("type") == "user_gate" and rec.get("id") not in answered:
                gates.append(rec)
        return gates

    def dispositions(self):
        out = {}
        for rec in self.records():
            if rec.get("type") == "disposition":
                out.setdefault(rec.get("target"), []).append(rec)
        return out

    def flags_for(self, label):
        return [
            rec
            for rec in self.records()
            if rec.get("type") == "flag" and rec.get("label") == label
        ]


def parse_key_value(items, what):
    out = {}
    for item in items or []:
        if "=" not in item:
            die("%s needs NAME=VALUE, got %r" % (what, item))
        key, value = item.split("=", 1)
        out[key.strip()] = value
    return out


def parse_unit(spec):
    if ":" not in spec:
        die("unit must be role:item, got %r" % spec)
    role, item = spec.split(":", 1)
    if not role.strip() or not item.strip():
        die("unit must name a role and an item, got %r" % spec)
    return role.strip(), item.strip()


# ---------------------------------------------------------------------------
# init and probe
# ---------------------------------------------------------------------------


def plant_extension(argv):
    for arg in argv:
        if re.match(r"^\.[A-Za-z0-9]+$", arg):
            return arg.lower()
    for arg in argv:
        ext = os.path.splitext(arg)[1].lower()
        if ext in (".md", ".sh", ".py", ".json", ".txt", ".ts"):
            return ext
    return ".md"


def gate_spec(name, command):
    try:
        argv = shlex.split(command)
    except ValueError as exc:
        die("gate %s has an unparsable command: %s" % (name, exc))
    if not argv:
        die("gate %s has an empty command" % name)
    return {"name": name, "argv": argv, "auto_fix": False, "plant": "", "reports_plant": False}


def run_gate_argv(argv, root, controls_dir):
    rendered = []
    used = False
    for arg in argv:
        if "{controls}" in arg:
            rendered.append(arg.replace("{controls}", controls_dir))
            used = True
        else:
            rendered.append(arg)
    if not used:
        rendered.append(controls_dir)
    try:
        proc = subprocess.run(
            rendered, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
    except OSError as exc:
        return None, str(exc)
    return proc.returncode, proc.stdout.decode("utf-8", "replace")


def hashed_walk(root):
    hashes = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            name for name in dirnames if name not in (RUN_NAME, ".git")
        ]
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            if under_run_dir(root, rel):
                continue
            hashes[rel] = file_hash(full)
    return hashes


def store_hashed_walk(led):
    base = led.path("baseline")
    hashes = hashed_walk(led.root)
    atomic_write(
        os.path.join(base, "walk.json"),
        json.dumps(hashes, indent=2, sort_keys=True) + "\n",
    )
    copies = os.path.join(base, "walk-copies")
    for rel in hashes:
        src = os.path.join(led.root, rel)
        dest = os.path.join(copies, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(src, dest)
    return hashes


def record_baseline(led, request_text, intent_text):
    base = led.path("baseline")
    os.makedirs(base, exist_ok=True)
    head = git_head(led.root)
    status = git_status(led.root)
    stash = git_stash_list(led.root)
    ignored = [p for p in git_ignored(led.root) if not under_run_dir(led.root, p)]
    atomic_write(os.path.join(base, "HEAD"), head + "\n")
    atomic_write(
        os.path.join(base, "status"),
        "\n".join("%s %s" % (code, path) for code, path in status) + ("\n" if status else ""),
    )
    atomic_write(os.path.join(base, "stash-list"), stash + ("\n" if stash else ""))
    atomic_write(os.path.join(base, "ignored"), "\n".join(ignored) + ("\n" if ignored else ""))
    hashes = {}
    for code, path in status:
        if under_run_dir(led.root, path):
            continue
        full = os.path.join(led.root, path)
        if os.path.isfile(full):
            hashes[path] = file_hash(full)
            dest = os.path.join(base, "copies", path)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copyfile(full, dest)
    atomic_write(os.path.join(base, "hashes.json"), json.dumps(hashes, indent=2, sort_keys=True) + "\n")
    return head, status, stash, ignored, hashes


def cmd_init(args):
    led = Ledger(require_run=False)
    os.makedirs(led.run_dir, exist_ok=True)

    if args.probe:
        return init_probe(led, args)

    if led.run:
        if led.run.get("closed"):
            history = os.path.join(led.run_dir, "history", led.run.get("run_id") or "closed")
            os.makedirs(history, exist_ok=True)
            for name in os.listdir(led.run_dir):
                if name in ("history", ".gitignore", ".lock"):
                    continue
                src = os.path.join(led.run_dir, name)
                dest = os.path.join(history, name)
                if os.path.isdir(src):
                    shutil.move(src, dest)
                else:
                    shutil.move(src, dest)
            led.run = {}
            led.rows = []
        else:
            die("a run is already open; re-enter it with attach")

    # A gate the caller marks auto-fixing is refused even when no definition
    # accompanies the mark. The run body says init refuses a gate the caller
    # marks as auto-fixing, and silently recording a bare mark would let a
    # later --update path believe an auto-fix gate is registered.
    auto_fix = list(args.auto_fix_gate or [])
    if auto_fix:
        die(
            "gate %s is marked auto-fixing; the ledger refuses an auto-fix gate"
            % auto_fix[0]
        )
    gates = {}
    for item in args.gate or []:
        if "=" not in item:
            die("gate needs NAME=COMMAND, got %r" % item)
        name, command = item.split("=", 1)
        gates[name.strip()] = gate_spec(name.strip(), command)

    labels = []
    seen_slugs = {}
    seen_labels = {}
    for spec in args.unit or []:
        role, item = parse_unit(spec)
        if not item.strip():
            die("blank slug in unit %r" % spec)
        slug = slugify(item)
        label = "%s:%s" % (role, item)
        key = slug.casefold()
        if key in seen_slugs:
            die("slug %r collides with %r (case-folded)" % (item, seen_slugs[key]))
        if label in seen_labels:
            die("label %r is used by two units" % label)
        seen_slugs[key] = item
        seen_labels[label] = True
        labels.append((role, item, slug, label))

    for spec in args.exclude or []:
        if ":" not in spec:
            die("exclude needs LABEL:REASON, got %r" % spec)
        label, reason = spec.split(":", 1)
        if not label.strip() or not reason.strip():
            die("exclude needs a label and a reason, got %r" % spec)

    unit_paths = parse_key_value(args.unit_path, "unit-path")

    request = read_text(args.request) if args.request else ""
    intent = read_text(args.intent) if args.intent else request
    atomic_write(led.path("request.txt"), request)
    atomic_write(led.path("intent.md"), intent)
    atomic_write(led.path("preamble.md"), "# Preamble\n\nHold every hard rule in this run.\n")
    atomic_write(led.path("facts.tsv"), "fact\ttier\tsource\n")

    for sub in (
        "access",
        "kinds",
        "items",
        "briefs",
        "returns",
        "baseline",
        "snapshots",
        "diffs",
        "gates",
        "outbound",
        "controls",
        "history",
    ):
        os.makedirs(led.path(sub), exist_ok=True)
    atomic_write(os.path.join(led.run_dir, ".gitignore"), "*\n")

    controls = led.path("controls")
    gate_records = {}
    for name, spec in gates.items():
        ext = plant_extension(spec["argv"])
        gate_controls = os.path.join(controls, slugify(name))
        os.makedirs(gate_controls, exist_ok=True)
        plant_name = "known-positive" + ext
        plant_path = os.path.join(gate_controls, plant_name)
        atomic_write(
            plant_path,
            "CONTROL_DEFECT\nCONTROL_MARKER\n#bad heading\n",
        )
        rc, output = run_gate_argv(spec["argv"], led.root, gate_controls)
        spec = dict(spec)
        spec["plant"] = os.path.relpath(plant_path, led.root)
        spec["reports_plant"] = bool(output and plant_name in output)
        spec["baseline_rc"] = rc
        spec["baseline_output"] = output or ""
        gate_records[name] = spec

    run_id = datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + short_hash(led.cwd, 4)
    led.run = {
        "run_id": run_id,
        "created": now_utc(),
        "phase_order": [args.phase],
        "bound": int(args.bound),
        "wave_size": int(args.wave),
        "severity_ladder": args.severity or ["blocker", "major", "minor"],
        "baseline_commit": git_head(led.root),
        "gates": gate_records,
        "exclusions": [],
        "owned_targets": [],
        "brief_tokens": {},
        "brief_hashes": {},
        "shared_blocks": {},
        "obligations": {},
        "permissions": {},
        "producers": {},
        "depths": {},
        "counters": {},
        "changes": [],
        "repair_list": [],
        "closed": False,
        "is_repo": led.is_repo,
        "probe_capabilities": {},
    }
    for spec in args.exclude or []:
        label, reason = spec.split(":", 1)
        led.run["exclusions"].append({"label": label.strip(), "reason": reason.strip()})
        with open(led.path("exclusions.tsv"), "a", encoding="utf-8") as fh:
            fh.write("%s\t%s\n" % (label.strip(), reason.strip()))
    for spec in args.owned_target or []:
        parts = spec.split(":")
        if len(parts) < 3:
            die("owned-target needs PATH:FAMILY:GATE, got %r" % spec)
        led.run["owned_targets"].append(
            {"path": parts[0], "family": parts[1], "gate": ":".join(parts[2:])}
        )
    for name, value in parse_key_value(args.counter, "counter").items():
        led.run["counters"][name] = value
    if not led.is_repo:
        store_hashed_walk(led)
        led.run["hashed_walk"] = True
        led.append({"type": "narrowing", "text": "working root is not a repository; hashed walk stands in"})

    for role, item, slug, label in labels:
        led.add_row(
            {
                "label": label,
                "phase": args.phase,
                "role": role,
                "item": slug,
                "path": unit_paths.get(label, ""),
                "kind": "writer" if role in ("produce", "write", "writer") else "reader",
                "state": "pending",
                "attempts": "0",
            }
        )

    record_baseline(led, request, intent)
    led.save()

    print("run: %s" % run_id)
    print("rows: %d" % len(led.rows))
    print("exclusions: %d" % len(led.run["exclusions"]))
    print("gates: %d" % len([g for g in gate_records.values() if not g.get("auto_fix")]))
    print(
        "known positives: %d"
        % len([g for g in gate_records.values() if g.get("reports_plant")])
    )
    return 0


def probe_brief(route, token, bound):
    return (
        "# Probe brief\n\n"
        "Route: %s\n\n"
        "Attempt one write inside the run directory, then report what you observed.\n"
        "State each capability as established, assumed_absent, or unverified.\n"
        "Return a fenced json block ending with END probe:%s\n"
        "Bound: %d seconds\n%s\n"
        % (route, slugify(route), bound, token)
    )


def init_probe(led, args):
    routes = []
    if args.cheapest:
        routes.append(args.cheapest)
    routes.extend(args.role or [])
    if not routes:
        die("init --probe needs --cheapest ROUTE or --role ROUTE")
    atomic_write(os.path.join(led.run_dir, ".gitignore"), "*\n")
    for sub in ("briefs", "returns", "controls", "history"):
        os.makedirs(led.path(sub), exist_ok=True)
    if os.path.exists(led.roster_path) and led.run:
        die("a run is already open; re-enter it with attach")
    existing = read_rows(led.roster_path)
    labels = set(row.get("label") for row in existing)
    bound = int(args.bound)
    for route in routes:
        slug = slugify(route)
        label = "probe:%s" % slug
        if label in labels:
            continue
        token = short_hash("probe:%s" % slug)
        atomic_write(led.path("briefs", "%s.txt" % label), probe_brief(route, token, bound))
        led.add_row(
            {
                "label": label,
                "phase": "probe",
                "role": "probe",
                "item": slug,
                "kind": "probe",
                "state": "pending",
                "attempts": "0",
                "brief_hash": sha256_text(probe_brief(route, token, bound)),
                "input_versions": json.dumps({"token": token}),
                "spawn_route": route,
            }
        )
    write_rows(led.roster_path, led.rows)
    print("probe rows: %d" % len(routes))
    print("run: none (init opens it)")
    return 0


# ---------------------------------------------------------------------------
# brief
# ---------------------------------------------------------------------------


STEERING_WORDS = (
    "you will find",
    "must fail",
    "should fail",
    "the bug is",
    "confirm that",
    "prove that",
    "there is a defect",
)


def render_permission_block(perms):
    lines = ["## Permissions", ""]
    for bucket in ("permits", "forbids"):
        for kind in ("paths", "commands"):
            values = perms.get(bucket, {}).get(kind, [])
            lines.append("%s %s: %s" % (bucket, kind, ", ".join(values) if values else "none"))
    return "\n".join(lines) + "\n"


def cmd_brief(args):
    led = Ledger()
    row = led.find_row(args.label)
    phase = args.phase or row.get("phase") or led.run.get("phase_order", ["work"])[0]
    row["phase"] = phase
    if phase not in led.run.get("phase_order", []):
        led.run.setdefault("phase_order", []).append(phase)

    body = read_text(args.body_file) if args.body_file else (args.body or "")
    shared = read_text(args.shared_file) if args.shared_file else read_text(led.path("preamble.md"))
    shared_hash = sha256_text(shared)
    recorded = led.run.setdefault("shared_blocks", {}).get(phase)
    if recorded and recorded != shared_hash:
        die("shared blocks differ within phase %s; refusing the brief" % phase)
    led.run["shared_blocks"][phase] = shared_hash

    perms = {"permits": {"paths": [], "commands": []}, "forbids": {"paths": [], "commands": []}}
    for bucket in ("permits", "forbids"):
        for kind in ("paths", "commands"):
            key = "%s_%s" % (bucket[:-1], kind[:-1])
            perms[bucket][kind] = list(getattr(args, key) or [])
    for kind in ("paths", "commands"):
        both = set(perms["permits"][kind]) & set(perms["forbids"][kind])
        if both:
            die("brief names %s under both permits and forbids: %s" % (kind, ", ".join(sorted(both))))

    obligations = list(args.obligation or [])
    relays = list(args.relay or [])
    input_versions = {"relayed": {}, "withheld": []}
    for relay in relays:
        upstream = led.row_or_none(relay)
        if not upstream or upstream.get("state") not in ("accepted", "inability"):
            die("relay %s names an upstream row that is not accepted" % relay)
        path = led.path("returns", "%s.md" % relay)
        digest = file_hash(path)
        input_versions["relayed"][relay] = digest
        led.run.setdefault("producers", {})[args.label] = relay

    withheld_hashes = []
    if args.withheld:
        withheld_text = sys.stdin.read()
        withheld_hashes.append(sha256_text(withheld_text))
        # Only the hash reaches the run files. The blind row's input versions
        # carry the hash alone, and no path or body is recorded.
        led.run.setdefault("withheld_sources", {}).setdefault(args.label, []).append(
            {"hash": withheld_hashes[-1]}
        )
    input_versions["withheld"] = withheld_hashes

    target = row.get("path") or args.target or ""
    if target:
        row["path"] = target
        recorded_dir = "snapshots" if row.get("kind") == "reader" else "baseline"
        src = os.path.join(led.root, target)
        if os.path.isfile(src):
            dest = os.path.join(led.path(recorded_dir, "inputs", args.label), target)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copyfile(src, dest)
            input_versions["target"] = file_hash(dest)
            input_versions["target_path"] = target

    token = short_hash(led.run.get("baseline_commit", "") + args.label + body + shared)
    led.run.setdefault("brief_tokens", {})[args.label] = token
    led.run.setdefault("obligations", {})[args.label] = obligations
    led.run.setdefault("permissions", {})[args.label] = perms
    if args.depth is not None:
        led.run.setdefault("depths", {})[args.label] = int(args.depth)
    if args.kind:
        row["kind"] = args.kind

    checker = bool(args.checker) or row.get("role") in ("check", "checker")
    warning = ""
    if checker:
        lowered = (shared + "\n" + body).lower()
        hits = [word for word in STEERING_WORDS if word in lowered]
        if hits:
            warning = "warning: checker brief carries steering words: %s\n" % ", ".join(hits)

    closing = []
    closing.append("## Return")
    closing.append("Return template: fenced json block with label, brief, status, verdict, examined, checklist, findings, forks, beyond_brief, incidents, own_authority, alternatives, brief_corrections, dropped_suspicions, notes.")
    closing.append("Return channel: write returns/%s.md as your last act." % args.label)
    closing.append("End with: END %s" % args.label)
    closing.append("Delegate no part of your item; perform your own item.")
    closing.append("Capabilities stated as facts: use only what this brief establishes.")
    closing.append("Bound: %d seconds." % int(led.run.get("bound", 900)))
    closing.append(token)

    text = (
        "# Brief %s\n\nphase: %s\nrole: %s\nitem: %s\n\n%s\n\n%s\n\n%s\n%s"
        % (
            args.label,
            phase,
            row.get("role", ""),
            row.get("item", ""),
            shared,
            body,
            render_permission_block(perms),
            "\n".join(closing) + "\n",
        )
    )
    dest = led.path("briefs", "%s.txt" % args.label)
    atomic_write(dest, text)
    row["brief_hash"] = sha256_text(text)
    row["input_versions"] = json.dumps(input_versions, sort_keys=True)
    row["stamp_owner"] = args.stamp_owner or row.get("stamp_owner", "")
    led.save()
    if warning:
        sys.stderr.write(warning)
    print("brief: %s" % args.label)
    print("token: %s" % token)
    return 0


# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------


def row_is_writer(row):
    return row.get("kind") in ("writer", "write", "produce") or row.get("role") in (
        "produce",
        "write",
        "writer",
    )


def row_is_checker(row):
    return row.get("kind") in ("check", "checker", "recheck") or row.get("role") in (
        "check",
        "checker",
        "verify",
        "verifier",
    )


def cmd_dispatch(args):
    led = Ledger()
    if os.path.exists(led.path("STOP")):
        die("STOP is present; nothing new is dispatched")
    row = led.find_row(args.label)
    if row.get("phase") == "probe" and not led.run:
        die("probe row needs an open run; run init first")
    if row.get("state") in ("accepted", "inability", "failed", "unreturned", "dropped"):
        die("row %s is already terminal (%s)" % (args.label, row.get("state")))
    if int(row.get("attempts") or 0) >= 2:
        die("row %s already had two attempts; a third is refused" % args.label)

    if row_is_writer(row):
        wave = int(led.run.get("wave_size", 2))
        unchecked = [
            r
            for r in led.rows
            if row_is_writer(r) and r.get("state") == "dispatched"
        ]
        if len(unchecked) >= wave:
            die("wave size %d reached: %d written rows are unchecked" % (wave, len(unchecked)))
        if led.open_gates():
            die("a user gate is open; a writer row waits for its answer")

    if row.get("kind") == "repair" and row.get("path"):
        prior = [
            rec
            for rec in led.records()
            if rec.get("type") == "dispatch"
            and rec.get("kind") == "repair"
            and rec.get("path") == row.get("path")
        ]
        if prior:
            die("path %s was already repaired once; a second repair is refused" % row.get("path"))
    if row.get("kind") == "recheck":
        prior = [
            rec
            for rec in led.records()
            if rec.get("type") == "dispatch"
            and rec.get("kind") == "recheck"
            and rec.get("path") == row.get("path")
        ]
        if prior:
            die("item %s was already re-checked once; a second re-check is refused" % row.get("item"))

    row["state"] = "dispatched"
    row["attempts"] = str(int(row.get("attempts") or 0) + 1)
    row["dispatched_at"] = now_utc()
    row["spawn_route"] = args.route or row.get("spawn_route") or "generic"
    row["helper_id"] = args.helper_id or row.get("helper_id", "")
    row["model_req"] = args.model if args.model is not None else row.get("model_req", "")
    row["effort_req"] = args.effort if args.effort is not None else row.get("effort_req", "")
    led.append(
        {
            "type": "dispatch",
            "label": args.label,
            "kind": row.get("kind"),
            "path": row.get("path"),
            "item": row.get("item"),
            "attempt": row["attempts"],
            "route": row["spawn_route"],
            "helper_id": row["helper_id"],
        }
    )
    led.save()
    print("dispatched: %s" % args.label)
    return 0


# ---------------------------------------------------------------------------
# accept
# ---------------------------------------------------------------------------


def fenced_blocks(text):
    pattern = re.compile(r"```([A-Za-z0-9_-]*)[ \t]*\n(.*?)\n```", re.S)
    return pattern.findall(text)


def is_placeholder(value):
    if value is None:
        return True
    if not isinstance(value, str):
        return False
    text = value.strip()
    if not text:
        return True
    if text in ("...", "\u2026"):
        return True
    if re.match(r"^<[^>]+>$", text):
        return True
    lowered = text.lower()
    return any(marker in lowered for marker in PLACEHOLDER_MARKERS)


def recorded_input_path(led, label, rel):
    candidates = [
        led.path("snapshots", "inputs", label, rel),
        led.path("baseline", "inputs", label, rel),
        led.path("baseline", "copies", rel),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return ""


def validate_return(led, row, text, source):
    errors = []
    label = row.get("label", "")
    stripped = text.rstrip("\n").rstrip()
    lines = [line.rstrip() for line in stripped.splitlines() if line.strip()]
    end_ok = bool(lines) and lines[-1] == "END %s" % label
    if not end_ok:
        errors.append("missing END line (expected END %s)" % label)

    blocks = fenced_blocks(text)
    if len(blocks) != 1:
        errors.append("block count is %d, expected exactly one" % len(blocks))
        return errors, None
    language, body = blocks[0]
    try:
        data = json.loads(body)
    except ValueError as exc:
        errors.append("json block is unreadable: %s" % exc)
        return errors, None
    if not isinstance(data, dict):
        errors.append("json block is not an object")
        return errors, None

    if data.get("label") != label:
        errors.append("echoed label %r disagrees with %r" % (data.get("label"), label))
    token = led.run.get("brief_tokens", {}).get(label, "")
    if not token or data.get("brief") != token:
        errors.append("brief token disagrees with the roster")

    for key in RETURN_KEYS:
        if key not in data:
            errors.append("required key missing: %s" % key)
    if data.get("status") not in ("done", "inability"):
        errors.append("status %r is outside done|inability" % data.get("status"))
    if data.get("verdict") not in ("pass", "fail"):
        errors.append("verdict %r is outside pass|fail" % data.get("verdict"))

    examined = data.get("examined") or []
    if not isinstance(examined, list):
        errors.append("examined is not a list")
        examined = []
    examined_paths = []
    for entry in examined:
        if not isinstance(entry, dict):
            errors.append("examined entry is not an object")
            continue
        path = entry.get("path", "")
        how = entry.get("how", "")
        receipt = entry.get("receipt", "")
        examined_paths.append(path)
        if is_placeholder(path):
            errors.append("examined path is a placeholder: %r" % path)
        if how not in ("full", "searched", "unreachable"):
            errors.append("examined how %r is outside full|searched|unreachable" % how)
        if is_placeholder(receipt):
            errors.append("examined receipt is a placeholder for %s" % path)
            continue
        recorded = recorded_input_path(led, label, path)
        if not recorded:
            errors.append("examined %s has no recorded input version" % path)
            continue
        recorded_text = read_text(recorded)
        needle = receipt.strip()
        if needle not in recorded_text:
            errors.append("receipt for %s is missing from the recorded input version" % path)

    obligations = led.run.get("obligations", {}).get(label, []) or []
    for required in obligations:
        if required not in examined_paths:
            errors.append("examined list does not cover obligation %s" % required)

    checklist = data.get("checklist") or []
    if not isinstance(checklist, list):
        errors.append("checklist is not a list")
        checklist = []
    for entry in checklist:
        if not isinstance(entry, dict):
            errors.append("checklist entry is not an object")
            continue
        verdict = entry.get("verdict")
        if verdict not in ("pass", "fail"):
            errors.append("checklist verdict %r is outside pass|fail" % verdict)
        span = entry.get("span", "")
        if is_placeholder(span):
            errors.append("checklist line cites a placeholder span: %r" % span)
        elif verdict == "pass" and not str(span).strip():
            errors.append("a passing checklist line cites no span")

    for finding in data.get("findings") or []:
        if not isinstance(finding, dict):
            errors.append("finding is not an object")
            continue
        for key in ("claim", "severity", "quote", "anchor"):
            if is_placeholder(finding.get(key)):
                errors.append("finding %s is a placeholder or missing" % key)
        ladder = led.run.get("severity_ladder", [])
        if ladder and finding.get("severity") not in ladder:
            errors.append("finding severity %r is outside the ladder" % finding.get("severity"))

    withheld = led.run.get("withheld_sources", {}).get(label, [])
    if withheld:
        seen = data.get("withheld_seen") or []
        recorded = set(item.get("hash") for item in withheld)
        for value in seen:
            if value in recorded:
                errors.append("a blind row returned the withheld text it must not see")

    for fork in data.get("forks") or []:
        if not isinstance(fork, dict):
            errors.append("fork is not an object")
            continue
        if is_placeholder(fork.get("issue")):
            errors.append("fork issue is a placeholder")
        options = fork.get("options") or []
        if not isinstance(options, list) or not (2 <= len(options) <= 4):
            errors.append("fork needs two to four options")
        if is_placeholder(fork.get("preferred")):
            errors.append("fork preferred end state is a placeholder")

    return errors, data


def accept_probe(led, args):
    label = args.label
    row = led.row_or_none(label)
    if not row or row.get("phase") != "probe":
        die("%s is not a probe row" % label)
    text = read_text(led.path("returns", "%s.md" % label))
    blocks = fenced_blocks(text)
    data = None
    if blocks:
        try:
            data = json.loads(blocks[0][1])
        except ValueError:
            data = None
    if data is None:
        try:
            data = json.loads(text)
        except ValueError:
            die("probe return %s is not readable json" % label)
    caps = dict(data.get("capabilities") or {})
    marker = led.path("returns", "%s.start" % label)
    caps["read_only"] = "not-enforced" if os.path.exists(marker) else "enforced"
    if args.observed_model:
        caps["model"] = "observed"
    else:
        caps["model"] = "unobserved"
    if args.observed_effort:
        caps["depth"] = "observed"
    else:
        caps["depth"] = "unobserved"
    for key, value in list(caps.items()):
        if value not in ("established", "assumed_absent", "unverified", "enforced", "not-enforced", "observed", "unobserved"):
            die("probe capability %s has value %r outside the allowed set" % (key, value))
    probe_path = led.path("probe.json")
    store = {}
    if os.path.exists(probe_path):
        try:
            store = json.loads(read_text(probe_path))
        except ValueError:
            store = {}
    store[label] = caps
    atomic_write(probe_path, json.dumps(store, indent=2, sort_keys=True) + "\n")
    row["state"] = "accepted"
    row["source"] = args.source or "file"
    row["returned_at"] = now_utc()
    row["model_obs"] = "observed" if args.observed_model else "unobserved"
    row["effort_obs"] = "observed" if args.observed_effort else "unobserved"
    led.save_rows()
    print("probe accepted: %s" % label)
    for key in sorted(caps):
        print("%s: %s" % (key, caps[key]))
    return 0


def extract_log_message(text):
    """Return the last host-log ``result`` payload, or an empty string."""
    message = ""
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            data = json.loads(line)
        except ValueError:
            continue
        if isinstance(data, dict) and isinstance(data.get("result"), str):
            message = data["result"]
    return message


def read_accept_text(led, args):
    label = args.label
    dest = led.path("returns", "%s.md" % label)
    if args.stdin is not None:
        raw = sys.stdin.read()
        source = args.source or "relayed"
        text = raw
        if source == "log":
            extracted = extract_log_message(raw)
            if extracted:
                text = extracted
        atomic_write(dest, text)
        return text, source
    if args.log:
        raw = read_text(args.log)
        text = extract_log_message(raw) or raw
        atomic_write(dest, text)
        return text, "log"
    return read_text(dest), "file"


def import_records(led, row, data):
    label = row.get("label", "")
    producer = led.run.get("producers", {}).get(label, "")
    for listname in RECORD_LISTS:
        values = data.get(listname) or []
        if not isinstance(values, list):
            continue
        singular = listname[:-1] if listname.endswith("s") else listname
        for idx, item in enumerate(values):
            if not isinstance(item, dict):
                item = {"text": str(item)}
            rec = dict(item)
            rec["id"] = "%s:%s:%d" % (label, listname, idx)
            rec["row"] = label
            rec["label"] = label
            rec["list"] = listname
            if listname == "findings":
                rec["type"] = "finding"
            elif listname == "forks":
                rec["type"] = "fork"
            elif listname == "confirmations":
                rec["type"] = "confirmation"
                rec["provenance"] = "recall-confirmed" if producer else "independently surfaced"
                if not producer:
                    rec["provenance"] = "independently surfaced"
            else:
                rec["type"] = singular
            led.append(rec)


def small_return_warning(led, label, text):
    sizes = []
    returns_dir = led.path("returns")
    if os.path.isdir(returns_dir):
        for name in os.listdir(returns_dir):
            if not name.endswith(".md") or name[:-3] == label:
                continue
            full = os.path.join(returns_dir, name)
            if os.path.isfile(full):
                sizes.append(os.path.getsize(full))
    if not sizes:
        return ""
    sizes.sort()
    median = sizes[len(sizes) // 2]
    size = len(text.encode("utf-8"))
    if median and size * 4 < median:
        return (
            "warning: return for %s is far smaller than its siblings "
            "(%d bytes against a median of %d)\n" % (label, size, median)
        )
    return ""


def cmd_accept(args):
    led = Ledger(require_run=False)
    if args.probe:
        return accept_probe(led, args)
    if not led.run:
        die("no open run; run init first")
    row = led.find_row(args.label)
    if args.wait:
        deadline = time.time() + 90
        while time.time() < deadline:
            pending = [
                r
                for r in led.rows
                if r.get("state") == "dispatched" and not os.path.exists(
                    led.path("returns", "%s.md" % r.get("label"))
                )
            ]
            if not pending:
                break
            time.sleep(0.5)
        for r in led.rows:
            if r.get("state") != "dispatched":
                continue
            if os.path.exists(led.path("returns", "%s.md" % r.get("label"))):
                continue
            deadline_dt = parse_utc(r.get("dispatched_at"))
            bound = int(led.run.get("bound", 900))
            if deadline_dt is not None:
                age = (datetime.datetime.now(datetime.timezone.utc) - deadline_dt).total_seconds()
                if age > bound:
                    r["state"] = "unreturned"
        led.save_rows()

    text, source = read_accept_text(led, args)
    if not text.strip():
        die("return for %s is empty" % args.label)

    errors, data = validate_return(led, row, text, source)
    if errors and source == "relayed" and args.stdin is not None:
        # The same stdin channel carries a verbatim final message or a piped
        # host log. A log's last ``result`` payload is the final message, so
        # retry the validation against it before rejecting.
        extracted = extract_log_message(text)
        if extracted and extracted != text:
            retry_errors, retry_data = validate_return(led, row, extracted, "log")
            if not retry_errors:
                text, data, errors, source = extracted, retry_data, [], "log"
                atomic_write(led.path("returns", "%s.md" % args.label), text)
    if errors and args.classify:
        row["state"] = "accepted"
        row["source"] = source
        row["returned_at"] = now_utc()
        led.append({"type": "classification", "label": args.label, "text": args.classify})
        led.save()
        print("accepted free text: %s (%s)" % (args.label, args.classify))
        return 0
    if errors:
        prior = [
            rec
            for rec in led.records()
            if rec.get("type") == "accept_reject" and rec.get("label") == args.label
        ]
        row["state"] = "violation" if not prior else "failed"
        led.append(
            {
                "type": "accept_reject",
                "label": args.label,
                "errors": errors,
                "source": source,
            }
        )
        led.save()
        sys.stderr.write("return rejected for %s:\n" % args.label)
        for err in errors:
            sys.stderr.write("  - %s\n" % err)
        return 1

    row["state"] = "inability" if data.get("status") == "inability" else "accepted"
    row["source"] = source
    return_path = led.path("returns", "%s.md" % args.label)
    if os.path.exists(return_path):
        row["returned_at"] = datetime.datetime.fromtimestamp(
            os.path.getmtime(return_path), datetime.timezone.utc
        ).replace(microsecond=0).isoformat()
    else:
        row["returned_at"] = now_utc()
    row["model_obs"] = args.observed_model or "unobserved"
    row["effort_obs"] = args.observed_effort or "unobserved"
    marker = led.path("returns", "%s.start" % args.label)
    if os.path.exists(marker):
        row["start_marker_time"] = datetime.datetime.fromtimestamp(
            os.path.getmtime(marker), datetime.timezone.utc
        ).replace(microsecond=0).isoformat()
    import_records(led, row, data)
    warning = small_return_warning(led, args.label, text)
    led.append(
        {
            "type": "accept",
            "label": args.label,
            "state": row["state"],
            "source": source,
        }
    )
    led.save()
    if warning:
        sys.stderr.write(warning)
    print("accepted: %s (%s)" % (args.label, row["state"]))
    return 0


# ---------------------------------------------------------------------------
# rows
# ---------------------------------------------------------------------------


def new_row_from_record(led, rec, phase, role):
    item = slugify(str(rec.get("id") or rec.get("row") or "item"))
    label = "%s:%s" % (role, item)
    if led.row_or_none(label):
        die("row %s already exists" % label)
    led.add_row(
        {
            "label": label,
            "phase": phase,
            "role": role,
            "item": item,
            "path": rec.get("path", "") or rec.get("target", ""),
            "kind": "check" if role in ("check", "checker") else "reader",
            "state": "pending",
            "attempts": "0",
            "stamp_owner": rec.get("id", ""),
        }
    )
    led.append(
        {
            "type": "row_source",
            "label": label,
            "source_phase": phase,
            "record": rec.get("id", ""),
        }
    )
    return label


def cmd_rows(args):
    led = Ledger()
    phase = args.phase
    role = args.role or "check"
    created = []
    if args.from_records:
        for rec in led.records():
            if rec.get("type") in ("finding", "incident", "own_authority", "confirmation") and fnmatch.fnmatch(
                str(rec.get("id", "")), args.from_records
            ):
                created.append(new_row_from_record(led, rec, phase, role))
    elif args.from_repair_list:
        for entry in led.run.get("repair_list", []):
            rec = {"id": entry.get("id") or entry.get("path"), "path": entry.get("path")}
            created.append(new_row_from_record(led, rec, phase, role))
    elif args.from_gaps:
        source = led.find_row(args.from_gaps)
        for rec in led.records():
            if rec.get("type") == "gap" and rec.get("row") == source.get("label"):
                created.append(new_row_from_record(led, rec, phase, role))
    else:
        die("rows needs --from-records, --from-repair-list, or --from-gaps")
    if phase not in led.run.get("phase_order", []):
        led.run.setdefault("phase_order", []).append(phase)
    led.save()
    for label in created:
        print("row: %s" % label)
    return 0


# ---------------------------------------------------------------------------
# dispose
# ---------------------------------------------------------------------------


def cmd_dispose(args):
    led = Ledger()
    changed = False
    if args.id:
        targets = [
            rec
            for rec in led.records()
            if rec.get("type") in ("finding", "fork", "incident", "own_authority", "confirmation", "alternative")
            and fnmatch.fnmatch(str(rec.get("id", "")), args.id)
        ]
        if not targets:
            die("no record matches %s" % args.id)
        for rec in targets:
            if args.disposition not in ("applied", "refuted", "surfaced", "deferred"):
                die("disposition %r is outside applied|refuted|surfaced|deferred" % args.disposition)
            record = {
                "type": "disposition",
                "target": rec.get("id"),
                "disposition": args.disposition,
                "tag": args.tag or "",
                "span": args.span or "",
                "packet": args.packet or "",
                "pointer": args.pointer or "",
            }
            led.append(record)
            changed = True
    if args.narrowing:
        led.append({"type": "narrowing", "text": args.narrowing, "drops": args.drops or ""})
        changed = True
    if args.open_gate:
        led.append(
            {
                "type": "user_gate",
                "id": args.open_gate,
                "question": args.question or "",
                "state": "open",
            }
        )
        changed = True
    if args.gate:
        if not args.answered:
            die("--gate needs --answered")
        led.append(
            {
                "type": "gate_answered",
                "gate_id": args.gate,
                "answer": args.answered,
                "answered_at": now_utc(),
            }
        )
        changed = True
    if args.fork:
        if not args.own_decision:
            die("--fork needs --own-decision")
        led.append(
            {
                "type": "own_authority",
                "id": args.fork,
                "fork": args.fork,
                "text": args.own_decision,
                "own_decision": args.own_decision,
            }
        )
        changed = True
    if args.flag:
        if not args.reason:
            die("--flag needs --reason")
        led.append({"type": "flag", "label": args.flag, "reason": args.reason})
        changed = True
    if not changed:
        die("dispose needs a disposition, narrowing, gate, fork, or flag")
    print("recorded")
    return 0


# ---------------------------------------------------------------------------
# diff
# ---------------------------------------------------------------------------


def baseline_copy(led, rel):
    path = led.path("baseline", "copies", rel)
    if os.path.isfile(path):
        return read_text(path)
    proc = git(["show", "%s:%s" % (led.run.get("baseline_commit", "HEAD"), rel)], led.root)
    if proc.returncode == 0:
        return proc.stdout.decode("utf-8", "replace")
    return ""


def current_text(led, rel):
    path = os.path.join(led.root, rel)
    if os.path.isfile(path):
        return read_text(path)
    return ""


def date_only(before, after):
    def strip_dates(text):
        return re.sub(r"\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2})?)?", "DATE", text)

    return before != after and strip_dates(before) == strip_dates(after)


def mostly_deleted(before, after):
    before_lines = before.splitlines()
    after_lines = after.splitlines()
    if not before_lines:
        return False
    removed = len(set(before_lines) - set(after_lines))
    return removed > 0 and removed * 2 > len(before_lines)


def append_only_violation(before, after):
    if not before:
        return False
    return not after.startswith(before)


def attribution_for(led, rel):
    for row in led.rows:
        if row.get("path") and norm_path(led.root, row.get("path")) == rel:
            return row.get("label")
    return "orchestrator"


def make_change(led, rel, before, after):
    flags = []
    if date_only(before, after):
        flags.append("date-only")
    if mostly_deleted(before, after):
        flags.append("mostly-deleted")
    if append_only_violation(before, after):
        flags.append("append-only-violation")
    diff_text = "".join(
        difflib.unified_diff(
            before.splitlines(True),
            after.splitlines(True),
            fromfile="a/" + rel,
            tofile="b/" + rel,
        )
    )
    dest = led.path("diffs", slugify(rel) + ".diff")
    atomic_write(dest, diff_text)
    return {
        "path": rel,
        "attribution": attribution_for(led, rel),
        "flags": flags,
        "checks": [],
        "gate": "",
        "diff": os.path.relpath(dest, led.root),
    }


def cmd_diff(args):
    led = Ledger()
    changes = []
    if led.run.get("hashed_walk"):
        baseline = {}
        walk_text = read_text(led.path("baseline", "walk.json"))
        if walk_text.strip():
            baseline = json.loads(walk_text)
        current = hashed_walk(led.root)
        for rel in sorted(set(baseline) | set(current)):
            if baseline.get(rel) == current.get(rel):
                continue
            copy_path = led.path("baseline", "walk-copies", rel)
            before = read_text(copy_path) if os.path.isfile(copy_path) else ""
            changes.append(make_change(led, rel, before, current_text(led, rel)))
    else:
        baseline_status = set()
        for line in read_text(led.path("baseline", "status")).splitlines():
            # Keep the leading status space: a modified tracked file reads
            # " M path", so stripping first would eat the first path character.
            if line.strip() and len(line) > 3:
                baseline_status.add(line[3:])
        current = git_status(led.root)
        current_paths = [path for code, path in current if not under_run_dir(led.root, path)]
        changed = sorted(set(current_paths) | baseline_status)
        for rel in changed:
            changes.append(
                make_change(led, rel, baseline_copy(led, rel), current_text(led, rel))
            )

        head = git_head(led.root)
        if head != led.run.get("baseline_commit", ""):
            changes.append({"path": "<HEAD>", "attribution": "orchestrator", "flags": ["head-move"], "checks": [], "gate": ""})
        stash = git_stash_list(led.root)
        if stash != read_text(led.path("baseline", "stash-list")).strip():
            changes.append({"path": "<stash>", "attribution": "orchestrator", "flags": ["stash-change"], "checks": [], "gate": ""})
        baseline_ignored = set(
            p for p in read_text(led.path("baseline", "ignored")).splitlines() if p
        )
        current_ignored = set(p for p in git_ignored(led.root) if not under_run_dir(led.root, p))
        for rel in sorted(current_ignored - baseline_ignored):
            changes.append({"path": rel, "attribution": "orchestrator", "flags": ["new-ignored-residue"], "checks": [], "gate": ""})

    led.run["changes"] = changes

    if args.add_checks:
        for change in changes:
            rel = change["path"]
            if rel.startswith("<"):
                continue
            item = slugify(rel)
            label = "check:%s" % item
            if led.row_or_none(label):
                change["checks"].append(label)
                continue
            led.add_row(
                {
                    "label": label,
                    "phase": led.run.get("phase_order", ["work"])[0],
                    "role": "check",
                    "item": item,
                    "path": rel,
                    "kind": "check",
                    "state": "pending",
                    "attempts": "0",
                }
            )
            change["checks"].append(label)
            led.append({"type": "check", "label": label, "path": rel, "state": "open"})

    if args.approved_edits:
        approved = json.loads(read_text(args.approved_edits))
        if isinstance(approved, dict):
            approved = approved.get("edits", [])
        for change in changes:
            rel = change["path"]
            if rel.startswith("<"):
                continue
            before = baseline_copy(led, rel).splitlines()
            after = current_text(led, rel).splitlines()
            matcher = difflib.SequenceMatcher(None, before, after)
            for tag, i1, i2, j1, j2 in matcher.get_opcodes():
                if tag == "equal":
                    continue
                block = "\n".join(after[j1:j2])
                mapped = None
                for edit in approved:
                    if edit.get("path") == rel and edit.get("text", "") in block:
                        mapped = edit.get("id")
                        break
                if mapped:
                    print("mapped %s %s" % (mapped, rel))
                else:
                    print("unmapped %s:%d-%d" % (rel, j1 + 1, j2))

    if args.count:
        counters = dict(led.run.get("counters", {}))
        for item in args.counter or []:
            if "=" not in item:
                die("counter needs NAME=PATTERN, got %r" % item)
            name, pattern = item.split("=", 1)
            counters[name] = pattern
        control = "CONTROL_MARKER\n"
        for name, pattern in counters.items():
            if not re.search(pattern, control):
                die("counter %s misses its own known positive; failing closed" % name)
            print("counter %s: %d" % (name, len(re.findall(pattern, control))))
        led.run["counters"] = counters

    led.append({"type": "diff", "changes": [c["path"] for c in changes]})
    led.save()
    print("changed: %d" % len(changes))
    for change in changes:
        flags = (" flags=" + ",".join(change["flags"])) if change["flags"] else ""
        print("  %s -> %s%s" % (change["path"], change["attribution"], flags))
    return 0


# ---------------------------------------------------------------------------
# gate
# ---------------------------------------------------------------------------


def cmd_gate(args):
    led = Ledger()
    command = [arg for arg in (args.command or []) if arg != "--"]
    if not command:
        die("gate needs a command after --")
    resolved = shutil.which(command[0])
    if not resolved:
        led.append(
            {
                "type": "narrowing",
                "text": "gate %s unavailable: executable %s does not resolve" % (args.name, command[0]),
            }
        )
        led.save()
        die("gate %s unavailable: executable %s does not resolve" % (args.name, command[0]))
    proc = subprocess.run(
        [resolved] + command[1:],
        cwd=led.root,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    output = proc.stdout.decode("utf-8", "replace")
    gate = led.run.get("gates", {}).get(args.name, {})
    filtered = output
    if gate.get("reports_plant") and gate.get("plant"):
        kept = []
        dropped = 0
        for line in output.splitlines():
            if RUN_NAME in line or gate.get("plant", "") in line:
                dropped += 1
                continue
            kept.append(line)
        if dropped:
            filtered = "\n".join(kept)
            print("dropped %d run-directory finding(s) for gate %s" % (dropped, args.name))
    expect = args.expect
    ok = proc.returncode == 0
    silent = not output.strip()
    if expect == "nonempty":
        ok = ok and not silent
    elif expect == "count":
        counters = led.run.get("counters", {})
        if not counters:
            die("gate %s needs a counter whose positive control passed" % args.name)
        ok = ok and not silent
    elif expect == "exit0":
        ok = ok
    record = {
        "type": "gate_result",
        "name": args.name,
        "exit": proc.returncode,
        "silent": silent,
        "executable": resolved,
        "output": filtered,
        "expect": expect or "",
        "ok": ok,
        "baseline": bool(args.on_baseline),
    }
    led.append(record)
    if args.on_baseline:
        led.run.setdefault("gate_baseline", {})[args.name] = {"exit": proc.returncode, "output": filtered}
    else:
        baseline = led.run.get("gate_baseline", {}).get(args.name)
        if baseline is not None:
            print("baseline difference: %s" % ("same" if baseline.get("output") == filtered else "differs"))
    led.save()
    print("gate %s: exit=%d silent=%s executable=%s" % (args.name, proc.returncode, silent, resolved))
    if not ok:
        return 1
    return 0


# ---------------------------------------------------------------------------
# snapshot
# ---------------------------------------------------------------------------


def cmd_snapshot(args):
    led = Ledger()
    copied = 0
    for rel in args.paths:
        rel = norm_path(led.root, rel)
        dest = led.path("snapshots", args.label, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if args.base:
            proc = git(["show", "%s:%s" % (led.run.get("baseline_commit", "HEAD"), rel)], led.root)
            if proc.returncode != 0:
                die("git show could not read %s at the base commit" % rel)
            atomic_write(dest, proc.stdout)
        else:
            src = os.path.join(led.root, rel)
            if not os.path.isfile(src):
                die("snapshot source %s does not exist" % rel)
            shutil.copyfile(src, dest)
        copied += 1
    led.run.setdefault("snapshots", {})[args.label] = {
        "base": bool(args.base),
        "paths": [norm_path(led.root, p) for p in args.paths],
    }
    led.save()
    print("snapshotted: %d file(s) for %s" % (copied, args.label))
    return 0


# ---------------------------------------------------------------------------
# status, show, search, stop
# ---------------------------------------------------------------------------


def print_tally(led):
    counts = led.state_counts()
    print("tally: rows=%d accepted=%d inability=%d failed=%d unreturned=%d dropped=%d"
          % (
              len(led.rows),
              counts.get("accepted", 0),
              counts.get("inability", 0),
              counts.get("failed", 0),
              counts.get("unreturned", 0),
              counts.get("dropped", 0),
          ))


def cmd_status(args):
    led = Ledger()
    print("run: %s" % led.run.get("run_id", "?"))
    print("state: %s" % ("closed" if led.run.get("closed") else "open"))
    print_tally(led)
    bound = int(led.run.get("bound", 900))
    print("open rows:")
    any_open = False
    for row in led.rows:
        if row.get("state") in TERMINAL:
            continue
        any_open = True
        deadline = ""
        dispatched = parse_utc(row.get("dispatched_at"))
        if dispatched is not None:
            deadline = (dispatched + datetime.timedelta(seconds=bound)).isoformat()
        print("  %s state=%s deadline=%s" % (row.get("label"), row.get("state"), deadline or "-"))
    if not any_open:
        print("  none")
    print("open gates:")
    gates = led.open_gates()
    for gate in gates:
        print("  %s %s" % (gate.get("id"), gate.get("question", "")))
    if not gates:
        print("  none")
    print("repair list:")
    for entry in led.run.get("repair_list", []):
        print("  %s" % entry.get("path", entry))
    if not led.run.get("repair_list"):
        print("  none")
    print("resume:")
    for row in led.rows:
        if row.get("brief_hash"):
            print("  %s %s" % (row.get("brief_hash"), row.get("label")))
    intervals = []
    for row in led.rows:
        start = parse_utc(row.get("start_marker_time"))
        end = parse_utc(row.get("returned_at"))
        if start is not None and end is not None:
            intervals.append((row.get("label"), start, end))
    print("intervals:")
    for index, (label, start, end) in enumerate(intervals):
        others = []
        for other_index, (other, other_start, other_end) in enumerate(intervals):
            if index == other_index:
                continue
            if start < other_end and other_start < end:
                others.append(other)
        state = "overlap" if others else "serial"
        print("  %s start=%s return=%s %s" % (label, start.isoformat(), end.isoformat(), state))
        for other in others:
            if label < other:
                print("overlap: %s %s" % (label, other))
    return 0


def cmd_show(args):
    led = Ledger()
    row = led.find_row(args.label)
    for name in COLUMNS:
        print("%s: %s" % (name, row.get(name, "")))
    print("records:")
    for rec in led.records_of(args.label):
        print("  " + json.dumps(rec, sort_keys=True))
    return 0


def cmd_search(args):
    led = Ledger()
    control_path = led.path("controls", "search-control.txt")
    atomic_write(control_path, "LEDGER_SEARCH_CONTROL\n")
    control_hit = False
    for dirpath, dirnames, filenames in os.walk(led.run_dir):
        for name in filenames:
            full = os.path.join(dirpath, name)
            if "LEDGER_SEARCH_CONTROL" in read_text(full):
                control_hit = True
    if not control_hit:
        die("search positive control failed")
    pattern = re.compile(args.pattern)
    hits = 0
    for dirpath, dirnames, filenames in os.walk(led.run_dir):
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, led.run_dir)
            for number, line in enumerate(read_text(full).splitlines(), 1):
                if pattern.search(line):
                    hits += 1
                    print("%s:%d:%s" % (rel, number, line))
    print("positive control: passed")
    print("hits: %d" % hits)
    return 0


def cmd_stop(args):
    led = Ledger(require_run=False)
    os.makedirs(led.run_dir, exist_ok=True)
    atomic_write(os.path.join(led.run_dir, ".gitignore"), "*\n")
    atomic_write(led.path("STOP"), now_utc() + "\n")
    print("STOP created")
    return 0


# ---------------------------------------------------------------------------
# close
# ---------------------------------------------------------------------------


def tally_block(led):
    counts = led.state_counts()
    records = led.records()
    confirmations = [rec for rec in records if rec.get("type") == "confirmation"]
    recall = len([rec for rec in confirmations if rec.get("provenance") == "recall-confirmed"])
    independent = len(
        [rec for rec in confirmations if rec.get("provenance") == "independently surfaced"]
    )
    checks = [rec for rec in records if rec.get("type") == "check"]
    gates = [rec for rec in records if rec.get("type") == "gate_result"]
    lines = [
        "TALLY-BEGIN",
        "rows %d" % len(led.rows),
        "accepted %d" % counts.get("accepted", 0),
        "inability %d" % counts.get("inability", 0),
        "failed %d" % counts.get("failed", 0),
        "unreturned %d" % counts.get("unreturned", 0),
        "dropped %d" % counts.get("dropped", 0),
        "checks %d" % len(checks),
        "gates %d" % len(gates),
        "confirmations %d" % len(confirmations),
        "recall-confirmed %d" % recall,
        "independently-surfaced %d" % independent,
        "TALLY-END",
    ]
    return "\n".join(lines)


def change_covered(led, change, dispositions):
    for label in change.get("checks", []):
        row = led.row_or_none(label)
        if row and row.get("state") == "accepted":
            return True
    if change.get("gate"):
        return True
    path = change.get("path", "")
    for rec in led.records():
        if rec.get("type") == "finding" and rec.get("path") == path:
            for disp in dispositions.get(rec.get("id"), []):
                if disp.get("disposition") == "applied" and disp.get("tag") == "taken on a helper's word":
                    return True
    return False


def close_open_items(led):
    open_items = []
    counts = led.state_counts()
    for row in led.rows:
        if row.get("state") not in TERMINAL:
            open_items.append("condition 1: row %s is %s" % (row.get("label"), row.get("state")))

    dispositions = led.dispositions()
    for rec in led.records():
        if rec.get("type") in ("finding", "incident", "alternative"):
            if not dispositions.get(rec.get("id")):
                open_items.append("condition 2: record %s has no disposition" % rec.get("id"))

    for change in led.run.get("changes", []):
        if change.get("path", "").startswith("<"):
            continue
        if not change_covered(led, change, dispositions):
            open_items.append("condition 3: changed path %s has no accepted check, gate, or taken-on-word disposition" % change.get("path"))

    for change in led.run.get("changes", []):
        if not change.get("attribution"):
            open_items.append("condition 4: change %s is unattributed" % change.get("path"))

    current = set(path for code, path in git_status(led.root) if not under_run_dir(led.root, path))
    known = set(c.get("path") for c in led.run.get("changes", []))
    baseline_paths = set()
    for line in read_text(led.path("baseline", "status")).splitlines():
        if line.strip() and len(line) > 3:
            baseline_paths.add(line[3:])
    for path in sorted(current - known - baseline_paths):
        open_items.append("condition 5: tree guard sees %s with no disposition" % path)
    if git_head(led.root) != led.run.get("baseline_commit", "") and "<HEAD>" not in known:
        open_items.append("condition 5: HEAD moved with no disposition")
    if git_stash_list(led.root) != read_text(led.path("baseline", "stash-list")).strip() and "<stash>" not in known:
        open_items.append("condition 5: stash list changed with no disposition")

    own_authority_forks = set(
        rec.get("fork") for rec in led.records() if rec.get("type") == "own_authority"
    )
    for rec in led.records():
        if rec.get("type") == "fork":
            surfaced = any(
                disp.get("disposition") == "surfaced"
                for disp in dispositions.get(rec.get("id"), [])
            )
            if not surfaced and rec.get("id") not in own_authority_forks:
                open_items.append("condition 6: fork %s is neither surfaced nor decided" % rec.get("id"))
    for gate in led.open_gates():
        open_items.append("condition 6: user gate %s has no answered record" % gate.get("id"))

    report = read_text(led.path("report.md"))
    if tally_block(led) not in report:
        open_items.append("condition 7: report.md does not carry the current tally block")

    for row in led.rows:
        if row.get("state") in ("accepted", "inability", "failed"):
            if row.get("source") not in ("file", "relayed", "log"):
                open_items.append("condition 8: row %s has no recorded source" % row.get("label"))

    producers = led.run.get("producers", {})
    depths = led.run.get("depths", {})
    flagged = set(rec.get("label") for rec in led.records() if rec.get("type") == "flag")
    for row in led.rows:
        label = row.get("label")
        producer = producers.get(label)
        if not producer:
            continue
        checker_depth = depths.get(label)
        producer_depth = depths.get(producer)
        if checker_depth is None or producer_depth is None:
            continue
        if int(checker_depth) < int(producer_depth) and label not in flagged:
            open_items.append(
                "condition 9: checker %s sits below producer %s and no flags record names it"
                % (label, producer)
            )
    return open_items


def cmd_close(args):
    led = Ledger()
    block = tally_block(led)
    print(block)
    if args.stopped:
        changed = [c.get("path") for c in led.run.get("changes", []) if not c.get("path", "").startswith("<")]
        print("modified:")
        for path in changed:
            print("  %s" % path)
        print("untouched:")
        row_paths = set(norm_path(led.root, r.get("path")) for r in led.rows if r.get("path"))
        for path in sorted(row_paths - set(changed)):
            print("  %s" % path)
        print("unknown:")
        for row in led.rows:
            if row.get("state") not in TERMINAL:
                print("  %s state=%s" % (row.get("label"), row.get("state")))
    for rec in led.records():
        if rec.get("type") == "confirmation" and rec.get("provenance") == "recall-confirmed":
            print("advisory: %s claims independent support but is recall-confirmed" % rec.get("id"))
    producers = led.run.get("producers", {})
    depths = led.run.get("depths", {})
    for row in led.rows:
        producer = producers.get(row.get("label"))
        if not producer:
            continue
        checker_depth = depths.get(row.get("label"))
        producer_depth = depths.get(producer)
        if checker_depth is not None and producer_depth is not None and int(checker_depth) < int(producer_depth):
            print("advisory: checker %s sits below producer %s" % (row.get("label"), producer))
    open_items = close_open_items(led)
    if open_items:
        sys.stderr.write("close refused; open items:\n")
        for item in open_items:
            sys.stderr.write("  - %s\n" % item)
        return 3

    for row in led.rows:
        try:
            versions = json.loads(row.get("input_versions") or "{}")
        except ValueError:
            versions = {}
        if versions.get("target"):
            versions["snapshot_hash"] = versions.get("target")
            row["input_versions"] = json.dumps(versions, sort_keys=True)
            led.run.setdefault("snapshot_hashes", {})[row.get("label")] = versions.get("target")
    for sub in ("inputs",):
        target = led.path("snapshots", sub)
        if os.path.isdir(target):
            shutil.rmtree(target)
    for name in os.listdir(led.path("snapshots")):
        target = led.path("snapshots", name)
        if os.path.isdir(target):
            shutil.rmtree(target)
        else:
            os.unlink(target)
    led.run["closed"] = True
    led.run["closed_at"] = now_utc()
    led.save()
    print("closed: %s" % led.run.get("run_id"))
    return 0


# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------


def build_parser():
    parser = argparse.ArgumentParser(
        prog="run_ledger.py",
        description="Keep one helper run's records on disk under .agent_spinner/.",
    )
    sub = parser.add_subparsers(dest="verb", metavar="verb")

    p = sub.add_parser("init", help="open a run over an enumerated list")
    p.add_argument("--unit", action="append", default=[], help="role:item unit")
    p.add_argument("--unit-path", action="append", default=[], help="LABEL=PATH target")
    p.add_argument("--exclude", action="append", default=[], help="LABEL:REASON")
    p.add_argument("--gate", action="append", default=[], help="NAME=COMMAND")
    p.add_argument("--auto-fix-gate", action="append", default=[], help="NAME of an auto-fixing gate")
    p.add_argument("--owned-target", action="append", default=[], help="PATH:FAMILY:GATE")
    p.add_argument("--counter", action="append", default=[], help="NAME=PATTERN")
    p.add_argument("--bound", type=int, default=900)
    p.add_argument("--wave", type=int, default=2)
    p.add_argument("--phase", default="work")
    p.add_argument("--request")
    p.add_argument("--intent")
    p.add_argument("--severity", action="append", default=[])
    p.add_argument("--role", action="append", default=[], help="registered role for init --probe")
    p.add_argument("--cheapest", help="cheapest route for init --probe")
    p.add_argument("--probe", action="store_true", help="prepare probe briefs without opening a run")
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("attach", help="re-enter an open run")
    p.set_defaults(func=cmd_attach)

    p = sub.add_parser("brief", help="write one helper's instructions")
    p.add_argument("label")
    p.add_argument("--phase")
    p.add_argument("--body")
    p.add_argument("--body-file")
    p.add_argument("--shared-file")
    p.add_argument("--relay", action="append", default=[])
    p.add_argument(
        "--withheld",
        action="store_true",
        help="read a withheld text from standard input; record only its hash",
    )
    p.add_argument("--obligation", action="append", default=[])
    p.add_argument("--permit-path", action="append", default=[])
    p.add_argument("--forbid-path", action="append", default=[])
    p.add_argument("--permit-command", action="append", default=[])
    p.add_argument("--forbid-command", action="append", default=[])
    p.add_argument("--checker", action="store_true")
    p.add_argument("--kind")
    p.add_argument("--depth", type=int)
    p.add_argument("--target")
    p.add_argument("--stamp-owner")
    p.set_defaults(func=cmd_brief)

    p = sub.add_parser("dispatch", help="record that a helper was sent")
    p.add_argument("label")
    p.add_argument("--helper-id")
    p.add_argument("--model")
    p.add_argument("--effort")
    p.add_argument("--route")
    p.set_defaults(func=cmd_dispatch)

    p = sub.add_parser("accept", help="take in a helper's return")
    p.add_argument("label", nargs="?")
    p.add_argument(
        "--stdin",
        nargs="?",
        const=True,
        default=None,
        help="read the verbatim final message or a piped host log",
    )
    p.add_argument("--source", choices=["relayed", "log"])
    p.add_argument("--log", help="read a host log file instead of stdin")
    p.add_argument("--observed-model")
    p.add_argument("--observed-effort")
    p.add_argument("--wait", action="store_true")
    p.add_argument("--classify")
    p.add_argument("--probe", action="store_true")
    p.set_defaults(func=cmd_accept)

    p = sub.add_parser("rows", help="add rows for a later phase")
    p.add_argument("--phase", required=True)
    p.add_argument("--from-records")
    p.add_argument("--from-repair-list", action="store_true")
    p.add_argument("--from-gaps")
    p.add_argument("--role")
    p.set_defaults(func=cmd_rows)

    p = sub.add_parser("dispose", help="record what became of each record")
    p.add_argument("--id")
    p.add_argument("--disposition")
    p.add_argument("--tag")
    p.add_argument("--span")
    p.add_argument("--packet")
    p.add_argument("--pointer")
    p.add_argument("--narrowing")
    p.add_argument("--drops")
    p.add_argument("--open-gate")
    p.add_argument("--question")
    p.add_argument("--gate")
    p.add_argument("--answered")
    p.add_argument("--fork")
    p.add_argument("--own-decision")
    p.add_argument("--flag")
    p.add_argument("--reason")
    p.set_defaults(func=cmd_dispose)

    p = sub.add_parser("diff", help="measure what changed")
    p.add_argument("--add-checks", action="store_true")
    p.add_argument("--approved-edits")
    p.add_argument("--count", action="store_true")
    p.add_argument("--counter", action="append", default=[])
    p.set_defaults(func=cmd_diff)

    p = sub.add_parser("gate", help="run a check command")
    p.add_argument("name")
    p.add_argument("--expect", choices=["exit0", "nonempty", "count"])
    p.add_argument("--on-baseline", action="store_true")
    p.set_defaults(func=cmd_gate)

    p = sub.add_parser("snapshot", help="make read copies")
    p.add_argument("label")
    p.add_argument("paths", nargs="+")
    p.add_argument("--base", action="store_true")
    p.set_defaults(func=cmd_snapshot)

    p = sub.add_parser("status", help="show where the run stands")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("show", help="print one row's records in full")
    p.add_argument("label")
    p.set_defaults(func=cmd_show)

    p = sub.add_parser("search", help="run a pattern search over the run directory")
    p.add_argument("pattern")
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("stop", help="create STOP so nothing new is dispatched")
    p.set_defaults(func=cmd_stop)

    p = sub.add_parser("close", help="end the run")
    p.add_argument("--stopped", action="store_true")
    p.set_defaults(func=cmd_close)
    return parser


def cmd_attach(args):
    led = Ledger()
    print("run: %s" % led.run.get("run_id", "?"))
    print("state: %s" % ("closed" if led.run.get("closed") else "open"))
    head = git_head(led.root)
    baseline = led.run.get("baseline_commit", "")
    print("HEAD: %s" % ("unchanged" if head == baseline else "moved since baseline (%s -> %s)" % (baseline, head)))
    print("tree guard: %s" % ("clean" if not git_status(led.root) else "dirty"))
    print("pending returns:")
    any_pending = False
    for row in led.rows:
        if row.get("state") == "dispatched":
            any_pending = True
            print("  %s" % row.get("label"))
    if not any_pending:
        print("  none")
    led.append({"type": "attach"})
    led.save()
    return 0


def main(argv=None):
    check_interpreter()
    raw = list(sys.argv[1:] if argv is None else argv)
    command = None
    if raw and raw[0] == "gate" and "--" in raw:
        split = raw.index("--")
        command = raw[split + 1:]
        raw = raw[:split]
    parser = build_parser()
    args = parser.parse_args(raw)
    if getattr(args, "verb", None) == "gate":
        if command is None:
            die("gate needs -- before its command")
        args.command = command
    if not getattr(args, "verb", None):
        parser.print_help()
        return 2
    if args.verb == "accept":
        if isinstance(args.stdin, str):
            args.label = args.stdin
            args.stdin = True
        elif args.stdin is None:
            args.stdin = None
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
