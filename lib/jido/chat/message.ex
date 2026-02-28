defmodule Jido.Chat.Message do
  @moduledoc """
  Chat SDK-style normalized message model.
  """

  alias Jido.Chat.{Author, Incoming, Media}

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              thread_id: Zoi.string() |> Zoi.nullish(),
              channel_id: Zoi.string() |> Zoi.nullish(),
              text: Zoi.string() |> Zoi.nullish(),
              formatted: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish(),
              author: Zoi.struct(Author) |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{}),
              attachments: Zoi.array(Zoi.struct(Media)) |> Zoi.default([]),
              is_mention: Zoi.boolean() |> Zoi.default(false),
              created_at: Zoi.any() |> Zoi.nullish(),
              updated_at: Zoi.any() |> Zoi.nullish(),
              external_message_id: Zoi.string() |> Zoi.nullish(),
              external_room_id: Zoi.any() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Message."
  def schema, do: @schema

  @doc "Creates a normalized message from map input."
  def new(attrs) when is_map(attrs) do
    attrs
    |> attach_defaults()
    |> normalize_author()
    |> normalize_attachments()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Creates a normalized message from canonical incoming payload."
  @spec from_incoming(Incoming.t(), keyword()) :: t()
  def from_incoming(%Incoming{} = incoming, opts \\ []) do
    thread_id =
      opts[:thread_id] ||
        build_thread_id(
          opts[:adapter_name],
          incoming.external_room_id,
          incoming.external_thread_id
        )

    new(%{
      id: stringify(incoming.external_message_id) || Jido.Chat.ID.generate!(),
      thread_id: thread_id,
      channel_id: stringify(incoming.external_room_id),
      text: incoming.text,
      formatted: incoming.text,
      raw: incoming.raw,
      author: incoming.author,
      metadata: Map.merge(incoming.metadata || %{}, %{channel_meta: incoming.channel_meta}),
      attachments: incoming.media,
      is_mention: incoming.was_mentioned,
      created_at: incoming.timestamp,
      external_message_id: stringify(incoming.external_message_id),
      external_room_id: incoming.external_room_id
    })
  end

  @doc "Serializes the message into a plain map with a revivable type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = message) do
    message
    |> Map.from_struct()
    |> Jido.Chat.Wire.to_plain()
    |> Map.put("__type__", "message")
  end

  @doc "Builds a message from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp attach_defaults(attrs) do
    id = attrs[:id] || attrs["id"] || attrs[:external_message_id] || attrs["external_message_id"]

    text = attrs[:text] || attrs["text"] || attrs[:content] || attrs["content"]

    external_room_id = attrs[:external_room_id] || attrs["external_room_id"]

    attrs
    |> Map.put_new(:id, stringify(id) || Jido.Chat.ID.generate!())
    |> Map.put_new(:thread_id, attrs[:thread_id] || attrs["thread_id"])
    |> Map.put_new(
      :channel_id,
      stringify(attrs[:channel_id] || attrs["channel_id"] || external_room_id)
    )
    |> Map.put_new(:text, text)
    |> Map.put_new(:formatted, attrs[:formatted] || attrs["formatted"] || text)
    |> Map.put_new(:raw, attrs[:raw] || attrs["raw"])
    |> Map.put_new(:metadata, attrs[:metadata] || attrs["metadata"] || %{})
    |> Map.put_new(
      :attachments,
      attrs[:attachments] || attrs["attachments"] || attrs[:media] || attrs["media"] || []
    )
    |> Map.put_new(:is_mention, attrs[:is_mention] || attrs["is_mention"] || false)
    |> Map.put_new(
      :created_at,
      attrs[:created_at] || attrs["created_at"] || attrs[:timestamp] || attrs["timestamp"]
    )
    |> Map.put_new(:updated_at, attrs[:updated_at] || attrs["updated_at"])
    |> Map.put_new(
      :external_message_id,
      stringify(attrs[:external_message_id] || attrs["external_message_id"] || id)
    )
    |> Map.put_new(:external_room_id, external_room_id)
  end

  defp normalize_author(%{author: %Author{}} = attrs), do: attrs

  defp normalize_author(%{author: author} = attrs) when is_map(author),
    do: Map.put(attrs, :author, Author.new(author))

  defp normalize_author(%{"author" => %Author{}} = attrs), do: attrs

  defp normalize_author(%{"author" => author} = attrs) when is_map(author),
    do: Map.put(attrs, :author, Author.new(author))

  defp normalize_author(attrs), do: attrs

  defp normalize_attachments(attrs) do
    attachments = attrs[:attachments] || attrs["attachments"] || []

    normalized =
      Enum.map(attachments, fn
        %Media{} = media -> media
        map when is_map(map) -> Media.new(map)
        other -> other
      end)

    Map.put(attrs, :attachments, normalized)
  end

  defp build_thread_id(nil, nil, nil), do: nil
  defp build_thread_id(nil, room_id, nil), do: stringify(room_id)

  defp build_thread_id(nil, room_id, thread_id),
    do: "#{stringify(room_id)}:#{stringify(thread_id)}"

  defp build_thread_id(adapter_name, room_id, nil), do: "#{adapter_name}:#{room_id}"

  defp build_thread_id(adapter_name, room_id, thread_id),
    do: "#{adapter_name}:#{room_id}:#{thread_id}"

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
