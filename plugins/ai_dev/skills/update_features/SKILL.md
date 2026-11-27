---
name: update_features
description: Create or refresh a repository-root FEATURES.md behaviour ledger from the codebase. It records what the system does today, grouped by capability area, with an explicit not-yet-built boundary. Use when asked to write, generate, refresh, or maintain a feature ledger or FEATURES.md, to record what the system currently does, or to state what is built versus not yet built. Repo-agnostic and independent of any task system; the behaviour analogue of update_changelog, whose source is the code rather than git history.
version: 1.0.0
author: Andreas F. Hoffmann
license: MIT
---

# update_features

<update_features_skill>

<role>
Maintain one repository-root `FEATURES.md`: a behaviour-of-record describing what the system does today, grouped by capability area, with an explicit boundary listing what the repository declares but does not yet deliver. Read the code, the tests, and the docs that already describe the system; write the ledger from them.
</role>

<objective>
Produce a `FEATURES.md` a reader can trust as a present-tense account of the running system: behaviour-first rather than a module inventory, organized by the capability areas a user meets, and closed by a not-yet-built boundary that names only targets the repository itself declares.
</objective>

<command_intent>
build FEATURES.md, refresh the feature ledger, write down what the system currently does, record what is built and what is not yet built
</command_intent>

<authority>
The codebase is the sole source of truth. A claim enters the ledger only when the code, its tests, or a doc the repository ships as current-state description supports it. A feature the repository only declares, plans, or stubs belongs in the boundary section, never in a capability section. Never carry a claim forward from an earlier ledger version without re-checking it against the tree.
</authority>

<independence>
The skill runs on its own: it reads no task backlog, requires no `tasks/` directory, and its output is a behaviour record rather than a work list. A repository with no task system gets the same ledger a repository with one gets. The reverse holds too — nothing in a task lifecycle requires this file, and `FEATURES.md` absent is a normal state rather than an error.
</independence>

<tools>
<scan_features_sources>
Run `scripts/scan_features_sources.sh` from this skill before reading the code. It writes one structured context file describing where behaviour is declared: project-name candidates, manifests, the top-level layout, executable entry points, declared package entry points, public API surfaces, the docs that already describe the system, the declared-target markers that feed the not-yet-built boundary, and the test layout. Its last stdout line is the context file's absolute path. It is read-only, needs no network or build, and works in a repository with no task system.
</scan_features_sources>
</tools>

<consume_scan>
Read the whole scan file first, then read the code it names. The scan is an index, not evidence: a capability earns a ledger entry only after you have read the code that delivers it, so follow each entry point, public surface, and test it points at. When the scan file overflows a single read, continue with `offset`/`limit` until every line is covered rather than sampling it.
</consume_scan>

<output_contract>
<header>
The file opens with the H1 `# FEATURES — {Project Name}`. Resolve `{Project Name}` from the scan's name candidates, preferring a manifest's declared name over the directory name.
</header>
<intro>
One short paragraph under the H1 stating what the file is: a present-tense record of what the system does today, grouped by capability area, with a boundary section listing what the repository declares but does not yet deliver. State that a behaviour absent from the ledger is not part of the system as it stands.
</intro>
<capability_section>
One `## <Capability area>` section per user-observable area, ordered the way a user meets them rather than the way the tree is laid out. Name an area by what it lets a user do, not by the module that implements it.
</capability_section>
<behaviour_entry>
One bullet per observable behaviour, in the present tense: what the system does, the input or trigger that produces it, and the outcome a user sees. State the contract, not the implementation. Keep a bullet short enough to read as one claim; split a bullet that carries two independent behaviours.
</behaviour_entry>
<boundary>
The file closes with `## Not yet implemented`, holding one bullet per target the repository itself declares and the code does not yet deliver, each naming the evidence that declares it. When the repository declares no such target, the section says so in one line rather than being omitted.
</boundary>
<shape_rules>
Every section names user-observable capability. A file path, module name, class name, or internal helper never stands as a bullet's subject; it may appear only as the evidence behind a behaviour. Keep the ledger free of task IDs, sprint state, and dated status, which belong to the backlog and the changelog.
</shape_rules>
</output_contract>

<policy>
<source_of_truth>Code first, then the tests that pin its behaviour, then the docs that describe it. A doc that states intention rather than current behaviour is evidence for the boundary, not for a capability section.</source_of_truth>
<behaviour_first>Describe what a user can do and observe. An internal refactor that changes no observable behaviour changes no ledger entry.</behaviour_first>
<refresh_in_place>The ledger describes current state, so update a section in place as behaviour changes, retire a capability the code no longer delivers, and add a section for a new area. This is the one place the ledger differs from an add-only changelog: a stale claim is corrected rather than kept for history.</refresh_in_place>
<boundary_discipline>List only targets the repository itself declares, through a roadmap note, a documented limitation, a stub, or an explicit not-yet-implemented marker. Never invent a target, and never promote a declared target into a capability section on the strength of a plan.</boundary_discipline>
<optional_courtesy>When `FEATURES.md` exists, an implementation workflow may refresh it after shipping behaviour, and its absence is never an error and never blocks work. The guardrail hub's `<consumption>` refresh rule owns that touchpoint; this skill owns only the ledger's content.</optional_courtesy>
<guardrail_position>The `guardrail` hub recognizes `FEATURES.md` as a Tier 2 descriptive-context doc, and its guard value is truthfulness about present-tense description. Write the ledger so a stale passage is obvious to the next reader rather than plausible.</guardrail_position>
</policy>

<procedure>
<resolve_project_name>Take the project name from the scan's candidates, preferring a manifest's declared name, then a README H1, then the directory name.</resolve_project_name>
<scan>Run `scripts/scan_features_sources.sh` and read its context file end to end.</scan>
<walk_capabilities>Walk the scan's entry points, public surfaces, and tests, and group what they deliver into user-observable capability areas. For each area, read the code that implements it before writing a word about it.</walk_capabilities>
<collect_boundary>Collect the declared targets the code does not deliver from the scan's marker section, the docs, and the stubs. Verify each against the code: a target whose code already exists is a capability, not a boundary item.</collect_boundary>
<compose>Compose the header, the intro paragraph, the capability sections in user order, and the boundary section, following `<output_contract>`.</compose>
<land>The file is one artifact at the repository root. On a first run, write it whole. On a refresh, rewrite the affected sections in place and leave an unaffected section byte-identical, so a diff shows only behaviour that actually changed.</land>
<report>Report the capability areas written, the entries added, changed, and retired, and the boundary items recorded, naming the evidence for each boundary item.</report>
</procedure>

<pitfalls>
<module_inventory>A ledger that lists directories and modules describes the tree, not the system. Lead every section and bullet with what a user can do.</module_inventory>
<stale_claim>Carrying an earlier ledger's claim forward unchecked is the failure this skill exists to prevent. Re-read the code for every claim a refresh keeps.</stale_claim>
<plan_as_fact>An entry in a roadmap, a TODO, or a design note is a target, not a feature. It belongs in the boundary section until the code delivers it.</plan_as_fact>
<task_coupling>Reading a backlog to decide what is built couples the ledger to a task system and dates it. Read the code instead, and keep task IDs and status out of the file.</task_coupling>
</pitfalls>

<output_report>
Close a run with the four parts the repository's documentation workflows share: the file touched by relative path; whether it was created or refreshed and which sections changed; the evidence behind every boundary item; and any judgement call the user should correct, such as an area grouping decision or a target left out because the repository does not declare it.
</output_report>

<related_skills>
`update_features` sits beside the repository-document skills and shares their shape: a root `UPPERCASE.md` artifact, an on-demand run, and a repo-agnostic source. `update_changelog` maintains `CHANGELOG.md` from committed history (add-only, day-grouped), while this skill maintains `FEATURES.md` from the codebase (present-tense, refreshed in place). The `guardrail` skill recognizes `FEATURES.md` as a Tier 2 descriptive-context doc whose guard value is truthfulness, and `guardrail_audit` audits that doc set read-only.
</related_skills>

</update_features_skill>
