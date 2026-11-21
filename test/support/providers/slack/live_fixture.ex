defmodule Jido.Chat.Slack.LiveFixture do
  @moduledoc false
  import ExUnit.Assertions
  alias __MODULE__.Request
  alias Jido.Chat
  alias Jido.Chat.LiveCase
  alias Jido.Chat.LiveCase.Probes
  alias Jido.Chat.Providers.Dependencies
  alias Jido.Chat.Signal
  alias Jido.Chat.Slack.{LiveAPI, LiveFiles, LiveInput}

  def provider, do: "slack"
  def adapter, do: Chat.Slack.Adapter
  def legacy_flag, do: "RUN_LIVE_SLACK_TESTS"
  def features, do: []

  def native_operations do
    ~w(stream_text send_message send_file edit_message delete_message fetch_metadata fetch_thread
       fetch_message get_user fetch_subject get_thread_participants mark_as_read download_file
       add_reaction remove_reaction post_ephemeral open_modal load_options fetch_messages list_threads open_dm)a
  end

  @unsupported %{
    "P03" => "Slack Chat has no HTML rendering",
    "P05" => "Slack Chat has no draft preview",
    "P06" => "Slack Chat streams with one final send",
    "P07" => "Slack Chat has no preview coalescing settings",
    "P09" => "Slack Chat uploads inline bytes and cannot reuse a provider file reference",
    "P16" => "Slack Chat has no Web API typing operation",
    "P18" => "Slack threads start with a reply and have no separate creation operation",
    "A03" => "Slack Chat has no webhook status operation",
    "A05" => "Slack Chat has no rich draft Action",
    "A06" => "Slack Chat has no send-and-edit stream Action",
    "A08" => "Slack Chat has no explicit draft Action for a Flow",
    "A14" => "Slack SendFile accepts inline bytes only",
    "A15" => "Slack Chat has no native poll Action"
  }

  def cases do
    LiveCase.Baseline.register(baseline_cases(), @unsupported) ++
      [
        input("A17-LIVE", "real Slack button delivery through Socket Mode", :live_interaction, Signal.ActionReceived,
          operations: [:send_message, :edit_message, :fetch_message],
          target: :socket,
          manual: "RUN_LIVE_SLACK_UI",
          timeout: 210_000
        ),
        api("S01", "resolve the configured direct recipient", :direct, [:open_dm], target: :direct)
      ]
  end

  defp baseline_cases do
    [
      Probes.text_case(:api),
      api("P02", "rich reply with a Slack Block Kit button", :rich_reply, [:send_message, :fetch_message]),
      Probes.stream_case(:api),
      file("P08", "inline file and exact download bytes", :file),
      file("P10", "image upload, download and event normalization", :image, events: [Signal.MessageReceived]),
      api("P12", "edit and verify Slack removed the buttons", :edit_keyboard, [
        :send_message,
        :edit_message,
        :fetch_message
      ]),
      api("P13", "delete, verify absence and check repeated deletion", :delete, [
        :send_message,
        :delete_message,
        :fetch_message
      ]),
      api("P14", "observe added and removed reactions", :reactions, [
        :send_message,
        :fetch_message,
        :add_reaction,
        :remove_reaction
      ]),
      api("P15", "compare Slack room metadata and trace", :metadata, [:fetch_metadata]),
      api("P17", "reply in a thread and discover its root in history", :thread, [
        :send_message,
        :fetch_thread,
        :list_threads
      ]),
      api("P20", "reject an invalid Block Kit button at Slack", :reject_send, [:send_message]),
      input("P21", "receive a fresh test message through Socket Mode", :receive_message, Signal.MessageReceived,
        operations: [:send_message],
        target: :socket
      ),
      api("A01", "native Actions send, fetch, edit and delete", :lifecycle, [
        :send_message,
        :fetch_message,
        :edit_message,
        :delete_message
      ]),
      api("A02", "bot identity and current room", :identity, [:fetch_metadata, :get_user]),
      file("A04", "public text and exact binary file round trip", :text_and_file,
        operations: [:send_message, :send_file, :download_file]
      ),
      api("A07", "finite render and one native send", :render_and_send, [:send_message]),
      api("A09", "native rich controls, reply, edit and finite render", :rich_and_reply, [
        :send_message,
        :edit_message,
        :fetch_message
      ]),
      api("A10", "native reply routes to the real Slack message", :reply, [:send_message]),
      api("A11", "native reaction Actions and stored state", :native_reactions, [
        :send_message,
        :fetch_message,
        :add_reaction,
        :remove_reaction
      ]),
      file("A12", "native file Actions verify document metadata and exact JSON", :document),
      file("A13", "native image and video uploads and media normalization", :native_media,
        events: [Signal.MessageReceived]
      ),
      api("A16", "native threaded send addresses the Slack root", :native_thread, [:send_message]),
      input(
        "A17",
        "live send and edit with a replayed Slack button action",
        :replayed_interaction,
        Signal.ActionReceived,
        operations: [:send_message, :edit_message, :fetch_message]
      )
    ] ++ Probes.local_cases(:api)
  end

  defp api(id, name, body, operations, opts \\ []),
    do: LiveCase.spec(:api, id, name, {LiveAPI, body}, [operations: operations] ++ opts)

  defp input(id, name, body, event, opts),
    do: LiveCase.spec(:api, id, name, {LiveInput, body}, [events: [event]] ++ opts)

  defp file(id, name, body, opts \\ []),
    do:
      LiveCase.spec(:api, id, name, {LiveFiles, body}, Keyword.put_new(opts, :operations, [:send_file, :download_file]))

  def prepare(%{target: :none}, _run_id, _stop), do: {:ok, Probes.local_context(__MODULE__)}

  def prepare(spec, run_id, stop) do
    with {:ok, token} <- LiveCase.required_env("SLACK_BOT_TOKEN"),
         {:ok, room_id} <- LiveCase.required_env("SLACK_TEST_CHANNEL_ID"),
         :ok <- identifier(room_id, ~r/^[CG][A-Z0-9]+$/, "SLACK_TEST_CHANNEL_ID"),
         :ok <- LiveCase.dependency(Dependencies.req()),
         {:ok, user_id} <- test_user(spec.target),
         {:ok, socket} <- socket_credentials(spec.target) do
      client =
        Chat.Client.new!(adapter(),
          id: "slack-live",
          credentials: Map.put(socket, :bot_token, token),
          transport: __MODULE__.Transport,
          config: [live_stop: stop, live_observer: self(), req: __MODULE__.Request]
        )

      {:ok,
       %{profile: __MODULE__, client: client, room_id: room_id, user_id: user_id, opts: [], run_id: run_id, stop: stop}}
    end
  end

  defp socket_credentials(:socket) do
    with {:ok, token} <- LiveCase.required_env("SLACK_APP_TOKEN"),
         :ok <- LiveCase.dependency(Dependencies.slack_socket()),
         do: {:ok, %{app_token: token}}
  end

  defp socket_credentials(_), do: {:ok, %{}}

  defp test_user(:direct) do
    with {:ok, id} <- LiveCase.required_env("SLACK_TEST_USER_ID"),
         :ok <- identifier(id, ~r/^[UW][A-Z0-9]+$/, "SLACK_TEST_USER_ID"),
         do: {:ok, id}
  end

  defp test_user(_), do: {:ok, nil}

  defp identifier(id, format, name) do
    if Regex.match?(format, id), do: :ok, else: {:blocked, "set #{name} to a Slack ID"}
  end

  def cleanup(ctx, id) do
    LiveCase.on_cleanup({:slack_message, id}, fn ->
      request_id = "cleanup:#{ctx.run_id}"

      assert {:ok, signal} =
               Chat.delete_message(ctx.client, ctx.room_id, id,
                 request_id: request_id,
                 options: [live_cleanup?: true]
               )

      assert %{"acknowledged" => true} =
               LiveCase.assert_completion(ctx.client, signal, Chat.Signal.DeleteMessage, request_id)
    end)
  end

  def forget_cleanup(id), do: LiveCase.on_cleanup({:slack_message, id}, fn -> :ok end)

  def assert_send_evidence(ctx, signal, result, text) do
    assert result["text"] == text
    assert_receive {:slack_live_wire, :send_message, [room, ^text], {:ok, raw}}
    assert room == ctx.room_id
    assert raw["ts"] == result["id"]
    assert get_in(raw, ["message", "text"]) == text
    refute_received {:slack_live_wire, :send_message, _, _}
    assert {:ok, encoded} = Jido.Signal.Codec.serialize(signal)
    refute encoded =~ ctx.client.credentials.bot_token
    raw
  end

  def api_request(ctx, method, form, kind \\ :read) do
    LiveCase.provider_call(ctx.stop, kind, fn ->
      case Request.request(
             method: :post,
             url: "https://slack.com/api/" <> method,
             headers: [{"authorization", "Bearer " <> ctx.client.credentials.bot_token}],
             form: form,
             redirect: false
           ) do
        {:ok, %{status: 200, body: %{"ok" => true} = body}} -> {:ok, body}
        {:ok, %{status: 401}} -> {:error, {:rejected, :unauthorized, %{}}}
        {:ok, %{status: 429}} -> {:error, {:rejected, :rate_limited, %{}}}
        _ -> {:error, :slack_api_request_failed}
      end
    end)
  end

  defmodule Request do
    @moduledoc false
    @compile {:no_warn_undefined, Req}
    def request(opts), do: Req.request(Keyword.merge(opts, retry: false, receive_timeout: 12_000))
  end

  defmodule Transport do
    @moduledoc false
    alias Jido.Chat.Slack.Transport.ReqClient

    for {name, arity, kind} <- [
          {:send_message, 4, :write},
          {:send_file, 4, :write},
          {:edit_message, 5, :write},
          {:delete_message, 4, :write},
          {:fetch_message, 4, :read},
          {:fetch_metadata, 3, :read},
          {:fetch_thread, 4, :read},
          {:list_threads, 3, :read},
          {:get_user, 3, :read},
          {:add_reaction, 5, :write},
          {:remove_reaction, 5, :write},
          {:open_dm, 3, :write},
          {:download_file, 3, :read}
        ] do
      [token | args] = Macro.generate_arguments(arity, __MODULE__)

      def unquote(name)(unquote_splicing([token | args])) do
        {opts, data} = List.pop_at([unquote_splicing(args)], -1)
        kind = request_kind(unquote(name), unquote(kind), opts)

        observe(opts, unquote(name), data, kind, fn ->
          apply(ReqClient, unquote(name), [unquote(token) | data] ++ [opts])
        end)
      end
    end

    defp request_kind(:delete_message, :write, opts) do
      if opts[:live_cleanup?] == true, do: :cleanup, else: :write
    end

    defp request_kind(_operation, kind, _opts), do: kind

    defp observe(opts, operation, data, kind, call) do
      stop = Keyword.fetch!(opts, :live_stop)

      LiveCase.provider_call(stop, kind, fn ->
        result = call.()
        note_rejection(stop, kind, result)
        if operation == :download_file, do: note_download_failure(result)
        send(Keyword.fetch!(opts, :live_observer), {:slack_live_wire, operation, data, result})
        result
      end)
    end

    defp note_rejection(stop, _, {:error, {:http_error, 401, _}}), do: LiveCase.halt(stop, :unauthorized)
    defp note_rejection(stop, _, {:error, {:http_error, 429, _}}), do: LiveCase.halt(stop, :rate_limited)

    defp note_rejection(stop, _, {:error, {:slack_api_error, code, _}})
         when code in ["invalid_auth", "not_authed", "token_revoked"],
         do: LiveCase.halt(stop, :unauthorized)

    defp note_rejection(stop, kind, {:error, {:http_error, status, _}}) when kind != :read and status >= 500,
      do: LiveCase.halt(stop, :uncertain_write)

    defp note_rejection(stop, kind, {:error, %{__struct__: Req.TransportError}}) when kind != :read,
      do: LiveCase.halt(stop, :uncertain_write)

    defp note_rejection(_, _, _), do: :ok

    defp note_download_failure({:error, {:http_error, status, _}}),
      do: IO.puts("Slack file download failed with HTTP #{status}")

    defp note_download_failure({:error, :unexpected_html_response}),
      do: IO.puts("Slack file download returned an HTML page")

    defp note_download_failure({:error, %{__struct__: Req.TransportError, reason: reason}}) when is_atom(reason),
      do: IO.puts("Slack file download transport failed (#{reason})")

    defp note_download_failure(_), do: :ok
  end
end
