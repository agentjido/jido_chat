# Public Signal migration

See [the current API and breaking migration](public_api.md#removed-api-and-host-boundary).
The API uses immutable Clients, native Jido Actions, native Signal catalogs,
and ordered Delivery values. It has no request store, resource registry, or
managed listener. The host owns the messaging runtime.

Every Action now has nested Completed and Failed definitions. Add
Jido.Chat.signal_definitions() and provider signal_definitions() to a host
catalog. Do not route the removed generic operation result types.

Use CreateThread with room_id and name. Send into its returned thread ID with
SendMessage.thread_id. Use DownloadFile with resource_ref for file bytes.
Requests reject removed and unknown fields. Schema URNs changed where fields changed.

The full API reference includes Actions, Flow, Router, Dispatch, files,
keyboards, failure outcomes, and provider extension examples.
