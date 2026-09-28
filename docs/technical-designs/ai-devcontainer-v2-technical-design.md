---
ticket: none
date: 2026-09-28
status: approved
spec: ../specs/2026-09-28-ai-devcontainer-v2-design.md
branch: feature/ai-devcontainer-v2
architect: LGTM
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
| Shared Compose file | Compose file | new | `.devcontainer/compose.yaml` | the `workspace` service: `build` with context `.` (the `.devcontainer/` directory, since Compose resolves it against this first file) tagged `aidc-workspace:local`, `init: true`, user `vscode`, entrypoint, keep-alive command, fixed policy and tool environment, read-only mount of `.devcontainer/` at `/opt/aidc/devcontainer` | anything profile-specific |
| Generated profile files | local files | new | `.local/<p>/compose.yaml` (the profile's Compose fragment) and `.local/<p>/.devcontainer/devcontainer.json` | the profile's project name, `hostname: <p>`, build arguments, volume names, mounts, environment and socket opt-in | anything versioned; secrets |
| Workspace image | Dockerfile | new | `.devcontainer/Dockerfile`, `FROM debian:trixie-slim`, context `.devcontainer/` | OS packages (`zsh`, `git`, `curl`, `gnupg`, `ca-certificates`, `openssh-client`, `jq`, `util-linux`, `procps`, `locales`), `docker-ce-cli` with the Compose plugin and no daemon, mise pinned by version and SHA-256, user `vscode` built with the host UID and GID, volume mount points owned by `vscode`, policy files, launchers, scripts, a minimal `zshrc` (§3.6) | container tools; agent state |
| Policy files | image assets | new | `.devcontainer/policy/` → `/etc/claude-code/managed-settings.json`, `/etc/codex/requirements.toml`, `/etc/codex/config.toml` | CLI self-update off, Claude HTTPS marketplace clones, Codex file credentials, Codex default sandbox and approval mode | user preferences; files in agent state |
| Entrypoint | container executable | new | `.devcontainer/bin/aidc-entrypoint` → `/usr/local/lib/aidc/bin/` | the start sequence (§3.4), the init log and the init result marker, handing over to the keep-alive command whatever happened | tool and plugin logic |
| Container tasks | mise tasks + bash script | new | `[tasks]` of `.devcontainer/mise.toml` (`aidc:sync`, `aidc:update`, `aidc:status`); `.devcontainer/bin/aidc-tools` shared with the entrypoint; invoked as `MISE_TASK_RUN_AUTO_INSTALL=false mise -C / run aidc:<task>`, so the neutral directory is chosen before any configuration loads and no auto-install bypasses the tools lock (*to verify*, §8) | the tools lock, copying the config into the tools volume, `mise install`/`mise upgrade`, the status report | plugin updates |
| Agent CLI launchers | container executables | new | `.devcontainer/launchers/claude`, `.../codex` → `/usr/local/lib/aidc/launchers/`, first on `PATH` | resolving each CLI from the tools config copy; Codex without the managed daemon | installing anything; CLI state |
| Plugin catalog and script | versioned data + bash script | new | `.devcontainer/plugins.json`; `.devcontainer/bin/aidc-plugins` | the default marketplaces and plugins per agent; plugin initialization and its marker, under the state lock | plugin updates, removal, rollback |
| Profile tools volume | named volume | new | `aidc-tools-<p>` at `/opt/aidc/tools` | installations, the tools config copy with `mise.lock`, the tools lock, the init log and result marker | agent state |
| Profile example | versioned files | new | `examples/profile/profile.env` | fictional sample values, state fields empty, socket off | real names or values |
| Ignore files | versioned file | new | `.gitignore` | excluding `profiles/`, `projects/` and `.local/` from Git; the image context is `.devcontainer/` alone, so none of them reaches a build | a guarantee against a force-add or a custom context |

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

Names match `^[a-z0-9][a-z0-9_-]*$` and are neither `locks` nor `active-profile`. The variables override `user.name`,
`user.email` and `core.sshCommand` of the copied Git configuration
(*verified*, Git 2.43.0, probe 2026-09-28). The generator escapes `$` as `$$`,
because Compose interpolates the fragment.

### 3.2 Volumes and mounts

| source | target | environment |
|---|---|---|
| `aidc-tools-<p>` | `/opt/aidc/tools` | `MISE_DATA_DIR=/opt/aidc/tools/mise`, `MISE_GLOBAL_CONFIG_FILE=/opt/aidc/tools/mise.toml` |
| `aidc-claude-<PROFILE_CLAUDE>` | `/home/vscode/.claude` | `CLAUDE_CONFIG_DIR=/home/vscode/.claude` |
| `aidc-codex-<PROFILE_CODEX>` | `/home/vscode/.codex` | `CODEX_HOME=/home/vscode/.codex` |
| `aidc-shell-<PROFILE_SHELL>` | `/home/vscode/.local/state/shell` | `HISTFILE=/home/vscode/.local/state/shell/zsh_history` |
| `projects/<p>/` (bind) | `/workspaces/<p>` | — |
| `.devcontainer/` (bind, read-only) | `/opt/aidc/devcontainer` | — |

Host tasks create the named volumes with `docker volume create`; the fragment
declares them `external`, so no Compose command removes shared state. The
generator writes every bind source as an absolute host path, because Compose
resolves relative paths against the first file's directory. An empty volume
takes the ownership of the image's mount point (*to verify*, AC2). `CLAUDE_CONFIG_DIR` holds `.claude.json` (*verified*, spike 2026-09-26);
Codex keeps `auth.json` in `CODEX_HOME` under the file store (*verified*,
spike 2026-09-27, after a keyring login failed). The fragment also sets
`hostname: <p>`, so the profile name identifies the container from inside
the shell (developer ruling, first VS Code use).

### 3.3 Tools config copy and lock

All steps run as `vscode`, from `/`, with inherited `MISE_*` variables removed
and the two fixed ones set again (the v1 `mise-isolation.sh` allowlist), under
the tools lock `/opt/aidc/tools/.lock`. *Copy* always means: write
`/opt/aidc/devcontainer/mise.toml` to a temporary file in the volume, then rename
it over `mise.toml`, so an interrupted copy leaves the old file or none.

- start: copy when no copy exists; run `mise lock --global --platform
  <container platform>` when no `mise.lock` exists (so a first start that
  failed offline locks again at the next start); then `mise install --locked`;
- `aidc:sync`: copy, `mise lock --global --platform <container platform>`,
  `mise install --locked`;
- `aidc:update`: as `aidc:sync` (with `mise lock --global --platform
  <container platform>`), then `mise upgrade`.

The lock in the profile tools volume serves only this container, so an asset
missing for another architecture must not block it; `<container platform>` is
`linux-x64` or `linux-arm64`, from `uname -m`.

When `mise lock --global` fails, for example because one declared tool cannot
be resolved, no `mise.lock` is written and `mise install --locked` would refuse
every tool. The step then runs plain `mise install`, which installs the tools
it can resolve (honouring an existing `mise.lock`), names the failure and exits
non-zero (*verified* on mise 2026.9.15, the pinned version, plan-adversary probes
2026-09-28; 2026.9.12 instead writes a partial lock and exits 0).

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

Catalog content (public marketplaces; IDs from the v1 catalog, the
Codex IDs *to verify*):

```json
{ "claude": { "marketplaces": ["anthropics/claude-plugins-official",
                               "obra/superpowers-marketplace",
                               "missing-bits/claude-plugins"],
              "plugins": ["superpowers@claude-plugins-official",
                          "elements-of-style@superpowers-marketplace",
                          "working-process@missing-bits",
                          "project-memory@missing-bits"] },
  "codex":  { "marketplaces": ["anthropics/claude-plugins-official",
                               "obra/superpowers-marketplace"],
              "plugins": ["superpowers@claude-plugins-official",
                          "elements-of-style@superpowers-marketplace"] } }
```

`aidc-plugins init <agent>`, run through the launchers:

1. If `<state>/.aidc/plugins-initialized` exists, stop.
2. Take the state lock `<state>/.aidc/lock`, waiting; check the marker again.
3. Read the agent's entry from `/opt/aidc/devcontainer/plugins.json`.
4. Run `marketplace list --json`. Add each catalog marketplace whose
   repository is not listed: `claude plugin marketplace add <owner/repo>
   --scope user` or `codex plugin marketplace add <owner/repo>`. Claude lists a
   shorthand as `{name, source: "github", repo}`; Codex's
   `plugin marketplace list --json` returns
   `{marketplaces: [{name, root, marketplaceSource: {sourceType, source}}]}`
   with a shorthand stored as `https://github.com/<owner/repo>.git`
   (*verified*, probes 2026-09-28).
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
result, the launcher exits non-zero and names the documented
`aidc:sync` invocation of §2.

The `codex` launcher reuses the tested v1 logic: `--no-daemon` for the
interactive CLI (no subcommand, `resume`, `fork`) unless `--remote` is given;
refusal of `agents`, `app-server daemon|proxy` and `remote-control` (*verified*,
0.157.1 source and spike 2026-09-27: without the flag a TUI start copied the
binary into `CODEX_HOME/packages/` and left a daemon running). The tables in
`codex-cli.sh` are those verified for 0.157; there is no version guard, and a
newer Codex is the accepted risk the spec states.

### 3.7 Policy keys

| file | key | purpose | evidence |
|---|---|---|---|
| Claude managed settings | `env.DISABLE_UPDATES = "1"` | blocks `claude update` and auto-update | *verified*, spike 2026-09-26 |
| Claude managed settings | `env.CLAUDE_CODE_PLUGIN_PREFER_HTTPS = "1"` | clones `owner/repo` marketplaces over HTTPS without the SSH probe | Claude Code docs (host-marketplace); name present in the 2.1.283 package |
| Codex `requirements.toml` | `check_for_update_on_startup = false` | no update check | *verified*, spike 2026-09-27 |
| Codex `requirements.toml` | `cli_auth_credentials_store = "file"` | `auth.json` in `CODEX_HOME` | *verified*, spike 2026-09-27 |
| Codex `/etc/codex/config.toml` | `sandbox_mode = "danger-full-access"`, `approval_policy = "on-request"` | container as the boundary, as defaults below user configuration | *verified*, Task 6 probe P6.3 2026-09-28 |

The shared Compose file sets `DISABLE_UPDATES` in the environment too; the
HTTPS key lives in managed settings only. Plugin updates are left to each
CLI's default behaviour (developer ruling 2026-09-28): source inspection of
Claude Code 2.1.283 suggests `DISABLE_UPDATES` also skips its plugin
auto-update, which is accepted. No allowed-sandbox-modes list is set: Codex
0.157.1 rejects one without `read-only` (probe P6.3).

Codex's sandbox does not start under Docker's default seccomp and AppArmor
profiles (*verified*, v1 plan 3 evidence 2026-09-28), hence the container as
boundary.

### 3.8 Generated files and VS Code

`.local/<p>/.devcontainer/devcontainer.json`, written with `jq`:

- `name: aidc-<p>`, `service: workspace`, `workspaceFolder: /workspaces/<p>`,
  `remoteUser: vscode`;
- `dockerComposeFile`: the absolute path of `.devcontainer/compose.yaml`, then
  `../compose.yaml`;
- `overrideCommand: false`, so the entrypoint and command stay (*to verify*);
- `updateRemoteUserUID: false`, because the build already uses the host UID.

`.local/<p>/compose.yaml`, written as JSON (valid YAML): `name: aidc-<p>`,
`hostname: <p>`, build arguments `USER_UID` and `USER_GID`, the volumes and mounts of §3.2
except the read-only `.devcontainer/` bind, which the shared Compose file owns,
the environment of §3.1, and the socket bind when opted in. The Dev
Containers CLI takes the project name from `COMPOSE_PROJECT_NAME`, then `.env`
in its working directory, then `name:` (*verified*, `devcontainers/cli`
source). Accepted risk: a VS Code started with `COMPOSE_PROJECT_NAME` set
resolves another project.

`profile:code` runs `devcontainer up --workspace-folder .local/<p>` (reuses a
running container; *verified*, `findComposeContainer`), then `code
--folder-uri vscode-remote://dev-container+<hex of the host path of
.local/<p>>/workspaces/<p>`. Under WSL (`WSL_DISTRO_NAME` set) the host path is
`wslpath -w`'s `\\wsl.localhost\...` form, because VS Code reads it as a
Windows path (*verified*, developer run 2026-09-28, after probe P2.1 showed the
Linux path fails). "Rebuild Container" reads the same files.

### 3.9 Implementation details

- **Script locations.** `aidc-entrypoint`, `aidc-tools`, `aidc-plugins` and
  the launchers ship in the image under `/usr/local/lib/aidc/`. The `[tasks]`
  entries call them by absolute path. A script change therefore needs an image
  rebuild, while a change to `mise.toml` or `plugins.json` needs only
  `aidc:sync` or the next start.
- **`aidc:status`** reads files only, so it works offline:
  - `init.status` and the tail of `init.log`;
  - the declared tools, read with `mise config get --file
    /opt/aidc/tools/mise.toml tools`, each shown with its installed version from
    `mise ls` or as `missing` (offline, `mise ls` omits an unresolvable `latest`
    tool, *verified* plan-adversary probe 2026-09-28);
  - for each agent, whether its plugin marker exists.
  It calls no agent CLI.
- **`profile:code` order.** It validates the name, parses and validates
  `profile.env`, then takes the host profile lock, generates `.local/<p>/`, runs
  `devcontainer up`, writes `.local/active-profile`, then opens VS Code. A
  failure before generation changes no file. This is the command that
  enforces AC1's `profile.env` rules; `profile:new` validates only the name.
  With no argument and no active profile, it exits non-zero and lists
  `profiles/`.
- **`profile:remove`** takes the lock and runs `docker compose -p aidc-<p>
  down` against the generated files, falling back to the
  `com.docker.compose.project=aidc-<p>` label when those files are gone. It
  then removes `aidc-tools-<p>` and `.local/<p>/`, and clears
  `.local/active-profile` if that file names `<p>`.
- **`profile.env` syntax.** Only whole-line `#` comments are allowed. Values
  are literal: quotes are kept as characters and no expansion takes place. A
  `DOCKER_SOCKET` value other than `on` or `off` is rejected.
- **Shell.** The login shell of `vscode` is zsh. The minimal config is
  `/etc/zsh/zshrc` in the image. It runs `mise activate zsh`, then registers
  the launcher `chpwd` and `precmd` hooks and sets the history options.
- **Host tools** in the root `mise.toml`, pinned: the Dev Containers CLI,
  `jq`, `bats`, `shellcheck`, `shfmt`. Docker and `flock` are host
  prerequisites.
- **Reused v1 files** (branch `feature/ai-devcontainer`):
  `.devcontainer/lib/mise-isolation.sh`, which removes every inherited
  `MISE_*` variable and sets only `MISE_DATA_DIR` and
  `MISE_GLOBAL_CONFIG_FILE`, and `.devcontainer/launchers/codex` with
  `lib/codex-cli.sh` and `tests/unit/container/launchers.bats`, each adapted to
  the v2 paths.
- **A CLI installed later.** When a CLI was missing at start and `aidc:sync`
  installs it afterwards, plugin initialization runs at the next container
  start. `aidc:sync` does not trigger it.

## 4. State

| record | home | written by | read by | lifecycle |
|---|---|---|---|---|
| Tool installations | `aidc-tools-<p>`: `mise/` | Container tasks, Entrypoint (through mise) | Agent CLI launchers, Container tasks | until `profile:remove`; `mise upgrade` may prune old versions; project runtimes installed from a project's `mise.toml` land here too, unlocked, and go with the volume |
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
interactive CLI sessions; a project `mise install` into the shared
`MISE_DATA_DIR`; a launcher during `aidc:update` (its running binary
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
including a partial run and its retry, and AC8's second half: a default removed
or disabled after the marker exists stays so at the next start, because
initialization stops at the marker.

**Docker integration tests**: two profiles (AC2); `cd project && claude`
in a project declaring its own `claude` (AC3); versions after recreation
offline (AC4); `aidc:status` offline from inside an untrusted project
(AC10); policy (AC6); `profile:remove` (AC11); the interrupted first plugin
install: stop the container after the first install, start it again, expect
every default and the marker (AC9); and one cross-container `flock` on a
shared volume: a second container waits while the first holds it and gets it
once the holder's container stops.

Also: AC5 with one uninstallable tool declared; AC12 (`git check-ignore`, the
build context listing, no private key file, `GIT_*` in a test commit, the
socket only with the opt-in).

**Manual VS Code smoke checklist**:

1. Project mise activation works in the VS Code terminal.
2. `command -v claude codex` shows the launchers first, also inside a project.
3. History persists across a rebuild and two shells share it.
4. The default plugins' skills load in Claude Code and in Codex.
5. `git push` over SSH works through the forwarded agent.
6. VS Code "Rebuild Container" keeps tools, state and history.
7. Two containers share one Claude and one Codex state profile at once:
   parallel sessions, login and settings stay intact.
8. A login survives a rebuild and `profile:remove` followed by `profile:code`.
9. With the container on no network, VS Code still attaches (AC10).

## 8. Open questions

- Whether VS Code "Rebuild Container" is enough, or `profile:rebuild` is needed.
- How `mise lock --global` resolves a changed declaration, and whether
  `mise install --locked` runs offline.
- Whether mise reads tasks from `MISE_GLOBAL_CONFIG_FILE`, whether `-C /`
  applies before configuration loads, and the exact name of the task
  auto-install setting.
- The plugin list command and JSON shape per CLI, disabled plugins included.
- Where Claude keeps its credentials inside `CLAUDE_CONFIG_DIR`.
- How Docker Desktop reports the socket's group inside a container.
- Whether Docker copies mount-point ownership into an empty external volume on
  every supported topology.

## Review rounds

Reviewed with the design spec in its architect round 1 (2026-09-28, LGTM); the findings and fixes are recorded in the spec's Review rounds section.

Integrity audit 2026-09-28 (consumption gate, with the spec): 8 defects and 14 implementer questions, all disposed in place — §3.3 locks again when `mise.lock` is missing, §3.5 carries the real catalog and the Codex list shape, §3.7 and §3.8 wording, and the new §3.9 answers the implementer questions.

### 2026-09-28 — fix from docs/plans/2026-09-28-ai-devcontainer-v2-plan.md

- fixed 2026-09-28 — `profile:code` took the host lock before validating `profile.env`, which creates a file and breaks AC1; license: spec AC1 (change no file); §3.9 now validates first (Codex co-author review of the plan).
- fixed 2026-09-28 — a failed `mise lock --global` left nothing installable, the Codex version guard compared the pin with itself, and the names `locks`/`active-profile` collided with `.local/` entries (plan-adversary round 1, I2, M8, M7); ruling: 2026-09-28 (developer): plain `mise install` after a failed lock; no Codex guard, both CLIs default to latest with the table risk accepted; the two names rejected.
- fixed 2026-09-28 — the lock-failure fallback was verified on mise 2026.9.15 only (plan-adversary round 2, I1); license: the probe; §3.3 names the version the image pins.
- fixed 2026-09-28 — offline, `mise ls` omits unresolvable `latest` tools, so `aidc:status` could not show the agent CLIs (plan-adversary round 3, I1); ruling: 2026-09-28 (developer); status lists the declared tools from the copy and marks missing ones.
- fixed 2026-09-28 — a lock across all platforms failed when a declared version lacked another architecture's asset (implementation Task 4, P4.4); ruling: 2026-09-28 (developer); locks cover the container platform only.
- fixed 2026-09-28 — Codex 0.157.1 rejects `allowed_sandbox_modes` without `read-only`, and forcing Claude's plugin auto-update contradicts leaving updates to the CLIs (Task 6 probes P6.3/P6.4); ruling: 2026-09-28 (developer); both keys dropped, `gnupg` added for the apt key check.
- fixed 2026-09-28 — the dev-container folder URI fails under WSL (Task 6 probe P2.1); license: the plan's pre-agreed P2.1 fallback; `profile:code` opens `.local/<p>` and asks for "Reopen in Container".
- fixed 2026-09-28 — opening `.local/<p>` and asking for "Reopen in Container" left the developer in the generated folder; license: developer run with the `wslpath -w` host path (window opened in the container); `profile:code` opens the container directly.
- fixed 2026-09-28 — developer ruling after first VS Code use: the container user is `vscode` (home `/home/vscode`, replacing `dev` everywhere, including the §3.2 mount targets); the generated fragment sets `hostname: <p>`; the image installs oh-my-zsh at a pinned commit under `/usr/share/oh-my-zsh`, loaded by `/etc/zsh/zshrc` with the default theme and the `git` plugin, updates disabled and its cache under `$HOME/.cache/oh-my-zsh`; the launcher PATH hooks stay registered after mise's and oh-my-zsh's.
