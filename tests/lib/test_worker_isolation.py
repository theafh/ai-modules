#!/usr/bin/env python3
"""Unit tests for worker_isolation that start no LLM and no worker process. Run:

    python3 tests/lib/test_worker_isolation.py
"""

from __future__ import annotations

import ast
import pathlib
import re
import shutil
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import worker_isolation  # noqa: E402

PASS = 0
FAIL = 0

TESTS_ROOT = pathlib.Path(__file__).resolve().parents[1]
HARNESS_PREFIX_LITERAL = re.compile(r"^[a-z][a-z0-9_]*_$")
# Independent allowlist: a declared ISOLATION_PREFIX is harness-only only when
# its value is listed here. Collecting assignments alone cannot prove that.
ALLOWED_ISOLATION_PREFIXES = frozenset(
    {
        "agent_spinner_",
        "git_auto_review_",
        "git_checkout_",
        "git_commit_",
        "git_refresh_",
        "git_review_",
        "guardrail_audit_",
        "lh_judge_",
        "lh_pass_",
        "nl_",
        "skill_doctor_",
        "task_",
        "task_auto_check_",
        "task_create_",
        "task_fix_",
        "wiki_layer2_",
    }
)
# Literals that are not an ISOLATION_PREFIX but are legitimate harness-role or
# unit-test stems (never eval/scenario/pass identity).
EXPLICIT_HELPER_TEST_PREFIXES = frozenset(
    {
        "nl_malformed_",
        "nl_marker_",
        "nl_judge_",
        "nl_iso_",
        "md_checkout_",
    }
)
LAYER2_SANDBOX = re.compile(r"^(AS|L2|WI|WU|MP)-")
SKIP_DIR_NAMES = {
    "workspace",
    "scratch",
    ".eval_cache",
    ".vendor_probe",
    "__pycache__",
}
WORKER_ISOLATION_REL = pathlib.Path("lib/worker_isolation.py")


def check(label: str, cond: bool) -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {label}")
    else:
        FAIL += 1
        print(f"  FAIL {label}")


def expect_refusal(label: str, root: pathlib.Path, needle: str) -> None:
    try:
        worker_isolation.raise_if_refused(root)
    except worker_isolation.CreateRootRefusal as err:
        text = str(err)
        check(label, "create-root refusal" in text and needle in text)
        return
    check(label, False)


def _skip_tests_subtree(
    path: pathlib.Path, root: pathlib.Path = TESTS_ROOT
) -> bool:
    """Return True when path sits under a gitignored run-output subtree.

    Mirrors ``tests/.gitignore`` and the Makefile ``EXCLUDE`` prune list for
    every Python-containing run-output pattern, including
    ``trigger_evals/results/*/`` and ``*/results/run-*``.
    """

    try:
        relative = path.relative_to(root)
    except ValueError:
        return True
    parts = relative.parts
    for part in parts:
        if part in SKIP_DIR_NAMES:
            return True
    if (
        len(parts) >= 3
        and parts[0] == "wiki"
        and parts[1] == "layer2"
        and LAYER2_SANDBOX.match(parts[2])
    ):
        return True
    # trigger_evals/results/<timestamp>/...
    if len(parts) >= 3 and parts[0] == "trigger_evals" and parts[1] == "results":
        return True
    # */results/run-*
    for index, part in enumerate(parts[:-1]):
        if part == "results" and parts[index + 1].startswith("run-"):
            return True
    return False


def _constant_str(node: ast.AST) -> str | None:
    """Return the string value of a Constant/Str node, else None."""

    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return None


def _is_isolation_prefix_name(node: ast.AST) -> bool:
    return isinstance(node, ast.Name) and node.id == "ISOLATION_PREFIX"


def _binding_display(value_node: ast.AST) -> str:
    """Return a compact RHS display for an ISOLATION_PREFIX assignment finding."""

    constant = _constant_str(value_node)
    if constant is not None:
        return repr(constant)
    try:
        return ast.unparse(value_node)
    except (AttributeError, TypeError, ValueError):
        return ast.dump(value_node, include_attributes=False)


def _literal_is_harness_only(value: str) -> bool:
    """Return True when a string literal equals an allowlisted harness prefix."""

    if not HARNESS_PREFIX_LITERAL.fullmatch(value):
        return False
    return (
        value in ALLOWED_ISOLATION_PREFIXES
        or value in EXPLICIT_HELPER_TEST_PREFIXES
    )


def _binding_is_allowlisted_constant(value_node: ast.AST) -> bool:
    value = _constant_str(value_node)
    return value is not None and value in ALLOWED_ISOLATION_PREFIXES


def _function_param_names(
    node: ast.FunctionDef | ast.AsyncFunctionDef,
) -> set[str]:
    args = node.args
    names = {arg.arg for arg in args.posonlyargs + args.args + args.kwonlyargs}
    if args.vararg is not None:
        names.add(args.vararg.arg)
    if args.kwarg is not None:
        names.add(args.kwarg.arg)
    return names


def _function_declares_global_isolation_prefix(
    node: ast.FunctionDef | ast.AsyncFunctionDef,
) -> bool:
    for stmt in node.body:
        if isinstance(stmt, ast.Global) and "ISOLATION_PREFIX" in stmt.names:
            return True
    return False


def _function_shadows_isolation_prefix_via_param(
    node: ast.FunctionDef | ast.AsyncFunctionDef,
) -> bool:
    """Return True when a parameter named ISOLATION_PREFIX shadows the module."""

    if _function_declares_global_isolation_prefix(node):
        return False
    return "ISOLATION_PREFIX" in _function_param_names(node)


def _expr_is_create_sandbox_root_ref(
    node: ast.AST, *, aliases: set[str]
) -> bool:
    """Return True when node refers to create_sandbox_root under aliases."""

    if isinstance(node, ast.Name):
        return node.id in aliases
    if isinstance(node, ast.Attribute):
        return node.attr == "create_sandbox_root"
    return False


def _collect_create_sandbox_root_aliases(body: list[ast.stmt]) -> set[str]:
    """Collect names bound to create_sandbox_root in one scope body."""

    aliases = {"create_sandbox_root"}

    class ScopeVisitor(ast.NodeVisitor):
        def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
            return

        def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
            return

        def visit_ClassDef(self, node: ast.ClassDef) -> None:
            return

        def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
            for alias in node.names:
                if alias.name == "create_sandbox_root":
                    aliases.add(alias.asname or alias.name)
            self.generic_visit(node)

        def visit_Assign(self, node: ast.Assign) -> None:
            if _expr_is_create_sandbox_root_ref(node.value, aliases=aliases):
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        aliases.add(target.id)
            self.generic_visit(node)

        def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
            if (
                node.value is not None
                and isinstance(node.target, ast.Name)
                and _expr_is_create_sandbox_root_ref(
                    node.value, aliases=aliases
                )
            ):
                aliases.add(node.target.id)
            self.generic_visit(node)

    for stmt in body:
        ScopeVisitor().visit(stmt)
    return aliases


def _isolation_prefix_binds_in_body(
    body: list[ast.stmt],
) -> list[tuple[ast.AST, ast.AST | None]]:
    """Return (bind_node, value_node|None) for ISOLATION_PREFIX binds in body.

    ``value_node`` is None for augmented assignment and other mutations that
    cannot prove an allowlisted constant. Nested function/class bodies skip.
    """

    found: list[tuple[ast.AST, ast.AST | None]] = []

    class ScopeVisitor(ast.NodeVisitor):
        def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
            return

        def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
            return

        def visit_ClassDef(self, node: ast.ClassDef) -> None:
            return

        def visit_Assign(self, node: ast.Assign) -> None:
            if any(_is_isolation_prefix_name(target) for target in node.targets):
                found.append((node, node.value))
            self.generic_visit(node)

        def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
            if _is_isolation_prefix_name(node.target):
                found.append((node, node.value))
            self.generic_visit(node)

        def visit_AugAssign(self, node: ast.AugAssign) -> None:
            if _is_isolation_prefix_name(node.target):
                found.append((node, None))
            self.generic_visit(node)

    for stmt in body:
        ScopeVisitor().visit(stmt)
    return found


def _is_create_sandbox_root_call(
    node: ast.Call, *, aliases: set[str]
) -> bool:
    """Return True when node calls create_sandbox_root or a tracked alias."""

    return _expr_is_create_sandbox_root_ref(node.func, aliases=aliases)


def _call_prefix_argument(node: ast.Call) -> ast.AST | None:
    """Return the prefix argument from position 0 or the ``prefix=`` keyword."""

    if node.args:
        return node.args[0]
    for keyword in node.keywords:
        if keyword.arg == "prefix":
            return keyword.value
    return None


def _resolved_isolation_prefix(
    *,
    call: ast.Call,
    func_stack: list[ast.FunctionDef | ast.AsyncFunctionDef],
    module_assigns: list[tuple[ast.AST, ast.AST | None]],
) -> str | None:
    """Return the allowlisted constant bound to ISOLATION_PREFIX, else None.

    Parameter shadowing, augmented assignment, and non-constant rebinding all
    fail closed. Local assigns win over the module binding when they precede
    the call; ``global`` assigns override the module value the same way.
    """

    for func in reversed(func_stack):
        if _function_shadows_isolation_prefix_via_param(func):
            return None
        local_assigns = _isolation_prefix_binds_in_body(func.body)
        if not local_assigns:
            continue
        prior = [
            value
            for assign, value in local_assigns
            if getattr(assign, "lineno", 0) <= getattr(call, "lineno", 0)
        ]
        if not prior:
            if _function_declares_global_isolation_prefix(func):
                continue
            return None
        last = prior[-1]
        if last is None or not _binding_is_allowlisted_constant(last):
            return None
        return _constant_str(last)

    if not module_assigns:
        return None
    last_module = module_assigns[-1][1]
    if last_module is None or not _binding_is_allowlisted_constant(last_module):
        return None
    return _constant_str(last_module)


def _call_argument_allowed(
    arg: ast.AST,
    *,
    rel_path: pathlib.Path,
    enclosing_func: str | None,
    resolved_prefix: str | None,
) -> bool:
    """Accept allowlisted ISOLATION_PREFIX, harness-only literals, or helper forward."""

    if isinstance(arg, ast.Name):
        if arg.id == "ISOLATION_PREFIX":
            return (
                resolved_prefix is not None
                and resolved_prefix in ALLOWED_ISOLATION_PREFIXES
            )
        if (
            arg.id == "prefix"
            and rel_path == WORKER_ISOLATION_REL
            and enclosing_func == "relocated_sandbox_root"
        ):
            return True
        return False
    value = _constant_str(arg)
    if value is not None:
        return _literal_is_harness_only(value)
    return False


def _argument_source(arg: ast.AST) -> str:
    """Return a compact display form for a rejected call argument."""

    value = _constant_str(arg)
    if value is not None:
        return repr(value)
    if isinstance(arg, ast.Name):
        return arg.id
    try:
        return ast.unparse(arg)
    except (AttributeError, TypeError, ValueError):
        return ast.dump(arg, include_attributes=False)


def findings_in_tree(
    tree: ast.AST,
    *,
    rel_path: pathlib.Path,
) -> list[str]:
    """List disallowed ISOLATION_PREFIX bindings and create_sandbox_root args."""

    findings: list[str] = []
    module_body = list(getattr(tree, "body", []))
    module_assigns = _isolation_prefix_binds_in_body(module_body)
    module_csr_aliases = _collect_create_sandbox_root_aliases(module_body)

    class Visitor(ast.NodeVisitor):
        def __init__(self) -> None:
            self.func_stack: list[ast.FunctionDef | ast.AsyncFunctionDef] = []

        def _csr_aliases(self) -> set[str]:
            aliases = set(module_csr_aliases)
            for func in self.func_stack:
                aliases |= _collect_create_sandbox_root_aliases(func.body)
            return aliases

        def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
            if _function_shadows_isolation_prefix_via_param(node):
                findings.append(
                    f"{rel_path}: ISOLATION_PREFIX parameter shadows module "
                    f"binding in {node.name}"
                )
            self.func_stack.append(node)
            self.generic_visit(node)
            self.func_stack.pop()

        def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
            if _function_shadows_isolation_prefix_via_param(node):
                findings.append(
                    f"{rel_path}: ISOLATION_PREFIX parameter shadows module "
                    f"binding in {node.name}"
                )
            self.func_stack.append(node)
            self.generic_visit(node)
            self.func_stack.pop()

        def visit_Assign(self, node: ast.Assign) -> None:
            if any(_is_isolation_prefix_name(target) for target in node.targets):
                if not _binding_is_allowlisted_constant(node.value):
                    findings.append(
                        f"{rel_path}: ISOLATION_PREFIX = "
                        f"{_binding_display(node.value)}"
                    )
            self.generic_visit(node)

        def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
            if (
                _is_isolation_prefix_name(node.target)
                and node.value is not None
                and not _binding_is_allowlisted_constant(node.value)
            ):
                findings.append(
                    f"{rel_path}: ISOLATION_PREFIX = "
                    f"{_binding_display(node.value)}"
                )
            self.generic_visit(node)

        def visit_AugAssign(self, node: ast.AugAssign) -> None:
            if _is_isolation_prefix_name(node.target):
                findings.append(
                    f"{rel_path}: ISOLATION_PREFIX augmented by "
                    f"{_binding_display(node.value)}"
                )
            self.generic_visit(node)

        def visit_Call(self, node: ast.Call) -> None:
            aliases = self._csr_aliases()
            if _is_create_sandbox_root_call(node, aliases=aliases):
                enclosing = (
                    self.func_stack[-1].name if self.func_stack else None
                )
                arg = _call_prefix_argument(node)
                if arg is None:
                    findings.append(f"{rel_path}: missing argument")
                else:
                    resolved = None
                    if isinstance(arg, ast.Name) and arg.id == "ISOLATION_PREFIX":
                        resolved = _resolved_isolation_prefix(
                            call=node,
                            func_stack=self.func_stack,
                            module_assigns=module_assigns,
                        )
                    if not _call_argument_allowed(
                        arg,
                        rel_path=rel_path,
                        enclosing_func=enclosing,
                        resolved_prefix=resolved,
                    ):
                        findings.append(
                            f"{rel_path}: {_argument_source(arg)}"
                        )
            self.generic_visit(node)

    Visitor().visit(tree)
    return findings


def scan_sandbox_root_prefixes(root: pathlib.Path = TESTS_ROOT) -> list[str]:
    """List create_sandbox_root calls and ISOLATION_PREFIX values that leak identity."""

    findings: list[str] = []
    for path in sorted(root.rglob("*.py")):
        if _skip_tests_subtree(path, root=root):
            continue
        text = path.read_text(encoding="utf-8")
        # Parse first so a syntax error in authored harness code fails loudly.
        tree = ast.parse(text, filename=str(path))
        rel = path.relative_to(root)
        findings.extend(findings_in_tree(tree, rel_path=rel))
    return findings


def collect_declared_isolation_prefix_constants(
    root: pathlib.Path = TESTS_ROOT,
) -> set[str]:
    """Collect module-level constant ``ISOLATION_PREFIX`` string values under root.

    Used to keep ``ALLOWED_ISOLATION_PREFIXES`` in lockstep with the runners:
    every declaration must be allowlisted, and every allowlist entry must be
    declared somewhere in the authored harness.
    """

    declared: set[str] = set()
    for path in sorted(root.rglob("*.py")):
        if _skip_tests_subtree(path, root=root):
            continue
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for _bind, value in _isolation_prefix_binds_in_body(list(tree.body)):
            constant = _constant_str(value) if value is not None else None
            if constant is not None:
                declared.add(constant)
    return declared


def _findings_for_snippet(source: str, *, rel_path: str) -> list[str]:
    """Scan a synthetic module; used to prove the scanner's fail branch."""

    tree = ast.parse(source)
    return findings_in_tree(tree, rel_path=pathlib.Path(rel_path))


def main() -> int:
    home_root = pathlib.Path.home() / "nl-isolation-probe"
    expect_refusal(
        "create-root refusal for a root under the home directory",
        home_root,
        "under the home directory",
    )

    git_probe = pathlib.Path(tempfile.mkdtemp(prefix="nl_iso_git_"))
    try:
        (git_probe / ".git").mkdir()
        nested = git_probe / "proj"
        nested.mkdir()
        expect_refusal(
            "create-root refusal for a root inside a git repository",
            nested,
            "inside a git repository",
        )
    finally:
        shutil.rmtree(git_probe, ignore_errors=True)

    fake_repo = pathlib.Path(tempfile.mkdtemp(prefix="nl_iso_repo_"))
    previous_tempdir = tempfile.tempdir
    try:
        (fake_repo / ".git").mkdir()
        tempfile.tempdir = str(fake_repo)
        try:
            worker_isolation.create_sandbox_root("nl_iso_")
            refused = False
        except worker_isolation.CreateRootRefusal as err:
            refused = "inside a git repository" in str(err)
        check("create_sandbox_root refuses a root inside a git repository", refused)
        leftovers = list(fake_repo.glob("nl_iso_*"))
        check("create_sandbox_root removes the refused root", not leftovers)
    finally:
        tempfile.tempdir = previous_tempdir
        shutil.rmtree(fake_repo, ignore_errors=True)

    created = worker_isolation.create_sandbox_root("nl_iso_")
    try:
        check("accepted fresh temporary root exists", created.is_dir())
        check("accepted root uses the caller prefix", created.name.startswith("nl_iso_"))
        check(
            "accepted root is the resolved path",
            created == created.resolve(),
        )
        try:
            worker_isolation.raise_if_refused(created)
            allowed = True
        except worker_isolation.CreateRootRefusal:
            allowed = False
        check("accepted root is outside home and any git repository", allowed)
    finally:
        shutil.rmtree(created, ignore_errors=True)

    keep = pathlib.Path(tempfile.mkdtemp(prefix="nl_iso_keep_"))
    keep_copy = keep / "sandbox"
    try:
        with worker_isolation.relocated_sandbox_root(
            "nl_iso_reloc_", keep_copy
        ) as root:
            live_root = root
            (root / "proj").mkdir()
            (root / "proj" / "ok.txt").write_text("kept\n")
            check("relocated root exists during the block", root.is_dir())
        check(
            "relocated helper copies the tree into keep_copy",
            (keep_copy / "proj" / "ok.txt").read_text() == "kept\n",
        )
        check(
            "relocated helper removes the temporary root",
            not live_root.exists(),
        )
    finally:
        shutil.rmtree(keep, ignore_errors=True)

    check(
        "claude isolation args",
        worker_isolation.isolation_args("claude") == ["--setting-sources", "project,local"],
    )
    check(
        "claude args ignore case",
        worker_isolation.isolation_args("Claude") == ["--setting-sources", "project,local"],
    )
    check("cursor isolation args", worker_isolation.isolation_args("cursor") == [])

    check(
        "allowlist includes task_create_",
        "task_create_" in ALLOWED_ISOLATION_PREFIXES,
    )
    declared_prefixes = collect_declared_isolation_prefix_constants()
    check(
        "allowlist matches declared ISOLATION_PREFIX constants",
        declared_prefixes == ALLOWED_ISOLATION_PREFIXES,
    )

    def _allowed(
        arg: ast.AST,
        *,
        rel: str = "task_create/evals/run.py",
        enclosing: str | None = "run_one",
        resolved_prefix: str | None = "task_create_",
    ) -> bool:
        return _call_argument_allowed(
            arg,
            rel_path=pathlib.Path(rel),
            enclosing_func=enclosing,
            resolved_prefix=resolved_prefix,
        )

    check(
        "harness-only literal prefix is accepted",
        _allowed(ast.Constant(value="task_create_")),
    )
    check(
        "bare ISOLATION_PREFIX is accepted when module value is allowlisted",
        _allowed(ast.Name(id="ISOLATION_PREFIX", ctx=ast.Load())),
    )
    check(
        "bare ISOLATION_PREFIX is rejected when module value embeds identity",
        not _allowed(
            ast.Name(id="ISOLATION_PREFIX", ctx=ast.Load()),
            resolved_prefix="task_create_guardrail_bound_surface_",
        ),
    )
    check(
        "prefix helper forward is accepted inside relocated_sandbox_root",
        _allowed(
            ast.Name(id="prefix", ctx=ast.Load()),
            rel=str(WORKER_ISOLATION_REL),
            enclosing="relocated_sandbox_root",
            resolved_prefix=None,
        ),
    )
    check(
        "prefix variable is rejected outside the helper forward",
        not _allowed(
            ast.Name(id="prefix", ctx=ast.Load()),
            rel="task_create/evals/run.py",
            enclosing="run_one",
        ),
    )
    check(
        "generic variable is rejected",
        not _allowed(ast.Name(id="sandbox_prefix", ctx=ast.Load())),
    )
    check(
        "eval id literal prefix is rejected",
        not _allowed(ast.Constant(value="task_create_guardrail-bound-surface_")),
    )
    check(
        "snake-case identity literal without marker words is rejected",
        not _allowed(
            ast.Constant(value="task_create_guardrail_bound_surface_")
        ),
    )
    check(
        "scenario literal prefix is rejected",
        not _allowed(ast.Constant(value="wiki_scenario_AS-01_")),
    )
    check(
        "pass literal prefix is rejected",
        not _allowed(ast.Constant(value="language_humanizer_pass2_")),
    )
    check(
        "harness role literal nl_malformed_ is accepted",
        _literal_is_harness_only("nl_malformed_"),
    )
    check(
        "explicit helper-test literal md_checkout_ is accepted",
        _literal_is_harness_only("md_checkout_"),
    )
    check(
        "unrecognized short identity literal is rejected",
        not _literal_is_harness_only("guardrail_bound_"),
    )

    # Fixture snippets prove the fail branch: a green suite alone is not enough.
    generic_var_findings = _findings_for_snippet(
        "def run():\n    create_sandbox_root(prefix)\n",
        rel_path="fixture/generic_var.py",
    )
    check(
        "fixture rejects generic prefix variable at a runner call site",
        generic_var_findings == ["fixture/generic_var.py: prefix"],
    )
    identity_literal_findings = _findings_for_snippet(
        'def run():\n    create_sandbox_root("task_create_guardrail_bound_surface_")\n',
        rel_path="fixture/identity_literal.py",
    )
    check(
        "fixture rejects identity-bearing literal without marker words",
        identity_literal_findings
        == [
            "fixture/identity_literal.py: "
            "'task_create_guardrail_bound_surface_'"
        ],
    )
    short_identity_findings = _findings_for_snippet(
        'def run():\n    create_sandbox_root("guardrail_bound_")\n',
        rel_path="fixture/short_identity.py",
    )
    check(
        "fixture rejects unrecognized short identity literal",
        short_identity_findings
        == ["fixture/short_identity.py: 'guardrail_bound_'"],
    )
    poisoned_declaration_findings = _findings_for_snippet(
        'ISOLATION_PREFIX = "task_create_guardrail_bound_surface_"\n'
        "def run():\n"
        "    create_sandbox_root(ISOLATION_PREFIX)\n",
        rel_path="fixture/poisoned_prefix.py",
    )
    check(
        "fixture rejects identity-bearing ISOLATION_PREFIX declaration",
        poisoned_declaration_findings
        == [
            "fixture/poisoned_prefix.py: ISOLATION_PREFIX = "
            "'task_create_guardrail_bound_surface_'",
            "fixture/poisoned_prefix.py: ISOLATION_PREFIX",
        ],
    )
    local_rebind_findings = _findings_for_snippet(
        'ISOLATION_PREFIX = "task_create_"\n'
        "def run(eval_id):\n"
        '    ISOLATION_PREFIX = f"task_{eval_id}_"\n'
        "    create_sandbox_root(ISOLATION_PREFIX)\n",
        rel_path="fixture/local_rebind.py",
    )
    check(
        "fixture rejects local ISOLATION_PREFIX rebinding before the call",
        local_rebind_findings
        == [
            "fixture/local_rebind.py: ISOLATION_PREFIX = "
            "f'task_{eval_id}_'",
            "fixture/local_rebind.py: ISOLATION_PREFIX",
        ],
    )
    dynamic_module_findings = _findings_for_snippet(
        'ISOLATION_PREFIX = "task_create_"\n'
        'ISOLATION_PREFIX = f"task_{eval_id}_"\n'
        "def run():\n"
        "    create_sandbox_root(ISOLATION_PREFIX)\n",
        rel_path="fixture/dynamic_module.py",
    )
    check(
        "fixture rejects dynamic module-level ISOLATION_PREFIX rebinding",
        dynamic_module_findings
        == [
            "fixture/dynamic_module.py: ISOLATION_PREFIX = "
            "f'task_{eval_id}_'",
            "fixture/dynamic_module.py: ISOLATION_PREFIX",
        ],
    )
    alias_findings = _findings_for_snippet(
        "from worker_isolation import create_sandbox_root as csr\n"
        "def run(eval_id):\n"
        '    csr(f"task_{eval_id}_")\n',
        rel_path="fixture/alias.py",
    )
    check(
        "fixture rejects aliased create_sandbox_root call with identity prefix",
        alias_findings == ["fixture/alias.py: f'task_{eval_id}_'"],
    )
    param_shadow_findings = _findings_for_snippet(
        'ISOLATION_PREFIX = "task_create_"\n'
        "def run(ISOLATION_PREFIX):\n"
        "    create_sandbox_root(ISOLATION_PREFIX)\n",
        rel_path="fixture/param_shadow.py",
    )
    check(
        "fixture rejects ISOLATION_PREFIX parameter shadowing",
        param_shadow_findings
        == [
            "fixture/param_shadow.py: ISOLATION_PREFIX parameter shadows "
            "module binding in run",
            "fixture/param_shadow.py: ISOLATION_PREFIX",
        ],
    )
    augassign_findings = _findings_for_snippet(
        'ISOLATION_PREFIX = "task_create_"\n'
        "def run():\n"
        '    ISOLATION_PREFIX += "eval_id_"\n'
        "    create_sandbox_root(ISOLATION_PREFIX)\n",
        rel_path="fixture/augassign.py",
    )
    check(
        "fixture rejects ISOLATION_PREFIX augmented assignment",
        augassign_findings
        == [
            "fixture/augassign.py: ISOLATION_PREFIX augmented by 'eval_id_'",
            "fixture/augassign.py: ISOLATION_PREFIX",
        ],
    )
    kwarg_findings = _findings_for_snippet(
        'ISOLATION_PREFIX = "task_create_"\n'
        "def run(eval_id):\n"
        '    create_sandbox_root(prefix=f"task_{eval_id}_")\n',
        rel_path="fixture/kwarg.py",
    )
    check(
        "fixture rejects identity-bearing prefix= keyword argument",
        kwarg_findings == ["fixture/kwarg.py: f'task_{eval_id}_'"],
    )

    check(
        "skip trigger_evals results timestamp trees",
        _skip_tests_subtree(
            TESTS_ROOT / "trigger_evals/results/20261023/generated.py"
        ),
    )
    check(
        "skip results/run-* output trees",
        _skip_tests_subtree(
            TESTS_ROOT / "task_create/results/run-abc/generated.py"
        ),
    )
    check(
        "scan authored harness files",
        not _skip_tests_subtree(TESTS_ROOT / "task_create/evals/run.py"),
    )
    skip_probe = pathlib.Path(tempfile.mkdtemp(prefix="iso_skip_"))
    try:
        ignored = skip_probe / "trigger_evals" / "results" / "20261023"
        ignored.mkdir(parents=True)
        (ignored / "generated.py").write_text(
            'create_sandbox_root("task_create_guardrail_bound_surface_")\n'
        )
        authored = skip_probe / "task_create" / "evals"
        authored.mkdir(parents=True)
        (authored / "run.py").write_text(
            'ISOLATION_PREFIX = "task_create_"\n'
            "create_sandbox_root(ISOLATION_PREFIX)\n"
        )
        # Point TESTS_ROOT-relative skip helper via scan over the probe tree.
        probe_findings = scan_sandbox_root_prefixes(root=skip_probe)
        check(
            "scan skips ignored trigger_evals results while reading authored files",
            probe_findings == [],
        )
        # Identity leak in an authored file under the probe must still surface.
        (authored / "run.py").write_text(
            'create_sandbox_root("task_create_guardrail_bound_surface_")\n'
        )
        leak_findings = scan_sandbox_root_prefixes(root=skip_probe)
        check(
            "scan reports identity leak in authored probe file",
            leak_findings
            == [
                "task_create/evals/run.py: "
                "'task_create_guardrail_bound_surface_'"
            ],
        )
    finally:
        shutil.rmtree(skip_probe, ignore_errors=True)

    doc = worker_isolation.__doc__ or ""
    check("doc states the isolation contract", "standing-instruction files" in doc)
    check("doc names User Rules", "User Rules" in doc)
    check("doc names deployed user-level skills", "deployed user-level skills" in doc)
    check("doc states the Cursor-first posture", "preferred measurement vendor" in doc)
    check("doc states the Claude branch purpose", "output-style loading" in doc)
    check(
        "doc names the Claude inheritance pages",
        "wiki/entities/anthropic-claude-code.md" in doc
        and "wiki/concepts/verification-surfaces.md" in doc,
    )

    leak_findings = scan_sandbox_root_prefixes()
    if leak_findings:
        for finding in leak_findings:
            print(f"  leak {finding}")
    check(
        "create_sandbox_root callers pass a harness-prefix-only argument",
        not leak_findings,
    )

    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
