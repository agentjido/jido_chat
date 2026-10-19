defmodule Jido.Chat.Signal.CreateThread do
  @moduledoc "Request Signal API for `Jido.Chat.CreateThread`. The Action owns the shared schema."

  @doc false
  defdelegate __signal_definition__(), to: Jido.Chat.CreateThread

  for name <- [:type, :dataschema, :default_source, :datacontenttype, :schema] do
    @doc "Returns the shared CreateThread definition field."
    defdelegate unquote(name)(), to: Jido.Chat.CreateThread
  end

  @doc "Validates data with the shared CreateThread schema."
  defdelegate validate_data(data), to: Jido.Chat.CreateThread

  @doc "Builds a CreateThread request Signal."
  defdelegate new(data \\ %{}, opts \\ []), to: Jido.Chat.CreateThread

  @doc "Builds a CreateThread request Signal or raises."
  defdelegate new!(data \\ %{}, opts \\ []), to: Jido.Chat.CreateThread
end
