---
ticket: none
date: 2026-09-28
status: draft
spec: ../specs/2026-09-28-ai-devcontainer-v2-design.md
technical-design: ../technical-designs/ai-devcontainer-v2-technical-design.md
branch: feature/ai-devcontainer-v2
base: develop
---

# AI Devcontainer v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v2 development container: host tasks that generate and start one
container per environment profile, an image with policy, launchers, container tasks and
plugin initialization, plus the tests and documents that prove the spec's twelve acceptance
criteria.

**Architecture:** Bash host tasks (root `mise.toml`, `tasks/host/`) validate a profile,
write `.local/<p>/` and call `devcontainer up`. The image (`.devcontainer/`) ships an
entrypoint, the `aidc-tools` and `aidc-plugins` scripts and the `claude`/`codex` launchers;
container tools live in the profile tools volume. The technical design (TD) defines every
contract; this plan orders the work and names the tests. It does not restate the contracts.

**Tech Stack:** Bash, bats, shellcheck, shfmt, jq, mise, Docker Compose, Dev Containers CLI.

**Annotations:** the design spec does not set `decisions: registered`, so under the
lifecycle rule this plan carries no `**Realizes:**` lines. Each task lists the spec ACs and
TD sections it covers instead.

## Global Constraints

- Terms follow `docs/domain/glossary.md`; `_Avoid_` terms stay out of code, messages and
  documents.
- KISS/YAGNI: add nothing the spec's Out of scope list names (no `aidc` front, snapshots,
  startup record, bounded waits, override validator, plugin updates, SSH relay). Report and
  retry; no custom transactions (TD §6).
- Names match `^[a-z0-9][a-z0-9_-]*$`; an invalid name changes no file or Docker object
  (spec Profiles, AC1).
- `profiles/`, `projects/`, `.local/` stay out of Git and out of the image context
  (`.devcontainer/` only). Versioned examples are fictional.
- No private key enters the image or container; SSH only through the forwarded host agent.
- Exactly three `flock` locks (TD §5); no script holds the tools lock and a state lock at
  once.
- Every container-side mise call runs from `/` with the v1 isolation: inherited `MISE_*`
  removed, only `MISE_DATA_DIR=/opt/aidc/tools/mise` and
  `MISE_GLOBAL_CONFIG_FILE=/opt/aidc/tools/mise.toml` set (TD §3.3).
- Integration tests read `GITHUB_TOKEN` from the host and pass it to containers only as an
  environment variable, never in logs, build arguments or persisted files.
- Every task runs `mise run check`; from Task 7 on, `mise run test:integration` too.
  Tasks 2 and 6 run only their probes and smoke steps against Docker.
  Report actual results; never claim an untested integration.
- Commits: one-line Conventional Commit, no body, no trailers.
- Probe results go to `docs/verification/acceptance-matrix.md` (Task 8); a probe whose
  fallback needs more than the stated one stops the task and goes to the developer. Design
  documents are not edited from this plan.

**Needs Docker:** Tasks 6 and 7 (Task 2's P2.2 probe too). **Needs network:** Tasks 1 (host
tools), 4–7 (mise, CLI and marketplace downloads). Tasks 2, 3 and 8 run offline once host
tools are installed.

---

### Task 1: Repository tooling and checks

**Goal:** A working `mise run check` on an empty tree, the ignore rules, and the bats
helpers every later task uses.

**Files:**
- Create: `mise.toml`, `.gitignore`, `.editorconfig`, `.shellcheckrc`,
  `tools/shell-files.sh`, `tests/helpers/common.bash`, `tests/unit/host/repository.bats`

**Covers:** spec Host tasks (repository tasks), Privacy; AC12 (ignore half); TD §2 Ignore
files row, §3.9 Host tools.

**Reuse:** copy v1 `tools/shell-files.sh`, `.editorconfig`, `.shellcheckrc` and the
`fmt`/`lint`/`test` task shapes from v1 `mise.toml`
(`/home/vircung/code/missing-bits/ai-devcontainer-wt`). Take `aidc_test_repo` and the
`assert_*` helpers from v1 `tests/helpers/common.bash`; drop hadolint and yq (not in TD
§3.9).

- [ ] **Step 1: Write the failing tests** in `repository.bats`:
  - `git check-ignore covers profiles, projects and .local` — `git check-ignore -q` succeeds
    for `profiles/x/profile.env`, `projects/x/a`, `.local/x/compose.yaml`.
  - `the image context holds none of the private directories` — the compose file's
    `build.context` is `.` relative to `.devcontainer/` (skipped until Task 6 creates it),
    and no `profiles`, `projects` or `.local` path exists under `.devcontainer/`.
  - `host tools are pinned` — every `[tools]` entry in `mise.toml` has a full version (no
    `latest`, no bare major).
- [ ] **Step 2: Run** `bats tests/unit/host/repository.bats`. Expected: FAIL (no
      `.gitignore`, no `mise.toml`).
- [ ] **Step 3: Implement.** Root `mise.toml` sets `min_version = "2026.9.15"` (a floor:
      mise cannot pin itself exactly; Task 4's probes run on exactly 2026.9.15) and pins `node` (required by the npm backend of
      the Dev Containers CLI), `npm:@devcontainers/cli`, `jq`, `bats`, `shellcheck`,
      `shfmt`; `[task_config] includes = ["tasks/host"]`; tasks `fmt`, `fmt:check`, `lint`,
      `test` (`bats --recursive tests/unit`), `test:integration` (fails with a clear message when
      `docker info` fails; bats `tests/integration`), `check` (depends on `fmt:check`,
      `lint`, `test`). `.gitignore`: `/profiles/`, `/projects/`, `/.local/`.
- [ ] **Step 4: Run** `mise install && mise run check`. Expected: PASS.
- [ ] **Step 5: Commit** `chore: add repository tooling and checks`

### Task 2: Host tasks and the generator

**Goal:** `profile:new`, `profile:code` and `profile:remove`, with the `profile.env` parser
and the generator of `.local/<p>/`.

**Files:**
- Create: `tasks/host/lib/common.sh`, `tasks/host/lib/names.sh`,
  `tasks/host/lib/profile_env.sh`, `tasks/host/lib/generate.sh`, `tasks/host/lib/lock.sh`;
  `tasks/host/profile/new`, `tasks/host/profile/code`, `tasks/host/profile/remove`;
  `examples/profile/profile.env`
- Test: `tests/unit/host/names.bats`, `tests/unit/host/profile_env.bats`,
  `tests/unit/host/generate.bats`, `tests/unit/host/profile_tasks.bats`

**Covers:** AC1; AC7 (volume naming); AC11 (with stubbed Docker); AC12 (`GIT_*` and socket
opt-in in the fragment). TD §3.1, §3.2 (names, absolute bind sources, `external`), §3.8,
§3.9 (`profile:code` order, `profile:remove`, `profile.env` syntax), §5 lock 1.

**Reuse:** v1 `tasks/host/lib/profile_env.sh` (parser loop; replace the key set with TD
§3.1), `.devcontainer/lib/naming.sh` (name rule), and the task layout of
`tasks/host/profile/new`. Use plain `flock` with no timeout instead of v1's bounded
`lock.sh`.

**Interfaces:** produces the files of TD §3.8 and the volume names of TD §3.2; Task 7 drives
these tasks with `AIDC_ROOT` pointing at a test copy of the repository (v1 `aidc_test_repo`
pattern).

- [ ] **Step 1: Probe** (P2.1, the URI form, runs in Task 6 Step 5, where a container
      first exists):
  - *P2.2, TD §8 socket group:* with the opt-in, compare `stat -c %g /var/run/docker.sock`
    on the host with `id -G` inside (Docker Engine and, when available, Docker Desktop).
    Fallback: keep `group_add` of the host GID and document the Desktop case in the README
    as a known case.
- [ ] **Step 2: Write the failing tests** (Docker, `devcontainer` and `code` stubbed on
      `PATH`, each stub logging its arguments):
  - `names.bats`: `demo`, `a-1_b` valid; `Bad/Name`, `-x`, `` (empty), `Demo`, `..`,
    `locks`, `active-profile` rejected.
  - `profile_env.bats`: comments and blank lines ignored; unknown key rejected with its line
    number; duplicate key rejected; empty value is unset; `PROFILE_CLAUDE=Bad` rejected;
    `DOCKER_SOCKET=yes` rejected; quotes kept literally; a `$` value survives; a trailing `# x` after a
    value is part of the value.
  - `generate.bats`: fragment is valid JSON with `name: aidc-demo`, build args
    `USER_UID`/`USER_GID` equal `id -u`/`id -g`; volumes `aidc-tools-demo`,
    `aidc-claude-demo`, `aidc-codex-demo`, `aidc-shell-demo` all `external`; with
    `PROFILE_CLAUDE=team` the Claude volume is `aidc-claude-team`; bind sources are
    absolute; `$` in a `GIT_*` value is written `$$`; `GIT_*` set appear as environment,
    unset ones are absent; socket bind and `group_add` only with `DOCKER_SOCKET=on`;
    `devcontainer.json` carries the TD §3.8 fields and the absolute shared compose path
    first.
  - `profile_tasks.bats`: `profile:new demo` creates `profiles/demo/profile.env` (the
    example) and `projects/demo/`; `profile:new Bad/Name` exits non-zero and creates
    nothing; `profile:new demo` twice refuses the second time and keeps the file;
    `profile:code` with an unknown key or an invalid state profile name exits non-zero,
    and a before/after listing of the whole test repository (`find`, including
    `.local/`) is identical: no `.local/demo/`, no lock file, no `active-profile`, and no
    `docker`/`devcontainer` call; `profile:code demo` runs `docker volume create` for the four
    volumes, `devcontainer up --workspace-folder .local/demo`, then writes
    `.local/active-profile`, then calls `code`; `profile:code` alone uses the active
    profile, and without one exits non-zero listing `profiles/`; `profile:remove ../x`,
    `profile:remove Bad/Name` and `profile:remove ''` exit non-zero with an identical
    before/after `find` listing and no `docker` call; `profile:remove demo` calls
    `docker compose -p aidc-demo down` and `docker volume rm aidc-tools-demo`, removes
    `.local/demo/`, clears `active-profile` naming `demo`, keeps `profiles/demo/` and
    `projects/demo/`, never removes a state volume, and succeeds when run again with nothing
    left (label fallback used).
- [ ] **Step 3: Run** `mise run test`. Expected: FAIL.
- [ ] **Step 4: Implement** the libraries and tasks. Generate both files with `jq`. The lock
      file is `.local/locks/<p>.lock`; `profile:code` validates the name and `profile.env`
      before it creates the lock directory or takes the lock (TD §3.9).
- [ ] **Step 5: Run** `mise run check`. Expected: PASS.
- [ ] **Step 6: Commit** `feat: add profile host tasks and generator`

### Task 3: Agent CLI launchers and shell

**Goal:** `claude` and `codex` launchers that resolve the CLI from the tools config copy,
the Codex daemon guard, and the shell files that keep the launchers first on `PATH`.

**Files:**
- Create (adapted copies): `.devcontainer/lib/mise-isolation.sh`,
  `.devcontainer/lib/codex-cli.sh`, `.devcontainer/launchers/codex`,
  `tests/unit/container/launchers.bats`
- Create: `.devcontainer/lib/common.sh` (trimmed from v1 to `aidc::die`, `aidc::warn`,
  `aidc::info`; no `bounds.sh`), `.devcontainer/launchers/claude`, `.devcontainer/shell/zshrc`,
  `.devcontainer/shell/aidc-path.sh`, `tests/helpers/stub-mise.bash`

**Covers:** AC3 (unit half); AC6 (daemon half, unit). TD §3.6, §3.9 (Reused v1 files,
Shell), spec Mise scopes.

**Reuse (TD §3.9):** copy from `/home/vircung/code/missing-bits/ai-devcontainer-wt`:
`.devcontainer/lib/mise-isolation.sh` (set the global config to `/opt/aidc/tools/mise.toml`,
not `current/`), `.devcontainer/lib/codex-cli.sh` (tables unchanged),
`.devcontainer/launchers/codex` (replace the snapshot resolution with `mise which codex`
from `/`), `tests/unit/container/launchers.bats` (drop the snapshot and `claude-vscode`
cases). Copy v1 `.devcontainer/profile.d/aidc-path.sh` as `shell/aidc-path.sh`.

**Interfaces:** produces `/usr/local/lib/aidc/launchers/{claude,codex}` and
`/usr/local/lib/aidc/lib/*.sh`; Task 4 and Task 5 source `mise-isolation.sh`; Task 6 copies
`shell/` into the image.

- [ ] **Step 1: Write the failing tests** (a stub `mise` answers `which`):
  - `claude passes arguments, directory and environment unchanged` — stub CLI records
    `$PWD`, `$@` and a sentinel variable.
  - `the launcher resolves from / whatever the caller's directory` — stub `mise` records its
    `$PWD` as `/`, and every inherited `MISE_*` but the two fixed ones is absent.
  - `no resolved CLI exits non-zero and names the aidc:sync invocation`.
  - v1 codex cases kept: `--no-daemon` added to the interactive CLI, `resume`, `fork`; not
    added with `--remote` or `--no-daemon`; option values and words after `--` never read as
    flags; `agents`, `app-server daemon|proxy`, `remote-control` refused; other commands
    pass through.
  - No version guard: drop v1's qualification cases and constant (TD §3.6).
  - `zshrc registers the launcher hooks after mise's` — skipped when `zsh` is absent; the
    launcher directory is overridable for the test; in `zsh -f`, source the file with a
    stub `mise activate` that prepends a directory holding a fake `claude`; after `cd` and a
    `precmd` run, `command -v claude` is the launcher; `HISTSIZE`/`SAVEHIST` are 50000 and
    `SHARE_HISTORY` is set.
- [ ] **Step 2: Run** `bats tests/unit/container/launchers.bats`. Expected: FAIL.
- [ ] **Step 3: Implement** the launchers and shell files.
- [ ] **Step 4: Run** `mise run check`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add agent CLI launchers and shell integration`

### Task 4: Container tasks and the entrypoint

**Goal:** `aidc-tools` (copy, lock, install, upgrade, status), the
`aidc:sync`/`aidc:update`/`aidc:status` tasks and the entrypoint's start sequence.

**Files:**
- Create: `.devcontainer/mise.toml`, `.devcontainer/bin/aidc-tools`,
  `.devcontainer/bin/aidc-entrypoint`
- Test: `tests/unit/container/tools.bats`, `tests/unit/container/entrypoint.bats`

**Covers:** AC5 (unit), AC10 (status half); spec Tools, Container tasks. TD §3.3, §3.4, §3.9
(`aidc:status`, a CLI installed later), §4 rows for the tools volume, §5 lock 2, §6.

**Reuse:** v1 `.devcontainer/mise.toml` `[tools]` pins (full aqua keys:
`aqua:anthropics/claude-code = "latest"`, `aqua:openai/codex = "latest"`, plus the small
tools);
v1 `.devcontainer/bin/aidc-entrypoint` and `aidc-tools` as reference only (their snapshot
logic is out of scope).

**Interfaces:** `aidc-tools start|sync|update|status`, called by absolute path from the
`[tasks]` of `.devcontainer/mise.toml` and by the entrypoint. The entrypoint calls
`aidc-plugins init <agent>` from Task 5 (stubbed here). Marker format: `running <UTC time>`,
`ok <time>`, `failed <time>: <steps>`.

- [ ] **Step 1: Probes** on the host with mise 2026.9.15 (the image pin, Task 6), in a temp `MISE_DATA_DIR`
      (network):
  - *P4.1, TD §8 tasks from `MISE_GLOBAL_CONFIG_FILE`:* a `[tasks]` entry in that file is
    listed by `mise tasks` from `/`. Fallback: document `/usr/local/lib/aidc/bin/aidc-tools
    <task>` as the invocation; the `[tasks]` entries stay as a convenience.
  - *P4.2, `-C /` before configuration loads:* from a directory holding an untrusted
    `mise.toml`, `mise -C / run <task>` neither warns about trust nor reads that file.
    Fallback: document `cd / && mise run aidc:<task>`.
  - *P4.3, auto-install setting name:* confirm `MISE_TASK_RUN_AUTO_INSTALL` in `mise
    settings ls` (or the docs of the pinned version). Fallback: use the name the pinned
    version documents; with none, drop the variable and state the risk in the README.
  - *P4.4, TD §8 `mise lock --global` on a changed declaration:* lock `ripgrep = "14"`,
    change to `"13"`, lock again; record the picked version. Fallback: none built; if the
    lock keeps a version outside the new declaration, report it to the developer before
    continuing.
  - *P4.5, `mise install --locked` offline:* with everything installed, run it under
    `unshare -rn` (or `docker run --network none` in Task 7). Fallback: the start step runs
    `mise install --locked` only when `mise ls --missing` lists something.
- [ ] **Step 2: Write the failing tests** (stub `mise` logs calls and cwd; `AIDC_TOOLS_DIR`
      and `AIDC_DEVCONTAINER_DIR` overridable):
  - `start copies when no copy exists, locks when no mise.lock exists, then installs
    locked`; `start with a copy and a lock only installs` (never `upgrade`, never re-copy).
  - `sync copies, locks and installs`; `update runs the same then mise upgrade`.
  - `an interrupted copy leaves the old file` — stub `mv` fails; the old `mise.toml` is
    unchanged and no temp file is left.
  - `a failing install exits non-zero and names the failed tools` while the others were
    requested; `a failing mise lock --global falls back to plain mise install` (TD §3.3).
  - `every mise call runs from / with only the two MISE_* variables`.
  - `the tools lock is taken` — a held `flock` on `.lock` makes `sync` wait (checked with
    `timeout 1`, expecting status 124).
  - `status reads files only` — prints `init.status`, the log tail, every declared tool of
    the copy (`mise config get --file … tools`) with its `mise ls` version or `missing`,
    and, per agent, marker present/absent; the stub `claude` and `codex` are never
    called; a declared tool absent from `mise ls` is shown as `missing` (TD §3.9).
  - `entrypoint writes running, then ok` and `writes failed: tools` when the tools step
    fails, `failed: plugins-claude` when plugin init fails, and `exec`s its arguments in
    every case.
  - `entrypoint skips plugin init for an agent whose launcher does not resolve` and records
    that as a failed step.
- [ ] **Step 3: Run** `mise run test`. Expected: FAIL.
- [ ] **Step 4: Implement.** `[tasks]` entries use the invocation of TD §2 as adjusted by
      the probes.
- [ ] **Step 5: Run** `mise run check`. Expected: PASS.
- [ ] **Step 6: Commit** `feat: add container tasks and entrypoint`

### Task 5: Plugin initialization

**Goal:** `aidc-plugins init <agent>` with the default plugin catalog.

**Files:**
- Create: `.devcontainer/plugins.json`, `.devcontainer/bin/aidc-plugins`
- Test: `tests/unit/container/plugins.bats`, fixtures
  `tests/fixtures/plugins/{claude,codex}-{marketplaces,plugins}.json`

**Covers:** AC8, AC9 (unit halves); spec Plugins. TD §3.5, §4 plugin marker, §5 lock 3, §6.

**Interfaces:** consumes the launchers (Task 3) and is called by the entrypoint (Task 4).
Catalog content is exactly the JSON of TD §3.5.

- [ ] **Step 1: Probes** (network; CLIs via `mise exec` with a temp
      `CLAUDE_CONFIG_DIR`/`CODEX_HOME`, no login needed for local listing):
  - *P5.1, TD §8 plugin list command and JSON, disabled included:* for Claude try `claude
    plugin list --json`; for Codex the matching `codex plugin` listing. Install one plugin,
    disable it, list again; save both outputs as the fixtures, with host paths and the
    user name replaced by neutral ones. Fallback: read the CLI's own
    installed-plugins record in the state directory, whose shape the probe also records.
  - *P5.2, Codex catalog IDs (TD §3.5 "to verify"):* `codex plugin marketplace add` for both
    marketplaces, then `codex plugin add` for both defaults. Fallback: correct the IDs in
    `plugins.json` only; a default no Codex marketplace provides is reported to the
    developer.
  - *P5.3, Codex plugin auto-upgrade (TD §8):* note whether
    `plugins-marketplace-auto-upgrade` runs by default. Fallback: document Codex plugin
    updates as by hand (spec Plugins allows it).
- [ ] **Step 2: Write the failing tests** (stub `claude`/`codex` serve the fixtures and log
      calls; a stub state dir per test):
  - `an existing marker stops before any CLI call`.
  - `the marker is rechecked after the lock` — marker created while waiting; no install
    runs.
  - `a new state profile gets every catalog marketplace and default, then the marker`
    (Claude and Codex, with `--scope user` for Claude).
  - `a listed marketplace is not added again` (Claude `repo` match; Codex
    `https://github.com/<owner/repo>.git` match).
  - `a listed plugin, disabled included, is not installed again`.
  - `one failing install leaves the marker absent and logs the failure`, and `the retry
    installs only the missing defaults, then writes the marker` (AC9).
  - `a default removed after the marker exists is not reinstalled` (AC8).
  - `a marketplace add failure is reported and the run exits non-zero`.
- [ ] **Step 3: Run** `bats tests/unit/container/plugins.bats`. Expected: FAIL.
- [ ] **Step 4: Implement** the script and catalog.
- [ ] **Step 5: Run** `mise run check`. Expected: PASS.
- [ ] **Step 6: Commit** `feat: add plugin initialization`

### Task 6: Image, shared Compose file and policy

**Goal:** A buildable `aidc-workspace:local` image with the policy files and the shared
Compose file; one profile starts through `profile:code`'s `devcontainer up`.

**Files:**
- Create: `.devcontainer/Dockerfile`, `.devcontainer/compose.yaml`,
  `.devcontainer/policy/claude-managed-settings.json`,
  `.devcontainer/policy/codex-requirements.toml`, `.devcontainer/policy/codex-config.toml`
- Modify (only if the P2.1 fallback triggers): `tasks/host/profile/code`,
  `tests/unit/host/profile_tasks.bats`
- Test: `tests/unit/container/policy.bats`

**Covers:** AC6 (policy files), AC2 (UID/GID build); spec Tools (self-update off),
Isolation. TD §2 image, Compose and policy rows, §3.2 mount points, §3.7, §3.8
(`overrideCommand`).

**Reuse:** v1 `.devcontainer/Dockerfile` for the Docker apt key check, the mise download
with SHA-256 and the `chmod` of copied files. Pin mise **2026.9.15** (not v1's 2026.9.12,
on which a failed `mise lock --global` exits 0 with a partial lock), with the SHA-256
values from that release's checksums (the root `mise.toml` floor comes from Task 1). Drop the base digest argument (TD:
`FROM debian:trixie-slim`), yq, and `/run/aidc`. Build arguments are `USER_UID`/`USER_GID`
(TD §3.8). Create, owned by `dev` and in v1's loop shape so parents are owned too:
`/home/dev/.claude`, `/home/dev/.codex`, `/home/dev/.local`, `/home/dev/.local/state`,
`/home/dev/.local/state/shell`, `/opt/aidc/tools` and `/workspaces`.

- [ ] **Step 1: Probes** (Docker, network), in throwaway `debian:trixie-slim` containers
      with the CLIs installed by mise 2026.9.15 and the draft policy files bind-mounted at
      their `/etc` paths:
  - *P6.1, `overrideCommand: false` (TD §3.8):* a two-line Compose service with an
    entrypoint that writes a file, opened by `devcontainer up` with `overrideCommand:
    false`, keeps entrypoint and command. Fallback: add `postStartCommand` calling
    `aidc-entrypoint true`.
  - *P6.2, empty volume ownership (TD §3.2, §8):* a fresh external volume mounted at a
    `dev`-owned image directory is owned by `dev`. Fallback: none built; list the failing
    topology in the README as unsupported.
  - *P6.3, Codex enforcement (TD §8):* a user `config.toml` with `sandbox_mode =
    "read-only"` is refused or overridden, and `/etc/codex/config.toml` is read below user
    configuration; record the command that reports the effective settings (Task 7 uses it).
    Fallback: stop and report to the developer; no flag injection without a ruling.
  - *P6.4, Claude plugin auto-update (TD §8):* with the managed settings, add the official
    marketplace, enable its auto-update, run `claude --debug` briefly and require a
    positive plugin auto-update log line; "Plugin autoupdate: skipped" or no line at all
    fails the probe. On failure stop and report to
    the developer: the spec requires Claude's plugin auto-update to survive the policy.
    Manual checklist item 10 stays.
- [ ] **Step 2: Write the failing tests** (`policy.bats`, no Docker):
  - Claude managed settings hold exactly `env.DISABLE_UPDATES="1"`,
    `env.FORCE_AUTOUPDATE_PLUGINS="1"`, `env.CLAUDE_CODE_PLUGIN_PREFER_HTTPS="1"`.
  - `requirements.toml` holds `check_for_update_on_startup = false`,
    `cli_auth_credentials_store = "file"`, `allowed_sandbox_modes = ["danger-full-access"]`.
  - `codex-config.toml` holds `sandbox_mode = "danger-full-access"` and `approval_policy =
    "on-request"`.
  - `compose.yaml` sets `DISABLE_UPDATES=1`, `init: true`, user `dev`, the read-only
    `.:/opt/aidc/devcontainer` bind, image `aidc-workspace:local`.
- [ ] **Step 3: Run** `bats tests/unit/container/policy.bats`. Expected: FAIL.
- [ ] **Step 4: Implement** the files.
- [ ] **Step 5: Run** in an `AIDC_ROOT` copy of the repository (so the developer's
      `.local/active-profile`, `profiles/` and `projects/` stay untouched), with an unused
      name `smoke<run>`: `mise run profile:new smoke<run> &&
      mise run profile:code smoke<run>` (VS Code may be absent: the `code` step may fail),
      then poll `docker exec aidc-smoke<run>-workspace-1 cat /opt/aidc/tools/init.status`
      until it no longer starts with `running`. Expected: `ok` or `failed` with named steps,
      and the container running. Also run *P2.1, TD §8 URI form:* on Linux and on WSL2,
      open the container with `code --folder-uri
      vscode-remote://dev-container+<hex of .local/<p>>/workspaces/<p>`; fallback:
      `profile:code` prints the `.local/<p>` path and runs `code .local/<p>`, the developer
      picks "Reopen in Container", and `profile:code`'s unit test is amended here. Finish
      with `mise run profile:remove smoke<run>` and `docker volume rm` of its three state
      volumes.
- [ ] **Step 6: Run** `mise run check`. Expected: PASS.
- [ ] **Step 7: Commit** `feat: add workspace image, compose file and policy`

### Task 7: Integration tests

**Goal:** Docker tests for every AC the TD §7 assigns to integration, run by `mise run
test:integration`.

**Files:**
- Create: `tests/helpers/integration.bash`, `tests/fixtures/compose.test.yaml`,
  `tests/fixtures/compose.nonet.yaml`, `tests/integration/00_suite.bats`,
  `tests/integration/profiles.bats`, `tests/integration/tools.bats`,
  `tests/integration/policy.bats`, `tests/integration/plugins.bats`,
  `tests/integration/privacy.bats`, `tests/integration/zz_cleanup.bats`

**Covers:** AC2–AC12 (automated parts); TD §7 Docker list, §5 cross-container lock. **Needs
Docker and network.**

**Reuse:** v1 `tests/integration/00_suite.bats`, `zz_cleanup.bats` and `aidc_test_repo` for
suite setup and teardown. Every name carries a per-run id (`it<run>-a`, `it<run>-b`,
state profile `it<run>-shared`); setup refuses to start when any resource with those
names exists; each test records the containers and volumes it creates, and cleanup
removes exactly those, never by pattern.

**Interfaces:** drives the host tasks of Task 2 through a copied repository (`AIDC_ROOT`);
`code` is stubbed and `docker` is real; `devcontainer` is stubbed wherever a test uses the
test Compose files, so the real `devcontainer up` path is exercised only by the Task 6
smoke and P6.1 (an acceptance-matrix row says so). Suite setup builds
`aidc-workspace:local` once per run from the repository copy (`docker compose … build`),
so image-baked script fixes reach the tests. The image is outside cleanup; the v1 `00_suite.bats`/`zz_cleanup.bats` serve
only as ordering scaffolding. A test-only Compose file
`tests/fixtures/compose.test.yaml` adds `GITHUB_TOKEN` as a pass-through environment
entry (tests only, never the shared file); a second one,
`tests/fixtures/compose.nonet.yaml`, sets `network_mode: none`. Tests that need either
run `profile:code` with `devcontainer` and `code` stubbed on `PATH`, so it only generates
the files and creates the volumes; the first real start is then `docker compose -p
aidc-<p> -f .devcontainer/compose.yaml -f .local/<p>/compose.yaml -f <test file> up -d`.
Every first start in the suite uses `compose.test.yaml`, so no tool download runs
unauthenticated.
Every test that reads `init.status` polls until it no longer starts with `running`.

- [ ] **Step 1: Probes** (manual parts need VS Code or a login):
  - *P7.1, Claude login location (spec, TD §8):* after a manual `claude` login, list new
    files in `CLAUDE_CONFIG_DIR` and elsewhere under `/home/dev`. Fallback: a credential
    outside the volume stops the task and goes to the developer.
  - *P7.2, "Rebuild Container" (spec, TD §8):* rebuild a running profile from VS Code;
    tools, state and history stay and the entrypoint runs. Fallback: add `profile:rebuild
    [p]` as `devcontainer up --remove-existing-container`, with a unit test (spec allows it).
  - *P7.3, concurrent use of one state profile (spec):* two containers on `it<run>-shared`
    run parallel Claude and Codex sessions; login and settings stay intact. Fallback: none
    built; record it in the matrix and report to the developer (the requirement stays).
- [ ] **Step 2: Write the tests**, each expecting success:
  - `profiles.bats`: `two profiles run at once with their own volume and checkouts` and `id
    -u`/`id -g` inside equal the host's (AC2); `a profile with unset state fields mounts
    volumes named after itself` and `two profiles naming it<run>-shared share one Claude and
    one Codex volume and a settings file written in one is read in the other` (AC7);
    `profile:remove` removes the container, `.local/it<run>-a/` and `aidc-tools-it<run>-a`,
    keeps projects, profiles and all state volumes, and succeeds again (AC11); `a state
    volume survives remove and code` (AC7).
  - `tools.bats`: `claude --version` and `codex --version` match `mise ls` of the copy, also
    after `cd` into a project whose `mise.toml` declares another `claude`/`codex` (AC3);
    `after recreation from the cached image with --network none, versions are unchanged`
    (AC4); `aidc:sync installs a changed .devcontainer/mise.toml` and `aidc:update moves a
    tool locked to an older version to a newer allowed one` (AC5); `with one uninstallable
    tool declared, sync and update install the others, name it and exit non-zero` (AC5); `a
    second container waits for a flock held by the first on a shared volume and gets it once
    the holder stops` (TD §5).
  - `policy.bats`: `claude update refuses`; `a user settings.json setting DISABLE_UPDATES=0
    does not re-enable updates`; `a user config.toml cannot re-enable the Codex update
    check`; `after codex runs, no app-server daemon process exists and CODEX_HOME/packages
    is absent`; `Codex reports danger-full-access and on-request` with the P6.3 command
    (AC6).
  - `plugins.bats`: `a new state profile gets every default and the marker` (AC8); `stop the
    container after the first plugin install, start again: every default and the marker`
    (AC9); `first start on no network: the container runs, and aidc:status run from an
    untrusted project shows every declared tool by name (claude and codex as missing),
    the plugins and the failed initialization`, then `recreated with the network
    (`up -d` with compose.test.yaml and without compose.nonet.yaml): the tools are
    installed and init.status is ok` (AC10, TD §3.3 and §6).
  - `privacy.bats`: build context listing (`docker build` of `.devcontainer/` with a debug
    stage, or `tar` of the context) holds no `profiles`, `projects`, `.local`; no file in
    the image (`docker run --rm --user 0` of the image) or in the running container
    (`docker exec -u 0`) matches `grep -rlIE '^-----BEGIN [A-Z ]*PRIVATE KEY-----'` with
    `/proc` and `/sys` excluded, asserted as empty output (text files, line-anchored: the
    string is compiled into ssh binaries); `GIT_AUTHOR_NAME` and
    `GIT_COMMITTER_EMAIL` from `profile.env` appear in a test commit; the socket exists only
    with `DOCKER_SOCKET=on` (AC12).
- [ ] **Step 3: Run** `GITHUB_TOKEN=… mise run test:integration`. Expected: PASS; any
      failure is a defect in Tasks 2–6, fixed in that task's files with its unit test first.
- [ ] **Step 4: Run** `mise run check`. Expected: PASS.
- [ ] **Step 5: Commit** `test: add docker integration tests`

### Task 8: Documentation and stage update

**Goal:** The README, the manual checklist, the acceptance matrix and the AGENTS.md stage
and validation sections.

**Files:**
- Create: `README.md`, `docs/verification/manual-checklist.md`,
  `docs/verification/acceptance-matrix.md` (both with `ticket: none` and `date` frontmatter)
- Modify: `AGENTS.md` (Context and current stage; Validation)

**Covers:** spec Host integration (documentation duties), Isolation consequences, Open
verification items; TD §7 manual checklist.

- [ ] **Step 1: Write** `README.md`: prerequisites (Docker, `flock`, mise, VS Code with Dev
      Containers, a running host ssh-agent); a WSL systemd user unit example for `ssh-agent`
      (`ssh-agent -D -a %t/ssh-agent.socket`, `SSH_AUTH_SOCK` exported from the login
      shell); host tasks and container task invocations as the probes settled them; the
      isolation consequences and the Docker socket warning; known Git cases: a host
      `core.sshCommand` blocks the agent (fix: `GIT_SSH_COMMAND=ssh` in `profile.env`), and
      on one server with several accounts the first offered key wins; plugin update
      behaviour per CLI; the fallbacks the probes triggered.
- [ ] **Step 2: Write** `manual-checklist.md`: the ten TD §7 items, each with the command to
      run and the expected result, plus the spec's open items without a test (Rebuild
      Container vs `profile:rebuild`; concurrent CLI use of one state profile), pointing at
      P7.2 and P7.3.
- [ ] **Step 3: Write** `acceptance-matrix.md`: one row per AC 1–12 with the test file and
      test name (unit, integration or checklist item), and one row per probe P2.1–P7.3 with
      its result and date.
- [ ] **Step 4: Update** `AGENTS.md`: the stage paragraph says v2 is implemented per this
      plan; Validation lists `mise run check`, `mise run test:integration` (Docker, network,
      `GITHUB_TOKEN` as environment only) and the manual checklist.
- [ ] **Step 5: Run** `mise run check` and check the matrix: each automated row's test
      name exists in `tests/`, each manual row's item exists in `manual-checklist.md`,
      and each probe row has a result and a date. Expected: PASS, nothing missing.
- [ ] **Step 6: Commit** `docs: add readme, verification checklist and acceptance matrix`

## Review rounds

### 2026-09-28 — Codex co-author review, NOT READY

- fixed 2026-09-28 — [blocking] integration tests required before Task 7 creates them; license: plan order; required from Task 7 on.
- fixed 2026-09-28 — [blocking] the host lock was created before `profile.env` validation, breaking AC1; license: spec AC1; validation first, whole-tree delta test; TD §3.9 order corrected.
- fixed 2026-09-28 — [blocking] manual Claude plugin updates are no fallback; license: spec Plugins (auto-update must survive the policy); P6.4 stops and reports.
- fixed 2026-09-28 — [blocking] pattern cleanup could delete unrelated resources; license: AGENTS.md (preserve user work); per-run names, refusal on collision, exact recorded cleanup.
- fixed 2026-09-28 — [blocking] the private-key check relied on file names; license: spec Privacy; key-header scan of image and container.
- fixed 2026-09-28 — [blocking] the matrix check grepped only tests; license: Task 8 goal; per-row-kind checks.
- gate 2026-09-28 — propagation: three Files lists used shorthand paths; expanded to full paths.

### 2026-09-28 — plan-adversary, opus 5.5, blocking (round 1, full-document)

- fixed 2026-09-28 — [Important] I1: `bats tests/unit` does not recurse; license: v1 task shape (probe); `--recursive`.
- fixed 2026-09-28 — [Important] I2: a failed `mise lock --global` blocked every install; ruling: 2026-09-28 (developer); plain `mise install` fallback, TD §3.3 and a Task 4 test.
- fixed 2026-09-28 — [Important] I3: the key-header scan matched ssh binaries; license: probe; text-only, line-anchored scan.
- fixed 2026-09-28 — [Important] I4: `GITHUB_TOKEN` had no route into test containers; ruling: 2026-09-28 (developer: temporary, not default); a test-only Compose file.
- fixed 2026-09-28 — [Important] I5: `~/.local` and `~/.local/state` would be root-owned; license: probe and v1 Dockerfile loop; listed.
- fixed 2026-09-28 — [Important] I6: `profile:remove` lacked name validation (data loss); license: spec Profiles; tests added.
- fixed 2026-09-28 — [Important] I7: P2.1 needed a container before one exists; license: plan order; moved to Task 6 Step 5.
- fixed 2026-09-28 — [Minor] M1: poll `init.status`; M2: no-network via a test-only Compose file; M3: shared image outside cleanup, per-run names everywhere; M4: P6.4 needs a positive log line; M5: zshrc test skips without zsh, overridable path; M6: `common.sh` listed; M9: smoke on an unused name with cleanup; M10: neutral fixtures; license: the round's evidence.
- fixed 2026-09-28 — [Minor] M7: names `locks`/`active-profile` rejected; ruling: 2026-09-28 (developer). M8: the Codex guard is removed and both CLIs default to latest, with the table risk accepted; ruling: 2026-09-28 (developer).
- signal 2026-09-28 — one diff-scoped round on these fixes suffices.

### 2026-09-28 — plan-adversary, opus 5.5, blocking (round 2, full-document)

- fixed 2026-09-28 — [Important] I1: the lock-failure behaviour holds only on mise 2026.9.15, and v1's 2026.9.12 pin never recovers an offline first start; license: probe and TD §3.3/§6; image and host pin 2026.9.15, probes on it, an online-restart case added to AC10.
- fixed 2026-09-28 — [Important] I2: the test Compose files ran after a real first start; license: AC10 and the round-1 I4 ruling; `profile:code` stubbed in those tests, first real start through `docker compose … -f <test file>`, every first start authenticated.
- fixed 2026-09-28 — [Minor] M1: key scan as root with empty-output assertion; M2: conditional Files for the P2.1 fallback; M3: the smoke test runs in an `AIDC_ROOT` copy; license: the round's evidence.
- signal 2026-09-28 — one confirming full-document round after these fixes.
- gate 2026-09-28 — propagation: Task 6 probes named "the pinned mise" without the version; now mise 2026.9.15.

### 2026-09-28 — plan-adversary, opus 5.5, blocking (round 3, full-document)

- fixed 2026-09-28 — [Important] I1: offline `mise ls` omits unresolvable `latest` tools; ruling: 2026-09-28 (developer); `aidc:status` lists declared tools from the copy and marks missing ones; AC10 asserts each by name; TD §3.9.
- fixed 2026-09-28 — [Important] I2: nothing built the image in the suite; license: TD §3.9 (scripts are image-baked); suite setup builds `aidc-workspace:local` once per run.
- fixed 2026-09-28 — [Minor] M1: Interfaces reworded, real `devcontainer up` only in the smoke and P6.1; M2: `min_version` floor in Task 1; M3: the online recreation spelled out; license: the round's evidence.
- signal 2026-09-28 — cap spent; another full round would not earn its cost; a short diff check closes the loop (developer: Codex closure check).
