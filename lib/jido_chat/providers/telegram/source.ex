defmodule Jido.Chat.Telegram.Source do
  @moduledoc """
  Telegram update source for `Jido.Chat.Sensor`.

  Uses the FetchUpdates Action and the Client catalog. It starts no process,
  sends no replies, and does not acknowledge callbacks. Use one polling Sensor
  per bot token. Webhook delivery and polling must not run at the same time.
  """
  @behaviour Jido.Chat.Sensor.Source

  @impl true
  def mode, do: :poll

  @impl true
  def poll_interval(options), do: Keyword.get(options, :interval, 1_000)

  @impl true
  def signal_types do
    [
      "jido.chat.message.received",
      "jido.chat.message.updated",
      "jido.chat.reaction.added",
      "jido.chat.reaction.removed",
      "jido.chat.action.received"
    ]
  end

  @impl true
  def key(client, _options) do
    case client.credentials[:token] do
      token when is_binary(token) and token != "" -> :crypto.hash(:sha256, token)
      _ -> nil
    end
  end

  @impl true
  def read(client, cursor, options) do
    data = options |> Keyword.delete(:interval) |> Map.new() |> Map.new(fn {key, value} -> {to_string(key), value} end)

    data =
      Map.merge(
        %{
          "limit" => 100,
          "timeout" => 0,
          "allowed_updates" => ["message", "edited_message", "callback_query", "message_reaction"]
        },
        data
      )

    data = if is_nil(cursor), do: data, else: Map.put(data, "offset", cursor)
    data = Map.merge(data, %{"client_id" => client.id, "request_id" => Jido.Id.uuid7()})

    with {:ok, request} <- Jido.Chat.Signal.Policy.new(Jido.Chat.Telegram.Signal.FetchUpdates, data),
         {:ok, completed} <- Jido.Chat.execute(client, request, timeout: (data["timeout"] + 5) * 1_000),
         result <- completed.data["result"],
         {:ok, signals} <- decode(client, result["signals"]) do
      {:ok, Enum.filter(signals, &(&1.type in signal_types())), result["next_offset"] || cursor}
    end
  end

  defp decode(client, wires) do
    Enum.reduce_while(wires, {:ok, []}, fn wire, {:ok, signals} ->
      case Jido.Signal.Catalog.decode(Jido.Chat.catalog(client), wire) do
        {:ok, signal} -> {:cont, {:ok, [signal | signals]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, signals} -> {:ok, Enum.reverse(signals)}
      error -> error
    end
  end
end
