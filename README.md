# AI Devcontainer

A generic development container for AI coding agent CLIs. v2 supports
Claude Code and Codex CLI.

Each named environment profile gets its own container, checkouts and
container tools. Agent logins, settings, plugins and shell history live in
state profiles that survive rebuilds and can be shared between environment
profiles. VS Code is the only entry point: you work in its terminal inside
the container. By default the container keeps running after VS Code closes,
and Claude Code and Codex keep working on their tasks in the background.

## Requirements

- A Linux or WSL2 host (macOS is not supported) with Docker and the Compose
  plugin.
- [mise](https://mise.jdx.dev/) 2026.9.15 or newer.
- VS Code with the Dev Containers extension, `code` on `PATH`, and
  `remote.autoForwardPortsSource` at its default, `process`, which agent
  logins need.
- A running host `ssh-agent`; VS Code forwards it into the container.

Details, including an `ssh-agent` setup for WSL, are in
[docs/guides/host-setup.md](docs/guides/host-setup.md).

## Quick start

```sh
git clone git@github.com:missing-bits/ai-devcontainer.git
cd ai-devcontainer
mise trust && mise install
mise run profile:new demo      # then edit profiles/demo/profile.env
mise run profile:code demo     # starts the container and opens VS Code
```

In the VS Code terminal inside the container, clone a project into
`/workspaces/demo`, then run `claude` or `codex` and log in. The first start
installs the container tools and the default plugins; if anything looks
wrong, run:

```sh
MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:status
```

## Guides

- [Host setup](docs/guides/host-setup.md): requirements, mise, `ssh-agent`.
- [Profiles](docs/guides/profiles.md): creating, changing and removing
  profiles; sharing state; logging in to the agents; Git identity and SSH
  accounts.
- [Inside the container](docs/guides/container.md): container tasks,
  container tools and project runtimes, updating mise, downloads, plugins,
  recovery, CLI versions.
- [Security](docs/guides/security.md): the isolation boundary, root and
  project trust, and the Docker socket. Read it before you enable
  `DOCKER_SOCKET`.

The terms used here are defined in
[docs/domain/glossary.md](docs/domain/glossary.md); the design is in
[docs/specs/](docs/specs/). To change this repository, see
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
