---
modules:
  - Jido.Chat.Telegram.SendPoll
  - Jido.Chat.Telegram.SendPhoto
  - Jido.Chat.Telegram.SendDocument
  - Jido.Chat.Telegram.SendSticker
  - Jido.Chat.Telegram.SendAnimation
  - Jido.Chat.Telegram.SendVideoNote
  - Jido.Chat.Telegram.GetFile
  - Jido.Chat.Telegram.GetMe
  - Jido.Chat.Telegram.AnswerCallbackQuery
  - Jido.Chat.Telegram.SendDraft
  - Jido.Chat.Telegram.FetchUpdates
  - Jido.Chat.Telegram.SetWebhook
  - Jido.Chat.Telegram.GetWebhookInfo
  - Jido.Chat.Telegram.DeleteWebhook
---
# Telegram Actions

## Purpose

Define all fourteen Telegram extension Actions through the public Jido Chat
extension points. Requests and results are native Signals. Private execution
context supplies the Client, credentials, and transport options.

### jido_chat_telegram.actions.I1 — Every extension executes as a native Jido Action
- **scope:** The fourteen reviewed request, Action, wire method, payload, and result examples.
- **must:** Run each Action through Jido.Exec and configured Jido.Chat.execute for two client identities. Make exactly one provider call for these finite operations. Return the actual canonical provider result in the matching Completed Signal, with client_id, request_id, operation, source, trace, and causation context. Validate the output and preserve native Catalog serialization.
- **kind:** functional
- **status:** active

### jido_chat_telegram.actions.I2 — Invalid requests fail before transport I/O
- **scope:** Wrong request type, schema, client, subject, references, data, context, credentials, and legacy options.
- **must:** Reject forged or foreign requests and malformed source data before a provider call. Require a configured Telegram adapter and a non-empty private token. Do not let old content options bypass the request Signal. Invalid requests must not produce a success Signal.
- **kind:** security
- **status:** active

### jido_chat_telegram.actions.I3 — Provider failures have safe typed outcomes
- **scope:** Provider rejection, malformed success, exceptions, and execution deadlines.
- **must:** Return the matching Failed Signal through Jido.Chat.Error. Preserve correlation and trace context. Map Telegram 401, 403, 404, and 429 to safe categories and expose only a valid retry_after_ms hint. Keep other unknown outcomes unknown. Reject malformed provider results. Do not expose raw errors, credentials, or token URLs. Make no automatic retry.
- **kind:** security
- **status:** active

### jido_chat_telegram.actions.I4 — Draft and webhook Actions perform only their explicit operation
- **scope:** SendDraft, SetWebhook, GetWebhookInfo, DeleteWebhook, and Webhook.verify.
- **must:** Send one plain or rich draft without a final message or scheduled work. Send a webhook secret only from private Client credentials and omit it from Signals. Make one explicit webhook call per Action. Verify a configured secret without I/O; reject absent or wrong secrets. The host owns HTTP responses and delivery.
- **kind:** ordering
- **status:** active

### jido_chat_telegram.actions.I5 — Provider and core Actions compose through Jido primitives
- **scope:** A mixed core/provider Flow and provider Router, Instruction, and Dispatch calls.
- **must:** Execute dependent steps in order and return native result Signals. A failed dependency must prevent the next provider write. Route a typed Telegram request to its Action Instruction and dispatch the native completion. The host owns any Bus and publication process.
- **kind:** ordering
- **status:** active

### jido_chat_telegram.actions.I6 — Agent discovery uses the native SignalAction data contracts
- **scope:** to_json input and output schemas and serialized data for all fourteen Actions.
- **must:** Match the request and completion Signal data schemas. Accept serialized request data through Exec, with an optional request Signal in context. Build a completion Signal with reply/3. Reject envelope wrappers, private fields, mismatched identities, and malformed data before transport I/O.
- **kind:** persisted-format
- **status:** active
