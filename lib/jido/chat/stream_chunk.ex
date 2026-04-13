defmodule Jido.Chat.StreamChunk do
  @moduledoc """
  Typed stream input chunk used by outbound stream payloads.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind:
                Zoi.enum([:text, :markdown, :status, :plan, :data, :step_start, :step_finish])
                |> Zoi.default(:text),
              text: Zoi.string() |> Zoi.nullish(),
              payload: Zoi.any() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @type input :: t() | String.t() | map()

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for StreamChunk."
  def schema, do: @schema

  @doc "Creates a stream chunk from normalized map input."
  def new(%__MODULE__{} = chunk), do: chunk
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc "Builds a text chunk."
  @spec text(String.t(), keyword() | map()) :: t()
  def text(value, opts \\ []) when is_binary(value) do
    opts = normalize_opts(opts)
    new(Map.merge(opts, %{kind: :text, text: value}))
  end

  @doc "Normalizes supported stream chunk inputs."
  @spec normalize(input()) :: t() | String.t()
  def normalize(%__MODULE__{} = chunk), do: chunk
  def normalize(value) when is_binary(value), do: value
  def normalize(attrs) when is_map(attrs), do: new(attrs)

  @doc "Normalizes a list of stream chunk inputs."
  @spec normalize_many([input()]) :: [t() | String.t()]
  def normalize_many(chunks) when is_list(chunks), do: Enum.map(chunks, &normalize/1)

  @doc "Returns the best text fallback for the chunk."
  @spec fallback_text(t() | String.t()) :: String.t()
  def fallback_text(value) when is_binary(value), do: value

  def fallback_text(%__MODULE__{kind: kind, text: text, payload: payload}) do
    cond do
      is_binary(text) and text != "" ->
        text

      kind in [:step_start, :step_finish] ->
        payload_label(payload)

      kind == :plan ->
        payload_lines(payload)

      kind == :status ->
        payload_label(payload)

      true ->
        payload_label(payload) || ""
    end
  end

  @doc "Serializes a stream chunk into a plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = chunk) do
    chunk
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "stream_chunk")
  end

  @doc "Builds a stream chunk from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp payload_label(%{label: label}) when is_binary(label), do: label
  defp payload_label(%{"label" => label}) when is_binary(label), do: label
  defp payload_label(%{title: title}) when is_binary(title), do: title
  defp payload_label(%{"title" => title}) when is_binary(title), do: title
  defp payload_label(payload) when is_binary(payload), do: payload
  defp payload_label(_payload), do: nil

  defp payload_lines(payload) when is_list(payload) do
    payload
    |> Enum.map(&to_string/1)
    |> Enum.join("\n")
  end

  defp payload_lines(payload), do: payload_label(payload) || ""

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
end
