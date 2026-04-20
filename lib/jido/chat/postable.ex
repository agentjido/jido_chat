defmodule Jido.Chat.Postable do
  @moduledoc """
  Typed post payload accepted by thread/channel post helpers.
  """

  alias Jido.Chat.{Attachment, Card, FileUpload, Markdown, PostPayload}

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind:
                Zoi.enum([:raw, :markdown, :ast, :card, :text, :stream])
                |> Zoi.default(:text),
              text: Zoi.string() |> Zoi.nullish(),
              markdown: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish(),
              ast: Zoi.any() |> Zoi.nullish(),
              card: Zoi.any() |> Zoi.nullish(),
              stream: Zoi.any() |> Zoi.nullish(),
              fallback_text: Zoi.string() |> Zoi.nullish(),
              attachments: Zoi.array(Zoi.struct(Attachment)) |> Zoi.default([]),
              files: Zoi.array(Zoi.struct(FileUpload)) |> Zoi.default([]),
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

  def new(attrs) when is_map(attrs) do
    attrs
    |> PostPayload.new()
    |> Map.from_struct()
    |> Map.take([
      :kind,
      :text,
      :markdown,
      :raw,
      :ast,
      :card,
      :stream,
      :fallback_text,
      :attachments,
      :files,
      :metadata
    ])
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds a text post payload."
  def text(value, opts \\ []) when is_binary(value),
    do: new(Map.merge(normalize_opts(opts), %{kind: :text, text: value}))

  @doc "Builds a markdown post payload."
  def markdown(value, opts \\ [])

  def markdown(value, opts) when is_binary(value),
    do: new(Map.merge(normalize_opts(opts), %{kind: :markdown, markdown: value, text: value}))

  def markdown(%Markdown{} = value, opts) do
    new(
      Map.merge(normalize_opts(opts), %{
        kind: :markdown,
        markdown: Markdown.stringify(value),
        text: Markdown.plain_text(value)
      })
    )
  end

  @doc "Builds a raw payload wrapper."
  def raw(value, opts \\ []), do: new(Map.merge(normalize_opts(opts), %{kind: :raw, raw: value}))

  @doc "Builds an AST payload wrapper."
  def ast(value, opts \\ []), do: new(Map.merge(normalize_opts(opts), %{kind: :ast, ast: value}))

  @doc "Builds a card payload wrapper."
  def card(value, opts \\ [])

  def card(%Card{} = value, opts),
    do: new(Map.merge(normalize_opts(opts), %{kind: :card, card: value}))

  def card(value, opts),
    do: new(Map.merge(normalize_opts(opts), %{kind: :card, card: value}))

  @doc "Builds a stream payload wrapper."
  def stream(chunks, opts \\ []),
    do: new(Map.merge(normalize_opts(opts), %{kind: :stream, stream: chunks}))

  @doc "Builds a normalized outbound payload preserving post intent."
  @spec to_payload(t()) :: PostPayload.t()
  def to_payload(%__MODULE__{} = postable), do: postable |> Map.from_struct() |> PostPayload.new()

  @doc "Flattens postable payload into adapter-safe text."
  @spec to_text(t()) :: String.t()
  def to_text(%__MODULE__{} = postable) do
    payload = to_payload(postable)
    PostPayload.display_text(payload) || ""
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
end
