---
ticket: none
date: 2026-09-29
---

# Inside the container

## Container tasks

Run the container tasks in the VS Code terminal inside the container:

```sh
MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:<task>
```

`-C /` starts mise in a neutral directory, so no project configuration
loads, and disabling task auto-install keeps a project from installing
anything first. Both are needed: a plain `mise run aidc:<task>` inside an
untrusted project can trust it and run the project's own task of the same
name instead.

- `aidc:sync` copies this repository's `.devcontainer/mise.toml` (mounted
  read-only) into the profile tools volume, locks it and installs it.
- `aidc:update` does the same, then upgrades every tool to its newest
  allowed version.
- `aidc:status` reports the last start's result and log, the container
  tools, and whether plugin initialization completed for each agent. It
  reads files only, so it works offline.

## Container tools and project runtimes

Container tools, the agent CLIs included, are declared in
`.devcontainer/mise.toml` in this repository. Add or pin a tool there, then
run `aidc:sync` in each profile that needs it.

Project runtimes belong in the project's own `mise.toml`, inside its
checkout; run `mise install` there. mise trusts every project under
`/workspaces` without asking, so a project's configuration, its hooks and
tasks included, takes effect as soon as mise reads it: clone only what you
would trust ([Security](security.md)). A project's `mise.toml` never
changes which agent CLI runs: the `claude` and
`codex` launchers come first on `PATH` and resolve the CLI from the
container tools.

## Updating mise

The image pins mise, and `vscode` owns the binary, so you can update it
without `sudo`:

```sh
mise self-update            # newest release
mise self-update 2026.9.20  # a given version
```

An updated mise lasts until the container is recreated; "Rebuild Container"
returns to the pinned version. To update at every start, set
`START_UPDATE_MISE=on` in `profile.env`; `START_UPGRADE_TOOLS=on` does the
same for the container tools, as `aidc:update`. `vscode` also has
passwordless `sudo`, for OS packages a project needs.

## Downloads

Every profile shares the mise downloads volume, mounted at
`/opt/aidc/downloads`: a tool archive one profile downloaded installs in
another, or after `profile:remove`, without downloading again. Installed
tools and mise's other cache stay in each profile's tools volume. Two
profiles installing the same archive at the same moment can race; the
loser fails with "No such file or directory", and running the install
again (the next start, or `aidc:sync`) succeeds. To reclaim space, empty it
from any container:

```sh
rm -rf /opt/aidc/downloads/*
```

mise prunes its other cache in each tools volume on its own; `mise cache
clear` empties it.

## Default plugins

A new agent state profile gets the marketplaces and plugins listed in
`.devcontainer/plugins.json`, once, on the first container start that uses
it. After that, the catalog no longer touches that state profile: a plugin
added to the catalog does not reach state profiles already initialized, and
a plugin you removed is not installed again. Install or update plugins with
each CLI's own `plugin` and `marketplace` commands. Codex refreshes its
marketplace clones at session start on its own; Claude Code follows its own
update behaviour.

## When a start fails

A failed tool installation or plugin initialization does not stop the
container: VS Code still attaches. To recover:

1. Run `aidc:status` and read the start's log; the full log is
   `/opt/aidc/tools/init.log`. A failed step is named `mise` (the start's
   mise update), `tools` or `plugins-<agent>`.
2. Fix the cause, typically network access or GitHub's rate limit.
3. Run `aidc:sync` to install the tools again. Plugin initialization runs
   at container start, so use VS Code's "Rebuild Container" to retry it.

## CLI versions

`claude` and `codex` install at whatever `latest` resolves to when the tools
volume is first populated. Their self-update is off, so they move only
through `aidc:sync` or `aidc:update`. Pin a version in
`.devcontainer/mise.toml` if you need a fixed one.

**After an `aidc:update` that moves Codex to a newer minor version,** check
the `codex` launcher before relying on it. It recognises Codex commands
through tables verified against Codex 0.158.0, with no runtime version
check; a newer Codex can add a command the tables miss. See
[CONTRIBUTING.md](../../CONTRIBUTING.md#after-a-codex-update).
