---
name: harness_portability
description: Cross-agent-harness and cross-OS portability review for runtime artefacts bundled inside skills and plugins. Use when creating, editing, reviewing, or troubleshooting shell scripts, Python or Node helpers, hooks and hook configuration, MCP servers, command wrappers, setup and install flows, plugin wiring, agent and subagent definitions, agent frontmatter, tool allowlists, read-only agent enforcement, output styles and their per-harness rules-file and instructions-file counterparts, skill wording, execution and initialization instructions, path handling, environment variables, permissions, or provider-specific OpenAI Codex, Anthropic Claude, Cursor, Google Antigravity, SST OpenCode, and GitHub Copilot in VS Code behaviour that must work across agent harnesses, macOS, and Linux.
version: 1.0.14
author: Andreas F. Hoffmann
license: MIT
---

# harness_portability

<harness_portability>
  <objective>
    Keep bundled skill and plugin runtime artefacts portable across agent harnesses and operating systems. Apply this skill whenever a change creates or edits scripts, hooks, agent definitions, MCP helpers, command wrappers, setup flows, output styles, or the skill and plugin wording that tells future agents how to execute, initialize, or configure those artefacts.
  </objective>

  <scope>
    <included_artefacts>
      Apply these rules to Bash, POSIX shell, Python, JavaScript, TypeScript, Node.js, and other executable files shipped inside skills, agents, commands, hooks, MCP servers, plugin directories, and their supporting resources. Apply them equally to prose that wires those files into agent workflows, and to agent and subagent definition files themselves, whose frontmatter and body each harness parses under its own schema. Include a component type that only one harness implements, because the portability question there is which harnesses the component reaches and what carries the same intent on the rest.
    </included_artefacts>
    <target_harnesses>
      Treat OpenAI Codex and Anthropic Claude as the primary provider targets for every surface. Treat Cursor, SST OpenCode, Google Antigravity, and GitHub Copilot in VS Code as further targets whose native loaders each diverge in their own way, and confirm per surface whether a given target is worked out or still uncovered. Gemini CLI is no longer a supported target: Google retired that consumer surface on 18 June 2026, and Antigravity is the Google harness that replaces it, so route Google-surface work to Antigravity rather than restoring Gemini CLI paths, schemas, or deploy steps. Standard, Enterprise, and paid API-key access to the same provider's models sit outside this consumer-harness scope rather than being deploy targets of their own. Add further harnesses as concrete practice reveals new compatibility requirements.
    </target_harnesses>
    <target_operating_systems>
      Support macOS and Linux by default. Use portable APIs and runtime feature detection when behavior differs between the two systems.
    </target_operating_systems>
  </scope>

  <fact_sourcing>
    <verify_before_encoding>
      Treat every concrete harness fact as perishable: a configuration root, a frontmatter key, a tool name, an environment variable, a hook event, a settings key, a version threshold. Confirm each one against current official provider documentation, the loader source, or the installed build before a change depends on it, and record which of those three the claim rests on. An observed behavior on the machine at hand outranks documentation that omits it, and documentation outranks recollection.
    </verify_before_encoding>
    <where_snapshots_live>
      Where the working repository carries a wiki, read its harness pages first: they hold the last verified snapshot with the date and source behind each claim, which makes them a starting point that still needs re-verification rather than an authority. Write a new finding back there, or into this skill's own `references/` directory when a future agent needs it in a repository that has no such wiki. Keep this skill body to the rules themselves, so a portability review costs the rules rather than the whole fact base.
    </where_snapshots_live>
    <state_the_gap>
      State the verification gap plainly when a claim could not be confirmed, and name what would settle it. Carry an unconfirmed classification as pending rather than resolving it toward whichever answer is convenient, because a wrong negative closes a line of inquiry that a stated gap keeps open.
    </state_the_gap>
  </fact_sourcing>

  <policy>
    <rule>Design scripts and wiring for the harness that will run the published skill or plugin, not only for the harness currently doing the implementation work.</rule>
    <rule>Compose cross-harness behavior as a union of native fields: when one harness reads a field the others ignore, carry each harness's native field side by side in the shared artefact and let every other harness ignore the foreign ones. Verify unknown-field tolerance on every target first, and reach any target that cannot safely read a shared multi-harness file through a generated variant instead.</rule>
    <rule>Classify each target's frontmatter tolerance into one of three categories before sharing one file across harnesses, because two categories are not enough. An ignore-unknown target tolerates foreign keys. A strict-schema target rejects one unrecognized key and leaves the artefact unloaded while the harness keeps running. A pass-through target neither ignores nor rejects the key but forwards it to its model provider as an option, which is harmful in its own way. Both the strict and the pass-through categories need a generated variant, so define the categories on their own terms rather than through whichever product currently occupies one.</rule>
    <rule>Scope a behavior or prose rule to a single harness as a sanctioned cross-harness-compatibility mechanism, the behavior-and-prose sibling of the union-of-native-fields rule. Where that rule carries each harness's native config fields side by side, this one scopes an instruction to the one harness needing special attention, so every other harness keeps the shared instruction and its user experience while the special harness avoids an error or degraded behavior. Key the carve-out on the agent's actual capability rather than the harness identity when the triggering property is itself changing across versions, and key on the harness identity when that property is stable.</rule>
    <rule>Treat agent and subagent definition files as their own portability surface: confirm each target harness's frontmatter schema tolerance, tool naming, value shape, and agent registration mechanism before shipping a shared definition, and keep role-critical policy in the agent body so it survives harnesses that run the role inline.</rule>
    <rule>Express model and reasoning-effort inheritance by omitting the key from the shared definition, so the spawning session's setting stays the single knob. Translate an inheritance sentinel into key omission when generating a variant for a target that reads such a value as a literal model name. Reserve an explicit pin for a role that must run at a fixed depth, express it as a union of each harness's disjoint native key names, and keep a pin inside the range the target's current models actually advertise.</rule>
    <rule>Enforce a read-only agent role with each harness's own native lever, unioned in one source file where key tolerance allows, and pair every lever with the prompt-level prohibition stated in the agent body as the universal floor. Frontmatter enforcement binds only where the agent spawns as a separate agent, while the body contract also governs harnesses that degrade the role to inline execution.</rule>
    <rule>Confirm where a named agent actually registers before relying on its definition file for any guarantee. Inspect the harness agent directory, the installed plugin cache, and the spawnable-role list the harness advertises, rather than inferring registration from file placement. Write orchestrating skills so their policy survives inline degradation.</rule>
    <rule>Author shared agent sources with each harness's native field names, and reserve deploy-time transforms for format bridges. A native plugin or marketplace install reads the raw file, so a deploy-only convention takes effect only on machines where that step ran and is invisible on every native install path. Generate a variant in exactly two situations: the target reads a different format entirely, or the target cannot safely read a shared multi-harness file.</rule>
    <rule>Drop a value a variant generator cannot map rather than emitting a guess, and drop at the granularity the field has. From a structured allowlist drop only the unmappable entry and keep every name that mapped; reserve the whole-field drop for a value carrying no per-entry structure. Account for what the drop costs, since dropping a whole array also drops any enforcement its mapped names carried, and a field that falls back to its own documented default falls back to a meaning that differs per harness.</rule>
    <rule>Model hook wiring as a layered runtime surface. Identify every hook source the target harness can load, then choose one intentional activation path for each hook behavior unless duplicate execution is deliberate. Diagnose a surprising hook count by enumerating active sources before changing any script.</rule>
    <rule>Use provider-specific hook configuration files for provider-specific schemas, and keep the executable hook script shared when the same policy should run in multiple harnesses. Budget for one configuration file per harness whose schema, event names, or keying differs, plus a code bridge for a harness that expresses hooks only as executable plugin code.</rule>
    <rule>Make a shared hook script harness-neutral in both directions. Read event input from stdin when available, tolerate missing or extra fields, detect the active harness through documented environment variables, and resolve the plugin root from a documented variable with a script-relative fallback. Parse the envelope by the field names the invoking harness actually sends rather than assuming one casing, and branch the response shape the same way, since a script that only exits non-zero fails open silently on a harness that expects a decision value on stdout.</rule>
    <rule>Confirm a target harness loads plugin-bundled hooks at runtime before shipping a blocking or lifecycle hook inside a plugin, and document the trust, enablement, reload, or cache-refresh step that makes the hook active.</rule>
    <rule>Reserve a project-level hook configuration for a repository that intentionally owns its own hook policy, for repository-local activation without a plugin install, or for a quick experiment before packaging. Keep one out of a plugin's own source repository when the normal goal is to install the plugin, because the installed plugin already contributes the hook and a committed project hook usually creates a second active source.</rule>
    <rule>Size a hook's guarantee by its actual interception point. Where a harness leaves a delegation path or a tool class uncovered, state the weaker guarantee rather than presenting the guard as equivalent to the same guard elsewhere.</rule>
    <rule>Use POSIX shell features for shell scripts unless the script declares and checks for a stronger shell requirement such as Bash. Use Python standard-library APIs for path, JSON, subprocess, temporary-file, and filesystem operations when they are more portable than shell pipelines.</rule>
    <rule>Resolve paths relative to the script, skill, plugin, or explicit user-provided root. Use environment variables and documented harness inputs for configuration; keep user-specific absolute paths out of published artefacts.</rule>
    <rule>Handle spaces, quotes, newlines, and special characters in file paths and user-provided values. Quote shell expansions, pass subprocess arguments as arrays where the language supports it, and keep data separate from command strings.</rule>
    <rule>Use feature detection for external commands, optional tools, shells, package managers, and OS-specific utilities, including a binary that may sit off the executable path inside an application bundle. Provide a clear error message or documented fallback when a required dependency is unavailable.</rule>
    <rule>Treat GNU-only flags, BSD-only flags, macOS-only commands, Linux-only paths, current-user paths, and current-harness internals as portability risks. Add guards, alternative implementations, or documentation when the implementation truly depends on one of them.</rule>
    <rule>Keep non-interactive automation paths deterministic. Accept parameters, environment variables, or documented config files for inputs that scripts need in agent-driven workflows.</rule>
    <rule>Write skill and plugin instructions so future agents can execute the artefact in any target harness without relying on hidden thread state, local shell aliases, current-working-directory accidents, or undocumented plugin-cache layout.</rule>
    <rule>Treat a component type that only one harness implements as a portability surface of its own: name the harnesses it reaches, decide what carries the same intent on the others, and establish whether each mechanism adds to what the harness already supplies or replaces part of it. An additive carrier and a replacing one are not interchangeable, so moving the same text between them changes what it does even when the wording is identical.</rule>
    <rule>Sort displacement into three tiers rather than into one harness against the rest. A native tier exposes the replaceable layer as a configurable slot. A synthesizable tier exposes a whole-prompt slot whose current text can be re-derived, edited section by section, and written back, which behaves like a layer swap over an all-or-nothing slot. An append-only tier adds text that then competes with default guidance it cannot remove, so a rule written to remove something silently does nothing there. State the tier for each target rather than generalizing from one of them.</rule>
    <rule>State how a synthesized whole-prompt value re-derives its base text, which model that text belongs to, and what the generator does when an expected section heading has moved. Re-derive at generation time rather than committing a copy, expect the configured value to freeze against later model switches, and fail loudly on a missing heading instead of appending and hoping.</rule>
    <rule>Declare which delivery mode a standing-instruction artefact targets, since the modes differ in reach rather than only in file location. A global mode governs every session on the machine and is reachable only through a deploy step into the harness's own configuration tree, including any settings key that selects it. A plugin-integrated mode is live only while that plugin is loaded and enabled. Each mode needs its own placement, activation instructions, and removal steps, and one written for the other's channel does nothing.</rule>
    <rule>Deliver every supported artefact as a per-harness variant written into that harness's own native root, and treat cross-harness adoption as contamination to detect rather than as a delivery channel. A harness that loads skills, rules, or agents from a sibling's config tree will read a file shaped for the other tool, complete with frontmatter keys and conventions it does not implement, so adoption delivers a silently degraded artefact where a generated variant would have delivered a correct one. Confirm each target's discovery roots so the leak is visible, disable adoption wherever the harness offers an isolation switch, weigh what else that switch scopes away, and where no switch exists, plan for the foreign file arriving and keep the native variant authoritative. Relying on adoption is defensible only as a deliberate, stated fallback for a harness with no native root for that artefact class.</rule>
    <rule>Write a delimited block rather than the whole file when a harness's carrier for an artefact class is a single user-owned file instead of a directory. Rewrite only the text between the markers on redeploy, and remove only that span on uninstall, so the user's own content in the same file survives both. This is the markdown counterpart of merging one key into a shared settings file, and it applies wherever the file belongs to the user rather than to the deploy.</rule>
    <rule>Account for a first-match rules loader separately from an accumulating one. Where a harness stops at the first instruction file it finds, depositing one displaces the user's own file instead of adding to it, so prefer a carrier that accumulates when the goal is to add rules without suppressing what is already there.</rule>
    <rule>Read a global deploy as establishing a default rather than a guarantee, since a project, profile, or local layer outranks the user-level value on most targets. Say so wherever an instruction promises machine-wide behavior.</rule>
  </policy>

  <workflow>
    <inventory_runtime_surface>
      List every script, hook, MCP helper, command wrapper, setup flow, standing-instruction artefact, and prose instruction affected by the change. Include both directly edited files and callers that execute them.
    </inventory_runtime_surface>
    <identify_targets>
      Identify the harnesses, operating systems, shells, language runtimes, and dependency assumptions that the artefact must support.
    </identify_targets>
    <check_official_sources>
      Read the working repository's own harness snapshot first where one exists, then confirm every fact the change depends on against official provider documentation, loader source, or the installed build, per `<fact_sourcing>`. Use local official docs when they are bundled with the environment; browse official provider domains when current online details are needed.
    </check_official_sources>
    <map_hook_layers>
      For hook work, map every provider-specific source that can load the hook before editing: plugin default files, manifest hook overrides, user config, project config, managed policy, deploy-generated config, and installed plugin caches.
    </map_hook_layers>
    <apply_portable_patterns>
      Implement the change with portable path handling, argument handling, dependency detection, error reporting, and documented configuration. Prefer small explicit compatibility checks over implicit reliance on the current machine.
    </apply_portable_patterns>
    <verify_across_surfaces>
      Run the narrowest useful verification for the touched artefact. Include coverage across operating systems and harnesses when available; otherwise report the untested surface and why it could not be exercised in the current session. For agent definitions, confirm on the target harness that the definition actually loads and registers rather than inferring from file placement.
    </verify_across_surfaces>
    <record_new_findings>
      Write any newly verified or newly contradicted harness fact back to the snapshot it came from, with the date and the source, so the next reader inherits evidence instead of repeating the check.
    </record_new_findings>
    <refresh_installed_plugin_cache>
      After editing a marketplace-installed plugin, refresh the installed plugin cache through the harness's own documented command or marketplace workflow, then inspect the cached manifest and component files against the source. Restarting the harness alone can reuse stale cached plugin files.
    </refresh_installed_plugin_cache>
  </workflow>

  <review_checklist>
    <paths_and_locations>Paths resolve from documented roots and support spaces or special characters.</paths_and_locations>
    <shell_portability>Shell syntax, utilities, and flags work on macOS and Linux or are guarded with fallbacks.</shell_portability>
    <language_runtime>Python, Node.js, or other runtime code uses portable standard APIs for filesystem, process, encoding, and temporary-file behavior.</language_runtime>
    <harness_wiring>Skill and plugin prose explains execution and configuration through documented harness behavior rather than current-session implementation details.</harness_wiring>
    <fact_provenance>Every harness-specific claim the change depends on names the documentation, loader source, or installed build it was verified against, with its date, and every unconfirmed claim is carried as a stated gap rather than resolved by assumption.</fact_provenance>
    <artefact_discovery>Every supported artefact reaches each target as a variant in that target's own native root, with adoption from a sibling harness's tree treated as a leak to disable where a switch exists rather than as the delivery path, and with any unavoidable adoption stated as a deliberate fallback. Each target's discovery roots are known, any isolation switch is documented along with what else it scopes away, and a first-match rules loader is distinguished from an accumulating one.</artefact_discovery>
    <behavior_carveouts>A behavior or prose rule that special-cases one harness is scoped to the harness or capability that needs the special attention and leaves every other harness on the shared instruction and its user experience; where the triggering property changes across versions, the carve-out keys on the agent's capability rather than the harness identity.</behavior_carveouts>
    <plugin_hook_runtime>A blocking or lifecycle hook shipped inside a plugin is verified to load at runtime on each target harness, with explicit manifest overrides where the default hook file belongs to one harness only, and with config-layer registration where the harness does not execute plugin-bundled hooks.</plugin_hook_runtime>
    <hook_layering>Hook behavior has exactly the intended active sources across plugin, user, project, managed, and deploy-generated layers; duplicate execution is either removed or documented as intentional.</hook_layering>
    <hook_signalling>Hook configuration files are separated per schema, a shared script parses the envelope casing and field names the invoking harness actually sends, and it returns the response shape that harness reads, whether that is an exit code, a decision value on stdout, or a thrown error.</hook_signalling>
    <agent_definitions>Shared agent frontmatter carries only keys every target harness tolerates, each target is classified as ignore-unknown, strict-schema, or pass-through before the file is shared, tool allowlists use each harness's exact tool names and value shape, read-only roles pair frontmatter enforcement with a body-level policy that survives inline execution, unmappable values drop at field granularity with their enforcement cost accounted for, and the definition is verified to register on each harness expected to spawn it.</agent_definitions>
    <standing_instructions>A standing-instruction artefact declares its delivery mode, names the file placement and any settings key that mode needs, and describes activation through routes that currently exist. Each target is placed in the native, synthesizable, or append-only tier rather than generalizing displacement or plugin availability from one harness, an append-only variant says plainly that adherence is weaker because the prose competes with guidance it cannot remove, and a synthesized variant states how it re-derives its base text, which model that text belongs to, and what it does when an expected section heading is gone. Behavior that must hold in every session, or inside subagents, lives somewhere other than an artefact whose reach stops at the main conversation or that a safe mode disables.</standing_instructions>
    <failure_modes>Missing dependency, unsupported OS, unsupported shell, and missing config errors are actionable for a future agent.</failure_modes>
    <verification>Verification covers the touched runtime path, or the remaining unverified surfaces are named explicitly.</verification>
  </review_checklist>

  <output_contract>
    <format>
      When reporting the work, summarize the portability surface touched, the provider documentation or build checked and when, the verification performed, any harness fact written back to a snapshot, and any remaining harness or OS gaps.
    </format>
    <validation>
      The final artefact can be understood and executed by a future agent on any target harness from the published skill and plugin files, without relying on the implementation session's private state.
    </validation>
  </output_contract>
</harness_portability>
