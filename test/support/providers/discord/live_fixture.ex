defmodule Jido.Chat.Discord.LiveFixture do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Chat
  alias Jido.Chat.Discord
  alias Jido.Chat.Discord.{LiveActions, LiveAPI, LiveFiles, LiveGateway, LiveHelpers, LiveUI}
  alias Jido.Chat.LiveCase
  alias Jido.Chat.LiveCase.Probes
  alias Jido.Chat.Providers.Dependencies

  def provider, do: "discord"
  def adapter, do: Discord.Adapter
  def legacy_flag, do: "RUN_LIVE_DISCORD_TESTS"
  def features, do: []

  def native_operations do
    ~w(send_message stream_text send_file edit_message delete_message start_typing fetch_metadata
       fetch_thread fetch_message download_file open_dm create_thread add_reaction remove_reaction
       fetch_messages list_threads)a
  end

  @unsupported %{
    "P03" => "Discord Chat does not accept HTML format",
    "P05" => "Discord Chat has no rich draft preview",
    "P06" => "Discord streams render to one send and have no edit delivery mode",
    "P07" => "Discord streams have no preview coalescing settings",
    "A03" => "Discord has no equivalent Chat webhook status operation",
    "A05" => "Discord Chat has no rich draft Action",
    "A06" => "Discord Chat has no send-and-edit stream Action",
    "A08" => "Discord Chat has no explicit draft Action for a Flow",
    "A15" => "Discord Chat has no registered poll Action"
  }

  def cases do
    baseline = LiveCase.Baseline.register(baseline_cases(), @unsupported)

    baseline ++
      [
        api("D01", "paginate messages backward and forward", :paginate, [:send_message, :fetch_messages]),
        api("D02", "list archived threads and traverse their cursor", :archived_thread, [:create_thread, :list_threads]),
        api("D03", "verify the configured direct recipient", :direct, [:open_dm], target: :direct),
        api("D04", "send to the configured direct recipient", :direct_delivery, [:open_dm, :send_message],
          target: :direct
        ),
        interaction(:ui, "A17-LIVE", "real Discord button, modal and slash delivery", :interactions,
          target: :gateway,
          manual: "RUN_LIVE_DISCORD_UI",
          timeout: 600_000
        )
      ]
  end

  defp baseline_cases do
    [
      Probes.text_case(:api),
      api("P02", "rich reply with controls and message identity", :send_reply, [:send_message, :fetch_message]),
      Probes.stream_case(:api),
      file("P08", "inline file and exact download bytes", :inline),
      file("P09", "local file and provider reference reuse", :reuse),
      file("P10", "image delivery and normalized media", :image, events: [Chat.Signal.MessageReceived]),
      api("P12", "edit a message and clear controls", :edit_keyboard, [:send_message, :edit_message, :fetch_message]),
      api("P13", "delete, verify absence, and check repeated deletion", :delete, [
        :send_message,
        :delete_message,
        :fetch_message
      ]),
      api("P14", "add and remove reactions with stored-state evidence", :reactions, [
        :fetch_message,
        :send_message,
        :add_reaction,
        :remove_reaction
      ]),
      api("P15", "room metadata and trace", :metadata, [:fetch_metadata]),
      api("P16", "provider typing acknowledgment", :typing, [:start_typing]),
      api("P17", "parent and message threads, routing, and history", :thread, [
        :create_thread,
        :fetch_thread,
        :send_message,
        :fetch_message,
        :edit_message,
        :fetch_messages,
        :delete_message,
        :fetch_metadata,
        :start_typing
      ]),
      api("P18", "real thread rejection and failure signal", :reject_thread, [:create_thread]),
      api("P20", "real send rejection and failure signal", :reject_send, [:send_message]),
      LiveCase.spec(:gateway, "P21", "Gateway to Sensor to Agent reply", {LiveGateway, :reply},
        target: :gateway,
        operations: [:send_message, :fetch_message],
        events: [Chat.Signal.MessageReceived],
        timeout: 90_000
      ),
      action("A01", "native Actions send, edit, fetch and delete", :edit_delete, [
        :send_message,
        :edit_message,
        :fetch_message,
        :delete_message
      ]),
      api(
        "A02",
        "bot identity, room metadata and typing",
        :bot_identity,
        [:fetch_metadata, :start_typing]
      ),
      file("A04", "public text and exact binary file round trip", :text_and_file,
        operations: [:send_message, :send_file, :download_file]
      ),
      action("A07", "finite render and one final send", :render_and_send, [:send_message]),
      action(
        "A09",
        "rich embeds, controls, native reply, edit and render",
        :rich_and_reply,
        [:send_message, :edit_message, :fetch_message],
        extensions: [Discord.SendRichMessage]
      ),
      action("A10", "native reply and provider reference", :reply, [:send_message, :fetch_message]),
      action("A11", "native reaction Actions and stored state", :reactions, [
        :send_message,
        :fetch_message,
        :add_reaction,
        :remove_reaction
      ]),
      file("A12", "native document metadata and exact JSON", :native_document),
      file("A13", "image and video attachment normalization", :native_media, events: [Chat.Signal.MessageReceived]),
      file("A14", "native local file source bytes", :native_local),
      action(
        "A16",
        "native thread from a message with routed delivery",
        :message_thread,
        [
          :create_thread,
          :send_message,
          :fetch_message
        ],
        extensions: [Discord.StartMessageThread]
      ),
      interaction(:api, "A17", "live send and edit with replayed Discord interactions", :replayed, [])
    ] ++ Probes.local_cases(:api)
  end

  defp api(id, name, body, operations, opts \\ []),
    do: LiveCase.spec(:api, id, name, {LiveAPI, body}, [operations: operations] ++ opts)

  defp action(id, name, body, operations, opts \\ []),
    do: LiveCase.spec(:api, id, name, {LiveActions, body}, [operations: operations] ++ opts)

  defp interaction(group, id, name, body, opts) do
    LiveCase.spec(
      group,
      id,
      name,
      {LiveUI, body},
      [
        operations: [:send_message, :fetch_message, :edit_message],
        extensions: [Discord.SendRichMessage, Discord.RespondInteraction],
        events: [Chat.Signal.ActionReceived, Chat.Signal.ModalSubmitted, Chat.Signal.SlashCommandReceived]
      ] ++ opts
    )
  end

  defp file(id, name, body, opts \\ []),
    do:
      LiveCase.spec(:api, id, name, {LiveFiles, body}, Keyword.put_new(opts, :operations, [:send_file, :download_file]))

  def prepare(%{target: :none}, _run_id, _stop), do: {:ok, Probes.local_context(__MODULE__)}

  def prepare(spec, run_id, stop) do
    with {:ok, token} <- LiveCase.required_env("DISCORD_BOT_TOKEN"),
         {:ok, room} <- LiveCase.required_env("DISCORD_TEST_CHANNEL_ID"),
         :ok <- snowflake(room, "DISCORD_TEST_CHANNEL_ID"),
         {:ok, user_id} <- test_user(spec.target),
         :ok <- LiveCase.dependency(Dependencies.req()),
         :ok <- gateway_dependency(spec.target) do
      client =
        Chat.Client.new!(adapter(),
          id: "discord-live",
          credentials: %{token: token},
          config: [live_stop: stop, live_run_id: run_id, live_observer: self()],
          transport: __MODULE__.Transport
        )

      with {:ok, guild} <- confirm_room(client, room) do
        {:ok,
         %{
           client: client,
           room: room,
           room_id: room,
           guild: guild,
           user_id: user_id,
           opts: [],
           profile: __MODULE__,
           run_id: run_id
         }}
      end
    end
  end

  defp gateway_dependency(:gateway), do: LiveCase.dependency(Dependencies.discord_gateway())
  defp gateway_dependency(_), do: :ok

  defp test_user(:direct) do
    with {:ok, id} <- LiveCase.required_env("DISCORD_TEST_USER_ID"),
         :ok <- snowflake(id, "DISCORD_TEST_USER_ID"),
         do: {:ok, id}
  end

  defp test_user(_), do: {:ok, nil}

  defp snowflake(value, name) do
    if Regex.match?(~r/^[1-9][0-9]+$/, value), do: :ok, else: {:blocked, "set #{name} to a Discord ID"}
  end

  defp confirm_room(client, room) do
    with {:ok, %{"guild_id" => guild, "name" => "bridge"}} <- LiveHelpers.wire(client, :get, "/channels/" <> room),
         {:ok, %{"name" => "agentjido-test"}} <- LiveHelpers.wire(client, :get, "/guilds/" <> guild) do
      {:ok, guild}
    else
      _ ->
        {:blocked,
         LiveCase.failure_reason(client.config[:live_stop]) ||
           "Discord target must be the bridge channel on agentjido-test"}
    end
  end

  def cleanup(ctx, id), do: LiveHelpers.track_message(ctx.client, ctx.room_id, %{"id" => id})

  def assert_send_evidence(ctx, signal, result, text) do
    assert result["text"] == text
    path = "/channels/#{ctx.room_id}/messages"
    assert_receive {:discord_live_wire, :post, ^path, {:ok, %{"content" => ^text, "id" => id}}}
    assert id == result["id"]
    refute_received {:discord_live_wire, :post, ^path, _}

    fetched =
      LiveHelpers.execute(ctx.client, Chat.Signal.FetchMessage, %{
        "room_id" => ctx.room_id,
        "message_id" => result["id"]
      })

    assert fetched["text"] == text
    assert fetched["id"] == result["id"]
    assert fetched["room_id"] == ctx.room_id
    assert {:ok, encoded} = Jido.Signal.Codec.serialize(signal)
    refute encoded =~ ctx.client.credentials.token
  end

  defmodule Transport do
    @moduledoc false
    @behaviour Discord.Transport

    @impl true
    def call(token, method, path, body, opts) do
      stop = Keyword.fetch!(opts, :live_stop)
      kind = request_kind(method, opts)

      LiveCase.provider_call(stop, kind, fn ->
        result = Discord.Transport.REST.call(token, method, path, body, opts)

        if kind != :read and result in [{:error, :provider_failure}, {:error, :transport_failure}],
          do: LiveCase.halt(stop, :uncertain_write)

        if String.starts_with?(path, "/channels/"),
          do: send(Keyword.fetch!(opts, :live_observer), {:discord_live_wire, method, path, result})

        result
      end)
    end

    defp request_kind(method, opts) do
      cond do
        opts[:live_cleanup?] == true and method in [:get, :delete] -> :cleanup
        method == :get -> :read
        true -> :write
      end
    end
  end
end
