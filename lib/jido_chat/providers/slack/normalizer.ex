defmodule Jido.Chat.Slack.Normalizer do
  @moduledoc false

  alias Jido.Chat.Signal

  @doc "Converts private Slack input to one validated public delivery."
  def normalize(client, input) do
    items = if is_list(input), do: input, else: [input]
    delivery_id = "slack:" <> digest({client.id, items})
    context = %{client: client, delivery_id: delivery_id}

    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, facts} ->
      {kind, payload} = unpack(item)
      item_id = "slack:#{kind}:" <> digest(item)

      case safe_map_item(context, kind, payload, item_id) do
        {:ok, mapped} ->
          {:cont, {:ok, facts ++ List.wrap(mapped)}}

        {:error, reason} ->
          code = if reason == :unsupported, do: "unsupported_item", else: "invalid_item"

          case fact(context, Signal.NormalizationFailed, item_id, %{
                 "code" => code,
                 "provider_kind" => kind,
                 "item_index" => index,
                 "room_id" => room(payload)
               }) do
            {:ok, failure} -> {:cont, {:ok, facts ++ [failure]}}
            error -> {:halt, error}
          end
      end
    end)
    |> case do
      {:ok, facts} -> Jido.Chat.Delivery.new(client, delivery_id, facts)
      error -> error
    end
  rescue
    _ -> Signal.Policy.error(:invalid_delivery)
  end

  @doc "Projects one Slack message into the canonical message result."
  def message(client, payload, room_id, status) when is_map(payload) do
    id = identifier(field(payload, "ts") || field(payload, "message_ts"))

    %{
      "id" => id,
      "room_id" => identifier(field(payload, "channel") || room_id),
      "thread_id" => thread_id(payload),
      "text" => field(payload, "text"),
      "sender" => optional_actor(client, payload),
      "timestamp" => timestamp(id),
      "media" => media(client, payload),
      "status" => status
    }
    |> compact()
    |> then(&Zoi.parse(Signal.Schemas.result(:message), &1))
  end

  def message(_, _, _, _), do: {:error, :invalid_provider_result}

  defp unpack(%{} = input) do
    cond do
      field(input, "type") == "event_callback" ->
        event = field(input, "event")
        {to_string(field(event, "type") || "invalid"), event}

      is_binary(field(input, "command")) ->
        {"slash_command", input}

      is_binary(field(input, "type")) ->
        {field(input, "type"), input}

      true ->
        {"invalid", input}
    end
  end

  defp unpack(_), do: {"invalid", nil}

  defp safe_map_item(context, kind, payload, item_id) do
    map_item(context, kind, payload, item_id)
  rescue
    _ -> {:error, :invalid}
  end

  defp map_item(c, kind, payload, item_id) when kind in ["message", "app_mention"] do
    case field(payload, "subtype") do
      "message_changed" -> map_message_changed(c, payload, item_id)
      "message_deleted" -> map_message_deleted(c, payload, item_id)
      _ -> map_message_received(c, payload, item_id)
    end
  end

  defp map_item(c, kind, payload, item_id) when kind in ["reaction_added", "reaction_removed"] do
    item = field(payload, "item") || %{}
    definition = if kind == "reaction_added", do: Signal.ReactionAdded, else: Signal.ReactionRemoved

    fact(c, definition, item_id, %{
      "room_id" => identifier(field(item, "channel")),
      "message_id" => identifier(field(item, "ts")),
      "actor_id" => identifier(field(payload, "user")),
      "reaction" => field(payload, "reaction")
    })
  end

  defp map_item(c, "slash_command", payload, item_id) do
    fact(c, Signal.SlashCommandReceived, item_id, %{
      "room_id" => identifier(field(payload, "channel_id")),
      "interaction_id" => interaction_id(payload, item_id),
      "command" => field(payload, "command"),
      "text" => field(payload, "text") || "",
      "actor_id" => identifier(field(payload, "user_id")),
      "thread_id" => present(field(payload, "thread_ts"))
    })
  end

  defp map_item(c, "block_actions", payload, item_id) do
    actions = field(payload, "actions") || []

    actions
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {action, index}, {:ok, facts} ->
      data = %{
        "room_id" => room(payload),
        "interaction_id" => interaction_id(payload, item_id),
        "action_id" => field(action, "action_id"),
        "actor_id" => id(field(payload, "user"), "id"),
        "message_id" => id(field(payload, "message"), "ts"),
        "thread_id" => thread_id(field(payload, "message") || %{}),
        "value" => action_value(action),
        "values" => %{to_string(field(action, "action_id")) => action_values(action)}
      }

      case fact(c, Signal.ActionReceived, "#{item_id}:#{index}", data) do
        {:ok, fact} -> {:cont, {:ok, facts ++ [fact]}}
        error -> {:halt, error}
      end
    end)
  end

  defp map_item(c, "view_submission", payload, item_id) do
    view = field(payload, "view") || %{}

    fact(c, Signal.ModalSubmitted, item_id, %{
      "room_id" => room(payload),
      "interaction_id" => interaction_id(payload, item_id),
      "view_id" => id(view, "id"),
      "callback_id" => present(field(view, "callback_id")),
      "actor_id" => id(field(payload, "user"), "id"),
      "values" => view_values(view)
    })
  end

  defp map_item(c, "view_closed", payload, item_id) do
    view = field(payload, "view") || %{}

    fact(c, Signal.ModalClosed, item_id, %{
      "room_id" => room(payload),
      "interaction_id" => interaction_id(payload, item_id),
      "view_id" => id(view, "id"),
      "callback_id" => present(field(view, "callback_id")),
      "actor_id" => id(field(payload, "user"), "id")
    })
  end

  defp map_item(c, kind, payload, item_id) when kind in ["block_suggestion", "dialog_suggestion"] do
    action = List.first(field(payload, "actions") || []) || payload
    view = field(payload, "view") || %{}

    fact(c, Signal.OptionsRequested, item_id, %{
      "room_id" => room(payload),
      "interaction_id" => interaction_id(payload, item_id),
      "action_id" => field(action, "action_id") || field(payload, "name"),
      "query" => field(action, "value") || field(payload, "value") || "",
      "actor_id" => id(field(payload, "user"), "id"),
      "view_id" => present(field(view, "id"))
    })
  end

  defp map_item(_, _, _, _), do: {:error, :unsupported}

  defp map_message_received(c, payload, item_id) do
    room_id = room(payload)
    message_id = identifier(field(payload, "ts"))

    fact(c, Signal.MessageReceived, item_id, %{
      "room_id" => room_id,
      "message_id" => message_id,
      "sender" => actor(c.client, payload),
      "text" => field(payload, "text") || "",
      "thread_id" => thread_id(payload),
      "media" => media(c.client, payload),
      "mentions" => mentions(field(payload, "text")),
      "mentioned" => mentioned?(c.client, field(payload, "text")),
      "timestamp" => timestamp(field(payload, "event_ts") || message_id),
      "conversation_kind" => conversation_kind(room_id, payload)
    })
  end

  defp map_message_changed(c, payload, item_id) do
    message = field(payload, "message") || %{}

    fact(c, Signal.MessageUpdated, item_id, %{
      "room_id" => room(payload),
      "message_id" => identifier(field(message, "ts")),
      "sender" => optional_actor(c.client, message),
      "text" => field(message, "text"),
      "thread_id" => thread_id(message),
      "media" => media(c.client, message),
      "timestamp" => timestamp(field(payload, "event_ts") || field(message, "edited", "ts"))
    })
  end

  defp map_message_deleted(c, payload, item_id) do
    previous = field(payload, "previous_message") || %{}

    fact(c, Signal.MessageDeleted, item_id, %{
      "room_id" => room(payload),
      "message_id" => identifier(field(payload, "deleted_ts") || field(previous, "ts")),
      "actor_id" => identifier(field(previous, "user")),
      "thread_id" => thread_id(previous),
      "timestamp" => timestamp(field(payload, "event_ts"))
    })
  end

  defp fact(context, definition, item_id, data) do
    room_id = data["room_id"]

    subject =
      if is_binary(room_id) and room_id != "", do: Signal.Identity.conversation_subject(context.client.id, room_id)

    data =
      data
      |> compact()
      |> Map.merge(%{"item_id" => item_id, "delivery_id" => context.delivery_id})

    Signal.Policy.new(definition, data,
      id: item_id,
      source: context.client.source,
      subject: subject
    )
  end

  defp actor(client, payload) do
    id = identifier(field(payload, "user") || field(payload, "bot_id"))

    %{
      "id" => id,
      "username" => present(field(payload, "username")),
      "is_bot" => is_binary(field(payload, "bot_id")) or field(payload, "subtype") == "bot_message",
      "is_self" => id in [client.config[:bot_user_id], client.config[:bot_id]]
    }
    |> compact()
  end

  defp optional_actor(client, payload) do
    case actor(client, payload) do
      %{"id" => id} = value when is_binary(id) and id != "" -> value
      _ -> nil
    end
  end

  defp media(client, payload) do
    Enum.flat_map(field(payload, "files") || [], fn file ->
      type = field(file, "mimetype")
      url = present(field(file, "url_private_download") || field(file, "url_private"))

      if url do
        [
          %{
            "kind" => media_kind(type),
            "name" => field(file, "name") || field(file, "title"),
            "media_type" => type,
            "width" => field(file, "original_w"),
            "height" => field(file, "original_h"),
            "resource_ref" => %{"client_id" => client.id, "kind" => "media", "id" => url}
          }
          |> compact()
        ]
      else
        []
      end
    end)
  end

  defp media_kind(type) when is_binary(type) do
    cond do
      String.starts_with?(type, "image/") -> "image"
      String.starts_with?(type, "audio/") -> "audio"
      String.starts_with?(type, "video/") -> "video"
      true -> "file"
    end
  end

  defp media_kind(_), do: "file"

  defp room(payload) when is_map(payload) do
    channel = field(payload, "channel")
    view = field(payload, "view") || %{}

    identifier(
      if(is_map(channel), do: field(channel, "id"), else: channel) ||
        field(payload, "channel_id") || private_room(field(view, "private_metadata"))
    )
  end

  defp room(_), do: nil

  defp private_room(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> field(map, "room_id") || field(map, "channel_id")
      _ -> present(value)
    end
  end

  defp private_room(_), do: nil

  defp thread_id(payload) do
    value = present(field(payload, "thread_ts"))
    if value == identifier(field(payload, "ts")), do: nil, else: value
  end

  defp interaction_id(payload, fallback) do
    view = field(payload, "view") || %{}

    identifier(field(payload, "action_ts") || field(view, "id") || fallback)
  end

  defp action_value(action) do
    field(action, "value") || id(field(action, "selected_option"), "value") ||
      field(action, "selected_user") || field(action, "selected_conversation") ||
      field(action, "selected_channel") || field(action, "selected_date")
  end

  defp action_values(action) do
    case field(action, "selected_options") do
      values when is_list(values) -> Enum.map(values, &field(&1, "value"))
      _ -> action_value(action)
    end
  end

  defp view_values(view) do
    state = field(view, "state") || %{}
    values = field(state, "values") || %{}

    Enum.reduce(values, %{}, fn {block_id, actions}, result ->
      Enum.reduce(actions, result, fn {action_id, action}, acc ->
        key = "#{block_id}.#{action_id}"
        Map.put(acc, key, action_values(action))
      end)
    end)
  end

  defp mentions(text) when is_binary(text) do
    ~r/<@([A-Z0-9]+)(?:\|[^>]+)?>/
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp mentions(_), do: []

  defp mentioned?(client, text),
    do: Enum.any?(mentions(text), &(&1 in [client.config[:bot_user_id], client.config[:bot_id]]))

  defp conversation_kind("D" <> _, _), do: "direct"
  defp conversation_kind("G" <> _, _), do: "group"
  defp conversation_kind(_, payload), do: if(thread_id(payload), do: "thread", else: "channel")

  defp timestamp(nil), do: nil

  defp timestamp(value) do
    case Float.parse(to_string(value)) do
      {seconds, ""} ->
        seconds
        |> Kernel.*(1_000_000)
        |> round()
        |> DateTime.from_unix(:microsecond)
        |> case do
          {:ok, datetime} -> DateTime.to_iso8601(datetime)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp field(map, parent, child), do: field(field(map, parent), child)

  defp field(map, key) when is_map(map) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {atom, value} when is_atom(atom) -> if Atom.to_string(atom) == key, do: value
        _ -> nil
      end)
  end

  defp field(_, _), do: nil
  defp id(map, key), do: identifier(field(map, key))
  defp identifier(nil), do: nil
  defp identifier(value), do: to_string(value)
  defp present(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp present(_), do: nil
  defp compact(map), do: Map.reject(map, fn {_, value} -> is_nil(value) end)
  defp digest(value), do: :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.url_encode64(padding: false)
end
