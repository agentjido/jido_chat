defmodule Jido.Chat.Signal.LiveFixture do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias Jido.Chat
  alias Jido.Chat.LiveCase
  alias Jido.Chat.LiveCase.Probes
  alias Jido.Chat.Providers.Dependencies
  alias Jido.Chat.Signal
  alias Jido.Chat.Signal.Transport.{CliClient, JsonRpcClient}

  @receive_flag "RUN_LIVE_SIGNAL_RECEIVE_TESTS"

  def provider, do: "signal"
  def adapter, do: Signal.Adapter
  def legacy_flag, do: "RUN_LIVE_SIGNAL_TESTS"
  def features, do: []
  def native_operations, do: [:send_message, :send_file]

  @unsupported %{
    "P03" => "Signal has no HTML rendering",
    "P04" => "Signal has no stream operation",
    "P05" => "Signal has no draft preview",
    "P06" => "Signal has no send-and-edit stream",
    "P07" => "Signal has no draft coalescing",
    "P09" => "Signal supports local paths and inline bytes, with no reusable upload ID",
    "P10" => "Signal has no hosted attachment download",
    "P12" => "Signal has no edit or keyboard operation",
    "P13" => "Signal has no delete operation",
    "P14" => "Signal has no reaction operation",
    "P15" => "Signal has no conversation metadata query",
    "P16" => "Signal has no typing operation",
    "P17" => "Signal has no thread creation operation",
    "P18" => "Signal has no thread creation request to reject",
    "P20" => "Signal has no test fixture for a definite provider rejection",
    "A01" => "Signal has no fetch, edit, or delete operation",
    "A02" => "Signal has no identity, room metadata, typing, or direct-room lookup operation",
    "A03" => "Signal uses polling and has no webhook status operation",
    "A05" => "Signal has no rich draft Action",
    "A06" => "Signal has no send-and-edit stream Action",
    "A08" => "Signal has no draft Action for a Flow",
    "A09" => "Signal supports plain quotes and has no rich controls or edit",
    "A11" => "Signal has no reaction Actions",
    "A13" => "Signal sends inline attachments and has no media fetch or download",
    "A15" => "Signal has no poll Action",
    "A16" => "Signal has no thread or topic routing operation",
    "A17" => "Signal has no button interaction"
  }

  def cases do
    LiveCase.Baseline.register(
      [
        Probes.text_case(:api),
        spec("P02", "send a plain Signal quote", :public_quote, [:send_message]),
        spec("P08", "send exact inline file bytes to signal-cli", :file, [:send_file]),
        spec("P21", "receive a fresh Signal message through the polling Source", :receive_message, [],
          events: [Signal.MessageReceived],
          target: :receive,
          manual: @receive_flag,
          timeout: 110_000
        ),
        spec("A04", "send public text and a binary attachment", :text_and_file, [:send_message, :send_file]),
        spec("A07", "render finite text and send with the native Action", :native_send, [:send_message]),
        spec("A10", "send the exact quote through the native Action", :native_quote, [:send_message]),
        spec("A12", "send a native document with exact JSON bytes", :document, [:send_file]),
        spec("A14", "send a local file through the native Action", :local_file, [:send_file], target: :local_file)
      ] ++ Probes.local_cases(:api),
      @unsupported
    )
  end

  defp spec(id, name, body, operations, opts \\ []),
    do: LiveCase.spec(:api, id, name, {__MODULE__, body}, [operations: operations] ++ opts)

  def prepare(%{target: :none}, _run_id, _stop), do: {:ok, Probes.local_context(__MODULE__)}

  def prepare(spec, run_id, stop) do
    with {:ok, account} <- LiveCase.required_env("SIGNAL_ACCOUNT"),
         {:ok, backend, config} <- backend(),
         {:ok, room_id} <- LiveCase.required_env(target_env(spec.target)),
         :ok <- check_target(spec.target, backend),
         :ok <- ready(backend, config, stop) do
      client =
        Chat.Client.new!(adapter(),
          id: "signal-live",
          credentials: %{account: account},
          transport: __MODULE__.Transport,
          config: config ++ [live_backend: backend, live_stop: stop, live_observer: self()]
        )

      {:ok, %{profile: __MODULE__, client: client, room_id: room_id, opts: [], run_id: run_id}}
    end
  end

  defp target_env(:receive), do: "SIGNAL_TEST_SENDER"
  defp target_env(_), do: "SIGNAL_TEST_RECIPIENT"

  defp check_target(:local_file, JsonRpcClient), do: {:blocked, "use SIGNAL_TRANSPORT=cli for the local-file case"}
  defp check_target(_, _), do: :ok

  defp backend do
    case String.downcase(System.get_env("SIGNAL_TRANSPORT") || "cli") do
      "rpc" ->
        with {:ok, endpoint} <- LiveCase.required_env("SIGNAL_RPC_ENDPOINT"),
             :ok <- LiveCase.dependency(Dependencies.req()) do
          {:ok, JsonRpcClient,
           [endpoint: endpoint, req_options: [retry: false, redirect: false, receive_timeout: 12_000]]}
        end

      "cli" ->
        executable = System.get_env("SIGNAL_CLI_PATH") || "signal-cli"

        case System.find_executable(executable) do
          nil -> {:blocked, "signal-cli executable unavailable; set SIGNAL_CLI_PATH"}
          path -> {:ok, CliClient, [executable: path]}
        end

      _ ->
        {:blocked, "set SIGNAL_TRANSPORT to rpc or cli"}
    end
  end

  @compile {:no_warn_undefined, Req}
  defp ready(JsonRpcClient, config, stop) do
    result =
      LiveCase.provider_call(stop, :read, fn ->
        payload = %{"jsonrpc" => "2.0", "method" => "version", "id" => "jido-live-version"}

        Req.post(Keyword.merge(config[:req_options], url: config[:endpoint], json: payload))
      end)

    case result do
      {:ok, %{status: 200, body: %{"id" => "jido-live-version", "result" => _}}} ->
        :ok

      {:ok, %{status: 401}} ->
        LiveCase.halt(stop, :unauthorized)
        {:blocked, "Signal RPC returned HTTP 401"}

      {:ok, %{status: 429}} ->
        LiveCase.halt(stop, :rate_limited)
        {:blocked, "Signal RPC returned HTTP 429"}

      {:ok, %{status: status}} ->
        {:blocked, "Signal RPC did not answer the version request (HTTP #{status})"}

      {:error, %{__struct__: Req.TransportError, reason: :econnrefused}} ->
        {:blocked, "Signal RPC connection refused at SIGNAL_RPC_ENDPOINT"}

      {:error, _} ->
        {:blocked, "Signal RPC endpoint unavailable"}
    end
  end

  defp ready(CliClient, _config, _stop), do: :ok

  # Signal has no delete operation. Use a dedicated test conversation.
  def cleanup(_ctx, _id), do: :ok

  def public_quote(ctx), do: quote_message(ctx, :public)
  def native_quote(ctx), do: quote_message(ctx, :native)

  defp quote_message(ctx, mode) do
    marker = "Jido Signal live #{ctx.run_id} quote target"
    {parent, _} = send_case(ctx, Signal.SendMessage, %{"text" => marker}, mode)
    timestamp = String.to_integer(parent["id"])
    opts = [quote_author: ctx.client.credentials.account, quote_timestamp: timestamp, quote_message: marker]
    fields = %{"text" => marker <> " reply", "reply_to_id" => parent["id"]}
    {reply, wire} = send_case(%{ctx | opts: opts}, Signal.SendMessage, fields, mode)

    assert reply["id"] != parent["id"]
    assert reply["reply_to_id"] == parent["id"]
    assert Keyword.take(wire, Keyword.keys(opts)) |> Map.new() == Map.new(opts)
    assert wire[:reply_to_id] == parent["id"]
  end

  def file(ctx), do: send_file(ctx, "txt", "Jido Signal live #{ctx.run_id}\n", :public)

  def text_and_file(ctx) do
    Probes.send_text(ctx)
    send_file(ctx, "bin", <<0, 255, 10, 13, 65>>, :public)
  end

  def document(ctx) do
    document = %{"run" => ctx.run_id, "provider" => "signal"} |> Jason.encode!()
    send_file(ctx, "json", document, :native)
  end

  def local_file(ctx) do
    path = Path.join(System.tmp_dir!(), "jido-signal-#{ctx.run_id}.txt")
    File.write!(path, "Jido Signal local file #{ctx.run_id}\n", [:exclusive])
    LiveCase.on_cleanup(fn -> File.rm!(path) end)
    source = %{"kind" => "file", "client_id" => ctx.client.id, "id" => path}
    fields = %{"source" => source, "caption" => "Jido Signal live #{ctx.run_id} local file"}
    {_result, wire} = send_case(ctx, Signal.SendFile, fields, :native)
    assert wire[:attachments] == [path]
  end

  defp send_file(ctx, extension, bytes, mode) do
    name = "jido-signal-#{ctx.run_id}.#{extension}"
    encoded = Base.encode64(bytes)
    source = %{"content_base64" => encoded, "filename" => name}
    caption = "Jido Signal live #{ctx.run_id} attachment"
    fields = %{"source" => source, "caption" => caption}
    {_result, wire} = send_case(ctx, Signal.SendFile, fields, mode)
    assert [%{data: ^encoded, filename: ^name}] = wire[:attachments]
  end

  def native_send(ctx) do
    parts = ["Jido Signal live ", ctx.run_id, " final"]
    text = Chat.Adapter.render_stream(parts)
    assert text == Enum.join(parts)
    send_case(ctx, Signal.SendMessage, %{"text" => text}, :native)
  end

  defp send_case(ctx, definition, fields, mode) do
    request = Probes.request(ctx, definition, Map.put(fields, "room_id", ctx.room_id))
    assert {:ok, completed} = Probes.execute(ctx, request, mode)
    result = Probes.assert_sent(ctx, completed, definition, request.data["request_id"])
    {result, assert_send_evidence(ctx, completed, result, fields["text"] || fields["caption"])}
  end

  def assert_send_evidence(ctx, signal, result, text) do
    assert_receive {:signal_live_send, account, target, ^text, opts, {:ok, raw}}
    refute_received {:signal_live_send, _, _, _, _, _}
    assert account == ctx.client.credentials.account
    assert target == ctx.room_id
    assert result["text"] == text
    assert raw["timestamp"] && to_string(raw["timestamp"]) == result["id"]

    if ctx.client.config[:live_backend] == CliClient do
      # The CLI transport can fall back to a local time. Require a timestamp from signal-cli.
      assert result["id"] in String.split(raw["output"], "\n", trim: true)
      refute raw["output"] =~ "Failed to send"
    end

    if Map.has_key?(raw, "results") do
      assert [%{"type" => "SUCCESS"} | _] = receipts = raw["results"]
      assert Enum.all?(receipts, &(&1["type"] == "SUCCESS"))
    end

    assert {:ok, encoded} = Jido.Signal.Codec.serialize(signal)
    if account != ctx.room_id, do: refute(String.contains?(encoded, account))
    opts
  end

  def receive_message(ctx) do
    room = ctx.room_id
    type = Signal.MessageReceived.type()

    start_supervised!({
      Chat.Sensor,
      client: ctx.client,
      source: Signal.Source,
      emit: type,
      rooms: [room],
      dispatch: {:pid, target: self()},
      options: [receive_timeout_s: 1, max_messages: 10, poll_interval_ms: 500]
    })

    text = "Jido Signal inbound #{ctx.run_id}"
    IO.puts("SIGNAL_INPUT_READY Send the following text from the dedicated sender: #{text}")

    receive do
      {:signal, %{type: ^type, data: %{"room_id" => ^room, "text" => ^text, "sender" => %{"id" => ^room}}} = fact} ->
        refute get_in(fact.data, ["sender", "is_self"]) == true
        assert :ok = Chat.AdapterTestKit.Assertions.assert_json_round_trip(fact, Chat.catalog(ctx.client))
    after
      90_000 ->
        {:blocked, "no matching Signal message arrived from SIGNAL_TEST_SENDER"}
    end
  end

  defmodule Transport do
    @moduledoc false
    @behaviour Signal.Transport

    @impl true
    def send_message(account, room, text, opts) do
      stop = Keyword.fetch!(opts, :live_stop)

      LiveCase.provider_call(stop, :write, fn ->
        result = opts[:live_backend].send_message(account, room, text, opts)
        send(opts[:live_observer], {:signal_live_send, account, room, text, opts, result})
        if match?({:error, _}, result), do: flag_rejection(stop, result)
        result
      end)
    end

    @impl true
    def receive_messages(account, opts) do
      LiveCase.provider_call(opts[:live_stop], :read, fn -> opts[:live_backend].receive_messages(account, opts) end)
    end

    defp flag_rejection(stop, {:error, {:signal_rpc_error, 401, _}}), do: LiveCase.halt(stop, :unauthorized)
    defp flag_rejection(stop, {:error, {:signal_rpc_error, 429, _}}), do: LiveCase.halt(stop, :rate_limited)
    defp flag_rejection(stop, {:error, _}), do: LiveCase.halt(stop, :uncertain_write)
  end
end
