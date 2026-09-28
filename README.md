# AI Devcontainer

A generic development container for Claude Code and Codex CLI. Each named
environment profile gets its own container, its own checkouts, and its own
container tools; agent logins, settings, plugins and shell history live in
named state profiles that survive rebuilds and can be shared between
environment profiles. VS Code is the only entry point: you work in the VS
Code terminal inside the container.

See `docs/domain/glossary.md` for the terms this document uses, and
`docs/specs/2026-09-28-ai-devcontainer-v2-design.md` for the full design.

## Prerequisites

On the host:

- Docker (Engine or Desktop), running.
- `flock` (part of `util-linux`; present on essentially every Linux and WSL
  host already).
- [mise](https://mise.jdx.dev/) 2026.9.15 or newer. The root `mise.toml`
  pins the host tools it installs: the Dev Containers CLI, `jq`, `bats`,
  `shellcheck` and `shfmt`. Run `mise install` once after cloning.
- VS Code with the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
  extension.
- A running host `ssh-agent` with `SSH_AUTH_SOCK` exported in the shell VS
  Code starts from. VS Code forwards this agent into the container; no
  private key is ever copied in.

### A host `ssh-agent` on WSL

WSL does not start an `ssh-agent` for you. A systemd user unit that starts
one and keeps it running works well:

```ini
# ~/.config/systemd/user/ssh-agent.service
[Unit]
Description=SSH agent

[Service]
Type=simple
ExecStart=/usr/bin/ssh-agent -D -a %t/ssh-agent.socket

[Install]
WantedBy=default.target
```

```
systemctl --user enable --now ssh-agent.service
```

Export the socket from your login shell (e.g. `~/.zshrc` or `~/.bashrc`),
so every terminal and VS Code itself pick it up:

```sh
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
```

Add your keys with `ssh-add`. Optionally set `AddKeysToAgent yes` in
`~/.ssh/config` so `ssh` adds a key to the agent the first time it is used,
instead of asking every time.

## Host tasks

Run these from the repository root with `mise run <task>`:

- `profile:new <name>` — creates `profiles/<name>/profile.env` from the
  fictional example, and `projects/<name>/` for that profile's checkouts.
  Edit `profile.env` before the first `profile:code`.
- `profile:code [name]` — makes `<name>` the active profile (or reuses the
  active profile when no name is given), generates `.local/<name>/`, starts
  the container, and opens VS Code on it. Because a `vscode-remote://`
  dev-container folder URI resolves its host path as a Windows path under
  WSL and fails to attach (verified 2026-09-28), `profile:code` opens the
  plain folder instead and asks you to choose **"Reopen in Container"**,
  which attaches to the container it just started.
- `profile:remove <name>` — removes the container, `.local/<name>/` and the
  profile's tools volume. It keeps `projects/<name>/`, `profiles/<name>/`
  and every state volume (Claude, Codex, shell history), so a login and a
  checkout both survive.

`profile:rebuild` does not exist: VS Code's own "Rebuild Container" reads
the same generated files and is the documented way to pick up a
`profile.env` or image change (see the manual checklist for whether this
holds up in practice).

## Container tasks

Inside the container's VS Code terminal, run the container tasks with:

```sh
MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:<task>
```

`-C /` selects a neutral directory before any project configuration loads,
and disabling task auto-install keeps a project from installing anything
before the task runs; both are needed together (verified 2026-09-28) — a
plain `mise run aidc:<task>` from inside an untrusted project can silently
trust it and run its own task of the same name instead.

- `aidc:sync` — copies the current `.devcontainer/mise.toml` into the
  profile's tools volume, locks it and installs it.
- `aidc:update` — as `aidc:sync`, then upgrades every tool to its newest
  allowed version.
- `aidc:status` — reports the last start's result, the container tools
  (installed or missing) and, per agent, whether plugin initialization
  completed. Reads files only, so it works with the container offline.

## Isolation and the Docker socket

The container itself is the isolation boundary: Claude Code's own sandbox
stays off, and Codex runs with `sandbox_mode = "danger-full-access"` and
`approval_policy = "on-request"` from the container's own configuration
(Docker's default seccomp and AppArmor profiles stay in place around it). A
different Codex sandbox mode set in your own configuration is your choice.

Consequence: an agent command can change every project checkout of the
profile and its state volumes, and can use the forwarded SSH agent and the
network. A state volume shared between profiles carries an agent's changes
to every profile that shares it.

**Docker socket warning.** `DOCKER_SOCKET=on` in `profile.env` bind-mounts
the host's Docker socket into the container and adds its group so the
container user can use it. With the socket on, the container is no longer
the isolation boundary: an agent command inside it can control every
container on the host, not just this one. Leave it `off` unless you need
it.

## Git identity and known cases

- Set `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME` and
  `GIT_COMMITTER_EMAIL` in `profile.env` to set the Git identity used inside
  that profile's container; unset fields use whatever the copied Git
  configuration already has.
- **A host `core.sshCommand` blocks the agent.** If the Git configuration
  VS Code copies into the container sets `core.sshCommand` (for example to
  a Windows OpenSSH path), Git uses that instead of the forwarded
  `ssh-agent` and authentication fails. Fix it by setting
  `GIT_SSH_COMMAND=ssh` in `profile.env`; Git prefers the environment
  variable over `core.sshCommand` (verified with Git 2.43.0).
- **One server, several accounts.** When one Git host holds several of your
  accounts, the ssh-agent offers all your keys and the server accepts the
  first one it is willing to use — so the account tied to that key is the
  one Git authenticates as, regardless of which account you intended. There
  is no per-account key selection; pick a state profile per account if this
  matters, or restrict which key the agent offers for that host.

## CLI versions and plugin updates

Both `claude` and `codex` are installed at whatever `latest` resolves to
when the tools volume is first populated (the CLI self-update is off in
both, so this only moves through `aidc:sync`/`aidc:update`). This is an
accepted risk for the `codex` launcher: it recognises commands and options
through tables in `.devcontainer/lib/codex-cli.sh`, verified against Codex
0.157's `--help` output. A materially newer Codex may add a command or
option the tables miss, which could make the launcher fail to add
`--no-daemon` or fail to refuse a command that needs the managed daemon.
**When `.devcontainer/mise.toml` moves the Codex pin to a newer minor
version, re-check the tables in `.devcontainer/lib/codex-cli.sh` against
that version's `codex --help` (and `codex resume --help`, `codex fork
--help`, `codex app-server --help`) before relying on it.** Pinning an
older Codex version instead of `latest` is your choice.

Plugin updates follow each CLI's own default behaviour; nothing here forces
them on or off. Codex refreshes its marketplace clones at session start on
its own. Whether Claude Code's plugin auto-update runs under the
`DISABLE_UPDATES` self-update policy is left to Claude; either way, the
native `plugin`/`marketplace` commands update plugins by hand at any time.
A plugin version change that must not reach an existing agent state profile
calls for a separate one — nothing here updates a state profile's plugins
automatically or on its own initiative.

## Further reading

- `docs/verification/acceptance-matrix.md` — which test or checklist item
  covers each acceptance criterion, and every probe's result.
- `docs/verification/manual-checklist.md` — the items that still need VS
  Code or a real agent login.
