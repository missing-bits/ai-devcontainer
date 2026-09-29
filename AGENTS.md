# Project instructions

## Language

- Write repository files in English, including documentation, comments,
  configuration descriptions, and user-facing messages.

## Context and current stage

This project is a generic development container for Claude Code and Codex CLI,
with independent environment profiles and separate mise configurations for
container tools and project dependencies.

v2 is implemented per `docs/plans/2026-09-28-ai-devcontainer-v2-plan.md`:
host tasks (`profile:new`, `profile:code`, `profile:remove`), the shared
Compose file and workspace image, container tasks (`aidc:sync`,
`aidc:update`, `aidc:status`), the entrypoint, plugin initialization, the
agent CLI launchers, and the unit and Docker integration test suites all
exist. `README.md` documents host setup and day-to-day use.
`docs/verification/acceptance-matrix.md` and
`docs/verification/manual-checklist.md` record what each acceptance
criterion and probe verified, and what still needs a manual pass with VS
Code or a real agent login. Update this section when implementation changes
that status.

Before design or implementation work, read `docs/domain/glossary.md` for
canonical terms and the design specifications in `docs/specs/` for agreed
requirements. Read relevant plans and `docs/domain/adr/` decisions when those
files exist. Domain documents, design specifications, technical designs, and
implementation plans are versioned; do not ignore `docs/domain/`,
`docs/specs/`, `docs/technical-designs/`, or `docs/plans/`.

## Working process

- Use the available superpowers and working-process skills where applicable.
  Keep decisions in repository documents rather than relying on chat history.
- Complete the design specification and architecture review before preparing
  the implementation plan. Agent initialization does not authorize container
  implementation or mark the design as approved.
- Distinguish requirements from verified behavior. Concurrent access to shared
  agent state is a requirement that remains unverified; do not silently replace
  it with a limitation. `working-process` in Codex is out of scope for v2 by
  the developer's decision (v2 brief, 2026-09-28).
- Keep the design close to KISS and YAGNI: prefer native tool behavior and
  plain failure reporting over custom mechanisms.
- Keep shared project instructions here. Claude Code and Codex both read
  this file natively; do not add a `CLAUDE.md` that duplicates it.

## Privacy and scope

- Keep `profiles/`, `projects/`, and `.local/` private and excluded from Git
  and Docker build contexts. This includes profile names, local Compose
  overrides, credentials, and application checkouts.
- Use fictional, neutral examples in versioned files. Do not copy private
  configuration or credentials from the reference repository.
- Forward the host SSH agent; do not copy private SSH keys into containers.
- The reference setup is a source of design ideas, not a target for edits.
- Keep environment profiles, agent state profiles, and tool installations
  distinct as defined in the glossary. Updates to shared state can affect
  multiple environment profiles.

## Validation

- Run checks appropriate to the files changed and report their actual results.
- Run `mise run check` (formatting, lint, unit tests) for every change, and
  `mise run test:integration` when Docker is available; report both results.
  `mise run test:integration` needs network access too: it builds the
  workspace image and installs container tools, agent CLIs and plugin
  marketplaces from GitHub. It builds and keeps `aidc-workspace:local`, the
  same tag real profiles use, so a profile started right after a test run
  picks up the tested image. Export `GITHUB_TOKEN` on the host; the tests
  pass it to containers only as an environment variable, never in logs,
  build arguments or persisted configuration.
- Run `docs/verification/manual-checklist.md` for the items that need VS
  Code or a real agent login; no mise task runs it.
- Do not invent successful checks, or claim that a container, plugin
  integration or manual checklist item was tested without running it.
- Expose new routine checks as mise tasks and list them here.
- Keep changes focused and preserve existing user work.
