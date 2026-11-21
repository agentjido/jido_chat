defmodule Jido.Chat.Slack.Adapter do
  @moduledoc "Stateless Slack adapter for native Chat request and result Signals."

  use Jido.Chat.Adapter

  alias Jido.Chat.Slack.{Normalizer, Operations}

  @native ~w(stream_text send_message send_file edit_message delete_message fetch_metadata fetch_thread fetch_message get_user fetch_subject get_thread_participants mark_as_read download_file add_reaction remove_reaction post_ephemeral open_modal load_options fetch_messages list_threads open_dm)a

  @impl true
  def channel_type, do: :slack

  @impl true
  def default_transport, do: Jido.Chat.Slack.Transport.ReqClient

  @impl true
  def operations, do: Jido.Chat.Slack.operations()

  @impl true
  def event_definitions, do: Jido.Chat.Slack.event_definitions()

  @impl true
  def capabilities do
    Map.new(Jido.Chat.Operations.Definitions.all(), fn {_, {_, operation, _, _, _}} ->
      {operation, if(operation in @native, do: :native, else: :unsupported)}
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
