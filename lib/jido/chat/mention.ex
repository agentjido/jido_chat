defmodule Jido.Chat.Mention do
  @moduledoc """
  Normalized mention entry used in `Jido.Chat.Incoming`.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              user_id: Zoi.string() |> Zoi.nullish(),
              username: Zoi.string() |> Zoi.nullish(),
              display_name: Zoi.string() |> Zoi.nullish(),
              mention_text: Zoi.string() |> Zoi.nullish(),
              is_self: Zoi.boolean() |> Zoi.default(false),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Mention."
  def schema, do: @schema

  @doc "Creates a mention struct from map input."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
