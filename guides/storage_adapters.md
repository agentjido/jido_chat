# Runtime storage adapters

Jido Chat stores Runtime data through small domain capabilities. It does not
select Ecto, Ash, or another persistence framework for the host.

Every selection has this shape:

```elixir
{adapter_module, host_owned_resource}
```

The resource can be a process name, an Ecto Repo and schema map, an Ash Domain
and resource map, an event-store client, or another value owned by the host.
Starting `:jido_chat` does not start that resource.

## Capabilities

An adapter implements only the capabilities its Runtime use needs:

| Capability | Stored responsibility |
| --- | --- |
| `Jido.Chat.Runtime.Storage.Links` | Local-to-provider message identity |
| `Jido.Chat.Runtime.Storage.Outbox` | Provider work and compare-and-set transitions |
| `Jido.Chat.Runtime.Storage.Commit` | One atomic batch across supported capabilities |

Declare the capabilities on an adapter:

```elixir
defmodule MyApp.ChatStorage do
  alias Jido.Chat.Runtime.Storage.{Adapter, Commit, Links, Outbox}

  use Adapter, capabilities: [Links, Outbox, Commit]

  # Implement the callbacks from the three declared behaviours.
end
```

`Jido.Chat.Runtime.Storage.validate/2` checks the declaration and its exported
callbacks. Existing adapters that implement callbacks without the declaration
remain valid.

## Local durable storage

`Jido.Chat.Runtime.Storage.Dets` implements all current capabilities without
another package dependency. It stores one versioned snapshot and is intended
for local or single-node use.

```elixir
children = [
  {Jido.Chat.Runtime.Storage.Dets,
   name: MyApp.ChatStorage,
   table: :my_app_chat_storage,
   path: "data/chat-runtime.dets"},
  {Jido, name: MyApp.Jido, namespace: "my-app/chat"}
]

defmodule MyApp.Chat do
  use Jido.Chat.Runtime,
    jido: MyApp.Jido,
    storage: {Jido.Chat.Runtime.Storage.Dets, MyApp.ChatStorage}
end
```

The host owns the file path, backup, process, and supervision. Treat the DETS
file as trusted application data. An unsupported stored format stops the
adapter without resetting or overwriting the file.

DETS is not the scale or distributed-storage target. Use an indexed host
adapter when the application needs database queries, multi-node coordination,
tenancy, or framework migrations.

## Ecto mapping

An Ecto adapter uses a resource such as `%{repo: MyApp.Repo, schemas: ...}` and
maps each capability to its schemas and queries. Implement `Commit.commit/2`
with one `Repo.transact/2` operation only when every command in the batch uses
the same transaction boundary.

The normal mapping is:

| Chat capability | Ecto implementation shape |
| --- | --- |
| Links | Link schema with unique local and provider identities |
| Outbox | Work schema with status, lease owner, lease expiry, and compare-and-set update |
| Commit | `Ecto.Multi` or a function passed to `Repo.transact/2` |

Jido Chat does not require `ecto`, `ecto_sql`, or a specific database adapter.
The host owns migrations, prefixes, tenancy, sandbox setup, and error mapping.

## Ash mapping

An Ash adapter uses a resource such as `%{domain: MyApp.Chat, resources: ...}`
and maps each capability to Ash actions. Implement `Commit.commit/2` with
`Ash.transact/3` only when the selected resources share a transaction boundary.

The normal mapping is:

| Chat capability | Ash implementation shape |
| --- | --- |
| Links | Link resource with identities for local and provider keys |
| Outbox | Work resource with atomic status and lease actions |
| Commit | One transaction across the affected resource list |

Jido Chat does not require `ash` or one Ash data layer. The host owns resources,
domains, policies, tenancy, migrations, and framework error translation.

Official transaction references:

- [Ecto Repo transactions](https://ecto.hexdocs.pm/Ecto.Repo.html#transact/2)
- [Ash transactions](https://ash.hexdocs.pm/Ash.html#transact/3)

## Adapter invariants

Every adapter must preserve these rules:

- Link identities are unique in both directions.
- Outbox updates compare the expected status and allow only declared state
  transitions.
- Commit returns no partial success. Do not declare Commit if the backing data
  layer cannot make the complete batch atomic.
- Stored work keeps `lease_owner` and `lease_expires_at` while it is claimed.
- Unknown provider outcomes and submitted or terminal work are not retried
  automatically.
- Adapter failures return `{:error, reason}` and do not expose credentials or
  framework records as Chat domain results.

Use the built-in Memory and DETS tests as the conformance examples for a custom
adapter.
