defmodule Jido.Chat.Telegram.Normalizer do
  @moduledoc false
  alias Jido.Chat.{Client, Delivery}

  alias Jido.Chat.Signal.{
    ActionReceived,
    Identity,
    MembershipChanged,
    MessageReceived,
    MessageUpdated,
    NormalizationFailed,
    Policy,
    ReactionAdded,
    ReactionRemoved,
    SlashCommandReceived,
    ThreadChanged,
    ThreadStarted
  }

  alias Jido.Chat.Telegram.Membership

  @message_kinds ~w(message channel_post edited_message edited_channel_post)
  @kinds @message_kinds ++ ~w(chat_member my_chat_member message_reaction callback_query)
  @limits [:signal_too_large, :delivery_too_large, :too_many_signals, :too_many_failures]

  @doc false
  @spec normalize(Client.t(), term()) :: {:ok, Delivery.t()} | {:error, Jido.Chat.Errors.Contract.t()}

  def normalize(%Client{} = client, input) when is_map(input) or is_list(input) do
    updates = if is_list(input), do: input, else: [input]

    result =
      try do
        ids = Enum.map(updates, &update_identity/1)
        delivery_id = if is_map(input), do: hd(ids), else: "telegram:batch:" <> digest(ids)
        context = %{client: client, delivery: delivery_id}

        with {:ok, signals} <- map_updates(context, Enum.zip(updates, ids)),
             do: Delivery.new(client, delivery_id, signals)
      rescue
        _ -> Policy.error(:invalid_delivery)
      catch
        _, _ -> Policy.error(:invalid_delivery)
      end

    result
  end

  def normalize(_binding, _input), do: Policy.error(:invalid_delivery)

  defp map_updates(context, updates) do
    updates
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{update, id}, index}, {:ok, acc} ->
      case map_update(context, update, id, index) do
        {:ok, signals} -> {:cont, {:ok, acc ++ signals}}
        error -> {:halt, error}
      end
    end)
  end

  defp map_update(context, update, id, index) when is_map(update) do
    items = Enum.filter(@kinds, &(not is_nil(field(update, &1))))

    case items do
      [] ->
        if Enum.all?(keys(update), &(&1 == "update_id")),
          do: {:ok, []},
          else: failed(context, id, "unsupported", index, nil, "unsupported_item")

      kinds ->
        Enum.reduce_while(kinds, {:ok, []}, fn kind, {:ok, acc} ->
          payload = field(update, kind)
          room = payload |> field("chat") |> field("id") |> identifier()

          case map_item(context, kind, payload, id) do
            {:ok, signals} ->
              {:cont, {:ok, acc ++ List.wrap(signals)}}

            {:error, %Jido.Chat.Errors.Contract{code: code}} = error when code in @limits ->
              {:halt, error}

            _ ->
              case failed(context, id, kind, index, room, "invalid_item") do
                {:ok, signals} -> {:cont, {:ok, acc ++ signals}}
                error -> {:halt, error}
              end
          end
        end)
    end
  end

  defp map_update(context, _update, id, index), do: failed(context, id, "invalid", index, nil, "invalid_item")

  defp map_item(context, kind, payload, id) when kind in ~w(chat_member my_chat_member) do
    Membership.normalize(context.client, context.delivery, kind, payload, item_id: id <> ":" <> kind)
  end

  defp map_item(context, kind, message, id) when kind in @message_kinds and is_map(message) do
    room = message |> field("chat") |> field("id") |> identifier()
    message_id = message |> field("message_id") |> identifier()
    sender = sender(field(message, "from") || field(message, "sender_chat") || channel_sender(message), context.client)
    text = field(message, "text") || field(message, "caption") || ""
    thread = message |> field("message_thread_id") |> identifier()
    service = field(message, "new_chat_members") || field(message, "left_chat_member")

    cond do
      topic_service?(message) ->
        topic_event(context, message, id, room, thread)

      service ->
        service_members(context, message, id, room)

      true ->
        with true <- is_binary(room) and is_binary(message_id),
             subject <- Identity.conversation_subject(context.client.id, room),
             {:ok, media} <- media(context, message) do
          base = %{
            "room_id" => room,
            "message_id" => message_id,
            "sender" => sender,
            "text" => text,
            "thread_id" => thread,
            "media" => media,
            "timestamp" => timestamp(field(message, "edit_date") || field(message, "date"))
          }

          base = select_present(base)
          edited = kind in ~w(edited_message edited_channel_post)
          definition = if edited, do: MessageUpdated, else: MessageReceived

          data =
            if edited do
              base
            else
              base
              |> Map.put("conversation_kind", conversation_kind(message |> field("chat") |> field("type")))
              |> optional("conversation_name", message |> field("chat") |> field("title"))
              |> optional("reply_to_id", message |> field("reply_to_message") |> field("message_id") |> identifier())
              |> optional("reply_context", reply_context(field(message, "reply_to_message"), context.client))
              |> Map.merge(mentions(message, context.client))
            end

          with {:ok, signal} <- build(context, definition, id <> ":" <> kind, data, subject),
               {:ok, command} <- slash(context, message, id, room, sender, thread, edited),
               do: {:ok, [signal | command]}
        else
          {:error, %Jido.Chat.Errors.Contract{}} = error -> error
          _ -> Policy.error(:invalid_delivery)
        end
    end
  end

  defp map_item(context, "message_reaction", payload, id) when is_map(payload) do
    room = payload |> field("chat") |> field("id") |> identifier()
    actor = payload |> field("user") |> field("id") |> identifier()
    actor = actor || chat_actor(field(payload, "actor_chat"))
    previous = Enum.map(field(payload, "old_reaction") || [], &reaction/1)
    current = Enum.map(field(payload, "new_reaction") || [], &reaction/1)

    changes =
      Enum.map(previous -- current, &{ReactionRemoved, &1}) ++ Enum.map(current -- previous, &{ReactionAdded, &1})

    changes
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{definition, value}, ordinal}, {:ok, acc} ->
      data = %{
        "room_id" => room,
        "message_id" => identifier(field(payload, "message_id")),
        "actor_id" => actor,
        "reaction" => value
      }

      case build(context, definition, id <> ":reaction:" <> to_string(ordinal), data) do
        {:ok, signal} -> {:cont, {:ok, acc ++ [signal]}}
        error -> {:halt, error}
      end
    end)
  end

  defp map_item(context, "callback_query", payload, id) when is_map(payload) do
    message = field(payload, "message")
    room = message |> field("chat") |> field("id") |> identifier()
    interaction = identifier(field(payload, "id"))

    data = %{
      "room_id" => room,
      "interaction_id" => interaction,
      "action_id" => field(payload, "data") || interaction,
      "value" => field(payload, "data"),
      "actor_id" => payload |> field("from") |> field("id") |> identifier(),
      "message_id" => message |> field("message_id") |> identifier(),
      "thread_id" => message |> field("message_thread_id") |> identifier()
    }

    build(context, ActionReceived, id <> ":callback_query", data)
  end

  defp map_item(_context, _kind, _payload, _id), do: Policy.error(:invalid_delivery)

  defp topic_service?(message) do
    Enum.any?(
      ~w(forum_topic_created forum_topic_edited forum_topic_closed forum_topic_reopened
                 general_forum_topic_hidden general_forum_topic_unhidden),
      &(not is_nil(field(message, &1)))
    )
  end

  defp topic_event(context, message, id, room, thread) do
    created = field(message, "forum_topic_created")
    edited = field(message, "forum_topic_edited")

    data =
      %{
        "room_id" => room,
        "thread_id" =>
          thread ||
            if(field(message, "general_forum_topic_hidden") || field(message, "general_forum_topic_unhidden"), do: "1"),
        "actor_id" => message |> field("from") |> field("id") |> identifier()
      }
      |> optional("name", field(created || edited, "name"))

    {definition, data} =
      if created do
        {ThreadStarted, data}
      else
        change =
          cond do
            field(message, "forum_topic_closed") || field(message, "general_forum_topic_hidden") -> "closed"
            field(message, "forum_topic_reopened") || field(message, "general_forum_topic_unhidden") -> "reopened"
            true -> "updated"
          end

        {ThreadChanged, Map.put(data, "change", change)}
      end

    with {:ok, signal} <- build(context, definition, id <> ":topic", data), do: {:ok, [signal]}
  end

  defp service_members(context, message, id, room) do
    joined = field(message, "new_chat_members") || []
    left = field(message, "left_chat_member")

    changes =
      Enum.map(joined, &{&1, "joined", "explicit_join", "member", true}) ++
        if(left, do: [{left, "left", "explicit_leave", "left", false}], else: [])

    changes
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{user, transition, evidence, status, is_member}, ordinal}, {:ok, acc} ->
      peer = identifier(field(user, "id"))

      data = %{
        "room_id" => room,
        "participant_id" => peer,
        "actor_id" => message |> field("from") |> field("id") |> identifier(),
        "bot_self" => peer == identifier(context.client.config[:bot_id]),
        "transition" => transition,
        "evidence" => evidence,
        "previous" => nil,
        "current" => %{"status" => status, "is_member" => is_member}
      }

      case build(context, MembershipChanged, id <> ":service_member:" <> to_string(ordinal), data) do
        {:ok, signal} -> {:cont, {:ok, acc ++ [signal]}}
        error -> {:halt, error}
      end
    end)
  end

  defp slash(_context, _message, _id, _room, _sender, _thread, true), do: {:ok, []}

  defp slash(context, message, id, room, sender, thread, false) do
    text = field(message, "text")

    case if(is_binary(text), do: Regex.run(~r/^\/([A-Za-z0-9_]+)(?:@[A-Za-z0-9_]+)?(?:\s+(.*))?$/s, text)) do
      [_, command | arguments] ->
        data = %{
          "room_id" => room,
          "interaction_id" => id,
          "command" => command,
          "text" => List.first(arguments) || "",
          "actor_id" => sender["id"],
          "thread_id" => thread
        }

        with {:ok, signal} <- build(context, SlashCommandReceived, id <> ":slash", data), do: {:ok, [signal]}

      _ ->
        {:ok, []}
    end
  end

  defp media(context, message) do
    photos = field(message, "photo")
    photo = if is_list(photos) and photos != [], do: List.last(photos)

    entries = [
      {"image", photo, "image/jpeg"},
      {"video", field(message, "animation"), "video/mp4"},
      {"audio", field(message, "audio"), nil},
      {"audio", field(message, "voice"), "audio/ogg"},
      {"video", field(message, "video"), nil},
      {"video", field(message, "video_note"), "video/mp4"},
      {"file", field(message, "document"), nil}
    ]

    sticker = field(message, "sticker")

    sticker_kind =
      cond do
        field(sticker, "is_video") == true -> "video"
        field(sticker, "is_animated") == true -> "file"
        true -> "image"
      end

    sticker_type =
      case sticker_kind do
        "image" -> "image/webp"
        "video" -> "video/webm"
        _ -> "application/x-tgsticker"
      end

    entries = entries ++ [{sticker_kind, sticker, sticker_type}]
    entries = Enum.uniq_by(entries, fn {_kind, value, _default} -> field(value, "file_id") end)

    Enum.reduce_while(entries, {:ok, []}, fn
      {_kind, nil, _default}, result ->
        {:cont, result}

      {kind, value, default}, {:ok, acc} ->
        mime = media_type(field(value, "mime_type"), default)
        kind = media_kind(kind, mime)

        with file when is_binary(file) <- identifier(field(value, "file_id")),
             ref = %{"id" => "telegram://file/" <> file, "client_id" => context.client.id, "kind" => "media"} do
          item =
            %{"kind" => kind, "resource_ref" => ref}
            |> optional("name", field(value, "file_name"))
            |> optional("media_type", mime)
            |> optional("caption", field(message, "caption"))
            |> optional("width", field(value, "width") || field(value, "length"))
            |> optional("height", field(value, "height") || field(value, "length"))
            |> optional("duration", field(value, "duration"))
            |> sticker_metadata(value)

          {:cont, {:ok, acc ++ [item]}}
        else
          _ -> {:halt, Policy.error(:invalid_delivery)}
        end
    end)
  end

  defp sticker_metadata(item, value) do
    flags =
      Enum.reduce(["is_animated", "is_video"], %{}, fn key, acc ->
        case field(value, key) do
          flag when is_boolean(flag) -> Map.put(acc, key, flag)
          _ -> acc
        end
      end)

    if flags == %{}, do: item, else: Map.put(item, "metadata", %{"telegram" => flags})
  end

  defp media_kind("file", "image/" <> _), do: "image"
  defp media_kind("file", "audio/" <> _), do: "audio"
  defp media_kind("file", "video/" <> _), do: "video"
  defp media_kind(kind, _), do: kind

  defp media_type(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      value -> value
    end
  end

  defp media_type(_value, default), do: default

  defp channel_sender(message) do
    chat = field(message, "chat")
    if field(chat, "type") == "channel", do: chat
  end

  defp mentions(message, client) do
    entities = field(message, "entities") || field(message, "caption_entities") || []
    text = field(message, "text") || field(message, "caption") || ""

    details =
      Enum.flat_map(entities, fn entity ->
        case field(entity, "type") do
          "text_mention" ->
            user = field(entity, "user")

            [
              %{
                "id" => identifier(field(user, "id")),
                "username" => field(user, "username"),
                "offset" => field(entity, "offset"),
                "length" => field(entity, "length")
              }
              |> select_present()
            ]

          "mention" ->
            username = utf16_slice(text, field(entity, "offset"), field(entity, "length"))

            [
              %{
                "id" => username,
                "username" => username,
                "offset" => field(entity, "offset"),
                "length" => field(entity, "length")
              }
              |> select_present()
            ]

          _ ->
            []
        end
      end)

    bot = client.config[:bot_username]

    %{
      "mention_details" => details,
      "mentions" => Enum.map(details, & &1["id"]),
      "mentioned" =>
        Enum.any?(
          details,
          &(&1["id"] == identifier(client.config[:bot_id]) or
              (is_binary(bot) and &1["username"] in [bot, "@" <> bot]))
        )
    }
  end

  defp utf16_slice(text, offset, length)
       when is_binary(text) and is_integer(offset) and is_integer(length) and offset >= 0 and length >= 0 do
    encoded = :unicode.characters_to_binary(text, :utf8, {:utf16, :little})

    if (offset + length) * 2 <= byte_size(encoded),
      do: encoded |> binary_part(offset * 2, length * 2) |> :unicode.characters_to_binary({:utf16, :little}, :utf8)
  end

  defp utf16_slice(_text, _offset, _length), do: nil

  defp reply_context(nil, _binding), do: nil

  defp reply_context(message, client) do
    %{
      "message_id" => identifier(field(message, "message_id")),
      "text" => field(message, "text") || field(message, "caption"),
      "sender" => sender(field(message, "from") || field(message, "sender_chat"), client)
    }
    |> select_present()
  end

  defp sender(nil, _binding), do: nil

  defp sender(user, client) do
    id = identifier(field(user, "id"))
    name = [field(user, "first_name"), field(user, "last_name")] |> Enum.filter(&is_binary/1) |> Enum.join(" ")

    %{
      "id" => id,
      "username" => field(user, "username"),
      "display_name" => if(name != "", do: name, else: field(user, "title")),
      "is_bot" => field(user, "is_bot") == true,
      "is_self" => id == identifier(client.config[:bot_id])
    }
    |> select_present()
  end

  defp reaction(value) do
    case field(value, "type") do
      "emoji" -> field(value, "emoji")
      "custom_emoji" -> "custom_emoji:" <> to_string(field(value, "custom_emoji_id"))
      _ -> nil
    end
  end

  defp chat_actor(nil), do: nil
  defp chat_actor(chat), do: "chat:" <> to_string(field(chat, "id"))
  defp conversation_kind("private"), do: "direct"
  defp conversation_kind(kind) when kind in ["group", "supergroup"], do: "group"
  defp conversation_kind("channel"), do: "channel"
  defp conversation_kind(_), do: "unknown"

  defp timestamp(value) when is_integer(value) do
    case DateTime.from_unix(value) do
      {:ok, time} -> DateTime.to_iso8601(time)
      _ -> nil
    end
  end

  defp timestamp(_), do: nil

  defp build(context, definition, item, data, subject \\ nil) do
    data = data |> Map.put("delivery_id", context.delivery) |> Map.put("item_id", item)
    subject = subject || if data["room_id"], do: Identity.conversation_subject(context.client.id, data["room_id"])
    Policy.new(definition, data, source: context.client.source, subject: subject)
  end

  defp failed(context, id, kind, index, room, code) do
    data = %{"room_id" => room, "code" => code, "item_index" => index, "provider_kind" => kind}
    with {:ok, signal} <- build(context, NormalizationFailed, id <> ":failure:" <> kind, data), do: {:ok, [signal]}
  end

  defp update_identity(update) do
    case identifier(field(update, "update_id")) do
      nil -> "telegram:digest:" <> digest(canonical(update))
      id -> "telegram:update:" <> id
    end
  end

  defp digest(value),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic])) |> Base.encode16(case: :lower)

  defp canonical(%_{} = value), do: canonical(Map.from_struct(value))

  defp canonical(value) when is_map(value),
    do: Enum.map(value, fn {key, item} -> {to_string(key), canonical(item)} end) |> Enum.sort()

  defp canonical(value) when is_list(value), do: Enum.map(value, &canonical/1)
  defp canonical(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp canonical(_value), do: throw(:invalid_provider_input)
  defp keys(%_{} = value), do: keys(Map.from_struct(value))
  defp keys(value), do: Enum.map(Map.keys(value), &to_string/1)
  defp identifier(value) when is_integer(value), do: Integer.to_string(value)
  defp identifier(value) when is_binary(value) and value != "", do: value
  defp identifier(_value), do: nil
  defp optional(map, _key, nil), do: map
  defp optional(map, key, value), do: Map.put(map, key, value)
  defp select_present(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
  defp field(%_{} = value, key), do: field(Map.from_struct(value), key)

  defp field(value, key) when is_map(value) do
    case Map.fetch(value, key) do
      {:ok, result} ->
        result

      :error ->
        Enum.find_value(value, fn {name, result} ->
          if is_atom(name) and Atom.to_string(name) == key, do: {:found, result}
        end)
        |> case do
          {:found, result} -> result
          nil -> nil
        end
    end
  end

  defp field(_value, _key), do: nil
end
