defmodule Jido.Chat.ModalSubmitEvent do
  @moduledoc """
  Normalized modal submit event payload placeholder for Phase 2.
  """

  alias Jido.Chat.Author

  @schema Zoi.struct(
            __MODULE__,
            %{
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              callback_id: Zoi.string() |> Zoi.nullish(),
              view_id: Zoi.string() |> Zoi.nullish(),
              values: Zoi.map() |> Zoi.default(%{}),
              user: Zoi.struct(Author) |> Zoi.nullish(),
              raw: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for ModalSubmitEvent."
  def schema, do: @schema

  @doc "Creates a normalized modal submit event payload."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
