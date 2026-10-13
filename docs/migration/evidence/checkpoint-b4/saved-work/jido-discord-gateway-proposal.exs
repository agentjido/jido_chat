defmodule Jido.Chat.Discord.GatewayWorkerTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.Discord.{Adapter, GatewayWorker}

  defmodule Sink do
    def emit(pid, delivery, opts) do
      send(pid, {:sink_emit, delivery, opts})
      {:ok, :accepted}
    end
  end

  defmodule Source do
    def pop(agent) do
      Agent.get_and_update(agent, fn
        [next | rest] -> {{:ok, next}, rest}
        [] -> {{:ok, []}, []}
      end)
    end
  end

  defp captured_binding do
    {:ok, binding} = Jido.Chat.bind(Adapter, id: "bridge_discord")
    binding
  end

  defp worker(extra \\ []) do
    start_supervised!({GatewayWorker,
      [bridge_id: "bridge_discord", binding: captured_binding(),
       sink_mfa: {Sink, :emit, [self()]}, poll_interval_ms: 60_000] ++ extra})
  end

  defp message do
    %{"id" => "msg-1", "channel_id" => "channel-1", "content" => "hello",
      "author" => %{"id" => "user-1"}}
  end

  test "adapter listener_child_specs/2 returns expected webhook/gateway specs" do
    binding = captured_binding()
    assert {:ok, []} = Adapter.listener_child_specs(binding.id, ingress: %{mode: "webhook"})
    assert {:error, :invalid_sink_mfa} = Adapter.listener_child_specs(binding.id, ingress: %{mode: "gateway"})
    assert {:ok, specs} = Adapter.listener_child_specs(binding.id, binding: binding,
      ingress: %{mode: "gateway"}, sink_mfa: {Sink, :emit, [self()]})
    assert Enum.map(specs, & &1.id) == [
      {:discord_gateway_buffer, binding.id}, {:discord_gateway_listener, binding.id},
      {:discord_gateway_worker, binding.id}]
    assert {:ok, [spec]} = Adapter.listener_child_specs(binding.id, binding: binding,
      ingress: %{mode: "gateway", source: "mfa", event_source_mfa: {Source, :pop, [self()]}},
      sink_mfa: {Sink, :emit, [self()]})
    assert spec.id == {:discord_gateway_worker, binding.id}
  end

  test "gateway worker emits message create payload through sink" do
    pid = worker()
    GatewayWorker.emit(pid, %{event: "MESSAGE_CREATE", payload: message()})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [fact]}, []}
    assert fact.type == "jido.chat.message.received"
    assert fact.data["message_id"] == "msg-1"
    assert fact.data["room_id"] == "channel-1"
    assert fact.data["text"] == "hello"
  end

  test "gateway worker normalizes reaction dispatch payload into EventEnvelope" do
    pid = worker()
    GatewayWorker.emit(pid, %{"t" => "MESSAGE_REACTION_ADD", "d" => %{
      "channel_id" => "channel-1", "message_id" => "msg-1", "user_id" => "user-1",
      "emoji" => %{"name" => "👍"}}})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [fact]}, []}
    assert fact.type == "jido.chat.reaction.added"
    assert fact.data["reaction"] == "👍"
    assert fact.data["room_id"] == "channel-1"
  end

  test "gateway worker preserves a partial message update as a typed lifecycle event" do
    pid = worker()
    GatewayWorker.emit(pid, %{"t" => "MESSAGE_UPDATE", "d" => %{
      "id" => "msg-1", "channel_id" => "channel-1",
      "edited_timestamp" => "2026-08-20T12:00:00Z", "flags" => 4}})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [fact]}, []}
    assert fact.type == "jido.chat.message.updated"
    assert fact.data["message_id"] == "msg-1"
    assert fact.data["text"] == nil
    assert fact.data["timestamp"] == "2026-08-20T12:00:00Z"
    refute Map.has_key?(fact.data, "raw")
  end

  test "gateway worker treats null content as absent and preserves empty content" do
    pid = worker()
    GatewayWorker.emit(pid, {:MESSAGE_UPDATE, %{
      "id" => "msg-null", "channel_id" => "channel-1", "content" => nil}})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [null]}, []}
    assert null.data["text"] == nil
    GatewayWorker.emit(pid, {:MESSAGE_UPDATE, %{
      "id" => "msg-empty", "channel_id" => "channel-1", "content" => ""}})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [empty]}, []}
    assert empty.data["text"] == ""
  end

  test "gateway worker stays available after an invalid lifecycle payload" do
    pid = worker()
    GatewayWorker.emit(pid, {:MESSAGE_UPDATE, %{"id" => "msg-1"}})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [failure]}, []}
    assert failure.type == "jido.chat.normalization.failed"
    GatewayWorker.emit(pid, {:MESSAGE_CREATE, message()})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [fact]}, []}
    assert fact.type == "jido.chat.message.received"
    assert :sys.get_state(pid).last_result == :ok
  end

  test "gateway worker stays available after scalar payloads and object-valued lifecycle IDs" do
    pid = worker()
    for payload <- ["scalar", %{"id" => %{}, "channel_id" => %{}}] do
      GatewayWorker.emit(pid, {:MESSAGE_UPDATE, payload})
      assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [failure]}, []}
      assert failure.type == "jido.chat.normalization.failed"
    end
    GatewayWorker.emit(pid, {:MESSAGE_CREATE, message()})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [fact]}, []}
    assert fact.type == "jido.chat.message.received"
  end

  test "gateway worker preserves populated message update details" do
    pid = worker()
    payload = Map.merge(message(), %{"content" => "changed",
      "edited_timestamp" => "2026-08-20T12:00:00Z",
      "attachments" => [%{"id" => "file-1", "filename" => "photo.png",
        "url" => "https://fixture.test/private", "content_type" => "image/png"}]})
    GatewayWorker.emit(pid, {:MESSAGE_UPDATE, payload})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [fact]}, []}
    assert fact.data["text"] == "changed"
    assert fact.data["sender"]["id"] == "user-1"
    assert fact.data["timestamp"] == "2026-08-20T12:00:00Z"
    assert [%{"kind" => "image", "resource_ref" => _}] = fact.data["media"]
    refute Jason.encode!(Jido.Signal.to_map(fact)) =~ "https://fixture.test/private"
  end

  test "gateway worker preserves a message delete as a typed lifecycle event" do
    pid = worker()
    GatewayWorker.emit(pid, {:MESSAGE_DELETE, %{"id" => "msg-1", "channel_id" => "channel-1"}})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [fact]}, []}
    assert fact.type == "jido.chat.message.deleted"
    assert fact.data["message_id"] == "msg-1"
    assert fact.data["room_id"] == "channel-1"
  end

  test "gateway worker polls event source and emits events through sink" do
    source = start_supervised!({Agent, fn -> [[
      {:MESSAGE_CREATE, message()},
      {:MESSAGE_DELETE, %{"id" => "msg-2", "channel_id" => "channel-1"}}]] end})
    pid = worker(event_source_mfa: {Source, :pop, [source]})
    assert_receive {:sink_emit, %Jido.Chat.Delivery{signals: [first, second]}, []}
    assert first.type == "jido.chat.message.received"
    assert second.type == "jido.chat.message.deleted"
    assert :sys.get_state(pid).last_result == :ok
    refute_received {:sink_emit, _, _}
  end
end
