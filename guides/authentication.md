# Optional adapter authentication

Discover `:authenticate` through `Jido.Chat.Adapter.capabilities/1` (or the typed
capability matrix). The optional callback is `authenticate(request, owner_id,
opts)`; callers use `Jido.Chat.Adapter.authenticate(adapter, request, owner_id,
opts)`. No callback means `:unsupported`, with no effect on legacy adapters.
There is no core authentication runtime or separate methods registry.

Requests are atom-keyed maps. `owner_id` is a non-nil, host-authorized identity;
it is never inferred from possession of a handle. Trusted keyword options carry
the existing `sink_mfa`, context and an owner process, never browser-submitted configuration.

| Request | Result / effect |
| --- | --- |
| `%{op: :begin}` | Starts an attempt; normally returns pending before a QR exists. |
| `%{op: :status, session: handle}` | Reconciles current challenge/account state. |
| `%{op: :retry, session: handle}` | Reuses the live session and credentials, including after scanning. |
| `%{op: :confirm, session: handle, account_id: external_id}` | Explicitly confirms the displayed account; rejects identity changes. |
| `%{op: :cancel, session: handle}` | Cleans up the provisional session; returns cancelled. Does not delete a saved connector. |

Success is `{:ok, response}`. Responses contain `phase` and an opaque `session`
term. Preserve the handle unchanged across BEAM node dispatch; it is not JSON
and must not be parsed, persisted as credentials, or treated as authorization.
Phases are `:pending`, `:challenge`, `:authenticated`, `:saved`, `:failed`,
`:cancelled`. An authenticated account still requires confirmation.

```elixir
%{phase: :challenge, session: handle,
  challenge: %{type: :qr, value: qr_string, expires_at: nil}}
%{phase: :authenticated, session: handle,
  account: %{external_id: "+15550001", display_name: "Account"}}
%{phase: :saved, session: handle,
  receipt: %{id: 123, name: "Account"}, runtime_pending: false}
```

Optional `summary` is safe display text. QR values are confidential display data,
not log data. Challenge expiry clears the QR and may return `:failed`; it does
not expire the session. Replacement QR and reconnect recovery remain pollable.
Only `{:error, :pairing_expired}` requires a new attempt. Cancellation, owner
death and session lifetime expiry destroy provisional state.

Errors are `{:error, atom}`: core returns `:unsupported` or `:invalid_request`;
adapters use sanitized categories such as `:unauthorized`, `:pairing_unavailable`,
`:pairing_expired`, `:identity_not_ready`, `:identity_changed`, `:save_failed`.
Core validates operation/required fields and forwards callback results unchanged.
Adapter implementations must not return raw exceptions, credentials or context.

## Trusted host persistence boundary

The adapter owns protocol encoding and temporary storage. Hosts authorize every
operation and own encryption, atomic configuration creation and runtime activation.
The existing `sink_mfa: {module, function, args}` receives configured arguments
followed by `[payload, opts]`. Private `Jido.Chat.Authentication.Request` envelopes
contain `context` and `request`. `request.op` is `:persist` or `:start`; neither is
a chat action. Persist carries `%{attempt_id: stable_id, account: normalized_account,
credentials: encoded_records}`. Hosts reject these envelopes on public ingress and
handle them synchronously before serialized chat state. Hosts atomically persist
and replay the same receipt/binding for the same attempt after uncertain outcomes.
Activation must happen after that transaction commits.

Success is `{:ok, %{receipt: %{id: id, name: name}, binding: opaque_binding,
runtime: opaque_runtime}}`. Only scalar string/integer `id` and string `name`
are public. Binding, runtime, context and credentials never enter public responses.
The package translates binding into its backend options. Its `:start` request carries `%{runtime: %{binding: binding, runtime: runtime,
connection_options: package_prepared_options}}` in the same envelope/sink after volatile state is seeded.
Ordinary runtime startup consumes these prepared options through its existing path.
An adapter-specific connection-options helper may reconstruct them after restart;
generic authentication callers never call concrete storage modules.

Adapter-owned persistence and activation execution are each bounded to ten seconds and the
remaining attempt lifetime. Exceptions/timeouts return sanitized failures. A
save timeout may have committed: repeat confirm with the same attempt ID and
frozen credentials. After a success receipt, invalid binding, seeding failure or
activation failure remains saved with `runtime_pending: true`; repeated confirm
returns that receipt and never saves or activates again. Hosts reconcile pending
activation through their existing runtime operation.

## Contract regression matrix

Core fixtures cover legacy unsupported, inferred/declared capability, contradictory
declarations, malformed requests, and unchanged argument/result propagation with
a non-WhatsApp provider. Package tests cover asynchronous/replacement/expired QR,
scan/recovery/retry, nil/wrong owner, dead handle, identity change, duplicate confirm,
uncertain save, callback failure/timeout, saved activation failure, cleanup, and
legacy API compatibility. Only external transport and host callback edges are faked.

## Optional connection and runtime contracts

`Jido.Chat.Adapter.prepare_connection/2` delegates to optional
`prepare_connection/1`, which returns `{:ok, ingress_map}`. The core wrapper puts
that opaque map into listener opts; legacy adapters retain their original opts.
`provider_child_specs/2` returns optional shared infrastructure without starting it.
The host owns supervision; no runtime or retry process is introduced in core.
Trusted `:adapter_options` carry deployment policy and are distinct from persisted
ingress settings.

`connection_identity/2` derives an opaque stable identity from a host binding.
`connection_options/3` merges the adapter's option map with supplied delivery opts.
Legacy adapters retain their opts; identity and explicit `logout/2` default to
unsupported. Ordinary shutdown retains credentials; explicit logout targets an
exact listener. All adapter-to-host requests still use only `sink_mfa`.

Private credential access uses `Jido.Chat.Storage.Request` with `binding`,
`request`, `version: 1`, and a request ID. Its operations are bind/get/put/put_many/
delete/delete_namespace/clear/list_keys. Absence (`:error`) differs from failure
(`{:error, atom}`). Core dispatch is synchronous; the package owns deadlines.
Hosts validate provider/connector/binding on every request, including RAM access.
Do not queue private storage behind chat State: outbound operations may already
be waiting on that State while accessing storage.

Lifecycle actions keep the existing EventEnvelope/ActionEvent route and
`action_id: "connection_update"`. Metadata contains `category: :connection_lifecycle`,
`source` (original worker PID), opaque `profile` (matching connection_identity),
`attempt_id` (reference), atom `status`, optional binary `qr`, and adapter-owned
`presentation` (phase/status/summary/mode, optional QR/expiry). Hosts fence stale
sources/attempts and apply presentation before acknowledging. These envelopes do
not authorize credential operations or enter message handlers.
