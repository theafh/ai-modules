---
ingested: 2026-10-09
sha256: 117cb416f5807c7c637101094f16bc45a554b80ed285c21be92f2cede1c711ac
---

# Cursor helper transcript probes, 2026-10-09

This note records two print-mode probes run on 2026-10-09 that asked where a spawned helper's own tool calls land. The record is a set of local stream and transcript captures outside the repository, and their content is excerpted below as the authoritative copy. No machine path, scratch path, or session id from the probes is given.

Both probes ran the `agent` CLI 2026.10.01 in print mode with `--force`, `--sandbox disabled`, `--model auto`, and `--output-format stream-json`. `HOME` named a scratch home whose `Library` linked to the real one, and a scratch project was the workspace. A fixture role staged in the project's `.cursor/agents/` was asked to read two files and report their first lines: one inside the project, and one artefact-shaped `SKILL.md` under a `.cursor/skills/` directory outside both the project and the scratch home. The parent's prompt named that role and told the parent not to read either file itself.

## Facts

- **Parent stream.** The spawn appeared as a `getMcpToolsToolCall` that looked up `Task`, followed by a `taskToolCall`. Its completed `result.success` held `conversationSteps` (the helper's final text only), `agentId`, `isBackground`, `durationMs`, and `backgroundReason`. The helper's own `Read` calls did not appear in the stream.
- **Tool-call record keys.** Each `tool_call` object carried `toolCallId`, `startedAtMs`, and `hookAdditionalContexts` beside the key that names the tool kind, plus `completedAtMs` on completion.
- **Transcript location.** Under the scratch home the CLI wrote one JSONL transcript per chat, the parent's and the helper's alike, at `.cursor/projects/<workspace-slug>/agent-transcripts/<chat-id>/<chat-id>.jsonl`. The parent's chat id matched the stream's `session_id`, and the helper's matched the `agentId` in the `Task` result. No `subagents/` folder was written.
- **Transcript lines.** Each line held `role` and `message.content`. An assistant line's `tool_use` blocks named the tool and its input. The helper's transcript held two `Read` blocks with `path` and `limit`, and the parent's held the spawn as `GetDynamicTools` and `CallDynamicTool` with `toolName: Task` and the call's arguments. Each transcript ended in a `{"type": "turn_ended", "status": "success"}` record and held no tool results.
- **Other home state.** The same scratch home gained `.cursor/cli-config.json`, `.cursor/agent-cli-state.json`, `.cursor/statsig-cache.json`, a `store.db` and `meta.json` per chat under `.cursor/chats/<hash>/<chat-id>/`, and the CLI's built-in skills synced to `.cursor/skills-cursor/<name>/SKILL.md`.
- **Read check over the transcripts.** The second probe ran the same setup through the eval harness's run helper, which on Cursor also reads the chat transcripts under the scratch home. Its read list held both of the helper's reads, and the read check failed on the `SKILL.md` outside the deployment.

## Consequence

On Cursor a helper's reads are recoverable from its chat transcript under the worker's home directory and from nowhere in the parent's stream, so a read check that follows the stream alone misses them. Reading every transcript under a per-pass scratch home covers the parent and each helper it spawned.
