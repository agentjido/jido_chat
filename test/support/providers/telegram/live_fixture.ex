defmodule Jido.Chat.Telegram.LiveFixture do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 2]
  import Jido.Chat.LiveCase, only: [spec: 5]
  alias Jido.Chat
  alias Jido.Chat.LiveCase
  alias Jido.Chat.Telegram
  alias Jido.Chat.Telegram.{LiveActions, LivePublicAPI}
  alias __MODULE__.Tracker

  @native ~w(send_message stream_text send_file edit_message delete_message start_typing
             fetch_metadata download_file add_reaction remove_reaction open_dm create_thread)a
  @features ~w(replies rich_text keyboard draft_stream edit_stream local_file reuse_file image_file
               repeated_delete_rejection forum negative_destination)a

  def provider, do: "telegram"
  def adapter, do: Telegram.Adapter
  def legacy_flag, do: "RUN_LIVE_TELEGRAM_TESTS"
  def features, do: @features

  def expected_capabilities do
    Map.new(Chat.Operations.Definitions.all(), fn {_, {_, operation, _, _, _}} ->
      {operation, if(operation in @native, do: :native, else: :unsupported)}
    end)
  end

  def cases do
    LiveCase.Baseline.register(baseline_cases()) ++
      [
        action("A17-LIVE", "real Telegram callback delivery and answer", :a17_live, [:send_message, :edit_message],
          extensions: [Telegram.FetchUpdates, Telegram.AnswerCallbackQuery],
          events: [Chat.Signal.ActionReceived],
          features: [:keyboard],
          manual: "RUN_LIVE_TELEGRAM_UI_TESTS",
          timeout: 630_000
        )
      ]
  end

  defp baseline_cases do
    [
      LiveCase.Probes.text_case(:public_api),
      public("P02", "rich reply with keyboard", :p02, [:send_message], features: [:replies, :rich_text, :keyboard]),
      public("P03", "HTML text", :p03, [:send_message], features: [:rich_text]),
      public("P04", "lazy source and plain drafts", :p04, [:stream_text], features: [:draft_stream], target: :private),
      public("P05", "Markdown preview and final text", :p05, [:stream_text],
        features: [:draft_stream, :rich_text],
        target: :private
      ),
      public("P06", "send-and-edit stream", :p06, [:stream_text], features: [:edit_stream]),
      public("P07", "stream coalescing and final flush", :p07, [:stream_text], features: [:edit_stream]),
      public("P08", "inline file and download", :p08, [:send_file, :download_file]),
      public("P09", "local upload and reference reuse", :p09, [:send_file, :download_file],
        features: [:local_file, :reuse_file]
      ),
      public("P10", "image delivery and normalized media", :p10, [:send_file, :download_file],
        features: [:image_file],
        events: [Chat.Signal.MessageReceived]
      ),
      public("P11", "capability discovery", :p11, [], target: :none),
      public("P12", "edit and clear keyboard", :p12, [:send_message, :edit_message], features: [:keyboard]),
      public("P13", "delete and repeat delete", :p13, [:send_message, :delete_message],
        features: [:repeated_delete_rejection]
      ),
      public("P14", "add and remove reactions", :p14, [:send_message, :add_reaction, :remove_reaction]),
      public("P15", "room metadata and trace", :p15, [:fetch_metadata]),
      public("P16", "typing acknowledgment", :p16, [:start_typing]),
      public("P17", "topic creation and routing", :p17, [:create_thread, :send_message, :fetch_metadata, :start_typing],
        features: [:forum],
        target: :forum
      ),
      public("P18", "thread rejection", :p18, [:create_thread], features: [:negative_destination], target: :negative),
      public("P19", "invalid public input", :p19, [], target: :none),
      public("P20", "real send rejection", :p20, [:send_message], features: [:negative_destination], target: :negative),
      public("P21", "pull and normalize updates", :p21, [], extensions: [Telegram.FetchUpdates], target: :account),
      action("A01", "native send, edit, and delete", :a01, [:send_message, :edit_message, :delete_message]),
      action(
        "A02",
        "typing, metadata, direct addressing and bot identity",
        :a02,
        [:start_typing, :fetch_metadata, :open_dm],
        extensions: [Telegram.GetMe],
        target: :private
      ),
      action("A03", "read webhook status", :a03, [], extensions: [Telegram.GetWebhookInfo], target: :account),
      action("A04", "public text and file byte round trip", :a04, [:send_message, :send_file, :download_file]),
      action("A05", "rich draft stream", :a05, [:stream_text], features: [:draft_stream, :rich_text], target: :private),
      action("A06", "explicit send-and-edit stream", :a06, [:stream_text], features: [:edit_stream]),
      action("A07", "finite render and final send", :a07, [:send_message]),
      action("A08", "explicit drafts in a Flow", :a08, [:send_message],
        extensions: [Telegram.SendDraft],
        target: :private
      ),
      action("A09", "rich send, reply, edit and finite render", :a09, [:send_message, :edit_message],
        features: [:rich_text, :replies]
      ),
      action("A10", "actual reply metadata", :a10, [:send_message], features: [:replies]),
      action("A11", "native reaction Actions", :a11, [:send_message, :add_reaction, :remove_reaction]),
      action("A12", "document metadata and exact JSON bytes", :a12, [:download_file],
        extensions: [Telegram.SendDocument, Telegram.GetFile]
      ),
      action("A13", "photo, sticker, animation, and video note", :a13, [:download_file],
        extensions: [Telegram.SendPhoto, Telegram.SendSticker, Telegram.SendAnimation, Telegram.SendVideoNote],
        events: [Chat.Signal.MessageReceived]
      ),
      action("A14", "native local file source", :a14, [:send_file, :download_file], features: [:local_file]),
      action("A15", "poll through Router and Dispatch", :a15, [], extensions: [Telegram.SendPoll]),
      action("A16", "topic routing or non-forum rejection", :a16, [:create_thread, :send_message],
        features: [:forum],
        target: :forum_or_private
      ),
      action("A17", "live send and edit with a replayed callback", :a17, [:send_message, :edit_message],
        extensions: [Telegram.FetchUpdates, Telegram.AnswerCallbackQuery],
        events: [Chat.Signal.ActionReceived],
        features: [:keyboard]
      )
    ]
  end

  defp public(id, name, body, operations, opts \\ []),
    do: spec(:public_api, id, name, {LivePublicAPI, body}, [operations: operations] ++ opts)

  defp action(id, name, body, operations, opts \\ []),
    do:
      spec(
        :actions,
        id,
        name,
        {LiveActions, body},
        [operations: operations] ++ Keyword.put_new(opts, :timeout, 210_000)
      )

  def prepare(%{target: :none} = spec, run_id, stop) do
    {:ok, context(spec, run_id, stop, "local-sentinel", %{room_id: "123", forum_id: nil, thread_id: nil})}
  end

  def prepare(spec, run_id, stop) do
    targets = %{
      room_id: env("TELEGRAM_TEST_CHAT_ID"),
      forum_id: env("TELEGRAM_TEST_FORUM_CHAT_ID"),
      thread_id: env("TELEGRAM_TEST_THREAD_ID")
    }

    with {:ok, token} <- required("TELEGRAM_BOT_TOKEN"),
         :ok <- dependency(),
         :ok <- validate_target(spec.target, targets),
         {:ok, callback_timeout} <- callback_timeout(spec.manual) do
      ctx = context(spec, run_id, stop, token, targets)
      {:ok, ctx |> Map.put(:callback_timeout_ms, callback_timeout) |> track()}
    end
  end

  defp context(spec, run_id, stop, token, targets) do
    client =
      Chat.Client.new!(adapter(),
        id: "telegram.live",
        credentials: %{token: token},
        config: [
          live_observer: self(),
          live_stop: stop,
          live_wire?: spec.target != :none,
          connect_timeout: 5_000,
          receive_timeout: 12_000
        ],
        transport: __MODULE__.Transport
      )

    opts = if targets.thread_id, do: [thread_id: targets.thread_id], else: []

    Map.merge(targets, %{
      client: client,
      profile: __MODULE__,
      run_id: run_id,
      nonce: run_id,
      opts: opts,
      label: "Jido public API #{run_id}",
      reaction: env("TELEGRAM_TEST_REACTION") || "👍",
      keep_messages?: spec.group == :public_api and LiveCase.enabled?("TELEGRAM_PUBLIC_API_KEEP_MESSAGES"),
      stop: stop
    })
  end

  defp dependency do
    case Chat.Providers.Dependencies.telegram() do
      :ok -> :ok
      {:error, {:not_attempted, {:missing_dependency, dep}}} -> {:blocked, "missing dependency #{dep}"}
    end
  end

  defp validate_target(target, _) when target in [:account, :negative], do: :ok

  defp validate_target(:forum, %{forum_id: id}) do
    if match_id?(id, ~r/^-[1-9]\d*$/), do: :ok, else: {:blocked, "set TELEGRAM_TEST_FORUM_CHAT_ID to a test forum"}
  end

  defp validate_target(:forum_or_private, %{forum_id: nil} = targets), do: validate_target(:private, targets)
  defp validate_target(:forum_or_private, targets), do: validate_target(:forum, targets)

  defp validate_target(:private, %{room_id: id}) do
    if match_id?(id, ~r/^[1-9]\d*$/), do: :ok, else: {:blocked, "TELEGRAM_TEST_CHAT_ID must be a private test chat"}
  end

  defp validate_target(:room, %{room_id: id}) do
    if match_id?(id, ~r/^-?[1-9]\d*$/), do: :ok, else: {:blocked, "set TELEGRAM_TEST_CHAT_ID to a test chat"}
  end

  defp match_id?(id, pattern), do: is_binary(id) and Regex.match?(pattern, id)

  defp callback_timeout(nil), do: {:ok, nil}

  defp callback_timeout(_manual) do
    case Integer.parse(env("TELEGRAM_CALLBACK_TIMEOUT_MS") || "180000") do
      {ms, ""} when ms in 1..600_000 -> {:ok, ms}
      _ -> {:blocked, "TELEGRAM_CALLBACK_TIMEOUT_MS must be between 1 and 600000"}
    end
  end

  defp required(name) do
    case env(name) do
      nil -> {:blocked, "set #{name}"}
      value -> {:ok, value}
    end
  end

  defp env(name) do
    case String.trim(System.get_env(name) || "") do
      "" -> nil
      value -> value
    end
  end

  def assert_send_evidence(ctx, signal, result, text) do
    {payload, raw} = LivePublicAPI.response("sendMessage")
    assert payload["text"] == text
    assert result["text"] == text
    assert result["id"] =~ ~r/^\d+$/
    assert to_string(field(raw, "message_id")) == result["id"]
    refute Map.has_key?(payload, "rich_message")
    refute_receive {:telegram_live_wire, _, _, _}
    assert {:ok, encoded} = Jido.Signal.Codec.serialize(signal)
    refute encoded =~ ctx.client.credentials.token
  end

  defp track(ctx) do
    {:ok, tracker} = Tracker.start()
    ctx = put_in(ctx.client.config, Keyword.put(ctx.client.config, :live_tracker, tracker))
    ctx = Map.put(ctx, :tracker, tracker)

    # Register before the first request. The tracker survives an ExUnit test timeout.
    on_exit({:telegram_live_tracker, tracker}, fn ->
      try do
        %{pending: pending, messages: messages} = Tracker.close(tracker)
        if pending > 0, do: LiveCase.halt(ctx.stop, :uncertain_write)

        unless ctx.keep_messages? do
          Enum.each(messages, fn {room, id} -> delete_fixture(ctx, room, id) end)
        end
      after
        Agent.stop(tracker)
      end
    end)

    ctx
  end

  def cleanup(%{keep_messages?: true}, _id), do: :ok

  def cleanup(%{tracker: tracker, room_id: room}, id) when is_binary(id),
    do: Tracker.record(tracker, {:created, {room, id}})

  def cleanup(ctx, id) when is_binary(id),
    do: on_exit({ctx.room_id, id}, fn -> delete_fixture(ctx, ctx.room_id, id) end)

  def forget_cleanup(%{tracker: tracker, room_id: room}, id), do: Tracker.record(tracker, {:deleted, {room, id}})
  def forget_cleanup(ctx, id), do: on_exit({ctx.room_id, id}, fn -> :ok end)

  defp delete_fixture(ctx, room, id) do
    if LiveCase.cleanup_allowed?(ctx.stop) do
      LiveCase.protect(fn ->
        request_id = "cleanup:#{id}"

        assert {:ok, completed} =
                 Chat.delete_message(ctx.client, room, id,
                   request_id: request_id,
                   timeout: 15_000,
                   options: [live_teardown?: true]
                 )

        assert LiveCase.assert_completion(ctx.client, completed, Chat.Signal.DeleteMessage, request_id) ==
                 %{"acknowledged" => true}
      end)
    else
      LiveCase.blocked("#{LiveCase.failure_reason(ctx.stop)}; check retained fixtures by the run marker")
    end
  end

  def field(nil, _key), do: nil

  def field(map, key) do
    Map.get(map, key) ||
      Enum.find_value(Map.to_list(map), fn {k, v} -> if is_atom(k) and Atom.to_string(k) == key, do: v end)
  end

  def fixture_path("photo.png.b64"), do: Path.expand("../../../../examples/providers/telegram/photo.png.b64", __DIR__)

  def fixture_path(filename),
    do: Path.expand("../../../jido_chat/providers/telegram/fixtures/#{filename}", __DIR__)

  defmodule Tracker do
    @moduledoc false

    def start, do: Agent.start(fn -> %{closed?: false, pending: 0, messages: MapSet.new()} end)

    def begin_write(tracker) do
      Agent.get_and_update(tracker, fn
        %{closed?: true} = state -> {:closed, state}
        state -> {:ok, %{state | pending: state.pending + 1}}
      end)
    catch
      :exit, {reason, _} when reason in [:noproc, :normal] -> :closed
    end

    def finish_write(tracker, effect) do
      Agent.update(tracker, fn state ->
        %{state | pending: state.pending - 1, messages: update_messages(state.messages, effect)}
      end)
    catch
      :exit, {reason, _} when reason in [:noproc, :normal] -> :ok
    end

    def close(tracker), do: Agent.get_and_update(tracker, &{&1, %{&1 | closed?: true}})

    def record(tracker, effect) do
      Agent.update(tracker, fn state ->
        %{state | messages: update_messages(state.messages, effect)}
      end)
    end

    defp update_messages(messages, {:created, key}), do: MapSet.put(messages, key)
    defp update_messages(messages, {:deleted, key}), do: MapSet.delete(messages, key)
    defp update_messages(messages, nil), do: messages
  end

  defmodule Transport do
    @moduledoc false
    @behaviour Telegram.Transport
    @read_methods ~w(getMe getChat getFile downloadFile getUpdates getWebhookInfo)
    @create_methods ~w(sendMessage sendRichMessage sendPhoto sendDocument sendSticker sendAnimation sendVideoNote sendPoll)

    @impl true
    def call(token, method, payload, opts) do
      stop = Keyword.fetch!(opts, :live_stop)

      result =
        cond do
          not Keyword.fetch!(opts, :live_wire?) ->
            {:error, {:not_attempted, :offline_sentinel}}

          LiveCase.halted?(stop) and not teardown_allowed?(stop, method, opts) ->
            {:error, {:not_attempted, :live_run_stopped}}

          teardown_allowed?(stop, method, opts) or method in @read_methods ->
            call_provider(stop, token, method, payload, opts)

          true ->
            track_write(stop, token, method, payload, opts)
        end

      observer = Keyword.fetch!(opts, :live_observer)
      send(observer, {:telegram_live_wire, method, payload, result})
      result
    end

    defp teardown_allowed?(stop, "deleteMessage", opts),
      do: Keyword.get(opts, :live_teardown?) == true and LiveCase.cleanup_allowed?(stop)

    defp teardown_allowed?(_, _, _), do: false

    defp track_write(stop, token, method, payload, opts) do
      tracker = Keyword.fetch!(opts, :live_tracker)

      case Tracker.begin_write(tracker) do
        :ok ->
          result = call_provider(stop, token, method, payload, opts)
          Tracker.finish_write(tracker, fixture_effect(method, payload, result))
          result

        :closed ->
          {:error, {:not_attempted, :live_run_stopped}}
      end
    end

    defp call_provider(stop, token, method, payload, opts) do
      result = Telegram.Transport.ExGramClient.call(token, method, payload, opts)
      observe_outcome(stop, method, Telegram.Operations.classify(result))
      result
    catch
      kind, reason ->
        if method not in @read_methods, do: LiveCase.halt(stop, :uncertain_write)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end

    defp fixture_effect(method, %{"chat_id" => room}, {:ok, raw})
         when method in @create_methods and is_map(raw) do
      case Jido.Chat.Telegram.LiveFixture.field(raw, "message_id") do
        id when is_integer(id) or is_binary(id) ->
          {:created, {to_string(room), to_string(id)}}

        _ ->
          nil
      end
    end

    defp fixture_effect("deleteMessage", %{"chat_id" => room, "message_id" => id}, {:ok, true}),
      do: {:deleted, {to_string(room), to_string(id)}}

    defp fixture_effect(_, _, _), do: nil

    defp observe_outcome(stop, _, {:error, {:rejected, reason, _}}) when reason in [:rate_limited, :unauthorized],
      do: LiveCase.halt(stop, reason)

    defp observe_outcome(_, _, {:error, {status, _}}) when status in [:not_attempted, :rejected], do: :ok
    defp observe_outcome(_, _, {:error, {:rejected, _, _}}), do: :ok
    defp observe_outcome(_, method, _) when method in @read_methods, do: :ok
    defp observe_outcome(stop, _, {:error, _}), do: LiveCase.halt(stop, :uncertain_write)
    defp observe_outcome(_, _, _), do: :ok
  end
end
