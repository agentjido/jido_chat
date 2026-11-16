defmodule Jido.Chat.Runtime do
  @moduledoc """
  Optional stateful chat services built on a host-owned Jido instance.

  Runtime owns rooms, participants, provider account activation, bridges,
  bounded provider work, and small storage capability contracts. Starting the
  `:jido_chat` application does not start Runtime.
  """

  use Boundary,
    deps: [Jido.Chat],
    exports: [
      Supervisor,
      {Room, []},
      Participant,
      Connection,
      Bridge,
      {Actions, []},
      {Signal, []},
      {Storage, []}
    ]

  @doc "Defines one process-free Runtime facade over a host-owned Jido instance."
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      opts =
        Keyword.validate!(opts, [
          :jido,
          :storage,
          :room_definitions,
          :provider_work_limit,
          :provider_queue_limit,
          :provider_work_lease_ms
        ])

      @chat_runtime_jido Keyword.fetch!(opts, :jido)
      @chat_runtime_storage Keyword.get(opts, :storage)
      room_definitions = Keyword.get(opts, :room_definitions, %{})

      unless is_map(room_definitions) do
        raise ArgumentError, "room_definitions must be a map"
      end

      @chat_runtime_room_definitions room_definitions
      @chat_runtime_provider_work_limit Keyword.get(opts, :provider_work_limit, 4)
      @chat_runtime_provider_queue_limit Keyword.get(opts, :provider_queue_limit, 1_000)
      @chat_runtime_provider_work_lease_ms Keyword.get(opts, :provider_work_lease_ms, 60_000)

      unless is_atom(@chat_runtime_jido) and @chat_runtime_jido not in [nil, true, false] do
        raise ArgumentError, "jido must be a named host Jido instance"
      end

      unless is_nil(@chat_runtime_storage) or
               match?({adapter, _resource} when is_atom(adapter), @chat_runtime_storage) do
        raise ArgumentError, "storage must be {adapter, resource}"
      end

      unless Enum.all?(@chat_runtime_room_definitions, fn {key, definition} ->
               is_binary(key) and byte_size(key) in 1..256 and is_atom(definition) and
                 definition not in [nil, true, false]
             end) do
        raise ArgumentError, "room_definitions must map nonempty string keys to Room Agent modules"
      end

      unless is_integer(@chat_runtime_provider_work_limit) and
               @chat_runtime_provider_work_limit > 0 do
        raise ArgumentError, "provider_work_limit must be a positive integer"
      end

      unless is_integer(@chat_runtime_provider_queue_limit) and
               @chat_runtime_provider_queue_limit > 0 do
        raise ArgumentError, "provider_queue_limit must be a positive integer"
      end

      unless is_integer(@chat_runtime_provider_work_lease_ms) and
               @chat_runtime_provider_work_lease_ms > 0 do
        raise ArgumentError, "provider_work_lease_ms must be a positive integer"
      end

      @doc "Returns the required host-owned Jido instance."
      @spec jido() :: atom()
      def jido, do: @chat_runtime_jido

      @doc "Returns the selected Runtime storage resource, when configured."
      @spec storage() :: Jido.Chat.Runtime.Storage.selection() | nil
      def storage, do: @chat_runtime_storage

      @doc "Resolves one durable Room definition key through trusted host code."
      @spec room_definition(String.t()) :: {:ok, module()} | {:error, :unknown_room_definition}
      def room_definition(key) when is_binary(key) do
        case Enum.find(@chat_runtime_room_definitions, fn {known, _definition} -> known == key end) do
          {_known, definition} -> {:ok, definition}
          nil -> {:error, :unknown_room_definition}
        end
      end

      def room_definition(_key), do: {:error, :unknown_room_definition}

      @doc false
      def room_definitions, do: @chat_runtime_room_definitions

      @doc false
      def provider_work_limits do
        {@chat_runtime_provider_work_limit, @chat_runtime_provider_queue_limit}
      end

      @doc false
      def provider_work_lease_ms, do: @chat_runtime_provider_work_lease_ms

      @doc "Returns a child specification for the optional managed Runtime tree."
      @spec child_spec(keyword()) :: Supervisor.child_spec()
      def child_spec(opts \\ []) do
        Jido.Chat.Runtime.Supervisor.child_spec({__MODULE__, opts})
      end

      @doc "Starts the optional managed Runtime tree."
      @spec start_link(keyword()) :: Supervisor.on_start()
      def start_link(opts \\ []) do
        Jido.Chat.Runtime.Supervisor.start_link(__MODULE__, opts)
      end

      @doc "Returns status for the managed Runtime tree."
      def runtime_status, do: Jido.Chat.Runtime.Supervisor.status(__MODULE__)

      @doc "Reconciles all managed Runtime declarations now."
      def reconcile_runtime, do: Jido.Chat.Runtime.Supervisor.reconcile(__MODULE__)

      @doc "Lists all managed Room Agent declarations."
      def list_managed_rooms,
        do: Jido.Chat.Runtime.Supervisor.list_rooms(__MODULE__)

      @doc "Returns status for one managed Room declaration."
      def room_runtime_status(id),
        do: Jido.Chat.Runtime.Supervisor.room_status(__MODULE__, id)

      @doc "Starts one managed Room declaration."
      def start_managed_room(id),
        do: Jido.Chat.Runtime.Supervisor.start_room(__MODULE__, id)

      @doc "Stops one managed Room declaration."
      def stop_managed_room(id),
        do: Jido.Chat.Runtime.Supervisor.stop_room(__MODULE__, id)

      @doc "Restarts one managed Room declaration."
      def restart_managed_room(id),
        do: Jido.Chat.Runtime.Supervisor.restart_room(__MODULE__, id)

      @doc "Creates one durable Room record."
      @spec create_room(map()) ::
              {:ok, Jido.Chat.Runtime.Room.Record.t()} | {:error, term()}
      def create_room(attrs),
        do: Jido.Chat.Runtime.Room.Records.create(__MODULE__, attrs)

      @doc "Returns one durable Room record."
      @spec get_room(String.t()) ::
              {:ok, Jido.Chat.Runtime.Room.Record.t()} | {:error, term()}
      def get_room(id),
        do: Jido.Chat.Runtime.Room.Records.get(__MODULE__, id)

      @doc "Lists durable Room records with bounded query options."
      @spec list_rooms(keyword()) ::
              {:ok, [Jido.Chat.Runtime.Room.Record.t()]} | {:error, term()}
      def list_rooms(opts \\ []),
        do: Jido.Chat.Runtime.Room.Records.list(__MODULE__, opts)

      @doc "Updates the name or metadata of one durable Room record."
      @spec update_room(String.t(), map()) ::
              {:ok, Jido.Chat.Runtime.Room.Record.t()} | {:error, term()}
      def update_room(id, attrs),
        do: Jido.Chat.Runtime.Room.Records.update(__MODULE__, id, attrs)

      @doc "Updates one durable Room record at the expected revision."
      @spec update_room(String.t(), pos_integer(), map()) ::
              {:ok, Jido.Chat.Runtime.Room.Record.t()} | {:error, term()}
      def update_room(id, expected_revision, attrs),
        do: Jido.Chat.Runtime.Room.Records.update(__MODULE__, id, expected_revision, attrs)

      @doc "Deletes one durable Room record at its current revision."
      @spec delete_room(String.t()) :: :ok | {:error, term()}
      def delete_room(id),
        do: Jido.Chat.Runtime.Room.Records.delete(__MODULE__, id)

      @doc "Deletes one durable Room record at the expected revision."
      @spec delete_room(String.t(), pos_integer()) :: :ok | {:error, term()}
      def delete_room(id, expected_revision),
        do: Jido.Chat.Runtime.Room.Records.delete(__MODULE__, id, expected_revision)

      @doc "Atomically creates one Room record and durable managed declaration."
      def provision_room(definition_key, attrs),
        do: Jido.Chat.Runtime.Room.Provisioning.provision(__MODULE__, definition_key, attrs)

      @doc "Stops and removes one durable managed declaration without deleting Room data."
      def deprovision_room(id),
        do: Jido.Chat.Runtime.Room.Provisioning.deprovision(__MODULE__, id)

      @doc "Lists durable memberships for one Room."
      def list_room_memberships(id, opts \\ []),
        do: Jido.Chat.Runtime.Room.Durable.list_memberships(__MODULE__, id, opts)

      @doc "Returns one durable membership for a Room member."
      def get_room_membership(id, member),
        do: Jido.Chat.Runtime.Room.Durable.get_membership(__MODULE__, id, member)

      @doc "Lists immutable durable Room message history."
      def list_room_history(id, opts \\ []),
        do: Jido.Chat.Runtime.Room.Durable.list_history(__MODULE__, id, opts)

      @doc "Returns one durable Room message history record."
      def get_room_history(id, message_id),
        do: Jido.Chat.Runtime.Room.Durable.get_message(__MODULE__, id, message_id)

      @doc "Lists all managed provider account declarations."
      def list_managed_connections,
        do: Jido.Chat.Runtime.Supervisor.list_connections(__MODULE__)

      @doc "Returns status for one managed provider account declaration."
      def managed_connection_status(id),
        do: Jido.Chat.Runtime.Supervisor.connection_status(__MODULE__, id)

      @doc "Starts one managed provider account declaration."
      def start_managed_connection(id),
        do: Jido.Chat.Runtime.Supervisor.start_connection(__MODULE__, id)

      @doc "Stops one managed provider account declaration."
      def stop_managed_connection(id),
        do: Jido.Chat.Runtime.Supervisor.stop_connection(__MODULE__, id)

      @doc "Restarts one managed provider account declaration."
      def restart_managed_connection(id),
        do: Jido.Chat.Runtime.Supervisor.restart_connection(__MODULE__, id)

      @doc "Returns the stable Agent Address for one provider account."
      def connection_ref(account_id),
        do: Jido.Chat.Runtime.Connection.ref(__MODULE__, account_id)

      @doc "Starts one provider account through the host Jido instance."
      def start_connection(account_id, definition),
        do: Jido.Chat.Runtime.Connection.start(__MODULE__, account_id, definition)

      @doc "Stops one provider account through the host Jido instance."
      def stop_connection(account_id),
        do: Jido.Chat.Runtime.Connection.stop(__MODULE__, account_id)

      @doc "Returns safe local status for one provider account."
      def connection_status(account_id),
        do: Jido.Chat.Runtime.Connection.status(__MODULE__, account_id)

      @doc "Returns stored Bridge provider-work status for one account."
      def bridge_status(account_id),
        do: Jido.Chat.Runtime.Bridge.status(__MODULE__, account_id)

      @doc "Schedules pending Bridge work for one active account."
      def recover_bridge(account_id),
        do: Jido.Chat.Runtime.Bridge.recover(__MODULE__, account_id)

      @doc "Returns the Bridge link for one local message."
      def bridge_link(account_id, local_message_id),
        do: Jido.Chat.Runtime.Bridge.link(__MODULE__, account_id, local_message_id)
    end
  end
end
