defmodule Jido.Chat.Concurrency do
  @moduledoc """
  Chat-level overlapping-message concurrency configuration.

  The model is a pure state protocol. It does not start timers or processes.
  Callers supply `now_ms` when they need deterministic timing and call
  `Jido.Chat.drain_lock/4` after the configured idle window.

  Queue and burst entries default to a size of 10 and a lifetime of 90 seconds.
  Burst and debounce idle windows default to 1.5 seconds. Concurrent handlers
  are unbounded unless `max_concurrent` is set.
  """

  @strategies [:reject, :queue, :debounce, :burst, :concurrent]
  @overflow_policies [:drop_oldest, :drop_newest]
  @lock_scopes [:thread, :channel]

  @schema Zoi.struct(
            __MODULE__,
            %{
              strategy: Zoi.enum(@strategies) |> Zoi.default(:reject),
              debounce_ms: Zoi.integer() |> Zoi.min(0) |> Zoi.default(1_500),
              max_queue_size: Zoi.integer() |> Zoi.min(1) |> Zoi.default(10),
              queue_entry_ttl_ms: Zoi.integer() |> Zoi.min(1) |> Zoi.default(90_000),
              overflow_policy: Zoi.enum(@overflow_policies) |> Zoi.default(:drop_oldest),
              lock_scope: Zoi.enum(@lock_scopes) |> Zoi.default(:thread),
              max_concurrent: Zoi.integer() |> Zoi.min(1) |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type strategy :: :reject | :queue | :debounce | :burst | :concurrent
  @type overflow_policy :: :drop_oldest | :drop_newest
  @type lock_scope :: :thread | :channel
  @type t :: unquote(Zoi.type_spec(@schema))

  @type pending_entry :: %{
          owner: String.t(),
          strategy: strategy(),
          metadata: map(),
          enqueued_at: non_neg_integer(),
          expires_at: pos_integer(),
          ready_at: non_neg_integer(),
          conversation_key: String.t()
        }

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for concurrency configuration."
  def schema, do: @schema

  @doc "Creates a normalized concurrency config."
  @spec new(t() | map() | keyword()) :: t()
  def new(%__MODULE__{} = config), do: config
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(opts) when is_map(opts) do
    normalized = normalize_aliases(opts)
    Jido.Chat.Schema.parse!(__MODULE__, @schema, normalized)
  end

  @doc "Returns the lock key for the configured thread or channel scope."
  @spec lock_key(t() | map() | keyword(), String.t(), String.t() | nil) :: String.t()
  def lock_key(config, thread_id, channel_id \\ nil) when is_binary(thread_id) do
    case new(config).lock_scope do
      :channel when is_binary(channel_id) and channel_id != "" -> channel_id
      _ -> thread_id
    end
  end

  @doc "Returns a deterministic message context for drained pending entries."
  @spec message_context([map()]) :: Jido.Chat.MessageContext.t()
  def message_context(entries) when is_list(entries) do
    Jido.Chat.MessageContext.new(
      skipped: Enum.map(entries, &message_from_entry/1),
      total_count: length(entries) + 1
    )
  end

  defp normalize_aliases(opts) do
    %{
      strategy: value(opts, [:strategy, "strategy"], :reject) |> normalize_enum(),
      debounce_ms: value(opts, [:debounce_ms, "debounce_ms", "debounceMs", :idle_ms, "idle_ms"]),
      max_queue_size: value(opts, [:max_queue_size, "max_queue_size", "maxQueueSize"]),
      queue_entry_ttl_ms: value(opts, [:queue_entry_ttl_ms, "queue_entry_ttl_ms", "queueEntryTtlMs"]),
      overflow_policy:
        value(opts, [
          :overflow_policy,
          "overflow_policy",
          :on_queue_full,
          "on_queue_full",
          "onQueueFull"
        ])
        |> normalize_enum(),
      lock_scope: value(opts, [:lock_scope, "lock_scope", "lockScope"]) |> normalize_enum(),
      max_concurrent: value(opts, [:max_concurrent, "max_concurrent", "maxConcurrent"]),
      metadata: value(opts, [:metadata, "metadata"], %{})
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp value(opts, keys, default \\ nil) do
    Enum.find_value(keys, default, fn key ->
      if Map.has_key?(opts, key), do: {:found, Map.get(opts, key)}
    end)
    |> case do
      {:found, value} -> value
      value -> value
    end
  end

  defp normalize_enum(value) when is_binary(value) do
    value
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> value
  end

  defp normalize_enum(value), do: value

  defp message_from_entry(entry) do
    metadata = entry[:metadata] || entry["metadata"] || %{}
    metadata[:message] || metadata["message"] || metadata[:incoming] || metadata["incoming"] || metadata
  end
end
