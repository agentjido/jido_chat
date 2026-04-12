defmodule Jido.Chat.PostPayload do
  @moduledoc """
  Typed normalized outbound payload used by thread/channel posting helpers.
  """

  alias Jido.Chat.{Attachment, Wire}

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind:
                Zoi.enum([:text, :markdown, :raw, :ast, :card, :stream])
                |> Zoi.default(:text),
              text: Zoi.string() |> Zoi.nullish(),
              formatted: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish(),
              attachments: Zoi.array(Zoi.struct(Attachment)) |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for PostPayload."
  def schema, do: @schema

  @doc "Creates a normalized post payload."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_attachments()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds a text payload."
  @spec text(String.t()) :: t()
  def text(value) when is_binary(value), do: new(%{kind: :text, text: value, formatted: value})

  @doc "Builds a stream payload marker."
  @spec stream() :: t()
  def stream, do: new(%{kind: :stream})

  @doc "Serializes post payload into plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = payload) do
    payload
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "post_payload")
  end

  @doc "Builds post payload from serialized data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  defp normalize_attachments(attrs) do
    attachments = attrs[:attachments] || attrs["attachments"] || []

    attrs
    |> Map.delete("attachments")
    |> Map.put(:attachments, Attachment.normalize_many(attachments))
  end
end
