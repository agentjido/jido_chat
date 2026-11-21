defmodule Jido.Chat.Telegram.Adapter do
  @moduledoc "Stateless Telegram adapter for native Chat request and result Signals."
  use Jido.Chat.Adapter
  alias Jido.Chat.Telegram.{Normalizer, Operations}

  @impl true
  def channel_type, do: :telegram
  @impl true
  def default_transport, do: Jido.Chat.Telegram.Transport.ExGramClient

  @impl true
  def operations, do: Jido.Chat.Telegram.operations()
  @impl true
  def event_definitions, do: Jido.Chat.Telegram.event_definitions()

  @native [
    :send_message,
    :stream_text,
    :send_file,
    :edit_message,
    :delete_message,
    :start_typing,
    :fetch_metadata,
    :download_file,
    :add_reaction,
    :remove_reaction,
    :open_dm,
    :create_thread
  ]
  @impl true
  def capabilities do
    Map.new(Jido.Chat.Operations.Definitions.all(), fn {_, {_, operation, _, _, _}} ->
      status = if operation in @native, do: :native, else: :unsupported
      {operation, status}
    end)
  end

  @impl true
  def invoke(client, request, opts) do
    case Jido.Chat.Operations.Definitions.lookup(request.type) do
      {_, operation, _, _, _} -> Operations.invoke(operation, client, request, opts)
      _ -> {:error, {:not_attempted, :unsupported}}
    end
  end

  @impl true
  def normalize(client, input, _opts), do: Normalizer.normalize(client, input)
end
