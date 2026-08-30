#!/usr/bin/env bash
# plugin_version.sh — shared plugin-meta lockstep assertions for the harnesses.
#
# The standing repo rules require that when a skill or agent version rises, the
# plugin's `.claude-plugin/plugin.json`, its `.codex-plugin/plugin.json`, and
# both marketplace registrations all carry the same plugin version. A harness
# that pins the literal version its own change shipped at goes stale on the next
# routine bump, so these helpers assert the invariant instead: read the version
# from `.claude-plugin/plugin.json` and require the other three to match it.
#
# Usage from a harness at tests/<name>/script_tests/run.sh:
#
#     # shellcheck source=../../lib/plugin_version.sh
#     . "$HERE/../../lib/plugin_version.sh"
#     check_plugin_version_lockstep ai_dev
#
# check_plugin_version_lockstep expects two things from the sourcing harness:
# a `REPO_ROOT` variable, and the usual `check <label> <cmd...>` helper. It
# reports through that `check`, so the harness's own pass and fail tallies and
# its failure list pick the results up with no further wiring.

# plugin_json_version <plugin.json> -> the file's own top-level version.
plugin_json_version() {
  python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["version"])
' "$1" 2>/dev/null
}

# marketplace_plugin_version <marketplace.json> <plugin> -> that one plugin's
# version. A registration lists many plugins, so matching the name matters:
# grepping the file for a version string would match any entry in it.
marketplace_plugin_version() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(next(p["version"] for p in d["plugins"] if p["name"] == sys.argv[2]))
' "$1" "$2" 2>/dev/null
}

# Predicates the `check` helper invokes. They stay shell functions rather than
# `bash -c` bodies so they run in the harness's own shell and can call the two
# readers above.
plugin_version_is() { [[ "$(plugin_json_version "$1")" == "$2" ]]; }
marketplace_version_is() { [[ "$(marketplace_plugin_version "$1" "$2")" == "$3" ]]; }
version_is_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# check_plugin_version_lockstep <plugin> — four checks against the version in
# plugins/<plugin>/.claude-plugin/plugin.json.
check_plugin_version_lockstep() {
  local plugin="$1"
  local version
  version="$(plugin_json_version \
    "$REPO_ROOT/plugins/$plugin/.claude-plugin/plugin.json" || true)"

  # Guard the three comparisons that follow. An unreadable source file yields
  # the empty string, and comparing empty against empty would pass vacuously.
  check "$plugin .claude-plugin version reads as a semver" \
    version_is_semver "$version"
  check "$plugin .codex-plugin matches .claude-plugin ($version)" \
    plugin_version_is "$REPO_ROOT/plugins/$plugin/.codex-plugin/plugin.json" "$version"
  check "marketplace .agents $plugin matches .claude-plugin ($version)" \
    marketplace_version_is "$REPO_ROOT/.agents/plugins/marketplace.json" \
      "$plugin" "$version"
  check "marketplace .claude-plugin $plugin matches .claude-plugin ($version)" \
    marketplace_version_is "$REPO_ROOT/.claude-plugin/marketplace.json" \
      "$plugin" "$version"
}
