defmodule Jido.Chat.Authorizer.Room do
  @moduledoc "Preserves the local Room administrator and membership policy."

  @behaviour Jido.Chat.Authorizer

  @impl true
  def authorize(principal, action, _resource, context) do
    actor = principal.agent_address || principal.id
    admin = context.admin
    member = context[:member]
    actor_active? = Map.get(context, :actor_active?, actor in Map.get(context, :members, []))

    allowed =
      case action do
        :room_join -> actor == admin
        :room_leave -> actor == admin or actor == member
        :message_post -> actor_active?
        :member_check -> actor == member
        _other -> false
      end

    if allowed, do: :ok, else: {:error, :not_authorized}
  end
end
