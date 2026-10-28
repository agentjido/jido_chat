defmodule Jido.Chat.PluginFixture.Adapter do
  @moduledoc false
  @behaviour Jido.Chat.Adapter
  @doc false
  def channel_type, do: :mock

  @doc false
  def capabilities,
    do: %{
      send_message: :native,
      edit_message: :native,
      add_reaction: :native,
      remove_reaction: :native
    }

  @doc false
  def normalize(_client, _input, _opts), do: {:error, :not_used}

  @doc false
  def invoke(client, command, _opts) do
    send(client.config[:observer], {:mock_send, client.id, command})

    client.config[:result] ||
      if(
        command.type in ["jido.chat.command.add_reaction", "jido.chat.command.remove_reaction"],
        do: {:ok, %{"acknowledged" => true}},
        else:
          {:ok,
           %{
             "id" => "mock-reply",
             "room_id" => command.data["room_id"],
             "text" => command.data["text"]
           }}
      )
  end
end

defmodule Jido.Chat.PluginFixture.RoomChanged do
  @moduledoc false
  use Jido.Signal,
    type: "test.chat.room.changed",
    dataschema: "urn:test:chat:room:1",
    default_source: "urn:test:chat:fixture",
    schema:
      Zoi.map(
        %{
          "item_id" => Zoi.string(),
          "delivery_id" => Zoi.string(),
          "room_id" => Zoi.string() |> Zoi.to_upcase(),
          "metadata" => Zoi.map() |> Zoi.optional()
        },
        unrecognized_keys: :error
      )
end

defmodule Jido.Chat.PluginFixture.ProviderAdapter do
  @moduledoc false
  use Jido.Chat.Adapter
  defdelegate capabilities(), to: Jido.Chat.PluginFixture.Adapter
  defdelegate invoke(client, request, opts), to: Jido.Chat.PluginFixture.Adapter
  defdelegate normalize(client, input, opts), to: Jido.Chat.PluginFixture.Adapter
  @doc false
  def event_definitions, do: Jido.Chat.event_definitions() ++ [Jido.Chat.PluginFixture.RoomChanged]
end

defmodule Jido.Chat.PluginFixture.Reply do
  @moduledoc "Builds a fixed reply. Replace this Action with a Flow later."
  use Jido.Action,
    name: "spike_reply",
    schema: Zoi.map()

  def run(params, context) do
    sender = params["sender"] || %{}

    if sender["is_bot"] == true or sender["is_self"] == true or
         not Regex.match?(~r/^\/spike(?:\s|$)/u, params["text"] || "") do
      {:ok, context.agent_state}
    else
      reply(context)
    end
  end

  defp reply(context) do
    incoming = context.signal

    data = %{
      "client_id" => context.chat.client_id,
      "request_id" => incoming.data["item_id"] <> ":reply",
      "room_id" => incoming.data["room_id"],
      "reply_to_id" => incoming.data["message_id"],
      "text" => "Spike received your message.",
      "format" => "plain",
      "keyboard" => %{"rows" => [[%{"value" => "spike:verify", "text" => "Verify spike"}]]}
    }

    data =
      case incoming.data["thread_id"] do
        nil -> data
        thread_id -> Map.put(data, "thread_id", thread_id)
      end

    command =
      Jido.Chat.Signal.Policy.new!(Jido.Chat.Signal.SendMessage, data,
        source: "urn:jido:spike:telegram-agent",
        subject: incoming.subject
      )

    state =
      context.agent_state
      |> Map.update!(:replies, &(&1 + 1))
      |> Map.put(
        :pending,
        Map.put(
          Map.get(context.agent_state, :pending, %{}),
          data["client_id"] <> ":" <> data["request_id"],
          %{
            "client_id" => data["client_id"],
            "room_id" => data["room_id"],
            "message_id" => data["reply_to_id"]
          }
        )
      )

    {:ok, state, [Jido.Agent.Directive.emit(command)]}
  end
end

defmodule Jido.Chat.PluginFixture.EditReply do
  @moduledoc "Edits the bot reply when the human edits its source message."
  use Jido.Action, name: "spike_edit_reply", schema: Zoi.map()

  def run(params, context) do
    key = context.chat.client_id <> ":" <> params["room_id"] <> ":" <> params["message_id"]
    message_id = context.agent_state.messages[key]

    if message_id && String.starts_with?(params["text"] || "", "/spike") do
      command =
        Jido.Chat.Signal.Policy.new!(Jido.Chat.Signal.EditMessage, %{
          "client_id" => context.chat.client_id,
          "request_id" => params["item_id"] <> ":edit",
          "room_id" => params["room_id"],
          "message_id" => message_id,
          "text" => "Spike received your edit: " <> params["text"],
          "format" => "plain",
          "keyboard" => %{"rows" => [[%{"value" => "spike:verify", "text" => "Verify spike"}]]}
        })

      {:ok, context.agent_state, [Jido.Agent.Directive.emit(command)]}
    else
      {:ok, context.agent_state}
    end
  end
end

defmodule Jido.Chat.PluginFixture.React do
  @moduledoc "Mirrors a human thumbs-up with eyes on a known bot reply."
  use Jido.Action, name: "spike_react", schema: Zoi.map()

  def run(params, context) do
    known =
      Enum.any?(context.agent_state.messages, fn {key, id} ->
        String.starts_with?(key, context.chat.client_id <> ":" <> params["room_id"] <> ":") and
          id == params["message_id"]
      end)

    if params["reaction"] == "👍" and known do
      definition =
        if context.signal.type == "jido.chat.reaction.added",
          do: Jido.Chat.Signal.AddReaction,
          else: Jido.Chat.Signal.RemoveReaction

      command =
        definition.new!(%{
          "client_id" => context.chat.client_id,
          "request_id" => params["item_id"] <> ":reaction",
          "room_id" => params["room_id"],
          "message_id" => params["message_id"],
          "reaction" => "👀"
        })

      {:ok, context.agent_state, [Jido.Agent.Directive.emit(command)]}
    else
      {:ok, context.agent_state}
    end
  end
end

defmodule Jido.Chat.PluginFixture.RecordDelivery do
  @moduledoc false
  use Jido.Action,
    name: "spike_record_delivery",
    schema: Zoi.map()

  def run(_params, context) do
    state = context.agent_state
    request = context.signal.data["request_id"]

    {pending, remaining} =
      Map.pop(state.pending, context.signal.data["client_id"] <> ":" <> request)

    state = %{
      state
      | pending: remaining,
        last_delivery: context.signal.type,
        last_request: request,
        deliveries: Map.put(state.deliveries, request, context.signal.type)
    }

    state =
      if pending && context.signal.type == "jido.chat.command.send_message.completed" do
        key = pending["client_id"] <> ":" <> pending["room_id"] <> ":" <> pending["message_id"]
        %{state | messages: Map.put(state.messages, key, context.signal.data["result"]["id"])}
      else
        state
      end

    {:ok, state}
  end
end

defmodule Jido.Chat.PluginFixture.Agent do
  @moduledoc "One V3 Agent. State and pending updates exist only in memory."
  use Jido.Agent, name: "telegram_spike", extensions: [Jido.Chat.Plugin]

  agent do
    schema Zoi.object(%{
             pending: Zoi.map() |> Zoi.default(%{}),
             messages: Zoi.map() |> Zoi.default(%{}),
             deliveries: Zoi.map() |> Zoi.default(%{}),
             replies: Zoi.integer() |> Zoi.default(0),
             last_delivery: Zoi.string() |> Zoi.default(""),
             last_request: Zoi.string() |> Zoi.default("")
           })
  end

  chat do
    connection :telegram do
      client Jido.Chat.PluginFixture.Adapter, id: "mock/support"
      rooms ["room-1"]
      commands [Jido.Chat.SendMessage, Jido.Chat.EditMessage, Jido.Chat.AddReaction, Jido.Chat.RemoveReaction]
    end
  end

  routes do
    route "jido.chat.message.received", Jido.Chat.PluginFixture.Reply, emits: ["jido.chat.command.send_message"]

    route "jido.chat.message.updated", Jido.Chat.PluginFixture.EditReply, emits: ["jido.chat.command.edit_message"]

    route "jido.chat.reaction.added", Jido.Chat.PluginFixture.React, emits: ["jido.chat.command.add_reaction"]

    route "jido.chat.reaction.removed", Jido.Chat.PluginFixture.React, emits: ["jido.chat.command.remove_reaction"]

    route "jido.chat.command.*", Jido.Chat.Plugin.Execute, emits: []
    route "jido.chat.telegram.command.*", Jido.Chat.Plugin.Execute, emits: []
    route "jido.chat.command.*.completed", Jido.Chat.PluginFixture.RecordDelivery, emits: []
    route "jido.chat.command.*.failed", Jido.Chat.PluginFixture.RecordDelivery, emits: []
    route "jido.chat.telegram.command.*.completed", Jido.Chat.PluginFixture.RecordDelivery, emits: []
    route "jido.chat.telegram.command.*.failed", Jido.Chat.PluginFixture.RecordDelivery, emits: []
  end
end

defmodule Jido.Chat.PluginFixture.Source do
  @moduledoc false
  @behaviour Jido.Chat.Sensor.Source
  @doc false
  def mode, do: :poll
  @doc false
  def poll_interval(options), do: Keyword.get(options, :interval, 1_000)
  @doc false
  def signal_types, do: ["jido.chat.message.received"]
  @doc false
  def read(_client, cursor, options), do: {:ok, Keyword.get(options, :signals, []), cursor}
end

defmodule Jido.Chat.PluginFixture.Accept do
  @moduledoc false
  use Jido.Action, name: "accept_chat_fact", schema: Zoi.map()
  def run(_params, context), do: {:ok, context.agent_state}
end

defmodule Jido.Chat.PluginFixture.SensorAgent do
  @moduledoc false
  use Jido.Agent, name: "sensor_agent", extensions: [Jido.Chat.Plugin]

  agent do
    schema Zoi.object(%{
             last_delivery: Zoi.string() |> Zoi.default(""),
             last_request: Zoi.string() |> Zoi.default(""),
             deliveries: Zoi.map() |> Zoi.default(%{})
           })
  end

  chat do
    connection :mock do
      client Jido.Chat.PluginFixture.Adapter, id: "mock/sensor"
      rooms ["room-1"]

      source Jido.Chat.PluginFixture.Source,
        emit: "jido.chat.message.received",
        options: [interval: 60_000]
    end
  end

  routes do
    route "jido.chat.message.received", Jido.Chat.PluginFixture.Accept, emits: []
  end
end

defmodule Jido.Chat.PluginFixture.PushSource do
  @moduledoc false
  use GenServer
  @behaviour Jido.Chat.Sensor.Source
  @doc false
  def mode, do: :push
  @doc false
  def signal_types, do: ["jido.chat.message.received"]
  @doc false
  def start_link(client, sensor, _options), do: GenServer.start_link(__MODULE__, {client, sensor})

  @doc false
  def init({client, sensor}) do
    send(client.config[:observer], {:push_worker, self()})
    {:ok, sensor}
  end

  @doc false
  def handle_call({:batch, signals}, _from, sensor),
    do: {:reply, Jido.Chat.Sensor.push(sensor, signals), sensor}
end
