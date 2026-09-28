# Project instructions

## Language

- Write repository files in English, including documentation, comments,
  configuration descriptions, and user-facing messages.

## Context and current stage

This project is a generic development container for Claude Code and Codex CLI,
with independent environment profiles and separate mise configurations for
container tools and project dependencies.

The project is in design. Container configuration, scripts, mise tasks, and
automated checks have not been implemented yet. Treat commands mentioned in
design discussions as proposed interfaces until their implementations exist.
Update this section when implementation changes that status.

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
- Keep shared project instructions here. `CLAUDE.md` imports this file;
  avoid maintaining duplicate copies of the same instructions.

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
- No build, lint, or test task exists yet. Do not invent successful checks or
  claim that a container or plugin integration was tested without running it.
- Once implemented, expose routine checks through mise and document them here.
- Keep changes focused and preserve existing user work.
