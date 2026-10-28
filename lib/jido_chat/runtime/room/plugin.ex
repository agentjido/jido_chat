defmodule Jido.Chat.Runtime.Room.Plugin do
  @moduledoc "Owns room membership, bounded working history, and one Jido Bus."

  alias Jido.Chat.Runtime.Directives.Publish
  alias Jido.Chat.Runtime.{Resources, Room}
  alias Jido.Chat.Runtime.Signal.Room, as: Signals
  alias Spark.Dsl.Extension, as: DSL

  @section %Spark.Dsl.Section{
    name: :room,
    schema: [
      admin: [type: :any, default: "operator"],
      history_limit: [type: :pos_integer, default: 100],
      member_limit: [type: :pos_integer, default: 20]
    ]
  }
  use Jido.Plugin, id: "jido.chat.runtime.room", sections: [@section]

  @impl true
  def lower(dsl, config) do
    defaults =
      Map.new(@section.schema, fn {key, schema} ->
        {key, DSL.get_opt(dsl, [:room], key, Keyword.fetch!(schema, :default))}
      end)

    {:ok, Map.merge(defaults, config)}
  end

  @impl true
  def validate_options(opts) do
    if match?({:ok, _}, Zoi.parse(Room.member_schema(), opts[:admin])) and
         is_integer(opts[:history_limit]) and opts[:history_limit] > 0 and
         is_integer(opts[:member_limit]) and opts[:member_limit] > 0,
       do: :ok,
       else: {:error, :invalid_room_options}
  end

  @impl true
  def state_spec(_opts) do
    {:room,
     Zoi.object(%{
       members: Zoi.list(Room.member_schema()),
       messages: Zoi.list(Zoi.struct(Jido.Signal)),
       sequence: Zoi.integer()
     })
     |> Zoi.default(%{members: [], messages: [], sequence: 0})}
  end

  @impl true
  def directives(_opts), do: [Publish]

  @impl true
  def prepare(input, _opts) do
    case input.signal.type do
      "jido.chat.room.join" -> Signals.Join.validate_data(input.signal.data)
      "jido.chat.room.leave" -> Signals.Leave.validate_data(input.signal.data)
      "jido.chat.room.post" -> Signals.Post.validate_data(input.signal.data)
      "jido.chat.room.check_member" -> Signals.CheckMember.validate_data(input.signal.data)
      _ -> {:ok, nil}
    end
  end

  @impl true
  def admit(runtime, input, opts) do
    actor = Map.get(input.caller_context, :actor)

    allowed =
      case input.signal.type do
        "jido.chat.room.join" -> actor == opts[:admin]
        "jido.chat.room.leave" -> actor == opts[:admin] or actor == input.prepared_input["member"]
        "jido.chat.room.post" -> actor in input.plugin_state.members
        "jido.chat.room.check_member" -> actor == input.prepared_input["member"]
        _ -> true
      end

    if allowed do
      {_, room, _, _} = Resources.identity(runtime)
      {:ok, %{actor: actor, room: room}}
    else
      {:error, :not_authorized}
    end
  end

  @impl true
  def reduce(input, opts) do
    state = input.plugin_state

    case input.signal.type do
      "jido.chat.room.join" ->
        members = Enum.uniq(state.members ++ [input.prepared_input["member"]])

        if length(members) <= opts[:member_limit],
          do: {:ok, %{state | members: members}},
          else: {:error, :room_full}

      "jido.chat.room.leave" ->
        {:ok, %{state | members: List.delete(state.members, input.prepared_input["member"])}}

      _ ->
        messages = for %Publish{message: message} <- input.directives, do: message
        history = Enum.take(state.messages ++ messages, -opts[:history_limit])
        {:ok, %{state | messages: history, sequence: state.sequence + length(messages)}}
    end
  end

  @impl true
  def child_spec(init) do
    {:ok, room} = Jido.agent_ref(init.jido, init.agent_id, partition: init.partition)
    options = [name: Room.bus_name(room), jido: init.jido, max_log_size: init.options[:history_limit]]
    resource = Jido.Plugin.Bus.Manager.child_spec(%{init | options: options})
    Resources.child_spec(init, resource, room)
  end

  @impl true
  def dispatch(runtime, %Publish{message: message}, _context, _opts) do
    {_, _, _, bus} = Resources.identity(runtime)

    case Jido.Signal.Bus.publish(bus, [message]) do
      {:ok, _} -> :ok
      error -> error
    end
  end
end
