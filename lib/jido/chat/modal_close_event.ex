defmodule Jido.Chat.ModalCloseEvent do
  @moduledoc """
  Normalized modal close event payload placeholder for Phase 2.
  """

  alias Jido.Chat.Author

  @schema Zoi.struct(
            __MODULE__,
            %{
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              callback_id: Zoi.string() |> Zoi.nullish(),
              view_id: Zoi.string() |> Zoi.nullish(),
              user: Zoi.struct(Author) |> Zoi.nullish(),
              raw: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ModalCloseEvent."
  def schema, do: @schema

  @doc "Creates a normalized modal close event payload."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
