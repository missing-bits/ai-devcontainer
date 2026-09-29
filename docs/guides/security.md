---
ticket: none
date: 2026-09-29
---

# Security

## The container is the isolation boundary

Agent commands run without an agent sandbox inside the container. Claude
Code's sandbox stays off, its default. Codex runs with
`sandbox_mode = "danger-full-access"` and `approval_policy = "on-request"`
from the container's system configuration, because its sandbox does not start under Docker's default
seccomp and AppArmor profiles. Those Docker profiles stay in place around
the container. A different Codex sandbox mode in your own configuration
overrides the default.

An agent command can therefore change every checkout of the profile and its
state volumes, and use the forwarded SSH agent and the network. A state
volume shared between profiles carries an agent's changes to every profile
that shares it.

## Root, trust and shared downloads

`vscode` has passwordless `sudo`, so an agent command can act as root inside
the container. It can change files the image owns, including the mise
binary and the policy files in `/etc/claude-code/` and `/etc/codex/`, until
the container is recreated. It can also change the ownership and permissions
of the checkouts and of every mounted volume; those changes persist, and a
rebuild does not undo them.

mise trusts every project under `/workspaces`: a project's `mise.toml` runs
its environment, hooks and tasks without a prompt, including in a
repository an agent clones there.

The mise downloads volume reaches every profile, whatever state profiles
they use: an agent command in one profile can change an archive another
profile installs next, subject to the checksums mise verifies. Two
profiles installing the same archive at once can race; a retry settles it
([Inside the container](container.md#downloads)).

With `START_UPDATE_MISE` and `START_UPGRADE_TOOLS` on, the default, an
online start runs mise and tool versions no test has seen. Codex's managed
daemon updates itself into the agent state volume, which every profile
naming that state profile shares
([Inside the container](container.md#cli-versions)).

## The Docker socket

`DOCKER_SOCKET=on` in `profile.env` bind-mounts the host's Docker socket
into the container and adds its group, so the container user can use it.
With the socket on, the container is no longer the isolation boundary: an
agent command inside it can control every container on the host, not just
this one. Leave it `off` unless you need it.

The opt-in is verified on Docker Engine only; Docker Desktop is untested.
