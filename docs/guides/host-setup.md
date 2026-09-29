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
