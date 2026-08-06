# Changelog

## 1.0.0

Initial Hex release of `jido_chat`.

### Features

- Adds the core `Jido.Chat` adapter contract and canonical chat data model.
- Adds typed thread and channel handles, outbound payloads, file uploads, stream chunks, and normalized inbound event models.
- Adds adapter capability negotiation, fallback behavior, lightweight state/concurrency hooks, and AI history conversion helpers.

<!-- changelog -->

## [v1.1.0](https://github.com/agentjido/jido_chat/compare/v1.0.2...v1.1.0) (2026-08-06)




### Features:

* adapter: add optional fetch_media/2 callback (#29) by Jad Tarabay

### Bug Fixes:

* deps: update Mint for CVE-2026-59249 by mikehostetler

## [v1.0.2](https://github.com/agentjido/jido_chat/compare/v1.0.1...v1.0.2) (2026-05-28)




### Bug Fixes:

* type: external_message_id can be any type (#22) by Julien

## [v1.0.1](https://github.com/agentjido/jido_chat/compare/v1.0.0...v1.0.1) (2026-05-21)




### Bug Fixes:

* update Hex installation docs by mikehostetler