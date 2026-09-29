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
checkout. Run `mise trust` and `mise install` in that checkout as usual. A
project's `mise.toml` never changes which agent CLI runs: the `claude` and
`codex` launchers come first on `PATH` and resolve the CLI from the
container tools.

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
   `/opt/aidc/tools/init.log`.
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
through tables verified against Codex 0.157.1, with no runtime version
check; a newer Codex can add a command the tables miss. See
[CONTRIBUTING.md](../../CONTRIBUTING.md#after-a-codex-update).
