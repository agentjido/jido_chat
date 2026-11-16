defmodule Jido.Chat.IdentityProvider.Function do
  @moduledoc "Resolves principals with a host function for tests and local setup."

  @behaviour Jido.Chat.IdentityProvider

  @impl true
  def resolve(source, context) do
    resolver = get_in(context, [:options, :resolver]) || context[:resolver]

    if is_function(resolver, 2),
      do: resolver.(source, context),
      else: {:error, :identity_resolver_missing}
  end
end
