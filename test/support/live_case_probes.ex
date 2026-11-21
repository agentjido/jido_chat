defmodule Jido.Chat.LiveCase.Probes do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Chat
  alias Jido.Chat.LiveCase
  alias Chat.Signal

  @trace "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

  def text_case(group) do
    LiveCase.spec(group, "P01", "portable text completion", {__MODULE__, :send_text},
      operations: [:send_message]
    )
  end

  def stream_case(group) do
    LiveCase.spec(group, "P04", "consume stream once and verify final text", {__MODULE__, :stream_text},
      operations: [:stream_text]
    )
  end

  def local_cases(group) do
    [
      LiveCase.spec(group, "P11", "capability discovery", {__MODULE__, :capabilities}, target: :none),
      LiveCase.spec(group, "P19", "invalid public input", {__MODULE__, :invalid_input}, target: :none)
    ]
  end

  def local_context(profile) do
    %{
      profile: profile,
      client: Chat.Client.new!(profile.adapter(), id: "#{profile.provider()}-local", transport: __MODULE__.Offline)
    }
  end

  def capabilities(ctx) do
    expected =
      Map.new(Chat.Operations.Definitions.all(), fn {_, {_, operation, _, _, _}} ->
        {operation, if(operation in ctx.profile.native_operations(), do: :native, else: :unsupported)}
      end)

    assert Chat.capabilities(ctx.client) == expected
  end

  def invalid_input(ctx) do
    room_id = "1"
    owner = self()
    stream = Stream.map(["invalid"], fn text -> send(owner, {:unexpected_input, text}) end)
    assert {:error, %Chat.Errors.Contract{}} = Chat.send_text(ctx.client, room_id, "invalid", unknown_option: true)
    assert {:error, %Chat.Errors.Contract{}} = Chat.edit_message(ctx.client, room_id, "1", "invalid", thread_id: "2")
    assert {:error, %Chat.Errors.Contract{}} = Chat.stream_text(ctx.client, room_id, stream, update_interval_ms: -1)
    ref = %{"client_id" => "different-client", "kind" => "media", "id" => "invalid-reference"}
    assert {:error, %Chat.Errors.Contract{code: :context_mismatch}} = Chat.download_file(ctx.client, ref)
    refute_received {:unexpected_input, _}
  end

  def send_text(%{client: client, room_id: room_id, run_id: run_id, profile: profile} = ctx) do
    text = "Jido live #{run_id}: Literal **plain text**."
    request_id = "live:#{run_id}:text"
    opts = request_options(request_id)
    assert {:ok, signal} = Chat.send_text(client, room_id, text, ctx.opts ++ opts)
    result = assert_sent(ctx, signal, Chat.Signal.SendMessage, request_id)
    profile.assert_send_evidence(ctx, signal, result, text)
    :ok
  end

  def stream_text(%{client: client, room_id: room_id, run_id: run_id, profile: profile} = ctx) do
    test = self()
    request_id = "live:#{run_id}:stream"
    parts = ["Jido live #{run_id}", " final", " text"]

    stream =
      Stream.resource(
        fn ->
          send(test, {:live_stream_open, self()})
          parts
        end,
        fn
          [] -> {:halt, []}
          [part | rest] -> {[part], rest}
        end,
        fn _ -> send(test, :live_stream_closed) end
      )

    assert {:ok, signal} = Chat.stream_text(client, room_id, stream, ctx.opts ++ request_options(request_id))
    result = assert_sent(ctx, signal, Signal.StreamText, request_id)
    assert_receive {:live_stream_open, execution}
    assert_receive :live_stream_closed
    refute_received {:live_stream_open, _}
    refute Process.alive?(execution)
    profile.assert_send_evidence(ctx, signal, result, Enum.join(parts))
  end

  def request_options(request_id),
    do: [request_id: request_id, signal_options: [extensions: %{"traceparent" => @trace}]]

  def assert_sent(ctx, signal, definition, request_id) do
    if id = get_in(signal.data, ["result", "id"]), do: ctx.profile.cleanup(ctx, id)
    result = LiveCase.assert_completion(ctx.client, signal, definition, request_id)
    assert result["room_id"] == ctx.room_id
    assert is_binary(result["id"]) and result["id"] != ""
    assert signal.extensions["traceparent"] == @trace
    result
  end

  defmodule Offline do
    @moduledoc false
  end
end
