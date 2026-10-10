# Wiki Log

> Chronological record of wiki changes. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`
> Actions: ingest, update, query, lint, create, archive, delete, audit, import, session-wrapup
> Entries: an operation that creates or updates wiki files appends one entry; an
> operation that changes no file appends none. Lint and audit runs are the
> exception — each records its outcome, including a zero-change one, as a
> process record.
> Body: list only files actually created or updated. Skip files that were
> inspected, considered, or deliberately left unchanged, and do not narrate
> decisions about what not to do. Aim for roughly 20 lines per entry.
> When this file exceeds 500 entries, rotate: rename to log-YYYY.md, start fresh.

## [2026-08-08] create | Wiki initialized

- Structure created with SCHEMA.md, index.md, log.md, raw/, entities/, concepts/, comparisons/, queries/, summaries/, procedures/

## [2026-08-08] update | Schema configured for the ai-modules domain

- SCHEMA.md: domain set to the repository's own knowledge plus the cross-harness research; tag taxonomy set to 21 tags across harnesses, artefacts, mechanisms, and meta

## [2026-08-08] create | Base repository knowledge

- summaries/ai-modules-repository.md
- concepts/plugin-packaging-and-versioning.md
- concepts/skill-family-architecture.md
- concepts/deployment-model.md
- index.md

## [2026-08-08] ingest | Harness research migrated out of the harness_portability skill

Facts moved from the shipped skill body into the wiki, leaving the rules in the
skill. Sources are provider documentation, loader source, and installed builds,
verified July and 7 August 2026 and cited per page.

- entities/anthropic-claude-code.md
- entities/openai-codex.md
- entities/sst-opencode.md
- entities/google-antigravity.md
- entities/cursor.md
- entities/github-copilot-vs-code.md
- concepts/claude-output-styles.md
- concepts/foreign-directory-adoption.md
- concepts/agent-definition-portability.md
- concepts/hook-surface-portability.md
- comparisons/system-prompt-substitution-across-harnesses.md
- index.md

## [2026-08-08] create | System prompt substitution experiment programme

- summaries/system-prompt-substitution-experiments.md
- index.md

## [2026-08-08] update | Antigravity gaps split out to keep the entity page scannable

- queries/antigravity-open-verification-gaps.md (created from the entity page's
  verification-gaps section, which now links to it)
- entities/google-antigravity.md
- entities/sst-opencode.md (bare-URL wording)
- index.md

## [2026-08-08] ingest | Output-style research read from the 7 and 8 August session transcripts

- concepts/output-style-delivery-design.md (source-directory decision, per-target
  delivery matrix, marked-block write, activation marker, scope rejections,
  Claude-first sequencing, and the superseded additive-semantics framing)
- concepts/hook-surface-portability.md (the concrete three-config plugin layout)
- entities/openai-codex.md (prompt subsections, off-path binary, matcher-group
  guidance, project-hook placement)
- entities/sst-opencode.md (no CLI on the machine checked)
- entities/cursor.md (the undocumented rules folder was empty when checked)
- summaries/system-prompt-substitution-experiments.md (reframed to whole-prompt
  rewrite, then before and after, then ablation)
- index.md

## [2026-08-08] session-wrapup | 2 new, 2 extended, 0 contested

- procedures/deciding-where-knowledge-belongs.md
- procedures/splitting-a-shipped-skill.md
- summaries/ai-modules-repository.md (guardrail-versus-wiki distinction sharpened
  to constrain versus inform, same audience)
- index.md (procedures section populated, total corrected to 20)

## [2026-08-08] update | Two inaccuracies in the repository description, plus the deploy script's status

- summaries/ai-modules-repository.md ("nothing here is an application" scoped to
  end-user applications; toolchain paragraph corrected against the charter's full
  dependency list rather than the instruction files' shorthand)
- concepts/deployment-model.md (what the script has become, the format-bridge
  test that keeps it a helper, and the install-path divergence risk)

## [2026-08-08] update | Audit pass: Codex delivery-route contradiction and four smaller repairs

Cross-checked every page against the task records, the deployment README, and the
code. The delivery-design table gave Codex a marked-block route the Codex task had
overruled in favour of the synthesized replacement; fixed against the task record
as the authoritative decision.

- concepts/output-style-delivery-design.md (Codex row corrected to the
  synthesized route, OpenCode row marked decision-open per its task, marked
  block rescoped to Antigravity with Codex named as the rejected taker)
- comparisons/system-prompt-substitution-across-harnesses.md (`.agents/rules/`
  removed from Antigravity's global-deploy cell; it is project scope)
- concepts/hook-surface-portability.md (harness coverage rescoped to worked-out
  contracts versus unfinished coverage)
- summaries/ai-modules-repository.md (Python-versus-shell claim scoped to the
  plugins tree with the deploy script named as the difference)
- entities/openai-codex.md (recovered the dropped fact that a relative path in
  a project configuration resolves against its own `.codex/` directory)

## [2026-08-09] update | Prior-value capture shipped, so five pages left the gap framing

The Claude output-style groundwork landed: a second discovery root at repo-root
`styles/`, a `style:<name>` configuration directive, and first-write prior capture
on the shared key-merge function with a restore on uninstall.

- concepts/deployment-model.md (discovery rewritten to two roots, `style:` added
  to the configuration directives, missing-prior section replaced by the
  recorded-prior restore with its legacy four-field and success-check provisions,
  and the Claude-only style type added to the open target-matrix holes)
- concepts/claude-output-styles.md (scope question settled for Claude at both
  scopes and left open for the three project-native harnesses; deployment-model
  link repointed at the shipped restore)
- concepts/output-style-delivery-design.md (Claude row marked as the only one
  built; why-Claude-went-first records that the shared-machinery bet paid out)
- summaries/system-prompt-substitution-experiments.md (experiment teardown now
  inherits the capture instead of waiting on it)
- summaries/ai-modules-repository.md (`styles/` added to the repo-root list)
- index.md (deployment-model summary line and date)

## [2026-08-09] lint | 0 blocking, 0 warn, 1 info

The one info is the over-threshold size of `entities/google-antigravity.md`.

## [2026-08-09] update | Pre-publish pass: one contradiction, one unsourced cap, two tag gaps, and the build fingerprints

Reviewed for publish safety and internal consistency. The activation
contradiction and the character cap were settled against
`antigravity.google/docs/rules-workflows`: the cap is stated for rules files
without exempting the global file, and the four activation modes are documented
for workspace rules only. Build numbers read off installed applications were
generalised to the date they were checked.

- comparisons/system-prompt-substitution-across-harnesses.md (Antigravity
  activation cell corrected from "Always On activation mode" to none, and the
  reach paragraph rewritten so the cap covers the global deposit)
- entities/google-antigravity.md (rules section rewritten so it sources the cap
  for both scopes and confines the activation modes to workspace rules)
- concepts/foreign-directory-adoption.md (`verification-gap` tag added)
- concepts/agent-definition-portability.md (`verification-gap` tag added)
- entities/anthropic-claude-code.md, concepts/claude-output-styles.md,
  entities/sst-opencode.md, entities/openai-codex.md (installed-build numbers
  replaced by the date checked)

## [2026-08-09] update | Antigravity page compacted rather than split

- entities/google-antigravity.md (overview scoped to what the repository deploys,
  the workspace-tree collision compacted onto the adoption page, sidecars reduced
  to the scope boundary)

## [2026-08-09] update | Single-owner pass on the duplicated harness facts

The rule applied throughout: the page that owns the subject keeps the perishable
detail, and a cross-cutting page keeps the consequence and links.

- entities/anthropic-claude-code.md (safe-mode annotation string and the
  style-collision rule handed to the styles page, consequences kept)
- summaries/system-prompt-substitution-experiments.md (Codex apparatus reduced to
  what the experiment needs, command and off-path caveat left to the entity page)
- procedures/deciding-where-knowledge-belongs.md (the duplication pitfall now
  covers page-to-page as well as home-to-home, and derivations get a filing type)

## [2026-08-09] session-wrapup | 1 new, 2 extended, 0 contested

A session applying the guardrail doc set to a Rust project produced the reasoning
behind a set of rules now filed against the `guardrail` family. The rules go to
the skill because they travel; the derivation lands here.

- concepts/guardrail-documents-as-rules.md (new: the lookup mechanism, optional
  adoption, the read-as-description misreading, the three paths by which a rule
  becomes true, why a rule carries nothing perishable, the guarding/describing
  split, and rule placement across the docs)
- summaries/ai-modules-repository.md (the harness-loads claim corrected to the
  lookup, and the contrast rewritten onto constrain-in-flight versus
  inform-on-research)
- index.md (new concept listed, total pages 20 to 21)

## [2026-08-09] audit | Pre-publish repair: framing, drifting numbers, confidence, hook state, and a log compaction

Repository going public, so the schema's purpose statement was rewritten and every
page re-read for content that decays or does not belong in a public repo. Line
counts, file sizes, token estimates, per-model prompt lengths, and version pins
restated away from their owning page were removed in favour of the property each
was standing in for. Confidence was re-rated against a new evidence rule and now
tracks each page's weakest load-bearing claim. Earlier log entries were compacted
in place, dropping narration of rejected alternatives and stale measurements.

- SCHEMA.md (domain rewritten as project memory for the agents working here, with
  the maintenance obligation, the division against guardrails and tasks, and the
  three exclusion classes; confidence given an evidence rule)
- concepts/hook-surface-portability.md (new section stating what ships and what
  the deploy actually routes per target, including Copilot's unfiltered deposit;
  open questions rewritten onto the three unsettled coverage decisions)
- concepts/deployment-model.md (hook-merge claim scoped to the targets a shipped
  file reaches, script size stated as a property)
- entities/openai-codex.md (per-model prompt lengths, model identifiers, and
  template filenames replaced by the read route and the re-derivation rule)
- entities/sst-opencode.md (vendor-prompt lengths and heading enumerations
  replaced by the two read routes and their costs; confidence raised to high)
- entities/cursor.md (confidence raised to high)
- concepts/foreign-directory-adoption.md (confidence lowered to medium, capping
  claim named; OpenCode version pin left to its owning page)
- concepts/agent-definition-portability.md (same, for the pending Antigravity
  tolerance classification)
- queries/antigravity-open-verification-gaps.md (confidence raised to high, with
  the caveat section splitting the report from the answers)
- comparisons/system-prompt-substitution-across-harnesses.md (Antigravity cap
  restatement replaced by consequence and link)
- concepts/output-style-delivery-design.md (cap number dropped from the table)
- concepts/claude-output-styles.md (loader byte limit dropped)
- concepts/skill-family-architecture.md (skill size stated as a property)
- concepts/plugin-packaging-and-versioning.md (open question rewritten onto the
  two distribution options)
- summaries/ai-modules-repository.md (line-count comparison stated as a property)
- summaries/system-prompt-substitution-experiments.md (prompt sizes dropped)
- log.md (entries compacted)
- raw/*/.gitkeep (five markers so the source tree survives a clone)
- index.md

## [2026-08-09] ingest | Copilot hook contract researched, which reclassified the deploy's foreign-file deposit

Read against `code.visualstudio.com/docs/agent-customization/hooks` and GitHub's
`/copilot/reference/hooks-reference` and `/copilot/concepts/agents/hooks`, plus a
type-scoped dry run of the deploy script. Three findings changed earlier pages
rather than only adding to them: Copilot has a worked hook contract, so it is no
longer unfinished coverage and Cursor is the last unworked target; `~/.copilot/`
is one root shared by the editor and the CLI, so a deploy named for the editor
reaches both; and Copilot reads `.claude/settings.json` and
`~/.claude/settings.json` for hooks, which makes every Claude hook deploy a
two-harness deploy.

- entities/github-copilot-vs-code.md (two-products-one-root section, full hook
  contract with roots, schema, eight events, stdin and stdout envelopes, exit
  codes and `permissionDecision`, the CLI superset and its loading rules, and the
  Claude-tree adoption extended to hooks; confidence raised to high)
- concepts/hook-surface-portability.md (four schemas and four signalling
  contracts, the matcher-group divergence named as near-miss compatibility, the
  Copilot deposit reclassified from clutter to two live parsers with the two
  failures that keep it inert, and the `~/.claude/settings.json` two-harness
  consequence added to open questions)
- concepts/foreign-directory-adoption.md (Copilot's adoption extended from prose
  to executable policy, with the line that distinction crosses)
- index.md

## [2026-08-09] update | Adoption is switched off, not just avoided, and VS Code turns out to have the switches

The user settled the delivery route: deploy natively into each harness's own root
and disable the foreign-read paths where the harness documents a switch, because a
harness reading another's artefacts implements them partially and silently, which
degrades the integration in the target rather than saving work. Checking whether
that position is implementable turned up two VS Code settings keys nothing here
had recorded, which also closed the open Copilot delivery question.

- concepts/foreign-directory-adoption.md (standing position extended from avoid to
  avoid-and-disable with the delivery-quality reasoning; the switch inventory
  rewritten, since "no other target documents an equivalent switch" was false —
  `chat.hookFilesLocations` and `chat.instructionsFilesLocations` disable a path
  at a time including documented defaults, which is finer-grained than OpenCode's
  broad environment variable)
- entities/github-copilot-vs-code.md (the two settings keys recorded beside the
  adoption paths they scope, with `github.copilot.chat.claudeAgent.enabled`
  distinguished as a different mechanism)
- concepts/hook-surface-portability.md (the two-harness consequence moved from
  forced-but-open to decided, and the Claude configuration-file question dropped
  from open questions since the decision settles it)

## [2026-08-09] update | Antigravity entity page split along its two self-contained mechanisms

An earlier pass compacted this page instead of splitting it, on the reading that
every section was per-harness reference the entity page should carry. Two sections
do not fit that reading: the global-root divergence and the tool vocabulary each
answer a question of their own, each is consumed by a cross-cutting page rather
than by a reader of the entity, and each carries its own open question. Both moved
out under a summary and a link, leaving the sections that keep the entity pages
parallel — workspace tree, skills, subagents, hooks, bundles, rules — in place.

- concepts/antigravity-global-roots.md (new: the two diverging artefact classes,
  what one global deploy does and does not reach, the `brain/` output tree that is
  not a configuration root, and the untested duplicate-registration question)
- concepts/antigravity-tool-vocabulary.md (new: both published name lists, the
  absent canonical registry, the runtime hang, the one-namespace assumption, and
  the undefined meaning of an empty array)
- entities/google-antigravity.md (both sections reduced to a summary paragraph
  and a link, bringing the page back under the split threshold)
- concepts/agent-definition-portability.md (the unmapped-name consequence now
  points at the vocabulary page for the lists behind it)
- concepts/deployment-model.md (the Antigravity generator and the per-class
  fan-out now link the two new pages)
- queries/antigravity-open-verification-gaps.md (the four-gap claim scoped to the
  ones that gate a decision, with a pointer to the two narrower questions the
  split promoted onto the vocabulary page)
- index.md (both pages listed, total 21 to 23, Antigravity entity summary
  rewritten around what it still carries)

## [2026-08-09] ingest | Per-harness isolation procedures recovered from two solved sessions

Two earlier sessions had solved the foreign-config problem empirically and the
answers lived only in transcripts. Recovered and filed as procedure pages, one per
adopting harness, because the published advice for each is wrong in a specific way
that cost real time. Both fixes were re-verified as still live on the machine
before filing: the OpenCode login agent sets its variable today, and Cursor's
internal flag reads false.

- procedures/isolating-opencode-from-foreign-config.md (new: narrow versus broad
  variable, the three escalating placements, the GUI-versus-shell environment trap
  that makes shell-profile advice fail on a desktop install, and the healthy
  `state = not running` a one-shot login agent reports, observed while confirming
  the live agent rather than taken from the source session)
- procedures/isolating-cursor-from-foreign-config.md (new: the single settings
  toggle, confirming it in the state database under the key name observed today
  rather than the one secondary sources still print, and what it removes along
  with the skills)
- procedures/isolating-vs-code-from-foreign-config.md (new: the two per-path
  location maps, the third-party agent switch, and the separate session-list
  lever, kept apart because operators conflate the first and second)
- concepts/foreign-directory-adoption.md (related-concepts list now routes to the
  three procedures, so the position links to its execution)
- index.md (three procedures listed, total 23 to 26)

## [2026-08-10] update | Output-style selection re-verified per fact against build 2.1.226

A session that lost a deployed output style to a project-local override re-checked
the settings mechanics on the current build. Three facts were re-verified and now
carry a 10 August stamp; two were not, and were held at their 7 August stamp
rather than allowed to inherit the newer date, which is the whole point of writing
the refresh per fact instead of bumping the page-wide paragraph.

Re-verified: the three-file settings precedence order, the `/config` picker's
write target and its lack of any scope choice, and the absence of a `config` CLI
subcommand. Held at 7 August: the `/output-style` deprecation and removal version
numbers, where only the command's absence from the current build was confirmed,
and the desktop-application route, which gained an operator report of the symptom
but no check of the mechanism.

- entities/anthropic-claude-code.md (precedence order stated as the three-file
  chain, `claude config` closure re-stamped, the no-interactive-route consequence
  recorded, the desktop claim marked as the page's weakest and owed a check, and
  `verification-gap` added to the tags)
- concepts/claude-output-styles.md (selection paragraph carrying the picker's
  write target, the missing scope choice against the permission-rules editor that
  has one, and the deployment consequence that only the user-level settings file
  reaches a machine-wide style)

## [2026-08-10] session-wrapup | 0 new, 1 extended, 0 contested

The page already held the override mechanism and framed it as usually desirable.
What the session established is that the same override is a silent-failure surface,
and that what a deploy may claim about it is bounded by the one repository root it
can resolve, so the scope section was rewritten around both.

- concepts/deployment-model.md (three-file order in place of the two-file
  statement, the shadowed-but-successful run named as a failure mode with the
  interactive-route asymmetry that makes it confusing, and the reachability bound
  that keeps a missing warning from reading as coverage)

## [2026-08-10] update | Wiki reconciled against the repo after skill_doctor shipped

Compared every repo-facing page against the current tree. Four commits had landed
since the last wiki write, and the largest was a new skill that mechanizes rules
this wiki already described, so most of the work was reconciling ownership rather
than adding facts. Two claims were stale in the ordinary way: a toolchain
divergence the instruction files had since closed, and a task-file pointer that
went stale when one of the six moved to the archive. One cell framed as an
accidental gap turned out to be a decision the charter had recorded since June.
The verification model had no page at all, which was the one real coverage hole.

- concepts/verification-surfaces.md (new: the two surfaces and why neither
  substitutes for the other, harnesses that exist without shipping and what that
  costs a claim of correctness, the two harness patterns, the pinned model under
  test against the inherited meta level, trigger coverage as a separate question,
  the ships-with-the-change scope rule, and the auditor checking presence rather
  than passage; confidence capped at medium by the model policy, which is
  recorded only in the uncommitted tree)
- concepts/skill-family-architecture.md (the checker section: what it covers, why
  it cites the authoring skills instead of copying them, and the block-versus-warn
  line with the reasoning that no heuristic separates absent trigger coverage from
  differently-phrased triggers; the authoring-and-checking coupling that shaped
  the YAML-scalar rule; the size open question corrected, since what the checker
  measures is description length among siblings and not body size)
- concepts/plugin-packaging-and-versioning.md (lockstep now machine-checked, and
  the ambiguity that encoding it settled: a skill version may differ from its
  plugin version, because the two count different edit histories)
- concepts/deployment-model.md (the command type recorded as retained-not-used
  under the charter's deprecation, with the term pinned down because two
  misreadings made it sound broader; the open question no longer counts the empty
  command row as a hole)
- concepts/output-style-delivery-design.md (the task-file pointer softened to name
  neither a count nor a status)
- summaries/ai-modules-repository.md (skill_doctor added to the ai_dev inventory,
  the toolchain stated as one agreed list, the authoring conventions pointed at
  their checker, and the test tree linked to its new page)
- index.md (new concept listed, total pages 26 to 27, skill-family summary
  extended)

## [2026-08-10] update | Repo state the repo already holds, swept off the pages and ruled out in the schema

The maintainer's correction on reading the pass above: a wiki page has no business
mirroring a task count, a lifecycle status, an own-artefact version, or the date a
change landed here, because git and the backlog answer all four on demand and the
copy is wrong by the next commit. Swept every instance, including several this
session had just written, and anchored the rule so the next pass does not
reintroduce them. Verification stamps against vendor products and against the
uncommitted test tree stay, since no clone can re-read either subject.

- SCHEMA.md (the third exclusion class widened from moving measurements to any
  state the repository already holds authoritatively, naming task counts and
  statuses, own-artefact versions, and in-repo change dates, with the two
  carve-outs that keep it from eating the verification stamp and the decision date)
- concepts/output-style-delivery-design.md (task-file count and archive location
  dropped from the derivation, the built row stated without a ship date, remaining
  targets no longer counted, and two task-ownership asides rewritten as the open
  decisions they stand for)
- concepts/deployment-model.md (three in-repo change dates dropped, and the open
  question's sibling-task count replaced by the unbuilt harnesses it meant)
- concepts/claude-output-styles.md (ship date dropped, open-elsewhere scope
  question no longer routed through backlog status)
- concepts/skill-family-architecture.md (checker introduced without a landing date)
- concepts/plugin-packaging-and-versioning.md (same, and the lockstep clarification
  rewritten to carry the reasoning rather than the commit that added it)
- summaries/ai-modules-repository.md (plugin and skill counts replaced by named
  families with a pointer at `plugins/` for current membership, and the toolchain
  archaeology cut in favour of why both documents name the dependencies)

## [2026-08-13] update | The Claude Code skill load path, read out of the build

Making `skill_doctor` portable across repository conventions needed one question
answered from the harness rather than from house style: which faults actually stop
a skill loading or routing. Reading the installed build's own skill load path
settled five mechanics and overturned two assumptions the wiki had recorded — that
a missing `version:` and a `name:` disagreeing with its directory are harness
faults. Neither is. The auditor's severity lines now follow the load path, and the
page that described the old lines was carrying a statement the code had left
behind.

- entities/anthropic-claude-code.md (new **Skill loading** section: the
  case-insensitive filename match and the multiple-files log line, the
  regular-file-and-byte-limit guard with its stat-follows-symlink behaviour and
  the skip warning it emits, the registered-name resolution that prefers
  frontmatter `name:` and falls back to the directory basename, and `version:`
  being optional in every schema that accepts it — each stamped to the build it
  was read from, with that read added to the derivation list)
- concepts/skill-family-architecture.md (severity passage rewritten in place from
  two tiers to three and re-anchored on the harness load path rather than on the
  house style, the mismatch and version findings moved to the tiers the harness
  supports, the portability shift stated, the auditor's scope widened past the
  plugin layout, and the description-length open question corrected to the two
  axes it now measures)
- index.md (both summaries widened to name what the pages gained)

## [2026-08-13] update | The Codex CLI found and read, closing its no-local-build gap

A maintainer correction overturned a wrong negative from the pass above: the
Codex CLI is installed after all, shipped inside the ChatGPT desktop application
bundle rather than on PATH — the trap the entity page's own instructions-slot
section already warned about. Reading the binary settled which harness owns the
skill load-path messages the portability task quoted (they are Claude's, absent
from Codex) and yielded Codex's own skill mechanics, previously resting on
documentation only.

- entities/openai-codex.md (verification preamble rewritten in place now that a
  local build exists; new **Skill loading** section: the bundle location that
  hides the binary from PATH lookups, the tooling's closed frontmatter allowlist
  rejecting `version` while the runtime loader tolerates it on copied-in skills,
  frontmatter-sourced skill names with no directory-equality rule, the
  listing-layer metadata budget and traversal cap, the recorded negative that
  Claude's `Skipping plugin skill` message family appears nowhere in this
  binary, and the unverified filename-case question; derivation list extended
  with the binary read)
- index.md (Codex summary widened to name the skill-loading split)

## [2026-08-15] update | Instruction-defect classes and grader-design lessons from the backlog-coherence session

Captured the generalizing knowledge from building the base `task` skill's
backlog-coherence assessment: a taxonomy of three defect classes in
AI-consumed instructions that pass human review and fail at runtime (reach,
disposition, intra-file contradiction), and the eval-grader lessons that a
grader testing surface form reports working behaviour as broken and a long
conjunction hides which behaviour broke. The through-line, that measurement
surfaces what review misses, connects both. The instruction-defect taxonomy is
new knowledge with no prior home; the grader lessons extend the existing
verification page because they advance its open question about what an eval
result means. Confidence medium: the underlying defects are observed, but the
taxonomy's reach beyond the one block is unvalidated, since the cross-artefact
pass never ran.

- concepts/instruction-defect-classes.md (new concept page: the three classes,
  why each evades review, the coordination-link versus reverse-duplicate-pointer
  contradiction as worked example, and open questions on distillation into a
  shipped rule, mechanization, and completeness)
- concepts/verification-surfaces.md (two new state-of-knowledge subsections on
  grader authoring: surface-form graders misreport, and a conjunction hides
  which behaviour broke; open question on eval weight sharpened with the
  distribution framing; cross-link to the new page added)
- index.md (new concept entry; verification-surfaces summary widened for the
  grader-honesty lessons)

## [2026-08-26 19:06] update | The limit of instruction repair, measured on the log-preamble fix

Captured while closing the wiki-only log-scope backlog task: removing three
genuine intra-file contradictions from the wiki agent's log-preamble drift fix
left the owner-line deletion rate unchanged (Layer 2 pass rate 92% before, 90%
after, runs of 2026-08-22). The lesson extends the instruction-defect taxonomy:
once no instruction misdirects, a residual judgement stays sampled, and a
must-always-hold property needs a mechanism the instruction merely invokes. The
task backlog carries the mechanism follow-up.

- concepts/instruction-defect-classes.md (new state-of-knowledge subsection on
  the repair limit and the measure-after-repair test, derivation extended with
  the measuring session, tags gain experiment)
- index.md (summary widened for the repair-limit lesson; last-updated bumped)

## [2026-08-29 19:37] update | Reconciled the wiki with the autonomous task family and the guardrail direction register

Three weeks of skill and agent work had landed since the last content pass with
no wiki reconciliation. Two meta-level gaps were filled from the shipped
artifacts. The autonomous task and wiki families share one delegation
architecture that had no page, and the guardrail direction register shipped
without its reasoning captured. The declared-direction material also reconciled
the guarding-versus-describing page, which had filed direction under describing.

- concepts/agent-delegated-automation.md (new: the front-end-to-agent delegation
  shape, read fan-out against a single serialized writer, refute-by-default
  verification with refutable gate citations, human-routed judgement calls,
  frozen intent, and the monolith-to-fan-out scaling)
- concepts/guardrail-documents-as-rules.md (new declared-direction subsection kept
  to the reasoning, with the mechanics left to the guardrail skill to avoid a
  drifting second copy; the guarding-and-describing section widened to three
  registers so an unreached target no longer reads as a false description; open
  question rewritten for the three-way distinction)
- concepts/skill-family-architecture.md (naming section points at the new runtime
  architecture page; related concepts extended)
- concepts/verification-surfaces.md (related concepts link to the run-time
  verification counterpart)
- concepts/instruction-defect-classes.md (related concepts link to the mechanism
  that carries a property the instruction only invokes)
- summaries/ai-modules-repository.md (inline pointer to the delegation pattern the
  spawned agents share)
- index.md (new concept listed, total pages 28 to 29, last-updated bumped)

## [2026-08-29 19:49] audit | 0 blocking, 1 warn, 1 info; 1 page updated, 0 pages split

Full end-to-end audit with a cold read of every page, since no prior audit
recorded a git baseline to scope against. The linter is clean at exit 0. The
session's new and extended pages hold: agent-delegated-automation and the
guardrail direction register carry correct concept anatomy, frontmatter, and
tags, and neither contradicts the pages they cross-link. Index membership is
exact at 29 of 29, and the index and SCHEMA section scaffolds match the canonical
templates. One genuine issue was fixed. The two standing lint findings were left
in place: the log preamble deviation is owned by the open template-deviation
tasks, and the openai-codex size is a pre-existing INFO whose split is out of
this pass's scope. Several confidence and cross-page items on pages this pass did
not otherwise touch are surfaced for human review rather than changed, because
re-rating evidence and reconciling a compatible-but-unclear path claim are
judgement calls, not deterministic repairs.

- procedures/splitting-a-shipped-skill.md (dropped the off-subject `portability`
  tag; the page's subject is intra-skill refactoring, not how one artefact
  behaves across harnesses, so the tag was a false entry point for cross-harness
  search; `authoring` and `skill` still cover it)
- Audit baseline: 7aac9722939b82981d71f38a70fdb64b239ee293
- Cold page reads: entities/anthropic-claude-code.md, entities/cursor.md, entities/github-copilot-vs-code.md, entities/google-antigravity.md, entities/openai-codex.md, entities/sst-opencode.md, concepts/agent-definition-portability.md, concepts/agent-delegated-automation.md, concepts/antigravity-global-roots.md, concepts/antigravity-tool-vocabulary.md, concepts/claude-output-styles.md, concepts/deployment-model.md, concepts/foreign-directory-adoption.md, concepts/guardrail-documents-as-rules.md, concepts/hook-surface-portability.md, concepts/instruction-defect-classes.md, concepts/output-style-delivery-design.md, concepts/plugin-packaging-and-versioning.md, concepts/skill-family-architecture.md, concepts/verification-surfaces.md, comparisons/system-prompt-substitution-across-harnesses.md, queries/antigravity-open-verification-gaps.md, summaries/ai-modules-repository.md, summaries/system-prompt-substitution-experiments.md, procedures/deciding-where-knowledge-belongs.md, procedures/isolating-cursor-from-foreign-config.md, procedures/isolating-opencode-from-foreign-config.md, procedures/isolating-vs-code-from-foreign-config.md, procedures/splitting-a-shipped-skill.md

## [2026-08-29 20:55] update | Claude Code file-edit read state verified

The installed Claude Code build confirms that `Edit` checks a session-local
file-read record. Bash inspection does not satisfy that precondition, so the
portable instruction scopes the `Read`-before-`Edit` rule to harnesses exposing
that capability while preserving Bash for locating offsets and oversized-file
narrowing.

- entities/anthropic-claude-code.md (new dated file-edit read-state section and
  installed-build derivation)
- index.md (Anthropic Claude Code summary widened for the new mechanism)

## [2026-08-29 20:58] lint | 0 blocking, 1 warn, 1 info

The narrow post-update lint exited 0. The live findings are the pre-existing
`boilerplate` warn on `log.md` and the size info on
`entities/openai-codex.md`; this update introduced neither.

## [2026-08-30 14:32] update | Tests harness now committed; verification-surfaces reconciled

The repository started tracking the `tests/` harness: the authored evals,
fixtures, scripts, and READMEs are committed and linted, while `tests/.gitignore`
keeps only run output out of git. The verification-surfaces concept page was
built on the opposite premise, so its current-state section, its confidence
caveat, and one open question were reconciled to the committed arrangement.

- concepts/verification-surfaces.md (retitled and rewrote the lead subsection for
  the committed-but-not-deployed apparatus; relieved the model-policy confidence
  caveat, since `tests/CLAUDE.md` and the runner defaults now travel with a clone;
  removed the resolved open question on whether the tree should stay uncommitted;
  refreshed the `## Derived from` provenance)
- concepts/instruction-defect-classes.md (a `## Derived from` bullet called the
  Layer 2 harness the "uncommitted local test tree"; the session it cites stayed
  ephemeral, but the tree is committed now, so the bullet says so)
- summaries/ai-modules-repository.md (the "local-only test tree" is now the
  "committed test tree")
- index.md (updated the verification-surfaces summary line and the Last updated
  stamp)

## [2026-09-01 13:23] update | Claude Code standing-instruction discovery verified

The Claude Code entity page never said which files carry project standing
instructions, a gap that surfaced while designing an eval sandbox that had to
plant one. Build 2.1.226 states on its Codex-import path that it hardcodes the
`CLAUDE.md` / `AGENTS.md` pair, which is also the point of contrast with Codex,
where the filename set and its size bound are configurable settings. Two worker
runs then honoured a rule written only in an `AGENTS.md`, confirming either
filename stands alone.

- entities/anthropic-claude-code.md (new dated standing-instruction-files
  section covering the hardcoded filename pair, the Codex contrast, and the
  observed either-filename-alone behaviour; `## Derived from` extended with the
  build read and the two worker runs)
- index.md (Anthropic Claude Code summary widened for the standing-instruction
  pair; last-updated bumped)

## [2026-09-01 13:26] lint | 0 blocking, 1 warn, 2 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` is the
pre-existing preamble deviation the open template-deviation work owns. The size
info on `entities/openai-codex.md` is likewise pre-existing. The size info on
`entities/anthropic-claude-code.md` is new: the standing-instruction section
carried the page from 182 to 209 lines, past the ~200 soft threshold, and the
split is left for a human to weigh rather than taken here.

## [2026-09-05 21:26] update | punctuation sweep across the wiki's own pages

Applied the repo-wide em-dash and en-dash rewrite to the wiki pages, rewording
each dash into ordinary punctuation with no change of meaning, then bumped
`updated` on the eight content pages and refreshed the index stamp.

- SCHEMA.md (dash rewrites in the conventions, page-type, and provenance prose)
- index.md (dash rewrites in every entry summary; Last updated bumped)
- concepts/claude-output-styles.md
- concepts/deployment-model.md
- concepts/guardrail-documents-as-rules.md
- concepts/skill-family-architecture.md
- entities/anthropic-claude-code.md
- entities/cursor.md
- entities/openai-codex.md
- summaries/ai-modules-repository.md

## [2026-09-16 09:43] update | Agent-delegated automation records where the general rule now lives

The orchestration doctrine this page reasons about now also ships as a
standalone skill, so the page says so and marks the direction: the skill states
the general shape and the front-end families keep authority over their own
runs. The split is the wiki's own travel test, since a rule an agent needs in
another repository has to travel with the artefact.

- concepts/agent-delegated-automation.md (new subsection on the general rule
  living in a skill, the one-way advisory direction, and the inline floor the
  skill adds beyond this page; `## Derived from` extended with the skill and
  its references; `updated` bumped)
- index.md (Agent-delegated automation summary widened for the skill pointer;
  Last updated bumped)

## [2026-09-16 09:44] lint | 0 blocking, 1 warn, 2 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` and
both size infos are pre-existing; this update introduced none of them.

## [2026-10-01 22:26] update | Claude output styles re-checked against the docs, the changelog, and build 2.1.284

A question about whether Claude Code still supports custom output styles was
checked against the docs page, the full changelog, and the running build.
Support is current and still being extended. Two recorded claims did not
survive. The `/output-style` command is back since v2.1.269, and the loader
ignores an unknown frontmatter key instead of rejecting it. Two design pages
cited the second claim as a reason, so their premise was corrected while the
decisions keep their remaining reasons.

- concepts/claude-output-styles.md now lists Concise among the built-ins, adds
  the restored command and the VS Code menu as routes that write local scope,
  records next-message switching since v2.1.251, and replaces the fifth-key
  rejection with the shadow-only validation, all stamped 1 October 2026.
- entities/anthropic-claude-code.md renames its retired-surfaces section to
  cover the restored command, marks the v2.1.91 removal as unverified, records
  the documented desktop route, and narrows the verification gap to two open
  questions.
- concepts/output-style-delivery-design.md keeps the deploy-configuration
  placement and drops the loader-breakage reason it no longer has.
- concepts/deployment-model.md now points at the delivery design page for its
  reasons instead of restating the stale one.
- index.md widens two summaries and bumps the last-updated stamp.

## [2026-10-01 22:27] lint | 0 blocking, 1 warn, 3 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` and the
size infos on `entities/anthropic-claude-code.md` and `entities/openai-codex.md`
are pre-existing. The size info on `concepts/claude-output-styles.md` is new,
because this update carried the page from 185 to 211 lines. The split is left
for a human to weigh.

## [2026-10-01 22:45] update | Oversized pages split along their natural seams

Three pages had grown past the size threshold and a fourth sat exactly on it.
Each held a sub-topic an operator would look up on its own, so each was split
along that seam. The moved prose is verbatim apart from links and the sentences
that join it to its new page. Each new page carries a `checked:` date for the
oldest claim it holds.

- concepts/skill-load-paths.md is new and holds the Claude Code and Codex skill
  load paths from the two entity pages, with the unverified Codex filename-case
  question as its open question.
- concepts/claude-output-style-selection.md is new and merges the selection
  material the output-style concept page and the Claude entity page each held
  part of: the key, the routes and the scope they write, switching, the command
  history, and the desktop route.
- concepts/hook-delivery-design.md is new and holds the hook layout, the
  per-target deploy routing, the Copilot deposit finding, and the decision to
  deliver Copilot natively.
- entities/anthropic-claude-code.md now points at the two new Claude pages in
  place of its skill-loading and style-route sections, keeps the `claude config`
  closure, and drops the derivation bullets that moved with their facts.
- entities/openai-codex.md keeps the bundled-binary location under a renamed
  skill section that points at the skill load paths page.
- concepts/claude-output-styles.md keeps the file locations and points at the
  selection page for everything a route writes.
- concepts/hook-surface-portability.md keeps the harness contracts and points at
  the delivery page for the layout, the routing, and the Copilot decision.
- concepts/deployment-model.md links the delivery and selection pages, and now
  says every interactive route writes the winning file, since three routes exist.
- concepts/skill-family-architecture.md and
  procedures/isolating-vs-code-from-foreign-config.md now link the new pages
  their references moved to.
- index.md lists the three new pages, narrows four summaries, and counts 32
  pages.

## [2026-10-01 22:46] lint | 0 blocking, 1 warn, 0 info

The narrow post-split lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing. The split cleared all three size infos, and no page now runs past
200 lines.

## [2026-10-02 12:54] update | What a headless Claude Code worker loads, probed on build 2.1.226

Marker styles and marker instruction files in throwaway sandboxes showed which
styles, settings, and instruction files reach a `claude -p` worker.

- entities/anthropic-claude-code.md records that `--setting-sources
  project,local` keeps the user-level settings and their style out of a worker,
  that print mode drops a malformed settings file silently, and that the
  `CLAUDE.md` search runs past the repository root and reaches the user-level
  file from any working directory under the home directory.
- concepts/claude-output-style-selection.md records that a headless worker
  honours a project selection, nested in another repository and under the
  narrowed setting sources alike.
- concepts/claude-output-styles.md records that `--append-system-prompt-file`
  loads a style body beside the style layer rather than in it.
- concepts/verification-surfaces.md adds what an eval worker inherits from its
  host and the two moves that isolate it, with the unmeasured effect on the
  prose harness's recorded results as an open question.
- index.md refreshes those four one-liners.

## [2026-10-02 12:55] lint | 0 blocking, 1 warn, 0 info

The narrow post-update lint exited 0 after concepts/verification-surfaces.md was
tightened back to the size threshold. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-03] update | Test harness vendor switch (Claude sonnet alias / Cursor auto)

Probed and recorded the shared `--vendor {claude,cursor}` worker policy for the
local eval runners.

- concepts/verification-surfaces.md: worker pin is now vendor-scoped (`sonnet`
  latest alias on Claude, `auto` on Cursor); judges inherit on Claude; Claude-only
  surfaces reject `--vendor cursor`.
- tests/AGENTS.md (new) and tests/CLAUDE.md / tests/README.md carry the operator
  matrix, auth, and skill/agent staging rules beside the sandbox.

## [2026-10-03] create | Interpreter and tool-path portability

Recorded the dated evidence behind the bash 3.2 floor now carried by the
`harness_portability` skill.

- concepts/interpreter-and-tool-path-portability.md: stock `/bin/bash` 3.2.57,
  licence why, login-shell PATH trap, and per-construct diagnostics verified by
  execution under that build on 3 October 2026.
- procedures/deciding-where-knowledge-belongs.md: See Also link to the new page
  as the worked skill-versus-wiki split.
- index.md: Concepts entry for the new page; page count to 33.

## [2026-10-04 12:32] ingest | Agent spinner run evidence and agent delegation host observations, September 2026

Imported the two anonymized raw notes captured today from a private research
archive, `raw/notes/agent-spinner-run-evidence-2026-09.md` and
`raw/notes/agent-delegation-host-observations-2026-09.md`. The run evidence got
a page of its own, the Claude Code delegation observations got a concept page,
and each other dated host observation went to the page that owns its subject.

- concepts/orchestration-failure-families.md (new: run classes and a case
  register under neutral labels, the 23 failure families with their counts and
  doctrine values, the base rates, the mechanisms observed together, and a
  recipe table with the raw note's families column; it calls the recipes
  proposed, and its confidence paragraph names the claims that cap it)
- concepts/claude-delegation-surfaces.md (new: the Workflow and Agent tool
  delegation, shell-tool, and print-mode passages, each citing its raw note
  inline, with the analyst-only list flagged as partial)
- entities/anthropic-claude-code.md (points at the new delegation page)
- entities/cursor.md (dated delegation, delivery, isolation, context-load,
  continuation, hook-event, agent-shell, and print-mode CLI observations, the
  observed reach of `readonly`, the lint-gate limit as a dated workstation
  condition, and the planned probes in its verification gaps)
- concepts/interpreter-and-tool-path-portability.md (the stock bash and python3
  as the bundled-script floor, the absent timeout commands, an observed
  confirmation of the PATH trap, and two zsh constructs that misfire in commands
  an agent runs directly)
- concepts/agent-definition-portability.md (Cursor's `readonly` lever points at
  its observed reach)
- concepts/agent-delegated-automation.md (the read-only property as per-harness
  levers beside the gate's stamp write, an open question on how the relay capped
  the verifiers in three governed runs, and a link to the new evidence page)
- concepts/instruction-defect-classes.md (a link to the new evidence page)
- index.md (two new concept entries, adjusted summaries, 35 pages)

## [2026-10-04 13:12] lint | 0 blocking, 1 warn, 2 info

The narrow post-ingest lint exited 0. The `boilerplate` warn on `log.md` and the
size info on `concepts/verification-surfaces.md` are pre-existing. The size info
on `entities/cursor.md` came with the 12:32 import, and its split is left for a
human to weigh.

## [2026-10-04 15:12] ingest | Delegation probes of Claude Code, Cursor, and Codex, 4 October 2026

Imported today's live probe results as one raw note that keeps the sub-agent
facts agent_spinner relies on apart from the CLI facts that serve the test
runner, and placed each fact on the page that owns its subject.

- raw/notes/delegation-probes-2026-10-04.md (new: both fact groups with their
  builds, plus the probe flags read from the run metadata)
- concepts/agent-definition-portability.md (two dated tables, role-level levers
  by host and mode and session-level levers, replacing the superseded Codex
  approval caveat)
- concepts/claude-delegation-surfaces.md (the print-mode spawn surface, observed
  flag behaviour with resume and stream-json events, narrowed open questions)
- entities/cursor.md (print-mode roles, tools, Task record, delivery, goal tools,
  permission file, resume, and stream events; the builds comparison and the
  verification gaps rewritten, the deny-entry question settled)
- entities/anthropic-claude-code.md (deployed roles and skills reaching a
  sandboxed session, and the scratch configuration directory that kept them out)
- entities/openai-codex.md (binary path corrected to
  `Contents/Resources/codex-cli/bin/codex`, per-run project trust, role sources,
  sub-agent and goal tools, headless runs through `codex exec`)
- concepts/skill-load-paths.md (a Codex project skill found under `.agents/skills/`)
- concepts/verification-surfaces.md (deployed roles and skills among what a
  worker inherits)
- index.md (seven summaries refreshed)

## [2026-10-04 15:13] lint | 0 blocking, 1 warn, 3 info

The narrow post-ingest lint exited 0, and markdownlint passed on every file the
ingest touched. The `boilerplate` warn on `log.md` is pre-existing. The size info on
`concepts/verification-surfaces.md` is pre-existing, the one on
`entities/cursor.md` came with the 12:32 import and grew with this one, and the
one on `entities/openai-codex.md` is new with this ingest. Both entity splits
are left for a human to weigh.

## [2026-10-05 16:28] update | Claude-only surfaces now include natural_language

- concepts/verification-surfaces.md (`natural_language` added to the Claude-only
  surfaces parenthetical)

## [2026-10-05 20:07] update | Headless outputStyle selection re-checked on build 2.1.289

- concepts/claude-output-style-selection.md (build 2.1.289 still applies a
  project `outputStyle` on the same marker route the 2.1.226 probe used, observed
  on 5 October 2026 through the `natural_language` harness preflight)
- index.md (selection-page one-liner and Last updated)

## [2026-10-05 20:08] lint | 0 blocking, 1 warn, 0 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-06 15:59] update | Toolchain floor owns remaining standing tools

- summaries/ai-modules-repository.md (toolchain passage now describes the
  charter's delegation to the `make install` floor, the instruction-file
  inventory, and the deploy script's `jq`, `perl`, and `rsync` startup gate)
- index.md (Last updated)

## [2026-10-06 16:01] lint | 0 blocking, 1 warn, 0 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-06 17:20] ingest | Cursor style-rule injection probes

- raw/notes/cursor-style-injection-probes-2026-10-06.md (new)
- entities/cursor.md (project always-apply `.mdc` as the injecting deploy path;
  home `rules/` and local-plugin rules settled as print-mode negatives; account
  User Rules kept as the settings-only machine-wide slot)
- concepts/output-style-delivery-design.md (Cursor row and harness-split passage)
- comparisons/system-prompt-substitution-across-harnesses.md (Cursor global-write
  row and expense paragraph)
- index.md (Cursor, delivery-design, and comparison one-liners)

## [2026-10-06 17:21] lint | 0 blocking, 1 warn, 0 info

The narrow post-ingest lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-07 08:25] update | Cursor style row built

- concepts/output-style-delivery-design.md (Claude and Cursor as the built rows;
  the content-transform passage records the Cursor generator's
  `<engineering_behavior>` rewrite beside the `replace:` route the remaining
  append-only targets still plan; the deploy script added to Derived from)
- concepts/deployment-model.md (Cursor's generated style rule among the generated
  files, the generator clause made count-free, and the `style` open question)
- index.md (Last updated)

## [2026-10-07 08:25] lint | 0 blocking, 1 warn, 0 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-08 11:05] ingest | Cursor skill-shadowing probes

- raw/notes/cursor-skill-shadowing-probes-2026-10-08.md (new)
- entities/cursor.md (a deployed user-level skill taking the place of a staged
  copy outside the workspace, and the project-skill staging that avoided it)
- concepts/verification-surfaces.md (the two isolated prose harnesses named in
  place of the backlog pointer, and a pointer to the Cursor skill swap)
- index.md (Cursor one-liner and Last updated)

## [2026-10-08 11:06] lint | 0 blocking, 1 warn, 0 info

The narrow post-ingest lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-08 11:50] ingest | Eval-worker dependency skill reads

- raw/notes/eval-worker-dependency-skill-reads-2026-10-08.md (new)
- entities/cursor.md (three-of-three frequency for the deployed-copy read, and
  unstaged dependency skills resolving to their deployed copies)
- concepts/verification-surfaces.md (unstaged dependency skills resolving to
  deployed copies or the checkout on both vendors, and the backlog pointer)

## [2026-10-08 11:51] lint | 0 blocking, 1 warn, 0 info

The narrow post-ingest lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-08 12:03] ingest | Micro-deployed worker home probes

- raw/notes/micro-deployed-worker-home-probes-2026-10-08.md (new)
- entities/cursor.md (a project copy does not displace a deployed copy without a
  path, `CURSOR_CONFIG_DIR` leaves skill discovery on the home directory, and a
  scratch home with its `Library` linked back loads the skill deployed into it)
- entities/anthropic-claude-code.md (a scratch config directory lists project
  skills and loads a skill deployed into its own `skills/` by name)
- concepts/verification-surfaces.md (scratch home and scratch config directory as
  the way to take deployed copies out of view)

## [2026-10-08 12:03] lint | 0 blocking, 1 warn, 0 info

The narrow post-ingest lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-09 14:32] update | Per-pass micro-deployment and read check

- concepts/verification-surfaces.md (the backlog pointer replaced by the shipped
  mechanism: per-pass deployment through the deploy script, the read check that
  fails on home and checkout copies, and why it expands shell paths against the
  worker's own environment on Claude)
- index.md (Last updated)

## [2026-10-09 14:33] lint | 0 blocking, 1 warn, 0 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-09 16:52] update | Cursor as the default eval vendor

- concepts/verification-surfaces.md (Cursor as the default vendor because its
  runs are cheaper and faster, a Claude suite as an occasional sample the
  operator asks for, and the repo rules and `TESTING.md` among the places the
  practice is recorded)

## [2026-10-09 16:53] lint | 0 blocking, 1 warn, 0 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-09 17:16] update | Per-harness default eval vendor

- concepts/verification-surfaces.md (evals run without `--vendor`; Claude-only
  surfaces default to Claude and stop with an error on an explicit
  `--vendor cursor`)

## [2026-10-09 17:17] lint | 0 blocking, 1 warn, 0 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-09 17:53] update | Claude runs where a test needs a Claude-specific feature

- concepts/verification-surfaces.md (a test that exercises a Claude-specific
  feature names it and runs on Claude through the vendor flag or a Claude-only
  harness, and any other Claude run waits for the operator's explicit request)

## [2026-10-09 17:54] lint | 0 blocking, 1 warn, 0 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-09 18:10] update | Claude runs name the vendor flag

- concepts/verification-surfaces.md (a Claude run's command carries
  `--vendor claude` even on a Claude-only harness whose default is already
  Claude, so every Claude run is visible in its command)

## [2026-10-09 18:11] lint | 0 blocking, 1 warn, 0 info

The narrow post-update lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-09 21:05] ingest | Cursor helper transcript probes

- raw/notes/cursor-helper-transcript-probes-2026-10-09.md (new)
- entities/cursor.md (a helper's tool calls land in its own chat transcript;
  the print-mode transcript location per chat with the parent's `session_id`
  and the helper's `agentId` as chat ids; the extra keys on a stream
  `tool_call` object)
- concepts/verification-surfaces.md (a spawned helper's reads count as the
  worker's, from Claude's stream and from Cursor's chat transcripts)
- index.md (Cursor one-liner)

## [2026-10-09 21:06] lint | 0 blocking, 1 warn, 0 info

The narrow post-ingest lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.

## [2026-10-09 22:06] ingest | Cursor print-mode shell probes

- raw/notes/cursor-print-mode-shell-probes-2026-10-09.md (new)
- entities/cursor.md (the print-mode CLI builds a shell command's environment
  from a login shell under the worker's `HOME`, where a scratch home without a
  profile resolved the stock bash; the non-login observation scoped to the IDE)
- concepts/verification-surfaces.md (the login profiles in Cursor's scratch
  home that put back the worker's launch `PATH`)
- index.md (Cursor one-liner)

## [2026-10-09 22:06] lint | 0 blocking, 1 warn, 0 info

The narrow post-ingest lint exited 0. The `boilerplate` warn on `log.md` is
pre-existing.
