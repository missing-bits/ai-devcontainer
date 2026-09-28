---
ticket: none
date: 2026-09-28
status: draft
spec: ../specs/2026-09-28-ai-devcontainer-v2-design.md
branch: feature/ai-devcontainer-v2
---

# AI Devcontainer v2 Technical Design

## 1. Context

This document says where each part of the v2 design spec sits, what crosses
its borders, and where state lives; the plan decides the order of work. The
system runs under one host user on Linux or WSL2, with VS Code and its Dev
Containers extension as the only entry point. Outside it: VS Code, plugin
marketplaces, tool download sources and the checkouts under `projects/`.

*Verified* names its source: a v1 spike or probe recorded in the v1 technical
design (branch `feature/ai-devcontainer`), or a check made for this document.
*To verify* feeds §7 and §8. No domain skill covers Docker, Compose or mise,
so part kinds come from generic knowledge (vocabulary gap). KISS and YAGNI
rule: where a safeguard would be tempting, the document states the behaviour
and the accepted risk instead.

## 2. Parts

All parts are `new`.

| part | kind | change | placement | owns | deliberately excludes |
|---|---|---|---|---|---|
| Host tasks | mise file tasks (bash) | new | root `mise.toml`, `tasks/host/`, small library `tasks/host/lib/` | name validation, `profile.env` parsing, profile creation, generation of `.local/<p>/`, volume creation, `devcontainer up`, opening VS Code, removal, the host profile lock, the active profile, repository checks | any change inside a running container; reading agent state |
| Shared Compose file | Compose file | new | `.devcontainer/compose.yaml` | the `workspace` service: `build` with context `.` (the `.devcontainer/` directory, since Compose resolves it against this first file) tagged `aidc-workspace:local`, `init: true`, user `dev`, entrypoint, keep-alive command, fixed policy and tool environment, read-only mount of `.devcontainer/` at `/opt/aidc/desired` | anything profile-specific |
| Generated profile files | local files | new | `.local/<p>/compose.yaml` (the profile's Compose fragment) and `.local/<p>/.devcontainer/devcontainer.json` | the profile's project name, build arguments, volume names, mounts, environment and socket opt-in | anything versioned; secrets |
| Workspace image | Dockerfile | new | `.devcontainer/Dockerfile`, `FROM debian:trixie-slim`, context `.devcontainer/` | OS packages (`zsh`, `git`, `curl`, `ca-certificates`, `openssh-client`, `jq`, `util-linux`, `procps`, `locales`), `docker-ce-cli` with the Compose plugin and no daemon, mise pinned by version and SHA-256, user `dev` built with the host UID and GID, volume mount points owned by `dev`, policy files, launchers, scripts, a minimal `zshrc` (§3.6) | container tools; agent state |
| Policy files | image assets | new | `.devcontainer/policy/` → `/etc/claude-code/managed-settings.json`, `/etc/codex/requirements.toml`, `/etc/codex/config.toml` | CLI self-update off, Claude plugin auto-update on, Codex file credentials, Codex sandbox and approval mode | user preferences; files in agent state |
| Entrypoint | container executable | new | `.devcontainer/bin/aidc-entrypoint` → `/usr/local/lib/aidc/bin/` | the start sequence (§3.4), the init log and the init result marker, handing over to the keep-alive command whatever happened | tool and plugin logic |
| Container tasks | mise tasks + bash script | new | `[tasks]` of `.devcontainer/mise.toml` (`aidc:sync`, `aidc:update`, `aidc:status`); `.devcontainer/bin/aidc-tools` shared with the entrypoint; invoked as `MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:<task>`, so the neutral directory is chosen before any configuration loads and no auto-install bypasses the tools lock (*to verify*, §8) | the tools lock, copying the config into the tools volume, `mise install`/`mise upgrade`, the status report | plugin updates |
| Agent CLI launchers | container executables | new | `.devcontainer/launchers/claude`, `.../codex` → `/usr/local/lib/aidc/launchers/`, first on `PATH` | resolving each CLI from the tools config copy; Codex without the managed daemon | installing anything; CLI state |
| Plugin catalog and script | versioned data + bash script | new | `.devcontainer/plugins.json`; `.devcontainer/bin/aidc-plugins` | the default marketplaces and plugins per agent; plugin initialization and its marker, under the state lock | plugin updates, removal, rollback |
| Profile tools volume | named volume | new | `aidc-tools-<p>` at `/opt/aidc/tools` | installations, the tools config copy with `mise.lock`, the tools lock, the init log and result marker | agent state |
| Profile example | versioned files | new | `examples/profile/profile.env` | fictional sample values, state fields empty, socket off | real names or values |
| Ignore files | versioned files | new | `.gitignore`, `.dockerignore` | excluding `profiles/`, `projects/` and `.local/` from Git and from any build context; the image context is `.devcontainer/` alone | a guarantee against a force-add or a custom context |

## 3. Contracts

### 3.1 `profile.env` fields

`KEY=value` lines, split at the first `=`, `#` comments and blank lines
ignored, never sourced. Unknown and duplicate keys are rejected; an empty value
counts as unset.

| key | values | unset means | reaches the container as |
|---|---|---|---|
| `PROFILE_CLAUDE`, `PROFILE_CODEX`, `PROFILE_SHELL` | a valid name | the environment profile's name | the volume names in §3.2 |
| `DOCKER_SOCKET` | `on`, `off` | `off` | with `on`: a bind of `/var/run/docker.sock` and `group_add` of its host GID |
| `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL`, `GIT_SSH_COMMAND` | literal text | not set | environment variables of the same name |

Names match `^[a-z0-9][a-z0-9_-]*$`. The variables override `user.name`,
`user.email` and `core.sshCommand` of the copied Git configuration
(*verified*, Git 2.43.0, probe 2026-09-28). The generator escapes `$` as `$$`,
because Compose interpolates the fragment.

### 3.2 Volumes and mounts

| source | target | environment |
|---|---|---|
| `aidc-tools-<p>` | `/opt/aidc/tools` | `MISE_DATA_DIR=/opt/aidc/tools/mise`, `MISE_GLOBAL_CONFIG_FILE=/opt/aidc/tools/mise.toml` |
| `aidc-claude-<PROFILE_CLAUDE>` | `/home/dev/.claude` | `CLAUDE_CONFIG_DIR=/home/dev/.claude` |
| `aidc-codex-<PROFILE_CODEX>` | `/home/dev/.codex` | `CODEX_HOME=/home/dev/.codex` |
| `aidc-shell-<PROFILE_SHELL>` | `/home/dev/.local/state/shell` | `HISTFILE=/home/dev/.local/state/shell/zsh_history` |
| `projects/<p>/` (bind) | `/workspaces/<p>` | — |
| `.devcontainer/` (bind, read-only) | `/opt/aidc/desired` | — |

Host tasks create the named volumes with `docker volume create`; the fragment
declares them `external`, so no Compose command removes shared state. The
generator writes every bind source as an absolute host path, because Compose
resolves relative paths against the first file's directory. An empty volume
takes the ownership of the image's mount point (*to verify*, AC2). `CLAUDE_CONFIG_DIR` holds `.claude.json` (*verified*, spike 2026-09-26);
Codex keeps `auth.json` in `CODEX_HOME` under the file store (*verified*,
spike 2026-09-27, after a keyring login failed).

### 3.3 Tools config copy and lock

All steps run as `dev`, from `/`, with inherited `MISE_*` variables removed
and the two fixed ones set again (the v1 `mise-isolation.sh` allowlist), under
the tools lock `/opt/aidc/tools/.lock`. *Copy* always means: write
`/opt/aidc/desired/mise.toml` to a temporary file in the volume, then rename
it over `mise.toml`, so an interrupted copy leaves the old file or none.

- start: copy and run `mise lock --global` only when no copy exists; then
  `mise install --locked`;
- `aidc:sync`: copy, `mise lock --global`, `mise install --locked`;
- `aidc:update`: as `aidc:sync`, then `mise upgrade`.

One directory holds the copy and `mise.lock`: no staging, no manifest. A copy
that installs partly stays, and the next run installs the rest. *Verified*,
spike 2026-09-26: full aqua keys install standalone binaries without Node;
`mise lock --global` keeps unchanged entries and drops undeclared tools;
`mise upgrade` moves tools to their newest allowed versions and rewrites
`mise.lock`. *To verify*: which version `mise lock --global` picks for a
changed declaration (v1 probes saw the newest installed match), and that
`mise install --locked` needs no network when everything is installed.

### 3.4 Start sequence

1. Redirect output to `/opt/aidc/tools/init.log`; write `running <UTC time>`
   to the result marker `/opt/aidc/tools/init.status`. Run the tools step of
   §3.3.
2. Plugin initialization (§3.5) for Claude, then Codex, each only when its
   launcher resolves the CLI.
3. Write `ok <time>` or `failed <time>: <steps>` to the marker.
4. `exec` the keep-alive command, whatever happened, so VS Code can attach.

### 3.5 Plugin initialization

Catalog shape, with fictional names; `codex` has the same shape:

```json
{ "claude": { "marketplaces": ["example-org/example-marketplace"],
              "plugins": ["example-plugin@example-marketplace"] } }
```

`aidc-plugins init <agent>`, run through the launchers:

1. If `<state>/.aidc/plugins-initialized` exists, stop.
2. Take the state lock `<state>/.aidc/lock`, waiting; check the marker again.
3. Read the agent's entry from `/opt/aidc/desired/plugins.json`.
4. Run `marketplace list --json`. Add each catalog marketplace whose
   repository is not listed: `claude plugin marketplace add <owner/repo>
   --scope user` or `codex plugin marketplace add <owner/repo>`. Claude lists a
   shorthand as `{name, source: "github", repo}`; Codex stores it as
   `https://github.com/<owner/repo>.git` (*verified*, probe 2026-09-28).
5. List the installed plugins, disabled ones included, and install each
   default not listed: `claude plugin install <plugin@marketplace> --scope
   user` or `codex plugin add <plugin@marketplace>`. A listed plugin is never
   installed again, because install re-enables a disabled plugin (*verified*,
   probe 2026-09-28).
6. If every command succeeded, write the marker; otherwise log each failure
   and leave the marker absent.
7. Release the lock.

Codex plugin commands never start the managed daemon (*verified*, 0.157.1
source). The plugin list command and its JSON shape are *to verify*.

### 3.6 Shell and launcher resolution

`PATH` starts with `/usr/local/lib/aidc/launchers` through the image `ENV`, a
`/etc/profile.d` script (Debian's `/etc/profile` resets `PATH`), and zsh
`chpwd` and `precmd` hooks registered after mise's, so `cd project && claude`
still finds the launcher. The `zshrc` also sets `HISTSIZE` and `SAVEHIST` to
50000 and `SHARE_HISTORY`, which appends to the shared file. Each launcher, in a
subshell with the isolation of §3.3, runs `mise which <tool>` from `/`, then
`exec`s the result in the caller's directory and environment. From `/`,
`mise which` returns the version `mise.lock` pins, even when the caller's
directory holds a project configuration (*verified*, spike 2026-09-26). With no
result, the launcher exits non-zero and names `mise run aidc:sync`.

The `codex` launcher reuses the tested v1 logic: `--no-daemon` for the
interactive CLI (no subcommand, `resume`, `fork`) unless `--remote` is given;
refusal of `agents`, `app-server daemon|proxy` and `remote-control`; only the
Codex minor version pinned in `.devcontainer/mise.toml` runs (*verified*,
0.157.1 source and spike 2026-09-27: without the flag a TUI start copied the
binary into `CODEX_HOME/packages/` and left a daemon running).

### 3.7 Policy keys

| file | key | purpose | evidence |
|---|---|---|---|
| Claude managed settings | `env.DISABLE_UPDATES = "1"` | blocks `claude update` and auto-update | *verified*, spike 2026-09-26 |
| Claude managed settings | `env.FORCE_AUTOUPDATE_PLUGINS = "1"` | keeps plugin auto-update on | see below |
| Codex `requirements.toml` | `check_for_update_on_startup = false` | no update check | *verified*, spike 2026-09-27 |
| Codex `requirements.toml` | `cli_auth_credentials_store = "file"` | `auth.json` in `CODEX_HOME` | *verified*, spike 2026-09-27 |
| Codex `requirements.toml` | `allowed_sandbox_modes = ["danger-full-access"]` | pins the isolation choice | source inspection; runtime *to verify* |
| Codex `/etc/codex/config.toml` | `sandbox_mode = "danger-full-access"`, `approval_policy = "on-request"` | container as the boundary | source inspection; runtime *to verify* |

The shared Compose file sets both Claude variables in the environment too.
Source inspection, 2026-09-28, is not runtime verification:
- Claude Code 2.1.283, `strings bin/claude.exe`: `Yte(){return
  Kte()&&!a.FORCE_AUTOUPDATE_PLUGINS}`, where `Kte()` is true under
  `DISABLE_UPDATES` or `DISABLE_AUTOUPDATER`, and the plugin pass logs
  "Plugin autoupdate: skipped (auto-updater disabled)" when `Yte()` holds;
  `claude update` still refuses under `DISABLE_UPDATES`.
- Codex 0.157.1, `strings codex | grep -o -E 'allowed_sandbox_modes|/etc/codex/[a-z_.]+'`:
  both names are present.

Codex's sandbox does not start under Docker's default seccomp and AppArmor
profiles (*verified*, v1 plan 3 evidence 2026-09-28), hence the container as
boundary.

### 3.8 Generated files and VS Code

`.local/<p>/.devcontainer/devcontainer.json`, written with `jq`:

- `name: aidc-<p>`, `service: workspace`, `workspaceFolder: /workspaces/<p>`,
  `remoteUser: dev`;
- `dockerComposeFile`: the absolute path of `.devcontainer/compose.yaml`, then
  `../compose.yaml`;
- `overrideCommand: false`, so the entrypoint and command stay (*verified*);
- `updateRemoteUserUID: false`, because the build already uses the host UID.

`.local/<p>/compose.yaml`, written as JSON (valid YAML): `name: aidc-<p>`,
build arguments `USER_UID` and `USER_GID`, the volumes and mounts of §3.2,
the environment of §3.1, and the socket bind when opted in. The Dev
Containers CLI takes the project name from `COMPOSE_PROJECT_NAME`, then `.env`
in its working directory, then `name:` (*verified*, `devcontainers/cli`
source). Accepted risk: a VS Code started with `COMPOSE_PROJECT_NAME` set
resolves another project.

`profile:code` runs `devcontainer up --workspace-folder .local/<p>` (reuses a
running container; *verified*, `findComposeContainer`), then `code
--folder-uri vscode-remote://dev-container+<hex host path of .local/<p>>/workspaces/<p>`
(form *to verify*). "Rebuild Container" reads the same files.

## 4. State

| record | home | written by | read by | lifecycle |
|---|---|---|---|---|
| Tool installations | `aidc-tools-<p>`: `mise/` | Container tasks, Entrypoint (through mise) | Agent CLI launchers, Container tasks | until `profile:remove`; `mise upgrade` may prune old versions |
| Tools config copy | `aidc-tools-<p>`: `mise.toml`, `mise.lock` | Container tasks, Entrypoint | Agent CLI launchers, Container tasks | replaced by `aidc:sync` and `aidc:update`; survives rebuilds |
| Init log | `aidc-tools-<p>`: `init.log` | Entrypoint | Container tasks (`aidc:status`) | overwritten at every start |
| Init result marker | `aidc-tools-<p>`: `init.status` | Entrypoint | Container tasks (`aidc:status`) | overwritten at every start |
| Claude state | `aidc-claude-<name>` | external: Claude Code, Plugin catalog and script | external: Claude Code | kept until the developer removes the volume |
| Codex state | `aidc-codex-<name>` | external: Codex CLI, Plugin catalog and script | external: Codex CLI | as Claude state |
| Plugin marker | `<state>/.aidc/plugins-initialized`, one per agent state volume | Plugin catalog and script | Plugin catalog and script | written once after full success; never removed by aidc |
| Shell history | `aidc-shell-<name>` | external: zsh | external: zsh | kept until the developer removes the volume |
| Generated profile files | `.local/<p>/` | Host tasks | external: Dev Containers CLI, VS Code | regenerated by `profile:code`; removed by `profile:remove` |
| Active profile | `.local/active-profile` | Host tasks | Host tasks | replaced by each `profile:code <p>` |

## 5. Concurrency

Exactly three `flock` locks, each waited for without a bound:

1. **Host profile lock**, `.local/locks/<p>.lock`, outside `.local/<p>/` so
   `profile:remove` never deletes a lock someone holds. `profile:new`,
   `profile:code` and `profile:remove` take it.
2. **Tools lock**, `/opt/aidc/tools/.lock`. The start sequence, `aidc:sync`
   and `aidc:update` take it.
3. **Agent state lock**, `<state>/.aidc/lock` in each agent state volume.
   Plugin initialization takes it and rechecks the marker.

No process holds the tools lock and a state lock at once. Unlocked, accepted:
interactive CLI sessions; a launcher during `aidc:update` (its running binary
keeps its inode); "Rebuild Container" beside `profile:code`. Cross-container
`flock` on a named volume is *to verify* by the §7 test.

## 6. Failure handling

Report and retry; no custom transactions.

- Tool install fails or is interrupted at start: log and marker say so; the
  next start runs `mise install` again.
- `aidc:sync` or `aidc:update` fails partly: installed tools stay; the task
  names the failures, exits non-zero, and a rerun retries.
- Plugin initialization fails or is interrupted: no marker; the next start
  installs only what is missing. A CLI not installed skips it, reported.
- A marketplace name already configured from another source: `add` fails,
  reported at every start until fixed by hand.
- Network down: the container starts; `aidc:status` shows the failure. Plugin
  updates follow each CLI's own failure behaviour; no retry, no rollback.
- `profile.env` edited while running: `profile:code` regenerates the files;
  the change applies at the next "Rebuild Container".
- `profile:remove` interrupted: a rerun removes what remains.

## 7. Verification

**bats unit tests**, no Docker: `profile.env` parsing, name validation,
generated files, marketplace matching on recorded list shapes, the `codex`
launcher's arguments (v1 tests), and plugin initialization with stub CLIs,
including a partial run and its retry.

**Docker integration tests**: two profiles (AC2); `cd project && claude`
in a project declaring its own `claude` (AC3); versions after recreation
offline (AC4); `aidc:status` offline from inside an untrusted project
(AC10); policy (AC6); `profile:remove` (AC11); the interrupted first plugin
install: stop the container after the first install, start it again, expect
every default and the marker (AC9); and one cross-container `flock` on a
shared volume: a second container waits while the first holds it and gets it
once the holder's container stops.

**Manual VS Code smoke checklist**:

1. Project mise activation works in the VS Code terminal.
2. `command -v claude codex` shows the launchers first, also inside a project.
3. History persists across a rebuild and two shells share it.
4. The default plugins' skills load in Claude Code and in Codex.
5. `git push` over SSH works through the forwarded agent.
6. VS Code "Rebuild Container" keeps tools, state and history.
7. Two containers share one Claude and one Codex state profile at once:
   parallel sessions, login and settings stay intact.

## 8. Open questions

- Whether VS Code "Rebuild Container" is enough, or `profile:rebuild` is needed.
- Whether `FORCE_AUTOUPDATE_PLUGINS` keeps Claude's plugin auto-update working
  under `DISABLE_UPDATES` at runtime, and whether Codex updates plugins on its
  own (its binary names `plugins-marketplace-auto-upgrade`).
- Whether Codex enforces `allowed_sandbox_modes` and reads
  `/etc/codex/config.toml` below user configuration.
- How `mise lock --global` resolves a changed declaration, and whether
  `mise install --locked` runs offline.
- Whether mise reads tasks from `MISE_GLOBAL_CONFIG_FILE`, whether `-C /`
  applies before configuration loads, and the exact name of the task
  auto-install setting.
- The plugin list command and JSON shape per CLI, disabled plugins included.
- Where Claude keeps its credentials inside `CLAUDE_CONFIG_DIR`.
- The `vscode-remote://dev-container+…` URI form on Linux and WSL2.
- How Docker Desktop reports the socket's group inside a container.
- Whether Docker copies mount-point ownership into an empty external volume on
  every supported topology.
