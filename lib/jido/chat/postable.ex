defmodule Jido.Chat.Postable do
  @moduledoc """
  Typed post payload accepted by thread/channel post helpers.
  """

  alias Jido.Chat.PostPayload

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum([:raw, :markdown, :ast, :card, :text]) |> Zoi.default(:text),
              text: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish(),
              ast: Zoi.any() |> Zoi.nullish(),
              card: Zoi.any() |> Zoi.nullish(),
              attachments: Zoi.array(Zoi.any()) |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Postable."
  def schema, do: @schema

  @doc "Creates a new typed post payload."
  def new(%__MODULE__{} = postable), do: postable
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc "Builds a text post payload."
  def text(value) when is_binary(value), do: new(%{kind: :text, text: value})

  @doc "Builds a markdown post payload."
  def markdown(value) when is_binary(value), do: new(%{kind: :markdown, text: value})

  @doc "Builds a raw payload wrapper."
  def raw(value), do: new(%{kind: :raw, raw: value})

  @doc "Builds an AST payload wrapper."
  def ast(value), do: new(%{kind: :ast, ast: value})

  @doc "Builds a card payload wrapper."
  def card(value), do: new(%{kind: :card, card: value})

  @doc "Builds a normalized outbound payload preserving post intent."
  @spec to_payload(t()) :: PostPayload.t()
  def to_payload(%__MODULE__{} = postable) do
    attachments = postable.attachments || []
    metadata = postable.metadata || %{}

    case postable.kind do
      :text ->
        PostPayload.new(%{
          kind: :text,
          text: postable.text,
          formatted: postable.text,
          attachments: attachments,
          metadata: metadata
        })

      :markdown ->
        text = postable.text || ""

        PostPayload.new(%{
          kind: :markdown,
          text: text,
          formatted: text,
          attachments: attachments,
          metadata: Map.put(metadata, :format, :markdown)
        })

      :raw ->
        text = to_text_value(postable.raw)

        PostPayload.new(%{
          kind: :raw,
          text: text,
          formatted: text,
          raw: postable.raw,
          attachments: attachments,
          metadata: metadata
        })

      :ast ->
        text = to_text_value(postable.ast)

        PostPayload.new(%{
          kind: :ast,
          text: text,
          formatted: text,
          raw: postable.ast,
          attachments: attachments,
          metadata: Map.put(metadata, :format, :ast)
        })

      :card ->
        text = to_text_value(postable.card)

        PostPayload.new(%{
          kind: :card,
          text: text,
          formatted: text,
          raw: postable.card,
          attachments: attachments,
          metadata: Map.put(metadata, :format, :card)
        })
    end
  end

  @doc "Flattens postable payload into adapter-safe text."
  @spec to_text(t()) :: String.t()
  def to_text(%__MODULE__{} = postable) do
    payload = to_payload(postable)
    payload.text || ""
  end

  defp to_text_value(value) when is_binary(value), do: value

  defp to_text_value(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> encoded
      {:error, _reason} -> inspect(value)
    end
  end
end
