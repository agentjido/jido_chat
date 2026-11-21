defmodule Jido.Chat.Discord.Interaction do
  @moduledoc """
  Private interaction controls passed to an explicit host Source sink.

  This value must stay outside Signals and Agent state. The host owns bounded
  storage, atomic single-use lookup, and cleanup on expiry and shutdown. Pass
  the value as `:interaction` in private execution options to RespondInteraction.
  The initial response must start within three seconds of Gateway receipt.
  No store or per-interaction execution options are supplied by the Agent Plugin.
  """
  @derive {Inspect, only: []}
  @enforce_keys [:client_id, :bot_id, :room_id, :interaction_id, :token, :received_at]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          client_id: String.t(),
          bot_id: String.t(),
          room_id: String.t(),
          interaction_id: String.t(),
          token: String.t(),
          received_at: integer()
        }

  @doc false
  def capture(_client, _event, nil), do: :ok

  def capture(client, event, {module, function, args}) when is_atom(module) and is_atom(function) and is_list(args) do
    bot_id = client.config[:bot_id]

    with %{"type" => type, "id" => id, "application_id" => ^bot_id, "channel_id" => room, "token" => token} <- event,
         true <- type in [2, 3, 5],
         true <- Enum.all?([bot_id, id, room, token], &(is_binary(&1) and &1 != "")),
         :ok <-
           apply(module, function, [
             %__MODULE__{
               client_id: client.id,
               bot_id: bot_id,
               room_id: room,
               interaction_id: id,
               token: token,
               received_at: System.monotonic_time(:millisecond)
             }
             | args
           ]) do
      :ok
    else
      _ -> {:error, :interaction_rejected}
    end
  rescue
    _ -> {:error, :interaction_rejected}
  catch
    _, _ -> {:error, :interaction_rejected}
  end

  def capture(_, _, _), do: {:error, :interaction_rejected}

  @doc false
  def token(client, data, %__MODULE__{received_at: received_at} = private) when is_integer(received_at) do
    elapsed = System.monotonic_time(:millisecond) - private.received_at

    if private.client_id == client.id and private.room_id == data["room_id"] and
         private.interaction_id == data["interaction_id"] and
         is_binary(private.bot_id) and private.bot_id != "" and client.config[:bot_id] == private.bot_id and
         elapsed >= 0 and elapsed < 3_000 and
         is_binary(private.token) and private.token != "" do
      {:ok, private.token}
    else
      {:error, {:not_attempted, :invalid_interaction}}
    end
  end

  def token(_, _, _), do: {:error, {:not_attempted, :invalid_interaction}}
end
