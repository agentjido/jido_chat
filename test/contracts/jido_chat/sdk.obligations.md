---
modules: [Jido.Chat]
---
# Static SDK boundary

## Purpose

Jido Chat supplies libraries that a host application calls to read and write
chat systems. The host application owns its runtime. Jido Messaging supplies
the full messaging system. This obligation checks application startup
metadata. The public_api, actions, signals, and adapter components define the callable boundary.

### jido_chat.sdk.I1 — Chat declares no application runtime
- **scope:** The built `jido_chat.app` application specification.
- **must:** Declare no application callback and no registered process names. Do not require `jido_messaging` as an application dependency. Signal and other SDK dependencies can own their own application processes.
- **why:** The host must control runtime ownership. A Chat-owned application callback or registered process would introduce a required runtime into the static SDK.
- **kind:** non-functional
- **status:** active
