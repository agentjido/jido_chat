defmodule Jido.Chat.Message do
  @moduledoc """
  Portable normalized chat message snapshot.

  A Message contains chat meaning. It does not contain credentials, process
  references, retry state, grants, or delivery workers.
  """

  alias Jido.Chat.{Actor, Content}

  @roles [:user, :assistant, :system, :tool]
  @fields [
    :id,
    :room_id,
    :thread_id,
    :reply_to_id,
    :actor,
    :role,
    :content,
    :client_id,
    :provider_message_id,
    :timestamp,
    :edited_at,
    :metadata
  ]
  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.min(1),
              room_id: Zoi.string() |> Zoi.min(1),
              thread_id: Zoi.string() |> Zoi.nullish(),
              reply_to_id: Zoi.string() |> Zoi.nullish(),
              actor: Zoi.struct(Actor),
              role: Zoi.enum(@roles) |> Zoi.default(:user),
              content: Zoi.list(Zoi.struct(Content)) |> Zoi.min(1),
              client_id: Zoi.string() |> Zoi.nullish(),
              provider_message_id: Zoi.string() |> Zoi.nullish(),
              timestamp: Zoi.string() |> Zoi.nullish(),
              edited_at: Zoi.string() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the portable message schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a portable normalized message."
  @spec new(t() | map()) :: t()
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> Jido.Chat.Value.normalize_keys(@fields)
    |> Jido.Chat.Value.normalize_enum(:role, @roles)
    |> normalize_actor()
    |> normalize_content()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Returns accessible text for the complete message."
  @spec fallback_text(t()) :: String.t()
  def fallback_text(%__MODULE__{} = value) do
    value.content
    |> Enum.map(&Content.fallback_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @doc "Serializes the message to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    replacements = %{
      actor: Actor.to_map(value.actor),
      content: Enum.map(value.content, &Content.to_map/1)
    }

    Jido.Chat.Value.plain_struct(new(value), "message", replacements)
  end

  @doc "Restores a message from a portable map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  defp normalize_actor(attrs) do
    case attrs[:actor] do
      %Actor{} = value -> Map.put(attrs, :actor, Actor.new(value))
      value when is_map(value) -> Map.put(attrs, :actor, Actor.from_map(value))
      _ -> attrs
    end
  end

  defp normalize_content(attrs) do
    case attrs[:content] do
      values when is_list(values) -> Map.put(attrs, :content, Enum.map(values, &Content.new/1))
      value when is_binary(value) -> Map.put(attrs, :content, [Content.text(value)])
      _ -> attrs
    end
  end
end
