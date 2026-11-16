---
title: Durable adapter-neutral Chat storage
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
status: superseded
superseded_by: guides/architecture.md
domain: software
execution: code
product_contract_source: direct-request
---

# Durable adapter-neutral Chat storage

This plan is a historical record. Do not use it for implementation.

The design review removed the unused History and Rooms storage capabilities.
Runtime did not own a process that used these contracts. At that checkpoint,
the storage boundary had three capabilities:

- `Jido.Chat.Runtime.Storage.Links`
- `Jido.Chat.Runtime.Storage.Outbox`
- `Jido.Chat.Runtime.Storage.Commit`

Memory and DETS implemented these capabilities. A host can implement the same
contracts with Ecto, Ash, or another storage system. Jido Chat does not require
these packages.

Room membership and bounded message history stay in Room Plugin state. Durable
Bus records are the responsibility of the selected Jido Bus store.

The current design and its limits are in:

- `guides/architecture.md`
- `guides/runtime.md`
- `guides/storage_adapters.md`

History storage can return only when Runtime has a process that owns and uses
the contract. Durable Room catalog storage returned under the narrower contract
in `2026-11-16-1010-durable-room-records-plan.md`; Room membership remains Agent
state.
