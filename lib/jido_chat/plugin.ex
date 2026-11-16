defmodule Jido.Chat.Plugin do
  @moduledoc """
  Chat connections for a Jido Agent.

  Declare immutable Client configuration, room scope, allowed command Actions,
  and an optional Sensor in a `chat` block. Plain Agent routes select Actions.
  The Agent owns each Sensor and the resolved Clients for its activation.

  Use `Jido.Chat.Plugin.Execute` as the terminal command route. It creates a
  Deliver directive; the Plugin runs the SDK Action after the turn commits and
  casts its result Signal back to the Agent. Result delivery is best effort.
  No process starts when the Chat SDK application starts.

  See `guides/agent_plugin.md` for the complete declaration and source contract.
  """
  require Logger
  alias Jido.Chat.Plugin.Patterns
  alias Spark.Dsl.Extension, as: E

  @client %Spark.Dsl.Entity{
    name: :client,
    target: Jido.Chat.Plugin.ClientSpec,
    args: [:adapter],
    schema: [
      adapter: [type: :atom, required: true],
      id: [type: :string, required: true],
      credentials: [type: :map, default: %{}],
      config: [type: :keyword_list, default: []],
      transport: [type: :atom]
    ]
  }
  @source %Spark.Dsl.Entity{
    name: :source,
    target: Jido.Chat.Plugin.SourceSpec,
    args: [:module],
    schema: [
      module: [type: :atom, required: true],
      options: [type: :keyword_list, default: []],
      emit: [type: {:or, [:string, {:list, :string}]}, required: true]
    ]
  }
  @connection %Spark.Dsl.Entity{
    name: :connection,
    target: Jido.Chat.Plugin.Connection,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      rooms: [type: :any, required: true],
      commands: [type: {:list, :atom}, default: [Jido.Chat.SendMessage]]
    ],
    entities: [client: [@client], source: [@source]],
    singleton_entity_keys: [:client, :source]
  }
  @section %Spark.Dsl.Section{
    name: :chat,
    schema: [
      identity_provider: [type: :atom],
      identity_options: [type: :map, default: %{}],
      authorizer: [type: :atom],
      authorization_options: [type: :map, default: %{}]
    ],
    entities: [@connection]
  }
  use Jido.Plugin, id: "jido.chat", sections: [@section]

  @impl Jido.Agent.Extension
  def verify(data, definition) do
    overlap =
      for {left, i} <- Enum.with_index(definition.routes),
          right <- Enum.drop(definition.routes, i + 1),
          Patterns.overlap?(left.path, right.path),
          do: {left.path, right.path}

    case overlap do
      [{left, right} | _] -> {:error, {:overlapping_chat_routes, left, right}}
      [] -> verify_sources(data.connections, definition.routes)
    end
  end

  defp verify_sources(connections, routes) do
    Enum.reduce_while(connections, :ok, fn connection, :ok ->
      types =
        case connection.source do
          nil -> []
          %{module: source, emit: emit} -> Enum.filter(source.signal_types(), &Patterns.selected?(&1, emit))
        end

      case Enum.find(types, fn type -> not Enum.any?(routes, &Jido.Signal.Router.matches?(type, &1.path)) end) do
        nil -> {:cont, :ok}
        type -> {:halt, {:error, {:unhandled_sensor_signal, connection.name, type}}}
      end
    end)
  end

  @impl Jido.Plugin
  def directives(_opts), do: [Jido.Chat.Plugin.Deliver]

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    connections = E.get_entities(dsl, [:chat])

    cond do
      connections != [] and config != %{} ->
        {:error, :use_chat_block_or_config}

      config != %{} ->
        {:ok, config}

      true ->
        {:ok,
         %{
           identity_provider: E.get_opt(dsl, [:chat], :identity_provider),
           identity_options: E.get_opt(dsl, [:chat], :identity_options, %{}),
           authorizer: E.get_opt(dsl, [:chat], :authorizer),
           authorization_options: E.get_opt(dsl, [:chat], :authorization_options, %{}),
           connections:
             Enum.map(connections, fn connection ->
               %{
                 name: connection.name,
                 rooms: connection.rooms,
                 commands: connection.commands,
                 client:
                   if(connection.client,
                     do:
                       Map.take(connection.client, [
                         :adapter,
                         :id,
                         :credentials,
                         :config,
                         :transport
                       ])
                   ),
                 source:
                   if(connection.source,
                     do: Map.take(connection.source, [:module, :options, :emit])
                   )
               }
             end)
         }}
    end
  end

  @impl Jido.Agent.Extension
  def normalize(data) do
    with {:ok, value} <-
           Zoi.parse(
             Zoi.object(
               %{
                 identity_provider: Zoi.any() |> Zoi.default(nil),
                 identity_options: Zoi.map() |> Zoi.default(%{}),
                 authorizer: Zoi.any() |> Zoi.default(nil),
                 authorization_options: Zoi.map() |> Zoi.default(%{}),
                 connections:
                   Zoi.array(
                     Zoi.object(
                       %{
                         name: Zoi.atom(),
                         client: Zoi.map(),
                         commands:
                           Zoi.array(Zoi.atom())
                           |> Zoi.min(1)
                           |> Zoi.default([Jido.Chat.SendMessage]),
                         rooms: Zoi.any(),
                         source: Zoi.any() |> Zoi.default(nil)
                       },
                       unrecognized_keys: :error
                     )
                   )
                   |> Zoi.min(1)
               },
               unrecognized_keys: :error
             ),
             data
           ),
         true <- length(Enum.uniq_by(value.connections, & &1.name)) == length(value.connections),
         true <- Enum.all?(value.connections, &valid_connection?/1),
         true <- valid_access_config?(value) do
      {:ok, value}
    else
      _ -> {:error, :invalid_chat_config}
    end
  rescue
    _ -> {:error, :invalid_chat_config}
  end

  defp valid_connection?(connection) do
    rooms? =
      case connection.rooms do
        rooms when is_list(rooms) ->
          rooms != [] and Enum.all?(rooms, &valid_room?/1)

        _ ->
          false
      end

    source? =
      case connection.source do
        nil ->
          true

        %{module: source, options: options, emit: emit} = spec when map_size(spec) == 3 ->
          Jido.Chat.Sensor.valid_source?(source) and Keyword.keyword?(options) and
            Patterns.valid?(emit, source.signal_types())

        _ ->
          false
      end

    client? =
      case connection.client do
        %{adapter: adapter, id: id} = spec ->
          is_atom(adapter) and match?({:module, _}, Code.ensure_compiled(adapter)) and
            function_exported?(adapter, :invoke, 3) and is_binary(id) and id != "" and
            Map.keys(spec) -- [:adapter, :id, :credentials, :config, :transport] == []

        _ ->
          false
      end

    commands? =
      Enum.all?(connection.commands, fn action ->
        match?({:module, _}, Code.ensure_compiled(action)) and function_exported?(action, :signal_definition, 0)
      end)

    rooms? and source? and client? and commands?
  end

  defp valid_room?({:env, key}), do: is_binary(key) and key != ""
  defp valid_room?(room), do: is_binary(room) and room != ""

  defp valid_access_config?(config) do
    (is_nil(config.identity_provider) or Jido.Chat.IdentityProvider.valid?(config.identity_provider)) and
      is_map(config.identity_options) and
      (is_nil(config.authorizer) or Jido.Chat.Authorizer.valid?(config.authorizer)) and
      is_map(config.authorization_options)
  end

  @doc "Returns the resolved connections for one active Agent."
  @spec connections(pid()) :: [map()]
  def connections(server), do: Jido.Chat.Plugin.Runtime.connections(server)

  @doc "Returns process status and last observed provider input status by connection. Readiness does not prove provider connectivity."
  @spec status(pid()) :: %{optional(atom()) => map()}
  def status(server), do: GenServer.call({:global, {Jido.Chat.Plugin.Runtime, server}}, :status)

  @impl Jido.Plugin
  def child_spec(init) do
    init = %{init | agent_server: GenServer.whereis(init.agent_server)}
    access = resolve_access!(init.options)

    connections =
      Enum.map(init.options[:connections], fn connection ->
        spec = resolve!(connection.name, :client, connection.client)
        options = spec |> Map.delete(:adapter) |> Enum.reject(fn {_, value} -> is_nil(value) end)
        client = Jido.Chat.Client.new!(spec.adapter, options)
        rooms = resolve!(connection.name, :rooms, connection.rooms)

        if not Enum.all?(rooms, &(is_binary(&1) and &1 != "")),
          do: raise(ArgumentError, "Chat connection #{connection.name}: invalid rooms")

        validate_commands!(connection, client)
        Map.merge(connection, %{client: client, rooms: rooms})
      end)

    ids = Enum.map(connections, & &1.client.id)

    if length(Enum.uniq(ids)) != length(ids),
      do: raise(ArgumentError, "Chat Client IDs must be unique")

    sensors =
      for %{source: %{module: source} = spec} = connection <- connections do
        options = [
          client: connection.client,
          source: source,
          emit: spec.emit,
          options: resolve!(connection.name, :source_options, spec.options),
          status_target: {{:global, {Jido.Chat.Plugin.Runtime, init.agent_server}}, connection.name},
          rooms: connection.rooms,
          dispatch: {Jido.Chat.Plugin.Ingress, [server: init.agent_server, connection: connection.name]}
        ]

        Supervisor.child_spec(
          {Jido.Chat.Sensor, options},
          id: connection.name
        )
      end

    runtime =
      Supervisor.child_spec({Jido.Chat.Plugin.Runtime, {init.agent_server, connections, access}},
        id: {Jido.Chat.Plugin.Runtime, :connections}
      )

    children = [runtime | sensors]

    %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  @impl Jido.Plugin
  def await_ready(_runtime, _opts), do: :ok

  @impl Jido.Plugin
  def admit(runtime, input, _opts) do
    case Jido.Chat.Plugin.Runtime.access_from_runtime(runtime) do
      %{identity_provider: nil} ->
        {:ok, nil}

      _access ->
        case Jido.Chat.Plugin.Runtime.inbound_client(runtime, input.signal.source) do
          nil ->
            {:ok, nil}

          client_id ->
            with %{client_id: ^client_id, principal: caller_principal} <- input.caller_context[:chat],
                 {:ok, principal} <-
                   Jido.Chat.Plugin.Runtime.consume_identity(runtime, client_id, input.signal),
                 true <- principal === caller_principal do
              {:ok, %{principal: principal, authorization: :granted}}
            else
              false -> {:error, :identity_admission_mismatch}
              {:error, _reason} = error -> error
              _other -> {:error, :identity_admission_missing}
            end
        end
    end
  end

  @doc "Validates an incoming fact against a named connection and calls the Agent."
  @spec ingest(pid(), atom(), Jido.Signal.t()) :: term()
  # Use the Client fixed at activation. Do not trust caller-supplied Clients.
  def ingest(server, name, %Jido.Signal{} = signal) when is_map(signal.data) do
    connection = Enum.find(connections(server), &(&1.name == name))
    access = Jido.Chat.Plugin.Runtime.access(server)

    cond do
      is_nil(connection) ->
        {:error, :unknown_chat_connection}

      signal.source != connection.client.source ->
        {:error, :chat_scope_denied}

      signal.data["room_id"] not in connection.rooms ->
        {:error, :chat_scope_denied}

      not emitted?(connection, signal.type) ->
        {:error, :undeclared_sensor_signal}

      true ->
        with {:ok, signal} <-
               Jido.Chat.Signal.Policy.validate(Jido.Chat.catalog(connection.client), signal),
             true <- signal.data["room_id"] in connection.rooms,
             {:ok, principal} <- resolve_identity(access, connection, signal),
             :ok <- authorize_identity(access, principal, connection, signal),
             :ok <- register_admission(server, connection, signal, principal) do
          chat = %{
            connection: name,
            client_id: connection.client.id,
            adapter: connection.client.adapter
          }

          chat = if principal, do: Map.put(chat, :principal, principal), else: chat
          Jido.AgentServer.call(server, signal, context: %{chat: chat})
        else
          false -> {:error, :chat_scope_denied}
          error -> error
        end
    end
  end

  def ingest(_server, _name, _signal), do: {:error, :invalid_chat_signal}

  defp resolve_identity(%{identity_provider: nil}, _connection, _signal), do: {:ok, nil}

  defp resolve_identity(access, connection, signal) do
    with {:ok, source} <- Jido.Chat.IdentitySource.from_signal(connection.client, signal) do
      Jido.Chat.IdentityProvider.resolve(access.identity_provider, source, %{
        connection: connection.name,
        signal_type: signal.type,
        room_id: signal.data["room_id"],
        options: access.identity_options
      })
    end
  end

  defp authorize_identity(%{identity_provider: nil}, nil, _connection, _signal), do: :ok

  defp authorize_identity(access, principal, connection, signal) do
    Jido.Chat.Authorizer.authorize(
      access.authorizer,
      principal,
      ingress_action(signal.type),
      %{type: :room, id: signal.data["room_id"], client_id: connection.client.id},
      %{
        connection: connection.name,
        signal_type: signal.type,
        options: access.authorization_options
      }
    )
  end

  defp register_admission(server, connection, signal, nil) do
    GenServer.call(
      {:global, {Jido.Chat.Plugin.Runtime, server}},
      {:admit, connection.client.id, signal}
    )
  end

  defp register_admission(server, connection, signal, principal) do
    Jido.Chat.Plugin.Runtime.register_identity(server, connection.client.id, signal, principal)
  end

  defp ingress_action("jido.chat.message.received"), do: :message_receive
  defp ingress_action("jido.chat.message.updated"), do: :message_update_receive
  defp ingress_action("jido.chat.message.deleted"), do: :message_delete_receive
  defp ingress_action("jido.chat.reaction.added"), do: :reaction_add_receive
  defp ingress_action("jido.chat.reaction.removed"), do: :reaction_remove_receive
  defp ingress_action("jido.chat.action.received"), do: :action_receive
  defp ingress_action("jido.chat.slash_command.received"), do: :slash_command_receive
  defp ingress_action("jido.chat.modal.submitted"), do: :modal_submit_receive
  defp ingress_action("jido.chat.modal.closed"), do: :modal_close_receive
  defp ingress_action("jido.chat.options.requested"), do: :options_request_receive
  defp ingress_action(_type), do: :event_receive

  defp emitted?(%{source: nil, client: client}, type),
    do: Enum.any?(Jido.Chat.event_definitions(client), &(&1.type() == type))

  defp emitted?(%{source: %{module: source, emit: emit}}, type),
    do: type in source.signal_types() and Patterns.selected?(type, emit)

  defp resolve_access!(opts) do
    identity_provider = opts[:identity_provider] || Application.get_env(:jido_chat, :identity_provider)

    authorizer =
      opts[:authorizer] || Application.get_env(:jido_chat, :authorizer) ||
        if(identity_provider, do: Jido.Chat.Authorizer.DenyAll)

    identity_options =
      Application.get_env(:jido_chat, :identity_options, %{})
      |> Map.merge(opts[:identity_options] || %{})

    authorization_options =
      Application.get_env(:jido_chat, :authorization_options, %{})
      |> Map.merge(opts[:authorization_options] || %{})

    access = %{
      identity_provider: identity_provider,
      identity_options: identity_options,
      authorizer: authorizer,
      authorization_options: authorization_options
    }

    valid =
      (is_nil(identity_provider) and is_nil(authorizer)) or
        (Jido.Chat.IdentityProvider.valid?(identity_provider) and
           Jido.Chat.Authorizer.valid?(authorizer))

    if valid and is_map(identity_options) and is_map(authorization_options),
      do: access,
      else: raise(ArgumentError, "invalid Chat identity or authorization configuration")
  end

  @impl Jido.Plugin
  def dispatch(runtime, %Jido.Chat.Plugin.Deliver{signal: signal}, context, _opts) do
    {_, store, _, _} =
      Enum.find(Supervisor.which_children(runtime), fn {id, _, _, _} ->
        id == {Jido.Chat.Plugin.Runtime, :connections}
      end)

    connections = GenServer.call(store, :connections)
    connection = Enum.find(connections, &(&1.client.id == signal.data["client_id"]))

    outcome =
      cond do
        is_nil(connection) ->
          {:error, :unknown_chat_client}

        not Enum.any?(connection.commands, &(&1.signal_definition().type() == signal.type)) ->
          {:error, :chat_command_denied}

        true ->
          room =
            signal.data["room_id"] ||
              GenServer.call(
                store,
                {:interaction_room, connection.client.id, signal.data["interaction_id"]}
              )

          with true <- room in connection.rooms,
               true <-
                 Enum.any?(Jido.Chat.operations(connection.client), fn {definition, action} ->
                   definition.type() == signal.type and action in connection.commands
                 end),
               {:ok, signal} <-
                 Jido.Chat.Signal.Policy.validate(Jido.Chat.catalog(connection.client), signal) do
            # SDK Actions run only here, after the command-handling Turn commits.
            case Jido.Chat.execute(connection.client, signal) do
              {:ok, result} -> return_result(context, result)
              {:error, %Jido.Chat.Error{signal: result}} -> return_result(context, result)
              {:error, _} -> {:error, :chat_execution_failed}
            end
          else
            false -> {:error, :chat_scope_denied}
            error -> error
          end
      end

    case outcome do
      {:error, reason} = error when reason != :agent_unavailable ->
        reject(context, connections, signal, reason)
        error

      other ->
        other
    end
  end

  defp reject(context, connections, request, reason) do
    operations = Enum.flat_map(connections, &Jido.Chat.operations(&1.client))

    case Enum.find(operations, fn {definition, _} -> definition.type() == request.type end) do
      {_, action} ->
        failed = Module.concat(action, Failed)
        code = if reason == :chat_execution_failed, do: "provider_failure", else: "forbidden"
        outcome = if reason == :chat_execution_failed, do: "unknown", else: "not_attempted"

        data =
          Map.take(request.data, ["client_id", "request_id"])
          |> Map.merge(%{"operation" => request.type, "code" => code, "outcome" => outcome})

        case Jido.Chat.Signal.Policy.reply(failed, data, request,
               source: "urn:jido:chat:plugin",
               subject: request.subject
             ) do
          {:ok, signal} -> return_result(context, signal)
          {:error, _} -> :ok
        end

      nil ->
        :ok
    end
  end

  defp resolve!(name, field, value) do
    case Jido.Plugin.Config.resolve(value) do
      {:ok, resolved} ->
        resolved

      {:error, error} ->
        path = Enum.join([field | get_in(error, [Access.key(:details, %{}), :path]) || []], ".")
        raise ArgumentError, "Chat connection #{name}: cannot resolve #{path}"
    end
  end

  defp validate_commands!(connection, client) do
    for action <- connection.commands do
      type = action.signal_definition().type()

      supported? =
        Enum.any?(Jido.Chat.operations(client), fn {definition, candidate} ->
          candidate == action and definition.type() == type
        end)

      capability =
        case Jido.Chat.Operations.Definitions.lookup(type) do
          nil -> true
          {_, operation, _, _, _} -> client.adapter.capabilities()[operation] == :native
        end

      if not (supported? and capability),
        do: raise(ArgumentError, "Chat connection #{connection.name}: unsupported Action #{inspect(action)}")
    end
  end

  defp return_result(context, result) do
    case Jido.whereis_agent(context.jido, context.agent_id, partition: Map.get(context, :partition)) do
      server when is_pid(server) ->
        Jido.AgentServer.cast(server, result)
        Logger.info("Chat output: #{result.type}")
        :ok

      _ ->
        {:error, :agent_unavailable}
    end
  end
end
