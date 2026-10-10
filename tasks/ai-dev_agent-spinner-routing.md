---
description: Route agent_spinner by whether the user named it, in its routing blocks and description, add a recipe table to <selector>, retire three blocks, and add evals and checks.
scope: plugins/ai_dev/skills/agent_spinner
created: 2026-10-03T15:54:08
updated: 2026-10-10T00:02:04
status: open
reported-by: Andreas Hoffmann
---

# Route agent_spinner requests by whether the user named the skill: `<role>`, `<invocation_boundary>`, `<selector>`, a recipe table, and the description's routing sentence

## Goal

agent_spinner is the skill an orchestrating agent, the orchestrator, follows when it runs helper agents. Before a run starts, the skill settles two routing questions: who owns the request, and which shape and recipe the run follows. A shape is one of six standard ways to arrange helpers, such as one helper per file. A recipe is a procedure file for one kind of job, kept under `references/recipes/`. Today the first question is spread over three blocks, `<when_to_activate>`, `<invocation_boundary>`, and `<worked_instances>`. Their routing sends every request that names the task backlog or the wiki to that skill family, even when the user named agent_spinner.

After this task, agent_spinner decides in one block who owns an ask, and in one block which shape and recipe a run follows:

- A request that names the task backlog or the wiki without naming the skill goes to that family. A per-harness question goes to `harness_portability`, the skill that holds facts about each agent harness.
- When the user names agent_spinner for a job a family skill owns, the family's writer stays the only writer. The independent looks run at the orchestrator's level: a read-only finder before the writer, and a post-write check on every file the writer changes. Every repair a look raises returns to that writer as a scope the user approves.
- The selector matches a shape first and then a recipe table. An ask that matches a shape and no recipe runs that shape from the body and says so.

`<role>` names the ledger program, which keeps a run's records, and the run directory, where those records live. `<when_to_activate>` and `<worked_instances>` merge into `<invocation_boundary>`, and `<references>` retires. The rewritten blocks stay within the byte budgets Approach sets, the body ends 1,791 bytes smaller, and `SKILL.md` stays under the 25,000-byte check. Two new evals prove the explicit request, in which the user names the skill, and the no-recipe path, in which an ask matches a shape and no recipe. A static check ties the recipe table's rows to the recipe files one to one. Three existing evals re-run as regression guards, and the wiki concept page states the new routing. The description's routing sentence becomes conditional in the same way, and a trigger run shows that it still keeps sibling requests away and loads the skill when the user names it.

## Context

- **Current state, read on 2026-10-04.** `plugins/ai_dev/skills/agent_spinner/SKILL.md` is version 1.0.1 and 21,616 bytes. Measured from opening tag through closing tag, `<role>` holds 603 bytes, `<when_to_activate>` 828, `<invocation_boundary>` 585, `<selector>` 1,066, `<references>` 479, and `<worked_instances>` 567. `<when_to_activate>` quotes example asks. Its routing sentence applies whether or not the user named the skill: "Route a request naming the task backlog to the `task_*` family and a request naming the wiki to `wiki_fix`." `<invocation_boundary>` says "Read `agent_spinner` for a request about running helpers in general, or for a job no shipped family owns." `<references>` is the only place SKILL.md names its four reference files. `<worked_instances>` lists four shipped skills and says they are not a "`agent_spinner_*` family roster". It replaced a `<family>` block, because skill_doctor, the repository's check-only skill auditor, counts the skills a `<family>` block lists as family members. With the replacement, skill_doctor stopped reading the four as members: today `python3 plugins/ai_dev/skills/skill_doctor/scripts/resolve_scope.py --root . --family agent_spinner` resolves exactly `agent_spinner`, with an empty `warnings` list.
- **Checks that read these blocks.** In `tests/agent_spinner/script_tests/run.sh`, the CONTRACTS array lists the blocks the script requires, and it names none of `<role>`, `<when_to_activate>`, `<references>`, and `<worked_instances>`. The check "selector carries the residual smallest-covering rule" pins `smallest shape that covers it` inside `<selector>`, so that phrase must stay in the block. The checks "description routes task requests to the task_* family" and "description routes wiki requests to wiki_fix" read the frontmatter alone. The greps over the skill directory reach every block this task writes.
- **Decisions this task implements.** On 2026-10-03 the owner approved routing that depends on whether the user named the skill. When the user names agent_spinner for a job a family skill owns, the family's writer stays the only writer, and the independent looks run at the orchestrator's level. Every repair a look raises returns to the family writer as a scope the user approves. That reverses the name-blind routing of [the archived spinner task](archive/ai-dev_agent-spinner-skill.md), which ignored whether the user named the skill. The reversal covers its `<invocation_boundary>` item "Read `agent_spinner` when the orchestration decision belongs to the orchestrator, meaning a request about running helpers in general or a job no shipped family owns". It also covers its Context sentence routing a request that names tasks or the wiki to that family. The archived task stays unedited as the decision record. The owner also approved that defects inside governed loops become family-owned tasks, where a governed loop is one a family skill runs under its own contract. As a result, the citation direction stays one-way: agent_spinner names the family skills, and no family skill cites agent_spinner.
- **The description's routing sentence, measured on 2026-10-04.** The frontmatter `description:` routes the way the body does today. Its sentence beginning "Route a request naming the task backlog" sends every backlog or wiki request to that family, whether or not the user named the skill. The trigger runner, `tests/trigger_evals/run.py`, measured it with `claude` 2.1.226 and a `claude-sonnet-4-6` worker, three runs per query. The set was `tests/trigger_evals/agent_spinner.json` plus the two naming queries Approach adds, one naming agent_spinner on a task-family job and one on a wiki job. Each run used a scratch config directory holding a copy of the deployed skills with only agent_spinner's files swapped, so no deploy was needed. Two runs of today's description passed 4 and 3 of the eight `should_trigger: true` queries that name no skill, all eight `should_trigger: false` queries, and both naming queries. The conditional sentence Approach gives passed 4 of 8, all eight negatives, and both naming queries. The router therefore already loads the skill when the user names it, and the change aligns the description with `<invocation_boundary>` at no measured cost.
- **Order.**
  - [The run-ledger task](ai-dev_agent-spinner-run-ledger.md) lands first. It owns two passages of the concept page `wiki/concepts/agent-delegated-automation.md`, the list of what ships with the skill and the "Derived from" entry, and its Out of scope hands this task the `<role>` sentence naming `scripts/`, which holds true only once the ledger ships.
  - [The runner-modes task](tests_agent-spinner-runner-modes.md) lands first. A harness key is a per-eval setting that tells the eval runner how to stage a run. Its `agents` harness key stages the mock family agent that `explicit_spinner_on_family_job` needs. Its `needs_real_absence` key marks governed_stop as an eval whose behaviour rests on a real withheld tool.
  - [The judgement-containment task](ai-dev_agent-spinner-judgement-containment.md) lands after this one, so its additions meet the 25,000-byte check on the body this task has already cut. The order against the ledger-doctrine and checking-doctrine tasks is free. The ledger-doctrine task's `<start_here>` cites `<selector>` and `<invocation_boundary>` by name, and both blocks exist either way.
- **Where the reference pointers go.** `<references>` is the block that lists the four reference files today, and retiring it moves each pointer to its point of use. The checking-doctrine task rewrites `<shapes>` around the templates in `references/role-prompts.md`. The judgement-containment task names `references/report-shapes.md` in `<judgement>` and `references/degradation-examples.md` from the run-protocol tier table. The decision-research recipes name `references/variants.md` where they apply its variants. Until each lands, the body still states the rules those files illustrate, since today's `<shapes>` carries every prompt skeleton and `<reporting>` every report part. An interim commit therefore loses pointers to worked examples and no rule.
- **Grader rules.** Every new grader follows TESTING.md's `## Test Design Principles`. Shell added to `run.sh` or `grade.sh` stays within the bash 3.2 floor that harness_portability states in its rule beginning "Target bash 3.2 as the interpreter floor".

## Approach

### SKILL.md

Rewrite `<role>`, `<invocation_boundary>`, and `<selector>` in place to this target text. Delete `<when_to_activate>`, `<references>`, and `<worked_instances>`, each with the blank line after it. Every other block stays byte-identical, and the frontmatter changes only as the next section gives.

```markdown
<role>
agent_spinner is the orchestration doctrine an agent follows when it runs helper agents, whatever delegation the host offers. `scripts/` holds the ledger program, and the run's files live under `.agent_spinner/` in the working root. The skill owns no artifact class and writes no domain state, and every guarantee holds at the inline floor.
</role>

<invocation_boundary>
A request that names the task backlog or the wiki without naming this skill goes to that family (`task_*`, `wiki_fix`), and a per-harness question goes to `harness_portability`. A run governed by a named skill keeps that skill's contract, including its loop bounds, helper-failure policy, verification standard, aggregation rule, and stop-and-ask boundary.

When the user names this skill for a family-owned job, the family's writer stays the only writer and its loop keeps its rules. Run the looks at your level: one read-only finder per ledger unit before the writer, and the post-write check of `<paired_refute_check>` on every file it changes. Every repair a look raises returns to the family writer as a scope the user approves. Write no family-owned artifact yourself, encode no multi-helper shape into a family agent's brief, and relay the family's report as its contract prescribes.
</invocation_boundary>

<selector>
Match orchestration weight first.

- An enumerated imperative over many artifacts: per-artifact fan-out.
- One corpus needing several angles: a lens panel.
- A produced artifact needing an adversarial read: a paired refute-by-default check.
- A closed comparison among candidates: a judge panel.
- A finished body needing a what-is-missing read: a completeness critic.
- A tree of writes: a single-writer validator after the writers.

A read-only diagnostic or a single judgement question is answered inline, takes no recipe, and names the checks a fuller shape would run. An ask that matches no shape gets the smallest shape that covers it, named as the smallest covering choice, and takes no recipe. An ask that matches a shape then matches the recipe table, and a matched recipe is the procedure the run follows. An ask that matches a shape but no recipe runs that shape from this body and says so. Name what matched, or that nothing did, in the run's opening sentence.

| Ask | Recipe in `references/recipes/` |
| --- | --- |

</selector>
```

- **The table frame.** The recipe table ships empty. At this task's commit it holds its header and delimiter rows and no data row. A data row names one ask in its first cell and one backticked file name under `references/recipes/` in its second, the column order the recipe tasks follow. While the table is empty, every ask that matches a shape takes the no-recipe path.
- **What the merge keeps.** The first paragraph of `<invocation_boundary>` carries the routing sentence `<when_to_activate>` held, now conditional on the user not naming the skill. It also carries the authority rule that `<worked_instances>` illustrated with its list: a run a named skill governs keeps that skill's contract. A line-owning tag is one that stands alone on its line. No line-owning `<family>` tag returns, so skill_doctor's family resolution keeps its result.
- **Superseded passages.** The rewrite removes "Read `agent_spinner` for a request about running helpers in general", "It owns one question", "Match orchestration weight to the ask before picking a mechanism", "Load a reference when the run needs its detail", and "family roster".
- **Budget.** Measured from opening tag through closing tag, the target blocks hold `<role>` 355 bytes, `<invocation_boundary>` 935, and `<selector>` 1,053. The three deleted blocks free 1,880 bytes with their blank lines, so the body shrinks by 1,791 bytes. `SKILL.md` stays within run.sh's check labelled "SKILL.md under 25000 bytes", measured with `wc -c` at implementation time.

### The description's routing sentence

In the frontmatter `description:`, rewrite the sentence beginning "Route a request naming the task backlog" in place so it reads: "Route a request naming the task backlog to the task_* family and a request naming the wiki to wiki_fix, unless the user names agent_spinner, since those families are worked instances of this shape that keep their own contracts." Rewrap the folded block and leave every other word of the frontmatter unchanged.

Add two `should_trigger: true` entries to `tests/trigger_evals/agent_spinner.json`: "use agent_spinner to run the readiness repair on tasks/api_rate-limit.md until task_check passes" and "with agent_spinner, fan the broken-link repair out across the five pages of my wiki".

Measure the change in a scratch config directory, which needs no deploy. The empty `CLAUDE_SECURESTORAGE_CONFIG_DIR` keeps the stored login usable from that directory. The scratch config directory is Claude's, so the command names `--vendor claude`, which keeps the measurement on Claude after the trigger harness gains Cursor.

```bash
cfg=$(mktemp -d)
cp -R ~/.claude/skills "$cfg/skills"
rm -rf "$cfg/skills/agent_spinner"
cp -R plugins/ai_dev/skills/agent_spinner "$cfg/skills/agent_spinner"
CLAUDE_CONFIG_DIR="$cfg" CLAUDE_SECURESTORAGE_CONFIG_DIR= python3 tests/trigger_evals/run.py --vendor claude \
  --eval-set tests/trigger_evals/agent_spinner.json --skill agent_spinner \
  --skill-path plugins/ai_dev/skills/agent_spinner \
  --model claude-sonnet-4-6 --runs-per-query 3 --timeout 45 --workers 6
```

In `tests/agent_spinner/RUNBOOK.md`, rewrite the paragraph beginning "The skill has to be deployed for the runner's deployed-mode path" in place so it names both routes: a deployed skill, and a scratch config directory that measures a source description without a deploy, with the commands above. Below it, record the 2026-10-04 measurements from Context and this task's run, each with its date, build, model, and counts.

### The one-to-one check

Add a check labelled "selector recipe rows match references/recipes/ one to one" to the `# --- references ---` section of `tests/agent_spinner/script_tests/run.sh`. It reads `<selector>` from its line-start opening tag to its closing tag. Starting at the line-start tag keeps the inline `<selector>` citation in `<start_here>` out of the scan. The check collects the backticked file name in each data row's second cell. It passes when every named file exists under `references/recipes/`, no name appears twice, and every `*.md` file under `references/recipes/` has exactly one row. It also passes with no data row and no recipe directory, so it holds at this commit and at each recipe task's commit. It is a new check under TESTING.md's `## Test Integrity`.

### Evals

Add each eval to `tests/agent_spinner/evals/evals.json`, with a fixture at `fixtures/<id>/setup.sh` and its checks in `grade.sh`. Each grader asserts its filesystem, roster, or ledger fact before any response marker, so it grades what the run left on disk before any phrase in the run's reply. A run meets pre-dispatch gates, the questions it must put to the user before it dispatches helpers. Each prompt states the answers to the pre-dispatch gates the run meets before the step the eval tests. Both evals are new checks, proven under TESTING.md's vendor rule.

- `explicit_spinner_on_family_job`. Fixture: a mock family skill with one agent. The eval's `extra_reads` key lists further skill files the run reads, and it names the mock skill's `SKILL.md` under `fixtures/explicit_spinner_on_family_job/`. The `agents` harness key stages the skill's agent from that fixture's `agents/` directory. The mock skill is a front end: it hands the job to the agent, forbids narrowing the agent's scope unless the user supplies a narrower one, and forbids re-listing the agent's checks. The agent definition names three distinctive checks. Five pages under `notes/` each carry one planted defect. The prompt names agent_spinner, asks it to fix the five pages, and answers the scope and estimate gates, while it leaves the approval of the family writer's scope unanswered. Asserted: exactly five finder briefs exist under `.agent_spinner/briefs/`, one per page, and no brief grants a write. Every page and every staged family file stays byte-identical. No brief addressed to the family agent names any of its three planted checks or assigns a lens panel. The report hands each raised repair to the family writer as a scope that waits for the user's approval, naming each page with a planted defect.
- `shape_matched_no_recipe`. Fixture: five pages under `docs/`, and a prompt asking for a three-line summary of each page written to `notes/<page>.md`, with the gate answers stated. The ask matches per-artifact fan-out and none of the asks the recipe tasks plan, so it stays a no-recipe case as their rows land. Asserted: the announcement names per-artifact fan-out and states that no recipe matched. The roster holds five rows, five briefs each name one page, and five note files exist under `notes/`. Every page under `docs/` stays byte-identical, and no brief names a file under `references/recipes/`.

Re-run `diagnostic_inline`, `residual_selector`, and `governed_stop` on the default vendor under TESTING.md's vendor rule. `governed_stop` withholds its spawn tool by the runner-modes task's withholding rule, which covers both vendors. Each keeps its fixture, prompt, expectations, and grade.sh case unchanged.

Add one row per new eval to the `## Signal per eval` table in `tests/agent_spinner/evals/README.md`. Keep every agent_spinner eval-count statement in `tests/agent_spinner/`, `tests/README.md`, and `tests/CLAUDE.md` equal to `jq '.evals | length' tests/agent_spinner/evals/evals.json`.

### Wiki

Through the wiki skill family, rewrite the paragraph of `wiki/concepts/agent-delegated-automation.md` that opens "The skill is advisory, and the direction is one-way". The paragraph keeps the citation direction one-way: no family skill cites agent_spinner, and the skill restates none of their rules. It names the two routing cases. A request that names a family without naming the skill goes to that family, whose contract wins inside its run. A family-owned job the user names the skill for keeps the family's writer as the only writer, while the looks run at the orchestrator's level and every repair returns to that writer as a scope the user approves. The paragraph's sentence on per-harness facts stays.

**Out of scope:**

- Rewriting the rest of the description for recall. On 2026-10-04, rewrites that led with the purpose or anchored the triggers to the moment of spawning passed 3 and 2 of the eight queries that name no skill, against 3 and 4 for today's text. The queries that still miss load no skill at all, or the bundled code-review skill.
- The recipe rows and the recipe files, which [the review-repair recipes task](ai-dev_agent-spinner-review-repair-recipes.md), [the rewrite-implement recipes task](ai-dev_agent-spinner-rewrite-implement-recipes.md), and [the decision-research recipes task](ai-dev_agent-spinner-decision-research-recipes.md) each add in one change.
- The pointers to `references/role-prompts.md` in `<shapes>` and to `references/report-shapes.md` in `<judgement>`, which [the checking-doctrine task](ai-dev_agent-spinner-checking-doctrine.md) and the judgement-containment task own.
- The concept page's list of what ships with the skill and its "Derived from" entry, which the run-ledger task owns.

## Acceptance

- `<role>`, `<invocation_boundary>`, and `<selector>` read as their target text, and the selector's table holds its header and delimiter rows and no data row.
- `grep -cE '^<(when_to_activate|references|worked_instances|family)>$'` on SKILL.md returns 0, and `grep -c` returns 0 for each superseded passage Approach lists.
- Measured from opening tag through closing tag, `<role>` holds at most 355 bytes, `<invocation_boundary>` at most 935, and `<selector>` at most 1,053. The body below the frontmatter is at least 1,791 bytes smaller than at the parent commit, and `wc -c` reports `SKILL.md` under 25,000 bytes.
- The frontmatter differs from the parent commit's only in the description's routing sentence, which reads as Approach gives it, and the description stays under 1,500 characters.
- `tests/trigger_evals/agent_spinner.json` holds the two naming queries Approach gives as `should_trigger: true` entries.
- A trigger run of the changed description, made with the scratch-config commands in Approach, passes all eight `should_trigger: false` queries and both naming queries. It also passes at least 3 of the eight `should_trigger: true` queries that name no skill, the lower of the two 2026-10-04 runs of today's text. A run below that is fixed inside this task by revising the routing sentence and measuring again.
- The RUNBOOK paragraph that named only the deployed route now names both routes, and the RUNBOOK records the 2026-10-04 measurements and this task's run, each with its date, build, model, and counts.
- `python3 plugins/ai_dev/skills/skill_doctor/scripts/resolve_scope.py --root . --family agent_spinner` resolves exactly `agent_spinner` with an empty `warnings` list.
- `bash tests/agent_spinner/script_tests/run.sh` passes with the one-to-one check. The check fails on a scratch copy whose table names a recipe file that does not exist, and on a scratch copy holding a recipe file with no row.
- Both evals exist in `evals.json` with their fixtures and grade.sh cases, each checking its named fact before any response marker, and each passes under TESTING.md's vendor rule. A failing eval is fixed in the component or the fixture before the commit, never by weakening its check.
- `diagnostic_inline`, `residual_selector`, and `governed_stop` pass on the default vendor under TESTING.md's vendor rule, with `governed_stop`'s spawn tool withheld by the runner-modes task's withholding rule, each with its fixture, prompt, expectations, and grade.sh case unchanged.
- The `## Signal per eval` table has one row per new eval, and every agent_spinner eval-count statement in the harness docs matches `jq '.evals | length' tests/agent_spinner/evals/evals.json`.
- The concept page's paragraph that opens "The skill is advisory" states the one-way citation direction and both routing cases, written through the wiki skill family, and run.sh's "the wiki concept page points at the skill" passes.
- Before the commit, a manual read of every changed shipped file and of this task's own diff finds no session, company, or project name, and no denylist is committed.
