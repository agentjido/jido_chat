defmodule Jido.Chat.MessageContext do
  @moduledoc """
  Ordered message context for a collapsed queue or burst dispatch.

  `skipped` contains the earlier messages from the same conversation. The
  current message is not in this list. `total_since_last_handler` and
  `total_count` have the same value. The second field gives callers a short,
  transport-neutral name while the first field matches the Chat SDK contract.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              skipped: Zoi.list(Zoi.any()) |> Zoi.default([]),
              total_since_last_handler: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1),
              total_count: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the schema for message context."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates normalized ordered message context."
  @spec new(t() | map() | keyword()) :: t()
  def new(%__MODULE__{} = context), do: context
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(opts) when is_map(opts) do
    skipped = opts[:skipped] || opts["skipped"] || []

    total =
      opts[:total_count] || opts["total_count"] || opts[:total_since_last_handler] ||
        opts["total_since_last_handler"] || length(skipped) + 1

    Jido.Chat.Schema.parse!(__MODULE__, @schema, %{
      skipped: skipped,
      total_since_last_handler: total,
      total_count: total
    })
  end
end
