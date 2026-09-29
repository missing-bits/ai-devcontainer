---
ticket: none
date: 2026-09-28
---

# Manual verification checklist

These items need VS Code, a real agent login, or two containers running at
once, so no automated test covers them; `mise` does not run this checklist.
Items 1–9 are the technical design's §7 manual smoke checklist
(`docs/technical-designs/ai-devcontainer-v2-technical-design.md`); the two
items after them are the spec's open verification items that have no test
of their own. Run all of it against a profile started with `profile:code`.

## 1. Project mise activation works in the VS Code terminal

**Command:** in the VS Code terminal, `cd` into a checkout under
`/workspaces/<p>/` that has its own `mise.toml` declaring a tool (a project
runtime, not `claude` or `codex`); run `mise install` if prompted, then
`mise ls` or exercise the tool it declares.

**Expected:** mise activates for that directory and installs/exposes the
project's own runtime, without changing which `claude`/`codex` the
launchers resolve.

## 2. `command -v claude codex` shows the launchers first, also inside a project

**Command:** `command -v claude codex` from the home directory, then again
after `cd` into a project whose own `mise.toml` declares a `claude` or
`codex` tool. Also run `zsh -lic 'command -v claude codex'`: a login,
interactive shell whose single `-c` command draws no prompt and changes no
directory, so it never fires the `precmd`/`chpwd` hooks that otherwise
restore the launcher directory's place on PATH.

**Expected:** both resolve to `/usr/local/lib/aidc/launchers/claude` and
`/usr/local/lib/aidc/launchers/codex` in both locations, including the
`zsh -lic` run.

## 3. History persists across a rebuild and two shells share it

**Command:** in one terminal, run a uniquely-named command (e.g.
`echo aidc-history-check-1`); in a second terminal opened at the same time,
run `history | grep aidc-history-check-1`; then use VS Code's "Rebuild
Container", open a new terminal, and repeat the `history | grep` there.

**Expected:** the second shell sees the first shell's command right away
(`SHARE_HISTORY`), and it is still there after the rebuild (the shell
history state profile's volume is kept).

## 4. The default plugins' skills load in Claude Code and in Codex

**Command:** start `claude` and use a skill or command that one of its
default plugins provides (superpowers, elements-of-style, working-process,
project-memory); separately, start `codex` and use a skill or command from
one of its defaults (superpowers, elements-of-style).

**Expected:** both CLIs offer and run the default plugins' skills without
further setup.

## 5. `git push` over SSH works through the forwarded agent

**Command:** from a checkout under `/workspaces/<p>/` with a real SSH
remote, run `git push`.

**Expected:** the push succeeds, authenticated through the host's forwarded
`ssh-agent`; no private key file exists in the container (also checked
automatically — see the acceptance matrix, AC12).

## 6. VS Code "Rebuild Container" keeps tools, state and history

**Command:** note `claude --version`, `codex --version`, current agent
logins, and a marker in shell history; use "Rebuild Container"; check all
four again.

**Expected:** unchanged tool versions (unless `aidc:sync`/`aidc:update` ran
in between), unchanged logins, and the same shell history.

## 7. Two containers share one Claude and one Codex state profile at once

**Command:** set the same `PROFILE_CLAUDE` and `PROFILE_CODEX` value in two
profiles' `profile.env` files, `profile:code` both, and run interactive
`claude` and `codex` sessions in both containers at the same time — log in
from one, use the session from the other, change a setting from one and
read it from the other.

**Expected:** both sessions authenticate with the shared login, and a
setting or plugin change made in one session is visible from the other.
This is the one requirement no automated test exercises with a real,
concurrent agent session: the Docker integration suite only proves that the
two containers mount the identical volumes and that a file written by one
is immediately visible from the other (see the acceptance matrix, AC7),
which is the filesystem precondition this item still has to confirm under
real concurrent use. See also item 10 below and probe P7.3.

## 8. A login survives a rebuild and `profile:remove` followed by `profile:code`

**Command:** log in to `claude` and `codex` in a profile; use "Rebuild
Container"; then run `profile:remove <p>` followed by `profile:code <p>`.

**Expected:** both logins are still active after the rebuild and after the
remove-then-recreate cycle, with no re-authentication needed. The Docker
integration suite proves this with a plain marker file in place of a real
login (see the acceptance matrix, AC7); this item confirms it with the real
thing.

## 9. With the container on no network, VS Code still attaches (AC10)

**Command:** start a profile's container for the first time with the host
or the container's network unavailable; open it in VS Code.

**Expected:** VS Code attaches to the running container despite failed
tool and plugin initialization, and `aidc:status` run inside it reports the
tools, the plugins and the failed initialization. The Docker integration
suite covers the same behaviour at the container level (see the acceptance
matrix, AC10); this item confirms VS Code itself still attaches.

## 10. Whether VS Code "Rebuild Container" makes `profile:rebuild` unnecessary

Spec open verification item; TD §8. No automated test exists, and none of
Tasks 1–7 implemented `profile:rebuild` — it stays a possible future host
task, not a current one. Decide by exercising item 6 above across several
kinds of change (an image change, a change to the shared
`.devcontainer/compose.yaml`) and confirming "Rebuild Container" alone always
picks them up. A `.devcontainer/mise.toml` change is out of scope here: a
start keeps the existing tools config copy, so it needs `aidc:sync` or
`aidc:update` (TD §3.9). Corresponds to
probe P7.2, which was not run (needs VS Code driving a running profile).

A `profile.env` edit is settled by the code, not by this item: "Rebuild
Container" reads the generated `.local/<p>/` files and never re-reads
`profile.env`, so the edit needs `profile:code <p>` first. What remains to
check is whether `profile:code` alone applies the edit to an already running
container, or whether "Rebuild Container" must follow it; the integration
suite stubs `devcontainer`, so it cannot tell.

## 11. Concurrent use of one Claude and one Codex state profile from two containers

Spec open verification item ("Profiles", "Agent state and login"). No
automated test exercises two live agent sessions writing to a shared state
profile at once; item 7 above is this checklist's coverage of it.
Corresponds to probe P7.3, which was not run as a real two-CLI-session
probe (needs interactive `claude`/`codex` logins) — only its filesystem
precondition was verified in Docker (see the acceptance matrix, AC7).
