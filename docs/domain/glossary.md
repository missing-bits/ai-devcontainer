# AI Devcontainer — domain glossary

A development container for Claude Code and Codex CLI, opened through VS Code.
This glossary defines terms; requirements live in `docs/specs/`.

## Terms

**Environment profile**:
A named working environment `<p>` with its own configuration in
`profiles/<p>/`, its own checkouts in `projects/<p>/`, its own container, and
its own profile tools volume.
_Avoid_: workspace, project

**Profile project space**:
The checkouts in `projects/<p>/`, mounted in that profile's container at
`/workspaces/<p>`.

**Agent state profile**:
A named, persistent namespace for one agent's user state (credentials,
settings, plugins, sessions), kept in one volume; profiles that name the same
agent state profile share that state.
_Avoid_: login profile, account

**Shell history profile**:
A named, persistent namespace for shell history, shared by the profiles that
name it.

**Default state profile**:
The rule that an agent state profile or shell history profile left unset takes
the environment profile's name.
_Avoid_: profile inheritance

**Profile tools volume**:
The named volume `aidc-tools-<p>` that holds one environment profile's
container tool installations, the tools config copy, and its lockfile.
_Avoid_: snapshot, active tool snapshot

**Tools config copy**:
The copy of `.devcontainer/mise.toml` in the profile tools volume, with the
`mise.lock` mise writes beside it; launchers and container tasks read it.
_Avoid_: desired toolset, manifest

**Container tools**:
The tools that `.devcontainer/mise.toml` declares, the agent CLIs included.
_Avoid_: project tools

**Project runtimes**:
The tools and runtimes that a project's own `mise.toml` declares.

**Default plugin catalog**:
The versioned file `.devcontainer/plugins.json` that lists, per agent, the
marketplaces and the default plugins.

**Plugin initialization**:
The one-time install of the missing default plugins into a new agent state
profile, ended by the plugin marker.
_Avoid_: plugin sync, plugin update

**Host tasks**:
The mise tasks of the root `mise.toml`, run on the host (`profile:*` and the
repository checks).

**Container tasks**:
The `aidc:*` mise tasks of `.devcontainer/mise.toml`, run inside a container.
_Avoid_: aidc command, command front

**Active profile**:
The environment profile that `profile:code` last used, taken when no profile
is named.
_Avoid_: default profile

**Isolation boundary**:
The container itself: agent commands run without an agent sandbox inside it.
_Avoid_: sandbox
