---
name: git_commit
description: Create one structured git commit covering the full current working-tree state. Use when the user asks to commit, commit changes, save changes, save work, make a commit, write a commit message, wrap up changes, "commit this", "git commit", or otherwise put the current repo state into git history.
disable-model-invocation: true
version: 3.4.1
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
  <codex_agent_only>
    <scope>Codex agents apply this section. Non-Codex agents ignore this section and follow the primary workflow normally.</scope>
    <sandbox_preflight>When the active Codex environment reports managed filesystem sandboxing and `.git` is readable without write access, invoke the primary workflow scripts with Codex command escalation on their first attempt. Use `sandbox_permissions: "require_escalated"` for `prepare_commit_context.sh` and `commit_with_message.sh` so Git can create `.git/index.lock` without a failed first run.</sandbox_preflight>
    <fallback_boundary>Apply this only from visible Codex sandbox metadata. When `.git` is writable or sandbox metadata is unavailable, follow the primary workflow normally and use fallback handling only after an actual script failure.</fallback_boundary>
  </codex_agent_only>
  <primary_workflow>
    <gather_context>Invoke `scripts/prepare_commit_context.sh`. The script stages every untracked file and writes one structured context blob (status, recent commits, per-file staged/unstaged diffs, binary markers) to a file under the system tmp dir. Its stdout prints exactly two lines: the context file's absolute path, then a one-line consumption directive. Treat that file as the authoritative source for the commit; the path on stdout is the only thing you carry forward.</gather_context>
    <consume_context>
      <full_read>Use the `Read` tool on the path the script printed and read the entire file. This is the default path and works for any normal-sized commit.</full_read>
      <paginated_read>If the file overflows `Read`'s default window, call `Read` again with `offset`/`limit` and continue *in sequence* until every byte is covered. Do not stop after the first page.</paginated_read>
      <slicing_fallback>Only when the file is so large that paginated `Read` is impractical (typically 1000+ file changesets) fall back to `grep`/`awk`/`sed` via Bash. Use them to *chunk* the file into ordered slices and read each slice — not to query for a specific filename. You still need to see every `<file_change>` section in order to write a coherent multi-file message; selective sampling is the original failure mode this skill exists to prevent.</slicing_fallback>
      <hard_rules>Never re-derive the context with `git diff`, `git status`, or `git log` — the script already produced it once and re-deriving wastes tokens and time. Never sample by filename; iterate every `<file_change>` section. Summarize updated files from their diffs, summarize new text files from their full added content, summarize binary files with a generic file-level line.</hard_rules>
    </consume_context>
    <compose_message>Compose the commit message under `<message_policy>` directly in the Bash heredoc you will pass to `scripts/commit_with_message.sh`. Do not write the message to a temporary file first — the script reads it from stdin so there is no intermediate file to manage.</compose_message>
    <execute_commit>Invoke `scripts/commit_with_message.sh CONTEXT_FILE` with the composed message piped in via a single-quoted heredoc, where `CONTEXT_FILE` is the path printed by `prepare_commit_context.sh` (passed so the script can remove it on success). The script stages the full current repo state, runs `git commit -F -` to consume the message from stdin exactly as composed, prints the final status so line breaks stay exact in git history, and removes the context file on success (so it persists for a retry if the commit itself fails). Invocation shape: `/abs/path/to/scripts/commit_with_message.sh /abs/path/to/context.txt <<'COMMIT_MSG_END'` then the message lines then `COMMIT_MSG_END` on its own line. Quote the heredoc delimiter to prevent shell expansion inside the message, and pick a delimiter no message line could begin with.</execute_commit>
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
