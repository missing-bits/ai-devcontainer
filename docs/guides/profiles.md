---
ticket: none
date: 2026-09-29
---

# Profiles

An environment profile is a named working environment: its configuration in
`profiles/<name>/profile.env`, its checkouts in `projects/<name>/`, its own
container and its own container tools. `profiles/`, `projects/` and
`.local/` stay out of Git.

## Host tasks

Run these from the repository root with `mise run <task>`:

- `profile:new <name>` creates `profiles/<name>/profile.env` from
  `examples/profile/profile.env`, and an empty `projects/<name>/`. Edit
  `profile.env` before the first `profile:code`.
- `profile:code [name]` generates the container configuration in
  `.local/<name>/` from `profile.env`, starts the container, and opens VS
  Code inside it at `/workspaces/<name>`, where `projects/<name>/` is
  mounted. It makes `<name>` the active profile; without a name it uses the
  active profile.
- `profile:remove <name>` removes the container, `.local/<name>/` and the
  profile's tools volume. It keeps `projects/<name>/`, `profiles/<name>/`,
  every state volume and the shared mise downloads volume, so logins and
  checkouts survive.

## `profile.env`

| Field | Meaning |
| --- | --- |
| `PROFILE_CLAUDE`, `PROFILE_CODEX` | agent state profile: logins, settings, plugins, sessions |
| `PROFILE_SHELL` | shell history profile |
| `DOCKER_SOCKET` | `on` or `off`; see [Security](security.md) first |
| `START_UPDATE_MISE` | `on` (default) or `off`: update mise at every online start |
| `START_UPGRADE_TOOLS` | `on` (default) or `off`: run `aidc:update` at every online start |
| `KEEP_RUNNING` | `on` (default) or `off`: keep the container running after VS Code closes |
| `GIT_AUTHOR_*`, `GIT_COMMITTER_*` | Git identity inside the container |
| `GIT_SSH_COMMAND` | SSH command Git uses; see below |

An empty state field takes the environment profile's name. Profiles that
name the same state profile share it. For example, to use one Claude login
in two profiles while keeping Codex and shell history separate, set
`PROFILE_CLAUDE=main` in both. A change an agent makes to shared state
reaches every profile that shares it.

The start fields default to `on`. At a start without network access they
skip their updates without marking the start failed; `START_UPGRADE_TOOLS`
still copies `.devcontainer/mise.toml`, so a newly declared tool fails the
start until an online start or `aidc:sync` installs it. See
[Inside the container](container.md#updating-mise).

Values are taken literally: quotes stay as characters, and only whole-line
`#` comments are allowed.

## Applying changes

| You changed | Do this |
| --- | --- |
| `profile.env` | run `mise run profile:code <name>` again, then VS Code: "Rebuild Container" |
| the workspace image (`.devcontainer/Dockerfile`) | VS Code: "Rebuild Container" |
| `.devcontainer/mise.toml` | `aidc:sync` inside the container; see [Inside the container](container.md) |

`profile:code` regenerates `.local/<name>/` but never recreates an
existing container: the Dev Containers CLI starts it with `up
--no-recreate`, so a running session survives (verified 2026-09-29).
"Rebuild Container" reads the files in `.local/<name>/` and does not read
`profile.env`, so a `profile.env` change needs both, in that order.

## When VS Code closes

With `KEEP_RUNNING=on`, the default, the container keeps running after its
VS Code window closes. With `off`, closing the window stops it; state,
tools and volumes stay, and the next `profile:code` starts it again. The
field takes
effect after `profile:code` and "Rebuild Container": VS Code reads it from
the container, which stores it when it is created. Stop a kept container
with `docker stop aidc-<name>-workspace-1`, or remove it with
`profile:remove`. No container restarts on its own after Docker or WSL
restarts.

A kept container does not keep what ran in the window's terminal: a
process started there ends when the window closes. Claude Code keeps its
sessions running in its own background daemon, and Codex in its managed
app-server daemon (`codex agents` lists its sessions), so a task given to
either goes on and you can return to it later.

## Logging in to the agents

`claude` and `codex` log in through a browser that returns to a callback
server inside the container: Codex on `localhost:1455`, Claude Code on a
random port. The browser reaches it only through VS Code's port forwarding,
so keep VS Code's `remote.autoForwardPortsSource` at `process`, its
default. The `output` and `hybrid` modes detect ports only from terminal
output, and Claude Code never prints its callback port there, so its login
ends in `ERR_CONNECTION_REFUSED` (verified 2026-09-29).

Without the forward, both still log in:

- Claude Code prints a login address in the terminal whose page shows a
  code; paste it into the terminal.
- Codex: `codex login --device-auth` logs in with a code, no callback.

VS Code's forwarding setting and the Docker Desktop networking notes are
in [Host setup](host-setup.md#vs-code-port-forwarding).

## Git identity and SSH

- **Identity.** Set `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`,
  `GIT_COMMITTER_NAME` and `GIT_COMMITTER_EMAIL`. Empty fields leave the Git
  configuration VS Code copies into the container in charge.
- **A host `core.sshCommand` can block the forwarded agent.** VS Code
  copies your host Git configuration. If its `core.sshCommand` does not
  work in the container (for example a Windows OpenSSH path, or options
  that bypass the agent), authentication fails. Set `GIT_SSH_COMMAND=ssh`:
  Git prefers the environment variable.
- **Several accounts on one Git server.** The agent offers every key, and
  the server authenticates you as the account of the first key it accepts.
  This repository does not select a key per account. One way that works is
  to point `GIT_SSH_COMMAND` at the account's public key, readable inside
  the container, and offer only that key:
  `GIT_SSH_COMMAND=ssh -i /workspaces/<name>/.ssh/work.pub -o IdentitiesOnly=yes`.
  The agent still holds the private key; the container needs only the
  `.pub` file.
