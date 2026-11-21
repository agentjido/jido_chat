defmodule Jido.Chat.X.LiveFixture do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias __MODULE__.Transport
  alias Jido.Chat
  alias Jido.Chat.LiveCase
  alias Jido.Chat.LiveCase.Probes
  alias Jido.Chat.Providers.Dependencies
  alias Jido.Chat.Signal
  alias Jido.Chat.X.{Adapter, Transport.XdkClient}

  @write_flag "RUN_LIVE_X_SEND_TESTS"
  @finch __MODULE__.Finch
  @oauth_env [
    consumer_key: "X_CONSUMER_KEY",
    consumer_secret: "X_CONSUMER_SECRET",
    token: "X_ACCESS_TOKEN",
    token_secret: "X_ACCESS_TOKEN_SECRET"
  ]
  @event_fields ~w(id dm_conversation_id sender_id text)

  @compile {:no_warn_undefined, [Xdk, Xdk.Users, OAuther]}

  def provider, do: "x"
  def adapter, do: Adapter
  def legacy_flag, do: "RUN_LIVE_X_TESTS"
  def features, do: []
  def native_operations, do: [:send_message, :delete_message, :fetch_message, :fetch_messages, :open_dm]

  @unsupported %{
    "P02" => "X Chat has no reply or rich controls in DMs",
    "P03" => "X DMs have no HTML rendering",
    "P04" => "X Chat has no stream operation",
    "P05" => "X Chat has no draft preview",
    "P06" => "X Chat has no send-and-edit stream",
    "P07" => "X Chat has no draft coalescing",
    "P08" => "X Chat has no attachment send or download operation",
    "P09" => "X Chat has no upload-reference operation",
    "P10" => "X Chat has no image upload or download operation",
    "P12" => "X Chat has no edit or keyboard operation",
    "P14" => "X Chat has no reaction operation",
    "P15" => "X Chat has no room metadata operation",
    "P16" => "X Chat has no typing operation",
    "P17" => "X Chat addresses DM conversations and has no thread creation operation",
    "P18" => "X Chat has no thread creation request to reject",
    "P20" => "X Chat has no test fixture for a definite provider rejection",
    "P21" => "X requires a host-owned Account Activity webhook fixture for live inbound delivery",
    "A03" => "X Chat has no webhook status operation",
    "A04" => "X Chat has no file Action",
    "A05" => "X Chat has no rich draft Action",
    "A06" => "X Chat has no send-and-edit stream Action",
    "A08" => "X Chat has no draft Action for a Flow",
    "A09" => "X Chat has no rich controls, reply, or edit",
    "A10" => "X Chat has no reply metadata operation",
    "A11" => "X Chat has no reaction Actions",
    "A12" => "X Chat has no document Action",
    "A13" => "X Chat has no live media send or download operation",
    "A14" => "X Chat has no native file Action",
    "A15" => "X Chat has no poll Action",
    "A16" => "X Chat has no thread or topic operation",
    "A17" => "X DMs have no button interaction"
  }

  def cases do
    LiveCase.Baseline.register(
      [
        Probes.text_case(:api, target: :direct, write: @write_flag),
        writes("P13", "delete and verify absence of one owned test DM", :delete_owned, [
          :send_message,
          :fetch_message,
          :delete_message
        ]),
        writes("A01", "native Actions send, fetch and delete one owned test DM", :native_lifecycle, [
          :send_message,
          :fetch_message,
          :delete_message,
          :open_dm
        ]),
        LiveCase.spec(:api, "A02", "authenticate the X user through XDK", {__MODULE__, :identity}, target: :identity),
        writes("A07", "render finite text and send with the native Action", :native_send, [:send_message])
      ] ++ Probes.local_cases(:api),
      @unsupported
    )
  end

  defp writes(id, name, body, operations),
    do: LiveCase.spec(:api, id, name, {__MODULE__, body}, target: :direct, operations: operations, write: @write_flag)

  def prepare(%{target: :none}, _run_id, _stop), do: {:ok, Probes.local_context(__MODULE__)}

  def prepare(spec, run_id, stop) do
    with {:ok, room_id} <- target(spec.target),
         :ok <- LiveCase.dependency(Dependencies.check(xdk_elixir: Xdk.Users)),
         {:ok, oauth_opts} <- oauth_options() do
      start_supervised!({Finch, name: @finch})

      xdk =
        Xdk.new(
          base_url: "https://api.x.com",
          finch: @finch,
          auth: {:oauth1, OAuther.credentials(oauth_opts)},
          request_opts: [pool_timeout: 5_000, receive_timeout: 10_000]
        )

      client =
        Chat.Client.new!(adapter(),
          id: "x-live",
          transport: __MODULE__.Transport,
          config: [xdk_client: xdk, live_stop: stop, live_observer: self(), dm_event_fields: @event_fields]
        )

      {:ok, %{profile: __MODULE__, client: client, room_id: room_id, opts: [], run_id: run_id, stop: stop}}
    end
  end

  defp target(:identity), do: {:ok, nil}

  defp target(:direct) do
    with {:ok, room_id} <- LiveCase.required_env("X_TEST_RECIPIENT_ID") do
      if Regex.match?(~r/^[0-9]+$/, room_id),
        do: {:ok, room_id},
        else: {:blocked, "set X_TEST_RECIPIENT_ID to a numeric X user ID"}
    end
  end

  defp oauth_options do
    Enum.reduce_while(@oauth_env, {:ok, []}, fn {key, name}, {:ok, options} ->
      case LiveCase.required_env(name) do
        {:ok, value} -> {:cont, {:ok, [{key, value} | options]}}
        {:blocked, _} = blocked -> {:halt, blocked}
      end
    end)
  end

  def identity(ctx) do
    with {:ok, id} <- authenticated_user(ctx) do
      assert Regex.match?(~r/^[0-9]+$/, id)
    end
  end

  defp authenticated_user(ctx) do
    result = LiveCase.provider_call(ctx.stop, :read, fn -> Xdk.Users.get_me(ctx.client.config[:xdk_client]) end)

    case result do
      {:ok, %{"data" => %{"id" => id}}} when is_binary(id) and id != "" ->
        {:ok, id}

      {:error, %{status: status}} when status in [401, 403, 429] ->
        Transport.note_stop(ctx.stop, :read, result)
        {:blocked, "X OAuth identity returned HTTP #{status}"}

      {:error, %{status: status}} ->
        {:blocked, "X identity endpoint returned HTTP #{status}"}

      {:error, _} ->
        {:blocked, "X identity endpoint unavailable"}

      _ ->
        flunk("X identity response has no user ID")
    end
  end

  # Only the lifecycle probes delete, after a read verifies the exact test DM and owner.
  def cleanup(_ctx, _id), do: :ok

  def assert_send_evidence(ctx, signal, result, text) do
    assert_receive {:x_live_send, recipient, ^text, {:ok, %{"data" => raw}}}
    refute_received {:x_live_send, _, _, _}
    assert recipient == ctx.room_id
    assert raw["dm_event_id"] == result["id"]
    assert raw["dm_conversation_id"] == result["thread_id"]
    assert is_binary(result["thread_id"]) and result["thread_id"] != ""
    assert {:ok, encoded} = Jido.Signal.Codec.serialize(signal)
    refute String.contains?(encoded, System.fetch_env!("X_ACCESS_TOKEN"))
    refute String.contains?(encoded, System.fetch_env!("X_ACCESS_TOKEN_SECRET"))
    result
  end

  def native_send(ctx) do
    parts = ["Jido X live ", ctx.run_id, " final"]
    text = Chat.Adapter.render_stream(parts)
    assert text == Enum.join(parts)
    send_dm(ctx, text, :native)
  end

  def delete_owned(ctx), do: lifecycle(ctx, :public)
  def native_lifecycle(ctx), do: lifecycle(ctx, :native)

  defp lifecycle(ctx, mode) do
    with {:ok, owner} <- authenticated_user(ctx) do
      room = ctx.room_id
      assert {:ok, %{"id" => ^room, "kind" => "direct"}} = action(ctx, Signal.OpenDm, %{"user_id" => room}, mode)

      text = "Jido X live #{ctx.run_id} deletion proof"
      %{"id" => id, "thread_id" => conversation} = send_dm(ctx, text, mode)
      fields = %{"room_id" => "conversation:" <> conversation, "message_id" => id}

      with {:ok, message} <- fetch(ctx, fields, mode) do
        assert owned_message?(message, id, conversation, owner, text)
        assert {:ok, %{"acknowledged" => true}} = action(ctx, Signal.DeleteMessage, fields, mode)
        assert_receive {:x_live_delete, ^id, :ok}
        assert absent?(ctx, fields, mode)
      end
    end
  end

  @doc false
  def owned_message?(message, id, conversation, owner, text) do
    match?(
      %{"id" => ^id, "thread_id" => ^conversation, "sender" => %{"id" => ^owner}, "text" => ^text},
      message
    )
  end

  defp fetch(ctx, %{"message_id" => id} = fields, mode) do
    outcome = action(ctx, Signal.FetchMessage, fields, mode)

    case fetch_evidence(id) do
      {:error, %{status: status}} when status in [402, 403] ->
        {:blocked, "X account cannot read the newly sent test DM (HTTP #{status})"}

      {:ok, %{"data" => %{"id" => ^id}}} ->
        assert {:ok, %{"id" => ^id}} = outcome
        outcome

      _ ->
        flunk("X did not return the exact test DM")
    end
  end

  defp absent?(ctx, %{"message_id" => id} = fields, mode) do
    assert {:error, %Chat.Error{}} = action(ctx, Signal.FetchMessage, fields, mode)

    case fetch_evidence(id) do
      {:error, %{status: 404}} ->
        true

      {:ok, %{"errors" => errors} = raw} ->
        is_nil(raw["data"]) and
          Enum.any?(
            errors,
            &(&1["type"] == "https://api.x.com/2/problems/resource-not-found" and &1["resource_id"] == id)
          )

      _ ->
        false
    end
  end

  defp fetch_evidence(id) do
    assert_receive {:x_live_fetch, ^id, result}
    result
  end

  defp send_dm(ctx, text, mode) do
    request = Probes.request(ctx, Signal.SendMessage, %{"room_id" => ctx.room_id, "text" => text})
    assert {:ok, completed} = Probes.execute(ctx, request, mode)
    result = Probes.assert_sent(ctx, completed, Signal.SendMessage, request.data["request_id"])
    assert_send_evidence(ctx, completed, result, text)
  end

  defp action(ctx, definition, fields, mode) do
    request = Probes.request(ctx, definition, fields)

    with {:ok, completed} <- Probes.execute(ctx, request, mode) do
      assert completed.extensions["traceparent"] == request.extensions["traceparent"]
      {:ok, LiveCase.assert_completion(ctx.client, completed, definition, request.data["request_id"])}
    end
  end

  defmodule Transport do
    @moduledoc false
    @behaviour Jido.Chat.X.Transport

    @impl true
    def send_dm(recipient, text, opts) do
      observed(opts, :write, {:x_live_send, recipient, text}, fn -> XdkClient.send_dm(recipient, text, opts) end)
    end

    @impl true
    def fetch_dm_event(id, opts) do
      observed(opts, :read, {:x_live_fetch, id}, fn -> XdkClient.fetch_dm_event(id, opts) end)
    end

    @impl true
    def delete_dm_event(id, opts) do
      observed(opts, :write, {:x_live_delete, id}, fn -> XdkClient.delete_dm_event(id, opts) end)
    end

    @impl true
    def send_conversation_message(_, _, _), do: {:error, {:not_attempted, :outside_test_scope}}

    @impl true
    def fetch_conversation_messages(_, _), do: {:error, {:not_attempted, :outside_test_scope}}

    defp observed(opts, kind, witness, call) do
      stop = Keyword.fetch!(opts, :live_stop)

      LiveCase.provider_call(stop, kind, fn ->
        result = call.()
        note_stop(stop, kind, result)
        send(Keyword.fetch!(opts, :live_observer), Tuple.insert_at(witness, tuple_size(witness), result))
        result
      end)
    end

    def note_stop(stop, _, {:error, %{status: 401}}), do: LiveCase.halt(stop, :unauthorized)
    def note_stop(stop, _, {:error, %{status: 429}}), do: LiveCase.halt(stop, :rate_limited)
    def note_stop(stop, :write, {:error, _}), do: LiveCase.halt(stop, :uncertain_write)
    def note_stop(_, _, _), do: :ok
  end
end
