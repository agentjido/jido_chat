defmodule Jido.Chat.Authorizer.DenyAll do
  @moduledoc "Rejects every Chat action."

  @behaviour Jido.Chat.Authorizer

  @impl true
  def authorize(_principal, _action, _resource, _context), do: {:error, :not_authorized}
end
