defmodule Jido.Chat.Signal.Adapter do
  @moduledoc "Stateless Signal adapter for native Chat request and result Signals."
  use Jido.Chat.Adapter

  alias Jido.Chat.Operations.Definitions
  alias Jido.Chat.Signal.{Normalizer, Operations}

  @native [:send_message, :send_file]

  @impl true
  def channel_type, do: :signal

  @impl true
  def default_transport, do: Jido.Chat.Signal.Transport.JsonRpcClient

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
