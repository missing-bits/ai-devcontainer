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
  profile's tools volume. It keeps `projects/<name>/`, `profiles/<name>/`
  and every state volume, so logins and checkouts survive.

## `profile.env`

| Field | Meaning |
| --- | --- |
| `PROFILE_CLAUDE`, `PROFILE_CODEX` | agent state profile: logins, settings, plugins, sessions |
| `PROFILE_SHELL` | shell history profile |
| `DOCKER_SOCKET` | `on` or `off`; see [Security](security.md) first |
| `GIT_AUTHOR_*`, `GIT_COMMITTER_*` | Git identity inside the container |
| `GIT_SSH_COMMAND` | SSH command Git uses; see below |

An empty state field takes the environment profile's name. Profiles that
name the same state profile share it. For example, to use one Claude login
in two profiles while keeping Codex and shell history separate, set
`PROFILE_CLAUDE=main` in both. A change an agent makes to shared state
reaches every profile that shares it.

Values are taken literally: quotes stay as characters, and only whole-line
`#` comments are allowed.

## Applying changes

| You changed | Do this |
| --- | --- |
| `profile.env` | run `mise run profile:code <name>` again; it regenerates `.local/<name>/` |
| the workspace image (`.devcontainer/Dockerfile`) | VS Code: "Rebuild Container" |
| `.devcontainer/mise.toml` | `aidc:sync` inside the container; see [Inside the container](container.md) |

"Rebuild Container" reads the files in `.local/<name>/` and does not read
`profile.env`, so on its own it keeps the old values. Whether
`profile:code` alone applies a `profile.env` change to an already running
container is not verified yet (manual checklist, item 10); if a change does
not show, use "Rebuild Container" after `profile:code`.

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
