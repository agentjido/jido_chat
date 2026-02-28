defmodule Jido.Chat.EphemeralMessage do
  @moduledoc """
  Canonical result of an ephemeral send attempt.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              thread_id: Zoi.string(),
              used_fallback: Zoi.boolean() |> Zoi.default(false),
              raw: Zoi.any() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for EphemeralMessage."
  def schema, do: @schema

  @doc "Creates an ephemeral message result struct."
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
