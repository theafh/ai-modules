---
name: git_commit
description: git_commit
disable-model-invocation: true
version: 3.0.0
author: Andreas F. Hoffmann
license: MIT
---
# git_commit

<git_commit_skill>
  <objective>Stage all new files and create one commit for the intended repo state.</objective>
  <command_intent>git add all new files and then git commit all changed files</command_intent>
  <policy>
    <commit_scope>Stage every new file in the repo and create one commit for the full current repo state, including pre-existing staged changes and pre-existing unstaged changes, unless the user explicitly narrows the scope.</commit_scope>
    <commit_message_multi_file>For multi-file commits, write one concise sentence summarizing what all changes are about, then list one line per changed file in the format `file name -> concrete change`.</commit_message_multi_file>
    <commit_message_single_file>For single-file commits, write one concise line in the format `file name -> concrete change`.</commit_message_single_file>
    <file_line_quality>Use each file-level summary to name the specific behavior, content, or intent that changed so the line stays understandable on its own while remaining brief.</file_line_quality>
    <workflow_authority>Treat this skill as the source of truth for `/git_commit` workflow, commit scope, and commit-message guidance.</workflow_authority>
    <execution_default>Proceed without scope-confirmation prompts about dirty worktrees or pre-existing staged changes.</execution_default>
    <pause_conditions>Pause only for hard blockers that prevent a valid commit, such as command failure, hook failure, or an explicit user instruction that narrows the scope.</pause_conditions>
  </policy>
  <steps>
    <step>Run git diff between current state and last commit for every tracked file you are about to commit before composing the message.</step>
    <step>Review the full content of every new file you are about to commit and summarize it as a new addition.</step>
  </steps>
</git_commit_skill>
