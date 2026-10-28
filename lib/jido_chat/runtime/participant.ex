defmodule Jido.Chat.Runtime.Participant do
  @moduledoc """
  Composes local room observation and optional replies into a Jido Agent.

  The host must join the participant Ref to the room before Agent activation.
  """

  alias Jido.Chat.Runtime.Directives.Receive
  alias Jido.Chat.Runtime.{Resources, Room}
  alias Jido.Chat.Runtime.Signal.Room.{CheckMember, Message}
  alias Spark.Dsl.Extension, as: DSL

  @section %Spark.Dsl.Section{
    name: :participant,
    schema: [
      room: [type: :any, required: true],
      respond: [type: {:in, [:mentioned, :never]}, default: :mentioned],
      reply_text: [type: :string, default: "Received."],
      history_limit: [type: :pos_integer, default: 100]
    ]
  }
  use Jido.Plugin, id: "jido.chat.runtime.participant", sections: [@section]

  @impl true
  def lower(dsl, config) do
    defaults =
      Map.new(@section.schema, fn {key, schema} ->
        {key, DSL.get_opt(dsl, [:participant], key, Keyword.get(schema, :default))}
      end)

    {:ok, Map.merge(defaults, config)}
  end

  @impl true
  def validate_options(opts) do
    room = opts[:room]
    valid_room = (is_binary(room) and room != "") or match?({:ok, _}, Jido.Agent.Ref.validate(room))

    if valid_room and opts[:respond] in [:mentioned, :never] and
         is_binary(opts[:reply_text]) and opts[:reply_text] != "" and
         is_integer(opts[:history_limit]) and opts[:history_limit] > 0,
       do: :ok,
       else: {:error, :invalid_participant_options}
  end

  @impl true
  def state_spec(_opts) do
    {:participation,
     Zoi.object(%{received: Zoi.list(Zoi.struct(Jido.Signal))})
     |> Zoi.default(%{received: []})}
  end

  @impl true
  def directives(_opts), do: [Receive]

  @impl true
  def prepare(%{signal: %{type: "jido.chat.room.message"} = signal}, _opts),
    do: Message.validate_data(signal.data)

  def prepare(_input, _opts), do: {:ok, nil}

  @impl true
  def admit(runtime, %{signal: %{type: "jido.chat.room.message"}} = input, opts) do
    {jido, member, room, _} = Resources.identity(runtime)

    if input.prepared_input["room"] == room do
      with {:ok, agent, _} <-
             Jido.call(jido, room, CheckMember.new!(%{"member" => member}), context: %{actor: member}),
           true <- member in agent.state.room.members,
           true <-
             Enum.any?(agent.state.room.messages, fn message ->
               message.id == input.signal.id and message.data == input.prepared_input
             end) do
        {:ok, %{member: member, room: room, respond: opts[:respond], reply_text: opts[:reply_text]}}
      else
        false -> {:error, :not_member_or_retained_message}
        error -> error
      end
    else
      {:error, :room_mismatch}
    end
  end

  def admit(_runtime, _input, _opts), do: {:ok, nil}

  @impl true
  def reduce(input, opts) do
    received = for %Receive{message: message} <- input.directives, do: message
    {:ok, %{received: Enum.take(input.plugin_state.received ++ received, -opts[:history_limit])}}
  end

  @impl true
  def child_spec(init) do
    room = Resources.room_ref(init)
    options = [bus: Room.bus_name(room), path: "jido.chat.room.message"]
    resource = Jido.Plugin.Bus.Client.child_spec(%{init | options: options})
    Resources.child_spec(init, resource, room)
  end

  @impl true
  def await_ready(runtime, opts) do
    {_, _, _, client} = Resources.identity(runtime)
    Jido.Plugin.Bus.Client.await_ready(client, opts)
  end

  @impl true
  def dispatch(_runtime, %Receive{reply: nil}, _context, _opts), do: :ok

  def dispatch(runtime, %Receive{reply: reply}, context, _opts) do
    {_, member, room, _} = Resources.identity(runtime)

    case Jido.call(context.jido, room, reply, context: %{actor: member}) do
      {:ok, _, _} -> :ok
      error -> error
    end
  end
end
