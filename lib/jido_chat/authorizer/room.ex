defmodule Jido.Chat.Authorizer.Room do
  @moduledoc "Preserves the local Room administrator and membership policy."

  @behaviour Jido.Chat.Authorizer

  @impl true
  def authorize(principal, action, _resource, context) do
    actor = principal.agent_address || principal.id
    admin = context.admin
    members = context.members
    member = context[:member]

    allowed =
      case action do
        :room_join -> actor == admin
        :room_leave -> actor == admin or actor == member
        :message_post -> actor in members
        :member_check -> actor == member
        _other -> false
      end

    if allowed, do: :ok, else: {:error, :not_authorized}
  end
end
