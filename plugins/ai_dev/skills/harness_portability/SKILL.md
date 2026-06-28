---
name: harness_portability
description: Cross-agent-harness and cross-OS portability review for runtime artefacts bundled inside skills and plugins. Use when creating, editing, reviewing, or troubleshooting shell scripts, Bash scripts, Python helpers, Node helpers, hooks, Codex hook layering, Claude hook configuration, shared plugin hook scripts, MCP servers, command wrappers, setup or install flows, plugin wiring, skill wording, execution instructions, initialization instructions, configuration instructions, path handling, environment variables, permissions, or provider-specific OpenAI Codex and Anthropic Claude behavior that must work across agent harnesses, macOS, and Linux.
version: 1.0.3
author: Andreas F. Hoffmann
license: MIT
---

# harness_portability

<harness_portability>
  <objective>
    Keep bundled skill and plugin runtime artefacts portable across agent harnesses and operating systems. Apply this skill whenever a change creates or edits scripts, hooks, MCP helpers, command wrappers, setup flows, or the skill/plugin wording that tells future agents how to execute, initialize, or configure those artefacts.
  </objective>

  <scope>
    <included_artefacts>
      Apply these rules to Bash, POSIX shell, Python, JavaScript, TypeScript, Node.js, and other executable files shipped inside skills, agents, commands, hooks, MCP servers, plugin directories, and their supporting resources. Apply them equally to prose that wires those files into agent workflows.
    </included_artefacts>
    <target_harnesses>
      Treat OpenAI Codex and Anthropic Claude as the initial provider targets. Add additional harnesses as concrete practice reveals new compatibility requirements.
    </target_harnesses>
    <target_operating_systems>
      Support macOS and Linux by default. Use portable APIs and runtime feature detection when behavior differs between the two systems.
    </target_operating_systems>
  </scope>

  <policy>
    <rule>Design scripts and wiring for the harness that will run the published skill or plugin, not only for the harness currently doing the implementation work.</rule>
    <rule>Use official provider documentation before encoding provider-specific behavior for OpenAI Codex, Anthropic Claude, or another targeted harness. Prefer current official docs over memory, observed behavior in one session, or assumptions from another agent surface.</rule>
    <rule>State the provider documentation source or the verification gap when a change depends on harness-specific execution, initialization, configuration, filesystem, environment, permission, or tool-discovery behavior.</rule>
    <rule>Model hook wiring as a layered runtime surface. Identify every hook source the target harness can load, then choose one intentional activation path for each hook behavior unless duplicate execution is deliberate.</rule>
    <rule>Use provider-specific hook configuration files for provider-specific schemas, and keep the executable hook script shared when the same policy should run in multiple harnesses.</rule>
    <rule>Confirm a target harness loads plugin-bundled hooks at runtime before shipping a blocking or lifecycle hook inside a plugin, and document the trust, enablement, or reload step that makes the hook active.</rule>
    <rule>Use POSIX shell features for shell scripts unless the script declares and checks for a stronger shell requirement such as Bash. Use Python standard-library APIs for path, JSON, subprocess, temporary-file, and filesystem operations when they are more portable than shell pipelines.</rule>
    <rule>Resolve paths relative to the script, skill, plugin, or explicit user-provided root. Use environment variables and documented harness inputs for configuration; keep user-specific absolute paths out of published artefacts.</rule>
    <rule>Handle spaces, quotes, newlines, and special characters in file paths and user-provided values. Quote shell expansions, pass subprocess arguments as arrays where the language supports it, and keep data separate from command strings.</rule>
    <rule>Use feature detection for external commands, optional tools, shells, package managers, and OS-specific utilities. Provide a clear error message or documented fallback when a required dependency is unavailable.</rule>
    <rule>Treat GNU-only flags, BSD-only flags, macOS-only commands, Linux-only paths, current-user paths, and current-harness internals as portability risks. Add guards, alternative implementations, or documentation when the implementation truly depends on one of them.</rule>
    <rule>Keep non-interactive automation paths deterministic. Accept parameters, environment variables, or documented config files for inputs that scripts need in agent-driven workflows.</rule>
    <rule>Write skill and plugin instructions so future agents can execute the artefact in Codex and Claude without relying on hidden thread state, local shell aliases, current working-directory accidents, or undocumented plugin-cache layout.</rule>
  </policy>

  <hook_portability>
    <codex_hook_layers>
      Treat Codex hook sources as additive layers. Codex can load user hooks from `~/.codex/hooks.json` or inline `[hooks]` in `~/.codex/config.toml`, project hooks from `<repo>/.codex/hooks.json` or inline `[hooks]` in `<repo>/.codex/config.toml`, managed hooks from managed configuration, and plugin-bundled hooks from enabled plugins. Higher-precedence configuration layers do not replace lower-precedence hooks; all matching hooks run. If the same command is present in a plugin hook and a project or user hook, expect duplicate reviews and duplicate execution.
    </codex_hook_layers>
    <codex_project_hooks>
      Use project `.codex/` hooks for repository-local activation without plugin installation, for quick experiments before packaging, or for a project that intentionally owns its own hook policy. Keep project `.codex/` hooks out of plugin source repositories when the normal goal is to install the plugin; the installed plugin already contributes the hook and a committed project hook usually creates a second active source.
    </codex_project_hooks>
    <codex_plugin_hooks>
      Treat plugin-root `hooks/hooks.json` as Codex's default plugin hook file. Use a `.codex-plugin/plugin.json` `hooks` entry to override that default with a Codex-native hook file, an empty hook file containing only `{"hooks": {}}`, multiple hook files, or inline hook objects. Resolve manifest hook paths relative to the plugin root, keep them inside the plugin root, and start file paths with `./`.
    </codex_plugin_hooks>
    <codex_hook_schema>
      Keep Codex-consumed hook JSON strict and minimal: the top-level key is `hooks`, event names map to matcher groups, and matcher groups contain one or more handlers. Put descriptive prose in the plugin manifest, README, skill prose, or provider-specific documentation instead of adding custom top-level fields such as `description` to Codex hook JSON. Use one matcher group with a regex such as `^(apply_patch|Bash)$` when the same handler, timeout, and status message apply to multiple tools; use separate matcher groups when behavior, command arguments, timeout, status text, or policy differs.
    </codex_hook_schema>
    <codex_trust_and_cache>
      Account for Codex trust and cache behavior when validating hooks. Non-managed command hooks are listed but skipped until the user reviews and trusts the current hook definition. Trust is tied to the current hook definition, so edits require review again. After editing a marketplace-installed plugin, refresh the installed Codex plugin cache with `codex plugin add <plugin>@<marketplace>` or the matching marketplace workflow, then inspect `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`; restarting Codex alone can reuse stale cached plugin files.
    </codex_trust_and_cache>
    <claude_plugin_hooks>
      Treat Claude plugin hooks as plugin-root components that live at `hooks/hooks.json` or inline in the Claude plugin manifest. Claude command hooks receive event JSON on stdin and commonly resolve plugin files through `${CLAUDE_PLUGIN_ROOT}`. Reload or restart the Claude plugin surface after changing plugin hooks so the active session sees hook, MCP, agent, and other plugin component changes.
    </claude_plugin_hooks>
    <dual_harness_layout>
      Keep Claude and Codex hook configuration parallel rather than shared when their schemas, event coverage, matcher names, trust model, or command environment differ. A practical dual-harness plugin can use `hooks/hooks.json` for Claude, `.codex-plugin/plugin.json` pointing to `./hooks/codex-plugin-hooks.json` for Codex, and an optional deploy-only source such as `./hooks/codex-custom-deploy-hooks.json` for explicit user or project config-layer deployment. Use an empty Codex hook file when a Claude hook exists but no Codex-equivalent behavior is ready yet.
    </dual_harness_layout>
    <shared_hook_scripts>
      Share executable hook scripts across Codex and Claude when the policy is the same, but make the script harness-neutral. Read event input from stdin when available, tolerate missing or extra JSON fields, detect the active harness through documented environment variables, and resolve the plugin root from `${PLUGIN_ROOT}` or `${CLAUDE_PLUGIN_ROOT}` with a script-relative fallback. Emit blocking decisions and diagnostics in the format expected by the harness that invoked the script.
    </shared_hook_scripts>
    <duplicate_diagnosis>
      Diagnose duplicate or surprising hook counts by enumerating active sources before changing scripts. Check the plugin manifest hook path, plugin-root `hooks/hooks.json`, user and project `hooks.json`, inline `[hooks]` tables, managed policy, installed plugin cache, and the hook review UI. A displayed count can reflect separate sources, separate matcher groups, parse errors plus valid hooks, or stale cached plugin files.
    </duplicate_diagnosis>
  </hook_portability>

  <workflow>
    <inventory_runtime_surface>
      List every script, hook, MCP helper, command wrapper, setup flow, and prose instruction affected by the change. Include both directly edited files and callers that execute them.
    </inventory_runtime_surface>
    <identify_targets>
      Identify the harnesses, operating systems, shells, language runtimes, and dependency assumptions that the artefact must support.
    </identify_targets>
    <check_official_sources>
      Consult official provider documentation for any Codex, Claude, MCP, hook, skill, plugin, or command behavior that affects execution. Use local official docs when they are bundled with the environment; browse official provider domains when current online details are needed.
    </check_official_sources>
    <map_hook_layers>
      For hook work, map every provider-specific source that can load the hook before editing: plugin default files, manifest hook overrides, user config, project config, managed policy, deploy-generated config, and installed plugin caches.
    </map_hook_layers>
    <apply_portable_patterns>
      Implement the change with portable path handling, argument handling, dependency detection, error reporting, and documented configuration. Prefer small explicit compatibility checks over implicit reliance on the current machine.
    </apply_portable_patterns>
    <verify_across_surfaces>
      Run the narrowest useful verification for the touched artefact. Include macOS/Linux or Codex/Claude coverage when available; otherwise report the untested surface and why it could not be exercised in the current session.
    </verify_across_surfaces>
    <refresh_installed_plugin_cache>
      After editing a marketplace-installed plugin, refresh the installed Codex plugin cache with `codex plugin add <plugin>@<marketplace>` or the matching marketplace workflow, then inspect `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/` to confirm the cached manifest and hook files match the source. Restarting Codex alone can reuse stale cached plugin files.
    </refresh_installed_plugin_cache>
  </workflow>

  <review_checklist>
    <paths_and_locations>Paths resolve from documented roots and support spaces or special characters.</paths_and_locations>
    <shell_portability>Shell syntax, utilities, and flags work on macOS and Linux or are guarded with fallbacks.</shell_portability>
    <language_runtime>Python, Node.js, or other runtime code uses portable standard APIs for filesystem, process, encoding, and temporary-file behavior.</language_runtime>
    <harness_wiring>Skill/plugin prose explains execution and configuration through documented harness behavior rather than current-session implementation details.</harness_wiring>
    <plugin_hook_runtime>A blocking or lifecycle hook shipped inside a plugin is verified to load at runtime on each target harness, with explicit Codex manifest overrides when `hooks/hooks.json` is Claude-only and with config-layer registration where the harness does not execute plugin-bundled hooks.</plugin_hook_runtime>
    <hook_layering>Codex hook behavior has exactly the intended active sources across plugin, user, project, managed, and deploy-generated layers; duplicate execution is either removed or documented as intentional.</hook_layering>
    <dual_harness_hooks>Claude and Codex hook configuration files are separated when schemas differ, while shared shell scripts remain portable across both harnesses.</dual_harness_hooks>
    <provider_docs>Provider-specific claims are checked against official OpenAI Codex, Anthropic Claude, or other targeted provider documentation.</provider_docs>
    <failure_modes>Missing dependency, unsupported OS, unsupported shell, and missing config errors are actionable for a future agent.</failure_modes>
    <verification>Verification covers the touched runtime path, or the remaining unverified surfaces are named explicitly.</verification>
  </review_checklist>

  <output_contract>
    <format>
      When reporting the work, summarize the portability surface touched, the official provider documentation checked when applicable, the verification performed, and any remaining harness or OS gaps.
    </format>
    <validation>
      The final artefact can be understood and executed by a future Codex or Claude agent from the published skill/plugin files without relying on the implementation session's private state.
    </validation>
  </output_contract>
</harness_portability>
