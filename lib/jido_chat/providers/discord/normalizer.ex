defmodule Jido.Chat.Discord.Normalizer do
  @moduledoc false
  alias Jido.Chat.Signal

  @doc "Convert private provider input to a scoped public delivery."
  def normalize(client, input) do
    items = if is_list(input), do: input, else: [input]
    delivery = "discord:" <> digest({client.id, items})
    context = %{client: client, delivery: delivery}

    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      {kind, payload} = unpack(item)
      item_id = "discord:#{kind}:" <> digest(item)

      case safe_map_item(context, kind, payload, item_id) do
        {:ok, facts} ->
          {:cont, {:ok, acc ++ List.wrap(facts)}}

        _ ->
          case fact(context, Signal.NormalizationFailed, item_id, %{
                 "code" => "invalid_item",
                 "provider_kind" => kind,
                 "item_index" => index,
                 "room_id" => id(payload, "channel_id")
               }) do
            {:ok, failure} -> {:cont, {:ok, acc ++ [failure]}}
            error -> {:halt, error}
          end
      end
    end)
    |> case do
      {:ok, facts} -> Jido.Chat.Delivery.new(client, delivery, facts)
      error -> error
    end
  rescue
    _ -> Signal.Policy.error(:invalid_delivery)
  end

  defp unpack({kind, payload, _}), do: unpack({kind, payload})
  defp unpack({kind, {_, payload}}), do: unpack({kind, payload})
  defp unpack({kind, payload}), do: {kind |> to_string() |> String.upcase(), payload}

  defp unpack(%{} = input) do
    unpack(
      {field(input, "t") || field(input, "event") || "MESSAGE_CREATE",
       field(input, "d") || field(input, "payload") || input}
    )
  end

  defp unpack(_), do: {"invalid", nil}

  defp safe_map_item(context, kind, payload, item_id) do
    map_item(context, kind, payload, item_id)
  rescue
    _ -> {:error, :invalid_item}
  end

  defp map_item(c, "MESSAGE_CREATE", p, item) when is_map(p) do
    with {:ok, message} <- message(c.client, p, "received") do
      data =
        message
        |> Map.drop(["id", "status"])
        |> Map.put("message_id", message["id"])
        |> Map.put("text", message["text"] || "")
        |> Map.put("sender", actor(c.client, field(p, "author")))
        |> Map.put("mentions", Enum.map(field(p, "mentions") || [], &id(&1, "id")))
        |> Map.put("mentioned", Enum.any?(field(p, "mentions") || [], &(id(&1, "id") == bot_id(c.client))))
        |> Map.put(
          "conversation_kind",
          if(field(p, "guild_id"), do: if(thread_id(p), do: "thread", else: "channel"), else: "direct")
        )

      fact(c, Signal.MessageReceived, item, data)
    end
  end

  defp map_item(c, "MESSAGE_UPDATE", p, item) when is_map(p) do
    data = %{
      "room_id" => room(p),
      "thread_id" => thread_id(p),
      "message_id" => id(p, "id"),
      "text" => field(p, "content"),
      "timestamp" => time(field(p, "edited_timestamp"))
    }

    data = if field(p, "author"), do: Map.put(data, "sender", actor(c.client, field(p, "author"))), else: data
    data = if field(p, "attachments"), do: Map.put(data, "media", media(c.client, p)), else: data
    fact(c, Signal.MessageUpdated, item, data)
  end

  defp map_item(c, "MESSAGE_DELETE", p, item),
    do:
      fact(c, Signal.MessageDeleted, item, %{
        "room_id" => room(p),
        "thread_id" => thread_id(p),
        "message_id" => id(p, "id")
      })

  defp map_item(c, kind, p, item) when kind in ["MESSAGE_REACTION_ADD", "MESSAGE_REACTION_REMOVE"] do
    emoji = field(p, "emoji")
    reaction = if id(emoji, "id"), do: "#{field(emoji, "name")}:#{id(emoji, "id")}", else: field(emoji, "name")
    definition = if kind == "MESSAGE_REACTION_ADD", do: Signal.ReactionAdded, else: Signal.ReactionRemoved

    fact(c, definition, item, %{
      "room_id" => room(p),
      "thread_id" => thread_id(p),
      "message_id" => id(p, "message_id"),
      "actor_id" => id(p, "user_id"),
      "reaction" => reaction
    })
  end

  defp map_item(c, "THREAD_CREATE", p, item),
    do:
      fact(c, Signal.ThreadStarted, item, %{
        "room_id" => id(p, "parent_id"),
        "thread_id" => id(p, "id"),
        "name" => field(p, "name"),
        "actor_id" => id(p, "owner_id")
      })

  defp map_item(c, "INTERACTION_CREATE", p, item) do
    d = field(p, "data") || %{}
    user = field(p, "user") || field(field(p, "member"), "user")

    base = %{
      "room_id" => room(p),
      "interaction_id" => id(p, "id"),
      "actor_id" => id(user, "id")
    }

    case field(p, "type") do
      1 ->
        {:ok, []}

      2 ->
        fact(
          c,
          Signal.SlashCommandReceived,
          item,
          Map.merge(base, %{
            "command" => "/" <> to_string(field(d, "name")),
            "text" => Enum.map_join(field(d, "options") || [], " ", &to_string(field(&1, "value")))
          })
        )

      3 ->
        values = field(d, "values") || []

        fact(
          c,
          Signal.ActionReceived,
          item,
          Map.merge(base, %{
            "action_id" => field(d, "custom_id"),
            "value" => List.first(values),
            "values" => %{to_string(field(d, "custom_id")) => values},
            "message_id" => id(field(p, "message"), "id")
          })
        )

      5 ->
        values =
          for row <- field(d, "components") || [],
              f <- field(row, "components") || [],
              into: %{},
              do: {field(f, "custom_id"), field(f, "value")}

        fact(
          c,
          Signal.ModalSubmitted,
          item,
          Map.merge(base, %{"view_id" => id(p, "id"), "callback_id" => field(d, "custom_id"), "values" => values})
        )

      _ ->
        {:error, :unsupported}
    end
  end

  defp map_item(_, _, _, _), do: {:error, :unsupported}

  defp fact(c, definition, item, data) do
    room = data["room_id"]
    subject = if is_binary(room) and room != "", do: Signal.Identity.conversation_subject(c.client.id, room)

    Signal.Policy.new(definition, data |> compact() |> Map.merge(%{"item_id" => item, "delivery_id" => c.delivery}),
      id: item,
      source: c.client.source,
      subject: subject
    )
  end

  @doc "Project and validate a public message result."
  def message(client, p, status) do
    result =
      %{
        "id" => id(p, "id"),
        "room_id" => id(p, "parent_id") || id(p, "channel_id"),
        "thread_id" => if(id(p, "parent_id"), do: id(p, "channel_id")),
        "text" => field(p, "content"),
        "status" => status,
        "timestamp" => time(field(p, "timestamp")),
        "reply_to_id" => id(field(p, "message_reference"), "message_id"),
        "media" => media(client, p)
      }
      |> compact()

    Zoi.parse(Signal.Schemas.result(:message), result)
  end

  defp media(client, p) do
    Enum.map(field(p, "attachments") || [], fn a ->
      true = is_binary(id(a, "id"))
      type = field(a, "content_type")

      kind =
        cond do
          is_binary(type) and String.starts_with?(type, "image/") -> "image"
          is_binary(type) and String.starts_with?(type, "audio/") -> "audio"
          is_binary(type) and String.starts_with?(type, "video/") -> "video"
          true -> "file"
        end

      %{
        "kind" => kind,
        "name" => field(a, "filename"),
        "width" => field(a, "width"),
        "height" => field(a, "height"),
        "media_type" => type,
        "resource_ref" => %{
          "client_id" => client.id,
          "kind" => "media",
          "id" => "discord://attachment/#{id(p, "channel_id")}/#{id(p, "id")}/#{id(a, "id")}"
        }
      }
      |> compact()
    end)
  end

  defp actor(client, p),
    do:
      compact(%{
        "id" => id(p, "id"),
        "username" => field(p, "username"),
        "display_name" => field(p, "global_name") || field(p, "username"),
        "is_bot" => field(p, "bot") == true,
        "is_self" => id(p, "id") == bot_id(client)
      })

  defp room(p), do: id(p, "parent_id") || id(p, "channel_id")
  defp thread_id(p), do: if(id(p, "parent_id"), do: id(p, "channel_id"))
  defp bot_id(client), do: client.config[:bot_id]

  @doc "Read a provider field from atom or string keys."
  def field(p, key) when is_map(p) do
    case Map.fetch(p, key) do
      {:ok, value} -> value
      :error -> Enum.find_value(p, fn {k, v} -> if is_atom(k) and Atom.to_string(k) == key, do: v end)
    end
  end

  def field(_, _), do: nil
  @doc "Read a provider identifier as a string."
  def id(p, key), do: identifier(field(p, key))
  @doc "Convert a provider identifier to a string."
  def identifier(nil), do: nil
  def identifier(value), do: to_string(value)
  @doc "Remove absent fields from a public projection."
  def compact(map), do: Map.reject(map, fn {_, value} -> is_nil(value) end)
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp time(value) when is_binary(value), do: value
  defp time(_), do: nil
  defp digest(value), do: :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.url_encode64(padding: false)
end
