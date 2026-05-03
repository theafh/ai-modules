---
name: git_commit
description: git_commit
disable-model-invocation: true
version: 3.1.0
author: Andreas F. Hoffmann
license: MIT
---
# git_commit

<git_commit_skill>
  <objective>Stage all new files and create one commit for the intended repo state.</objective>
  <command_intent>git add all new files and then git commit all changed files</command_intent>
  <tools>
    <prepare_commit_context>Run `scripts/prepare_commit_context.sh` from this skill when it is available. The script stages untracked files, then emits one structured context blob with git status, recent commits, staged per-file diffs, unstaged per-file diffs, and generic markers for binary files.</prepare_commit_context>
    <commit_with_message>After writing the commit message, write it to a temporary message file and run `scripts/commit_with_message.sh MESSAGE_FILE` when it is available. The script stages the full current repository state, commits with `git commit -F`, and prints final status so line breaks stay exact in git history.</commit_with_message>
  </tools>
  <policy>
    <commit_scope>Stage every new file in the repo and create one commit for the full current repo state, including pre-existing staged changes and pre-existing unstaged changes, unless the user explicitly narrows the scope.</commit_scope>
    <commit_message_multi_file>For multi-file commits, write one concise sentence summarizing what all changes are about, then list one line per changed file in the format `file name -> concrete change`.</commit_message_multi_file>
    <commit_message_single_file>For single-file commits, write one concise line in the format `file name -> concrete change`.</commit_message_single_file>
    <file_line_quality>Use each file-level summary to name the specific behavior, content, or intent that changed so the line stays understandable on its own while remaining brief.</file_line_quality>
    <model_authority>The model remains the commit driver: read the complete context blob, infer the shared intent, and write the final message. Use script output as evidence and execution support, not as a substitute for review.</model_authority>
    <workflow_authority>Treat this skill as the source of truth for `/git_commit` workflow, commit scope, and commit-message guidance.</workflow_authority>
    <execution_default>Proceed without scope-confirmation prompts about dirty worktrees or pre-existing staged changes.</execution_default>
    <pause_conditions>Pause only for hard blockers that prevent a valid commit, such as command failure, hook failure, or an explicit user instruction that narrows the scope.</pause_conditions>
  </policy>
  <steps>
    <step>Run `scripts/prepare_commit_context.sh` to gather the full commit context in one command. If the script is unavailable, run the equivalent manual workflow: stage new files, inspect git status, inspect recent commits, run git diff between current state and last commit for every tracked file, and review the full content of every new file.</step>
    <step>Read every `<file_change>` section before composing the message. Summarize updated files from their diffs, summarize new text files from their full added content, and summarize binary files with a generic file-level line.</step>
    <step>Write the commit message according to the single-file or multi-file policy.</step>
    <step>Commit with `scripts/commit_with_message.sh MESSAGE_FILE` when available, or run `git add -A` followed by `git commit -F MESSAGE_FILE` manually. Verify the final git status after the commit completes.</step>
  </steps>
</git_commit_skill>
