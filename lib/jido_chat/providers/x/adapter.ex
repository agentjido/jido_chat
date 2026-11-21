defmodule Jido.Chat.X.Adapter do
  @moduledoc "Stateless X Direct Messages adapter for Jido Chat."
  use Jido.Chat.Adapter

  alias Jido.Chat.Operations.Definitions
  alias Jido.Chat.X.{Normalizer, Operations, Transport.XdkClient}

  @native ~w(send_message delete_message fetch_message fetch_messages open_dm)a

  @impl true
  def channel_type, do: :x

  @impl true
  def default_transport, do: XdkClient

  @impl true
  def event_definitions do
    [Jido.Chat.Signal.MessageReceived, Jido.Chat.Signal.NormalizationFailed]
  end

  @impl true
  def capabilities do
    Map.new(Definitions.all(), fn {_, {_, operation, _, _, _}} ->
      {operation, if(operation in @native, do: :native, else: :unsupported)}
    end)
  end

  @impl true
  def invoke(client, request, opts) do
    case Definitions.lookup(request.type) do
      {_, operation, _, _, _} -> Operations.invoke(operation, client, request, opts)
      _ -> {:error, {:not_attempted, :unsupported}}
    end
  end

  @impl true
  def normalize(client, input, _opts), do: Normalizer.normalize(client, input)
end
