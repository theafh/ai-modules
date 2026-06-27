---
name: harness_portability
description: Cross-agent-harness and cross-OS portability review for runtime artefacts bundled inside skills and plugins. Use when creating, editing, reviewing, or troubleshooting shell scripts, Bash scripts, Python helpers, Node helpers, hooks, MCP servers, command wrappers, setup or install flows, plugin wiring, skill wording, execution instructions, initialization instructions, configuration instructions, path handling, environment variables, permissions, or provider-specific OpenAI Codex and Anthropic Claude behavior that must work across agent harnesses, macOS, and Linux.
version: 1.0.2
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
    <rule>Confirm a target harness loads plugin-bundled hooks at runtime before shipping a blocking or lifecycle hook inside a plugin, and document the trust or enablement step that makes the hook active. Anthropic Claude auto-discovers a plugin-root `hooks/hooks.json` with no manifest entry. OpenAI Codex loads trusted plugin-bundled hooks from a plugin-root `hooks/hooks.json` by default, or from the `.codex-plugin/plugin.json` `hooks` path when present; Codex also loads config-layer hooks from files such as `~/.codex/hooks.json`, `<repo>/.codex/hooks.json`, or `[hooks]` in `config.toml`, which remain the right path for non-plugin activation or immediate repo/global wiring. Codex skips non-managed plugin hooks until the user reviews and trusts the current hook definition.</rule>
    <rule>Use POSIX shell features for shell scripts unless the script declares and checks for a stronger shell requirement such as Bash. Use Python standard-library APIs for path, JSON, subprocess, temporary-file, and filesystem operations when they are more portable than shell pipelines.</rule>
    <rule>Resolve paths relative to the script, skill, plugin, or explicit user-provided root. Use environment variables and documented harness inputs for configuration; keep user-specific absolute paths out of published artefacts.</rule>
    <rule>Handle spaces, quotes, newlines, and special characters in file paths and user-provided values. Quote shell expansions, pass subprocess arguments as arrays where the language supports it, and keep data separate from command strings.</rule>
    <rule>Use feature detection for external commands, optional tools, shells, package managers, and OS-specific utilities. Provide a clear error message or documented fallback when a required dependency is unavailable.</rule>
    <rule>Treat GNU-only flags, BSD-only flags, macOS-only commands, Linux-only paths, current-user paths, and current-harness internals as portability risks. Add guards, alternative implementations, or documentation when the implementation truly depends on one of them.</rule>
    <rule>Keep non-interactive automation paths deterministic. Accept parameters, environment variables, or documented config files for inputs that scripts need in agent-driven workflows.</rule>
    <rule>Write skill and plugin instructions so future agents can execute the artefact in Codex and Claude without relying on hidden thread state, local shell aliases, current working-directory accidents, or undocumented plugin-cache layout.</rule>
  </policy>

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
    <apply_portable_patterns>
      Implement the change with portable path handling, argument handling, dependency detection, error reporting, and documented configuration. Prefer small explicit compatibility checks over implicit reliance on the current machine.
    </apply_portable_patterns>
    <verify_across_surfaces>
      Run the narrowest useful verification for the touched artefact. Include macOS/Linux or Codex/Claude coverage when available; otherwise report the untested surface and why it could not be exercised in the current session.
    </verify_across_surfaces>
  </workflow>

  <review_checklist>
    <paths_and_locations>Paths resolve from documented roots and support spaces or special characters.</paths_and_locations>
    <shell_portability>Shell syntax, utilities, and flags work on macOS and Linux or are guarded with fallbacks.</shell_portability>
    <language_runtime>Python, Node.js, or other runtime code uses portable standard APIs for filesystem, process, encoding, and temporary-file behavior.</language_runtime>
    <harness_wiring>Skill/plugin prose explains execution and configuration through documented harness behavior rather than current-session implementation details.</harness_wiring>
    <plugin_hook_runtime>A blocking or lifecycle hook shipped inside a plugin is verified to load at runtime on each target harness, with config-layer registration where the harness does not execute plugin-bundled hooks.</plugin_hook_runtime>
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
