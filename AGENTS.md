# Project instructions

A generic dev container for AI coding agent CLIs; v2 supports Claude Code and
Codex CLI. `README.md` is the entry point for users, `CONTRIBUTING.md` for
changes to this repository.

## Language

- Write repository files in English: documentation, comments, configuration
  descriptions, and user-facing messages.

## Before design or implementation

- Read `docs/domain/glossary.md` and use its canonical terms. Keep
  environment profiles, agent state profiles, and tool installations
  distinct; a change to shared state reaches every profile that shares it.
- Read the relevant design spec (`docs/specs/`), technical design
  (`docs/technical-designs/`) and plan (`docs/plans/`), and ADRs in
  `docs/domain/adr/` once any exist. These directories are versioned; never
  ignore them.

## Working process

- New features go through a design spec and an architecture review before
  an implementation plan. Keep decisions in repository documents, not in
  chat history.
- Keep to KISS and YAGNI: prefer native tool behaviour and plain failure
  reporting over custom mechanisms.
- Distinguish requirements from verified behaviour. A requirement that is
  not yet verified (such as concurrent access to shared agent state) stays a
  requirement; do not silently turn it into a limitation.
- Keep changes focused and preserve existing user work.
- Keep shared agent instructions in this file. Claude Code and Codex both
  read it natively; do not add a `CLAUDE.md` that duplicates it.

## Privacy

- `profiles/`, `projects/`, and `.local/` stay out of Git and Docker build
  contexts: profile names, local overrides, credentials, checkouts.
- Use fictional, neutral examples in versioned files; never copy private
  configuration or credentials into them.
- Forward the host SSH agent; never copy private SSH keys into containers.

## Validation

- Run `mise run check` (format, lint, unit tests) for every change, and
  `mise run test:integration` when Docker and network access are available
  (see `CONTRIBUTING.md`). Report both actual results; report a skipped
  check as not run, with the reason.
- Run the applicable items of `docs/verification/manual-checklist.md` (VS
  Code or a real agent login; no task runs them), and report the ones not
  run. When behaviour changes, update that checklist and
  `docs/verification/acceptance-matrix.md`.
- Never claim a check, container, plugin integration or checklist item
  passed without running it.
- Expose new routine checks as mise tasks and list them in
  `CONTRIBUTING.md`.
