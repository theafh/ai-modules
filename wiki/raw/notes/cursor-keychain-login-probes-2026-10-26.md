---
ingested: 2026-10-27
sha256: 1872a2701b178a3a57b72621e24e85f89c5623d3ef70ca4d9c5c44243d106c04
---

# Cursor keychain login probes, 2026-10-26

This note records what the Cursor CLI needs from a scratch `HOME` to reuse a
stored login, measured on 2026-10-26 and re-measured on 2026-10-27. The record
is a set of local probe captures outside the repository, and their content is
excerpted below as the authoritative copy. No machine path, scratch path, or
session id from the probes is given.

Cursor ran as the `agent` CLI in print mode. The scratch home in each probe sat
in the system temporary directory, outside the home directory and outside any
git repository.

## Facts

- **Credential store.** The CLI stores its credentials in the macOS login
  keychain, under account `cursor-user` and services such as
  `cursor-access-token`, and it reads them through `/usr/bin/security`.
- **Empty scratch home.** With `HOME` naming an empty directory,
  `security find-generic-password -a cursor-user -s cursor-access-token`
  exited 44 and `agent status` reported "Not logged in".
- **Scratch home with `Library/Keychains` linked.** With `HOME` naming a
  directory whose `Library/Keychains` links to the real one, both the
  `security` lookup and `agent status` succeeded.
- **Other `Library` reads.** The CLI also looks for
  `Library/Application Support/Cursor/AgentStores`, falling back to a
  temporary store when it is absent, and for IDE workspace storage under
  `Library/Application Support/Cursor/User`, which is optional state. Neither
  read is needed for login, per the CLI bundle's code.
- **Live micro-deployment measurement, 2026-10-27.** A
  `micro_deploy("cursor", [], <temporary project>, bin_name="agent",
  preflight=True)` call returned a live handle, so its preflight probe passed.
  With `HOME` set to that
  handle's scratch home, one `agent status` run exited 0 and printed
  `✓ Logged in as <account>`. While the handle was still open, its `Library`
  was a real directory and not a symlink, and its `Keychains` entry was a
  symlink resolving to the real `~/Library/Keychains`. The `agent status` run created a `Caches` directory
  of its own inside that scratch `Library`; no other entry appeared, and no
  link reached an app-state tree. Closing the handle removed the scratch tree.
- **Fail branch not taken.** Neither check failed, so no extra top-level
  `Library` link was enrolled beyond `Keychains`.

## Consequence

A scratch `HOME` whose `Library` is a real directory holding one `Keychains`
symlink to the real one authenticates the Cursor CLI, and that single link is
enough: linking the whole `Library` is not required. Keeping `Library` a real
directory with only that entry leaves a worker's own file searches unable to
walk into other apps' state under the real `Library`.
