---
ingested: 2026-10-09
sha256: dc0bd41384b1260292e0fbb38bdedccc2d6e8f9039970e27b12631bef0b294c9
---

# Cursor print-mode shell probes, 2026-10-09

This note records two print-mode probes run on 2026-10-09 that asked how the agent CLI's shell tool builds the environment a command runs in, and which `bash` that environment resolves when the worker's `HOME` is a scratch home. The record is a local capture outside the repository, and its content is excerpted below as the authoritative copy. No machine path, scratch path, or session id from the probes is given.

Both probes ran the `agent` CLI 2026.10.01 in print mode with `--force`, `--sandbox disabled`, `--model auto`, and `--output-format stream-json`. `HOME` named a scratch home whose `Library` linked to the real one, and a scratch project was the workspace. The prompt asked the worker to run one command through its shell tool and return the output verbatim. The command printed `$0`, whether the shell's `login` option was set, `command -v bash`, the version of that `bash`, the first four `PATH` entries, and the command line of the shell process itself.

## Facts

- **Command wrapper.** The shell process was `/bin/zsh -c` running a wrapper. The wrapper first ran `builtin export PATH="/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"`, then read a saved shell-state snapshot with `snap=$(command cat <&3)`, removed aliases, and evaluated the snapshot with `builtin eval "$snap"`. Only then did it evaluate the requested command, and afterwards it wrote the shell state to file descriptor 4.
- **Login state.** Inside that wrapper `$0` printed `--`, and `[[ -o login ]]` reported a login shell.
- **Scratch home without a profile.** With only the `Library` link in the scratch home, `bash` resolved to `/bin/bash`, version 3.2.57. `PATH` began `/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin`, the order that macOS's `/etc/zprofile` produces through `path_helper` when no user profile adds to it.
- **Scratch home with a profile.** The second probe added a `.zprofile` to the scratch home that exports `PATH` from a variable the worker inherited, set to the worker's launch `PATH`. `bash` then resolved to the package-manager build that the launch `PATH` puts ahead of the stock one, and `PATH` began with the launch `PATH`'s own first entries.
- **Shells outside the agent, for comparison.** On the same workstation a login `zsh -l` with the real home resolved the package-manager bash, and the same login shell with an empty scratch home resolved `/bin/bash`. A non-login `zsh -c` with the empty scratch home resolved the package-manager bash, because it keeps the inherited `PATH` and runs no `path_helper`.

## Consequence

On the print-mode CLI, the environment a shell command sees comes from a login shell started under the worker's `HOME`. A scratch home that lacks the operator's login profile therefore changes which interpreter a bundled script gets: a script that fails on the stock bash 3.2 fails there, while the same command succeeds in the operator's terminal. A login profile in the scratch home that restores the launch `PATH` removes the difference.
