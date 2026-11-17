defmodule Jido.Chat.Runtime.Room.Plugin do
  @moduledoc "Owns room membership, bounded working history, and one Jido Bus."

  alias Jido.Chat.Runtime.{Bus, Resources, Room}
  alias Jido.Chat.Runtime.Directives.Publish
  alias Jido.Chat.Runtime.Signal.Room, as: Signals
  alias Spark.Dsl.Extension, as: DSL

  @section %Spark.Dsl.Section{
    name: :room,
    schema: [
      admin: [type: :any, default: "operator"],
      history_limit: [type: :pos_integer, default: 100],
      member_limit: [type: :pos_integer, default: 20],
      runtime: [type: :any, default: nil],
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
    if match?({:ok, _}, Jido.Joi.parse(Room.member_schema(), opts[:admin])) and
         is_integer(opts[:history_limit]) and opts[:history_limit] > 0 and
         is_integer(opts[:member_limit]) and opts[:member_limit] > 0 and
         valid_runtime?(opts[:runtime]) and
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
       members: Jido.Joi.list(Room.member_schema()),
       messages: Jido.Joi.list(Jido.Joi.struct(Jido.Signal)),
       sequence: Jido.Joi.integer()
     })
     |> Jido.Joi.default(%{members: [], messages: [], sequence: 0})}
  end

  @impl true
  def directives(_opts), do: [Publish]

  @impl true
  def prepare(input, _opts) do
    case input.signal.type do
      "jido.chat.room.join" -> Signals.Join.validate_data(input.signal.data)
      "jido.chat.room.leave" -> Signals.Leave.validate_data(input.signal.data)
      "jido.chat.room.post" -> Signals.Post.validate_data(input.signal.data)
      "jido.chat.room.reaction.add" -> Signals.AddReaction.validate_data(input.signal.data)
      "jido.chat.room.reaction.remove" -> Signals.RemoveReaction.validate_data(input.signal.data)
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
             actor = principal.agent_address || principal.id,
             {:ok, membership} <-
               authorization_membership(
                 opts[:runtime],
                 room.id,
                 input.plugin_state.members,
                 action,
                 actor,
                 member(input.prepared_input),
                 opts[:member_limit]
               ),
             :ok <-
               Jido.Chat.Authorizer.authorize(
                 opts[:authorizer],
                 principal,
                 action,
                 %{type: :room, id: room},
                 %{
                   admin: opts[:admin],
                   actor_active?: membership.actor_active?,
                   member: member(input.prepared_input),
                   member_active?: membership.member_active?,
                   members: input.plugin_state.members,
                   room_full?: membership.room_full?,
                   working_members: input.plugin_state.members,
                   signal: input.signal,
                   options: opts[:authorization_options]
                 }
               ),
             :ok <- room_capacity(action, membership, opts[:member_limit]) do
          {:ok,
           %{
             actor: actor,
             principal: principal,
             room: room,
             durable_runtime: opts[:runtime],
             member_active?: membership.member_active?,
             room_full?: membership.room_full?
           }}
        end
    end
  end

  @impl true
  def reduce(input, opts) do
    state = input.plugin_state

    case input.signal.type do
      "jido.chat.room.join" ->
        member = input.prepared_input["member"]
        members = Enum.uniq(state.members ++ [member])

        if length(members) <= opts[:member_limit],
          do: {:ok, %{state | members: members}},
          else: {:ok, state}

      "jido.chat.room.leave" ->
        {:ok, %{state | members: List.delete(state.members, input.prepared_input["member"])}}

      _ ->
        messages = for %Publish{message: message, retain: true} <- input.directives, do: message
        history = Enum.uniq_by(state.messages ++ messages, & &1.id) |> Enum.take(-opts[:history_limit])
        sequence = Enum.reduce(messages, state.sequence, &max(&1.data["sequence"] || 0, &2))
        {:ok, %{state | messages: history, sequence: sequence}}
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
  def dispatch(runtime, %Publish{message: message}, _context, opts) do
    {_, _, _, bus} = Resources.identity(runtime)

    case Jido.Signal.Bus.publish(bus, [message]) do
      {:ok, _} -> Bus.notify(opts[:runtime], message)
      error -> error
    end
  end

  @doc false
  def hydrate_state(definition, runtime, room_id) do
    definition = Jido.Agent.definition(definition)
    plugin = Enum.find(definition.plugins, &(&1.provider == __MODULE__))
    opts = plugin && plugin.data

    case opts && opts[:runtime] do
      nil ->
        {:ok, %{}}

      ^runtime ->
        with {:ok, room} <-
               Jido.Chat.Runtime.Room.Durable.hydrate(
                 runtime,
                 room_id,
                 opts[:member_limit],
                 opts[:history_limit]
               ),
             do: {:ok, %{room: room}}

      _other ->
        {:error, :room_runtime_mismatch}
    end
  rescue
    _ -> {:error, :invalid_room_definition}
  end

  @doc false
  def validate_durable_definition(definition, runtime) do
    definition = Jido.Agent.definition(definition)

    case Enum.filter(definition.plugins, &(&1.provider == __MODULE__)) do
      [%{data: %{runtime: ^runtime}}] -> :ok
      [_plugin] -> {:error, :room_runtime_mismatch}
      _plugins -> {:error, :one_room_plugin_required}
    end
  rescue
    _ -> {:error, :invalid_room_definition}
  end

  defp room_action("jido.chat.room.join"), do: :room_join
  defp room_action("jido.chat.room.leave"), do: :room_leave
  defp room_action("jido.chat.room.post"), do: :message_post
  defp room_action("jido.chat.room.reaction.add"), do: :reaction_add
  defp room_action("jido.chat.room.reaction.remove"), do: :reaction_remove
  defp room_action("jido.chat.room.check_member"), do: :member_check
  defp room_action(_type), do: nil

  defp member(input) when is_map(input), do: input["member"]
  defp member(_input), do: nil

  defp valid_runtime?(nil), do: true

  defp valid_runtime?(runtime),
    do: is_atom(runtime) and runtime not in [nil, true, false]

  defp authorization_membership(nil, _room_id, members, _action, actor, member, limit) do
    {:ok,
     %{
       actor_active?: actor in members,
       member_active?: member in members,
       room_full?: length(members) >= limit
     }}
  end

  defp authorization_membership(runtime, room_id, _members, action, actor, member, limit) do
    with {:ok, actor_active?} <- Jido.Chat.Runtime.Room.Durable.active_member?(runtime, room_id, actor),
         {:ok, member_active?} <- target_active?(runtime, room_id, actor, actor_active?, member),
         {:ok, room_full?} <- room_full?(runtime, room_id, action, limit) do
      {:ok,
       %{
         actor_active?: actor_active?,
         member_active?: member_active?,
         room_full?: room_full?
       }}
    end
  end

  defp target_active?(_runtime, _room_id, actor, actor_active?, actor), do: {:ok, actor_active?}
  defp target_active?(_runtime, _room_id, _actor, _actor_active?, nil), do: {:ok, false}

  defp target_active?(runtime, room_id, _actor, _actor_active?, member),
    do: Jido.Chat.Runtime.Room.Durable.active_member?(runtime, room_id, member)

  defp room_full?(runtime, room_id, :room_join, limit) do
    with {:ok, count} <- Jido.Chat.Runtime.Room.Durable.active_member_count(runtime, room_id, limit) do
      {:ok, count >= limit}
    end
  end

  defp room_full?(_runtime, _room_id, _action, _limit), do: {:ok, false}

  defp room_capacity(:room_join, membership, _limit) do
    if membership.member_active? or not membership.room_full?,
      do: :ok,
      else: {:error, :room_full}
  end

  defp room_capacity(_action, _membership, _limit), do: :ok

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
