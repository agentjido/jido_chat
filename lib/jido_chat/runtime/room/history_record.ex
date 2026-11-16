defmodule Jido.Chat.Runtime.Room.HistoryRecord do
  @moduledoc "One immutable durable Room message fact."

  @enforce_keys [:schema_version, :room_id, :message_id, :sequence, :thread_id, :signal, :inserted_at]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @doc "Builds one validated history record."
  @spec new(map() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = value), do: validate(value)

  def new(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new(:schema_version, 1)
      |> Map.put_new(:inserted_at, DateTime.utc_now())

    if Map.keys(attrs) -- @enforce_keys == [] do
      attrs |> then(&struct(__MODULE__, &1)) |> validate()
    else
      {:error, :invalid_history_record}
    end
  end

  def new(_value), do: {:error, :invalid_history_record}

  @doc "Builds one history record or raises."
  def new!(attrs), do: unwrap!(new(attrs))

  defp validate(%__MODULE__{} = value) do
    signal = value.signal

    valid =
      value.schema_version == 1 and valid_id?(value.room_id) and valid_id?(value.message_id) and
        is_integer(value.sequence) and value.sequence > 0 and
        (is_nil(value.thread_id) or valid_id?(value.thread_id)) and
        match?(%Jido.Signal{id: id} when id == value.message_id, signal) and
        signal.type == Jido.Chat.Runtime.Signal.Room.Message.type() and
        match?(%Jido.Agent.Address{id: id} when id == value.room_id, signal.data["room"]) and
        signal.data["sequence"] == value.sequence and
        get_in(signal.data, ["message", "id"]) == value.message_id and
        get_in(signal.data, ["message", "thread_id"]) == value.thread_id and
        match?(%DateTime{utc_offset: 0, std_offset: 0}, value.inserted_at)

    if valid, do: {:ok, value}, else: {:error, :invalid_history_record}
  end

  defp valid_id?(value), do: is_binary(value) and byte_size(value) in 1..256

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: raise(ArgumentError, "invalid Room history record: #{inspect(reason)}")
end
