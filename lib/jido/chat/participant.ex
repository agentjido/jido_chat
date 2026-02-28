defmodule Jido.Chat.Participant do
  @moduledoc """
  Represents a participant in conversations (human, agent, or system).

  Participants are mapped to external identities via `external_ids`
  which stores platform-specific user IDs.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              type: Zoi.enum([:human, :agent, :system]),
              identity: Zoi.map() |> Zoi.default(%{}),
              external_ids: Zoi.map() |> Zoi.default(%{}),
              presence: Zoi.enum([:online, :away, :busy, :offline]) |> Zoi.default(:offline),
              capabilities: Zoi.array(Zoi.atom()) |> Zoi.default([:text]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Participant"
  def schema, do: @schema

  @doc "Creates a new participant with generated ID"
  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(:id, Jido.Chat.ID.generate!())
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end
end
