defmodule Jido.Chat.Discord.LiveHelpers do
  @moduledoc false
  import ExUnit.Assertions

  @doc false
  def request(definition, client, data) do
    definition.new!(Map.merge(%{"client_id" => client.id, "request_id" => "live:" <> Jido.Id.uuid7()}, data),
      extensions: %{
        "traceparent" => "00-11111111111111111111111111111111-2222222222222222-01",
        "tracestate" => "discord=live"
      }
    )
  end

  @doc false
  def execute(client, definition, data, options \\ []) do
    signal = request(definition, client, data)
    complete(retry(fn -> Jido.Chat.execute(client, signal, options) end), client, signal)
  end

  @doc false
  def complete(result, client, request \\ nil)

  def complete({:ok, signal}, client, request) do
    assert signal.data["client_id"] == client.id
    assert signal.source == client.source
    assert signal.data["request_id"] != ""

    if request do
      assert signal.data["request_id"] == request.data["request_id"]
      assert signal.data["operation"] == request.type
      assert signal.extensions["jidocausationid"] == request.id
      assert signal.extensions["traceparent"] == request.extensions["traceparent"]
      assert signal.extensions["tracestate"] == "discord=live"
    end

    assert {:ok, _} = Jido.Signal.Catalog.validate(Jido.Chat.catalog(client), signal)
    refute Jason.encode!(Jido.Signal.Codec.to_map(signal)) =~ client.credentials.token
    signal.data["result"]
  end

  def complete({:error, error}, _client, _request), do: flunk("Chat request failed: #{inspect(error)}")

  @doc false
  def retry(call, attempts \\ 5) do
    case call.() do
      {:error, %Jido.Chat.Error{code: :rate_limited, signal: signal}} when attempts > 0 ->
        Process.sleep(min(signal.data["retry_after_ms"] + 100, 10_000))
        retry(call, attempts - 1)

      result ->
        result
    end
  end

  @doc false
  def wire(client, method, path, body \\ nil, attempts \\ 5) do
    case client.transport.call(client.credentials.token, method, path, body, []) do
      {:error, {:rejected, :rate_limited, %{retry_after_ms: delay}}} when attempts > 0 ->
        Process.sleep(min(delay + 100, 10_000))
        wire(client, method, path, body, attempts - 1)

      result ->
        result
    end
  end

  @doc false
  def setup_target do
    client =
      Jido.Chat.Client.new!(Jido.Chat.Discord.Adapter,
        id: "discord-live",
        credentials: %{token: System.fetch_env!("DISCORD_BOT_TOKEN")}
      )

    room = System.fetch_env!("DISCORD_TEST_CHANNEL_ID")
    {:ok, channel} = wire(client, :get, "/channels/" <> room)
    {:ok, guild} = wire(client, :get, "/guilds/" <> channel["guild_id"])
    assert guild["name"] == "agentjido-test"
    assert channel["name"] == "bridge"
    %{client: client, room: room, guild: guild["id"]}
  end

  @doc false
  def message(client, room, text) do
    retry(fn -> Jido.Chat.send_text(client, room, text) end) |> complete(client)
  end

  @doc false
  def remove_message(client, room, id) do
    case retry(fn -> Jido.Chat.delete_message(client, room, id) end) do
      {:ok, _} -> :ok
      {:error, %Jido.Chat.Error{code: :not_found}} -> :ok
      error -> flunk("test message cleanup failed: #{inspect(error)}")
    end
  end

  @doc false
  def remove_thread(client, id, room \\ nil) do
    parent =
      case wire(client, :get, "/channels/" <> id) do
        {:ok, channel} -> channel["parent_id"] || room
        {:error, {:rejected, :not_found, _}} -> room
        error -> flunk("test thread lookup failed: #{inspect(error)}")
      end

    case wire(client, :delete, "/channels/" <> id) do
      {:ok, _} -> :ok
      {:error, {:rejected, :not_found, _}} -> :ok
      error -> flunk("test thread cleanup failed: #{inspect(error)}")
    end

    # Discord keeps the generated type-18 notice after it deletes a thread.
    # Its ID is the created thread ID. Do not delete a normal starter message.
    if parent do
      case wire(client, :get, "/channels/#{parent}/messages/#{id}") do
        {:ok, %{"type" => 18}} -> remove_message(client, parent, id)
        {:ok, _} -> :ok
        {:error, {:rejected, :not_found, _}} -> :ok
        error -> flunk("test thread notice lookup failed: #{inspect(error)}")
      end
    end
  end
end
