---
ticket: none
date: 2026-09-29
---

# Host setup

## Requirements

- A Linux or WSL2 host. macOS is not supported: the host tasks use GNU
  coreutils (`mv -T`, `stat -c`), Bash and `flock` from `util-linux`, all
  present on a typical Linux or WSL distribution.
- Docker Engine or Docker Desktop, running, with the `docker compose`
  plugin.
- VS Code with the
  [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
  extension, and the `code` command on `PATH`: `profile:code` uses it to
  open VS Code inside the container.
- A running host `ssh-agent`, with `SSH_AUTH_SOCK` exported in the shell VS
  Code starts from. VS Code forwards the agent into the container; no
  private key is copied in.

## mise

Install [mise](https://mise.jdx.dev/) 2026.9.15 or newer, then, from the
repository root:

```sh
mise trust
mise install
```

`mise trust` lets mise load the repository's `mise.toml`, which defines the
host tasks. `mise install` installs the host tools it pins: Node.js, the
Dev Containers CLI, `jq`, `bats`, `shellcheck`, `shfmt` and `usage`, which
shell completion needs for task arguments. It also installs the latest
Claude Code and Codex CLI, for working on this repository on the host.

## VS Code port forwarding

The agents log in through a browser on the host that returns to a callback
server inside the container, on a fixed or a random port. Containers use
Docker's bridge network, so the browser reaches that port only through
VS Code's port forwarding. Keep this VS Code setting at its default:

```json
"remote.autoForwardPortsSource": "process"
```

With `output` or `hybrid`, VS Code forwards only ports it sees printed in a
terminal, and Claude Code's login fails with `ERR_CONNECTION_REFUSED`
(verified 2026-09-29). See [Profiles](profiles.md#logging-in-to-the-agents)
for logging in without a forward.

## Docker Desktop or Docker Engine in WSL

Both work; they differ in networking and in what this repository has
verified on them.

- **Docker Desktop** (the engine the probes of 2026-09-28/29 ran on):
  `network_mode: host` would share the Docker VM's network, not the one of
  WSL or Windows, so a port bound inside the container is unreachable from
  either (verified 2026-09-29). Docker Desktop 4.34 and later has a host
  networking setting (Settings → Resources → Network) that changes this;
  not verified here. The containers do not use host networking, so none of
  this is needed for normal use.
- **Docker Engine inside WSL** (`docker-ce`): host networking shares the
  WSL network. `DOCKER_SOCKET=on` is verified on Docker Engine only
  ([Security](security.md#the-docker-socket)). Behind a VPN that lowers
  the WSL interface's MTU, containers on a bridge network with the default
  MTU of 1500 can stall on HTTPS; setting a matching `mtu` in
  `/etc/docker/daemon.json` is the usual fix. Reported by a similar setup,
  not verified here.

## An `ssh-agent` on WSL

WSL does not start an `ssh-agent`. A systemd user unit can start one and
keep it running:

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

```sh
systemctl --user enable --now ssh-agent.service
```

Export the socket from your login shell (for example `~/.zshrc` or
`~/.bashrc`), so every terminal and VS Code pick it up:

```sh
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
```

Add your keys with `ssh-add`. To have `ssh` add a key the first time it is
used, set `AddKeysToAgent yes` in `~/.ssh/config`.
