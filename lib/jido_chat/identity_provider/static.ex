defmodule Jido.Chat.IdentityProvider.Static do
  @moduledoc """
  Resolves principals from a fixed map for tests and local integrations.

  Set `context.options.identities` to a map keyed by the complete
  `{provider, account_id, external_id}` tuple.
  """

  @behaviour Jido.Chat.IdentityProvider

  @impl true
  def resolve(source, context) do
    identities = get_in(context, [:options, :identities]) || context[:identities] || %{}

    case Map.fetch(identities, Jido.Chat.IdentitySource.key(source)) do
      {:ok, principal} -> {:ok, principal}
      :error -> {:error, :identity_not_found}
    end
  end
end
