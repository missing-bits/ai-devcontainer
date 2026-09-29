---
ticket: none
date: 2026-09-29
status: approved
revises: ./2026-09-28-ai-devcontainer-v2-design.md
branch: feature/container-sudo-mise-trust
base: develop
---

# Container sudo, mise updates, downloads and project trust design

## Purpose

Four problems in the v2 container, each with the decision that answers it:

- `vscode` cannot run anything as root, so it cannot install an OS
  package a project needs (D1).
- `vscode` cannot update mise when a project's `min_version` asks for a
  newer one, and the developer requires that this work without `sudo`
  (D2).
- Keeping mise and the container tools current needs a manual
  `aidc:update` in every profile; a profile may want that done at every
  start (D3).
- Every new profile, and every profile rebuilt after `profile:remove`,
  downloads the same tool archives again (D5); every project checked out
  in a profile asks for `mise trust` before its configuration loads (D4).

Terms follow `docs/domain/glossary.md`.

## Amended v2 contracts

This spec leaves the rest of the v2 design spec and technical design as
they stand. It replaces or makes exceptions to these contracts:

- v2 Goals, "Make tool upgrades explicit", and v2 Tools, "A later start
  installs what is missing and never upgrades": a profile with
  `START_UPGRADE_TOOLS=on` upgrades at every online start (D3). With the
  field `off`, the v2 contract holds unchanged.
- v2 Tools and TD §3.9, the tools config copy changes only through
  `aidc:sync` or `aidc:update`: with `START_UPGRADE_TOOLS=on` a start also
  copies it (D3).
- v2 Isolation: `vscode` can act as root (D1), and the consequences grow
  (Isolation, amended).
- v2 Profiles: `profile.env` gains two fields (D3); every container
  mounts one more volume, shared by all profiles (D5).
- v2 AC10 (a start without network marks the start failed and still lets
  VS Code attach): unchanged. A skipped update adds no failure of its own
  (D3), but a failed tools step or plugin initialization still marks the
  start failed.
- TD §2: the container tasks' script `aidc-tools` gains two subcommands,
  and the entrypoint's start sequence gains a step (D3); the entrypoint
  still holds no tool logic, and container tasks still exclude plugin
  updates. The shared Compose file gains the D4 and D5 variables; the
  generated fragment gains the D3 variables and the D5 volume.
- The container-task invocation `mise -C /` stays as it is; D4 does not
  weaken it (S6).

The TD sections this touches: §2 (workspace image, shared Compose file,
generated fragment, entrypoint and container tasks rows), §3.1
(`profile.env` fields), §3.3 (tools step), §3.4 (start sequence), §3.9,
§4 (state), §5 (concurrency), §6 (failure handling) and §7
(verification). No new part is needed.

## Decisions

- **D1.** The workspace image installs `sudo` and grants `vscode`
  passwordless `sudo` for every command, through one file in
  `/etc/sudoers.d/`.
- **D2.** The image installs mise as `/opt/aidc/mise/bin/mise` and links
  `/usr/local/bin/mise` to it. The layer that creates `vscode` hands
  `/opt/aidc/mise` to it with `chown`, so the mise download layer stays
  before the UID arguments and keeps its layer cache. `vscode` updates
  mise with the native command and no `sudo`: `mise self-update` for the
  newest release, `mise self-update <version>` for a given one (probe
  2026-09-29: 2026.9.15 to 2026.9.16 through the link, as `vscode`). An
  updated mise lasts until the container is recreated; "Rebuild
  Container" returns to the version the image pins, which the image keeps
  pinning by version and SHA-256. Considered: `sudo mise self-update`
  under D1 alone; rejected because the developer requires updating mise
  without `sudo`, and the start step (D3) then needs no `sudo` either.
- **D3.** Two `profile.env` fields, `START_UPDATE_MISE` and
  `START_UPGRADE_TOOLS`, `on` or `off`, default `off`, validated like
  `DOCKER_SOCKET`, reach the container as `AIDC_START_UPDATE_MISE` and
  `AIDC_START_UPGRADE_TOOLS`. The entrypoint decides the start policy and
  calls `aidc-tools` for every mise run:
  1. Network check, only when either field is `on`: one HTTPS request to
     `https://api.github.com` with a five-second timeout. A response of
     any status means online; no response means offline. Nothing else
     decides it.
  2. `START_UPDATE_MISE=on`: online, `aidc-tools self-update`, a new
     subcommand that runs `mise self-update -y --no-plugins` under the
     mise isolation and outside the tools lock (the binary is not in the
     tools volume); it updates the mise binary only. Offline, skipped.
     The init result marker names a failure of this step `mise`, beside
     `tools` and `plugins-<agent>`.
  3. Tools step. `START_UPGRADE_TOOLS=on`: online, `aidc-tools update`
     (copy, lock, install, upgrade under the tools lock, as `aidc:update`
     runs today); offline, `aidc-tools start copy`, a new variant of the
     start step that, under one tools lock, copies the current
     `.devcontainer/mise.toml` and then installs without `mise lock`,
     which needs the network: `mise install --locked` when `mise.lock`
     exists, plain `mise install` when it does not. A tool the old
     lockfile does not cover, or a missing lockfile, fails the step as
     `tools`; the copied config stays, and the next online update or
     `aidc:sync` locks it. `START_UPGRADE_TOOLS=off`: the
     v2 start step, unchanged.
  4. Plugin initialization, unchanged.

  A skip is logged in the start's log and adds no failure. After a
  successful network check, a failed self-update or upgrade is logged and
  marks the start failed, and the start goes on. Offline, a tools config
  that declares a tool not yet installed fails the plain start step as it
  does in v2. A self-update that runs while a container task uses mise
  is accepted: the old binary finishes its run.
- **D4.** The shared Compose file sets `MISE_TRUSTED_CONFIG_PATHS` to
  `/workspaces`, so mise trusts every project checked out in the profile
  project space without asking. A container mounts only its own profile
  project space there. The mise isolation still removes the variable, so
  container tasks, launchers and the entrypoint never read a project's
  configuration. Considered: `/workspaces/<p>` from the generator; the
  same effect, since nothing else is mounted under `/workspaces`, for a
  generator change. Trust matters for shell activation only: in mise's
  normal mode `mise exec`, `mise run` and `mise install` trust their active
  config on their own, and a config with only plain `[tools]` entries
  needs no trust (probe 2026-09-29, mise 2026.9.15 in the image).
- **D5.** One named volume, `aidc-mise-downloads`, shared by every
  environment profile, holds the archives mise downloads. The image
  creates its mount point, `/opt/aidc/downloads`, owned by `vscode`, so
  an empty volume takes that ownership. The shared Compose file and the
  mise isolation set `MISE_DOWNLOADS_DIR=/opt/aidc/downloads`,
  `MISE_ALWAYS_KEEP_DOWNLOAD=1`, which keeps an archive after its
  install, and `MISE_CACHE_DIR=/opt/aidc/tools/cache`, which keeps mise's
  other cache in each profile's tools volume. Installed tools stay in the
  tools volume too. The generated fragment mounts the volume;
  `profile:code` creates it as external; `profile:remove` never removes
  it. `AIDC_MISE_DOWNLOADS_VOLUME`, defaulting to `aidc-mise-downloads`,
  names it for both the generator and `profile:code`, so the integration
  suite can use its own. Considered: one volume per profile, which
  shares nothing between profiles; and sharing mise's whole cache, which
  profiles on different mise versions (D2, D3) would read and write
  together.

## Out of scope

- Keeping an updated mise across a rebuild; changing the pinned version
  stays a Dockerfile change, tested with `mise run test:integration`.
- A `sudo` password, or a narrower `sudo` rule.
- Sharing installed tools between profiles.
- Updating mise plugins or agent plugins at start; `mise plugins update`
  in a project stays the native way for project runtimes.
- A general network detector: D3's check is the whole contract.
- A lock around the shared downloads; mise's own handling applies until a
  probe shows it falls short.

## Isolation, amended

The container stays the isolation boundary; Docker's default capabilities,
seccomp and AppArmor profiles stay in place, and the container is not
privileged. With the Docker socket opted in, nothing below changes the
picture: the container is no longer the boundary either way.

An agent command can now act as root inside the container. On top of what
v2 lists, it can:

- change files the image owns, including the mise binary and the policy
  files in `/etc/claude-code/` and `/etc/codex/` that turn CLI
  self-update off and set Codex's defaults; these changes last until the
  container is recreated;
- change the ownership and permissions of the checkouts and of every
  mounted volume; these changes persist, and a rebuild does not undo
  them.

Trusting the profile project space means a project's `mise.toml` takes
effect as soon as mise reads it: its environment, hooks and tasks run
without a prompt, including in a repository an agent clones there. Clone
only what you would trust.

The mise downloads volume reaches every environment profile, whatever
state profiles they use: an agent command in one profile can change an
archive another profile's mise installs next, subject to the checksums
mise verifies. Several containers installing the same archive at once can
race, and a retry settles it (S8).

With `START_UPDATE_MISE` or `START_UPGRADE_TOOLS` on, an online start runs
mise and tool versions no test has seen; a newer Codex may outrun the
launcher's tables (v2 Tools). The profile accepts that risk by turning the
field on.

## Changes

- `.devcontainer/Dockerfile`: the `sudo` package and
  `/etc/sudoers.d/vscode`; mise under `/opt/aidc/mise/bin/` with the
  `/usr/local/bin/mise` link, handed to `vscode` in the user layer; the
  `/opt/aidc/downloads` mount point.
- `.devcontainer/compose.yaml`: `MISE_TRUSTED_CONFIG_PATHS` and the three
  D5 variables.
- `.devcontainer/lib/mise-isolation.sh`: the three D5 variables.
- `.devcontainer/bin/aidc-tools`: the `self-update` subcommand and the
  `start copy` variant.
- `.devcontainer/bin/aidc-entrypoint`: the D3 policy and the `mise` step
  in the init result marker.
- `examples/profile/profile.env` and the host parser: the D3 fields.
- The generator and `tasks/host/profile/code`: the D3 variables, the
  downloads volume and `AIDC_MISE_DOWNLOADS_VOLUME`.
- `docs/domain/glossary.md`: **Mise downloads volume**, with
  `_Avoid_: shared cache, tools cache`.
- Tests: unit tests for the parser, the generator, `aidc-tools`, the
  entrypoint's branches, and the mise isolation as `aidc-tools` and the
  launchers see it (five allowed `MISE_*` variables,
  `MISE_TRUSTED_CONFIG_PATHS` removed); integration tests for S1–S3 and
  S5–S8, with a downloads volume per test run.
- The v2 technical design: the sections named above.
- `docs/guides/profiles.md`, `container.md`, `security.md`: the new
  fields, updating mise, the downloads volume and reclaiming its space,
  and the consequences above.
- `docs/verification/acceptance-matrix.md` and `manual-checklist.md`: the
  criteria below.

## Reclaiming space

`rm -rf /opt/aidc/downloads/*` in any container empties the downloads
volume; `vscode` owns it, so no `sudo` is needed. mise prunes its own
cache in each tools volume, and `mise cache clear` empties it.

## Acceptance criteria

- **S1.** In a started container, `sudo -n true` as `vscode` succeeds
  without a password.
- **S2.** `visudo -c` accepts the image's sudoers configuration.
- **S3.** As `vscode`, without `sudo`, `mise self-update <version>`
  changes `mise --version`, and a recreated container with
  `START_UPDATE_MISE=off` reports the pinned version again.
- **S4.** The same holds after VS Code's "Rebuild Container" (manual
  checklist).
- **S5.** Each D3 branch behaves as stated: both fields `off` update
  nothing; each field `on` and online runs its update; a forced update
  failure marks the start failed under its step name and the start goes
  on; each field `on` and offline logs the skip and adds no failure of its
  own, and for `START_UPGRADE_TOOLS` copies the tools config and runs no
  `mise lock`: an unchanged tools config with its tools installed starts
  without a failure; a config that adds a tool the old `mise.lock` does
  not cover, and a tools volume with no `mise.lock`, each mark the start
  failed as `tools` and keep the copied config.
- **S6.** A project under `/workspaces/<p>` whose `mise.toml` sets an
  environment variable shows that value without a trust prompt in two
  checks: in the container's interactive zsh, where mise is activated,
  after `cd` into the project; and in a fresh non-interactive process that
  inherits the container environment but not that variable, through
  `mise exec -- printenv <variable>` run in the project, which is how an
  agent's command loads project configuration (this one holds without D4
  too, see D4). A fresh project outside `/workspaces` still gets mise's
  "not trusted" warning in the interactive zsh, without its variable, and
  `MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:status` run inside a
  trusted project that defines its own `aidc:status` runs the container
  task.
- **S7.** For the aqua backend, which installs the agent CLIs: after one
  profile installs a tool, a second profile with an empty tools volume and
  the first profile's `mise.lock` installs the same version on no network
  (the suite's no-network fixture), which proves the archive came from
  `aidc-mise-downloads`. The probe runs on the image's pinned mise and the
  container platform. For other backends reuse is whatever mise does
  natively; this change promises nothing more.
- **S8.** Probe on the image's pinned mise: two containers sharing
  `aidc-mise-downloads` install the same tool version at once, and
  `aidc:status` runs in one of them meanwhile; then an install killed
  mid-download is followed by an install of the same version in another
  container. The result, success or a named failure, is recorded in the
  acceptance matrix; a failure keeps the concurrency requirement open
  rather than turning it into a limitation.

  Result, 2026-09-29: an install killed mid-download does not break the
  next one. Two installs of one archive at once can race: the loser fails
  with "No such file or directory" (both integration runs, one of three
  standalone runs), and a plain retry then succeeds. Ruling, 2026-09-29
  (developer): accepted under v2's report-and-retry; a start that loses the
  race marks `tools` failed, and the next start or `aidc:sync` settles it.
  The integration test asserts that a retry settles a lost race. Concurrent
  use stays a requirement met by retry, not by a lock.
