# AGENTS.md - Jido Chat Development Guide

`jido_chat` owns the core adapter contract and typed chat data model for the
Jido chat ecosystem.

## Commands

- `mix setup` - Fetch dependencies.
- `mix test` - Run the default test suite.
- `mix quality` - Run the Jido package quality gate.
- `mix coveralls` - Run coverage.
- `mix install_hooks` - Explicitly install local git hooks.

## Rules

- Module namespace for this repository is `Jido.Chat`.
- Public modules should be defined under `Jido.Chat.*`.
- Keep the public Integration API at `Jido.Chat.Plugin`, `Jido.Chat.Sensor`,
  and their child modules.
- Rooms, participants, bridges, provider work, storage contracts, and delivery
  orchestration belong under `Jido.Chat.Runtime`.
- Starting the `:jido_chat` application must not start a Chat process, table,
  queue, room, Sensor, or storage resource.
- Prefer Zoi-backed structs and Splode errors for new core data and errors.
- Keep public APIs documented and typed.

## Release Hygiene

- Do not modify `CHANGELOG.md`; release notes are generated from Git history during release, so keep changes focused on proper Conventional Commits.
