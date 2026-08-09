---
title: Isolating OpenCode from foreign harness config
created: 2026-08-09
updated: 2026-08-09
type: procedure
tags: [opencode, claude, antigravity, discovery, portability, skill]
sources: []
confidence: high
---

# Isolating OpenCode from foreign harness config

When OpenCode lists skills nobody installed into it, set the narrowest
`OPENCODE_DISABLE_CLAUDE_CODE*` variable that covers the leak, and deliver it
where the running application can actually see it. On a macOS desktop install
that is the GUI login session, not the shell profile, which is where most
published instructions go wrong.

## When this applies

OpenCode surfaces skills, or applies rules, that were deployed for another
harness. Its discovery reads `~/.claude/skills/`, `.claude/skills/`, and
`.agents/skills/` beside its own, and it resolves rules by first match across
`~/.config/opencode/AGENTS.md` then `~/.claude/CLAUDE.md`, so a Claude or
Antigravity deployment appears inside it unbidden. The full discovery order is on
[SST OpenCode](../entities/sst-opencode.md).

## The rule

Pick the narrowest variable that covers the leak, then place it where the
application reads it.

`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` stops `.claude` skill discovery alone.
`OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1` stops only the `~/.claude/CLAUDE.md`
fallback. `OPENCODE_DISABLE_CLAUDE_CODE=1` is the broad one: it disables Claude
compatibility generally and also stops `.agents/skills` discovery, which is
Antigravity's native root rather than a Claude deposit. Reach for the broad
variable only when a narrow one leaves something behind, and copy the global
rules to `~/.config/opencode/AGENTS.md` before you do, because it removes the
`~/.claude/CLAUDE.md` fallback along with everything else.

Then apply the variable in three escalating placements, stopping at the one that
matches how long the change should last.

1. **Prove it works while persisting nothing.** Launch a single instance with the
   variable set and inspect the skill list inside the application before going
   further.

   ```bash
   open --env OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 -a OpenCode
   ```

2. **Set it for the current login session.** This puts the variable in the GUI
   session environment, so an ordinary Dock or Spotlight launch picks it up. It
   survives quitting and relaunching the application, and it is wiped at logout
   or reboot.

   ```bash
   launchctl setenv OPENCODE_DISABLE_CLAUDE_CODE_SKILLS 1
   ```

3. **Make it survive a reboot.** Write a login agent at
   `~/Library/LaunchAgents/<label>.plist` whose `ProgramArguments` run
   `/bin/launchctl setenv <VARIABLE> 1`, with `RunAtLoad` set true. Validate it
   with `plutil -lint`, bootstrap it into the GUI session, and confirm after the
   next login that `launchctl getenv <VARIABLE>` returns `1`.

Prove step 3 rather than assuming it: clear the variable, fire the agent the way
login does, and watch it come back. Remove the agent later with
`launchctl bootout gui/$(id -u)/<label>` followed by deleting the plist.

## Pitfalls

**A shell profile export does nothing for a desktop install.** An application
launched from Finder, the Dock, or Spotlight inherits launchd's environment
rather than the shell's, so an `export` in `~/.zshrc` never reaches it. This is
the most common wrong instruction in circulation, because published guidance
assumes a CLI install. Check whether the machine has an application bundle or a
binary on `PATH` before following any guide.

**Leave the application bundle's `Info.plist` alone.** It already carries an
`LSEnvironment` dictionary, which makes it look like the natural home. Editing it
invalidates the code signature, and the auto-updater overwrites the edit on the
next release. A login agent survives updates.

**Two variables circulate that nothing authoritative supports.**
`OPENCODE_DISABLE_EXTERNAL_SKILLS` and `OPENCODE_PURE` appear in source-derived
secondary material and in neither the documentation nor the issue tracker. Test
before trusting either.

**A login agent races an auto-launched application.** An application set to open
at login can start before the agent sets the variable. A manual launch always
happens after.

**A working agent of this kind reports `state = not running`.** Inspecting it
with `launchctl print gui/$(id -u)/<label>` shows `state = not running` beside
`state = active` and `properties = runatload`, which reads like a failure and is
not one. The job runs `launchctl setenv` once at login and exits, so active plus
runatload means registered and already fired. Verify the effect rather than the
process: `launchctl getenv <VARIABLE>` returning `1` is the check that matters.

## See Also

- [SST OpenCode](../entities/sst-opencode.md) for the discovery order and the
  version boundary on each variable.
- [Foreign directory adoption](../concepts/foreign-directory-adoption.md) for why
  isolation is the standing position rather than a workaround.
- [Isolating VS Code from foreign harness config](isolating-vs-code-from-foreign-config.md)
  and [Isolating Cursor from foreign harness config](isolating-cursor-from-foreign-config.md)
  for the sibling harnesses.
