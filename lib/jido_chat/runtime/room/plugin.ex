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
      member_limit: [type: :pos_integer, default: 20],
      identity_provider: [type: :atom, default: Jido.Chat.IdentityProvider.TrustedCaller],
      identity_options: [type: :map, default: %{}],
      authorizer: [type: :atom, default: Jido.Chat.Authorizer.Room],
      authorization_options: [type: :map, default: %{}]
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
         is_integer(opts[:member_limit]) and opts[:member_limit] > 0 and
         Jido.Chat.IdentityProvider.valid?(opts[:identity_provider]) and
         is_map(opts[:identity_options]) and
         Jido.Chat.Authorizer.valid?(opts[:authorizer]) and
         is_map(opts[:authorization_options]),
       do: :ok,
       else: {:error, :invalid_room_options}
  end

  @impl true
  def state_spec(_opts) do
    {:room,
     Jido.Joi.object(%{
       members: Zoi.list(Room.member_schema()),
       messages: Zoi.list(Jido.Joi.struct(Jido.Signal)),
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
    {_, room, _, _} = Resources.identity(runtime)

    case room_action(input.signal.type) do
      nil ->
        {:ok, nil}

      action ->
        with {:ok, source} <- identity_source(input.caller_context, room),
             {:ok, principal} <-
               Jido.Chat.IdentityProvider.resolve(opts[:identity_provider], source, %{
                 caller_context: input.caller_context,
                 signal: input.signal,
                 room: room,
                 options: opts[:identity_options]
               }),
             :ok <-
               Jido.Chat.Authorizer.authorize(
                 opts[:authorizer],
                 principal,
                 action,
                 %{type: :room, id: room},
                 %{
                   admin: opts[:admin],
                   members: input.plugin_state.members,
                   member: member(input.prepared_input),
                   signal: input.signal,
                   options: opts[:authorization_options]
                 }
               ) do
          actor = principal.agent_address || principal.id
          {:ok, %{actor: actor, principal: principal, room: room}}
        end
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
    {:ok, room} = Jido.agent_address(init.jido, init.agent_id, partition: init.partition)
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

  defp room_action("jido.chat.room.join"), do: :room_join
  defp room_action("jido.chat.room.leave"), do: :room_leave
  defp room_action("jido.chat.room.post"), do: :message_post
  defp room_action("jido.chat.room.check_member"), do: :member_check
  defp room_action(_type), do: nil

  defp member(input) when is_map(input), do: input["member"]
  defp member(_input), do: nil

  defp identity_source(caller_context, room) do
    case Map.get(caller_context, :identity_source) do
      nil -> source_from_actor(Map.get(caller_context, :actor), room)
      source -> validate_identity_source(source, room)
    end
  rescue
    _ -> {:error, :invalid_identity_source}
  end

  defp validate_identity_source(source, room) do
    source = Jido.Chat.IdentitySource.new(source)

    if is_nil(source.room_id) or source.room_id == room.id,
      do: {:ok, source},
      else: {:error, :identity_room_mismatch}
  end

  defp source_from_actor(%Jido.Chat.Principal{} = principal, room) do
    {:ok,
     Jido.Chat.IdentitySource.new(%{
       provider: "host",
       account_id: room.namespace,
       external_id: principal.id,
       room_id: room.id
     })}
  end

  defp source_from_actor(%Jido.Agent.Address{} = actor, room) do
    {:ok,
     Jido.Chat.IdentitySource.new(%{
       provider: "jido",
       account_id: actor.namespace,
       external_id: actor.id,
       room_id: room.id,
       metadata: %{"partition" => actor.partition}
     })}
  end

  defp source_from_actor(actor, room) when is_binary(actor) and actor != "" do
    {:ok,
     Jido.Chat.IdentitySource.new(%{
       provider: "host",
       account_id: room.namespace,
       external_id: actor,
       room_id: room.id
     })}
  end

  defp source_from_actor(_actor, _room), do: {:error, :identity_source_missing}
end
