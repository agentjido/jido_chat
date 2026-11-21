defmodule Jido.Chat.Slack.Source do
  @moduledoc """
  Receive-only Slack Socket Mode source for the shared Chat Sensor.

  The host starts the Sensor. This source starts one linked Socket Mode worker.
  The worker acknowledges only input that the Sensor admits. The source sends no
  chat reply and stores no state outside the worker connection.
  """

  @behaviour Jido.Chat.Sensor.Source

  @impl true
  def mode, do: :push

  @impl true
  def signal_types, do: Enum.map(Jido.Chat.Slack.event_definitions(), & &1.type())

  @impl true
  def key(client, _options) do
    case client.credentials[:app_token] do
      token when is_binary(token) and token != "" -> :crypto.hash(:sha256, token)
      _ -> nil
    end
  end

  @impl true
  def start_link(client, sensor, options) do
    case client.credentials[:app_token] do
      token when is_binary(token) and token != "" ->
        options =
          Keyword.merge(options,
            app_token: token,
            sink_mfa: {__MODULE__, :ingest, [client, sensor]}
          )

        Jido.Chat.Slack.SocketModeWorker.start_link(options)

      _ ->
        {:error, :missing_app_token}
    end
  end

  @doc false
  def ingest(client, sensor, payload, _options) do
    with {:ok, delivery} <- client.adapter.normalize(client, payload, []),
         :ok <- Jido.Chat.Sensor.push(sensor, delivery.signals) do
      :ok
    end
  end
end
