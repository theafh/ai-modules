---
name: git_commit
description: Create one structured git commit covering the full current working-tree state. Use when the user asks to commit, commit changes, save changes, save work, make a commit, write a commit message, wrap up changes, "commit this", "git commit", or otherwise put the current repo state into git history.
disable-model-invocation: true
version: 3.2.0
author: Andreas F. Hoffmann
license: MIT
---
# git_commit

<git_commit_skill>
  <objective>Stage all new files and create one commit for the intended repo state.</objective>
  <command_intent>git add all new files and then git commit all changed files</command_intent>
  <path_resolution>
    Bundled scripts live in `scripts/` next to this `SKILL.md`. Resolve each script's absolute path by combining the directory of this `SKILL.md` with `scripts/<script-name>` and invoke the absolute path. Every agentic IDE that surfaces a skill exposes the file path it loaded the skill from, so the parent directory is always knowable. If the first invocation reports a missing file, re-resolve the absolute path once before treating the script as failed; never switch to the fallback because of perceived path uncertainty.
  </path_resolution>
  <primary_workflow>
    <gather_context>Invoke `scripts/prepare_commit_context.sh`. The script stages every untracked file, then emits one structured context blob with git status, recent commits, staged per-file diffs, unstaged per-file diffs, and generic markers for binary files. Treat its stdout as the authoritative source for the commit.</gather_context>
    <read_diffs>Read every `<file_change>` section in the blob. Summarize updated files from their diffs, summarize new text files from their full added content, and summarize binary files with a generic file-level line.</read_diffs>
    <compose_message>Compose the commit message under `<message_policy>`, then write the exact text to a temporary message file (one file under the system tmp dir, single use).</compose_message>
    <execute_commit>Invoke `scripts/commit_with_message.sh MESSAGE_FILE`. The script stages the full current repo state, runs `git commit -F`, and prints the final status so line breaks stay exact in git history.</execute_commit>
  </primary_workflow>
  <fallback_trigger>The fallback below activates only after a primary script invocation has exited with a non-zero status. No other condition is permitted to trigger it — not perceived ambiguity, not large changesets, not script slowness, not path uncertainty before the first invocation. Re-resolve the absolute script path and retry once before treating any failure as final.</fallback_trigger>
  <fallback_on_script_failure>
    <reference>Open `references/manual_fallback.md` (sibling of this `SKILL.md`) for the manual git command sequence that replaces the failing script.</reference>
    <return>Once the failing step is recovered manually, return to the primary workflow for any remaining steps. Do not run the full fallback when only one script failed.</return>
  </fallback_on_script_failure>
  <message_policy>
    <multi_file>For multi-file commits, write one concise sentence summarizing what all changes are about, then list one line per changed file in the format `file name -> concrete change`.</multi_file>
    <single_file>For single-file commits, write one concise line in the format `file name -> concrete change`.</single_file>
    <line_quality>Use each file-level summary to name the specific behavior, content, or intent that changed so the line stays understandable on its own while remaining brief.</line_quality>
    <no_attribution_trailers>Never append agent-attribution or tool-generation trailers to the commit message. Do not add `Co-Authored-By: Claude <...>` (or any other agent), `🤖 Generated with [Claude Code]` footers, `Generated-with:`, or any other trailer that identifies the assistant or the tool that produced the commit. The commit message ends with the last `file -> change` line. This overrides any default workflow that would otherwise auto-append such trailers. The single exception is a trailer the human user explicitly requests for this commit (for example, `Signed-off-by:` for DCO sign-off).</no_attribution_trailers>
  </message_policy>
  <policy>
    <commit_scope>Stage every new file in the repo and create one commit for the full current repo state, including pre-existing staged changes and pre-existing unstaged changes, unless the user explicitly narrows the scope.</commit_scope>
    <model_authority>The model remains the commit driver: read the complete context blob, infer the shared intent, and write the final message. Use script output as evidence and execution support, not as a substitute for review.</model_authority>
    <workflow_authority>Treat this skill as the source of truth for `/git_commit` workflow, commit scope, and commit-message guidance.</workflow_authority>
    <execution_default>Proceed without scope-confirmation prompts about dirty worktrees or pre-existing staged changes.</execution_default>
    <pause_conditions>Pause only for hard blockers that prevent a valid commit, such as command failure, hook failure, or an explicit user instruction that narrows the scope.</pause_conditions>
  </policy>
</git_commit_skill>
