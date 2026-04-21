# Contributing to Jido Chat

## Development Setup

```bash
mix setup
```

Install local git hooks explicitly from the primary checkout when needed:

```bash
mix install_hooks
```

## Quality Checks

```bash
mix test
mix quality
mix coveralls
mix docs
```

Live or external-service tests must be excluded by default and enabled with
explicit ExUnit tags.

## Commit Messages

Use Conventional Commits:

```text
type(scope): description
```

Common types are `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`chore`, and `ci`.

## Release Workflow

Releases are prepared through the GitHub Actions release workflow. Before a
release, verify `mix quality`, `mix coveralls`, `mix docs`, and the changelog.
