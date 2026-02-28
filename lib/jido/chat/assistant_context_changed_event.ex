defmodule Jido.Chat.AssistantContextChangedEvent do
  @moduledoc """
  Normalized assistant-context-changed event.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              adapter_name: Zoi.atom() |> Zoi.nullish(),
              thread_id: Zoi.string(),
              context: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{}),
              raw: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for AssistantContextChangedEvent."
  def schema, do: @schema

  @doc "Creates a normalized assistant context changed event."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
