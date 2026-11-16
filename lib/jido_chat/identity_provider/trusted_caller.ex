defmodule Jido.Chat.IdentityProvider.TrustedCaller do
  @moduledoc """
  Resolves the current trusted Room caller without an external identity system.

  This provider preserves the local Room contract. Do not use it at an
  untrusted transport boundary.
  """

  @behaviour Jido.Chat.IdentityProvider

  @impl true
  def resolve(source, context) do
    case get_in(context, [:caller_context, :actor]) do
      %Jido.Chat.Principal{id: id} = principal when id == source.external_id ->
        {:ok, principal}

      %Jido.Agent.Address{id: id} = address when id == source.external_id ->
        {:ok,
         %{
           id: id,
           kind: :agent,
           assurance: :verified,
           agent_address: address,
           attributes: %{}
         }}

      actor when is_binary(actor) and actor == source.external_id ->
        {:ok, %{id: actor, kind: :human, assurance: :verified, attributes: %{}}}

      _other ->
        {:error, :caller_identity_mismatch}
    end
  end
end
