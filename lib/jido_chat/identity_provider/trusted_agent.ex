defmodule Jido.Chat.IdentityProvider.TrustedAgent do
  @moduledoc "Resolves a Jido Agent Address from trusted caller context."

  @behaviour Jido.Chat.IdentityProvider

  @impl true
  def resolve(source, context) do
    case get_in(context, [:caller_context, :actor]) do
      %Jido.Agent.Address{id: id} = address when id == source.external_id ->
        {:ok,
         %{
           id: id,
           kind: :agent,
           assurance: :verified,
           agent_address: address,
           attributes: %{
             "namespace" => address.namespace,
             "partition" => address.partition
           }
         }}

      _other ->
        {:error, :trusted_agent_required}
    end
  end
end
