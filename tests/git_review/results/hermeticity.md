# git_review suite hermeticity runs

Recorded 2026-10-31 on a working tree carrying the suite-entry clear of
`GIT_CONFIG_PARAMETERS` and the `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_*` /
`GIT_CONFIG_VALUE_*` block, scenario s35, and `git config core.quotepath true`
in the scratch repo of every scenario that asserts a quoted non-ASCII path.

| Command | Result |
| --- | --- |
| `bash tests/git_review/script_tests/run.sh` | 40 scenarios — 40 pass, 0 fail |
| `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false bash tests/git_review/script_tests/run.sh` | 40 scenarios — 40 pass, 0 fail |
| `GIT_CONFIG_GLOBAL=<file> bash tests/git_review/script_tests/run.sh` | 40 scenarios — 40 pass, 0 fail |
| `GIT_CONFIG_PARAMETERS="'core.quotepath'='false'" bash tests/git_review/script_tests/run.sh` | 40 scenarios — 40 pass, 0 fail |

The second run exports the inverted `core.quotePath` value the Cursor sandbox
and some operator profiles set. With the suite-entry clear removed, the same
command reports 34 pass and 6 fail (s22, s25, s30, s31, s32, s35), so the new
scenario flips with the pin rather than with the ambient setting.

The third run's `<file>` includes the operator's `~/.gitconfig` and adds
`core.quotePath = false`, the state `git config --global core.quotePath false`
leaves. The suite-entry clear does not reach that file, so the scratch-repo
setting is what keeps the quoted form; before s22 and s35 carried it, this run
reported 38 pass and 2 fail (s22, s35).

The fourth run carries the inverted value the way `git -c` hands it to child
processes. Before the clear named `GIT_CONFIG_PARAMETERS`, it reported 34 pass
and 6 fail (s22, s25, s30, s31, s32, s35).
