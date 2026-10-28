defmodule Jido.Chat.Runtime.Bridge do
  @moduledoc """
  Maps provider rooms on one account Agent to local Runtime rooms.

  The host creates each room and joins the account Ref before account
  activation. The Bridge does not create rooms or provider accounts.
  """

  alias Jido.Chat.Runtime.Bridge.{Mapping, Worker}
  alias Jido.Chat.Runtime.Directives.{CompleteOutbound, RelayInbound, RelayOutbound}
  alias Jido.Chat.Runtime.Room
  alias Jido.Chat.Runtime.Signal.Room, as: RoomSignal
  alias Jido.Chat.Runtime.Storage
  alias Jido.Chat.Runtime.Storage.{Links, Outbox}
  alias Spark.Dsl.Extension, as: DSL

  @mapping %Spark.Dsl.Entity{
    name: :mapping,
    target: Mapping,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      external_room: [type: :string, required: true],
      room: [type: :any, required: true],
      direction: [type: {:in, [:inbound, :outbound, :both]}, default: :both]
    ]
  }
  @section %Spark.Dsl.Section{name: :bridge, entities: [@mapping]}

  use Jido.Plugin, id: "jido.chat.runtime.bridge", sections: [@section]

  @doc "Returns stored provider-work status for one account."
  @spec status(module(), String.t()) :: {:ok, map()} | {:error, term()}
  def status(runtime, account_id) do
    with {:ok, storage} <- storage(runtime),
         {:ok, work} <- storage_call(storage, Outbox, :list_work, [account_id, []]) do
      counts = Enum.frequencies_by(work, & &1.status)

      {:ok,
       %{
         account_id: account_id,
         total: length(work),
         pending: Map.get(counts, :pending, 0),
         claimed: Map.get(counts, :claimed, 0),
         submitted: Map.get(counts, :submitted, 0),
         completed: Map.get(counts, :completed, 0),
         failed: Map.get(counts, :failed, 0),
         unknown: Map.get(counts, :unknown, 0)
       }}
    end
  end

  @doc "Schedules pending provider work for one active account."
  @spec recover(module(), String.t()) :: :ok | {:error, term()}
  def recover(runtime, account_id) do
    name = {Worker, runtime, account_id}

    case :global.whereis_name(name) do
      pid when is_pid(pid) -> Worker.recover(pid)
      :undefined -> {:error, :connection_not_started}
    end
  end

  @doc "Returns a message link by local message ID."
  @spec link(module(), String.t(), String.t()) :: {:ok, map() | nil} | {:error, term()}
  def link(runtime, account_id, local_message_id) do
    with {:ok, storage} <- storage(runtime) do
      storage_call(storage, Links, :link_for_local, [account_id, local_message_id])
    end
  end

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    mappings = DSL.get_entities(dsl, [:bridge])

    cond do
      mappings != [] and config != %{} ->
        {:error, :use_bridge_block_or_config}

      config != %{} ->
        {:ok, config}

      true ->
        {:ok, %{mappings: Enum.map(mappings, &Map.take(&1, [:name, :external_room, :room, :direction]))}}
    end
  end

  @impl Jido.Agent.Extension
  def normalize(data) do
    mappings = Map.get(data, :mappings, [])

    valid =
      is_list(mappings) and mappings != [] and Enum.all?(mappings, &valid_mapping?/1) and
        unique?(mappings, & &1.name) and unique?(mappings, & &1.external_room) and
        mappings |> Enum.filter(&outbound?/1) |> unique?(&room_key(&1.room))

    runtime =
      Enum.all?(
        [
          {:runtime, &valid_module?/1},
          {:storage, &valid_storage?/1},
          {:account_id, &valid_id?/1},
          {:account_ref, &valid_ref?/1},
          {:client_id, &valid_id?/1},
          {:client_source, &valid_id?/1},
          {:provider_work_limit, &positive_integer?/1},
          {:provider_queue_limit, &positive_integer?/1}
        ],
        fn {key, validator} -> not Map.has_key?(data, key) or validator.(data[key]) end
      )

    if valid and runtime, do: {:ok, data}, else: {:error, :invalid_bridge_config}
  end

  @impl Jido.Agent.Extension
  def verify(data, definition) do
    providers = Enum.map(definition.extensions, & &1.provider)

    cond do
      Jido.Chat.Plugin not in providers -> {:error, :bridge_requires_chat_plugin}
      not required_routes?(data.mappings, definition.routes) -> {:error, :bridge_routes_required}
      true -> :ok
    end
  end

  @impl Jido.Plugin
  def directives(_opts), do: [RelayInbound, RelayOutbound, CompleteOutbound]

  @impl Jido.Plugin
  def prepare(input, opts) do
    signal = input.signal

    cond do
      signal.type == Jido.Chat.Signal.MessageReceived.type() ->
        {:ok, %{kind: :inbound, mappings: inbound_mappings(opts, signal.data["room_id"])}}

      signal.type == RoomSignal.Message.type() ->
        {:ok, %{kind: :outbound, mappings: outbound_mappings(opts, signal.data["room"])}}

      signal.type == Jido.Chat.SendMessage.Completed.type() ->
        {:ok, %{kind: :result, outcome: :completed, request_id: signal.data["request_id"]}}

      signal.type == Jido.Chat.SendMessage.Failed.type() ->
        {:ok, %{kind: :result, outcome: :failed, request_id: signal.data["request_id"]}}

      true ->
        {:ok, nil}
    end
  end

  @impl Jido.Plugin
  def admit(_runtime, %{prepared_input: nil}, _opts), do: {:ok, nil}

  def admit(runtime, input, _opts) do
    data = runtime_data(runtime)

    case input.prepared_input do
      %{kind: :inbound, mappings: []} ->
        {:error, :bridge_mapping_not_found}

      %{kind: :inbound, mappings: [mapping]} ->
        admit_inbound(input, data, runtime_mapping(data, mapping))

      %{kind: :outbound, mappings: []} ->
        {:error, :bridge_mapping_not_found}

      %{kind: :outbound, mappings: mappings} ->
        admit_outbound(input, data, Enum.map(mappings, &runtime_mapping(data, &1)))

      %{kind: :result, request_id: request_id} = prepared ->
        with true <- input.signal.source == data.client_source,
             {:ok, %{account_id: account_id, kind: :outbound}} <-
               Worker.get_work(data.worker, request_id),
             true <- account_id == data.account_id do
          {:ok, Map.merge(data, prepared)}
        else
          _ -> {:error, :invalid_bridge_result}
        end
    end
  end

  @impl Jido.Plugin
  def child_spec(init) do
    data = runtime_options(init)

    clients =
      data.mappings
      |> Enum.filter(&outbound?/1)
      |> Enum.map(fn mapping ->
        options = [
          bus: Room.bus_name(mapping.room),
          path: RoomSignal.Message.type(),
          durable: durable_id(data, mapping)
        ]

        spec = Jido.Plugin.Bus.Client.child_spec(%{init | options: options})
        Supervisor.child_spec(spec, id: {:bridge_mapping, mapping.name})
      end)

    worker = Supervisor.child_spec({Worker, data}, id: Worker)

    %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [[worker | clients], [strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  @impl Jido.Plugin
  def await_ready(runtime, opts) do
    runtime
    |> Supervisor.which_children()
    |> Enum.reject(&(elem(&1, 0) == Worker))
    |> Enum.reduce_while(:ok, fn {_id, child, _type, _modules}, :ok ->
      case Jido.Plugin.Bus.Client.await_ready(child, opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @impl Jido.Plugin
  def dispatch(runtime, %RelayInbound{work: work}, _context, _opts),
    do: Worker.enqueue(worker(runtime), work)

  def dispatch(runtime, %RelayOutbound{work: work}, _context, _opts),
    do: Worker.enqueue(worker(runtime), work)

  def dispatch(runtime, %CompleteOutbound{} = completion, _context, _opts) do
    Worker.finish(
      worker(runtime),
      completion.request_id,
      completion.outcome,
      completion.result
    )
  end

  defp admit_inbound(input, data, mapping) do
    sender = input.signal.data["sender"]

    cond do
      input.signal.source != data.client_source ->
        {:error, :bridge_client_mismatch}

      sender["is_self"] == true ->
        {:ok, Map.merge(data, %{mapping: mapping, ignore: true})}

      true ->
        with :ok <- member?(data, mapping.room),
             {:ok, reply} <- local_link(data, mapping, input.signal.data["reply_to_id"]),
             {:ok, thread} <- local_link(data, mapping, input.signal.data["thread_id"]) do
          {:ok,
           Map.merge(data, %{
             mapping: mapping,
             ignore: false,
             reply_to_local: if(reply, do: reply.local_message_id),
             thread_local: if(thread, do: thread.local_message_id)
           })}
        end
    end
  end

  defp admit_outbound(input, data, mappings) do
    with {:ok, agent, _directives} <-
           Jido.call(
             data.jido,
             input.signal.data["room"],
             RoomSignal.CheckMember.new!(%{"member" => data.account_ref}),
             context: %{actor: data.account_ref}
           ),
         true <- data.account_ref in agent.state.room.members,
         true <-
           Enum.any?(
             agent.state.room.messages,
             &(&1.id == input.signal.id and &1.data == input.signal.data)
           ),
         {:ok, reply_links} <-
           outbound_replies(data, mappings, get_in(input.signal.data, ["message", "reply_to_id"])) do
      {:ok, Map.merge(data, %{mappings: mappings, reply_links: reply_links})}
    else
      _ -> {:error, :not_member_or_retained_message}
    end
  end

  defp member?(data, room) do
    case Jido.call(
           data.jido,
           room,
           RoomSignal.CheckMember.new!(%{"member" => data.account_ref}),
           context: %{actor: data.account_ref}
         ) do
      {:ok, agent, _directives} ->
        if data.account_ref in agent.state.room.members, do: :ok, else: {:error, :not_member}

      _error ->
        {:error, :not_member}
    end
  end

  defp local_link(_data, _mapping, external_id) when external_id in [nil, ""],
    do: {:ok, nil}

  defp local_link(data, mapping, external_id) do
    links(data, :link_for_external, [data.account_id, mapping.external_room, external_id])
  end

  defp outbound_replies(_data, mappings, local_id) when local_id in [nil, ""],
    do: {:ok, Map.new(mappings, &{&1.name, nil})}

  defp outbound_replies(data, mappings, local_id) do
    with {:ok, link} <- links(data, :link_for_local, [data.account_id, local_id]) do
      {:ok,
       Map.new(mappings, fn mapping ->
         external =
           if link && link.external_room_id == mapping.external_room,
             do: link.external_message_id

         {mapping.name, external}
       end)}
    end
  end

  defp runtime_options(init) do
    mappings =
      Enum.map(init.options[:mappings], fn mapping ->
        Map.put(mapping, :room, room_ref(init, mapping.room))
      end)

    %{
      runtime: init.options[:runtime],
      storage: init.options[:storage],
      account_id: init.options[:account_id],
      account_ref: init.options[:account_ref],
      client_id: init.options[:client_id],
      client_source: init.options[:client_source],
      jido: init.jido,
      mappings: mappings,
      limit: init.options[:provider_work_limit],
      queue_limit: init.options[:provider_queue_limit]
    }
  end

  defp runtime_data(runtime) do
    server = worker(runtime)
    Worker.data(server) |> Map.put(:worker, server)
  end

  defp worker(runtime) do
    {Worker, server, _, _} =
      Enum.find(Supervisor.which_children(runtime), &(elem(&1, 0) == Worker))

    server
  end

  defp runtime_mapping(data, mapping), do: Enum.find(data.mappings, &(&1.name == mapping.name))

  defp room_ref(init, %Jido.Agent.Ref{namespace: namespace} = room) do
    if namespace == Jido.namespace(init.jido),
      do: room,
      else: raise(ArgumentError, "bridge room must use the account Jido namespace")
  end

  defp room_ref(init, id) do
    {:ok, room} = Jido.agent_ref(init.jido, id, partition: init.partition)
    room
  end

  defp durable_id(data, mapping) do
    raw = :erlang.term_to_binary({data.runtime, data.account_id, mapping.name, mapping.room})
    "jido.chat.bridge/" <> Base.url_encode64(:crypto.hash(:sha256, raw), padding: false)
  end

  defp inbound_mappings(opts, external_room) do
    Enum.filter(opts[:mappings], &(&1.external_room == external_room and inbound?(&1)))
  end

  defp outbound_mappings(opts, room) do
    Enum.filter(opts[:mappings], fn mapping ->
      outbound?(mapping) and same_room?(mapping.room, room)
    end)
  end

  defp same_room?(%Jido.Agent.Ref{} = left, %Jido.Agent.Ref{} = right), do: left == right
  defp same_room?(id, %Jido.Agent.Ref{id: id}) when is_binary(id), do: true
  defp same_room?(_left, _right), do: false

  defp inbound?(mapping), do: mapping.direction in [:inbound, :both]
  defp outbound?(mapping), do: mapping.direction in [:outbound, :both]

  defp valid_mapping?(mapping) do
    is_map(mapping) and is_atom(mapping.name) and not is_nil(mapping.name) and
      valid_id?(mapping.external_room) and valid_room?(mapping.room) and
      mapping.direction in [:inbound, :outbound, :both]
  end

  defp valid_room?(room) when is_binary(room), do: room != ""
  defp valid_room?(%Jido.Agent.Ref{} = room), do: valid_ref?(room)
  defp valid_room?(_room), do: false

  defp valid_module?(value), do: is_atom(value) and value not in [nil, true, false]
  defp valid_storage?({adapter, _resource}), do: valid_module?(adapter)
  defp valid_storage?(_value), do: false
  defp valid_id?(value), do: is_binary(value) and value != ""
  defp valid_ref?(value), do: match?({:ok, _}, Jido.Agent.Ref.validate(value))
  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp unique?(items, fun) do
    values = Enum.map(items, fun)
    length(values) == length(Enum.uniq(values))
  end

  defp room_key(%Jido.Agent.Ref{} = room), do: {room.namespace, room.partition, room.id}
  defp room_key(room), do: room

  defp required_routes?(mappings, routes) do
    paths = MapSet.new(routes, & &1.path)
    inbound = Enum.any?(mappings, &inbound?/1)
    outbound = Enum.any?(mappings, &outbound?/1)

    (not inbound or MapSet.member?(paths, Jido.Chat.Signal.MessageReceived.type())) and
      (not outbound or
         Enum.all?(
           [
             RoomSignal.Message.type(),
             Jido.Chat.Signal.SendMessage.type(),
             Jido.Chat.SendMessage.Completed.type(),
             Jido.Chat.SendMessage.Failed.type()
           ],
           &MapSet.member?(paths, &1)
         ))
  end

  defp links(data, function, args) do
    storage_call(data.storage, Links, function, args)
  end

  defp storage(runtime) do
    cond do
      not is_atom(runtime) or not function_exported?(runtime, :storage, 0) ->
        {:error, :invalid_runtime}

      is_nil(runtime.storage()) ->
        {:error, :bridge_storage_required}

      true ->
        {:ok, runtime.storage()}
    end
  end

  defp storage_call({adapter, resource}, behaviour, function, args) do
    with :ok <- Storage.validate({adapter, resource}, [behaviour]),
         true <- function_exported?(adapter, function, length(args) + 1) do
      apply(adapter, function, [resource | args])
    else
      _ -> {:error, :storage_capability_required}
    end
  end
end
