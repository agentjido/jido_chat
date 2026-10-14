defmodule Jido.Chat.StreamChunk do
  @moduledoc """
  Typed stream input chunk used by outbound stream payloads.
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind:
                Zoi.enum([
                  :text,
                  :markdown,
                  :status,
                  :plan,
                  :data,
                  :step_start,
                  :step_finish,
                  :timeline
                ])
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

  def fallback_text(%__MODULE__{kind: kind, text: text})
      when kind in [:text, :markdown] and is_binary(text),
      do: text

  def fallback_text(%__MODULE__{kind: kind, text: text, payload: payload}) do
    cond do
      is_binary(text) and text != "" ->
        plain_text(text)

      kind in [:step_start, :step_finish, :status] ->
        payload |> payload_label() |> plain_text()

      kind == :plan ->
        payload_lines(payload)

      kind == :timeline ->
        timeline_lines(payload)

      true ->
        payload |> payload_label() |> plain_text()
    end
  end

  @doc "Returns a deterministic Markdown fallback for a text or structured chunk."
  @spec markdown_fallback(term()) :: String.t()
  def markdown_fallback(value) when is_binary(value), do: value
  def markdown_fallback(%{} = value) when not is_struct(value), do: value |> new() |> markdown_fallback()

  def markdown_fallback(%__MODULE__{kind: kind} = chunk) when kind in [:text, :markdown],
    do: chunk.text || ""

  def markdown_fallback(%__MODULE__{kind: :status} = chunk) do
    case fallback_text(chunk) do
      "" -> ""
      text -> bracketed_markdown("Status", text)
    end
  end

  def markdown_fallback(%__MODULE__{kind: :plan} = chunk) do
    case payload_items(chunk.payload, [:steps, :items]) do
      [] -> bracketed_markdown("Plan", fallback_text(chunk))
      items -> "\n**Plan**\n\n" <> Enum.map_join(items, "\n", &("- " <> item_label(&1))) <> "\n"
    end
  end

  def markdown_fallback(%__MODULE__{kind: :step_start} = chunk),
    do: checklist_markdown(" ", fallback_text(chunk))

  def markdown_fallback(%__MODULE__{kind: :step_finish} = chunk),
    do: checklist_markdown("x", fallback_text(chunk))

  def markdown_fallback(%__MODULE__{kind: :timeline} = chunk) do
    case payload_items(chunk.payload, [:events, :entries, :items]) do
      [] ->
        bracketed_markdown("Timeline", fallback_text(chunk))

      items ->
        "\n**Timeline**\n\n" <>
          Enum.map_join(items, "\n", &("- " <> timeline_item(&1))) <> "\n"
    end
  end

  def markdown_fallback(%__MODULE__{kind: :data}), do: ""
  def markdown_fallback(value), do: to_string(value)

  defp checklist_markdown(_mark, ""), do: ""
  defp checklist_markdown(mark, text), do: "\n- [#{mark}] #{inline_text(text)}\n"

  defp bracketed_markdown(_label, ""), do: ""
  defp bracketed_markdown(label, text), do: "\n> **#{label}:** #{inline_text(text)}\n"

  defp payload_items(payload, _keys) when is_list(payload), do: payload

  defp payload_items(payload, keys) when is_map(payload) do
    Enum.find_value(keys, [], fn key ->
      case Map.get(payload, key, Map.get(payload, Atom.to_string(key))) do
        items when is_list(items) -> items
        _other -> nil
      end
    end)
  end

  defp payload_items(_payload, _keys), do: []

  defp timeline_item(item) when is_map(item) do
    {at, label} = raw_timeline_item(item)
    label = inline_text(label)
    if at in [nil, ""], do: label, else: "#{inline_text(at)} — #{label}"
  end

  defp timeline_item(item), do: item_label(item)

  defp item_label(item), do: item |> raw_item_label() |> inline_text()

  defp map_value(map, keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key, Map.get(map, Atom.to_string(key))) end)
  end

  defp inline_text(text) do
    text
    |> to_string()
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")
    |> String.replace(~r/([\\`*_\[\]])/u, "\\\\\\1")
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
    |> Enum.map(&plain_item_label/1)
    |> Enum.join("\n")
  end

  defp payload_lines(payload) when is_map(payload) do
    case payload_items(payload, [:steps, :items]) do
      [] -> payload |> payload_label() |> plain_text()
      items -> Enum.map_join(items, "\n", &plain_item_label/1)
    end
  end

  defp payload_lines(payload), do: payload |> payload_label() |> plain_text()

  defp timeline_lines(payload) do
    case payload_items(payload, [:events, :entries, :items]) do
      [] -> payload |> payload_label() |> plain_text()
      items -> Enum.map_join(items, "\n", &plain_timeline_item/1)
    end
  end

  defp plain_timeline_item(item) when is_map(item) do
    {at, label} = raw_timeline_item(item)
    label = plain_text(label)
    if at in [nil, ""], do: label, else: "#{plain_text(at)} — #{label}"
  end

  defp plain_timeline_item(item), do: plain_item_label(item)

  defp plain_item_label(item), do: item |> raw_item_label() |> plain_text()

  defp raw_timeline_item(item) do
    {map_value(item, [:at, :time, :timestamp]), raw_item_label(item)}
  end

  defp raw_item_label(item) when is_binary(item), do: item

  defp raw_item_label(item) when is_map(item) do
    map_value(item, [:label, :title, :text, :description, :name]) ||
      inspect(item, limit: 50, printable_limit: 200)
  end

  defp raw_item_label(item), do: to_string(item)

  defp plain_text(nil), do: ""

  defp plain_text(text) do
    text |> to_string() |> String.trim() |> String.replace(~r/\s+/u, " ")
  end

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
end
