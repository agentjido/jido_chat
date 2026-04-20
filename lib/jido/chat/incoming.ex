defmodule Jido.Chat.Incoming do
  @moduledoc """
  Canonical normalized inbound message/event payload.
  """

  alias Jido.Chat.{Author, ChannelMeta, Media, Mention}
  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              external_room_id: Zoi.any(),
              external_user_id: Zoi.any() |> Zoi.nullish(),
              text: Zoi.string() |> Zoi.nullish(),
              author: Zoi.struct(Author) |> Zoi.nullish(),
              username: Zoi.string() |> Zoi.nullish(),
              display_name: Zoi.string() |> Zoi.nullish(),
              external_message_id: Zoi.any() |> Zoi.nullish(),
              external_reply_to_id: Zoi.any() |> Zoi.nullish(),
              external_thread_id: Zoi.string() |> Zoi.nullish(),
              delivery_external_room_id: Zoi.string() |> Zoi.nullish(),
              timestamp: Zoi.any() |> Zoi.nullish(),
              chat_type: Zoi.atom() |> Zoi.nullish(),
              chat_title: Zoi.string() |> Zoi.nullish(),
              was_mentioned: Zoi.boolean() |> Zoi.default(false),
              mentions: Zoi.array(Zoi.struct(Mention)) |> Zoi.default([]),
              media: Zoi.array(Zoi.struct(Media)) |> Zoi.default([]),
              channel_meta: Zoi.struct(ChannelMeta) |> Zoi.default(%ChannelMeta{}),
              raw: Zoi.map() |> Zoi.default(%{}),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Incoming."
  def schema, do: @schema

  @doc "Creates a normalized incoming payload."
  def new(attrs) when is_map(attrs) do
    attrs
    |> maybe_attach_author()
    |> maybe_normalize_mentions()
    |> maybe_normalize_media()
    |> maybe_normalize_channel_meta()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes the incoming payload into a plain map with a type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = incoming) do
    incoming
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "incoming")
  end

  @doc "Builds an incoming payload from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: map |> Map.drop(["__type__", :__type__]) |> new()

  defp maybe_attach_author(%{author: %Author{}} = attrs), do: attrs

  defp maybe_attach_author(%{author: author} = attrs) when is_map(author),
    do: Map.put(attrs, :author, Author.new(author))

  defp maybe_attach_author(attrs) do
    user_id = attrs[:external_user_id] || attrs["external_user_id"]
    username = attrs[:username] || attrs["username"]
    display_name = attrs[:display_name] || attrs["display_name"]

    if is_nil(user_id) do
      attrs
    else
      attrs
      |> Map.delete("author")
      |> Map.put_new(
        :author,
        %Author{
          user_id: to_string(user_id),
          user_name: username || to_string(user_id),
          full_name: display_name || username
        }
      )
    end
  end

  defp maybe_normalize_mentions(attrs) do
    mentions = attrs[:mentions] || attrs["mentions"]

    case mentions do
      nil ->
        attrs

      list when is_list(list) ->
        attrs
        |> Map.delete("mentions")
        |> Map.put(:mentions, Enum.map(list, &normalize_mention/1))

      _other ->
        attrs
    end
  end

  defp maybe_normalize_media(attrs) do
    media = attrs[:media] || attrs["media"]

    case media do
      nil ->
        attrs

      list when is_list(list) ->
        attrs
        |> Map.delete("media")
        |> Map.put(:media, Enum.map(list, &normalize_media/1))

      _other ->
        attrs
    end
  end

  defp normalize_mention(%Mention{} = mention), do: mention
  defp normalize_mention(map) when is_map(map), do: Mention.new(map)
  defp normalize_mention(other), do: other

  defp normalize_media(%Media{} = media), do: media
  defp normalize_media(map) when is_map(map), do: Media.normalize(map)
  defp normalize_media(other), do: other

  defp maybe_normalize_channel_meta(attrs) do
    channel_meta = attrs[:channel_meta] || attrs["channel_meta"]

    case channel_meta do
      nil ->
        attrs

      %ChannelMeta{} ->
        attrs

      map when is_map(map) ->
        attrs
        |> Map.delete("channel_meta")
        |> Map.put(:channel_meta, ChannelMeta.new(map))

      _other ->
        attrs
    end
  end
end
