defmodule Jido.Chat.Slack.LiveAPI do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Chat
  alias Jido.Chat.LiveCase
  alias Jido.Chat.LiveCase.Probes
  alias Jido.Chat.Signal
  alias Jido.Chat.Slack.LiveFixture

  def rich_reply(ctx), do: controlled_reply(ctx, :public)

  def rich_and_reply(ctx) do
    {ctx, reply} = controlled_reply(ctx, :native)
    id = reply["id"]
    edited = reply["text"] <> " edited"
    edit_and_check_removal(ctx, id, edited, :native)
  end

  defp controlled_reply(ctx, mode) do
    {root, _} = post(ctx, marker(ctx, "rich reply root"), mode)
    root_id = root["id"]
    assert %{"ts" => ^root_id} = stored(ctx, root_id)
    value = "reply:#{ctx.run_id}"
    text = Chat.Adapter.render_stream(["*Jido live* ", ctx.run_id, " rich reply"])
    fields = %{"reply_to_id" => root_id, "keyboard" => keyboard(value), "format" => "markdown"}
    {reply, raw} = post(ctx, text, mode, fields)
    assert reply["thread_id"] == root_id
    assert reply["id"] != root_id
    assert %{"thread_ts" => ^root_id} = raw["message"]
    ctx = %{ctx | opts: [thread_ts: root_id]}
    assert_button(stored(ctx, reply["id"], mode), value)
    {ctx, reply}
  end

  def edit_keyboard(ctx) do
    value = "edit:#{ctx.run_id}"
    {sent, _} = post(ctx, marker(ctx, "before edit"), :public, %{"keyboard" => keyboard(value)})
    assert_button(stored(ctx, sent["id"]), value)
    edit_and_check_removal(ctx, sent["id"], marker(ctx, "after edit"))
  end

  def edit_and_check_removal(ctx, id, text, mode \\ :public) do
    assert %{"id" => ^id, "text" => ^text, "status" => "updated"} =
             edit(ctx, id, text, mode, %{"keyboard" => %{"rows" => []}})

    assert %{"ts" => ^id, "text" => ^text} = raw = stored(ctx, id, mode)
    refute Enum.any?(raw["blocks"] || [], &(&1["type"] == "actions"))
  end

  def delete(ctx) do
    {sent, _} = post(ctx, marker(ctx, "delete fixture"))
    id = sent["id"]
    assert %{"ts" => ^id} = stored(ctx, id)
    delete_and_check_absence(ctx, id, :public)

    repeated = execute(ctx, Signal.DeleteMessage, %{"room_id" => ctx.room_id, "message_id" => id})
    assert {:error, %Chat.Error{code: :not_found, signal: failed}} = repeated
    assert failed.data["outcome"] == "rejected"
    assert_receive {:slack_live_wire, :delete_message, [_, ^id], {:error, {:slack_api_error, "message_not_found", _}}}
  end

  def lifecycle(ctx) do
    text = marker(ctx, "native lifecycle")
    {sent, _} = post(ctx, text, :native)
    id = sent["id"]
    assert %{"text" => ^text} = stored(ctx, id, :native)
    edited = text <> " edited"
    assert %{"id" => ^id, "text" => ^edited, "status" => "updated"} = edit(ctx, id, edited, :native)
    assert %{"text" => ^edited} = stored(ctx, id, :native)
    delete_and_check_absence(ctx, id, :native)
  end

  defp delete_and_check_absence(ctx, id, mode) do
    data = %{"room_id" => ctx.room_id, "message_id" => id}
    assert %{"acknowledged" => true} = complete(ctx, Signal.DeleteMessage, data, mode)
    LiveFixture.forget_cleanup(id)
    assert_receive {:slack_live_wire, :delete_message, [_, ^id], {:ok, true}}
    assert {:error, %Chat.Error{code: :not_found, signal: failed}} = execute(ctx, Signal.FetchMessage, data)
    assert failed.data["outcome"] == "rejected"
    assert_receive {:slack_live_wire, :fetch_message, [_, ^id], {:error, :not_found}}
  end

  def reactions(ctx), do: reaction_cycle(ctx, :public)
  def native_reactions(ctx), do: reaction_cycle(ctx, :native)

  defp reaction_cycle(ctx, mode) do
    {sent, _} = post(ctx, marker(ctx, "reaction"), mode)
    id = sent["id"]
    data = %{"room_id" => ctx.room_id, "message_id" => id, "reaction" => "thumbsup"}

    assert %{"acknowledged" => true} = complete(ctx, Signal.AddReaction, data, mode)
    # Slack accepts the thumbsup alias and returns the canonical name.
    assert Enum.any?(stored(ctx, id)["reactions"] || [], &(&1["name"] == "+1" and &1["count"] == 1))
    assert %{"acknowledged" => true} = complete(ctx, Signal.RemoveReaction, data, mode)
    refute Enum.any?(stored(ctx, id)["reactions"] || [], &(&1["name"] == "+1"))
  end

  def metadata(ctx) do
    result = complete(ctx, Signal.FetchMetadata, %{"room_id" => ctx.room_id})
    assert_receive {:slack_live_wire, :fetch_metadata, [room], {:ok, channel}}
    assert result["id"] == channel["id"] and channel["id"] == room and room == ctx.room_id
    assert result["name"] == channel["name"]
  end

  def identity(ctx) do
    assert {:ok, %{"user_id" => user_id}} = LiveFixture.api_request(ctx, "auth.test", %{})
    assert %{"id" => ^user_id, "is_bot" => true} = complete(ctx, Signal.GetUser, %{"user_id" => user_id})
    metadata(ctx)
  end

  def direct(ctx) do
    assert %{"id" => room, "kind" => "direct"} = complete(ctx, Signal.OpenDm, %{"user_id" => ctx.user_id})
    assert_receive {:slack_live_wire, :open_dm, [user], {:ok, ^room}}
    assert user == ctx.user_id
  end

  def render_and_send(ctx) do
    parts = ["Jido live ", ctx.run_id, " final render"]
    text = Chat.Adapter.render_stream(parts)
    assert text == Enum.join(parts)
    {sent, _} = post(ctx, text, :native)
    assert %{"text" => ^text} = stored(ctx, sent["id"])
  end

  def thread(ctx) do
    {root, _} = post(ctx, marker(ctx, "thread root"))
    root_id = root["id"]
    text = marker(ctx, "inside thread")
    {reply, raw} = post(ctx, text, :public, %{"thread_id" => root_id})
    reply_id = reply["id"]
    assert %{"thread_ts" => ^root_id} = raw["message"]
    assert reply["thread_id"] == root_id

    page = complete(ctx, Signal.ListThreads, %{"room_id" => ctx.room_id, "limit" => 15})
    assert Enum.any?(page["threads"], &(&1["id"] == root_id and &1["parent_message_id"] == root_id))

    outcome = execute(ctx, Signal.FetchThread, %{"room_id" => ctx.room_id, "thread_id" => root_id})

    case wire_result(:fetch_thread) do
      {:ok, %{"messages" => messages}} ->
        assert {:ok, signal} = outcome
        assert %{"id" => ^root_id, "parent_message_id" => ^root_id} = signal.data["result"]
        assert Enum.any?(messages, &(&1["ts"] == reply_id and &1["text"] == text))

      {:error, {:slack_api_error, code, _}} when code in ["missing_scope", "not_allowed_token_type"] ->
        {:blocked, "Slack test token cannot read channel threads with conversations.replies"}

      _ ->
        flunk("Slack thread read failed")
    end
  end

  def reply(ctx), do: native_thread_send(ctx, "reply_to_id")
  def native_thread(ctx), do: native_thread_send(ctx, "thread_id")

  defp native_thread_send(ctx, field) do
    {root, _} = post(ctx, marker(ctx, "native thread root"), :native)
    root_id = root["id"]
    text = marker(ctx, "native threaded message")
    {reply, raw} = post(ctx, text, :native, %{field => root_id})

    assert reply["id"] != root_id
    assert reply["thread_id"] == root_id
    assert %{"thread_ts" => ^root_id, "text" => ^text} = raw["message"]
  end

  def reject_send(ctx) do
    text = marker(ctx, "provider rejection")
    button = %{"text" => String.duplicate("a", 80), "value" => "jido:invalid"}
    data = %{"room_id" => ctx.room_id, "text" => text, "keyboard" => %{"rows" => [[button]]}}
    outcome = execute(ctx, Signal.SendMessage, data)

    case outcome do
      {:ok, signal} ->
        LiveFixture.cleanup(ctx, signal.data["result"]["id"])
        flunk("Slack accepted the invalid blocks")

      {:error, %Chat.Error{signal: failed}} ->
        assert failed.type == Chat.SendMessage.Failed.type()
        assert failed.data["outcome"] == "rejected"
        assert {:error, {:slack_api_error, code, _}} = wire_result(:send_message)
        assert code in ["invalid_blocks", "invalid_blocks_format"]
    end
  end

  def post(ctx, text, mode \\ :public, fields \\ %{}) do
    data = Map.merge(%{"room_id" => ctx.room_id, "text" => text}, fields)
    request = Probes.request(ctx, Signal.SendMessage, data)
    assert {:ok, signal} = Probes.execute(ctx, request, mode)
    result = Probes.assert_sent(ctx, signal, Signal.SendMessage, request.data["request_id"])
    raw = LiveFixture.assert_send_evidence(ctx, signal, result, text)
    {result, raw}
  end

  def stored(ctx, id, mode \\ :public) do
    assert %{"id" => ^id} = complete(ctx, Signal.FetchMessage, %{"room_id" => ctx.room_id, "message_id" => id}, mode)
    assert {:ok, %{"ts" => ^id} = raw} = wire_result(:fetch_message)
    raw
  end

  defp edit(ctx, id, text, mode, fields \\ %{}) do
    complete(
      ctx,
      Signal.EditMessage,
      Map.merge(%{"room_id" => ctx.room_id, "message_id" => id, "text" => text}, fields),
      mode
    )
  end

  defp execute(ctx, definition, data) do
    Probes.execute(ctx, Probes.request(ctx, definition, data), :public)
  end

  def complete(ctx, definition, data, mode \\ :public) do
    request = Probes.request(ctx, definition, data)
    assert {:ok, signal} = Probes.execute(ctx, request, mode)
    assert signal.extensions["traceparent"] == request.extensions["traceparent"]
    LiveCase.assert_completion(ctx.client, signal, definition, request.data["request_id"])
  end

  def wire_result(operation) do
    assert_receive {:slack_live_wire, ^operation, _, result}
    result
  end

  def marker(ctx, detail), do: "Jido live #{ctx.run_id}: #{detail}"
  def keyboard(value), do: %{"rows" => [[%{"text" => "Verify Jido SDK", "value" => value}]]}

  def assert_button(message, value) do
    assert [
             %{
               "type" => "actions",
               "elements" => [%{"type" => "button", "action_id" => ^value, "value" => ^value}]
             }
           ] = message["blocks"]
  end
end
