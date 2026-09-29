# Contributing

Read [AGENTS.md](AGENTS.md) before making changes: its rules bind people and
agents alike. New features start with a design spec in `docs/specs/`; the
glossary in `docs/domain/glossary.md` defines the terms.

## Checks

Run these from the repository root after `mise install`:

| Task | What it runs |
| --- | --- |
| `mise run check` | `fmt:check`, `lint` and `test`; run it for every change |
| `mise run fmt` | formats the shell sources with `shfmt` |
| `mise run fmt:check` | reports formatting differences |
| `mise run lint` | `shellcheck` over the shell sources |
| `mise run test` | unit tests (`bats`); no Docker, no credentials |
| `mise run test:integration` | Docker integration tests |

`test:integration` needs a running Docker engine and network access: it
builds the workspace image and installs container tools, agent CLIs and
plugin marketplaces from GitHub. Export `GITHUB_TOKEN` on the host so the
installs avoid GitHub's unauthenticated rate limit; the tests pass it to
containers only as an environment variable, never in logs, build arguments
or persisted configuration. The suite builds and keeps
`aidc-workspace:local`, the tag real profiles use, so a profile started
after a test run picks up the tested image.

Report a check you could not run as not run, with the reason.

## Manual checks

[docs/verification/manual-checklist.md](docs/verification/manual-checklist.md)
lists what needs VS Code or a real agent login; no task runs it.
[docs/verification/acceptance-matrix.md](docs/verification/acceptance-matrix.md)
maps each acceptance criterion to its test or checklist item. Update both
when behaviour changes.

## Commits

One-line [Conventional Commits](https://www.conventionalcommits.org/)
headers, for example `fix(tasks): keep the active profile on failure`.
