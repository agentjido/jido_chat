defmodule Jido.Chat.LiveCase.Probes do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Chat
  alias Jido.Chat.LiveCase

  def send_text(%{client: client, room_id: room_id, run_id: run_id, profile: profile} = ctx) do
    text = "Jido live #{run_id}: Literal **plain text**."
    request_id = "live:#{run_id}:text"
    trace = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    opts = [request_id: request_id, signal_options: [extensions: %{"traceparent" => trace}]]
    assert {:ok, signal} = Chat.send_text(client, room_id, text, ctx.opts ++ opts)
    if id = get_in(signal.data, ["result", "id"]), do: profile.cleanup(ctx, id)
    result = LiveCase.assert_completion(client, signal, Chat.Signal.SendMessage, request_id)
    assert result["room_id"] == room_id
    assert result["text"] == text
    assert signal.extensions["traceparent"] == trace
    profile.assert_send_evidence(ctx, signal, result, text)
    :ok
  end
end
