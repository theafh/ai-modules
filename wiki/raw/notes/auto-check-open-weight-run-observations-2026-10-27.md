---
ingested: 2026-10-27
sha256: 984c838f31edc971dd6e575d12582843ae93c547a2b18dd04ef912149f3c5ae3
---

# Auto-check runs on open-weight models, observations of 2026-10-27

This note records what a read of local session records and installed builds showed on 2026-10-27, after the maintainer ran `task_auto_check` on 2026-10-26 with DeepSeek models in Cursor and in the OpenCode desktop application. The records are local session stores and application bundles outside the repository, and their content is excerpted below as the authoritative copy. No machine path, session id, or account detail is given.

## Cursor

- **Helper return channel.** Four Cursor runs of the loop spawned helpers through the Task tool. In 11 helper returns the helper's transcript held the complete output contract in an earlier assistant message, and its final assistant message was a short closing note, such as "Decision delivered above." or "The proposal is returned above in the exact output-contract shape." The parent saw only the closing note. It named six of those returns summarized or contract-violating, one of them for pointing at a proposal "above", and retried each with the identical prompt (none in the first run, one in the second, two in the third, three in the fourth, in start order), and every retry whose outcome the transcripts record returned the full contract. It accepted the other five on the closing note's own summary.
- **Compaction trace.** In one run the parent transcript held the original user turn five times, each copy with the same timestamp and the manually attached skill re-inlined, while the maintainer typed it once. The maintainer reported that the session was auto-compacting. Right after the second re-delivery, the parent wrote the returns of five reviewer helpers itself instead of spawning them, then noticed and retracted them.

## OpenCode

- **Variant inheritance in the task tool.** In the installed desktop bundle's task tool, a spawned subagent runs on the agent definition's model when the definition sets one, and otherwise on the parent message's model. The call passes the parent message's variant only in the second case, so a subagent without a model of its own inherits the parent's model and its variant.
- **Agent variant needs a model.** The bundle's configuration loader applies an agent's `variant` only when that agent also has a `model`, and the client's variant resolver ignores an agent variant whose model does not match the selected model or whose name the model does not offer.
- **Recorded inheritance.** The local session database recorded the parent session of the run on variant `max`, and every helper's first user message carried `variant: max` beside the parent's model.
- **Output budget.** Five helper calls on `deepseek/deepseek-v4.1-flash` at variant `max` returned no text. Each one's final assistant message ended with finish reason `length`, 32,000 reasoning tokens, and 0 output tokens, at input contexts between about 60,000 and 250,000 tokens. Helpers on `deepseek/deepseek-v4-pro-0813` in the same session recorded no `length` finish.

## GitHub Copilot in VS Code

- **No per-agent effort key.** The Copilot extension built into Visual Studio Code, version 0.70.0, contributes two reasoning-effort settings and both are global: `github.copilot.chat.claudeDefaultReasoningEffort`, with the values empty, `low`, `medium`, `high`, and `max`, and `github.copilot.chat.reasoningEffortOverride`, described as an advanced debugging setting used by evals. No custom-agent field for effort appears in the extension's contributed configuration.
