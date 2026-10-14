defmodule Jido.Chat.Operations.Result do
  @moduledoc false

  @fields ~w(id user_id external_user_id scope external_message_id external_room_id external_thread_id message_id room_id thread_id delivery_room_ref delivery_external_room_id text sender author user username display_name is_bot is_self timestamp status role name title kind type is_dm topic parent_message_id root_message_id reply_to_id media resource_ref binding_id media_type caption messages items threads participants complete has_more next_cursor cursor options option_groups label value description url opened view)a
  @keys Map.new(@fields, &{Atom.to_string(&1), &1})

  @doc false
  @spec project(atom(), term(), map()) :: {:ok, map()} | {:error, :invalid_provider_result}
  def project(:acknowledgement, _value, _data), do: {:ok, %{"acknowledged" => true}}
  def project(:message, value, data) when is_map(value), do: {:ok, message(value, data["room_id"])}

  def project(:conversation, value, data) when is_map(value) or is_binary(value),
    do: {:ok, conversation(value, data["room_id"])}

  def project(:thread, value, data) when is_map(value), do: {:ok, thread(value, data["room_id"])}
  def project(:user, value, _data) when is_map(value), do: {:ok, actor(value)}

  def project(:subject, value, data) when is_map(value) do
    {:ok,
     %{
       "id" => id(value, ~w(id thread_id)),
       "kind" => subject_kind(get(value, "kind")),
       "room_id" => id(value, ~w(room_id external_room_id)) || data["room_id"]
     }
     |> optional("title", get(value, "title"))}
  end

  def project(:participants, value, _data) when is_list(value) do
    {:ok,
     %{"participants" => Enum.map(value, &actor/1), "complete" => false, "scope" => "observed", "next_cursor" => nil}}
  end

  def project(:participants, value, _data) when is_map(value) do
    {:ok,
     %{
       "participants" => Enum.map(get(value, "participants") || [], &actor/1),
       "complete" => get(value, "complete") == true,
       "scope" => scalar(get(value, "scope")) || "observed",
       "next_cursor" => scalar(get(value, "next_cursor"))
     }}
  end

  def project(:message_page, value, data) when is_map(value) do
    items = get(value, "messages") || get(value, "items") || []

    {:ok,
     %{
       "messages" => Enum.map(items, &message(&1, data["room_id"])),
       "next_cursor" => cursor(value),
       "complete" => complete?(value)
     }}
  end

  def project(:thread_page, value, data) when is_map(value) do
    items = get(value, "threads") || get(value, "items") || []

    {:ok,
     %{
       "threads" => Enum.map(items, &thread(&1, data["room_id"])),
       "next_cursor" => cursor(value),
       "complete" => complete?(value)
     }}
  end

  def project(:options, value, _data) when is_map(value) do
    {:ok,
     %{
       "options" => Enum.map(get(value, "options") || [], &option/1),
       "option_groups" =>
         Enum.map(get(value, "option_groups") || [], fn group ->
           %{"label" => get(group, "label"), "options" => Enum.map(get(group, "options") || [], &option/1)}
         end),
       "complete" => get(value, "complete") != false
     }}
  end

  def project(:modal, value, _data) when is_map(value) do
    {:ok,
     %{"opened" => get(value, "opened") != false}
     |> optional("id", id(value, ~w(id)) || id(get(value, "view"), ~w(id)))}
  end

  def project(_kind, _value, _data), do: {:error, :invalid_provider_result}

  defp message(value, room) do
    %{
      "id" => id(value, ~w(id external_message_id message_id)),
      "room_id" => id(value, ~w(room_id external_room_id)) || room
    }
    |> optional("text", get(value, "text"))
    |> optional("thread_id", id(value, ~w(thread_id external_thread_id)))
    |> optional("reply_to_id", id(value, ~w(reply_to_id)))
    |> optional("timestamp", timestamp(get(value, "timestamp")))
    |> optional("status", status(get(value, "status")))
    |> optional("role", scalar(get(value, "role")))
    |> optional("media", media(get(value, "media")))
    |> maybe_actor(get(value, "sender") || get(value, "author") || get(value, "user"))
  end

  defp media(values) when is_list(values) do
    Enum.map(values, fn value ->
      ref = get(value, "resource_ref")

      %{
        "kind" => scalar(get(value, "kind")),
        "resource_ref" => %{
          "id" => get(ref, "id"),
          "scope" => scalar(get(ref, "scope")),
          "binding_id" => get(ref, "binding_id"),
          "kind" => scalar(get(ref, "kind"))
        }
      }
      |> optional("name", get(value, "name"))
      |> optional("media_type", get(value, "media_type"))
      |> optional("caption", get(value, "caption"))
    end)
  end

  defp media(value), do: value

  defp conversation(value, _room) when is_binary(value), do: %{"id" => value, "kind" => "direct"}

  defp conversation(value, room) do
    %{"id" => id(value, ~w(id room_id external_room_id)) || room, "kind" => conversation_kind(value)}
    |> optional("name", get(value, "name") || get(value, "title"))
    |> optional("topic", get(value, "topic"))
  end

  defp thread(value, room) do
    %{
      "id" => id(value, ~w(external_thread_id thread_id id)),
      "room_id" => id(value, ~w(room_id external_room_id)) || room
    }
    |> optional("name", get(value, "name") || get(value, "title"))
    |> optional("parent_message_id", id(value, ~w(parent_message_id root_message_id)))
    |> optional("delivery_room_ref", id(value, ~w(delivery_room_ref delivery_external_room_id)))
  end

  defp actor(value) do
    %{"id" => id(value, ~w(id user_id external_user_id))}
    |> optional("username", get(value, "username"))
    |> optional("display_name", get(value, "display_name"))
    |> optional("is_bot", get(value, "is_bot"))
    |> optional("is_self", get(value, "is_self"))
  end

  defp option(value) do
    %{"label" => get(value, "label"), "value" => get(value, "value")}
    |> optional("description", get(value, "description"))
    |> optional("url", get(value, "url"))
  end

  defp maybe_actor(map, nil), do: map
  defp maybe_actor(map, value), do: Map.put(map, "sender", actor(value))
  defp cursor(value), do: scalar(get(value, "next_cursor") || get(value, "cursor"))
  defp complete?(value), do: get(value, "complete") == true or get(value, "has_more") == false

  defp conversation_kind(value) do
    cond do
      get(value, "is_dm") == true -> "direct"
      scalar(get(value, "kind")) in ~w(direct group channel thread unknown) -> scalar(get(value, "kind"))
      true -> "unknown"
    end
  end

  defp subject_kind(value) do
    if scalar(value) in ~w(conversation thread message), do: scalar(value), else: "thread"
  end

  defp status(:edited), do: "updated"
  defp status("edited"), do: "updated"
  defp status(value), do: scalar(value)
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(value), do: scalar(value)
  defp scalar(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp scalar(value) when is_binary(value), do: value
  defp scalar(_value), do: nil
  defp optional(map, _key, nil), do: map
  defp optional(map, key, value), do: Map.put(map, key, value)
  defp id(value, keys), do: Enum.find_value(keys, fn key -> identifier(get(value, key)) end)
  defp identifier(value) when is_integer(value), do: Integer.to_string(value)
  defp identifier(value) when is_binary(value), do: value
  defp identifier(_), do: nil
  defp get(value, key) when is_map(value), do: Map.get(value, key, Map.get(value, @keys[key]))
  defp get(_value, _key), do: nil
end
