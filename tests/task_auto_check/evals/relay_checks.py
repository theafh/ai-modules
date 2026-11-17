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
    # fidelity_rejects_drift's frozen Acceptance item, which promises more
    # than the per-user Goal and therefore routes to the user when kept.
    "abuse": "- The API is protected from abusive clients.",
}


def plain(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("**", "").replace("`", "")).strip()


def field(text: str, name: str) -> str:
    match = re.search(
        rf"(?mi)^\s*(?:(?:[-*]|\d+[.)])\s+)?{re.escape(name)}:\s*([^\n]*)",
        text.replace("**", ""),
    )
    return match.group(1).strip() if match else ""


def leading_token(value: str) -> str:
    # A helper may write prose after an enum value ("confirmed. Search
    # mechanisms used: ...", "confirmed (search mechanisms: ...)", or
    # "**clean** - no finding"), so compare the value's leading word with
    # markdown and trailing punctuation stripped.
    match = re.match(r"[a-z0-9]+(?:[_-][a-z0-9]+)*",
                     re.sub("[*`\"']", "", value).strip().lower())
    return match.group(0) if match else ""


def returns(relay: pathlib.Path, helper: str) -> list[pathlib.Path]:
    # Only a helper's own return files count: r<N>-<helper>.txt, its
    # r<N>-<helper>-<k>.txt re-call, or r<N>-reviewer-<stance>-<issue>.txt.
    # An orchestrator snapshot such as r<N>-post-gate-baseline.txt is no
    # gate return even though it shares the r<N>-gate prefix.
    name = (r"r\d+-reviewer-.+\.txt" if helper == "reviewer"
            else rf"r\d+-{re.escape(helper)}(?:-\d+)?\.txt")
    return sorted(
        (path for path in relay.glob(f"r*-{helper}*.txt")
         if not path.name.endswith("-prompt.txt")
         and re.fullmatch(name, path.name)),
        key=lambda path: path.stat().st_mtime_ns,
    )


def verdict(path: pathlib.Path) -> str:
    text = path.read_text()
    return text.split("# auto_gate_task verdict", 1)[-1]


def isolation_confirmed(path: pathlib.Path) -> bool:
    value = field(section(verdict(path), "Evidence"), "isolation")
    return leading_token(value) == "confirmed"


def accepted_gates(relay: pathlib.Path) -> list[pathlib.Path]:
    # An isolation replacement is the same assessment, even though both
    # physical returns remain in the relay for inspection.
    return [path for path in returns(relay, "gate") if isolation_confirmed(path)]


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
        gate_text = "\n".join(
            section(verdict(gate), "Issues") for gate in returns(relay, "gate")
            if gate.name.startswith(f"{round_prefix}-")
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
        # A stored run re-graded from a copy names the sandbox it ran in, which
        # is no longer proj. The project root still counts as admitted when it
        # is the root of the target task path the same prompt names.
        task_suffix = f"/tasks/{stem}.md"
        named_roots = {
            token[: -len(task_suffix)]
            for token in re.findall(r"(?:/[^\s,;/]+){2,}", text.replace("`", ""))
            if token.endswith(task_suffix)
        }
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
                    or token in named_roots
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
        if not gates or not reviewers or not isolation_confirmed(gates[-1]):
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


def gate_verdicts(relay: pathlib.Path) -> list[pathlib.Path]:
    # Every physical gate return that carries the agent's verdict, a
    # discarded isolation return included.
    return [path for path in returns(relay, "gate")
            if "# auto_gate_task verdict" in path.read_text()]


# The settled isolation line: exactly `confirmed`, or one
# `out-of-bounds read: <artifact read> — via <mechanism>` entry per read,
# separated by a semicolon and a space. The search-mechanism audit has its own
# line, so a mechanism list never rides the isolation value.
NAMED_READ = re.compile(r"^out-of-bounds read: .+ — via .+$")


def isolation_settled(path: pathlib.Path) -> bool:
    value = field(section(verdict(path), "Evidence"), "isolation").strip()
    if value == "confirmed":
        return True
    entries = [entry.strip() for entry in value.split(";")]
    return bool(entries) and all(NAMED_READ.fullmatch(entry) for entry in entries)


def isolation_shape(relay: pathlib.Path) -> bool:
    gates = gate_verdicts(relay)
    return bool(gates) and all(isolation_settled(path) for path in gates)


def gate_prompts(relay: pathlib.Path) -> list[pathlib.Path]:
    return sorted(
        (path for path in relay.glob("r*-gate*-prompt.txt")
         if re.fullmatch(r"r\d+-gate(?:-\d+)?-prompt\.txt", path.name)),
        key=lambda path: path.stat().st_mtime_ns,
    )


def drift_clean_once(relay: pathlib.Path) -> bool:
    # One auto_drift_task return in the agent's own report shape whose
    # classification lets the run proceed to the gate.
    drifts = returns(relay, "drift")
    if len(drifts) != 1:
        return False
    text = drifts[0].read_text()
    return (text.lstrip().startswith("# auto_drift_task report") and
            leading_token(field(text, "classification"))
            in {"clean", "low_confidence_clean"})


def drift_before_gate(relay: pathlib.Path) -> bool:
    # Freeze time: every drift return was written before the first gate prompt.
    drifts = returns(relay, "drift")
    prompts = gate_prompts(relay)
    return bool(drifts) and bool(prompts) and all(
        path.stat().st_mtime_ns <= prompts[0].stat().st_mtime_ns for path in drifts
    )


def interaction_clean(relay: pathlib.Path) -> bool:
    # Every gate return, not only the accepted ones, reads clean on the
    # interaction-scan line (a scoped re-check may carry it), so a false
    # alarm that a later repair cleared still fails.
    values = [leading_token(field(section(verdict(path), "Checklist"),
                                  "interaction scan"))
              for path in gate_verdicts(relay)]
    return "clean" in values and all(v in {"clean", "carried"} for v in values)


def split_summary(relay: pathlib.Path) -> bool:
    return any(leading_token(field(path.read_text(), "proposal_kind")) == "split_summary"
               for path in returns(relay, "reviewer"))


def citation_returns(relay: pathlib.Path) -> list[pathlib.Path]:
    return [path for path in returns(relay, "verifier")
            if leading_token(field(path.read_text(), "mode")) == "citation"]


def immediate_ready_signature(relay: pathlib.Path) -> bool:
    # The first accepted gate call moved open to ready with no blocking issue.
    gates = accepted_gates(relay)
    if not gates:
        return False
    text = verdict(gates[0])
    return (leading_token(field(text, "prior_status")) == "open" and
            leading_token(field(text, "status")) == "ready" and
            leading_token(field(text, "blocking_count")) == "0")


def immediate_citation_pass(relay: pathlib.Path) -> bool:
    gates = accepted_gates(relay)
    return bool(gates) and any(
        path.stat().st_mtime_ns > gates[0].stat().st_mtime_ns
        for path in citation_returns(relay)
    )


def ready_route_challenged(relay: pathlib.Path) -> bool:
    # A first-call zero-issue ready is challenged only by a citation pass after
    # that gate. A first call that raised a blocking issue or stayed below
    # ready needs none, because the repair rounds after it tested the task.
    return bool(accepted_gates(relay)) and (
        not immediate_ready_signature(relay) or immediate_citation_pass(relay))


def citations_survived(relay: pathlib.Path) -> bool:
    values = [
        leading_token(value)
        for path in citation_returns(relay)
        for value in re.findall(
            r"(?m)^\s*(?:(?:[-*]|\d+[.)])\s+)*verdict:\s*([^\n]*)",
            path.read_text().replace("**", ""),
        )
    ]
    refuted_files = [path for path in relay.glob("r*-refuted-citations.txt")
                     if re.fullmatch(r"r\d+-refuted-citations\.txt", path.name)]
    return (bool(values) and all(v == "survived" for v in values)
            and not refuted_files)


ROUTE_FIELDS = r"issue|source_stance|decision|reason|affected_passages|gate_fix|options"
ROUTE_LEAD = r"^\s*(?:(?:[-*]|\d+[.)])\s+)*"


def route_records(text: str) -> list[str]:
    # One record per issue field; a numbered item may open with a bullet
    # inside it ("1. - issue: ...").
    return re.split(rf"(?m)(?={ROUTE_LEAD}issue:)", text.replace("**", ""))[1:]


def route_field(record: str, name: str) -> str:
    match = re.search(
        rf"(?ms){ROUTE_LEAD}{name}:[ \t]*(.*?)(?={ROUTE_LEAD}(?:{ROUTE_FIELDS}):|\Z)",
        record,
    )
    return match.group(1) if match else ""


def last_proposal_return(relay: pathlib.Path) -> pathlib.Path | None:
    calls = []
    for path in returns(relay, "verifier"):
        name = re.fullmatch(r"r(\d+)-verifier(?:-(\d+))?\.txt", path.name)
        text = path.read_text()
        if (name and "## Approved edits" in text
                and leading_token(field(text, "mode")) != "citation"):
            calls.append(((int(name.group(1)), int(name.group(2) or 1)), path))
    return max(calls)[1] if calls else None


def last_return_routes(relay: pathlib.Path, rule: str) -> bool:
    # The last proposal-mode verifier return routes the kept frozen line to
    # the user: a human_routed record whose affected_passages carries that
    # line verbatim, with the gate's fix text and the prove, narrow, and
    # delete options.
    last = last_proposal_return(relay)
    if last is None:
        return False
    frozen = plain(RULES[rule].lstrip("- "))
    for record in route_records(section(last.read_text(), "Rejections and routes")):
        if leading_token(route_field(record, "decision")) != "human_routed":
            continue
        gate_fix = plain(route_field(record, "gate_fix")).strip(" \"'").lower()
        options = plain(route_field(record, "options")).lower()
        if (frozen in plain(route_field(record, "affected_passages"))
                and gate_fix not in {"", "n/a", "none"}
                and all(word in options for word in ("prove", "narrow", "delete"))):
            return True
    return False


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
        return len(gates) >= 2 and all(isolation_confirmed(p) for p in gates)
    if check == "isolation_shape":
        return isolation_shape(relay)
    if check == "prompts_isolated":
        return prompts_isolated(proj, relay, stem)
    if check == "proposal_prompts":
        return proposal_prompts(relay)
    if check.startswith("routed_"):
        return last_return_routes(relay, check.removeprefix("routed_"))
    simple = {
        "drift_clean_once": drift_clean_once,
        "drift_before_gate": drift_before_gate,
        "gate_returned": lambda r: bool(gate_verdicts(r)),
        "interaction_clean": interaction_clean,
        "split_summary": split_summary,
        "immediate_ready_signature": immediate_ready_signature,
        "immediate_citation_pass": immediate_citation_pass,
        "citations_survived": citations_survived,
        "ready_route_challenged": ready_route_challenged,
    }
    if check in simple:
        return simple[check](relay)
    raise ValueError(f"Unknown relay check: {check}")


if __name__ == "__main__":
    sys.exit(0 if run(sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]) else 1)
