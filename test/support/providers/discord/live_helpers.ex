defmodule Jido.Chat.Discord.LiveHelpers do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Chat.LiveCase

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
    complete(Jido.Chat.execute(client, signal, options), client, signal)
  end

  def native(client, action, data) do
    signal = request(action.signal_definition(), client, data)

    assert {:ok, %{signal: completed}} =
             Jido.Chat.Discord.ActionHelpers.execute(action, signal, %{client: client}, max_attempts: 1)

    complete({:ok, completed}, client, signal)
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
    assert :ok = Jido.Chat.AdapterTestKit.Assertions.assert_json_round_trip(signal, Jido.Chat.catalog(client))
    refute Jason.encode!(Jido.Signal.Codec.to_map(signal)) =~ client.credentials.token
    signal.data["result"]
  end

  def complete({:error, _} = error, client, _request) do
    LiveCase.flag_result(client.config[:live_stop], error)
    flunk("Chat request failed")
  end

  @doc false
  def wire(client, method, path, body \\ nil, opts \\ []) do
    opts = Keyword.merge(client.config, opts)
    client.transport.call(client.credentials.token, method, path, body, opts)
  end

  @doc false
  def message(client, room, text) do
    text = "Jido live #{client.config[:live_run_id]}: " <> text
    Jido.Chat.send_text(client, room, text) |> complete(client)
  end

  def track_message(client, room, %{"id" => id} = message) do
    LiveCase.on_cleanup({:discord_message, room, id}, fn -> remove_message(client, room, id) end)
    message
  end

  def forget_message(room, id), do: LiveCase.on_cleanup({:discord_message, room, id}, fn -> :ok end)

  def raw_message(client, room, id) do
    assert {:ok, raw} = wire(client, :get, "/channels/#{room}/messages/#{id}")
    assert raw["id"] == id
    raw
  end

  @doc false
  def remove_message(client, room, id) do
    case Jido.Chat.delete_message(client, room, id, options: [live_cleanup?: true]) do
      {:ok, _} -> :ok
      {:error, %Jido.Chat.Error{code: :not_found}} -> :ok
      error -> flunk("test message cleanup failed: #{inspect(error)}")
    end
  end

  @doc false
  def remove_thread(client, id, room \\ nil) do
    parent =
      case wire(client, :get, "/channels/" <> id, nil, live_cleanup?: true) do
        {:ok, channel} -> channel["parent_id"] || room
        {:error, {:rejected, :not_found, _}} -> room
        error -> flunk("test thread lookup failed: #{inspect(error)}")
      end

    case wire(client, :delete, "/channels/" <> id, nil, live_cleanup?: true) do
      {:ok, _} ->
        :ok

      {:error, {:rejected, :not_found, _}} ->
        :ok

      {:error, {:rejected, reason, _}} ->
        IO.puts("LIVE Discord thread cleanup rejected (#{reason})")
        flunk("test thread cleanup was rejected")

      _ ->
        flunk("test thread cleanup failed")
    end

    # Discord keeps the generated type-18 notice after it deletes a thread.
    # Its ID is the created thread ID. Do not delete a normal starter message.
    if parent do
      case wire(client, :get, "/channels/#{parent}/messages/#{id}", nil, live_cleanup?: true) do
        {:ok, %{"type" => 18}} -> remove_message(client, parent, id)
        {:ok, _} -> :ok
        {:error, {:rejected, :not_found, _}} -> :ok
        error -> flunk("test thread notice lookup failed: #{inspect(error)}")
      end
    end
  end
end
