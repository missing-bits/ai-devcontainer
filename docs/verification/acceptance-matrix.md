---
ticket: none
date: 2026-09-28
---

# Acceptance matrix

One row per acceptance criterion of
`docs/specs/2026-09-28-ai-devcontainer-v2-design.md` (`## Acceptance
criteria`), naming what verifies it, and one row per probe the plan ran
during implementation, with its result and the date it ran. `kind` is
`unit` (bats, no Docker), `integration` (bats, needs Docker) or `checklist`
(`docs/verification/manual-checklist.md`).

## Acceptance criteria

| AC | kind | test file | test name |
|---|---|---|---|
| 1 | unit | `tests/unit/host/profile_tasks.bats` | "profile:new creates the profile from the example, and the project space"; "profile:new rejects an invalid name and creates nothing"; "profile:code refuses an unknown key or an invalid state name and touches nothing" |
| 2 | integration | `tests/integration/profiles.bats` | "two profiles run at once with their own tools volume and checkouts; id -u/id -g match the host" |
| 3 | integration | `tests/integration/tools.bats` | "claude --version and codex --version report the tools volume's CLIs, also from inside a project declaring other versions" |
| 4 | integration | `tests/integration/tools.bats` | "after recreation from the cached image with --network none, tool versions are unchanged" |
| 5 | integration | `tests/integration/tools.bats` | "aidc:sync installs a tool added to .devcontainer/mise.toml"; "aidc:update moves a tool locked to an older version to a newer allowed one"; "with one uninstallable tool declared, sync installs the others, names it, and exits non-zero" |
| 6 | integration | `tests/integration/policy.bats` | "claude update refuses"; "a user settings.json setting DISABLE_UPDATES=0 does not re-enable Claude's update"; "a user config.toml cannot re-enable the Codex update check"; "after codex runs, no app-server daemon process exists and CODEX_HOME/packages is absent"; "Codex reports danger-full-access and on-request as effective" |
| 7 | integration | `tests/integration/profiles.bats` | "a profile with unset state fields mounts volumes named after itself"; "two profiles naming the same state profile share one Claude and one Codex volume, and a settings file written in one is read in the other"; "a state volume survives profile:remove and a later profile:code" |
| 8 | integration, unit | `tests/integration/plugins.bats`; `tests/unit/container/plugins.bats` | "a new state profile gets every default plugin and the marker"; "a default removed after the marker exists is not reinstalled" |
| 9 | integration | `tests/integration/plugins.bats` | "an interrupted first plugin install completes at the next start, with the marker" |
| 10 | integration | `tests/integration/plugins.bats` | "first start with no network runs, and aidc:status from an untrusted project shows the tools, plugins and failed initialization; a later start with the network installs and reports ok" |
| 11 | integration, unit | `tests/integration/profiles.bats`; `tests/unit/host/profile_tasks.bats` | "profile:remove removes the container, .local/<p> and the tools volume, keeps projects, profiles and state volumes, and succeeds again"; "profile:remove tears down a profile via compose, keeps state, and is idempotent via the label" |
| 12 | unit, integration | `tests/unit/host/repository.bats`; `tests/integration/privacy.bats` | "git check-ignore covers profiles, projects and .local"; "the image context holds none of the private directories"; "the build context holds none of the private directories"; "no private key file exists in the image"; "no private key file exists in a running container"; "GIT_AUTHOR_NAME and GIT_COMMITTER_EMAIL from profile.env appear in a test commit"; "the Docker socket exists only with DOCKER_SOCKET=on" |

AC10's VS Code half ("VS Code attaches") and AC7's login-survival half (a
real login rather than a marker file) additionally rely on
`docs/verification/manual-checklist.md` items 9 and 8, since no automated
test drives VS Code itself or a real agent login.

### `devcontainer up` coverage

No automated test invokes the real Dev Containers CLI path
(`devcontainer up` against a generated `.local/<p>/.devcontainer/devcontainer.json`):
the unit and Docker integration suites start containers with `docker
compose -f <test fixture>` instead, deliberately (`profile:code` is stubbed
in those tests — see the Task 7 report). The real `devcontainer up`
invocation is exercised only by the Task 6 implementation smoke run and by
probe P6.1 below.

## Probes

Every probe ran on 2026-09-28, during Tasks 2, 4, 5 and 6 of
`docs/plans/2026-09-28-ai-devcontainer-v2-plan.md`, except P7.4, which
reran on 2026-09-29 during the integrity audit's integration run. Full
detail is in the SDD reports of that plan (`task-2-report.md` through
`task-7-report.md`).

| probe | result | date |
|---|---|---|
| P2.1 (dev-container folder URI, TD §3.8) | With a Linux host path it fails under WSL, because VS Code resolves `hostPath` as a Windows path. With `wslpath -w`'s `\\wsl.localhost\...` form it opens directly in the container (developer run). `profile:code` uses that form under WSL. | 2026-09-28 |
| P2.2 (Docker socket group, TD §3.2/§8) | **Confirmed on Docker Engine**: `group_add` of the host socket's GID (`stat -c %g /var/run/docker.sock`) puts that GID in the container's `id -G`. Docker Desktop is unverified (not reachable from the probing host). | 2026-09-28 |
| P4.1 (global-config tasks) | **Pass**: a task in `MISE_GLOBAL_CONFIG_FILE` is listed and runs from `/` and from a project directory alike, with no trust prompt. | 2026-09-28 |
| P4.2 (`-C /` before configuration loads) | **Pass**: `-C /` on an untrusted project sources nothing, installs nothing and trusts nothing; without it, plain `mise run` silently trusts the project and runs its own task instead. | 2026-09-28 |
| P4.3 (task auto-install setting) | **Pass**: `MISE_TASK_RUN_AUTO_INSTALL=false` maps to `task.run_auto_install` and suppresses the auto-install that otherwise runs before the task. | 2026-09-28 |
| P4.4 (`mise lock --global` on a changed declaration) | **Pass**, after the developer's ruling that the lock covers the container platform only (`mise lock --global --platform <container platform>`): locking across every platform could fail and keep an out-of-declaration version when the new version lacks an asset for another architecture; scoped to the container's own platform, the same case locks and installs the new version cleanly. | 2026-09-28 |
| P4.5 (`mise install --locked` offline) | **Pass**: with everything already installed, including a `latest`-declared tool, it succeeds fully offline. | 2026-09-28 |
| P5.1 (plugin list/marketplace-list JSON shapes, disabled plugins included) | **Pass**: both CLIs' shapes match TD §3.5 exactly; a disabled plugin still appears in the listing, marked disabled. | 2026-09-28 |
| P5.2 (Codex catalog IDs) | **Pass**: the marketplace and plugin IDs in TD §3.5 install cleanly on Codex; no correction needed. | 2026-09-28 |
| P5.3 (Codex plugin auto-upgrade) | Codex refreshes its marketplace clones at session start on its own, with no configuration; observed only with an unauthenticated `codex exec` session (a real version move was not observed, since upstream had not changed during the probe). | 2026-09-28 |
| P6.1 (`overrideCommand: false`) | **Pass**: the Dev Containers CLI keeps both the image entrypoint and the image command; no `postStartCommand` fallback is needed. | 2026-09-28 |
| P6.2 (empty external volume ownership) | **Pass on Docker Desktop/WSL2**: a fresh external volume takes the image mount point's ownership. Native Linux Docker Engine was not exercised. | 2026-09-28 |
| P6.3 (Codex sandbox/approval enforcement) | Codex 0.157.1 rejects `allowed_sandbox_modes` set to anything that omits `read-only`, which would have made Codex unusable in the container. Ruling: the key is dropped; `sandbox_mode`/`approval_policy` still set the defaults, and a different mode in the user's own configuration is the developer's choice. | 2026-09-28 |
| P6.4 (Claude plugin auto-update) | Removed by ruling: forcing Claude's plugin auto-update on would contradict leaving updates to each CLI's own default behaviour. Plugin updates follow each CLI's defaults, with nothing forced either way. | 2026-09-28 |
| P7.1 (Claude login location inside `CLAUDE_CONFIG_DIR`) | **Not run**: needs a real `claude` login, which this non-interactive environment cannot perform. Stays on the manual checklist (item 4/8 exercise it incidentally; no dedicated item, since TD §8 only asks where the file is, not that login works). | 2026-09-28 |
| P7.2 (whether "Rebuild Container" makes `profile:rebuild` unnecessary) | **Not run**: needs VS Code driving a running profile. Stays on the manual checklist, item 10. | 2026-09-28 |
| P7.3 (concurrent use of one state profile from two containers) | **Not run** as a real two-CLI-session probe: needs interactive `claude`/`codex` logins. Its filesystem precondition — two containers mounting the identical state volumes, with a file written by one immediately visible from the other — is verified in Docker (AC7 above). The concurrent-session part stays on the manual checklist, item 11. | 2026-09-28 |
| P7.4 (cross-container `flock` on a shared volume, TD §5) | **Pass on Docker Desktop/WSL2**: `tests/integration/tools.bats`'s second-container test waits for the `flock` the first container holds on a shared volume and acquires it once `docker stop` ends the holder. Other topologies untested. | 2026-09-29 |
