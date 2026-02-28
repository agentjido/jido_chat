defmodule Jido.Chat.LegacyMessage do
  @moduledoc """
  Legacy pre-parity message shape retained for migration compatibility.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              room_id: Zoi.string(),
              sender_id: Zoi.string(),
              role: Zoi.enum([:user, :assistant, :system, :tool]),
              content: Zoi.array(Zoi.any()) |> Zoi.default([]),
              reply_to_id: Zoi.string() |> Zoi.nullish(),
              external_id: Zoi.string() |> Zoi.nullish(),
              external_reply_to_id: Zoi.string() |> Zoi.nullish(),
              thread_root_id: Zoi.string() |> Zoi.nullish(),
              external_thread_id: Zoi.string() |> Zoi.nullish(),
              status:
                Zoi.enum([:sending, :sent, :delivered, :read, :failed]) |> Zoi.default(:sending),
              reactions: Zoi.map() |> Zoi.default(%{}),
              receipts: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{}),
              inserted_at: Zoi.struct(DateTime) |> Zoi.nullish(),
              updated_at: Zoi.struct(DateTime) |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for LegacyMessage."
  def schema, do: @schema

  @doc "Creates a legacy message with generated ID and timestamps."
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    attrs
    |> Map.put_new(:id, Jido.Chat.ID.generate!())
    |> Map.put_new(:inserted_at, now)
    |> Map.put_new(:updated_at, now)
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end
end
