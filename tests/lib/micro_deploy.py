"""Per-pass micro-deployment for behavioral eval workers.

Builds a real deploy-script layout into a scratch home that hides the user's
deployed skills and agents, runs print-mode workers against that layout with
streaming output, and classifies artefact-file reads, a spawned helper's
included, as in-set or out-of-set.

No model call happens inside the unit tests; live runners call ``run_worker``.
"""

from __future__ import annotations

import filecmp
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from typing import Any

import vendor
from worker_io import as_text

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DEPLOY_SCRIPT = REPO_ROOT / "deployment" / "deployment.sh"
DEPLOY_BASH = "/bin/bash"
PLUGINS_ROOT = REPO_ROOT / "plugins"
STYLES_ROOT = REPO_ROOT / "styles"

# Vendor discovery layouts, including every skill directory Cursor reads beside
# its own. A fixture tree inside the sandbox project is in set by location, and
# the checkout's own artefact sources are matched by _is_checkout_artefact.
_ARTEFACT_PATH_RE = re.compile(
    r"(?:^|/)(?:\.cursor|\.claude|\.agents|\.codex|\.grok)/"
    r"(?:skills(?:/[^/\s\"']+)+|agents/[^/\s\"']+\.md|"
    r"output-styles/[^/\s\"']+\.md|rules/[^/\s\"']+\.mdc)"
)

# Shell-command path extraction. A command is cut at whitespace, quotes, and
# shell punctuation, so each fragment is one candidate path and `$VAR/...`
# never leaves a truncated `/...` behind. A fragment that keeps an unexpanded
# `$NAME` or a leading `~` is collected whole and fails closed; a `$` that is
# not followed by a name (a regex anchor, say) is not a variable.
_SHELL_VAR_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")
_TILDE_RE = re.compile(r"(^|[\s=:\"'(])~(?=/|$|[\s\"';)|&])")
_SHELL_SPLIT_RE = re.compile(r"[\s;|&<>()`'\"=:]+")
_UNEXPANDED_RE = re.compile(r"\$[A-Za-z_{(]")

# The parts of a command that change how its later words resolve, read left to
# right: a directory change in command position (`echo cd /x` moves nothing), a
# simple assignment, bare or after a declaration builtin, and a subshell
# opening or closing, which scopes both. An assignment from a command
# substitution, or with an empty value, records nothing, so a name it sets stays
# unexpanded. _shell_structure decides which matches are real: one inside
# quotes is text, and a parenthesis or backtick counts only where it opens or
# closes a level.
_SHELL_EVENT_RE = re.compile(
    r"(?:(?:\A|(?<=[;&|(\n{`]))[ \t]*|(?<=\bthen)[ \t]+|(?<=\bdo)[ \t]+"
    r"|(?<=\belse)[ \t]+)"
    r"(?P<verb>cd|pushd|popd)\b(?:[ \t]+(?:-[LPe@]+|--))*"
    r"(?:[ \t]+(?P<target>\"[^\"]*\"|'[^']*'|[^\s;&|()`<>]+))?"
    r"|(?:\A|(?<=[\s;&|(`{]))"
    r"(?:(?P<builtin>export|local|declare|typeset|readonly)[ \t]+(?:-\w+[ \t]+)*)?"
    r"(?P<name>[A-Za-z_]\w*)=(?!\$\(|`)"
    r"(?P<value>\"[^\"]*\"|'[^']*'|[^\s;&|()`<>]+)"
    r"|(?P<open>\$\(|\()"
    r"|(?P<close>\))"
    r"|(?P<tick>`)"
)
_HEREDOC_RE = re.compile(r"<<(-?)[ \t]*(['\"]?)([A-Za-z_][\w.-]*)\2")
# What may follow an assignment for it to outlast its statement: only more
# assignments, then the statement's end. `NAME=value cmd` sets NAME for cmd
# alone, the way the shell scopes a prefix assignment.
_STATEMENT_END_RE = re.compile(
    r"(?:[ \t]+[A-Za-z_]\w*=(?:\"[^\"]*\"|'[^']*'|[^\s;&|()`<>]*))*"
    r"[ \t]*(?:\Z|[;&|\n)}])"
)

# Tool arguments: where a glob or grep is rooted, and the pattern joined onto it.
_TOOL_DIR_KEYS = ("path", "target_directory", "targetDirectory")
_TOOL_GLOB_KEYS = ("pattern", "glob", "globPattern", "glob_pattern")

# Cursor's print mode keeps a spawned helper's own tool calls out of the
# parent's stream. The CLI writes every chat's transcript under the worker's
# HOME instead, one JSONL file per chat at
# .cursor/projects/<workspace>/agent-transcripts/<chat-id>/<chat-id>.jsonl,
# where a helper's chat id is the agentId in the parent's Task result
# (agent 2026.10.01, observed 9 October 2026). HOME is the scratch home, so
# every transcript there belongs to this pass. Claude needs no such step: its
# stream carries a helper's tool calls, marked with parent_tool_use_id.
_CURSOR_TRANSCRIPT_ROOTS = ".cursor/projects/*/agent-transcripts"

# Cursor runs every shell command from a snapshot of a login shell it starts
# under the worker's HOME (agent 2026.10.01, observed 9 October 2026). Under
# the scratch home that login shell skips the operator's own profile, and on
# macOS /etc/zprofile's path_helper then puts /usr/bin and /bin first, so
# `bash` resolved to the stock 3.2 and a bundled script that needs a newer
# bash failed where the operator's PATH would have found one. Each login
# profile in the scratch home therefore puts back the PATH the worker was
# launched with, which run_worker passes in WORKER_PATH_VAR. Claude keeps the
# real HOME and needs neither.
WORKER_PATH_VAR = "MICRO_DEPLOY_PATH"
_LOGIN_PROFILES = (".zprofile", ".bash_profile", ".profile")
_LOGIN_PROFILE_BODY = """\
# Written by tests/lib/micro_deploy.py. A login shell under this scratch home
# skips the operator's own profile, so put back the PATH the eval worker was
# launched with.
if [ -n "${MICRO_DEPLOY_PATH:-}" ]; then
  export PATH="$MICRO_DEPLOY_PATH"
fi
"""


@dataclass(frozen=True)
class ToolRecord:
    """Vendor-neutral tool call extracted from a stream-json turn."""

    name: str
    input: dict[str, Any] = field(default_factory=dict)
    failed: bool = False


@dataclass
class StreamParse:
    """Final message, session id, and tool records from one stream-json turn."""

    final_message: str = ""
    session_id: str | None = None
    tools: list[ToolRecord] = field(default_factory=list)


@dataclass
class WorkerRunResult:
    """Exit code, final response text, stderr, and artefact read provenance."""

    returncode: int
    stdout: str
    stderr: str
    read_paths: list[str]
    out_of_set_paths: list[str]
    session_id: str | None = None
    tools: list[ToolRecord] = field(default_factory=list)


@dataclass
class MicroDeployHandle:
    """Closeable handle for one pass's micro-deployment."""

    vendor: str
    scratch_home: pathlib.Path
    sandbox_project: pathlib.Path
    path_map: dict[str, pathlib.Path]
    env: dict[str, str]
    workspace: pathlib.Path
    _closed: bool = False

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        library = self.scratch_home / "Library"
        if library.is_symlink() or library.exists():
            try:
                library.unlink()
            except IsADirectoryError:
                shutil.rmtree(library, ignore_errors=True)
            except OSError:
                pass
        shutil.rmtree(self.scratch_home, ignore_errors=True)

    def __enter__(self) -> MicroDeployHandle:
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()


def discover_artefact_index() -> dict[str, tuple[str, pathlib.Path]]:
    """Map artefact name → (type, source path) the way discover_artifacts does."""

    index: dict[str, tuple[str, pathlib.Path]] = {}
    if PLUGINS_ROOT.is_dir():
        for plugin_dir in sorted(PLUGINS_ROOT.iterdir()):
            if not plugin_dir.is_dir():
                continue
            skills = plugin_dir / "skills"
            if skills.is_dir():
                for skill_dir in sorted(skills.iterdir()):
                    if (skill_dir / "SKILL.md").is_file():
                        index[skill_dir.name] = ("skill", skill_dir)
            agents = plugin_dir / "agents"
            if agents.is_dir():
                for agent_file in sorted(agents.iterdir()):
                    if not agent_file.is_file():
                        continue
                    if agent_file.name.startswith("."):
                        continue
                    if agent_file.name.lower().startswith("readme"):
                        continue
                    index[agent_file.stem] = ("agent", agent_file)
    if STYLES_ROOT.is_dir():
        for style_file in sorted(STYLES_ROOT.glob("*.md")):
            if style_file.name.startswith("."):
                continue
            if style_file.name.lower().startswith("readme"):
                continue
            index[style_file.stem] = ("style", style_file)
    return index


def source_roots_for(names: list[str]) -> list[pathlib.Path]:
    """Resolve declared artefact names to source trees for the cache key."""

    index = discover_artefact_index()
    roots: list[pathlib.Path] = []
    seen: set[pathlib.Path] = set()
    for name in names:
        entry = index.get(name)
        if entry is None:
            raise KeyError(f"unknown artefact name for micro-deploy: {name}")
        source = entry[1]
        resolved = source.resolve()
        if resolved not in seen:
            seen.add(resolved)
            roots.append(source)
    return roots


def _run_deploy(
    *,
    args: list[str],
    home: pathlib.Path,
    log_path: pathlib.Path,
) -> None:
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["DEPLOYED_ARTIFACTS_LOG"] = str(log_path)
    result = subprocess.run(
        [DEPLOY_BASH, str(DEPLOY_SCRIPT), *args],
        cwd=str(REPO_ROOT),
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        blob = (result.stdout + "\n" + result.stderr).strip()
        raise RuntimeError(
            f"micro-deploy failed (rc={result.returncode}): {blob[:800]}"
        )


def _deployed_path(
    vendor_name: str,
    name: str,
    art_type: str,
    scratch_home: pathlib.Path,
    sandbox_project: pathlib.Path,
) -> pathlib.Path:
    if art_type == "skill":
        root = ".cursor" if vendor_name == "cursor" else ".claude"
        return scratch_home / root / "skills" / name / "SKILL.md"
    if art_type == "agent":
        if vendor_name == "cursor":
            return sandbox_project / ".cursor" / "agents" / f"{name}.md"
        return scratch_home / ".claude" / "agents" / f"{name}.md"
    if art_type == "style":
        if vendor_name == "cursor":
            return sandbox_project / ".cursor" / "rules" / f"{name}.mdc"
        return sandbox_project / ".claude" / "output-styles" / f"{name}.md"
    raise ValueError(f"unsupported artefact type: {art_type}")


def _build_env(
    vendor_name: str, scratch_home: pathlib.Path
) -> dict[str, str]:
    env = vendor.worker_env(vendor_name)
    if vendor_name == "cursor":
        env["HOME"] = str(scratch_home)
    else:
        env["CLAUDE_CONFIG_DIR"] = str(scratch_home / ".claude")
        env["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = ""
    return env


def _write_login_profiles(scratch_home: pathlib.Path) -> None:
    for name in _LOGIN_PROFILES:
        (scratch_home / name).write_text(_LOGIN_PROFILE_BODY)


def _link_library(scratch_home: pathlib.Path) -> None:
    real_library = pathlib.Path.home() / "Library"
    link = scratch_home / "Library"
    if not real_library.exists() or link.exists() or link.is_symlink():
        return
    link.symlink_to(real_library, target_is_directory=True)


def _preflight_auth(
    vendor_name: str, bin_name: str, model: str, env: dict[str, str]
) -> None:
    prompt = "Reply with exactly: PROBE_OK"
    probe = vendor.build_print_cmd(
        vendor=vendor_name,
        bin=bin_name,
        model=model,
        prompt=prompt,
        output_format="text",
    )
    try:
        result = subprocess.run(
            probe,
            cwd="/tmp",
            env=env,
            capture_output=True,
            text=True,
            timeout=90,
        )
    except (OSError, subprocess.SubprocessError) as err:
        sys.exit(f"auth pre-flight could not launch `{bin_name} -p`: {err}")

    if result.returncode == 0 and "PROBE_OK" in result.stdout:
        return

    blob = (result.stdout + result.stderr).strip()
    if vendor.config(vendor_name).name == "cursor":
        remedy = (
            "The scratch home borrows the Cursor login through its `Library` "
            "link, so run `agent login` in an interactive terminal, or export "
            "CURSOR_API_KEY where the login lives elsewhere on this platform."
        )
    else:
        remedy = (
            "The scratch CLAUDE_CONFIG_DIR reads the stored login, so re-auth "
            "with `claude auth login` or set a headless token (tests/CLAUDE.md, "
            "`### Worker auth`)."
        )
    sys.exit(
        "auth pre-flight failed against the micro-deployment environment "
        f"(probe rc={result.returncode}). The CLI said:\n{blob}\n{remedy}"
    )


def micro_deploy(
    vendor_name: str,
    artefact_names: list[str],
    sandbox_project: pathlib.Path,
    *,
    bin_name: str | None = None,
    model: str = "",
    preflight: bool = True,
) -> MicroDeployHandle:
    """Deploy declared artefacts into a scratch home + sandbox project.

    Skills (and Claude agents) land under the scratch home via ``--global``.
    Cursor agents and style rules, and Claude output styles with project
    ``outputStyle``, land under ``sandbox_project`` via ``--project-dir``.
    """

    chosen = vendor.config(vendor_name)
    sandbox_project = pathlib.Path(sandbox_project).resolve()
    if not sandbox_project.is_dir():
        raise NotADirectoryError(
            f"micro-deploy requires an existing sandbox project: {sandbox_project}"
        )

    names = list(dict.fromkeys(artefact_names))
    index = discover_artefact_index()
    typed: list[tuple[str, str, pathlib.Path]] = []
    for name in names:
        entry = index.get(name)
        if entry is None:
            raise KeyError(f"unknown artefact name for micro-deploy: {name}")
        typed.append((name, entry[0], entry[1]))

    scratch_home = pathlib.Path(
        tempfile.mkdtemp(prefix=f"micro_deploy_{chosen.name}_")
    )
    log_path = scratch_home / "deployed_artefacts.log"
    try:
        if chosen.name == "cursor":
            _link_library(scratch_home)
            _write_login_profiles(scratch_home)

        path_map: dict[str, pathlib.Path] = {}
        if names:
            only = ",".join(names)
            common = ["--target", chosen.name, "--only", only]

            # User-level layout: skills always; Claude agents load from config dir.
            global_types = ["skill"]
            if chosen.name == "claude":
                global_types.append("agent")
            _run_deploy(
                args=["--global", "--type", ",".join(global_types), *common],
                home=scratch_home,
                log_path=log_path,
            )

            # Project-scoped layout: Cursor agents + styles; Claude styles.
            if chosen.name == "cursor":
                project_types = ["agent", "style"]
            else:
                project_types = ["style"]
            _run_deploy(
                args=[
                    "--project-dir",
                    str(sandbox_project),
                    "--type",
                    ",".join(project_types),
                    *common,
                ],
                home=scratch_home,
                log_path=log_path,
            )

            for name, art_type, _source in typed:
                path_map[name] = _deployed_path(
                    chosen.name, name, art_type, scratch_home, sandbox_project
                )

        env = _build_env(chosen.name, scratch_home)
        handle = MicroDeployHandle(
            vendor=chosen.name,
            scratch_home=scratch_home,
            sandbox_project=sandbox_project,
            path_map=path_map,
            env=env,
            workspace=sandbox_project,
        )
        if preflight:
            _preflight_auth(
                chosen.name,
                bin_name or chosen.bin,
                model,
                env,
            )
        return handle
    except BaseException:
        # BaseException, because a failed preflight leaves through sys.exit and
        # the scratch home (with its Library link) must not outlive it.
        library = scratch_home / "Library"
        if library.is_symlink():
            try:
                library.unlink()
            except OSError:
                pass
        shutil.rmtree(scratch_home, ignore_errors=True)
        raise


def preflight_auth(vendor_name: str, bin_name: str, model: str = "") -> None:
    """Probe one live worker call in a micro-deployment environment.

    Runners call this once before their first pass. It builds the same
    scratch-home environment every pass uses (no artefacts deployed), so a
    login that the scratch home cannot reach stops the run with the CLI's own
    message instead of failing every pass as a worker that did not complete.
    """

    probe_project = pathlib.Path(tempfile.mkdtemp(prefix="micro_deploy_probe_"))
    try:
        handle = micro_deploy(
            vendor_name,
            [],
            probe_project,
            bin_name=bin_name,
            model=model,
            preflight=True,
        )
        handle.close()
    finally:
        shutil.rmtree(probe_project, ignore_errors=True)


def overlay_fixture_edits(
    deploy: MicroDeployHandle, name: str, fixture_dir: pathlib.Path
) -> list[str]:
    """Copy a fixture's edits of a declared skill onto its deployed copy.

    A fixture that changes how the skill under test behaves, such as one that
    stubs a bundled script to fail, stages an edited copy of the skill. The
    worker still loads the deployed copy the path map names, so every file
    whose content the edited copy adds or changes relative to the skill's
    checkout source is copied over the deployed skill directory, keeping its
    mode. Every other deployed file stays as the deploy script wrote it, and
    a copy that matches the source overlays nothing. Python bytecode stays
    out, as the deploy script prunes it. Returns the overlaid paths relative
    to the skill directory.
    """

    entry = discover_artefact_index().get(name)
    if entry is None or entry[0] != "skill" or name not in deploy.path_map:
        raise ValueError(
            f"overlay needs a skill this micro-deployment declared: {name}"
        )
    source = entry[1]
    fixture_dir = pathlib.Path(fixture_dir)
    if not fixture_dir.is_dir():
        raise NotADirectoryError(f"fixture skill copy not found: {fixture_dir}")
    deployed_dir = deploy.path_map[name].parent

    overlaid: list[str] = []
    for path in sorted(fixture_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(fixture_dir)
        if "__pycache__" in rel.parts or path.suffix == ".pyc":
            continue
        original = source / rel
        if original.is_file() and filecmp.cmp(original, path, shallow=False):
            continue
        dest = deployed_dir / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        overlaid.append(rel.as_posix())
    return overlaid


def parse_stream_json(vendor_name: str, text: str) -> StreamParse:
    """Parse one vendor's stream-json stdout into message, session, tools."""

    chosen = vendor.config(vendor_name)
    parsed = StreamParse()
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue

        event_type = event.get("type")
        if event_type == "result":
            result_text = event.get("result")
            if isinstance(result_text, str):
                parsed.final_message = result_text
            sid = event.get("session_id")
            if isinstance(sid, str):
                parsed.session_id = sid
            continue

        if event_type == "system" and event.get("subtype") == "init":
            sid = event.get("session_id")
            if isinstance(sid, str):
                parsed.session_id = sid

        if chosen.name == "claude":
            _parse_claude_event(event, parsed)
        else:
            _parse_cursor_event(event, parsed)
    return parsed


def _tool_use_blocks(message: Any) -> list[ToolRecord]:
    """Tool records from the ``tool_use`` blocks of one assistant message."""

    if not isinstance(message, dict):
        return []
    content = message.get("content") or []
    if not isinstance(content, list):
        return []
    records: list[ToolRecord] = []
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") != "tool_use":
            continue
        name = str(block.get("name") or "other")
        raw_input = block.get("input") or {}
        if not isinstance(raw_input, dict):
            raw_input = {"value": raw_input}
        records.append(ToolRecord(name=name, input=dict(raw_input)))
    return records


def _parse_claude_event(event: dict[str, Any], parsed: StreamParse) -> None:
    # A helper's tool calls arrive here too, marked with parent_tool_use_id.
    if event.get("type") != "assistant":
        return
    parsed.tools.extend(_tool_use_blocks(event.get("message")))


def _parse_cursor_event(event: dict[str, Any], parsed: StreamParse) -> None:
    if event.get("type") != "tool_call":
        return
    if event.get("subtype") not in (None, "started", "completed"):
        return
    tool_call = event.get("tool_call") or {}
    if not isinstance(tool_call, dict):
        return
    for key, payload in tool_call.items():
        if not isinstance(payload, dict):
            continue
        args = payload.get("args") or {}
        if not isinstance(args, dict):
            args = {"value": args}
        result = payload.get("result")
        failed = False
        if isinstance(result, dict) and "success" not in result:
            failed = True
        parsed.tools.append(ToolRecord(name=str(key), input=dict(args), failed=failed))


def parse_transcript_tools(text: str) -> list[ToolRecord]:
    """Tool calls recorded in one Cursor chat transcript (JSONL).

    An assistant line holds ``message.content`` blocks, and each ``tool_use``
    block names the tool (``Read``, ``Shell``, ``Glob``, ...) and its
    ``input``, the same shape the Claude stream uses.
    """

    tools: list[ToolRecord] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line.startswith("{"):
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(entry, dict) or entry.get("role") != "assistant":
            continue
        tools.extend(_tool_use_blocks(entry.get("message")))
    return tools


def cursor_transcript_tools(scratch_home: pathlib.Path) -> list[ToolRecord]:
    """Tool calls from every chat transcript a Cursor worker wrote this pass.

    That covers each helper the worker spawned, whose tool calls the parent's
    stream leaves out. The parent's own transcript repeats calls the stream
    already carries, and reading it too keeps a cut-off stream covered.
    """

    tools: list[ToolRecord] = []
    for root in sorted(pathlib.Path(scratch_home).glob(_CURSOR_TRANSCRIPT_ROOTS)):
        for transcript in sorted(root.rglob("*.jsonl")):
            try:
                text = transcript.read_text(errors="replace")
            except OSError:
                continue
            tools.extend(parse_transcript_tools(text))
    return tools


def expand_worker_vars(
    text: str,
    env: dict[str, str] | None,
    cwd: pathlib.Path | str | None = None,
) -> str:
    """Expand ``~``, ``$NAME``, and ``${NAME}`` as the worker's shell sees them.

    Values come from the worker environment rather than the runner's, so ``~``
    is the scratch home on Cursor and the real home on Claude, and ``$PWD`` is
    the worker's working directory. A variable the environment leaves undefined
    or empty stays as written, and the classifier fails closed on it.
    """

    if not env:
        return text

    def variable(match: re.Match[str]) -> str:
        name = match.group(1) or match.group(2)
        if name == "PWD" and cwd is not None:
            return str(cwd)
        if name in ("PWD", "OLDPWD"):
            return match.group(0)
        value = env.get(name)
        return value if value else match.group(0)

    text = _SHELL_VAR_RE.sub(variable, text)
    home = env.get("HOME", "")
    if home:
        text = _TILDE_RE.sub(lambda m: m.group(1) + home, text)
    return text


def _unquote(word: str) -> str:
    if len(word) >= 2 and word[0] == word[-1] and word[0] in "\"'":
        return word[1:-1]
    return word


def _skip_heredoc_bodies(
    command: str, i: int, pending: list[tuple[str, bool]], quoted: list[bool]
) -> int:
    """Mark the bodies of the pending here-documents as quoted text.

    The bodies start at ``i``, the line after the one that opened them, and
    each runs through the line that holds only its delimiter (leading tabs
    dropped for ``<<-``). Returns the position after the last body.
    """

    n = len(command)
    for delimiter, strip_tabs in pending:
        while i < n:
            end = command.find("\n", i)
            line_end = n if end == -1 else end
            line = command[i:line_end]
            for j in range(i, min(line_end + 1, n)):
                quoted[j] = True
            i = line_end + 1
            if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                break
    return i


def _shell_structure(command: str) -> tuple[list[bool], set[int], set[int], set[int], set[int]]:
    """Quoting and nesting of one shell command, character by character.

    Returns which characters sit inside quotes at their own level, plus the
    positions where a subshell or a backtick substitution opens and closes.
    Single quotes hide everything up to the closing quote, and a here-document
    body counts as quoted text. Double quotes hide their text except a
    `$(...)` or backtick substitution, which opens a fresh unquoted level. A
    backslash escape travels with its character, and a `)` that closes
    nothing, such as a `case` pattern's, closes no level.
    """

    n = len(command)
    quoted = [False] * n
    opens: set[int] = set()
    closes: set[int] = set()
    tick_opens: set[int] = set()
    tick_closes: set[int] = set()
    pending: list[tuple[str, bool]] = []
    stack = ["code"]
    i = 0
    while i < n:
        ch = command[i]
        top = stack[-1]
        if top == "single":
            quoted[i] = True
            if ch == "'":
                stack.pop()
            i += 1
            continue
        if ch == "\\":
            for j in (i, i + 1):
                if j < n:
                    quoted[j] = top == "double"
            i += 2
            continue
        if top != "double":
            heredoc = _HEREDOC_RE.match(command, i) if ch == "<" else None
            if heredoc and not command.startswith("<<<", i):
                pending.append((heredoc.group(3), heredoc.group(1) == "-"))
                i = heredoc.end()
                continue
            if ch == "\n" and pending:
                i = _skip_heredoc_bodies(command, i + 1, pending, quoted)
                pending = []
                continue
        if command.startswith("$(", i):
            opens.add(i)
            stack.append("paren")
            i += 2
            continue
        if ch == "`" and top != "tick":
            tick_opens.add(i)
            stack.append("tick")
        elif ch == "`":
            tick_closes.add(i)
            stack.pop()
        elif top == "double":
            quoted[i] = True
            if ch == '"':
                stack.pop()
        elif ch == "'":
            quoted[i] = True
            stack.append("single")
        elif ch == '"':
            quoted[i] = True
            stack.append("double")
        elif ch == "(":
            opens.add(i)
            stack.append("paren")
        elif ch == ")" and top == "paren":
            closes.add(i)
            stack.pop()
        i += 1
    return quoted, opens, closes, tick_opens, tick_closes


def shell_command_paths(
    command: str,
    env: dict[str, str] | None,
    cwd: pathlib.Path | str | None = None,
) -> list[str]:
    """Every path fragment of one shell command, read left to right.

    A fragment is a piece that holds a `/` once the command is cut at
    whitespace, quotes, and shell punctuation. A variable that a statement of
    the command assigns, or a declaration builtin such as `export` sets,
    expands the fragments after it, while a prefix assignment such as
    `HOME=/x cmd` stays with its own command. A relative fragment after a `cd`
    or `pushd` is joined onto that directory, each scoped to its subshell or
    backtick substitution. Quoted text and here-document bodies move
    nothing, and a `cd` whose target cannot be expanded leaves the directory
    as it was. A name the
    command never assigns keeps its worker-environment value, or stays
    unexpanded and visible on its fragment.
    """

    variables = dict(env or {})
    base = str(cwd) if cwd is not None else None
    current = base
    oldpwd: str | None = None
    subshells: list[tuple[str | None, dict[str, str], str | None]] = []
    pushed: list[str | None] = []
    found: list[str] = []
    quoted, opens, closes, tick_opens, tick_closes = _shell_structure(command)

    def expand(text: str) -> str:
        return expand_worker_vars(text, variables, current)

    def place(fragment: str) -> str:
        if current is None or current == base or fragment.startswith(("/", "$", "~")):
            return fragment
        return f"{current.rstrip('/')}/{fragment}"

    def collect(text: str) -> None:
        for fragment in _SHELL_SPLIT_RE.split(text):
            if "/" in fragment:
                found.append(place(fragment))

    def change_dir(target: str | None) -> str | None:
        if not target or _is_unresolved(target):
            return None
        if target.startswith("/") or current is None:
            return target
        return f"{current.rstrip('/')}/{target}"

    pos = 0
    for event in _SHELL_EVENT_RE.finditer(command):
        start = event.start()
        if event.group("open") or event.group("tick"):
            if start not in opens and start not in tick_opens and start not in tick_closes:
                continue
        elif event.group("close"):
            if start not in closes:
                continue
        elif quoted[start]:
            continue
        collect(expand(command[pos:start]))
        pos = event.end()
        if start in opens or start in tick_opens:
            subshells.append((current, dict(variables), oldpwd))
        elif start in closes or start in tick_closes:
            if subshells:
                current, variables, oldpwd = subshells.pop()
        elif event.group("name"):
            value = expand(_unquote(event.group("value")))
            collect(value)
            if event.group("builtin") or _STATEMENT_END_RE.match(command, event.end()):
                variables[event.group("name")] = value
        elif event.group("verb") == "popd":
            if pushed:
                oldpwd, current = current, pushed.pop()
        else:
            raw = event.group("target")
            if raw is None:
                target = variables.get("HOME") if event.group("verb") == "cd" else None
            elif raw == "-":
                target = oldpwd
            else:
                target = expand(_unquote(raw))
                collect(target)
            moved = change_dir(target)
            if moved is not None:
                if event.group("verb") == "pushd":
                    pushed.append(current)
                oldpwd, current = current, moved
    collect(expand(command[pos:]))
    return found


def paths_from_tools(
    tools: list[ToolRecord],
    *,
    env: dict[str, str] | None = None,
    cwd: pathlib.Path | str | None = None,
) -> list[str]:
    """Derive every path a worker read, globbed, or named in a shell command.

    Each value is expanded against the worker environment first (see
    ``expand_worker_vars``). A shell command contributes every fragment that
    holds a `/`, read left to right so the command's own assignments and
    directory changes apply (see ``shell_command_paths``), and a leftover
    ``$NAME`` or ``~`` stays visible on its own fragment. A glob or grep rooted
    in a directory also contributes its pattern joined onto that directory,
    which is what it actually walked.
    """

    paths: list[str] = []
    seen: set[str] = set()

    def add(value: str) -> None:
        text = value.strip().strip("\"'")
        if not text or text in seen:
            return
        seen.add(text)
        paths.append(text)

    def expand(value: str) -> str:
        return expand_worker_vars(value, env, cwd)

    for tool in tools:
        name = tool.name.lower()
        data = tool.input
        is_grep = name in {"grep", "greptoolcall"}
        keys = ["path", "file_path", "filePath", "target_directory",
                "targetDirectory", "glob"]
        # A grep pattern is a content regex, so only other tools' patterns
        # (glob patterns above all) are treated as paths.
        if not is_grep:
            keys.append("pattern")
        for key in keys:
            value = data.get(key)
            if isinstance(value, str) and value:
                add(expand(value))
        if name in {"read", "readtoolcall"}:
            for value in data.values():
                if isinstance(value, str) and ("/" in value or value.endswith(".md")):
                    add(expand(value))
        if name in {"glob", "globtoolcall"} or is_grep:
            root = next(
                (data[key] for key in _TOOL_DIR_KEYS
                 if isinstance(data.get(key), str) and data[key]),
                None,
            )
            for key in _TOOL_GLOB_KEYS:
                value = data.get(key)
                if is_grep and key == "pattern":
                    continue
                if not isinstance(value, str) or not value:
                    continue
                if root and not value.startswith("/"):
                    add(expand(f"{root.rstrip('/')}/{value}"))
                elif "/" in value:
                    add(expand(value))
        if name in {"bash", "shell", "shelltoolcall"}:
            command = data.get("command") or data.get("cmd") or ""
            if not isinstance(command, str):
                continue
            for fragment in shell_command_paths(command, env, cwd):
                add(fragment)
    return paths


def is_artefact_path(path: str) -> bool:
    """Whether a path names a vendor-layout skill, agent, or style file."""

    normalized = path.replace("\\", "/")
    return bool(_ARTEFACT_PATH_RE.search(normalized))


def _is_checkout_artefact(resolved: pathlib.Path) -> bool:
    """Whether a path is a skill, agent, or style source in this checkout."""

    try:
        rel = resolved.relative_to(REPO_ROOT.resolve())
    except ValueError:
        return False
    parts = rel.parts
    if len(parts) >= 4 and parts[0] == "plugins" and parts[2] in {"skills", "agents"}:
        return True
    return len(parts) >= 2 and parts[0] == "styles"


def _is_unresolved(path: str) -> bool:
    """A path the worker's shell would expand but the classifier cannot."""

    return bool(_UNEXPANDED_RE.search(path)) or path.startswith("~")


def _resolve_worker_path(path: str, base: pathlib.Path) -> pathlib.Path:
    raw = pathlib.Path(path)
    if not raw.is_absolute():
        raw = base / raw
    try:
        return raw.resolve()
    except (OSError, RuntimeError, ValueError):
        return pathlib.Path(os.path.normpath(str(raw)))


def _is_under(path: pathlib.Path, root: pathlib.Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def classify_out_of_set(
    paths: list[str],
    *,
    scratch_home: pathlib.Path,
    sandbox_project: pathlib.Path,
    cwd: pathlib.Path | str | None = None,
) -> list[str]:
    """Return the skill, agent, and style paths read outside the micro-deployment.

    A path counts as an artefact when it sits in a vendor discovery layout or
    is one of the checkout's own skill, agent, or style sources. It stays in
    set only when it resolves under the scratch home or the sandbox project,
    and a relative path resolves against the worker's ``cwd`` (the sandbox
    project by default). A path that still carries an unexpanded ``$NAME`` or
    ``~`` cannot be placed, so one in a vendor layout fails closed. A checkout
    source shape behind such a variable is left alone, because a sandbox
    fixture tree can share it.
    """

    roots = [scratch_home.resolve(), sandbox_project.resolve()]
    base = pathlib.Path(cwd).resolve() if cwd else roots[1]
    out: list[str] = []
    for raw in paths:
        if _is_unresolved(raw):
            if is_artefact_path(raw):
                out.append(raw)
            continue
        resolved = _resolve_worker_path(raw, base)
        if not (
            is_artefact_path(raw)
            or is_artefact_path(str(resolved))
            or _is_checkout_artefact(resolved)
        ):
            continue
        if any(_is_under(resolved, root) for root in roots):
            continue
        out.append(str(resolved))
    return out


def integrity_record(
    read_paths: list[str], out_of_set_paths: list[str]
) -> dict[str, Any]:
    """Verdict fragment for ``artefacts_read_from_micro_deployment``."""

    return {
        "passed": not out_of_set_paths,
        "paths": list(read_paths),
        "out_of_set": list(out_of_set_paths),
    }


def run_worker(
    *,
    vendor_name: str,
    bin_name: str,
    model: str,
    prompt: str,
    deploy: MicroDeployHandle,
    timeout: int,
    extra_args: list[str] | None = None,
    cwd: pathlib.Path | str | None = None,
    prompt_before_flags: bool = False,
) -> WorkerRunResult:
    """Run a print-mode worker with stream-json and read provenance.

    The provenance covers every helper the worker spawns. On Claude a helper's
    tool calls arrive in the stream. On Cursor they come from the chat
    transcripts under the scratch home, read before the handle closes.
    """

    chosen = vendor.config(vendor_name)
    cmd = vendor.build_print_cmd(
        vendor=chosen.name,
        bin=bin_name,
        model=model,
        prompt=prompt,
        workspace=str(deploy.workspace),
        extra_args=list(extra_args or []),
        prompt_before_flags=prompt_before_flags,
        output_format="stream-json",
    )
    workdir = pathlib.Path(cwd or deploy.sandbox_project)
    env = dict(deploy.env)
    if chosen.name == "cursor":
        # Taken at launch, so a PATH the runner changed after micro_deploy
        # (a stub `gh` first, say) is the one the login profiles put back.
        env[WORKER_PATH_VAR] = env.get("PATH", "")
    try:
        completed = subprocess.run(
            cmd,
            cwd=str(workdir),
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        rc = completed.returncode
        stdout = as_text(completed.stdout)
        stderr = as_text(completed.stderr)
    except subprocess.TimeoutExpired as exc:
        rc = -1
        stdout = as_text(exc.stdout)
        stderr = as_text(exc.stderr) + f"\n[TIMEOUT after {timeout}s]"

    parsed = parse_stream_json(chosen.name, stdout)
    final = parsed.final_message or stdout
    tools = list(parsed.tools)
    if chosen.name == "cursor":
        tools.extend(cursor_transcript_tools(deploy.scratch_home))
    read_paths = paths_from_tools(tools, env=deploy.env, cwd=workdir)
    out_of_set = classify_out_of_set(
        read_paths,
        scratch_home=deploy.scratch_home,
        sandbox_project=deploy.sandbox_project,
        cwd=workdir,
    )
    return WorkerRunResult(
        returncode=rc,
        stdout=final,
        stderr=stderr,
        read_paths=read_paths,
        out_of_set_paths=out_of_set,
        session_id=parsed.session_id,
        tools=tools,
    )
