defmodule Jido.Chat.Sensor.Source do
  @moduledoc """
  Provider input for the shared, receive-only Chat Sensor.

  `mode/0` selects polling or push input. Both modes return normalized Signals
  from the Client catalog. Neither mode sends chat replies.

  Poll sources implement `read/3`. The Sensor commits the returned cursor only
  after Dispatch accepts the selected Signals. `poll_interval/1` sets the delay
  between reads; the fallback is 1,000 milliseconds.

  Push sources implement `start_link/3`. Start a linked connection worker and
  return its PID without waiting for Sensor input. That worker calls
  `Jido.Chat.Sensor.push/3` with normalized Signals. An `:ok` return confirms
  admission, not a reply or durable storage. The source owns protocol receipts,
  reconnection, and provider retry rules. It must not acknowledge rejected input
  as accepted. The Sensor stops if its worker exits and stops it on shutdown.
  The worker has 1,000 milliseconds to stop before the Sensor sends `:kill`.

  Optional `key/2` returns an opaque identity to prevent concurrent sources.
  Do not return a raw credential. Runtime workers and credentials never belong
  in a portable Signal or Agent definition.
  """
  @callback mode() :: :poll | :push
  @callback signal_types() :: [String.t()]
  @callback read(Jido.Chat.Client.t(), term(), keyword()) ::
              {:ok, [Jido.Signal.t()], term()} | {:error, term()}
  @callback poll_interval(keyword()) :: pos_integer()
  @callback start_link(Jido.Chat.Client.t(), pid(), keyword()) ::
              {:ok, pid()} | {:error, term()}
  @callback key(Jido.Chat.Client.t(), keyword()) :: term()
  @optional_callbacks read: 3, poll_interval: 1, start_link: 3, key: 2
end
