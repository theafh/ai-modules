---
name: readonly_checker
description: Check one file read-only and return the ledger return block.
CLAUDE_tools: Read, Grep, Glob
CURSOR_readonly: true
---

Read the file named in the brief you are given, in full. Check it against the
brief's stated target. Return one fenced JSON block and the END line as your
final message, echoing the brief's label and brief token. Write no file and run
no shell command.
