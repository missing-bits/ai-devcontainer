---
ticket: none
date: 2026-09-28
status: draft
branch: feature/ai-devcontainer-v2
technical-design: ../technical-designs/ai-devcontainer-v2-technical-design.md
architect: LGTM
integrity: 2026-09-28 (sha: 5ee7282; with: ../technical-designs/ai-devcontainer-v2-technical-design.md@69c59be)
---

# AI Devcontainer v2 Design

## Purpose

Provide one development container per environment profile for working with
Claude Code and Codex CLI on local checkouts. VS Code is the only entry point:
the developer works in the VS Code terminal inside the container. v2 replaces
the over-engineered v1, keeps what v1 proved, and states accepted risks
instead of guarding against them. Terms follow `docs/domain/glossary.md`.

## Goals

- Run several environment profiles at once, each with its own container,
  checkouts and tools.
- Keep agent logins, settings, plugins and shell history in named state
  profiles that survive rebuilds and can be shared between profiles.
- Make tool upgrades explicit and keep installed versions across rebuilds.
- Install the default plugins once per agent state profile, natively.
- Keep private configuration, checkouts and keys out of Git and images.

## Out of scope

- A terminal entry point: no enter, stop, status, use, reset-tools or
  ssh-retarget host tasks.
- The `aidc` command front; container tasks are mise tasks.
- Plugin updates by aidc: no `aidc:update-plugins`, no startup updates, no
  rollback, transactions, journal or `--resolve`; no automatic delivery of a
  new default to an existing agent state profile.
- Codex `working-process` (developer decision, v2 brief 2026-09-28).
- Tool snapshots: manifests, staging, read-only publication, drift reports.
- Configuration fingerprints, the Compose override validator and private
  Compose overrides.
- A startup record with start IDs; bounded waits; the SSH agent relay;
  per-account key selection; a record of the CLI version at the last plugin
  update.
- Agent sandboxes inside the container (see Isolation).
- Prompt frameworks and per-profile shell customization.
- macOS hosts; a Docker daemon inside the container.

## Profiles

An environment profile `<p>` has:

- `profiles/<p>/profile.env`: named fields only, parsed and never sourced;
  unknown keys are rejected. The fields select the state profiles
  (the Claude and Codex agent state profiles and the shell history profile), opt in to the Docker socket, and optionally
  set `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`,
  `GIT_COMMITTER_EMAIL` and `GIT_SSH_COMMAND`;
- `projects/<p>/`: its checkouts, mounted at `/workspaces/<p>`;
- its own container and its own profile tools volume.

Profiles run concurrently. The container user matches the host UID and GID.
A profile or state profile name that does not match `^[a-z0-9][a-z0-9_-]*$`
is rejected before any file or Docker change.

## Mise scopes

- The root `mise.toml` holds the host tools and the host tasks.
- `.devcontainer/mise.toml` holds the container tools, the agent CLIs
  included through aqua, and the container tasks.
- A project's `mise.toml` holds its project runtimes and never changes which
  agent CLI runs: the `claude` and `codex` launchers come first on `PATH` and
  resolve the CLI from the tools config copy.

## Tools

- The first start copies `.devcontainer/mise.toml` into the profile tools
  volume and installs the container tools there. A later start installs what
  is missing and never upgrades.
- Upgrades are explicit. `aidc:sync` copies the current file into the volume
  and locks and installs it; `aidc:update` also runs `mise upgrade`. The
  `mise.lock` beside the copy keeps versions across a rebuild.
- When some tools fail, the task installs the rest, names the failures and
  exits non-zero.
- CLI self-update is off: Claude Code through managed settings and
  `DISABLE_UPDATES`; Codex through `requirements.toml` and a launcher that
  never starts the managed daemon.

## Agent state and login

- Claude, Codex and shell history each keep one volume per state profile. The
  default state profile is the environment profile's name.
- Profiles naming the same state profile share it, also concurrently.
  Concurrent use is a requirement, verified by hand per CLI.
- Version skew between profiles sharing a state profile is an accepted risk.
- Login is symmetric and persistent. Claude keeps its login state in
  `CLAUDE_CONFIG_DIR` (the exact file is to verify); Codex keeps `auth.json` in `CODEX_HOME`, with the file
  store forced by policy because the keyring fails in containers. The
  developer logs in once per state profile; the login survives a rebuild and
  `profile:remove`.

## Plugins

- The versioned catalog `.devcontainer/plugins.json` lists, per agent, the
  marketplaces as GitHub `owner/repo` shorthands, cloned over HTTPS, and the
  default plugins as `plugin@marketplace`.
- Claude defaults: superpowers, elements-of-style, working-process,
  project-memory. Codex defaults: superpowers, elements-of-style.
- The container reads the catalog through the read-only `.devcontainer/`
  mount, which also serves `aidc:sync`.
- Only native commands install plugins: `claude plugin marketplace add
  <owner/repo> --scope user`, then `claude plugin install <plugin@marketplace>
  --scope user`; `codex plugin marketplace add <owner/repo>`, then `codex
  plugin add <plugin@marketplace>`. Installations live only in agent state
  volumes, never in project repositories; nothing is copied from the host.
- Plugin initialization runs at start for each agent state profile without a
  plugin marker, under that state profile's lock. It lists the installed
  plugins, disabled ones included, installs only the missing defaults, and
  writes the marker only after full success. An interrupted run completes at
  the next start. Once the marker exists, the developer's removals and
  disables stand.
- Plugin updates are each CLI's own behaviour: automatic where the CLI does
  it, by hand with native commands otherwise. The self-update policy must
  leave Claude's plugin auto-update working; Claude keeps background
  auto-update off for third-party marketplaces until the developer enables it
  per marketplace in `/plugin`, and that choice persists in the state volume. Other plugin versions call for a
  separate state profile; a new default reaches an existing one only by hand.

## Isolation

The container is the isolation boundary. Codex runs with
`sandbox_mode = "danger-full-access"` and `approval_policy = "on-request"`
from the container's Codex configuration, and `requirements.toml` allows only
that sandbox mode. Claude Code's sandbox stays off, its default. Docker's
default seccomp and AppArmor profiles stay in place.

Consequence: agent commands can change every project of the profile and its
state volumes, and can use the forwarded SSH agent and the network. A shared
state volume carries those changes to the other profiles that use it. With
the Docker socket opted in, the container is no longer the boundary: an agent
command can control every container on the host.

## Host tasks

- `profile:new <p>` creates `profiles/<p>/` from the fictional example, and
  `projects/<p>/`.
- `profile:code [p]` makes `<p>` the active profile (without `<p>`, it uses
  the active profile), generates `.local/<p>/`, starts the container and
  opens VS Code on it.
- `profile:remove <p>` removes the container, `.local/<p>/` and the profile
  tools volume; it keeps `projects/<p>/`, `profiles/<p>/` and state volumes.
- `profile:rebuild [p]` exists only if VS Code "Rebuild Container" proves not
  enough (to verify).
- Repository tasks: `fmt`, `lint`, `test` (unit), `test:integration` (Docker),
  `check`.

## Container tasks

- `aidc:sync`, `aidc:update` and `aidc:status`, defined in the container's
  global mise configuration. The prefix avoids accidental name collisions;
  the documented invocation is meant to select the neutral directory `/`
  before mise loads any configuration and to turn off task auto-install, so a
  project cannot interfere and `aidc:status` runs offline (the mechanism is
  to verify, TD §8).
- `aidc:status` shows the container tools, the plugins per agent and the last
  initialization result, read from a log and a marker.
- The container stays reachable when initialization fails.

## Host integration

- SSH keys come only from the host ssh-agent, which VS Code forwards
  (*verified* by the developer). The documentation requires a running agent
  on the host and gives a WSL systemd user-unit example.
- Git name and email come from the `GIT_*` fields of `profile.env` when set.
- Known case: a host `core.sshCommand` in the Git configuration VS Code copies
  can block the agent. `GIT_SSH_COMMAND=ssh` in `profile.env` fixes it; Git
  prefers the variable (*verified*, Git 2.43.0, probe 2026-09-28).
- Known limit: when one server holds several accounts, the first key the agent
  offers wins. Key selection through a `.pub` file is proven but deferred.
- Docker socket access is opt-in per profile; the documentation states that
  the socket controls every container on the host.

## Privacy

- `profiles/`, `projects/` and `.local/` stay out of Git and out of Docker
  build contexts; ignore rules do not stop a force-add or a custom context.
- Versioned examples are fictional.
- Private keys never enter the image or the container.

## Acceptance criteria

1. `profile:new demo` creates `profiles/demo/profile.env` and `projects/demo/`;
   `profile:new Bad/Name`, and a `profile.env` with an unknown key or an
   invalid state profile name, exit non-zero and change no file or Docker
   object.
2. Two profiles run at once, each in its own container with its own tools
   volume and checkouts at `/workspaces/<p>`; `id -u` and `id -g` inside equal
   the host user's.
3. After a first start, `claude --version` and `codex --version` report the
   tools volume's CLIs, also right after `cd project && claude` into a project
   whose `mise.toml` declares another `claude` or `codex`.
4. After a recreation from the cached image, with the container on no
   network, tool versions are unchanged.
5. `aidc:sync` installs a change to `.devcontainer/mise.toml`; `aidc:update`
   moves tools to newer allowed versions; with one tool uninstallable, both
   install the others, name the failure and exit non-zero.
6. `claude update` refuses; a user setting cannot re-enable Claude or Codex
   self-update; after a Codex session no managed daemon runs and
   `CODEX_HOME/packages/` is absent; Codex reports `danger-full-access` and
   `on-request` as effective.
7. Two profiles naming the same Claude and Codex state profiles share login
   and settings; a profile with those fields unset uses volumes named after
   itself; a login survives a rebuild and `profile:remove`.
8. A new agent state profile receives every default plugin of its agent and
   its marker; a default the developer then removes or disables stays so at
   later starts.
9. After an interrupted first plugin install, the next start installs only the
   missing defaults and writes the marker.
10. With the container on no network at first start, the container runs,
    VS Code attaches,
    and `aidc:status`, run inside an untrusted project, shows the tools, the
    plugins and the failed initialization.
11. `profile:remove demo` removes the container, `.local/demo/` and
    `aidc-tools-demo`, keeps `projects/demo/`, `profiles/demo/` and every state
    volume, and succeeds when run again.
12. `git check-ignore` covers `profiles/`, `projects/` and `.local/`; the build
    context holds none of them; no private key file exists in the image or
    container; the `GIT_*` fields reach commits; the Docker socket appears only
    with the opt-in.

## Open verification items

- Whether VS Code "Rebuild Container" makes `profile:rebuild` unnecessary.
- Whether Claude's plugin auto-update works under the self-update policy.
- Concurrent use of one Claude and one Codex state profile from two containers.
- How `mise lock --global` resolves a changed declaration.
- Whether Codex enforces the sandbox and approval settings.
- Where exactly Claude keeps its login state inside `CLAUDE_CONFIG_DIR`.
- The container task mechanism: global tasks, `-C /`, the auto-install setting.
- The manual VS Code smoke checklist in TD §7.

## Review rounds

### 2026-09-28 — architect, opus 5.5, LGTM (round 1, full-document, with the technical design)

- fixed 2026-09-28 — [Minor] M1: `owner/repo` marketplaces may clone over SSH; license: Claude Code host-marketplace docs; `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` in managed settings.
- fixed 2026-09-28 — [Minor] M2: third-party marketplace auto-update is off until enabled in `/plugin`; license: Claude Code docs; stated in Plugins, checked manually.
- fixed 2026-09-28 — [Minor] M3: AC5, AC7 login survival, AC10 attach and AC12 had no test; license: TD §7 duty; tests and checklist items added.
- fixed 2026-09-28 — [Minor] M4: "network off" undefined; license: AC4/AC10 testability; "recreation from the cached image, container on no network".
- fixed 2026-09-28 — [Minor] M5: the socket opt-in breaks the boundary claim; license: Host integration; stated in Isolation.
- fixed 2026-09-28 — [Minor] M6: the Codex version guard read the live mount; license: Mise scopes (launchers read the tools config copy); TD §3.6.
- fixed 2026-09-28 — [Minor] M7: a root `.dockerignore` had no effect; license: TD §2 (context `.devcontainer/`); dropped.
- fixed 2026-09-28 — [Minor] M8: project runtimes share the tools volume; license: TD §3.2; stated in TD §4 and §5.
- fixed 2026-09-28 — [Minor] M9: Codex working-process drop not cited, AGENTS.md stale; license: v2 brief; cited here, AGENTS.md updated.
- fixed 2026-09-28 — [Minor] M10: bare "state profile" and `/opt/aidc/desired`; license: glossary; umbrella term added, mount renamed `/opt/aidc/devcontainer`.
- fixed 2026-09-28 — integrity-class note: Claude credential location stated as fact but open in TD §8; license: TD §8; the spec now marks the exact file to verify.
- signal 2026-09-28 — another architect round would not earn its cost; a propagation audit after the fixes and the integrity audit at the consumption gate suffice.
- fixed 2026-09-28 — integrity audit (consumption gate, with the TD): 8 defects and 14 implementer questions disposed in place; license: the audit's two-quote proofs and the v2 brief; spec wording (state profiles, container task mechanism marked to verify, open items, `test:integration`) and TD §3.3–§3.9.
