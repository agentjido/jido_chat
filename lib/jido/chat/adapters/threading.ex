defmodule Jido.Chat.Adapters.Threading do
  @moduledoc """
  Behaviour for channel-specific threading support.

  Threading is fundamental to messaging but varies significantly across platforms.
  This behaviour defines how channels can implement platform-specific threading
  logic while providing a normalized output for the messaging pipeline.

  ## Implementation

  Channels that support threading should implement this behaviour:

      defmodule MyApp.Channels.Slack do
        @behaviour Jido.Chat.Channel
        @behaviour Jido.Chat.Adapters.Threading

        @impl Jido.Chat.Adapters.Threading
        def supports_threads?, do: true

        @impl Jido.Chat.Adapters.Threading
        def compute_thread_root(raw) do
          # Slack uses thread_ts as the thread identifier
          raw["thread_ts"] || raw["ts"]
        end

        @impl Jido.Chat.Adapters.Threading
        def extract_thread_context(raw) do
          %{
            thread_id: raw["thread_ts"],
            is_thread_reply: raw["thread_ts"] != nil,
            thread_root_ts: raw["thread_ts"] || raw["ts"]
          }
        end
      end

  ## Default Implementations

  All callbacks are optional. The defaults assume no threading support:

    * `supports_threads?/0` - Returns `false`
    * `compute_thread_root/1` - Returns `nil`
    * `extract_thread_context/1` - Returns empty map
  """

  @type thread_context :: %{
          optional(:thread_id) => String.t() | nil,
          optional(:is_thread_reply) => boolean(),
          optional(:thread_root_ts) => String.t() | nil
        }

  @doc """
  Returns whether this channel supports threading.

  Used for capability detection and feature gating.
  """
  @callback supports_threads?() :: boolean()

  @doc """
  Computes the thread root identifier from a raw message payload.

  The thread root is the first message in a thread. For messages that are
  not part of a thread, this typically returns `nil` or the message's own ID.

  ## Parameters

    * `raw` - The raw platform-specific message payload

  ## Returns

  The thread root identifier as a string, or `nil` if not applicable.
  """
  @callback compute_thread_root(raw :: map()) :: String.t() | nil

  @doc """
  Extracts threading context from a raw message payload.

  Returns a map with thread-related information that can be used for
  routing decisions and context building.

  ## Parameters

    * `raw` - The raw platform-specific message payload

  ## Returns

  A map that may contain:
    * `:thread_id` - The thread identifier
    * `:is_thread_reply` - Whether this message is a reply in a thread
    * `:thread_root_ts` - The timestamp/ID of the thread root message
  """
  @callback extract_thread_context(raw :: map()) :: thread_context()

  @optional_callbacks supports_threads?: 0, compute_thread_root: 1, extract_thread_context: 1

  @doc """
  Checks if a module implements the Threading behaviour and supports threads.

  Returns `true` only if the module implements `supports_threads?/0` and it returns `true`.
  """
  @spec supports_threads?(module()) :: boolean()
  def supports_threads?(module) do
    function_exported?(module, :supports_threads?, 0) and module.supports_threads?()
  end

  @doc """
  Safely computes the thread root for a module.

  Returns `nil` if the module doesn't implement the callback.
  """
  @spec compute_thread_root(module(), map()) :: String.t() | nil
  def compute_thread_root(module, raw) do
    if function_exported?(module, :compute_thread_root, 1) do
      module.compute_thread_root(raw)
    else
      nil
    end
  end

  @doc """
  Safely extracts thread context for a module.

  Returns an empty map if the module doesn't implement the callback.
  """
  @spec extract_thread_context(module(), map()) :: thread_context()
  def extract_thread_context(module, raw) do
    if function_exported?(module, :extract_thread_context, 1) do
      module.extract_thread_context(raw)
    else
      %{}
    end
  end
end
