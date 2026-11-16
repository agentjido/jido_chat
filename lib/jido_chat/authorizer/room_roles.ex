defmodule Jido.Chat.Authorizer.RoomRoles do
  @moduledoc """
  Applies a small default Room role policy to roles on a Principal.

  Hosts can replace this module when their policy system owns role meaning.
  """

  @behaviour Jido.Chat.Authorizer

  @all [
    :room_read,
    :room_join,
    :room_leave,
    :room_manage,
    :member_manage,
    :message_post,
    :message_edit,
    :message_delete,
    :reaction_add,
    :reaction_remove,
    :thread_create,
    :thread_reply,
    :bridge_manage,
    :agent_request
  ]

  @permissions %{
    "owner" => @all,
    "admin" => @all,
    "moderator" => @all -- [:room_manage, :member_manage, :bridge_manage],
    "member" => [
      :room_read,
      :room_leave,
      :message_post,
      :message_edit,
      :reaction_add,
      :reaction_remove,
      :thread_create,
      :thread_reply
    ],
    "guest" => [:room_read, :room_leave]
  }

  @impl true
  def authorize(principal, action, _resource, _context) do
    if Enum.any?(principal.roles, &(action in Map.get(@permissions, &1, []))),
      do: :ok,
      else: {:error, :not_authorized}
  end
end
