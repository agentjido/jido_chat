defmodule Jido.Chat.Discord.Source do
  @moduledoc """
  Receive-only Discord Gateway push source for the shared Chat Sensor.

  The host starts the Sensor. This source starts one linked connection worker.
  The worker owns heartbeats, session resume, and reconnects. It sends no chat
  replies and does not acknowledge interactions. Use RespondInteraction in a
  host Action with a private interaction token when a response is required.

  Admission is not durable storage. Discord replay is bounded by its session
  lifetime. A new worker has no saved session. Use one Sensor per bot token.
  Default intents are guilds, guild messages/reactions, direct messages/reactions,
  and message content (46593). Enable Message Content in the bot portal if needed.
  Set `:intents` in Source options to use a different intent set.

  Optional `interaction_sink: {Module, :function, extra_args}` receives one private
  `Jido.Chat.Discord.Interaction` before normalization and Signal admission.
  It must return `:ok` promptly. Failure stops the Source with `:input_rejected`;
  no fact is admitted and the sequence does not advance. A sink can receive a
  replay, or retain a control whose fact admission later fails. The host owns
  deduplication, bounded storage, atomic use, expiry, and cleanup in both cases.
  The sink must not log its input. The worker has no private token store.
  Bot identity comes from READY and must match the interaction application.
  The normal Agent Plugin does not supply these private execution options.
  """
  @behaviour Jido.Chat.Sensor.Source
  @impl true
  def mode, do: :push
  @impl true
  def signal_types, do: Enum.map(Jido.Chat.Discord.event_definitions(), & &1.type())
  @impl true
  def key(client, _options) do
    case client.credentials[:token] do
      token when is_binary(token) and token != "" -> :crypto.hash(:sha256, token)
      _ -> nil
    end
  end

  @impl true
  def start_link(client, sensor, options), do: Jido.Chat.Discord.GatewayWorker.start_link({client, sensor, options})
end
