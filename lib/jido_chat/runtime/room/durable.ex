defmodule Jido.Chat.Runtime.Room.Durable do
  @moduledoc false

  alias Jido.Chat.Runtime.Room.{Declaration, HistoryRecord, Membership, Record}
  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Commit, History, Memberships, RoomDeclarations, Rooms}

  @doc false
  def provision(runtime, definition_key, attrs) do
    with {:ok, _definition} <- runtime.room_definition(definition_key),
         {:ok, storage} <- storage(runtime, [Rooms, RoomDeclarations, Commit]),
         {:ok, room} <- Record.new(attrs),
         {:ok, declaration} <-
           Declaration.new(%{room_id: room.id, definition_key: definition_key, desired: :running}),
         {:ok, [^room, ^declaration]} <-
           call(storage, :commit, [[{:insert_room, room}, {:insert_room_declaration, declaration}]]) do
      {:ok, %{room: room, declaration: declaration}}
    end
  end

  @doc false
  def list_declarations(runtime) do
    with {:ok, storage} <- storage(runtime, [RoomDeclarations]),
         do: call(storage, :list_room_declarations, [])
  end

  @doc false
  def get_declaration(runtime, room_id) do
    with {:ok, storage} <- storage(runtime, [RoomDeclarations]),
         do: call(storage, :get_room_declaration, [room_id])
  end

  @doc false
  def set_desired(runtime, room_id, desired) do
    with {:ok, storage} <- storage(runtime, [RoomDeclarations]),
         {:ok, %Declaration{} = current} <- required_declaration(storage, room_id),
         {:ok, next} <- Declaration.set_desired(current, desired),
         do: update_declaration(storage, current, next)
  end

  @doc false
  def delete_declaration(runtime, room_id, expected_revision) do
    with {:ok, storage} <- storage(runtime, [RoomDeclarations]),
         {:ok, :ok} <- call(storage, :delete_room_declaration, [room_id, expected_revision]),
         do: :ok
  end

  @doc false
  def active_members(runtime, room_id, limit) do
    with {:ok, storage} <- storage(runtime, [Memberships]),
         {:ok, values} <- collect_members(storage, room_id, limit, nil, []) do
      {:ok, Enum.map(values, &Membership.member/1)}
    end
  end

  @doc false
  def active_member?(runtime, room_id, member) do
    case get_membership(runtime, room_id, member) do
      {:ok, %Membership{status: :active}} -> {:ok, true}
      {:ok, %Membership{}} -> {:ok, false}
      {:ok, nil} -> {:ok, false}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  def active_member_count(runtime, room_id, stop_after) when is_integer(stop_after) and stop_after > 0 do
    with {:ok, storage} <- storage(runtime, [Memberships]),
         do: collect_member_count(storage, room_id, stop_after, nil, 0)
  end

  @doc false
  def list_memberships(runtime, room_id, opts) do
    with {:ok, storage} <- storage(runtime, [Memberships]),
         do: call(storage, :list_memberships, [room_id, opts])
  end

  @doc false
  def get_membership(runtime, room_id, member) do
    with {:ok, key} <- member_key(member),
         {:ok, storage} <- storage(runtime, [Memberships]),
         do: call(storage, :get_membership, [room_id, key])
  end

  @doc false
  def join(runtime, room_id, member, issuer) do
    with {:ok, storage} <- storage(runtime, [Memberships]),
         {:ok, candidate} <- Membership.new(%{room_id: room_id, member: member, issuer: issuer}),
         {:ok, current} <- call(storage, :get_membership, [room_id, candidate.member_key]) do
      case current do
        nil -> call(storage, :insert_membership, [candidate])
        %Membership{status: :active} -> {:ok, current}
        %Membership{} -> transition(storage, current, :active, issuer)
      end
    end
  end

  @doc false
  def leave(runtime, room_id, member, issuer) do
    with {:ok, storage} <- storage(runtime, [Memberships]),
         {:ok, key} <- member_key(member),
         {:ok, current} <- call(storage, :get_membership, [room_id, key]) do
      case current do
        nil -> {:ok, nil}
        %Membership{status: :revoked} -> {:ok, current}
        %Membership{} -> transition(storage, current, :revoked, issuer)
      end
    end
  end

  @doc false
  def store_message(runtime, room_id, %Jido.Signal{} = signal) do
    with {:ok, storage} <- storage(runtime, [History]),
         {:ok, current} <- call(storage, :get_history, [room_id, signal.id]) do
      case current do
        %HistoryRecord{signal: stored} ->
          if same_fact?(stored, signal), do: {:ok, current}, else: {:error, :message_id_conflict}

        nil ->
          insert_message(storage, room_id, signal)
      end
    end
  end

  @doc false
  def get_message(runtime, room_id, message_id) do
    with {:ok, storage} <- storage(runtime, [History]),
         do: call(storage, :get_history, [room_id, message_id])
  end

  @doc false
  def list_history(runtime, room_id, opts) do
    with {:ok, storage} <- storage(runtime, [History]),
         do: call(storage, :list_history, [room_id, opts])
  end

  @doc false
  def hydrate(runtime, room_id, member_limit, history_limit) do
    with {:ok, members} <- active_members(runtime, room_id, member_limit),
         {:ok, storage} <- storage(runtime, [History]),
         {:ok, history} <- recent_history(storage, room_id, history_limit),
         {:ok, sequence} <- call(storage, :last_history_sequence, [room_id]) do
      {:ok, %{members: members, messages: Enum.map(history, & &1.signal), sequence: sequence}}
    end
  end

  @doc false
  def durable?(runtime),
    do: is_atom(runtime) and runtime not in [nil, true, false] and function_exported?(runtime, :storage, 0)

  defp required_declaration(storage, room_id) do
    case call(storage, :get_room_declaration, [room_id]) do
      {:ok, nil} -> {:error, :room_declaration_not_found}
      result -> result
    end
  end

  defp update_declaration(_storage, current, current), do: {:ok, current}

  defp update_declaration(storage, current, next),
    do: call(storage, :update_room_declaration, [current.room_id, current.revision, next])

  defp transition(storage, current, status, issuer) do
    with {:ok, next} <- Membership.transition(current, status, issuer),
         do:
           call(storage, :update_membership, [
             current.room_id,
             current.member_key,
             current.revision,
             next
           ])
  end

  defp insert_message(storage, room_id, signal) do
    with {:ok, sequence} <- call(storage, :last_history_sequence, [room_id]),
         signal = %{signal | data: Map.put(signal.data, "sequence", sequence + 1)},
         {:ok, record} <-
           HistoryRecord.new(%{
             room_id: room_id,
             message_id: signal.id,
             sequence: sequence + 1,
             thread_id: get_in(signal.data, ["message", "thread_id"]),
             signal: signal
           }),
         do: call(storage, :insert_history, [record])
  end

  defp collect_members(_storage, _room_id, remaining, _after_key, values)
       when is_integer(remaining) and remaining <= 0,
       do: {:ok, Enum.reverse(values)}

  defp collect_members(storage, room_id, remaining, after_key, values) do
    limit = min(remaining, 1_000)
    opts = [status: :active, limit: limit] ++ if(after_key, do: [after: after_key], else: [])

    with {:ok, page} <- call(storage, :list_memberships, [room_id, opts]) do
      case List.last(page) do
        nil ->
          {:ok, Enum.reverse(values)}

        last ->
          collect_members(
            storage,
            room_id,
            remaining - length(page),
            last.member_key,
            Enum.reverse(page, values)
          )
      end
    end
  end

  defp collect_member_count(_storage, _room_id, stop_after, _after_key, count)
       when count >= stop_after,
       do: {:ok, count}

  defp collect_member_count(storage, room_id, stop_after, after_key, count) do
    limit = min(stop_after - count, 1_000)
    opts = [status: :active, limit: limit] ++ if(after_key, do: [after: after_key], else: [])

    with {:ok, page} <- call(storage, :list_memberships, [room_id, opts]) do
      case List.last(page) do
        nil -> {:ok, count}
        last -> collect_member_count(storage, room_id, stop_after, last.member_key, count + length(page))
      end
    end
  end

  defp recent_history(storage, room_id, limit) do
    page_limit = min(limit, 1_000)

    with {:ok, page} <- call(storage, :list_history, [room_id, [latest: true, limit: page_limit]]) do
      collect_older_history(storage, room_id, limit - length(page), page)
    end
  end

  defp collect_older_history(_storage, _room_id, remaining, values) when remaining <= 0,
    do: {:ok, values}

  defp collect_older_history(storage, room_id, remaining, [first | _] = values) do
    limit = min(remaining, 1_000)

    with {:ok, page} <- call(storage, :list_history, [room_id, [before: first.message_id, limit: limit]]) do
      case page do
        [] -> {:ok, values}
        _ -> collect_older_history(storage, room_id, remaining - length(page), page ++ values)
      end
    end
  end

  defp collect_older_history(_storage, _room_id, _remaining, []), do: {:ok, []}

  defp member_key(member) do
    case Membership.new(%{room_id: "key", member: member}) do
      {:ok, membership} -> {:ok, membership.member_key}
      {:error, _reason} -> {:error, :invalid_member}
    end
  end

  defp same_fact?(left, right) do
    left.id == right.id and left.type == right.type and
      Map.delete(left.data, "sequence") == Map.delete(right.data, "sequence")
  end

  defp storage(runtime, capabilities) do
    cond do
      not durable?(runtime) -> {:error, :invalid_runtime}
      is_nil(runtime.storage()) -> {:error, :room_storage_required}
      Storage.validate(runtime.storage(), capabilities) != :ok -> {:error, :unsupported_storage_capability}
      true -> {:ok, runtime.storage()}
    end
  end

  defp call({adapter, resource}, function, args) do
    apply(adapter, function, [resource | args])
  catch
    :exit, _reason -> {:error, :room_storage_unavailable}
  end
end
