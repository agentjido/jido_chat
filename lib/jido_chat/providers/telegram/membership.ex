defmodule Jido.Chat.Telegram.Membership do
  @moduledoc false

  alias Jido.Chat.Client
  alias Jido.Chat.Signal.{Identity, MembershipChanged, Policy}

  @permissions ~w(can_send_messages can_send_audios can_send_documents can_send_photos
                  can_send_videos can_send_video_notes can_send_voice_notes can_send_polls
                  can_send_other_messages can_add_web_page_previews can_change_info
                  can_invite_users can_pin_messages can_manage_topics can_react_to_messages
                  can_edit_tag)

  @doc false
  @spec normalize(Client.t(), String.t(), String.t(), map()) ::
          {:ok, Jido.Signal.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  @spec normalize(Client.t(), String.t(), String.t(), map(), keyword()) ::
          {:ok, Jido.Signal.t()} | {:error, Jido.Chat.Errors.Contract.t()}
  def normalize(client, delivery_id, kind, update, opts \\ [])

  def normalize(%Client{} = client, delivery_id, kind, update, opts)
      when is_binary(delivery_id) and kind in ["chat_member", "my_chat_member"] and is_map(update) and is_list(opts) do
    with room when is_binary(room) <- update |> field("chat") |> field("id") |> id(),
         member when is_map(member) <- field(update, "new_chat_member"),
         participant when is_binary(participant) <- member |> field("user") |> field("id") |> id(),
         :ok <- previous_identity(update, participant),
         {:ok, previous} <- state(field(update, "old_chat_member")),
         {:ok, current} <- state(member) do
      {transition, evidence} = transition(previous, current)

      data = %{
        "delivery_id" => delivery_id,
        "item_id" => Keyword.get(opts, :item_id, delivery_id <> ":" <> kind <> ":" <> participant),
        "room_id" => room,
        "participant_id" => participant,
        "actor_id" => update |> field("from") |> field("id") |> id(),
        "bot_self" => kind == "my_chat_member" or participant == id(client.config[:bot_id]),
        "transition" => transition,
        "evidence" => evidence,
        "previous" => previous,
        "current" => current
      }

      Policy.new(MembershipChanged, data,
        source: client.source,
        subject: Identity.conversation_subject(client.id, room)
      )
    else
      {:error, _} = error -> error
      _ -> Policy.error(:invalid_delivery)
    end
  rescue
    _ -> Policy.error(:invalid_delivery)
  catch
    _, _ -> Policy.error(:invalid_delivery)
  end

  def normalize(_binding, _delivery_id, _kind, _update, _opts), do: Policy.error(:invalid_delivery)

  defp previous_identity(update, participant) do
    case update |> field("old_chat_member") |> field("user") |> field("id") |> id() do
      nil -> :ok
      ^participant -> :ok
      _ -> Policy.error(:invalid_context)
    end
  end

  defp state(nil), do: {:ok, nil}

  defp state(member) when is_map(member) do
    status = field(member, "status")
    status = if status == "kicked", do: "removed", else: status

    with true <- status in ~w(creator administrator member restricted left removed),
         {:ok, is_member} <- member_state(status, member),
         {:ok, restrictions} <- restrictions(member) do
      {:ok, %{"status" => status, "is_member" => is_member, "role" => status, "restrictions" => restrictions}}
    else
      _ -> Policy.error(:invalid_delivery)
    end
  end

  defp state(_member), do: Policy.error(:invalid_delivery)

  defp member_state("restricted", member) do
    case field(member, "is_member") do
      value when is_boolean(value) -> {:ok, value}
      _ -> Policy.error(:invalid_delivery)
    end
  end

  defp member_state(status, _member), do: {:ok, status in ~w(creator administrator member)}

  defp restrictions(member) do
    Enum.reduce_while(@permissions ++ ["until_date"], {:ok, %{}}, fn key, {:ok, acc} ->
      case field(member, key) do
        nil -> {:cont, {:ok, acc}}
        value when key == "until_date" and is_integer(value) and value >= 0 -> {:cont, {:ok, Map.put(acc, key, value)}}
        value when key != "until_date" and is_boolean(value) -> {:cont, {:ok, Map.put(acc, key, value)}}
        _ -> {:halt, Policy.error(:invalid_delivery)}
      end
    end)
  end

  defp transition(nil, _current), do: {"unknown", "partial_transition"}

  defp transition(previous, current) do
    cond do
      current["status"] == "removed" and previous["status"] != "removed" ->
        {"removed", "explicit_remove"}

      not previous["is_member"] and current["is_member"] ->
        {"joined", "explicit_join"}

      previous["is_member"] and not current["is_member"] ->
        {"left", "explicit_leave"}

      previous["status"] != current["status"] and "restricted" in [previous["status"], current["status"]] ->
        {"restriction_changed", "state_transition"}

      previous["status"] != current["status"] and previous["is_member"] and current["is_member"] ->
        {"role_changed", "state_transition"}

      previous["status"] != current["status"] ->
        {"unknown", "state_transition"}

      previous["restrictions"] != current["restrictions"] ->
        {"restriction_changed", "state_transition"}

      true ->
        {"unchanged", "state_transition"}
    end
  end

  defp id(value) when is_integer(value), do: Integer.to_string(value)
  defp id(value) when is_binary(value) and value != "", do: value
  defp id(_value), do: nil

  defp field(%_{} = value, key), do: field(Map.from_struct(value), key)

  defp field(value, key) when is_map(value) do
    case Map.fetch(value, key) do
      {:ok, result} ->
        result

      :error ->
        Enum.find_value(value, fn
          {name, result} when is_atom(name) -> if Atom.to_string(name) == key, do: {:found, result}
          _ -> nil
        end)
        |> case do
          {:found, result} -> result
          nil -> nil
        end
    end
  end

  defp field(_value, _key), do: nil
end
