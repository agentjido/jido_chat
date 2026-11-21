defmodule Jido.Chat.Discord.Adapter do
  @moduledoc "Stateless Discord adapter for Chat Actions and Signals."
  use Jido.Chat.Adapter

  @native ~w(send_message stream_text send_file edit_message delete_message start_typing fetch_metadata fetch_thread fetch_message download_file open_dm create_thread add_reaction remove_reaction fetch_messages list_threads)a
  @impl true
  def channel_type, do: :discord
  @impl true
  def default_transport, do: Jido.Chat.Discord.Transport.REST
  @impl true
  def operations, do: Jido.Chat.Discord.operations()
  @impl true
  def event_definitions, do: Jido.Chat.Discord.event_definitions()
  @impl true
  def capabilities do
    Map.new(Jido.Chat.Operations.Definitions.all(), fn {_, {_, operation, _, _, _}} ->
      {operation, if(operation in @native, do: :native, else: :unsupported)}
    end)
  end

  @impl true
  def invoke(client, signal, opts) do
    case Jido.Chat.Operations.Definitions.lookup(signal.type) do
      {_, operation, _, _, _} -> Jido.Chat.Discord.Operations.invoke(operation, client, signal, opts)
      _ -> {:error, {:not_attempted, :unsupported}}
    end
  end

  @impl true
  def normalize(client, input, _opts), do: Jido.Chat.Discord.Normalizer.normalize(client, input)
end
