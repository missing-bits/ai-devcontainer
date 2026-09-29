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

## The Docker socket

`DOCKER_SOCKET=on` in `profile.env` bind-mounts the host's Docker socket
into the container and adds its group, so the container user can use it.
With the socket on, the container is no longer the isolation boundary: an
agent command inside it can control every container on the host, not just
this one. Leave it `off` unless you need it.

The opt-in is verified on Docker Engine only; Docker Desktop is untested.
