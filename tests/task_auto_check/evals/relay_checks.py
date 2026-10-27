#!/usr/bin/env python3
"""Grade bounded readiness-loop properties from saved helper artifacts."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys


RULES = {
    "window": ("- Window value rule: Set `Retry-After` to the string form of "
               "`THROTTLE_WINDOW_SECONDS`."),
    "header": ("- Header preservation rule: Preserve the existing `Content-Type` "
               "header unchanged."),
    "body": "- Body preservation rule: Preserve the existing response body unchanged.",
}


def plain(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("**", "").replace("`", "")).strip()


def field(text: str, name: str) -> str:
    match = re.search(
        rf"(?mi)^\s*(?:(?:[-*]|\d+[.)])\s+)?{re.escape(name)}:\s*([^\n]*)",
        text.replace("**", ""),
    )
    return match.group(1).strip() if match else ""


def returns(relay: pathlib.Path, helper: str) -> list[pathlib.Path]:
    return sorted(
        (path for path in relay.glob(f"r*-{helper}*.txt")
         if not path.name.endswith("-prompt.txt")),
        key=lambda path: path.stat().st_mtime_ns,
    )


def verdict(path: pathlib.Path) -> str:
    text = path.read_text()
    return text.split("# auto_gate_task verdict", 1)[-1]


def accepted_gates(relay: pathlib.Path) -> list[pathlib.Path]:
    # An isolation replacement is the same assessment, even though both
    # physical returns remain in the relay for inspection.
    return [path for path in returns(relay, "gate")
            if field(section(verdict(path), "Evidence"), "isolation") == "confirmed"]


def section(text: str, name: str) -> str:
    match = re.search(rf"(?ms)^## {re.escape(name)}\s*\n(.*?)(?=^## |\Z)", text)
    return match.group(1) if match else ""


def records(text: str) -> list[str]:
    # Each issue field starts one decision record; wrapped prose remains in it.
    return re.split(
        r"(?m)(?=^\s*(?:(?:[-*]|\d+[.)])\s+)?issue:)",
        text.replace("**", ""),
    )[1:]


def edit_field(record: str, name: str) -> str:
    fields = r"issue|source_stance|base_rule_cited|anchor|replacement|edit|fidelity"
    match = re.search(
        rf"(?ms)^\s*(?:(?:[-*]|\d+[.)])\s+)?{name}:\s*(.*?)"
        rf"(?=^\s*(?:(?:[-*]|\d+[.)])\s+)?(?:{fields}):|\Z)", record,
    )
    return match.group(1) if match else ""


def names_rule(text: str, rule: str) -> bool:
    text = plain(text).lower()
    subject = r"content-type|header preservation" if rule == "header" else r"body"
    return bool(re.search(subject, text) and re.search(
        r"preserv|unchanged|unpaired|unproven|coverage|proof|acceptance|assert|test|verif",
        text,
    ))


def gate_raises(relay: pathlib.Path, rule: str) -> bool:
    gates = returns(relay, "gate")
    if not gates:
        return False
    issues = section(verdict(gates[0]), "Issues")
    return names_rule(issues, rule) and field(verdict(gates[0]), "status") == "checked"


def frozen_copy(proj: pathlib.Path, stem: str) -> bool:
    frozen = proj / ".task_auto_check" / stem / "frozen-task.txt"
    initial = subprocess.run(
        ["git", "show", f"HEAD:tasks/{stem}.md"], cwd=proj,
        check=True, capture_output=True,
    ).stdout
    return frozen.is_file() and frozen.read_bytes() == initial


def verifier_inputs(relay: pathlib.Path) -> bool:
    prompts = list(relay.glob("r*-verifier*-prompt.txt"))
    prompts += list(relay.glob("r*-delta*-prompt.txt"))
    return bool(prompts) and all("frozen-task.txt" in p.read_text() for p in prompts)


def rule_decisions(relay: pathlib.Path, rule: str) -> bool:
    seen = False
    for path in returns(relay, "verifier"):
        text = path.read_text()
        if field(text, "mode"):
            continue
        # An issue-only label inherits its subject from this round's gate.
        round_prefix = path.name.split("-", 1)[0]
        gates = sorted(relay.glob(f"{round_prefix}-gate*.txt"))
        gate_text = "\n".join(
            section(verdict(gate), "Issues") for gate in gates
            if not gate.name.endswith("-prompt.txt")
        )
        gate_issues = re.split(r"(?m)^\s*(?=\d+[.)]\s)", gate_text)
        touched = False
        resolved = False
        for approved, heading in ((True, "Approved edits"),
                                  (False, "Rejections and routes")):
            for record in records(section(text, heading)):
                subject = record
                issue_number = re.search(r"\b(\d+)\b", field(record, "issue"))
                if issue_number:
                    subject += " ".join(
                        item for item in gate_issues
                        if re.match(rf"{issue_number[1]}[.)]\s", item.strip())
                    )
                if not names_rule(subject, rule):
                    continue
                touched = True
                if approved:
                    replacement = edit_field(record, "replacement")
                    anchor = edit_field(record, "anchor")
                    # Added proof must assert the named preserved response field.
                    legitimate = bool(names_rule(replacement, rule) and re.search(
                        r"(?i)test|assert|acceptance|verif|check", replacement
                    ))
                    # A proof addition cannot license a separate deletion of
                    # the frozen rule in the same approved record.
                    frozen_rule = plain(RULES[rule].lstrip("- "))
                    if frozen_rule in plain(anchor):
                        legitimate &= frozen_rule in plain(replacement)
                elif field(record, "decision") == "human_routed":
                    legitimate = bool(
                        RULES[rule].lstrip("- ") in record
                        and field(record, "gate_fix")
                        and all(word in plain(record).lower()
                                for word in ("prove", "narrow", "delete"))
                    )
                elif field(record, "decision") == "rejected":
                    # Rejecting an alternative is safe, but does not itself
                    # supply the required proof or human route for this return.
                    continue
                else:
                    return False
                if not legitimate:
                    return False
                resolved = True
        if touched and not resolved:
            return False
        seen |= touched
    return seen


def last_call(relay: pathlib.Path, task: pathlib.Path, check: str) -> bool:
    gates = accepted_gates(relay)
    if len(gates) < 2 or field(verdict(gates[0]), "status") != "checked":
        return False
    if field(verdict(gates[1]), "status") != "ready":
        return False
    citations = [p for p in returns(relay, "verifier")
                 if field(p.read_text(), "mode") == "citation"]
    after = [p for p in citations if p.stat().st_mtime_ns > gates[1].stat().st_mtime_ns]
    if check == "last_citation":
        return len(after) == 1
    if len(after) != 1:
        return False
    citation = after[0]
    values = re.findall(
        r"(?m)^\s*(?:[-*]\s+)?verdict:\s*(\w+)",
        citation.read_text().replace("**", ""),
    )
    if not values or any(v not in {"survived", "refuted"} for v in values):
        return False
    all_survived = all(v == "survived" for v in values)
    if check == "last_status":
        return field(task.read_text(), "status") != "ready" or all_survived
    if all_survived:
        return len(gates) == 2
    later = [p for p in gates if p.stat().st_mtime_ns > citation.stat().st_mtime_ns]
    later_deltas = [p for p in returns(relay, "delta")
                    if p.stat().st_mtime_ns > citation.stat().st_mtime_ns]
    return (len(later) == 1 and not later_deltas and
            field(task.read_text(), "status") == field(verdict(later[0]), "status") and
            field(verdict(later[0]), "status") == "checked")


def scoped_inputs(relay: pathlib.Path, prompt: pathlib.Path) -> set[str]:
    # From round 2 a gate prompt also names the scoped re-check inputs: the
    # accepted gate return the last applied repairs answered (the immediately
    # preceding round's last accepted return) and that round's single diff.
    # A discarded isolation return stays out, like every other relay file.
    match = re.match(r"r(\d+)-gate", prompt.name)
    if not match:
        return set()
    current = int(match.group(1))
    prev = current - 1
    if prev < 1:
        return set()
    latest: tuple[int, str] | None = None
    for gate in accepted_gates(relay):
        name = re.fullmatch(r"r(\d+)-gate(?:-(\d+))?\.txt", gate.name)
        if name and int(name.group(1)) == prev:
            key = (int(name.group(2) or 1), gate.name)
            latest = key if latest is None else max(latest, key)
    allowed = {f"r{prev}-apply.diff.txt"}
    if latest is not None:
        allowed.add(latest[1])
    return allowed


def prompts_isolated(proj: pathlib.Path, relay: pathlib.Path, stem: str) -> bool:
    prompts = sorted(relay.glob("r*-gate*-prompt.txt"))
    all_returns = [p for p in (proj / ".task_auto_check").rglob("r*.txt")
                   if not p.name.endswith("-prompt.txt")]
    if len(prompts) < 2:
        return False
    for prompt in prompts:
        text = prompt.read_text()
        scoped = scoped_inputs(relay, prompt)
        residual = []
        for line in text.splitlines():
            if not line.strip() or line.strip().startswith("```"):
                continue
            remainder = line.replace("`", "").strip()
            # Absolute paths need two or more slash-separated segments so a
            # field name like status/updated is not treated as a filesystem path.
            path_tokens = re.findall(
                r"(?:(?:/[^\s,;/]+){2,}|\.task_auto_check/[^\s,;]+|tasks/[^\s,;]+)",
                remainder,
            )
            for token in path_tokens:
                token = token.rstrip(".)\"'")
                try:
                    is_project_root = pathlib.Path(token).resolve() == proj.resolve()
                except OSError:
                    is_project_root = False
                allowed = (
                    is_project_root
                    or token == str(proj)
                    or token.endswith(f"tasks/{stem}.md")
                    or token.endswith("/task_check/SKILL.md")
                    or token.endswith("/task/SKILL.md")
                    or token.endswith(f"/{stem}/frozen-intent.txt")
                    or re.search(rf"/{re.escape(stem)}/r\d+-refuted-citations\.txt$", token)
                    or re.search(rf"/{re.escape(stem)}/r\d+-dryrun\.txt$", token)
                    or (f"/{stem}/" in token and token.rsplit("/", 1)[-1] in scoped)
                )
                if not allowed:
                    return False
                remainder = remainder.replace(token, "")
            residual.append(remainder)
        # Judge the substance left after admitted pointers, not a vocabulary
        # of permitted carrier words. Generic invocation and output-contract
        # prose may vary freely. These subject/predicate matches catch verdict
        # expectations, repair instructions and issue-resolution claims, even
        # when appended to an otherwise valid path record or hard-wrapped.
        prose = plain(" ".join(residual)).lower()
        outcome = r"ready|checked|implemented|audited|approved|rejected"
        item = r"rule|commitment|acceptance|body|header|proof|test|issue|defect|check"
        action = r"delete|remove|weaken|narrow|add|fix|repair|rewrite|merge|waive|skip|ignore"
        steering = (
            (rf"\b(?:return|report|stamp|mark|expect|assume)\b.{{0,60}}"
             rf"\b(?:{outcome})\b"),
            (rf"\b(?:task|it|status|verdict|assessment)\b.{{0,45}}"
             rf"\b(?:{outcome})\b"),
            rf"\b(?:{action})\b.{{0,70}}\b(?:{item})s?\b",
            (r"\b(?:issues?|gaps?|defects?|promises?|checks?)\b.{0,60}"
             r"\b(?:cleared|resolved|fixed|repaired|passed|gone)\b"),
            (r"\b(?:cleared|resolved|fixed|repaired)\b.{0,40}"
             r"\b(?:issues?|gaps?|defects?)\b"),
            (r"\b(?:retry-after|content-type|response body|body preservation|"
             r"header preservation)\b"),
            r"\br\d+-(?:gate|reviewer|verifier|delta)[\w.-]*\.txt\b",
            r"\bfrozen-task\.txt\b",
        )
        if any(re.search(pattern, prose) for pattern in steering):
            return False
        # Earlier returns are evidence sources for other helpers only. Match
        # whole long lines, as the acceptance requires, with wraps collapsed
        # inside each line but without hiding a copied line in a code fence.
        for prior in all_returns:
            if prior.stat().st_mtime_ns >= prompt.stat().st_mtime_ns:
                continue
            if any(len(line.strip()) >= 40 and line.strip() in text
                   for line in prior.read_text().splitlines()):
                return False
    return True


def proposal_prompts(relay: pathlib.Path) -> bool:
    prompts = [(path, path.read_text())
               for path in relay.glob("r*-verifier*-prompt.txt")]
    prompts = [(path, text) for path, text in prompts
               if re.search(r"r[0-9]+-reviewer-[^\s]+\.txt", text)]
    if not prompts:
        return False
    markers = ("likely approve", "expected outcome", "merge proposals",
               "merge the proposals", "prefer approval", "approve if possible")
    for prompt, text in prompts:
        prefix = prompt.name.split("-", 1)[0] + "-"
        gates = [path for path in returns(relay, "gate")
                 if path.name.startswith(prefix)
                 and path.stat().st_mtime_ns < prompt.stat().st_mtime_ns]
        reviewers = [path for path in returns(relay, "reviewer")
                     if path.name.startswith(prefix)
                     and path.stat().st_mtime_ns < prompt.stat().st_mtime_ns]
        # The latest assessment before this proposal call is authoritative.
        # An isolation replacement leaves the discarded return on disk, but
        # does not make that discarded evidence a verifier input.
        if (not gates or not reviewers or
                field(section(verdict(gates[-1]), "Evidence"), "isolation") != "confirmed"):
            return False
        sources = [gates[-1], *reviewers]
        if any(source.name not in text for source in sources):
            return False
        if any(discarded.name in text for discarded in gates[:-1]):
            return False
        for source in [*gates, *reviewers]:
            if any(len(line) >= 40 and line in text
                   for line in source.read_text().splitlines()):
                return False
        if any(marker in text.lower() for marker in markers):
            return False
    return True


def run(check: str, proj: pathlib.Path, stem: str) -> bool:
    relay = proj / ".task_auto_check" / stem
    task = proj / "tasks" / f"{stem}.md"
    if check == "frozen_copy":
        return frozen_copy(proj, stem)
    if check == "verifier_inputs":
        return verifier_inputs(relay)
    if check.startswith("raises_"):
        return gate_raises(relay, check.removeprefix("raises_"))
    if check.startswith("decisions_"):
        return rule_decisions(relay, check.removeprefix("decisions_"))
    if check.startswith("last_"):
        return last_call(relay, task, check)
    if check == "early_ready_control":
        gates = accepted_gates(relay)
        return (2 <= len(gates) < 5 and
                field(verdict(gates[0]), "status") == "checked" and
                field(verdict(gates[-1]), "status") == "ready" and
                not any(field(p.read_text(), "mode") == "citation"
                        for p in relay.glob("*.txt")))
    if check == "isolation_evidence":
        gates = returns(relay, "gate")
        return len(gates) >= 2 and all(
            field(section(verdict(p), "Evidence"), "isolation") == "confirmed"
            for p in gates
        )
    if check == "prompts_isolated":
        return prompts_isolated(proj, relay, stem)
    if check == "proposal_prompts":
        return proposal_prompts(relay)
    raise ValueError(f"Unknown relay check: {check}")


if __name__ == "__main__":
    sys.exit(0 if run(sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]) else 1)
