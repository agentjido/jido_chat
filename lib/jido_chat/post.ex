defmodule Jido.Chat.Post do
  @moduledoc """
  Portable content that can be posted to a provider or local Runtime room.

  The destination stays outside this value. A Post contains no Client,
  credential, process, or retry state.
  """

  alias Jido.Chat.Content

  @fields [:content, :thread_id, :reply_to_id, :mentions, :metadata]
  @schema Zoi.struct(
            __MODULE__,
            %{
              content: Zoi.list(Zoi.struct(Content)) |> Zoi.min(1),
              thread_id: Zoi.string() |> Zoi.nullish(),
              reply_to_id: Zoi.string() |> Zoi.nullish(),
              mentions: Zoi.list(Zoi.string() |> Zoi.min(1)) |> Zoi.default([]),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the portable post schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a portable post."
  @spec new(t() | map() | String.t()) :: t()
  def new(%__MODULE__{} = value), do: value |> Map.from_struct() |> new()
  def new(text) when is_binary(text), do: new(%{content: [Content.text(text)]})

  def new(attrs) when is_map(attrs) do
    attrs
    |> Jido.Chat.Value.without_marker()
    |> Jido.Chat.Value.normalize_keys(@fields)
    |> normalize_content()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Creates a plain text post."
  @spec text(String.t(), keyword()) :: t()
  def text(text, opts \\ []) do
    new(%{
      content: [Content.text(text)],
      thread_id: opts[:thread_id],
      reply_to_id: opts[:reply_to_id],
      mentions: opts[:mentions] || [],
      metadata: opts[:metadata] || %{}
    })
  end

  @doc "Returns accessible text for the complete post."
  @spec fallback_text(t()) :: String.t()
  def fallback_text(%__MODULE__{} = value) do
    value.content
    |> Enum.map(&Content.fallback_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @doc "Serializes the post to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = value) do
    Jido.Chat.Value.plain_struct(new(value), "post", %{
      content: Enum.map(value.content, &Content.to_map/1)
    })
  end

  @doc "Restores a post from a portable map."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  defp normalize_content(attrs) do
    case attrs[:content] do
      values when is_list(values) -> Map.put(attrs, :content, Enum.map(values, &Content.new/1))
      value when is_binary(value) -> Map.put(attrs, :content, [Content.text(value)])
      _ -> attrs
    end
  end
end
